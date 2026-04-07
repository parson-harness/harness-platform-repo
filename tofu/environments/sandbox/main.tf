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
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
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

# Auth token for newly created cluster
data "aws_eks_cluster_auth" "new" {
  count = var.create_eks_cluster ? 1 : 0
  name  = module.eks[0].cluster_name
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
  cluster_token    = var.create_eks_cluster ? data.aws_eks_cluster_auth.new[0].token : data.aws_eks_cluster_auth.existing[0].token

  common_tags = {
    Project     = "harness-demo"
    Environment = var.environment
    ManagedBy   = "tofu"
    Owner       = var.owner
    Contact     = "todd.parson@harness.io"
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
  token                  = local.cluster_token
}

provider "helm" {
  kubernetes {
    host                   = local.cluster_endpoint
    cluster_ca_certificate = base64decode(local.cluster_ca_data)
    token                  = local.cluster_token
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
# Harness Code Repository (import from GitHub for self-contained POV)
################################################################################

module "harness_code_repo" {
  source = "../../modules/harness-code-repo"
  count  = var.import_to_harness_code ? 1 : 0

  harness_endpoint   = var.harness_endpoint
  harness_account_id = var.harness_account_id
  harness_api_key    = var.harness_api_key
  org_id             = local.resolved_org_id
  project_id         = local.resolved_project_id

  repo_identifier  = "${var.owner}-demo-app"
  repo_description = "POV Demo App for ${var.owner} - cloned from GitHub (${var.source_github_repo})"

  source_provider = "github"
  source_repo     = var.source_github_repo

  depends_on = [module.harness_org_project]
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
# Artifact Registry (HAR or ECR based on artifact_registry_type)
################################################################################

# Harness Artifact Registry (default)
module "har" {
  source = "../../modules/harness-artifact-registry"
  count  = var.artifact_registry_type == "har" ? 1 : 0

  account_id = var.harness_account_id
  org_id     = local.resolved_org_id
  project_id = local.resolved_project_id

  registry_id          = "har-${var.owner}"
  registry_description = "Docker registry for ${var.owner} demo app"

  # DockerHub upstream proxy (per-owner to avoid conflicts)
  create_dockerhub_upstream     = var.create_dockerhub_upstream
  dockerhub_upstream_id         = "${var.owner}-dockerhub-proxy"
  dockerhub_username            = var.dockerhub_username
  dockerhub_password_secret_ref = var.dockerhub_password_secret_ref
  dockerhub_secret_space_path   = var.harness_account_id

  depends_on = [module.harness_org_project]
}

# ECR Repository (optional - when artifact_registry_type = "ecr")
module "ecr" {
  source = "../../modules/ecr"
  count  = var.artifact_registry_type == "ecr" ? 1 : 0

  repository_name         = "harness-demo-app-${var.owner}"
  enable_lifecycle_policy = true
  max_image_count         = 30

  tags = local.common_tags
}

locals {
  # Artifact registry outputs based on type
  artifact_registry_url = var.artifact_registry_type == "har" ? (
    length(module.har) > 0 ? module.har[0].registry_url : ""
    ) : (
    length(module.ecr) > 0 ? module.ecr[0].repository_url : ""
  )
}

################################################################################
# IAM User + Harness Secrets for ASG Packer CI Builds
# Creates a dedicated IAM user with minimal AMI-build permissions, generates an
# access key, and stores both values as project-scoped Harness secrets.
# Fully automated - no manual credential handling required.
################################################################################

resource "terraform_data" "cleanup_existing_packer_ci_user" {
  count = local.enable_asg ? 1 : 0

  provisioner "local-exec" {
    interpreter = ["/bin/sh", "-c"]
    command     = <<-EOT
      set +e
      USER_NAME="harness-packer-ci-${var.owner}"
      IAM_ACCESS_KEY_ID="$${AWS_ACCESS_KEY_ID}"
      IAM_SECRET_ACCESS_KEY="$${AWS_SECRET_ACCESS_KEY}"
      IAM_AUTH_USER="$${IAM_ACCESS_KEY_ID}:$${IAM_SECRET_ACCESS_KEY}"

      iam_get() {
        curl -s --aws-sigv4 "aws:amz:us-east-1:iam" \
          --user "$${IAM_AUTH_USER}" \
          -H "x-amz-security-token: $${AWS_SESSION_TOKEN}" \
          "https://iam.amazonaws.com/$1"
      }
      iam_post() {
        curl -s --aws-sigv4 "aws:amz:us-east-1:iam" \
          --user "$${IAM_AUTH_USER}" \
          -H "x-amz-security-token: $${AWS_SESSION_TOKEN}" \
          -d "$1" "https://iam.amazonaws.com/"
      }

      RESPONSE=$(iam_get "?Action=GetUser&UserName=$${USER_NAME}&Version=2010-05-08" 2>&1)
      if echo "$${RESPONSE}" | grep -q "NoSuchEntity"; then
        exit 0
      fi
      if ! echo "$${RESPONSE}" | grep -q "<UserName>"; then
        exit 0
      fi

      ACCESS_KEYS_XML=$(iam_get "?Action=ListAccessKeys&UserName=$${USER_NAME}&Version=2010-05-08" 2>&1)
      for KEY_ID in $(echo "$${ACCESS_KEYS_XML}" | grep -o '<AccessKeyId>[^<]*</AccessKeyId>' | sed 's/<[^>]*>//g'); do
        iam_post "Action=DeleteAccessKey&UserName=$${USER_NAME}&AccessKeyId=$${KEY_ID}&Version=2010-05-08" >/dev/null 2>&1 || true
      done

      POLICIES_XML=$(iam_get "?Action=ListUserPolicies&UserName=$${USER_NAME}&Version=2010-05-08" 2>&1)
      for POLICY in $(echo "$${POLICIES_XML}" | grep -o '<member>[^<]*</member>' | sed 's/<[^>]*>//g'); do
        iam_post "Action=DeleteUserPolicy&UserName=$${USER_NAME}&PolicyName=$${POLICY}&Version=2010-05-08" >/dev/null 2>&1 || true
      done

      ATTACHED_XML=$(iam_get "?Action=ListAttachedUserPolicies&UserName=$${USER_NAME}&Version=2010-05-08" 2>&1)
      for ARN in $(echo "$${ATTACHED_XML}" | grep -o '<PolicyArn>[^<]*</PolicyArn>' | sed 's/<[^>]*>//g'); do
        iam_post "Action=DetachUserPolicy&UserName=$${USER_NAME}&PolicyArn=$${ARN}&Version=2010-05-08" >/dev/null 2>&1 || true
      done

      GROUPS_XML=$(iam_get "?Action=ListGroupsForUser&UserName=$${USER_NAME}&Version=2010-05-08" 2>&1)
      for GROUP in $(echo "$${GROUPS_XML}" | grep -o '<GroupName>[^<]*</GroupName>' | sed 's/<[^>]*>//g'); do
        iam_post "Action=RemoveUserFromGroup&UserName=$${USER_NAME}&GroupName=$${GROUP}&Version=2010-05-08" >/dev/null 2>&1 || true
      done

      iam_post "Action=DeleteLoginProfile&UserName=$${USER_NAME}&Version=2010-05-08" >/dev/null 2>&1 || true
      iam_post "Action=DeleteUser&UserName=$${USER_NAME}&Version=2010-05-08" >/dev/null 2>&1 || true
      exit 0
    EOT
  }
}

resource "aws_iam_user" "packer_ci" {
  count = local.enable_asg ? 1 : 0
  name  = "harness-packer-ci-${var.owner}"
  tags  = local.common_tags

  depends_on = [terraform_data.cleanup_existing_packer_ci_user]
}

resource "aws_iam_user_policy" "packer_ci" {
  count = local.enable_asg ? 1 : 0
  name  = "harness-packer-ci-policy"
  user  = aws_iam_user.packer_ci[0].name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "PackerAMIBuild"
        Effect = "Allow"
        Action = [
          "ec2:RunInstances",
          "ec2:StopInstances",
          "ec2:TerminateInstances",
          "ec2:CreateImage",
          "ec2:CreateTags",
          "ec2:DeleteTags",
          "ec2:ModifyImageAttribute",
          "ec2:DescribeImages",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceStatus",
          "ec2:DescribeRegions",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeVpcs",
          "ec2:DescribeVolumes",
          "ec2:CreateSecurityGroup",
          "ec2:DeleteSecurityGroup",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:CreateKeyPair",
          "ec2:DeleteKeyPair",
          "ec2:DescribeKeyPairs"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_access_key" "packer_ci" {
  count = local.enable_asg ? 1 : 0
  user  = aws_iam_user.packer_ci[0].name
}

resource "harness_platform_secret_text" "packer_aws_access_key" {
  count = local.enable_asg ? 1 : 0

  identifier = "aws_access_key_id"
  name       = "AWS-Access-Key-ID-Packer"
  org_id     = local.resolved_org_id
  project_id = local.resolved_project_id

  secret_manager_identifier = "harnessSecretManager"
  value_type                = "Inline"
  value                     = aws_iam_access_key.packer_ci[0].id

  depends_on = [aws_iam_access_key.packer_ci]
}

resource "harness_platform_secret_text" "packer_aws_secret_key" {
  count = local.enable_asg ? 1 : 0

  identifier = "aws_secret_access_key"
  name       = "AWS-Secret-Access-Key-Packer"
  org_id     = local.resolved_org_id
  project_id = local.resolved_project_id

  secret_manager_identifier = "harnessSecretManager"
  value_type                = "Inline"
  value                     = aws_iam_access_key.packer_ci[0].secret

  depends_on = [aws_iam_access_key.packer_ci]
}

################################################################################
# ASG Infrastructure (created when deployment_targets includes "asg")
# Provides: VPC, ALB, target groups, Launch Template, seed ASG
# Packer builds the AMI; no ECR or Docker required
################################################################################

module "asg" {
  source = "../../modules/asg"
  count  = local.enable_asg ? 1 : 0

  name_prefix   = local.name_prefix
  owner         = var.owner
  aws_region    = var.aws_region
  vpc_cidr      = var.asg_vpc_cidr
  instance_type = var.asg_instance_type

  asg_desired_capacity = var.asg_desired_capacity
  asg_max_size         = var.asg_max_size

  create_dns_record = var.asg_create_dns_record
  route53_zone_name = var.route53_zone_name
  acm_cert_arn      = var.acm_cert_arn

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

  ecr_repository_arns     = var.artifact_registry_type == "ecr" && length(module.ecr) > 0 ? [module.ecr[0].repository_arn] : []
  s3_bucket_arns          = var.s3_bucket_arns
  cross_account_role_arns = var.cross_account_role_arns

  enable_ecs_permissions    = var.enable_ecs_permissions
  enable_lambda_permissions = var.enable_lambda_permissions
  enable_asg_permissions    = local.enable_asg || var.enable_asg_permissions

  tags = local.common_tags

  depends_on = [module.eks]
}

################################################################################
# Harness Delegate Token (project-scoped, created via API)
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
  enable_irsa_annotations = var.enable_irsa
  irsa_role_arn           = var.enable_irsa && length(module.irsa_delegate_role) > 0 ? module.irsa_delegate_role[0].role_arn : ""

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
  # Note: AmazonMachineImage artifact type requires cross_account_access even for same-account IRSA
  create_aws_connector        = true
  aws_connector_id            = "${var.owner}_aws_reference_architecture"
  aws_connector_name          = "${title(var.owner)} AWS Reference Architecture"
  aws_connector_description   = "AWS connector for ${title(var.owner)} sandbox Reference Architecture (irsa)"
  connector_tags              = ["tofu-managed:true", "harness-sandbox:true", "owner:${var.owner}"]
  aws_auth_type               = var.enable_irsa ? "irsa" : "delegate"
  aws_region                  = var.aws_region
  enable_cross_account_access = var.enable_cross_account_access || (var.enable_irsa && local.enable_asg)
  cross_account_role_arn      = var.cross_account_role_arn != "" ? var.cross_account_role_arn : (var.enable_irsa && local.enable_asg && length(module.irsa_delegate_role) > 0 ? module.irsa_delegate_role[0].role_arn : "")
  cross_account_external_id   = var.cross_account_external_id

  # Docker/ECR Connector - disabled, ECR auth handled by AWS connector via IRSA
  create_docker_connector = false
  docker_connector_id     = "${var.owner}_ecr"
  docker_connector_name   = "${title(var.owner)} ECR"
  docker_registry_url     = var.artifact_registry_type == "ecr" && length(module.ecr) > 0 ? module.ecr[0].repository_url : ""

  # GitHub Connector (keep for backward compatibility, but service uses Harness Code when enabled)
  create_github_connector = var.github_token_ref != ""
  github_connector_id     = "${var.owner}_github_reference_architecture"
  github_connector_name   = "${title(var.owner)} GitHub Reference Architecture"
  github_url              = var.github_url
  github_username         = var.github_username
  github_token_ref        = var.github_token_ref

  # Prometheus Connector (for CV)
  create_prometheus_connector = var.enable_cv && var.prometheus_url != ""
  prometheus_connector_id     = "${var.owner}_prometheus"
  prometheus_connector_name   = "${title(var.owner)} Prometheus"
  prometheus_url              = var.prometheus_url

  depends_on = [module.harness_delegate]
}

################################################################################
# Harness Service Definition
################################################################################

################################################################################
# Harness ASG Service Definition
# Separate service required - Harness services are single-deployment-type.
# Uses AmazonMachineImage artifact; JAR is baked into the AMI by Packer CI.
################################################################################

module "harness_service_asg" {
  source = "../../modules/harness-service"
  count  = local.enable_asg && var.create_harness_service ? 1 : 0

  service_id          = "${var.owner}_demo_app_asg"
  service_name        = "${title(var.owner)} Demo App ASG"
  service_description = "ASG demo application for ${var.owner} - Blue/Green, Canary, Rolling on EC2"
  org_id              = local.resolved_org_id
  project_id          = local.resolved_project_id

  deployment_type = "Asg"

  # ASG artifact = Packer-built AMI; AWS connector used to query AMI by name/tag
  artifact_registry_type = "ecr"
  artifact_connector_ref = var.create_connectors ? "${var.owner}_aws_reference_architecture" : var.aws_connector_ref
  aws_region             = var.aws_region
  asg_ami_owner_tag      = var.owner

  # Startup script in repo (Harness renders expressions at deploy time)
  asg_startup_script_path = "asg/user-data.sh"
  manifest_store_type     = var.import_to_harness_code ? "HarnessCode" : "Github"
  git_connector_ref = var.import_to_harness_code ? "" : (
    var.create_connectors && var.github_token_ref != "" ? "${var.owner}_github_reference_architecture" : var.github_connector_ref
  )
  git_repo_name          = var.import_to_harness_code ? "" : element(split("/", var.source_github_repo), length(split("/", var.source_github_repo)) - 1)
  harness_code_repo_name = var.import_to_harness_code ? "${var.owner}-demo-app" : ""
  git_branch             = var.service_git_branch

  tags = ["tofu-managed", var.owner, "asg"]

  service_variables = [
    {
      name  = "appUrl"
      type  = "String"
      value = length(module.asg) > 0 ? module.asg[0].app_url : ""
    },
    {
      name  = "stageUrl"
      type  = "String"
      value = length(module.asg) > 0 ? module.asg[0].stage_url : ""
    },
    {
      name  = "instanceProfileName"
      type  = "String"
      value = length(module.asg) > 0 ? module.asg[0].instance_profile_name : ""
    },
    {
      name  = "securityGroupId"
      type  = "String"
      value = length(module.asg) > 0 ? module.asg[0].instance_security_group_id : ""
    },
    {
      name  = "subnetIds"
      type  = "String"
      value = length(module.asg) > 0 ? join(",", module.asg[0].public_subnet_ids) : ""
    },
    {
      name  = "baseAsgName"
      type  = "String"
      value = length(module.asg) > 0 ? module.asg[0].base_asg_name : ""
    }
  ]

  depends_on = [module.harness_connectors, module.asg]
}

module "harness_service" {
  source = "../../modules/harness-service"
  count  = var.create_harness_service && (local.enable_eks || local.enable_ecs || local.enable_lambda) ? 1 : 0

  service_id          = "${var.owner}_demo_app"
  service_name        = "${title(var.owner)} Demo App"
  service_description = "Demo application for ${var.owner} (${join(", ", var.deployment_targets)})"
  org_id              = local.resolved_org_id
  project_id          = local.resolved_project_id

  # Deployment type based on selected targets
  deployment_type = local.primary_deployment_type

  # Manifest configuration (K8s/Helm)
  manifest_type       = local.enable_eks ? "K8sManifest" : "values"
  manifest_store_type = var.import_to_harness_code ? "HarnessCode" : "Github"

  # Git connector (only used when not using Harness Code)
  git_connector_ref = var.import_to_harness_code ? "" : (
    var.create_connectors ? "${var.owner}_github_reference_architecture" : var.github_connector_ref
  )
  git_repo_name  = var.import_to_harness_code ? "" : element(split("/", var.source_github_repo), length(split("/", var.source_github_repo)) - 1)
  git_branch     = var.service_git_branch
  manifest_paths = var.service_manifest_paths

  # Harness Code repo (used when import_to_harness_code = true)
  harness_code_repo_name = var.import_to_harness_code ? "${var.owner}-demo-app" : ""

  # ECS manifest paths (if ECS target)
  ecs_task_definition_paths    = local.enable_ecs ? var.ecs_task_definition_paths : []
  ecs_service_definition_paths = local.enable_ecs ? var.ecs_service_definition_paths : []

  # Artifact configuration - HAR or ECR based on artifact_registry_type
  artifact_registry_type = var.artifact_registry_type

  # ECR configuration (when artifact_registry_type = "ecr")
  artifact_connector_ref = var.artifact_registry_type == "ecr" ? (
    var.create_connectors ? "${var.owner}_aws_reference_architecture" : var.aws_connector_ref
  ) : ""
  ecr_image_path = var.artifact_registry_type == "ecr" && length(module.ecr) > 0 ? module.ecr[0].repository_name : ""
  aws_region     = var.aws_region

  # HAR configuration (when artifact_registry_type = "har")
  # registryRef format: account.<registry-id> for account-level, or project-level ref
  har_registry_ref = var.artifact_registry_type == "har" && length(module.har) > 0 ? (
    module.har[0].registry_id
  ) : ""
  har_image_path = var.artifact_registry_type == "har" ? "${var.owner}demoapp" : ""

  tags = ["tofu-managed", var.owner, join("-", var.deployment_targets)]

  service_variables = var.acm_cert_arn != "" ? [
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
    ] : [
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
      value = ""
    }
  ]

  depends_on = [module.harness_connectors, module.ecr, module.har]
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
  create_k8s_namespace      = false # Namespace created in main.tf
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

  # ASG infrastructure (created if asg in deployment_targets)
  create_asg_infrastructure = local.enable_asg
  asg_infra_id              = "${var.owner}_asg_dev"
  asg_infra_name            = "${title(var.owner)} ASG Dev"
  asg_base_asg_name         = local.enable_asg && length(module.asg) > 0 ? module.asg[0].base_asg_name : ""
  asg_load_balancer_name    = local.enable_asg && length(module.asg) > 0 ? module.asg[0].alb_name : ""
  asg_prod_listener_arn     = local.enable_asg && length(module.asg) > 0 ? module.asg[0].prod_listener_arn : ""
  asg_stage_listener_arn    = local.enable_asg && length(module.asg) > 0 ? module.asg[0].stage_listener_arn : ""

  tags = ["tofu-managed", var.owner, join("-", var.deployment_targets)]

  depends_on = [module.harness_connectors, module.asg]
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
  create_k8s_namespace      = false # Namespace created in main.tf
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

  # ASG infrastructure (created if asg in deployment_targets)
  # Shares the same ASG/ALB as dev (single ALB with prod:80 + stage:8080 listeners)
  create_asg_infrastructure = local.enable_asg
  asg_infra_id              = "${var.owner}_asg_prod"
  asg_infra_name            = "${title(var.owner)} ASG Prod"
  asg_base_asg_name         = local.enable_asg && length(module.asg) > 0 ? module.asg[0].base_asg_name : ""
  asg_load_balancer_name    = local.enable_asg && length(module.asg) > 0 ? module.asg[0].alb_name : ""
  asg_prod_listener_arn     = local.enable_asg && length(module.asg) > 0 ? module.asg[0].prod_listener_arn : ""
  asg_stage_listener_arn    = local.enable_asg && length(module.asg) > 0 ? module.asg[0].stage_listener_arn : ""

  tags = ["tofu-managed", var.owner, join("-", var.deployment_targets)]

  depends_on = [module.harness_connectors, module.asg]
}

################################################################################
# HAR Pull Secret for Kubernetes (when using Harness Artifact Registry)
# Creates the dockercfg secret needed to pull images from HAR
################################################################################

locals {
  # Namespaces that need HAR pull secrets
  har_namespaces = var.artifact_registry_type == "har" ? compact([
    local.enable_eks ? "harness-demo-${var.owner}" : "",
    local.enable_eks && var.create_prod_environment ? "harness-demo-${var.owner}-prod" : ""
  ]) : []

  # Generate the dockercfg JSON for HAR authentication
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

resource "kubernetes_namespace" "app_namespace" {
  for_each = toset(local.har_namespaces)

  metadata {
    name = each.value
    labels = {
      "app.kubernetes.io/managed-by" = "tofu"
      "harness.io/owner"             = var.owner
    }
  }

  depends_on = [module.eks]
}



resource "kubernetes_secret" "har_pull_secret" {
  for_each = toset(local.har_namespaces)

  metadata {
    name      = "${var.owner}demoapp-dockercfg"
    namespace = each.value

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

  depends_on = [kubernetes_namespace.app_namespace]
}

################################################################################
# Harness Pipelines
################################################################################

################################################################################
# Harness ASG Pipelines
################################################################################

module "harness_pipelines_asg" {
  source = "../../modules/harness-pipeline"
  count  = local.enable_asg && var.create_harness_service && var.create_harness_environment ? 1 : 0

  org_id     = local.resolved_org_id
  project_id = local.resolved_project_id

  # Required by module but unused for ASG-only pipelines
  service_ref        = ""
  environment_ref    = var.create_harness_environment ? "${var.owner}_dev" : ""
  environment_name   = "Dev"
  infrastructure_ref = ""

  # ASG strategy pipeline
  create_asg_strategy_pipeline      = var.create_asg_strategy_pipeline
  asg_strategy_pipeline_id          = "${var.owner}_asg_strategy_deploy"
  asg_strategy_pipeline_name        = "${title(var.owner)} Application Delivery - ASG"
  asg_strategy_pipeline_description = "Unified ASG deployment pipeline with runtime strategy selection for customer demos"
  asg_service_ref                   = "${var.owner}_demo_app_asg"
  asg_infrastructure_ref            = "${var.owner}_asg_dev"
  asg_canary_instance_count         = var.asg_canary_instance_count
  asg_prod_asg_name                 = local.enable_asg && length(module.asg) > 0 ? replace(module.asg[0].base_asg_name, "-base", "") : ""

  # ALB configuration for Blue-Green deployments
  asg_alb_name                = local.enable_asg && length(module.asg) > 0 ? module.asg[0].alb_name : ""
  asg_prod_listener_arn       = local.enable_asg && length(module.asg) > 0 ? module.asg[0].prod_listener_arn : ""
  asg_prod_listener_rule_arn  = local.enable_asg && length(module.asg) > 0 ? module.asg[0].prod_listener_rule_arn : ""
  asg_stage_listener_arn      = local.enable_asg && length(module.asg) > 0 ? module.asg[0].stage_listener_arn : ""
  asg_stage_listener_rule_arn = local.enable_asg && length(module.asg) > 0 ? module.asg[0].stage_listener_rule_arn : ""

  # Disable all K8s pipelines for this ASG-only module
  create_canary_pipeline     = false
  create_blue_green_pipeline = false
  create_strategy_pipeline   = false

  # EKS Docker CI pipeline is NOT created for ASG-only deployments
  create_ci_pipeline = false

  # ASG CI pipeline: Gradle + CI Intelligence + security scans → Packer AMI build (separate from EKS Docker CI pipeline)
  create_asg_ci_pipeline      = (local.enable_asg && !(local.enable_eks || local.enable_ecs || local.enable_lambda)) ? var.create_asg_ci_pipeline : false
  asg_ci_pipeline_id          = "${var.owner}_asg_ci_build"
  asg_ci_pipeline_name        = "${title(var.owner)} ASG CI Build"
  asg_ci_pipeline_description = "Enterprise CI pipeline: Gradle build, Test Intelligence, Security Scanning, and Packer AMI bake"
  git_connector_ref           = var.create_connectors && var.github_token_ref != "" ? "${var.owner}_github_reference_architecture" : var.github_connector_ref
  git_repo_name               = var.github_repo_name
  har_registry_ref            = var.artifact_registry_type == "har" ? "har-${var.owner}" : ""
  har_upstream_proxy_ref      = var.artifact_registry_type == "har" && var.create_dockerhub_upstream ? "${var.owner}-dockerhub-proxy" : ""
  har_image_name              = "${var.owner}demoapp"
  use_harness_code            = var.import_to_harness_code
  harness_code_repo_name      = var.import_to_harness_code ? "${var.owner}-demo-app" : ""
  harness_account_id          = var.harness_account_id
  harness_org_id              = local.resolved_org_id
  harness_project_id          = local.resolved_project_id
  harness_api_key             = var.harness_api_key

  asg_packer_owner          = var.owner
  asg_packer_region         = "us-east-1"
  asg_aws_access_key_secret = "aws_access_key_id"
  asg_aws_secret_key_secret = "aws_secret_access_key"

  delegate_selector = "delegate-${var.owner}"
  pipeline_tags     = ["tofu-managed:true", "owner:${var.owner}", "deployment-target:asg"]

  depends_on = [module.harness_service_asg, module.harness_environment_dev]
}

module "harness_pipelines_dev" {
  source = "../../modules/harness-pipeline"
  count  = var.create_harness_service && var.create_harness_environment && (local.enable_eks || local.enable_ecs || local.enable_lambda) ? 1 : 0

  org_id             = local.resolved_org_id
  project_id         = local.resolved_project_id
  service_ref        = var.create_harness_service ? "${var.owner}_demo_app" : ""
  environment_ref    = var.create_harness_environment ? "${var.owner}_dev" : ""
  environment_name   = "Dev"
  infrastructure_ref = local.enable_eks ? "${var.owner}_k8s_dev" : ""

  # Strategy Choice pipeline (single pipeline with runtime strategy selection)
  create_strategy_pipeline      = var.create_strategy_pipeline
  strategy_pipeline_id          = "${var.owner}_k8s_strategy_deploy"
  strategy_pipeline_name        = "${title(var.owner)} Application Delivery"
  strategy_pipeline_description = "Unified deployment pipeline with runtime strategy selection for customer demos"

  create_standard_ci_gradle      = var.create_standard_ci_gradle
  standard_ci_gradle_id          = "${var.owner}_standard_ci_gradle"
  standard_ci_gradle_name        = "${title(var.owner)} Standard CI - Gradle"
  standard_ci_gradle_description = "Enterprise CI pipeline: Gradle build, Test Intelligence, Security Scanning (SAST/SCA/Trivy), Supply Chain (SBOM/SLSA)"
  standard_ci_gradle_test_packages = "io.harness.demo"

  create_ci_pipeline = false
  create_canary_pipeline = false
  create_blue_green_pipeline = false
  git_connector_ref       = var.create_connectors && var.github_token_ref != "" ? "${var.owner}_github_reference_architecture" : var.github_connector_ref
  git_repo_name           = var.github_repo_name
  har_registry_ref        = var.artifact_registry_type == "har" ? "har-${var.owner}" : ""
  har_upstream_proxy_ref  = var.artifact_registry_type == "har" && var.create_dockerhub_upstream ? "${var.owner}-dockerhub-proxy" : ""
  har_image_name          = "${var.owner}demoapp"

  # Harness Code Repository (replaces GitHub as CI source when enabled)
  use_harness_code       = var.import_to_harness_code
  harness_code_repo_name = var.import_to_harness_code ? "${var.owner}-demo-app" : ""
  harness_account_id     = var.harness_account_id
  harness_org_id         = local.resolved_org_id
  harness_project_id     = local.resolved_project_id
  harness_api_key        = var.harness_api_key

  delegate_selector = "delegate-${var.owner}"

  pipeline_tags = ["tofu-managed:true", "owner:${var.owner}"]

  depends_on = [module.harness_service, module.harness_environment_dev, module.harness_environment_prod, module.harness_monitored_service_dev, module.har, module.harness_code_repo, module.asg, module.harness_service_asg]
}

################################################################################
# Harness Monitored Service (for Continuous Verification)
################################################################################

module "harness_monitored_service_dev" {
  source = "../../modules/harness-monitored-service"
  count  = var.enable_cv && var.create_harness_service && var.create_harness_environment ? 1 : 0

  org_id     = local.resolved_org_id
  project_id = local.resolved_project_id

  monitored_service_id          = "${var.owner}_demo_app_dev"
  monitored_service_name        = "${title(var.owner)} Demo App - Dev"
  monitored_service_description = "Monitored service for CV on ${var.owner} demo app in Dev"

  service_ref     = "${var.owner}_demo_app"
  environment_ref = "${var.owner}_dev"

  # Prometheus health source - use auto-created connector or explicit ref
  prometheus_connector_ref = var.prometheus_url != "" ? "${var.owner}_prometheus" : var.prometheus_connector_ref
  enable_live_monitoring   = true

  # Application details for metric queries
  namespace = "harness-demo-${var.owner}"
  app_name  = "harness-demo-app"

  # Thresholds
  memory_threshold_bytes = 536870912 # 512MB

  tags = ["tofu-managed", var.owner, "cv"]

  depends_on = [module.harness_service, module.harness_environment_dev]
}
