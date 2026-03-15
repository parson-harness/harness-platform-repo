################################################################################
# Harness Code Repository Import Module - Variables
################################################################################

variable "import_repo" {
  description = "Whether to import the repository to Harness Code"
  type        = bool
  default     = true
}

variable "harness_endpoint" {
  description = "Harness API endpoint (e.g., https://app.harness.io)"
  type        = string
  default     = "https://app.harness.io"
}

variable "harness_account_id" {
  description = "Harness account identifier"
  type        = string
}

variable "harness_api_key" {
  description = "Harness API key for authentication"
  type        = string
  sensitive   = true
}

variable "org_id" {
  description = "Harness organization identifier"
  type        = string
}

variable "project_id" {
  description = "Harness project identifier"
  type        = string
}

variable "repo_identifier" {
  description = "Identifier for the repository in Harness Code"
  type        = string
}

variable "repo_description" {
  description = "Description for the repository"
  type        = string
  default     = "POV Demo Application - imported from GitHub"
}

################################################################################
# Source Repository Configuration
################################################################################

variable "source_provider" {
  description = "Source Git provider type (github, gitlab, bitbucket)"
  type        = string
  default     = "github"
}

variable "source_host" {
  description = "Source Git provider host (include https://)"
  type        = string
  default     = "https://github.com"
}

variable "source_repo" {
  description = "Source repository in format 'owner/repo'"
  type        = string
  default     = "parson-harness/harness-demo-app"
}

variable "source_username" {
  description = "Username for source repo authentication (empty for public repos)"
  type        = string
  default     = ""
}

variable "source_password" {
  description = "Password/token for source repo authentication (empty for public repos)"
  type        = string
  default     = ""
  sensitive   = true
}
