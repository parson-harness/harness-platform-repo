################################################################################
# EKS Stack Variables
################################################################################

################################################################################
# Required Variables
################################################################################

variable "owner" {
  description = "Owner name for resource naming (e.g., 'todd')"
  type        = string
}

variable "eks_cluster_name" {
  description = "Name of the existing EKS cluster to deploy to"
  type        = string
}

variable "harness_account_id" {
  description = "Harness Account ID"
  type        = string
}

variable "harness_api_key" {
  description = "Harness Platform API Key"
  type        = string
  sensitive   = true
}

variable "harness_api_key_email" {
  description = "Email associated with the Harness API key (for HAR auth)"
  type        = string
}

################################################################################
# AWS Configuration
################################################################################

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

################################################################################
# Harness Platform Configuration
################################################################################

variable "harness_endpoint" {
  description = "Harness Platform endpoint"
  type        = string
  default     = "https://app.harness.io/gateway"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

################################################################################
# Harness Organization and Project
################################################################################

variable "create_harness_org" {
  description = "Create a new Harness organization"
  type        = bool
  default     = false
}

variable "harness_org_id" {
  description = "Existing Harness organization ID (used if create_harness_org = false)"
  type        = string
  default     = "default"
}

variable "new_harness_org_id" {
  description = "New Harness organization ID (used if create_harness_org = true)"
  type        = string
  default     = ""
}

variable "new_harness_org_name" {
  description = "New Harness organization name (used if create_harness_org = true)"
  type        = string
  default     = ""
}

variable "create_harness_project" {
  description = "Create a new Harness project"
  type        = bool
  default     = false
}

variable "harness_project_id" {
  description = "Existing Harness project ID (used if create_harness_project = false)"
  type        = string
  default     = ""
}

variable "new_harness_project_id" {
  description = "New Harness project ID (used if create_harness_project = true)"
  type        = string
  default     = ""
}

variable "new_harness_project_name" {
  description = "New Harness project name (used if create_harness_project = true)"
  type        = string
  default     = ""
}

################################################################################
# Connector Configuration
################################################################################

variable "create_aws_connector" {
  description = "Create AWS connector"
  type        = bool
  default     = true
}

variable "aws_auth_type" {
  description = "AWS connector auth type: 'irsa' or 'delegate'"
  type        = string
  default     = "irsa"
}

variable "github_url" {
  description = "GitHub URL"
  type        = string
  default     = "https://github.com"
}

variable "github_username" {
  description = "GitHub username"
  type        = string
  default     = ""
}

variable "github_token_ref" {
  description = "Harness secret reference for GitHub token"
  type        = string
  default     = ""
}

variable "github_connector_ref" {
  description = "Existing GitHub connector reference (if not creating)"
  type        = string
  default     = ""
}

################################################################################
# Artifact Registry Configuration
################################################################################

variable "artifact_registry_type" {
  description = "Artifact registry type: 'har' (Harness Artifact Registry) or 'ecr'"
  type        = string
  default     = "har"
}

variable "create_dockerhub_upstream" {
  description = "Create DockerHub upstream proxy in HAR"
  type        = bool
  default     = false
}

variable "dockerhub_username" {
  description = "DockerHub username for upstream proxy"
  type        = string
  default     = ""
}

variable "dockerhub_password_secret_ref" {
  description = "Harness secret reference for DockerHub password"
  type        = string
  default     = ""
}

################################################################################
# Harness Code Repository Configuration
################################################################################

variable "use_harness_code" {
  description = "Use Harness Code Repository instead of GitHub. When true, creates a Harness Code repo and imports from GitHub."
  type        = bool
  default     = false
}

variable "github_repo_name" {
  description = "GitHub repository name (org/repo format) - used as source for Harness Code import or direct GitHub access"
  type        = string
  default     = "parson-harness/harness-demo-app"
}

variable "github_pat" {
  description = "GitHub PAT for importing repo to Harness Code (needs repo read access). Only required when use_harness_code=true."
  type        = string
  default     = ""
  sensitive   = true
}

variable "git_branch" {
  description = "Git branch for manifests"
  type        = string
  default     = "main"
}

variable "manifest_paths" {
  description = "Paths to Kubernetes manifests"
  type        = list(string)
  default     = ["k8s/"]
}

variable "acm_cert_arn" {
  description = "ACM certificate ARN for HTTPS ingress"
  type        = string
  default     = ""
}

################################################################################
# Pipeline Configuration
################################################################################

variable "create_strategy_pipeline" {
  description = "Create the strategy choice deployment pipeline"
  type        = bool
  default     = true
}

variable "create_ci_pipeline" {
  description = "Create the CI build pipeline"
  type        = bool
  default     = true
}
