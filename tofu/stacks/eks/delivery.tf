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
