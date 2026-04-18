terraform {
  required_version = ">= 1.6.0"

  required_providers {
    harness = {
      source  = "harness/harness"
      version = "~> 0.30"
    }
  }
}

provider "harness" {
  endpoint         = var.harness_endpoint
  account_id       = var.harness_account_id
  platform_api_key = var.harness_api_key
}

locals {
  factory_tags = ["tofu-managed", "project-factory", var.harness_project_id]
  project_title = title(replace(var.harness_project_id, "_", " "))

  shared_aws_connector_id = var.shared_aws_connector_id != "" ? var.shared_aws_connector_id : "${var.harness_project_id}_aws_reference_architecture"
  shared_aws_connector_name = var.shared_aws_connector_name != "" ? var.shared_aws_connector_name : "${local.project_title} AWS Reference Architecture"
  shared_aws_connector_description = var.shared_aws_connector_description != "" ? var.shared_aws_connector_description : "Project-scoped shared AWS connector for ${var.harness_org_id}/${var.harness_project_id}"

  shared_github_connector_id = var.shared_github_connector_id != "" ? var.shared_github_connector_id : "${var.harness_project_id}_github_reference_architecture"
  shared_github_connector_name = var.shared_github_connector_name != "" ? var.shared_github_connector_name : "${local.project_title} GitHub Reference Architecture"

  should_create_shared_aws_connector    = var.create_shared_aws_connector
  should_create_shared_github_connector = var.create_shared_github_connector && var.shared_github_token_ref != ""
}

module "harness_org_project" {
  source = "../../modules/harness-org-project"

  create_organization      = var.create_harness_org
  existing_org_id          = var.harness_org_id
  organization_id          = var.harness_org_id
  organization_name        = title(replace(var.harness_org_id, "_", " "))
  organization_description = "Project-scoped factory bootstrap for ${var.harness_org_id}"

  create_project      = var.create_harness_project
  existing_project_id = var.harness_project_id
  project_id          = var.harness_project_id
  project_name        = title(replace(var.harness_project_id, "_", " "))
  project_description = "Project-scoped factory bootstrap for ${var.harness_project_id}"

  tags = local.factory_tags
}

locals {
  resolved_org_id     = module.harness_org_project.org_id
  resolved_project_id = module.harness_org_project.project_id
}

module "harness_connectors" {
  source = "../../modules/harness-connectors"

  environment_name   = "${var.harness_project_id}-factory"
  harness_org_id     = local.resolved_org_id
  harness_project_id = local.resolved_project_id
  delegate_selectors = [var.shared_delegate_selector]
  connector_tags     = local.factory_tags

  create_k8s_connector = false

  create_aws_connector          = local.should_create_shared_aws_connector
  aws_connector_id              = local.shared_aws_connector_id
  aws_connector_name            = local.shared_aws_connector_name
  aws_connector_description     = local.shared_aws_connector_description
  aws_region                    = var.shared_aws_region
  aws_auth_type                 = var.shared_aws_auth_type
  aws_access_key_ref            = var.shared_aws_access_key_ref
  aws_secret_key_ref            = var.shared_aws_secret_key_ref
  enable_cross_account_access   = var.shared_enable_cross_account_access
  cross_account_role_arn        = var.shared_cross_account_role_arn
  cross_account_external_id     = var.shared_cross_account_external_id

  create_docker_connector = false

  create_github_connector = local.should_create_shared_github_connector
  github_connector_id     = local.shared_github_connector_id
  github_connector_name   = local.shared_github_connector_name
  github_url              = var.shared_github_url
  github_connection_type  = var.shared_github_connection_type
  github_validation_repo  = var.shared_github_validation_repo
  github_token_ref        = var.shared_github_token_ref
  github_username         = var.shared_github_username

  create_prometheus_connector = false

  depends_on = [module.harness_org_project]
}
