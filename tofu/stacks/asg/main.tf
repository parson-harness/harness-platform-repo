################################################################################
# ASG Stack - Harness Entities for EC2 Auto Scaling Group Deployments
#
# This stack provisions:
#   - AWS infrastructure: VPC, ALB, ASG, Launch Template
#   - Harness entities: Service, Environment, Pipelines
#
# Use Cases:
#   - ASG deployments with Blue/Green, Canary, or Rolling strategies
#   - Packer-built AMIs (JAR baked into AMI, no Docker)
#
# Prerequisites:
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
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

################################################################################
# Providers
################################################################################

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
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

  common_tags = {
    Project     = "harness-demo"
    Environment = var.environment
    ManagedBy   = "tofu"
    Owner       = var.owner
    Stack       = "asg"
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

  tags = ["tofu-managed", var.owner, "asg"]
}

locals {
  resolved_org_id     = module.harness_org_project.org_id
  resolved_project_id = module.harness_org_project.project_id
}

################################################################################
# AWS Infrastructure - VPC, ALB, ASG
################################################################################

module "asg" {
  source = "../../modules/asg"

  name_prefix   = local.name_prefix
  owner         = var.owner
  aws_region    = var.aws_region
  vpc_cidr      = var.vpc_cidr
  instance_type = var.instance_type

  asg_min_size         = var.asg_min_size
  asg_desired_capacity = var.asg_desired_capacity
  asg_max_size         = var.asg_max_size

  create_dns_record = var.create_dns_record
  route53_zone_name = var.route53_zone_name
  acm_cert_arn      = var.acm_cert_arn

  tags = local.common_tags
}

################################################################################
# IAM User + Harness Secrets for Packer CI Builds
################################################################################

resource "aws_iam_user" "packer_ci" {
  name = "harness-packer-ci-${var.owner}"
  tags = local.common_tags
}

resource "aws_iam_user_policy" "packer_ci" {
  name = "harness-packer-ci-policy"
  user = aws_iam_user.packer_ci.name
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
  user = aws_iam_user.packer_ci.name
}

resource "harness_platform_secret_text" "packer_aws_access_key" {
  identifier = "aws_access_key_id"
  name       = "AWS-Access-Key-ID-Packer"
  org_id     = local.resolved_org_id
  project_id = local.resolved_project_id

  secret_manager_identifier = "harnessSecretManager"
  value_type                = "Inline"
  value                     = aws_iam_access_key.packer_ci.id

  depends_on = [aws_iam_access_key.packer_ci]
}

resource "harness_platform_secret_text" "packer_aws_secret_key" {
  identifier = "aws_secret_access_key"
  name       = "AWS-Secret-Access-Key-Packer"
  org_id     = local.resolved_org_id
  project_id = local.resolved_project_id

  secret_manager_identifier = "harnessSecretManager"
  value_type                = "Inline"
  value                     = aws_iam_access_key.packer_ci.secret

  depends_on = [aws_iam_access_key.packer_ci]
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

  # AWS Connector (for AMI artifact resolution)
  create_aws_connector        = true
  aws_connector_id            = "${var.owner}_aws_reference_architecture"
  aws_connector_name          = "${title(var.owner)} AWS Reference Architecture"
  aws_connector_description   = "AWS connector for ${title(var.owner)} ASG stack"
  connector_tags              = ["tofu-managed:true", "owner:${var.owner}", "stack:asg"]
  aws_auth_type               = var.aws_auth_type
  aws_region                  = var.aws_region
  enable_cross_account_access = var.enable_cross_account_access
  cross_account_role_arn      = var.cross_account_role_arn
  cross_account_external_id   = var.cross_account_external_id

  # GitHub Connector
  create_github_connector = var.github_token_ref != ""
  github_connector_id     = "${var.owner}_github_reference_architecture"
  github_connector_name   = "${title(var.owner)} GitHub Reference Architecture"
  github_url              = var.github_url
  github_username         = var.github_username
  github_token_ref        = var.github_token_ref

  # No K8s or Docker connectors for ASG
  create_k8s_connector    = false
  create_docker_connector = false

  depends_on = [module.harness_org_project]
}

################################################################################
# Harness ASG Service
################################################################################

module "harness_service_asg" {
  source = "../../modules/harness-service"

  service_id          = "${var.owner}_demo_app_asg"
  service_name        = "${title(var.owner)} Demo App ASG"
  service_description = "ASG demo application for ${var.owner} - Blue/Green, Canary, Rolling on EC2"
  org_id              = local.resolved_org_id
  project_id          = local.resolved_project_id

  deployment_type = "Asg"

  # ASG artifact = Packer-built AMI
  artifact_registry_type = "ecr"  # Uses AWS connector for AMI resolution
  artifact_connector_ref = "${var.owner}_aws_reference_architecture"
  aws_region             = var.aws_region
  asg_ami_owner_tag      = var.owner

  # Startup script in repo
  asg_startup_script_path = "asg/user-data.sh"
  manifest_store_type     = var.use_harness_code ? "HarnessCode" : "Github"
  git_connector_ref       = var.use_harness_code ? "" : (
    var.github_token_ref != "" ? "${var.owner}_github_reference_architecture" : var.github_connector_ref
  )
  git_repo_name          = var.use_harness_code ? "" : var.github_repo_name
  harness_code_repo_name = var.use_harness_code ? "${var.owner}-demo-app" : ""
  git_branch             = var.git_branch

  tags = ["tofu-managed", var.owner, "asg"]

  service_variables = [
    {
      name  = "appUrl"
      type  = "String"
      value = module.asg.app_url
    },
    {
      name  = "stageUrl"
      type  = "String"
      value = module.asg.stage_url
    },
    {
      name  = "instanceProfileName"
      type  = "String"
      value = module.asg.instance_profile_name
    },
    {
      name  = "securityGroupId"
      type  = "String"
      value = module.asg.instance_security_group_id
    },
    {
      name  = "subnetIds"
      type  = "String"
      value = join(",", module.asg.public_subnet_ids)
    },
    {
      name  = "baseAsgName"
      type  = "String"
      value = module.asg.base_asg_name
    }
  ]

  depends_on = [module.harness_connectors, module.asg]
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

  # ASG infrastructure
  create_asg_infrastructure = true
  asg_infra_id              = "${var.owner}_asg_dev"
  asg_infra_name            = "${title(var.owner)} ASG Dev"
  aws_connector_ref         = "${var.owner}_aws_reference_architecture"
  aws_region                = var.aws_region
  asg_base_asg_name         = module.asg.base_asg_name
  asg_load_balancer_name    = module.asg.alb_name
  asg_prod_listener_arn     = module.asg.prod_listener_arn
  asg_stage_listener_arn    = module.asg.stage_listener_arn

  # No K8s, ECS, or Lambda infrastructure
  create_k8s_infrastructure    = false
  create_ecs_infrastructure    = false
  create_lambda_infrastructure = false

  tags = ["tofu-managed", var.owner, "asg"]

  depends_on = [module.harness_connectors, module.asg]
}

################################################################################
# Harness Pipelines
################################################################################

module "harness_pipelines_asg" {
  source = "../../modules/harness-pipeline"

  org_id             = local.resolved_org_id
  project_id         = local.resolved_project_id

  # Required by module but unused for ASG-only pipelines
  service_ref        = ""
  environment_ref    = "${var.owner}_dev"
  environment_name   = "Dev"
  infrastructure_ref = ""

  # ASG strategy pipeline
  create_asg_strategy_pipeline      = var.create_asg_strategy_pipeline
  asg_strategy_pipeline_id          = "${var.owner}_asg_strategy_deploy"
  asg_strategy_pipeline_name        = "${title(var.owner)} ASG Deploy with Strategy Choice"
  asg_strategy_pipeline_description = "Single pipeline with runtime strategy selection for ASG - Blue/Green, Canary, or Rolling"
  asg_service_ref                   = "${var.owner}_demo_app_asg"
  asg_infrastructure_ref            = "${var.owner}_asg_dev"
  asg_canary_instance_count         = var.asg_canary_instance_count
  asg_prod_asg_name                 = replace(module.asg.base_asg_name, "-base", "")

  # ALB configuration for Blue-Green deployments
  asg_alb_name                = module.asg.alb_name
  asg_prod_listener_arn       = module.asg.prod_listener_arn
  asg_prod_listener_rule_arn  = module.asg.prod_listener_rule_arn
  asg_stage_listener_arn      = module.asg.stage_listener_arn
  asg_stage_listener_rule_arn = module.asg.stage_listener_rule_arn

  # Disable all K8s pipelines
  create_canary_pipeline     = false
  create_blue_green_pipeline = false
  create_strategy_pipeline   = false
  create_ci_pipeline         = false

  # ASG CI pipeline: Maven → Packer AMI build
  create_asg_ci_pipeline      = var.create_asg_ci_pipeline
  asg_ci_pipeline_id          = "${var.owner}_asg_ci_build"
  asg_ci_pipeline_name        = "${title(var.owner)} ASG CI Build"
  asg_ci_pipeline_description = "Builds Java JAR and bakes into AWS AMI using Packer"
  git_connector_ref           = var.github_token_ref != "" ? "${var.owner}_github_reference_architecture" : var.github_connector_ref
  git_repo_name               = var.github_repo_name
  use_harness_code            = var.use_harness_code
  harness_code_repo_name      = var.use_harness_code ? "${var.owner}-demo-app" : ""
  harness_account_id          = var.harness_account_id
  harness_org_id              = local.resolved_org_id
  harness_project_id          = local.resolved_project_id
  harness_api_key             = var.harness_api_key

  asg_packer_owner          = var.owner
  asg_packer_region         = var.aws_region
  asg_aws_access_key_secret = "aws_access_key_id"
  asg_aws_secret_key_secret = "aws_secret_access_key"

  delegate_selector = local.delegate_selector
  pipeline_tags     = ["tofu-managed", var.owner, "asg"]

  # HAR not used for ASG
  har_registry_ref       = ""
  har_upstream_proxy_ref = ""
  har_image_name         = ""

  depends_on = [module.harness_service_asg, module.harness_environment_dev]
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
  description = "Harness ASG service ID"
  value       = module.harness_service_asg.service_id
}

output "environment_id" {
  description = "Harness environment ID"
  value       = module.harness_environment_dev.environment_id
}

output "app_url" {
  description = "Production application URL"
  value       = module.asg.app_url
}

output "stage_url" {
  description = "Stage application URL"
  value       = module.asg.stage_url
}

output "alb_name" {
  description = "ALB name"
  value       = module.asg.alb_name
}

output "base_asg_name" {
  description = "Base ASG name"
  value       = module.asg.base_asg_name
}

output "prod_asg_name" {
  description = "Production ASG name (Harness-managed)"
  value       = replace(module.asg.base_asg_name, "-base", "")
}
