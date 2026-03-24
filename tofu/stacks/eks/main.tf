################################################################################
# EKS Stack - Harness Entities for Kubernetes Deployments
#
# This stack provisions Harness entities for deploying to an EXISTING EKS cluster.
# It does NOT create the EKS cluster itself - use shared-infra/eks-cluster for that.
#
# Use Cases:
#   #1 - SE Sandbox: Deploy to shared EKS cluster in same Harness account
#   #2 - POV-in-a-Box: Deploy to shared EKS cluster, customer Harness account
#
# Prerequisites:
#   - Existing EKS cluster (from shared-infra or external)
#   - Existing delegate with IRSA role (from shared-infra)
#   - Harness org/project (can be created by this stack or pre-existing)
################################################################################

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    harness = {
      source  = "harness/harness"
      version = "~> 0.30"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.25"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

################################################################################
# Data Sources - Existing EKS Cluster
################################################################################

data "aws_eks_cluster" "cluster" {
  name = var.eks_cluster_name
}

data "aws_eks_cluster_auth" "cluster" {
  name = var.eks_cluster_name
}

################################################################################
# Providers
################################################################################

provider "aws" {
  region = var.aws_region
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

provider "harness" {
  endpoint         = var.harness_endpoint
  account_id       = var.harness_account_id
  platform_api_key = var.harness_api_key
}

################################################################################
# Local Variables
################################################################################

locals {
  name_prefix       = "harness-demo-${var.owner}"
  delegate_selector = "delegate-${var.owner}"
  k8s_namespace     = "harness-demo-${var.owner}"

  common_tags = {
    Project     = "harness-demo"
    Environment = var.environment
    ManagedBy   = "tofu"
    Owner       = var.owner
    Stack       = "eks"
  }
}

################################################################################
# Harness Organization and Project (optional creation)
################################################################################

module "harness_org_project" {
  source = "../../modules/harness-org-project"

  create_organization      = var.create_harness_org
  existing_org_id          = var.harness_org_id
  organization_id          = var.new_harness_org_id
  organization_name        = var.new_harness_org_name
  organization_description = "Reference architecture for Harness CI/CD demonstrations - ${var.owner}"

  create_project      = var.create_harness_project
  existing_project_id = var.harness_project_id
  project_id          = var.new_harness_project_id != "" ? var.new_harness_project_id : "${var.owner}_demo"
  project_name        = var.new_harness_project_name != "" ? var.new_harness_project_name : "${title(var.owner)} Demo"
  project_description = "Demo project for ${var.owner}"

  tags = ["tofu-managed", var.owner, "eks"]
}

locals {
  resolved_org_id     = module.harness_org_project.org_id
  resolved_project_id = module.harness_org_project.project_id
}

################################################################################
# Harness Code Repository (imports from GitHub when use_harness_code=true)
# This is managed by Terraform, so destroy will clean up the repo
################################################################################

module "harness_code_repo" {
  source = "../../modules/harness-code-repo"
  count  = var.use_harness_code ? 1 : 0

  harness_account_id = var.harness_account_id
  org_id             = local.resolved_org_id
  project_id         = local.resolved_project_id

  repo_identifier  = "${var.owner}-demo-app"
  repo_description = "Demo app for ${var.owner} POV - imported from GitHub"
  default_branch   = "main"

  # Import from GitHub (auth only needed for private repos)
  import_from_scm = true
  source_provider = "github"
  source_host     = "https://github.com"
  source_repo     = var.github_repo_name
  source_username = "x-access-token"
  source_password = var.github_repo_is_public ? "" : var.github_pat

  depends_on = [module.harness_org_project]
}

################################################################################
# Kubernetes Namespace
################################################################################

resource "kubernetes_namespace" "app" {
  metadata {
    name = local.k8s_namespace
    labels = {
      "app.kubernetes.io/managed-by" = "tofu"
      "harness.io/owner"             = var.owner
    }
  }
}

################################################################################
# Harness Connectors
################################################################################

module "harness_connectors" {
  source = "../../modules/harness-connectors"

  environment_name   = var.environment
  harness_org_id     = local.resolved_org_id
  harness_project_id = local.resolved_project_id
  delegate_selectors = [local.delegate_selector]

  # Kubernetes Connector
  create_k8s_connector = true
  k8s_connector_id     = "${var.owner}_k8s_reference_architecture"
  k8s_connector_name   = "${title(var.owner)} K8s Reference Architecture"

  # AWS Connector (for ECR if needed)
  create_aws_connector      = var.create_aws_connector
  aws_connector_id          = "${var.owner}_aws_reference_architecture"
  aws_connector_name        = "${title(var.owner)} AWS Reference Architecture"
  aws_connector_description = "AWS connector for ${title(var.owner)} EKS stack"
  connector_tags            = ["tofu-managed:true", "owner:${var.owner}", "stack:eks"]
  aws_auth_type             = var.aws_auth_type
  aws_region                = var.aws_region

  # GitHub Connector
  create_github_connector = var.github_token_ref != ""
  github_connector_id     = "${var.owner}_github_reference_architecture"
  github_connector_name   = "${title(var.owner)} GitHub Reference Architecture"
  github_url              = var.github_url
  github_username         = var.github_username
  github_token_ref        = var.github_token_ref

  # Docker connector disabled - use HAR or ECR via AWS connector
  create_docker_connector = false

  depends_on = [module.harness_org_project]
}

################################################################################
# Harness Artifact Registry (HAR)
################################################################################

module "har" {
  source = "../../modules/harness-artifact-registry"
  count  = var.artifact_registry_type == "har" ? 1 : 0

  account_id = var.harness_account_id
  org_id     = local.resolved_org_id
  project_id = local.resolved_project_id

  registry_id          = "har-${var.owner}"
  registry_description = "Docker registry for ${var.owner} demo app"

  create_dockerhub_upstream     = var.create_dockerhub_upstream
  dockerhub_upstream_id         = "${var.owner}-dockerhub-proxy"
  dockerhub_username            = var.dockerhub_username
  dockerhub_password_secret_ref = var.dockerhub_password_secret_ref
  dockerhub_secret_space_path   = var.harness_account_id

  depends_on = [module.harness_org_project]
}

################################################################################
# HAR Pull Secret for Kubernetes
################################################################################

locals {
  har_email       = var.harness_api_key_email
  har_auth_string = base64encode("${local.har_email}:${var.harness_api_key}")
  har_dockercfg = jsonencode({
    "pkg.harness.io" = {
      username = local.har_email
      password = var.harness_api_key
      email    = local.har_email
      auth     = local.har_auth_string
    }
  })
}

resource "kubernetes_secret" "har_pull_secret" {
  count = var.artifact_registry_type == "har" ? 1 : 0

  metadata {
    name      = "${var.owner}demoapp-dockercfg"
    namespace = local.k8s_namespace
    labels = {
      "app.kubernetes.io/managed-by" = "tofu"
      "harness.io/component"         = "har-pull-secret"
      "owner"                        = var.owner
    }
  }

  type = "kubernetes.io/dockercfg"

  data = {
    ".dockercfg" = local.har_dockercfg
  }

  depends_on = [kubernetes_namespace.app]
}

################################################################################
# Harness Service
################################################################################

module "harness_service" {
  source = "../../modules/harness-service"

  service_id          = "${var.owner}_demo_app"
  service_name        = "${title(var.owner)} Demo App"
  service_description = "Demo application for ${var.owner} (EKS)"
  org_id              = local.resolved_org_id
  project_id          = local.resolved_project_id

  deployment_type = "Kubernetes"

  # Manifest configuration
  manifest_type       = "K8sManifest"
  manifest_store_type = var.use_harness_code ? "HarnessCode" : "Github"
  git_connector_ref   = var.use_harness_code ? "" : "${var.owner}_github_reference_architecture"
  git_repo_name       = var.use_harness_code ? "" : var.github_repo_name
  git_branch          = var.git_branch
  manifest_paths      = var.manifest_paths
  harness_code_repo_name = var.use_harness_code ? "${var.owner}-demo-app" : ""

  # Artifact configuration - HAR
  artifact_registry_type = var.artifact_registry_type
  har_registry_ref       = var.artifact_registry_type == "har" && length(module.har) > 0 ? module.har[0].registry_id : ""
  har_image_path         = var.artifact_registry_type == "har" ? "${var.owner}demoapp" : ""

  # ECR configuration (if using ECR)
  artifact_connector_ref = var.artifact_registry_type == "ecr" ? "${var.owner}_aws_reference_architecture" : ""
  ecr_image_path         = var.artifact_registry_type == "ecr" ? "harness-demo-app-${var.owner}" : ""
  aws_region             = var.aws_region

  tags = ["tofu-managed", var.owner, "eks"]

  service_variables = [
    {
      name  = "ingressHost"
      type  = "String"
      value = "${var.owner}.harness-demo.dev"
    },
    {
      name  = "ingressStageHost"
      type  = "String"
      value = "${var.owner}-stage.harness-demo.dev"
    },
    {
      name  = "certArn"
      type  = "String"
      value = var.acm_cert_arn
    }
  ]

  depends_on = [module.harness_connectors, module.har]
}

################################################################################
# Harness Environment and Infrastructure
################################################################################

module "harness_environment_dev" {
  source = "../../modules/harness-environment"

  environment_id          = "${var.owner}_dev"
  environment_name        = "${title(var.owner)} Dev"
  environment_description = "Development environment for ${var.owner}"
  org_id                  = local.resolved_org_id
  project_id              = local.resolved_project_id
  environment_type        = "PreProduction"

  create_k8s_infrastructure = true
  create_k8s_namespace      = false  # Already created above
  k8s_infra_id              = "${var.owner}_k8s_dev"
  k8s_infra_name            = "${title(var.owner)} K8s Dev"
  k8s_connector_ref         = "${var.owner}_k8s_reference_architecture"
  k8s_namespace             = local.k8s_namespace

  tags = ["tofu-managed", var.owner, "eks"]

  depends_on = [module.harness_connectors]
}

################################################################################
# Harness Pipelines
################################################################################

module "harness_pipelines" {
  source = "../../modules/harness-pipeline"

  org_id             = local.resolved_org_id
  project_id         = local.resolved_project_id
  service_ref        = "${var.owner}_demo_app"
  environment_ref    = "${var.owner}_dev"
  environment_name   = "Dev"
  infrastructure_ref = "${var.owner}_k8s_dev"

  # Strategy Choice pipeline
  create_strategy_pipeline      = var.create_strategy_pipeline
  strategy_pipeline_id          = "${var.owner}_k8s_strategy_deploy"
  strategy_pipeline_name        = "${title(var.owner)} K8s Deploy with Strategy Choice"
  strategy_pipeline_description = "Single pipeline with runtime strategy selection - Blue/Green, Canary, or Rolling"

  # CI Build pipeline
  # Only create CI pipeline if we have a valid codebase source (Harness Code OR GitHub connector)
  create_ci_pipeline      = var.create_ci_pipeline && (var.use_harness_code || var.github_token_ref != "" || var.github_connector_ref != "")
  ci_pipeline_id          = "${var.owner}_ci_build"
  ci_pipeline_name        = "${title(var.owner)} CI Build"
  ci_pipeline_description = "Builds Docker image and pushes to Harness Artifact Registry"
  git_connector_ref       = var.github_token_ref != "" ? "${var.owner}_github_reference_architecture" : var.github_connector_ref
  git_repo_name           = var.github_repo_name
  har_registry_ref        = var.artifact_registry_type == "har" ? "har-${var.owner}" : ""
  har_upstream_proxy_ref  = var.artifact_registry_type == "har" && var.create_dockerhub_upstream ? "${var.owner}-dockerhub-proxy" : ""
  har_image_name          = "${var.owner}demoapp"

  use_harness_code       = var.use_harness_code
  harness_code_repo_name = var.use_harness_code ? "${var.owner}-demo-app" : ""
  harness_account_id     = var.harness_account_id
  harness_org_id         = local.resolved_org_id
  harness_project_id     = local.resolved_project_id
  harness_api_key        = var.harness_api_key

  delegate_selector = local.delegate_selector
  pipeline_tags     = ["tofu-managed", var.owner, "eks"]

  # Disable other pipeline types
  create_canary_pipeline     = false
  create_blue_green_pipeline = false
  create_asg_strategy_pipeline = false
  create_asg_ci_pipeline       = false

  # Pipelines must be destroyed BEFORE service/environment to avoid reference errors
  # CI pipeline with Harness Code must wait for the repo to be created
  depends_on = [module.harness_service, module.harness_environment_dev, module.harness_code_repo]
}

################################################################################
# Outputs
################################################################################

output "org_id" {
  description = "Harness organization ID"
  value       = local.resolved_org_id
}

output "project_id" {
  description = "Harness project ID"
  value       = local.resolved_project_id
}

output "service_id" {
  description = "Harness service ID"
  value       = module.harness_service.service_id
}

output "environment_id" {
  description = "Harness environment ID"
  value       = module.harness_environment_dev.environment_id
}

output "k8s_namespace" {
  description = "Kubernetes namespace for the application"
  value       = local.k8s_namespace
}

output "app_url" {
  description = "Application URL"
  value       = "https://${var.owner}.harness-demo.dev"
}
