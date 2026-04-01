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
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
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

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.cluster.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
}

################################################################################
# Local Variables
################################################################################

locals {
  owner_title                = title(var.owner)
  name_prefix                = "harness-demo-${var.owner}"
  delegate_selector          = "delegate-${var.owner}"
  k8s_namespace              = "harness-demo-${var.owner}"
  repo_name                  = "${var.owner}-demo-app"
  service_id                 = "${var.owner}_demo_app"
  service_name               = "${local.owner_title} Demo App"
  dev_environment_id         = "${var.owner}_dev"
  dev_environment_name       = "${local.owner_title} Dev"
  k8s_infra_id               = "${var.owner}_k8s_dev"
  k8s_infra_name             = "${local.owner_title} K8s Dev"
  k8s_connector_id           = "${var.owner}_k8s_reference_architecture"
  k8s_connector_name         = "${local.owner_title} K8s Reference Architecture"
  aws_connector_id           = "${var.owner}_aws_reference_architecture"
  aws_connector_name         = "${local.owner_title} AWS Reference Architecture"
  github_connector_id        = "${var.owner}_github_reference_architecture"
  github_connector_name      = "${local.owner_title} GitHub Reference Architecture"
  har_registry_id            = "har-${var.owner}"
  har_upstream_proxy_id      = "${var.owner}-dockerhub-proxy"
  har_image_name             = "${var.owner}demoapp"
  ecr_image_path             = "harness-demo-app-${var.owner}"
  app_host                   = "${var.owner}.harness-demo.dev"
  stage_host                 = "${var.owner}-stage.harness-demo.dev"
  harness_code_repo_name     = var.use_harness_code ? local.repo_name : ""
  has_code_source            = var.use_harness_code || var.github_token_ref != "" || var.github_connector_ref != ""
  pipeline_git_connector_ref = var.github_token_ref != "" ? local.github_connector_id : var.github_connector_ref

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

  repo_identifier  = local.repo_name
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
  k8s_connector_id     = local.k8s_connector_id
  k8s_connector_name   = local.k8s_connector_name

  # AWS Connector (for ECR if needed)
  create_aws_connector      = var.create_aws_connector
  aws_connector_id          = local.aws_connector_id
  aws_connector_name        = local.aws_connector_name
  aws_connector_description = "AWS connector for ${local.owner_title} EKS stack"
  connector_tags            = ["tofu-managed:true", "owner:${var.owner}", "stack:eks"]
  aws_auth_type             = var.aws_auth_type
  aws_region                = var.aws_region

  # GitHub Connector
  create_github_connector = var.github_token_ref != ""
  github_connector_id     = local.github_connector_id
  github_connector_name   = local.github_connector_name
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

  registry_id          = local.har_registry_id
  registry_description = "Docker registry for ${var.owner} demo app"

  create_dockerhub_upstream     = var.create_dockerhub_upstream
  dockerhub_upstream_id         = local.har_upstream_proxy_id
  dockerhub_username            = var.dockerhub_username
  dockerhub_password_secret_ref = var.dockerhub_password_secret_ref
  dockerhub_secret_space_path   = var.harness_account_id

  # API credentials for pre-create cleanup (handles orphaned registries)
  harness_endpoint = var.harness_endpoint
  harness_api_key  = var.harness_api_key

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

  service_id          = local.service_id
  service_name        = local.service_name
  service_description = "Demo application for ${var.owner} (EKS)"
  org_id              = local.resolved_org_id
  project_id          = local.resolved_project_id

  deployment_type = "Kubernetes"

  # Manifest configuration
  manifest_type          = "K8sManifest"
  manifest_store_type    = var.use_harness_code ? "HarnessCode" : "Github"
  git_connector_ref      = var.use_harness_code ? "" : local.github_connector_id
  git_repo_name          = var.use_harness_code ? "" : var.github_repo_name
  git_branch             = var.git_branch
  manifest_paths         = var.manifest_paths
  harness_code_repo_name = local.harness_code_repo_name

  # Artifact configuration - HAR
  artifact_registry_type = var.artifact_registry_type
  har_registry_ref       = var.artifact_registry_type == "har" && length(module.har) > 0 ? module.har[0].registry_id : ""
  har_image_path         = var.artifact_registry_type == "har" ? local.har_image_name : ""

  # ECR configuration (if using ECR)
  artifact_connector_ref = var.artifact_registry_type == "ecr" ? local.aws_connector_id : ""
  ecr_image_path         = var.artifact_registry_type == "ecr" ? local.ecr_image_path : ""
  aws_region             = var.aws_region

  tags = ["tofu-managed", var.owner, "eks"]

  service_variables = [
    {
      name  = "ingressHost"
      type  = "String"
      value = local.app_host
    },
    {
      name  = "ingressStageHost"
      type  = "String"
      value = local.stage_host
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

  environment_id          = local.dev_environment_id
  environment_name        = local.dev_environment_name
  environment_description = "Development environment for ${var.owner}"
  org_id                  = local.resolved_org_id
  project_id              = local.resolved_project_id
  environment_type        = "PreProduction"

  create_k8s_infrastructure = true
  create_k8s_namespace      = false # Already created above
  k8s_infra_id              = local.k8s_infra_id
  k8s_infra_name            = local.k8s_infra_name
  k8s_connector_ref         = local.k8s_connector_id
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
  service_ref        = local.service_id
  environment_ref    = local.dev_environment_id
  environment_name   = "Dev"
  infrastructure_ref = local.k8s_infra_id

  # Strategy Choice pipeline
  create_strategy_pipeline      = var.create_strategy_pipeline
  strategy_pipeline_id          = "${var.owner}_k8s_strategy_deploy"
  strategy_pipeline_name        = "${local.owner_title} K8s Deploy with Strategy Choice"
  strategy_pipeline_description = "Single pipeline with runtime strategy selection - Blue/Green, Canary, or Rolling"

  # CI Build pipeline
  # Only create CI pipeline if we have a valid codebase source (Harness Code OR GitHub connector)
  create_ci_pipeline      = var.create_ci_pipeline && local.has_code_source
  ci_pipeline_id          = "${var.owner}_ci_build"
  ci_pipeline_name        = "${local.owner_title} CI Build"
  ci_pipeline_description = "Builds Docker image and pushes to Harness Artifact Registry"
  git_connector_ref       = local.pipeline_git_connector_ref
  git_repo_name           = var.github_repo_name
  har_registry_ref        = var.artifact_registry_type == "har" ? local.har_registry_id : ""
  har_upstream_proxy_ref  = var.artifact_registry_type == "har" && var.create_dockerhub_upstream ? local.har_upstream_proxy_id : ""
  har_image_name          = local.har_image_name

  use_harness_code       = var.use_harness_code
  harness_code_repo_name = local.harness_code_repo_name
  harness_account_id     = var.harness_account_id
  harness_org_id         = local.resolved_org_id
  harness_project_id     = local.resolved_project_id
  harness_api_key        = var.harness_api_key

  delegate_selector = local.delegate_selector
  pipeline_tags     = ["tofu-managed", var.owner, "eks"]

  # Standard CI Gradle pipeline (with security scanning and supply chain)
  # Include owner prefix for multi-sandbox support in same project
  create_standard_ci_gradle        = coalesce(var.create_standard_ci_gradle, false) && local.has_code_source
  standard_ci_gradle_id            = "${var.owner}_standard_ci_gradle"
  standard_ci_gradle_name          = "${local.owner_title} Standard CI - Gradle"
  standard_ci_gradle_description   = "Enterprise CI pipeline: Gradle build, Test Intelligence, Security Scanning (SAST/SCA/Trivy), Supply Chain (SBOM/SLSA)"
  standard_ci_gradle_test_packages = var.standard_ci_gradle_test_packages
  har_base_image_registry          = var.artifact_registry_type == "har" ? "pkg.harness.io/${lower(var.harness_account_id)}/${local.har_registry_id}" : ""

  # Disable other pipeline types
  create_canary_pipeline       = false
  create_blue_green_pipeline   = false
  create_asg_strategy_pipeline = false
  create_asg_ci_pipeline       = false

  # Pipelines must be destroyed BEFORE service/environment to avoid reference errors
  # CI pipeline with Harness Code must wait for the repo to be created
  depends_on = [module.harness_service, module.harness_environment_dev, module.harness_code_repo]
}

################################################################################
# OPA Policies - CI/CD Governance
# Creates policies for CI standards, security, and quality gates
################################################################################

module "opa_policies" {
  source = "../../modules/harness-opa-policies"
  count  = var.create_opa_policies ? 1 : 0

  org_id     = local.resolved_org_id
  project_id = local.resolved_project_id

  # Policy creation flags
  create_ci_policies       = true
  create_security_policies = true
  create_quality_policies  = true

  # Policy set creation flags
  create_ci_policy_set       = true
  create_security_policy_set = true
  create_quality_policy_set  = true

  # Enforcement flags
  enforce_ci_policies       = var.enforce_ci_policies
  enforce_security_policies = var.enforce_security_policies
  enforce_quality_policies  = var.enforce_quality_policies

  depends_on = [module.harness_org_project]
}

################################################################################
# DNS Management - Wildcard CNAME for *.harness-demo.dev
# Automatically updates the wildcard DNS to point to the shared ALB
################################################################################

data "aws_route53_zone" "harness_demo" {
  count = var.manage_dns ? 1 : 0
  name  = "${var.dns_domain}."
}

# DNS management for EKS ingress ALB
# Creates individual DNS record: {owner}.harness-demo.dev → shared ALB
# This is consistent with ASG pattern: {owner}-asg.harness-demo.dev → dedicated ALB
#
# The shared ALB is created by AWS Load Balancer Controller when the first ingress
# in the "harness-demo" group is deployed. Its DNS name is passed via shared_alb_dns_name.
locals {
  # Create individual DNS record if manage_dns=true and shared_alb_dns_name is provided
  create_dns_record = var.manage_dns && var.shared_alb_dns_name != ""
}

# Individual DNS record for this sandbox: {owner}.harness-demo.dev → shared ALB
resource "aws_route53_record" "app" {
  count           = local.create_dns_record ? 1 : 0
  zone_id         = var.route53_hosted_zone_id != "" ? var.route53_hosted_zone_id : data.aws_route53_zone.harness_demo[0].zone_id
  name            = "${var.owner}.${var.dns_domain}"
  type            = "CNAME"
  ttl             = 60
  records         = [var.shared_alb_dns_name]
  allow_overwrite = true

  lifecycle {
    create_before_destroy = true
  }
}

# Stage environment DNS record: {owner}-stage.harness-demo.dev → shared ALB
resource "aws_route53_record" "app_stage" {
  count           = local.create_dns_record ? 1 : 0
  zone_id         = var.route53_hosted_zone_id != "" ? var.route53_hosted_zone_id : data.aws_route53_zone.harness_demo[0].zone_id
  name            = "${var.owner}-stage.${var.dns_domain}"
  type            = "CNAME"
  ttl             = 60
  records         = [var.shared_alb_dns_name]
  allow_overwrite = true

  lifecycle {
    create_before_destroy = true
  }
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

output "delegate_name" {
  description = "Delegate name"
  value       = var.create_delegate ? "delegate-${var.owner}" : null
}

output "delegate_irsa_role_arn" {
  description = "IRSA role ARN for the delegate"
  value       = var.create_delegate ? module.irsa_delegate_role[0].role_arn : null
}

output "alb_dns_name" {
  description = "Shared ALB DNS name used for this sandbox's Route53 records when manage_dns is enabled"
  value       = var.shared_alb_dns_name != "" ? var.shared_alb_dns_name : null
}

output "dns_record" {
  description = "Primary per-sandbox DNS record created by this stack when manage_dns is enabled"
  value       = local.create_dns_record ? "${var.owner}.${var.dns_domain} -> ${var.shared_alb_dns_name}" : null
}

output "opa_policy_sets" {
  description = "OPA policy sets created for CI/CD governance"
  value       = var.create_opa_policies ? module.opa_policies[0].policy_set_ids : null
}

################################################################################
# IRSA Role for Delegate (AWS permissions via service account)
################################################################################

module "irsa_delegate_role" {
  source = "../../modules/irsa-delegate-role"
  count  = var.create_delegate ? 1 : 0

  name_prefix              = local.name_prefix
  owner                    = var.owner
  cluster_name             = var.eks_cluster_name
  delegate_namespace       = "harness-delegate-ng-${var.owner}"
  delegate_service_account = "delegate-${var.owner}"

  # ECR access for CI builds
  ecr_repository_arns = ["*"]

  # Enable deployment-specific permissions
  enable_ecs_permissions    = false
  enable_asg_permissions    = var.enable_asg_permissions
  enable_lambda_permissions = false

  # Use existing role if it already exists outside of Terraform state
  import_existing_role = var.import_existing_irsa_role

  tags = local.common_tags
}

################################################################################
# Delegate Token
################################################################################

resource "random_id" "delegate_token_suffix" {
  count       = var.create_delegate ? 1 : 0
  byte_length = 4
}

resource "harness_platform_delegatetoken" "delegate" {
  count      = var.create_delegate ? 1 : 0
  name       = "${var.owner}-delegate-token-${random_id.delegate_token_suffix[0].hex}"
  account_id = var.harness_account_id
  org_id     = local.resolved_org_id
  project_id = local.resolved_project_id
}

################################################################################
# Harness Delegate
################################################################################

module "harness_delegate" {
  source = "../../modules/harness-delegate"
  count  = var.create_delegate ? 1 : 0

  owner                    = var.owner
  delegate_name            = "delegate"
  harness_account_id       = var.harness_account_id
  harness_api_key          = var.harness_api_key
  delegate_token           = harness_platform_delegatetoken.delegate[0].value
  harness_manager_endpoint = var.harness_endpoint

  create_namespace     = true
  delegate_replicas    = var.delegate_replicas
  grant_cluster_admin  = true
  fetch_latest_version = true

  # IRSA configuration - bind delegate SA to IAM role
  enable_irsa_annotations = true
  irsa_role_arn           = module.irsa_delegate_role[0].role_arn

  # Tags for delegate selection - includes delegate-{owner} for CD pipeline
  delegate_tags = ["delegate-${var.owner}"]

  depends_on = [
    module.harness_org_project,
    module.irsa_delegate_role,
    harness_platform_delegatetoken.delegate
  ]
}
