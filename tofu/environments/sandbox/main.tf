################################################################################
# Sandbox Environment
# Personal sandbox for testing and development
# Supports: new or existing EKS cluster, new or existing delegate, IRSA
################################################################################

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.25"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    harness = {
      source  = "harness/harness"
      version = "~> 0.30"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
  }

  # Uncomment and configure for remote state (run bootstrap first)
  # backend "s3" {
  #   bucket         = "harness-demo-tfstate-<owner>-<suffix>"
  #   key            = "harness-demo/sandbox/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "harness-demo-tfstate-lock-<owner>"
  # }
}

################################################################################
# Data Sources for Existing Cluster
################################################################################

data "aws_eks_cluster" "existing" {
  count = var.create_eks_cluster ? 0 : 1
  name  = var.existing_cluster_name
}

data "aws_eks_cluster_auth" "existing" {
  count = var.create_eks_cluster ? 0 : 1
  name  = var.existing_cluster_name
}

################################################################################
# Local Variables
################################################################################

locals {
  name_prefix  = "harness-demo-${var.owner}"
  cluster_name = var.create_eks_cluster ? "${local.name_prefix}-eks" : var.existing_cluster_name

  # Cluster connection details (from new or existing cluster)
  cluster_endpoint = var.create_eks_cluster ? module.eks[0].cluster_endpoint : data.aws_eks_cluster.existing[0].endpoint
  cluster_ca_data  = var.create_eks_cluster ? module.eks[0].cluster_certificate_authority_data : data.aws_eks_cluster.existing[0].certificate_authority[0].data

  common_tags = {
    Project     = "harness-demo"
    Environment = var.environment
    ManagedBy   = "tofu"
    Owner       = var.owner
  }

  # Delegate selector includes owner for uniqueness
  delegate_selector = "delegate-${var.owner}"
}

################################################################################
# Provider Configuration
################################################################################

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

provider "kubernetes" {
  host                   = local.cluster_endpoint
  cluster_ca_certificate = base64decode(local.cluster_ca_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", local.cluster_name]
  }
}

provider "helm" {
  kubernetes {
    host                   = local.cluster_endpoint
    cluster_ca_certificate = base64decode(local.cluster_ca_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", local.cluster_name]
    }
  }
}

provider "harness" {
  endpoint         = var.harness_endpoint
  account_id       = var.harness_account_id
  platform_api_key = var.harness_api_key
}

################################################################################
# Harness Organization and Project (optional creation)
################################################################################

module "harness_org_project" {
  source = "../../modules/harness-org-project"

  # Organization
  create_organization      = var.create_harness_org
  existing_org_id          = var.harness_org_id
  organization_id          = var.new_harness_org_id
  organization_name        = var.new_harness_org_name
  organization_description = "Reference architecture for Harness CI/CD demonstrations - ${var.owner}"

  # Project
  create_project      = var.create_harness_project
  existing_project_id = var.harness_project_id
  project_id          = var.new_harness_project_id != "" ? var.new_harness_project_id : "${var.owner}_demo"
  project_name        = var.new_harness_project_name != "" ? var.new_harness_project_name : "${title(var.owner)} Demo"
  project_description = "Demo project for ${var.owner}"

  tags = ["tofu-managed", var.owner]
}

locals {
  # Use resolved org/project IDs from module
  resolved_org_id     = module.harness_org_project.org_id
  resolved_project_id = module.harness_org_project.project_id
}

################################################################################
# VPC (only if creating new cluster)
################################################################################

module "vpc" {
  source = "../../modules/vpc"
  count  = var.create_eks_cluster ? 1 : 0

  name_prefix        = local.name_prefix
  vpc_cidr           = var.vpc_cidr
  cluster_name       = local.cluster_name
  enable_nat_gateway = var.enable_nat_gateway

  tags = local.common_tags
}

################################################################################
# EKS Cluster (optional - can use existing)
################################################################################

module "eks" {
  source = "../../modules/eks"
  count  = var.create_eks_cluster ? 1 : 0

  name_prefix        = local.name_prefix
  cluster_name       = local.cluster_name
  vpc_id             = module.vpc[0].vpc_id
  subnet_ids         = module.vpc[0].private_subnet_ids
  kubernetes_version = var.kubernetes_version

  node_instance_types = var.node_instance_types
  node_capacity_type  = var.node_capacity_type
  node_desired_size   = var.node_desired_size
  node_min_size       = var.node_min_size
  node_max_size       = var.node_max_size

  create_namespace = true
  namespace        = "harness-demo"

  tags = local.common_tags
}

################################################################################
# ECR Repository
################################################################################

module "ecr" {
  source = "../../modules/ecr"

  repository_name         = "harness-demo-app-${var.owner}"
  enable_lifecycle_policy = true
  max_image_count         = 30

  tags = local.common_tags
}

################################################################################
# IRSA Role for Delegate (AWS permissions via service account)
################################################################################

module "irsa_delegate_role" {
  source = "../../modules/irsa-delegate-role"
  count  = var.create_delegate && var.enable_irsa ? 1 : 0

  name_prefix              = local.name_prefix
  owner                    = var.owner
  cluster_name             = local.cluster_name
  delegate_namespace       = "harness-delegate-ng-${var.owner}"
  delegate_service_account = "delegate-${var.owner}"

  ecr_repository_arns     = [module.ecr.repository_arn]
  s3_bucket_arns          = var.s3_bucket_arns
  cross_account_role_arns = var.cross_account_role_arns

  enable_ecs_permissions    = var.enable_ecs_permissions
  enable_lambda_permissions = var.enable_lambda_permissions

  tags = local.common_tags

  depends_on = [module.eks]
}

################################################################################
# Harness Delegate Token (project-scoped, created via API)
################################################################################

resource "harness_platform_delegatetoken" "delegate" {
  count      = var.create_delegate ? 1 : 0
  name       = "${var.owner}-delegate-token"
  account_id = var.harness_account_id
  org_id     = local.resolved_org_id
  project_id = local.resolved_project_id

  depends_on = [module.harness_org_project]
}

################################################################################
# Harness Delegate (optional - can use existing)
################################################################################

module "harness_delegate" {
  source = "../../modules/harness-delegate"
  count  = var.create_delegate ? 1 : 0

  owner                    = var.owner
  delegate_name            = "delegate"
  harness_account_id       = var.harness_account_id
  harness_api_key          = var.harness_api_key
  delegate_token           = var.create_delegate ? harness_platform_delegatetoken.delegate[0].value : var.harness_delegate_token
  harness_manager_endpoint = var.harness_endpoint

  create_namespace     = true
  create_delegate      = true
  grant_cluster_admin  = true
  enable_upgrader      = false
  delegate_version     = var.delegate_version
  fetch_latest_version = var.delegate_version == ""

  # IRSA configuration
  irsa_role_arn = var.enable_irsa && length(module.irsa_delegate_role) > 0 ? module.irsa_delegate_role[0].role_arn : ""

  delegate_tags = [var.owner, var.environment, "eks"]

  tags = local.common_tags

  depends_on = [module.eks, module.irsa_delegate_role]
}

################################################################################
# Harness Connectors
################################################################################

module "harness_connectors" {
  source = "../../modules/harness-connectors"
  count  = var.create_connectors ? 1 : 0

  environment_name   = var.environment
  harness_org_id     = local.resolved_org_id
  harness_project_id = local.resolved_project_id
  delegate_selectors = [local.delegate_selector]

  # Kubernetes Connector
  create_k8s_connector = true
  k8s_connector_id     = "${var.owner}_k8s_reference_architecture"
  k8s_connector_name   = "${title(var.owner)} K8s Reference Architecture"

  # AWS Connector with IRSA and cross-account support
  create_aws_connector        = true
  aws_connector_id            = "${var.owner}_aws_reference_architecture"
  aws_connector_name          = "${title(var.owner)} AWS Reference Architecture"
  aws_connector_description   = "AWS connector for ${title(var.owner)} sandbox Reference Architecture (irsa)"
  connector_tags              = ["tofu-managed:true", "harness-sandbox:true"]
  aws_auth_type               = var.enable_irsa ? "irsa" : "delegate"
  aws_region                  = var.aws_region
  enable_cross_account_access = var.enable_cross_account_access
  cross_account_role_arn      = var.cross_account_role_arn
  cross_account_external_id   = var.cross_account_external_id

  # Docker/ECR Connector - disabled, ECR auth handled by AWS connector via IRSA
  create_docker_connector = false
  docker_connector_id     = "${var.owner}_ecr"
  docker_connector_name   = "${title(var.owner)} ECR"
  docker_registry_url     = module.ecr.repository_url

  # GitHub Connector
  create_github_connector = var.github_token_ref != ""
  github_connector_id     = "${var.owner}_github_reference_architecture"
  github_connector_name   = "${title(var.owner)} GitHub Reference Architecture"
  github_url              = var.github_url
  github_username         = var.github_username
  github_token_ref        = var.github_token_ref

  depends_on = [module.harness_delegate]
}

################################################################################
# Harness Service Definition
################################################################################

module "harness_service" {
  source = "../../modules/harness-service"
  count  = var.create_harness_service ? 1 : 0

  service_id          = "${var.owner}_demo_app"
  service_name        = "${title(var.owner)} Demo App"
  service_description = "Demo application for ${var.owner} (${join(", ", var.deployment_targets)})"
  org_id              = local.resolved_org_id
  project_id          = local.resolved_project_id

  # Deployment type based on selected targets
  deployment_type = local.primary_deployment_type

  # Manifest configuration (K8s/Helm)
  manifest_type     = local.enable_eks ? "K8sManifest" : "values"
  git_connector_ref = var.create_connectors ? "${var.owner}_github_reference_architecture" : var.github_connector_ref
  git_repo_name     = var.service_git_repo
  git_branch        = var.service_git_branch
  manifest_paths    = var.service_manifest_paths

  # ECS manifest paths (if ECS target)
  ecs_task_definition_paths    = local.enable_ecs ? var.ecs_task_definition_paths : []
  ecs_service_definition_paths = local.enable_ecs ? var.ecs_service_definition_paths : []

  # Artifact configuration
  artifact_source_type   = "Ecr"
  artifact_connector_ref = var.create_connectors ? "${var.owner}_aws_reference_architecture" : var.aws_connector_ref
  ecr_image_path         = module.ecr.repository_name
  aws_region             = var.aws_region

  tags = ["tofu-managed", var.owner, join("-", var.deployment_targets)]

  depends_on = [module.harness_connectors, module.ecr]
}

################################################################################
# Harness Environment and Infrastructure
################################################################################

module "harness_environment_dev" {
  source = "../../modules/harness-environment"
  count  = var.create_harness_environment ? 1 : 0

  environment_id          = "${var.owner}_dev"
  environment_name        = "${title(var.owner)} Dev"
  environment_description = "Development environment for ${var.owner}"
  org_id                  = local.resolved_org_id
  project_id              = local.resolved_project_id
  environment_type        = "PreProduction"

  # Kubernetes infrastructure (created if eks in deployment_targets)
  create_k8s_infrastructure = local.enable_eks
  k8s_infra_id              = "${var.owner}_k8s_dev"
  k8s_infra_name            = "${title(var.owner)} K8s Dev"
  k8s_connector_ref         = var.create_connectors ? "${var.owner}_k8s_reference_architecture" : var.k8s_connector_ref
  k8s_namespace             = "harness-demo-${var.owner}"

  # ECS infrastructure (created if ecs in deployment_targets)
  create_ecs_infrastructure = local.enable_ecs
  ecs_infra_id              = "${var.owner}_ecs_dev"
  ecs_infra_name            = "${title(var.owner)} ECS Dev"
  aws_connector_ref         = var.create_connectors ? "${var.owner}_aws_reference_architecture" : var.aws_connector_ref
  aws_region                = var.aws_region
  ecs_cluster_name          = var.ecs_cluster_name

  # Lambda infrastructure (created if lambda in deployment_targets)
  create_lambda_infrastructure = local.enable_lambda
  lambda_infra_id              = "${var.owner}_lambda_dev"
  lambda_infra_name            = "${title(var.owner)} Lambda Dev"
  lambda_stage                 = "dev"

  tags = ["tofu-managed", var.owner, join("-", var.deployment_targets)]

  depends_on = [module.harness_connectors]
}

module "harness_environment_prod" {
  source = "../../modules/harness-environment"
  count  = var.create_harness_environment && var.create_prod_environment ? 1 : 0

  environment_id          = "${var.owner}_prod"
  environment_name        = "${title(var.owner)} Prod"
  environment_description = "Production environment for ${var.owner}"
  org_id                  = local.resolved_org_id
  project_id              = local.resolved_project_id
  environment_type        = "Production"

  # Kubernetes infrastructure (created if eks in deployment_targets)
  create_k8s_infrastructure = local.enable_eks
  k8s_infra_id              = "${var.owner}_k8s_prod"
  k8s_infra_name            = "${title(var.owner)} K8s Prod"
  k8s_connector_ref         = var.create_connectors ? "${var.owner}_k8s_reference_architecture" : var.k8s_connector_ref
  k8s_namespace             = "harness-demo-${var.owner}-prod"

  # ECS infrastructure (created if ecs in deployment_targets)
  create_ecs_infrastructure = local.enable_ecs
  ecs_infra_id              = "${var.owner}_ecs_prod"
  ecs_infra_name            = "${title(var.owner)} ECS Prod"
  aws_connector_ref         = var.create_connectors ? "${var.owner}_aws_reference_architecture" : var.aws_connector_ref
  aws_region                = var.aws_region
  ecs_cluster_name          = var.ecs_cluster_name

  # Lambda infrastructure (created if lambda in deployment_targets)
  create_lambda_infrastructure = local.enable_lambda
  lambda_infra_id              = "${var.owner}_lambda_prod"
  lambda_infra_name            = "${title(var.owner)} Lambda Prod"
  lambda_stage                 = "prod"

  tags = ["tofu-managed", var.owner, join("-", var.deployment_targets)]

  depends_on = [module.harness_connectors]
}

################################################################################
# Harness Pipelines
################################################################################

module "harness_pipelines_dev" {
  source = "../../modules/harness-pipeline"
  count  = var.create_harness_service && var.create_harness_environment ? 1 : 0

  org_id             = local.resolved_org_id
  project_id         = local.resolved_project_id
  service_ref        = var.create_harness_service ? "${var.owner}_demo_app" : ""
  environment_ref    = var.create_harness_environment ? "${var.owner}_dev" : ""
  environment_name   = "Dev"
  infrastructure_ref = local.enable_eks ? "${var.owner}_k8s_dev" : ""

  # Canary pipeline
  create_canary_pipeline      = var.create_canary_pipeline
  canary_pipeline_id          = "${var.owner}_k8s_canary_deploy"
  canary_pipeline_name        = "${title(var.owner)} K8s Canary Deploy"
  canary_pipeline_description = "Canary deployment with CV for ${var.owner} demo app"
  canary_instance_count       = 1
  cv_sensitivity              = "Medium"
  cv_duration                 = "5m"

  # Blue/Green pipeline
  create_blue_green_pipeline      = var.create_blue_green_pipeline
  blue_green_pipeline_id          = "${var.owner}_k8s_blue_green_deploy"
  blue_green_pipeline_name        = "${title(var.owner)} K8s Blue/Green Deploy"
  blue_green_pipeline_description = "Blue/Green deployment for ${var.owner} demo app"

  pipeline_tags = ["tofu-managed", var.owner]

  depends_on = [module.harness_service, module.harness_environment_dev]
}
