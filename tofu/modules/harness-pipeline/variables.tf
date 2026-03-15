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
# Canary Pipeline Variables
################################################################################

variable "create_canary_pipeline" {
  description = "Create Canary deployment pipeline"
  type        = bool
  default     = true
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
# Common Variables
################################################################################

variable "pipeline_tags" {
  description = "Tags to apply to pipelines"
  type        = list(string)
  default     = []
}
