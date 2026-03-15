################################################################################
# Required Variables
################################################################################

variable "owner" {
  description = "Owner name (SE last name or POV name) - used for namespace suffix and tagging"
  type        = string
}

variable "delegate_name" {
  description = "Base name of the Harness Delegate (will be suffixed with owner)"
  type        = string
  default     = "delegate"
}

variable "harness_account_id" {
  description = "Harness Account ID"
  type        = string
}

variable "delegate_token" {
  description = "Harness Delegate Token"
  type        = string
  sensitive   = true
}

variable "harness_api_key" {
  description = "Harness API Key (for fetching latest delegate version)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "harness_manager_endpoint" {
  description = "Harness Manager Endpoint URL"
  type        = string
  default     = "https://app.harness.io"
}

################################################################################
# Namespace Configuration
################################################################################

variable "namespace" {
  description = "Kubernetes namespace for the delegate (used when create_namespace=false)"
  type        = string
  default     = "harness-delegate-ng"
}

variable "create_namespace" {
  description = "Create a new namespace (harness-delegate-ng-<owner>)"
  type        = bool
  default     = true
}

################################################################################
# Delegate Creation Toggle
################################################################################

variable "create_delegate" {
  description = "Create a new delegate (set to false to use existing delegate)"
  type        = bool
  default     = true
}

################################################################################
# Delegate Image Configuration
################################################################################

variable "delegate_image" {
  description = "Full Docker image for the delegate (overrides version/prefix)"
  type        = string
  default     = ""
}

variable "delegate_version" {
  description = "Delegate version tag (e.g., 24.02.82302)"
  type        = string
  default     = ""
}

variable "delegate_image_prefix" {
  description = "Delegate image prefix (without tag)"
  type        = string
  default     = "harness/delegate"
}

variable "fetch_latest_version" {
  description = "Fetch latest delegate version from Harness API"
  type        = bool
  default     = true
}

variable "delegate_helm_version" {
  description = "Version of the Harness Delegate Helm chart"
  type        = string
  default     = "1.0.0"
}

variable "delegate_replicas" {
  description = "Number of delegate replicas"
  type        = number
  default     = 1
}

variable "enable_upgrader" {
  description = "Enable automatic delegate upgrades"
  type        = bool
  default     = true
}

variable "delegate_cpu_limit" {
  description = "CPU limit for delegate pods"
  type        = string
  default     = "1"
}

variable "delegate_memory_limit" {
  description = "Memory limit for delegate pods"
  type        = string
  default     = "2Gi"
}

variable "delegate_cpu_request" {
  description = "CPU request for delegate pods"
  type        = string
  default     = "0.5"
}

variable "delegate_memory_request" {
  description = "Memory request for delegate pods"
  type        = string
  default     = "1Gi"
}

variable "k8s_permissions_type" {
  description = "Kubernetes permissions type (CLUSTER_ADMIN, CLUSTER_VIEWER, NAMESPACE_ADMIN)"
  type        = string
  default     = "CLUSTER_ADMIN"
}

variable "init_script" {
  description = "Init script to run on delegate startup"
  type        = string
  default     = ""
}

variable "enable_irsa" {
  description = "Enable IAM Roles for Service Accounts"
  type        = bool
  default     = false
}

variable "enable_irsa_annotations" {
  description = "Enable IRSA annotations on the delegate service account (set to true when irsa_role_arn is provided)"
  type        = bool
  default     = false
}

variable "irsa_role_arn" {
  description = "ARN of the IAM role for IRSA"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

################################################################################
# RBAC Configuration
################################################################################

variable "grant_cluster_admin" {
  description = "Grant cluster-admin role to delegate service account (convenient for POVs)"
  type        = bool
  default     = true
}

################################################################################
# Delegate Tags
################################################################################

variable "delegate_tags" {
  description = "Additional tags for delegate selection in Harness"
  type        = list(string)
  default     = []
}
