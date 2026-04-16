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

  tags = local.common_tags_with_workspace
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
