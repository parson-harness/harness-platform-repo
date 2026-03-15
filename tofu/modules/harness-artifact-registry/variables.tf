################################################################################
# Harness Artifact Registry Module - Variables
################################################################################

variable "account_id" {
  description = "Harness account ID"
  type        = string
}

variable "org_id" {
  description = "Harness organization ID"
  type        = string
}

variable "project_id" {
  description = "Harness project ID"
  type        = string
}

################################################################################
# Registry Configuration
################################################################################

variable "registry_id" {
  description = "Identifier for the Docker registry"
  type        = string
}

variable "registry_description" {
  description = "Description for the Docker registry"
  type        = string
  default     = "Harness Docker Registry"
}

################################################################################
# DockerHub Upstream Proxy Configuration
################################################################################

variable "create_dockerhub_upstream" {
  description = "Whether to create a DockerHub upstream proxy at org level"
  type        = bool
  default     = true
}

variable "dockerhub_upstream_id" {
  description = "Identifier for the DockerHub upstream proxy"
  type        = string
  default     = "dockerhub-proxy"
}

variable "dockerhub_username" {
  description = "DockerHub username for authenticated pulls (optional)"
  type        = string
  default     = ""
}

variable "dockerhub_password_secret_ref" {
  description = "Secret reference for DockerHub password"
  type        = string
  default     = ""
}

variable "dockerhub_secret_space_path" {
  description = "Space path for the DockerHub secret (e.g., account ID for account-level secrets)"
  type        = string
  default     = ""
}

variable "upstream_proxy_ids" {
  description = "List of existing upstream proxy IDs to use (if not creating DockerHub upstream)"
  type        = list(string)
  default     = []
}
