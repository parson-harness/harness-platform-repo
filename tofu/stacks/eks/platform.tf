################################################################################
# Local Variables
################################################################################

module "sandbox_context" {
  source = "../../modules/sandbox-context"

  owner                 = var.owner
  environment           = var.environment
  stack                 = "eks"
  workspace_id          = var.workspace_id
  workspace_template_id = var.workspace_template_id
}

locals {
  owner_title                = module.sandbox_context.owner_title
  name_prefix                = module.sandbox_context.name_prefix
  delegate_selector          = module.sandbox_context.delegate_selector
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

  common_tag_values          = module.sandbox_context.common_tag_values
  common_tags                = module.sandbox_context.common_tags
  common_tags_with_workspace = module.sandbox_context.common_tags_with_workspace
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
  project_name        = var.new_harness_project_name != "" ? var.new_harness_project_name : "${local.owner_title} Demo"
  project_description = "Demo project for ${var.owner}"

  tags = local.common_tag_values
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
  connector_tags            = concat(["tofu-managed:true", "owner:${var.owner}", "stack:eks"], local.common_tag_values)
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
# OPA Policies - CI/CD Governance
# Creates policies for CI standards, security, and quality gates
################################################################################

module "opa_policies" {
  source = "../../modules/harness-opa-policies"
  count  = var.create_opa_policies ? 1 : 0

  org_id     = local.resolved_org_id
  project_id = local.resolved_project_id

  # Policy creation flags
  create_ci_policies                = true
  create_security_policies          = true
  create_quality_policies           = true
  create_change_governance_policies = var.manage_shared_change_governance

  # Policy set creation flags
  create_ci_policy_set                = true
  create_security_policy_set          = true
  create_quality_policy_set           = true
  create_change_governance_policy_set = var.manage_shared_change_governance

  # Enforcement flags
  enforce_ci_policies                = var.enforce_ci_policies
  enforce_security_policies          = var.enforce_security_policies
  enforce_quality_policies           = var.enforce_quality_policies
  enforce_change_governance_policies = var.manage_shared_change_governance

  depends_on = [module.harness_org_project]
}
