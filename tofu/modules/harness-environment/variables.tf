################################################################################
# Required Variables
################################################################################

variable "environment_id" {
  description = "Identifier for the environment (lowercase, underscores)"
  type        = string
}

variable "environment_name" {
  description = "Display name for the environment"
  type        = string
}

variable "org_id" {
  description = "Harness Organization ID"
  type        = string
}

variable "project_id" {
  description = "Harness Project ID"
  type        = string
}

################################################################################
# Environment Configuration
################################################################################

variable "environment_description" {
  description = "Description of the environment"
  type        = string
  default     = ""
}

variable "environment_type" {
  description = "Environment type: PreProduction or Production"
  type        = string
  default     = "PreProduction"

  validation {
    condition     = contains(["PreProduction", "Production"], var.environment_type)
    error_message = "environment_type must be PreProduction or Production"
  }
}

variable "environment_color" {
  description = "Color for the environment in Harness UI"
  type        = string
  default     = "#0063F7"
}

variable "tags" {
  description = "Tags for the environment (format: key:value)"
  type        = list(string)
  default     = ["tofu-managed"]
}

variable "environment_variables" {
  description = "Environment-level variables"
  type = list(object({
    name  = string
    type  = string
    value = string
  }))
  default = []
}

variable "overrides" {
  description = "Service overrides for this environment"
  type        = any
  default     = null
}

variable "allow_simultaneous_deployments" {
  description = "Allow simultaneous deployments to this infrastructure"
  type        = bool
  default     = false
}

################################################################################
# Kubernetes Infrastructure
################################################################################

variable "create_k8s_infrastructure" {
  description = "Create Kubernetes infrastructure definition"
  type        = bool
  default     = true
}

variable "k8s_infra_id" {
  description = "Identifier for K8s infrastructure"
  type        = string
  default     = "k8s_infra"
}

variable "k8s_infra_name" {
  description = "Display name for K8s infrastructure"
  type        = string
  default     = "Kubernetes Infrastructure"
}

variable "k8s_connector_ref" {
  description = "Reference to Kubernetes connector"
  type        = string
  default     = ""
}

variable "k8s_namespace" {
  description = "Kubernetes namespace for deployments"
  type        = string
  default     = "default"
}

variable "k8s_release_name" {
  description = "Helm release name (leave empty for auto-generated)"
  type        = string
  default     = ""
}

################################################################################
# ECS Infrastructure
################################################################################

variable "create_ecs_infrastructure" {
  description = "Create ECS infrastructure definition"
  type        = bool
  default     = false
}

variable "ecs_infra_id" {
  description = "Identifier for ECS infrastructure"
  type        = string
  default     = "ecs_infra"
}

variable "ecs_infra_name" {
  description = "Display name for ECS infrastructure"
  type        = string
  default     = "ECS Infrastructure"
}

variable "ecs_cluster_name" {
  description = "ECS cluster name"
  type        = string
  default     = ""
}

################################################################################
# Lambda Infrastructure
################################################################################

variable "create_lambda_infrastructure" {
  description = "Create Lambda infrastructure definition"
  type        = bool
  default     = false
}

variable "lambda_infra_id" {
  description = "Identifier for Lambda infrastructure"
  type        = string
  default     = "lambda_infra"
}

variable "lambda_infra_name" {
  description = "Display name for Lambda infrastructure"
  type        = string
  default     = "Lambda Infrastructure"
}

variable "lambda_stage" {
  description = "Lambda deployment stage"
  type        = string
  default     = "dev"
}

################################################################################
# AWS Configuration (shared by ECS/Lambda)
################################################################################

variable "aws_connector_ref" {
  description = "Reference to AWS connector"
  type        = string
  default     = ""
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}
