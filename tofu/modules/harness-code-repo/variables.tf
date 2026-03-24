################################################################################
# Harness Code Repository Module - Variables
# Uses native harness_platform_repo resource for proper state management
################################################################################

variable "create_repo" {
  description = "Whether to create the Harness Code repository"
  type        = bool
  default     = true
}

variable "harness_account_id" {
  description = "Harness account identifier (used for git URL construction)"
  type        = string
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

variable "default_branch" {
  description = "Default branch for the repository"
  type        = string
  default     = "main"
}

################################################################################
# Source Repository Configuration (for importing from external SCM)
################################################################################

variable "import_from_scm" {
  description = "Whether to import content from an external SCM provider"
  type        = bool
  default     = true
}

variable "source_provider" {
  description = "Source Git provider type (github, gitlab, bitbucket, stash, gitea, gogs)"
  type        = string
  default     = "github"

  validation {
    condition     = contains(["github", "gitlab", "bitbucket", "stash", "gitea", "gogs"], var.source_provider)
    error_message = "source_provider must be one of: github, gitlab, bitbucket, stash, gitea, gogs"
  }
}

variable "source_host" {
  description = "Source Git provider host URL"
  type        = string
  default     = "https://github.com"
}

variable "source_repo" {
  description = "Source repository in format 'owner/repo'"
  type        = string
  default     = "parson-harness/harness-demo-app"
}

variable "source_username" {
  description = "Username for source repo authentication (use 'x-access-token' for GitHub PAT)"
  type        = string
  default     = "x-access-token"
}

variable "source_password" {
  description = "Password/token for source repo authentication"
  type        = string
  default     = ""
  sensitive   = true
}
