################################################################################
# General Variables
################################################################################

variable "environment_name" {
  description = "Name of the environment (e.g., sandbox, pov-acme)"
  type        = string
}

variable "harness_org_id" {
  description = "Harness Organization ID"
  type        = string
}

variable "harness_project_id" {
  description = "Harness Project ID"
  type        = string
}

variable "delegate_selectors" {
  description = "Delegate selectors for connectors"
  type        = list(string)
}

variable "connector_tags" {
  description = "Tags to apply to all connectors"
  type        = list(string)
  default     = ["tofu-managed"]
}

################################################################################
# Kubernetes Connector Variables
################################################################################

variable "create_k8s_connector" {
  description = "Create a Kubernetes cluster connector"
  type        = bool
  default     = true
}

variable "k8s_connector_id" {
  description = "Identifier for the K8s connector"
  type        = string
  default     = "k8s_cluster"
}

variable "k8s_connector_name" {
  description = "Display name for the K8s connector"
  type        = string
  default     = "K8s Cluster"
}

################################################################################
# AWS Connector Variables
################################################################################

variable "create_aws_connector" {
  description = "Create an AWS connector"
  type        = bool
  default     = true
}

variable "aws_connector_id" {
  description = "Identifier for the AWS connector"
  type        = string
  default     = "aws_connector"
}

variable "aws_connector_name" {
  description = "Display name for the AWS connector"
  type        = string
  default     = "AWS"
}

variable "aws_connector_description" {
  description = "Description for the AWS connector"
  type        = string
  default     = ""
}

variable "aws_region" {
  description = "AWS region for the connector (used in IRSA credential)"
  type        = string
  default     = "us-east-1"
}

variable "aws_auth_type" {
  description = "AWS authentication type: delegate, manual, or irsa"
  type        = string
  default     = "delegate"

  validation {
    condition     = contains(["delegate", "manual", "irsa"], var.aws_auth_type)
    error_message = "aws_auth_type must be one of: delegate, manual, irsa"
  }
}

variable "aws_access_key_ref" {
  description = "Reference to AWS access key secret (for manual auth)"
  type        = string
  default     = ""
}

variable "aws_secret_key_ref" {
  description = "Reference to AWS secret key secret (for manual auth)"
  type        = string
  default     = ""
}

################################################################################
# AWS Cross-Account STS Access
################################################################################

variable "enable_cross_account_access" {
  description = "Enable cross-account STS access for AWS connector"
  type        = bool
  default     = false
}

variable "cross_account_role_arn" {
  description = "ARN of the IAM role to assume in the target account"
  type        = string
  default     = ""
}

variable "cross_account_external_id" {
  description = "External ID for cross-account role assumption (optional)"
  type        = string
  default     = ""
}

################################################################################
# Docker Registry Connector Variables
################################################################################

variable "create_docker_connector" {
  description = "Create a Docker registry connector"
  type        = bool
  default     = true
}

variable "docker_connector_id" {
  description = "Identifier for the Docker connector"
  type        = string
  default     = "ecr_registry"
}

variable "docker_connector_name" {
  description = "Display name for the Docker connector"
  type        = string
  default     = "ECR Registry"
}

variable "docker_registry_url" {
  description = "Docker registry URL"
  type        = string
  default     = ""
}

variable "docker_username_ref" {
  description = "Reference to Docker username secret"
  type        = string
  default     = ""
}

variable "docker_password_ref" {
  description = "Reference to Docker password secret"
  type        = string
  default     = ""
}

################################################################################
# GitHub Connector Variables
################################################################################

variable "create_github_connector" {
  description = "Create a GitHub connector"
  type        = bool
  default     = true
}

variable "github_connector_id" {
  description = "Identifier for the GitHub connector"
  type        = string
  default     = "github_repo"
}

variable "github_connector_name" {
  description = "Display name for the GitHub connector"
  type        = string
  default     = "GitHub"
}

variable "github_url" {
  description = "GitHub URL (org or repo)"
  type        = string
  default     = "https://github.com"
}

variable "github_connection_type" {
  description = "GitHub connection type: Account or Repo"
  type        = string
  default     = "Account"
}

variable "github_validation_repo" {
  description = "Repository to use for connection validation"
  type        = string
  default     = ""
}

variable "github_token_ref" {
  description = "Reference to GitHub token secret"
  type        = string
  default     = ""
}

################################################################################
# Prometheus Connector Variables
################################################################################

variable "create_prometheus_connector" {
  description = "Create a Prometheus connector for CV"
  type        = bool
  default     = false
}

variable "prometheus_connector_id" {
  description = "Identifier for the Prometheus connector"
  type        = string
  default     = "prometheus"
}

variable "prometheus_connector_name" {
  description = "Display name for the Prometheus connector"
  type        = string
  default     = "Prometheus"
}

variable "prometheus_url" {
  description = "Prometheus server URL"
  type        = string
  default     = ""
}
