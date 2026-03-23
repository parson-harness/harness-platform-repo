################################################################################
# Harness Pipeline Module Variables
################################################################################

variable "org_id" {
  description = "Harness organization ID"
  type        = string
}

variable "project_id" {
  description = "Harness project ID"
  type        = string
}

variable "service_ref" {
  description = "Reference to the Harness service"
  type        = string
}

variable "environment_ref" {
  description = "Reference to the Harness environment"
  type        = string
}

variable "environment_name" {
  description = "Environment name for display"
  type        = string
}

variable "infrastructure_ref" {
  description = "Reference to the infrastructure definition"
  type        = string
}

################################################################################
# Canary Pipeline Variables (DEPRECATED - use Strategy Pipeline instead)
################################################################################

variable "create_canary_pipeline" {
  description = "DEPRECATED: Create standalone Canary pipeline. Use create_strategy_pipeline instead with deployment_strategy=canary"
  type        = bool
  default     = false
}

variable "canary_pipeline_id" {
  description = "Identifier for Canary pipeline"
  type        = string
  default     = "k8s_canary_deploy"
}

variable "canary_pipeline_name" {
  description = "Name for Canary pipeline"
  type        = string
  default     = "K8s Canary Deploy"
}

variable "canary_pipeline_description" {
  description = "Description for Canary pipeline"
  type        = string
  default     = "Deploys to Kubernetes using Canary strategy with Continuous Verification"
}

variable "canary_instance_count" {
  description = "Number of canary instances to deploy"
  type        = number
  default     = 1
}

variable "cv_sensitivity" {
  description = "Continuous Verification sensitivity (High, Medium, Low)"
  type        = string
  default     = "Medium"
}

variable "cv_duration" {
  description = "Continuous Verification duration"
  type        = string
  default     = "5m"
}

variable "enable_cv" {
  description = "Enable Continuous Verification step in canary pipeline"
  type        = bool
  default     = false
}

variable "monitored_service_ref" {
  description = "Reference to the monitored service for CV"
  type        = string
  default     = ""
}

################################################################################
# Blue/Green + Canary Pipeline Variables (2-stage)
################################################################################

variable "create_blue_green_pipeline" {
  description = "Create Blue/Green + Canary deployment pipeline (2-stage: B/G to Dev, Canary to Prod)"
  type        = bool
  default     = false
}

variable "blue_green_pipeline_id" {
  description = "Identifier for Blue/Green + Canary pipeline"
  type        = string
  default     = "k8s_blue_green_canary_deploy"
}

variable "blue_green_pipeline_name" {
  description = "Name for Blue/Green + Canary pipeline"
  type        = string
  default     = "K8s Blue/Green + Canary Deploy"
}

variable "blue_green_pipeline_description" {
  description = "Description for Blue/Green + Canary pipeline"
  type        = string
  default     = "2-stage deployment: Blue/Green to Dev, then Canary to Prod"
}

variable "prod_environment_ref" {
  description = "Reference to the Prod Harness environment (for 2nd stage)"
  type        = string
  default     = ""
}

variable "prod_infrastructure_ref" {
  description = "Reference to the Prod infrastructure definition (for 2nd stage)"
  type        = string
  default     = ""
}

################################################################################
# Strategy Choice Pipeline Variables (Single pipeline with runtime strategy selection)
################################################################################

variable "create_strategy_pipeline" {
  description = "Create single pipeline with runtime strategy selection (blue-green, canary, rolling)"
  type        = bool
  default     = true
}

variable "strategy_pipeline_id" {
  description = "Identifier for Strategy Choice pipeline"
  type        = string
  default     = "k8s_strategy_deploy"
}

variable "strategy_pipeline_name" {
  description = "Name for Strategy Choice pipeline"
  type        = string
  default     = "K8s Deploy with Strategy Choice"
}

variable "strategy_pipeline_description" {
  description = "Description for Strategy Choice pipeline"
  type        = string
  default     = "Single pipeline with runtime strategy selection - Blue/Green, Canary, or Rolling"
}

################################################################################
# CI Pipeline Variables
################################################################################

variable "create_ci_pipeline" {
  description = "Create CI build pipeline"
  type        = bool
  default     = true
}

variable "ci_pipeline_id" {
  description = "Identifier for CI pipeline"
  type        = string
  default     = "ci_build"
}

variable "ci_pipeline_name" {
  description = "Name for CI pipeline"
  type        = string
  default     = "CI Build"
}

variable "ci_pipeline_description" {
  description = "Description for CI pipeline"
  type        = string
  default     = "Builds Docker image and pushes to Harness Artifact Registry"
}

variable "git_connector_ref" {
  description = "Reference to the Git connector for codebase"
  type        = string
  default     = ""
}

variable "git_repo_name" {
  description = "Git repository name"
  type        = string
  default     = ""
}

variable "har_registry_ref" {
  description = "Reference to the HAR registry"
  type        = string
  default     = ""
}

variable "har_image_name" {
  description = "Image name in HAR (without registry prefix)"
  type        = string
  default     = "demo-app"
}

variable "har_upstream_proxy_ref" {
  description = "Reference to the HAR upstream proxy registry (for pulling base images like maven through HAR)"
  type        = string
  default     = ""
}

################################################################################
# Trigger Variables
################################################################################

variable "create_ci_completion_trigger" {
  description = "Create webhook trigger on CD pipeline for auto-deploy from CI"
  type        = bool
  default     = true
}

variable "ci_completion_trigger_enabled" {
  description = "Enable the auto-deploy webhook trigger"
  type        = bool
  default     = true
}

################################################################################
# Harness Code Repository Variables (for CI pipeline source)
################################################################################

variable "use_harness_code" {
  description = "Use Harness Code repo as CI pipeline source instead of GitHub"
  type        = bool
  default     = false
}

variable "harness_code_repo_name" {
  description = "Harness Code repo identifier (e.g., owner-demo-app)"
  type        = string
  default     = ""
}

variable "harness_account_id" {
  description = "Harness account ID (needed to build HCR git URL)"
  type        = string
  default     = ""
}

variable "harness_org_id" {
  description = "Harness org ID (needed to build HCR git URL)"
  type        = string
  default     = ""
}

variable "harness_project_id" {
  description = "Harness project ID (needed to build HCR git URL)"
  type        = string
  default     = ""
}

variable "harness_api_key" {
  description = "Harness API key for authenticating git clone from Harness Code"
  type        = string
  default     = ""
  sensitive   = true
}

################################################################################
# ASG CI Integration - Packer AMI Build Variables
# When enabled, CI pipeline adds a Packer build step after the JAR build.
# The resulting AMI name is passed as image_tag to the ASG CD pipeline.
################################################################################

variable "asg_packer_build_enabled" {
  description = "Deprecated: Packer build now has its own pipeline (asg_ci_build). This variable is no longer used."
  type        = bool
  default     = false
}

variable "asg_packer_owner" {
  description = "Owner value baked into AMI tags and name (e.g., SE username)"
  type        = string
  default     = ""
}

variable "asg_packer_region" {
  description = "AWS region in which to build and register the AMI"
  type        = string
  default     = "us-east-1"
}

variable "asg_aws_access_key_secret" {
  description = "Name of the Harness secret holding AWS_ACCESS_KEY_ID for Packer builds"
  type        = string
  default     = "aws_access_key_id"
}

variable "asg_aws_secret_key_secret" {
  description = "Name of the Harness secret holding AWS_SECRET_ACCESS_KEY for Packer builds"
  type        = string
  default     = "aws_secret_access_key"
}

################################################################################
# ASG CI Pipeline Variables
################################################################################

variable "create_asg_ci_pipeline" {
  description = "Create ASG CI pipeline (Maven build + Packer AMI — separate from EKS Docker CI pipeline)"
  type        = bool
  default     = false
}

variable "asg_ci_pipeline_id" {
  description = "Identifier for the ASG CI pipeline"
  type        = string
  default     = "asg_ci_build"
}

variable "asg_ci_pipeline_name" {
  description = "Display name for the ASG CI pipeline"
  type        = string
  default     = "ASG CI Build"
}

variable "asg_ci_pipeline_description" {
  description = "Description for the ASG CI pipeline"
  type        = string
  default     = "Builds Java JAR and bakes it into an AWS AMI using Packer"
}

################################################################################
# ASG Strategy Pipeline Variables
################################################################################

variable "create_asg_strategy_pipeline" {
  description = "Create ASG strategy pipeline (Blue-Green, Canary, Rolling)"
  type        = bool
  default     = false
}

variable "asg_strategy_pipeline_id" {
  description = "Identifier for the ASG strategy pipeline"
  type        = string
  default     = "asg_strategy_deploy"
}

variable "asg_strategy_pipeline_name" {
  description = "Name for the ASG strategy pipeline"
  type        = string
  default     = "ASG Deploy with Strategy Choice"
}

variable "asg_strategy_pipeline_description" {
  description = "Description for the ASG strategy pipeline"
  type        = string
  default     = "Single pipeline with runtime strategy selection for ASG - Blue/Green, Canary, or Rolling"
}

variable "asg_service_ref" {
  description = "Reference to the Harness ASG service"
  type        = string
  default     = ""
}

variable "asg_infrastructure_ref" {
  description = "Reference to the ASG infrastructure definition"
  type        = string
  default     = ""
}

variable "asg_canary_instance_count" {
  description = "Number of canary instances to deploy in the canary ASG"
  type        = number
  default     = 1
}

variable "asg_prod_asg_name" {
  description = "Name of the Harness-managed production ASG (required when baseAsgName is set in infrastructure). Typically the base ASG name without the -base suffix."
  type        = string
  default     = ""
}

################################################################################
# Common Variables
################################################################################

variable "delegate_selector" {
  description = "Delegate selector tag/name to pin all K8s pipeline stages to the correct EKS delegate (e.g. delegate-alice)"
  type        = string
  default     = ""
}

variable "pipeline_tags" {
  description = "Tags to apply to pipelines"
  type        = list(string)
  default     = []
}
