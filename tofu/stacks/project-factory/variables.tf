variable "harness_account_id" {
  description = "Harness account identifier"
  type        = string
}

variable "harness_endpoint" {
  description = "Harness platform endpoint"
  type        = string
}

variable "harness_api_key" {
  description = "Harness platform API key"
  type        = string
  sensitive   = true
}

variable "harness_org_id" {
  description = "Harness organization identifier"
  type        = string
}

variable "harness_project_id" {
  description = "Harness project identifier"
  type        = string
}

variable "create_harness_org" {
  description = "Create the Harness organization if it does not already exist"
  type        = bool
  default     = false
}

variable "create_harness_project" {
  description = "Create the Harness project if it does not already exist"
  type        = bool
  default     = false
}

variable "shared_delegate_selector" {
  description = "Stable delegate selector used by shared project-level connectors"
  type        = string
  default     = "parson-eks-delegate"
}

variable "create_shared_aws_connector" {
  description = "Create the shared project-level AWS connector"
  type        = bool
  default     = true
}

variable "shared_aws_connector_id" {
  description = "Identifier for the shared AWS connector"
  type        = string
  default     = ""
}

variable "shared_aws_connector_name" {
  description = "Display name for the shared AWS connector"
  type        = string
  default     = ""
}

variable "shared_aws_connector_description" {
  description = "Description for the shared AWS connector"
  type        = string
  default     = ""
}

variable "shared_aws_region" {
  description = "AWS region for the shared AWS connector"
  type        = string
  default     = "us-east-1"
}

variable "shared_aws_auth_type" {
  description = "AWS authentication type for the shared AWS connector"
  type        = string
  default     = "irsa"

  validation {
    condition     = contains(["delegate", "manual", "irsa"], var.shared_aws_auth_type)
    error_message = "shared_aws_auth_type must be one of: delegate, manual, irsa"
  }
}

variable "shared_aws_access_key_ref" {
  description = "Reference to AWS access key secret for manual shared AWS auth"
  type        = string
  default     = ""
}

variable "shared_aws_secret_key_ref" {
  description = "Reference to AWS secret key secret for manual shared AWS auth"
  type        = string
  default     = ""
}

variable "shared_enable_cross_account_access" {
  description = "Enable cross-account STS access for the shared AWS connector"
  type        = bool
  default     = false
}

variable "shared_cross_account_role_arn" {
  description = "ARN of the IAM role to assume for the shared AWS connector"
  type        = string
  default     = ""
}

variable "shared_cross_account_external_id" {
  description = "External ID for shared AWS cross-account role assumption"
  type        = string
  default     = ""
}

variable "create_shared_github_connector" {
  description = "Create the shared project-level GitHub connector"
  type        = bool
  default     = true
}

variable "shared_github_connector_id" {
  description = "Identifier for the shared GitHub connector"
  type        = string
  default     = ""
}

variable "shared_github_connector_name" {
  description = "Display name for the shared GitHub connector"
  type        = string
  default     = ""
}

variable "shared_github_url" {
  description = "GitHub URL for the shared GitHub connector"
  type        = string
  default     = "https://github.com"
}

variable "shared_github_connection_type" {
  description = "GitHub connection type for the shared GitHub connector"
  type        = string
  default     = "Account"
}

variable "shared_github_validation_repo" {
  description = "Repository to use for shared GitHub connector validation"
  type        = string
  default     = "parson-harness/harness-demo-app"
}

variable "shared_github_token_ref" {
  description = "Harness secret reference for the shared GitHub connector token"
  type        = string
  default     = ""
}

variable "shared_github_username" {
  description = "GitHub username for the shared GitHub connector"
  type        = string
  default     = "x-access-token"
}

variable "create_shared_har_registry" {
  description = "Create the shared project-level Harness Artifact Registry"
  type        = bool
  default     = false
}

variable "shared_har_registry_id" {
  description = "Identifier for the shared project-level Harness Artifact Registry"
  type        = string
  default     = ""
}

variable "shared_har_dockerhub_upstream_id" {
  description = "Identifier for the shared DockerHub upstream proxy used by the shared Harness Artifact Registry"
  type        = string
  default     = ""
}

variable "create_shared_harness_code_repo" {
  description = "Create the shared project-level Harness Code repository"
  type        = bool
  default     = false
}

variable "shared_harness_code_repo_identifier" {
  description = "Identifier for the shared Harness Code repository"
  type        = string
  default     = ""
}

variable "shared_harness_code_source_repo" {
  description = "Source GitHub repository imported into the shared Harness Code repository"
  type        = string
  default     = "parson-harness/harness-demo-app"
}

variable "github_pat" {
  description = "GitHub PAT for importing the shared Harness Code repo when the source repo is private"
  type        = string
  default     = ""
  sensitive   = true
}

variable "github_repo_is_public" {
  description = "Whether the shared Harness Code source repo is public"
  type        = bool
  default     = true
}
