################################################################################
# Legacy Variables (for backward compatibility with older workspaces)
# These are ignored but declared to prevent "undeclared variable" errors
################################################################################

variable "existing_cluster_name" {
  description = "LEGACY: Use eks_cluster_name instead"
  type        = string
  default     = ""
}

variable "asg_create_dns_record" {
  description = "LEGACY: ASG DNS record (not used in EKS stack)"
  type        = bool
  default     = false
}

variable "enable_irsa" {
  description = "LEGACY: IRSA is always enabled when create_delegate=true"
  type        = bool
  default     = true
}

variable "deployment_targets" {
  description = "LEGACY: EKS stack only supports K8s deployments"
  type        = list(string)
  default     = ["eks"]
}

variable "create_blue_green_pipeline" {
  description = "LEGACY: Use create_strategy_pipeline instead"
  type        = bool
  default     = false
}

variable "create_prod_environment" {
  description = "LEGACY: Prod environment is always created"
  type        = bool
  default     = true
}

variable "import_to_harness_code" {
  description = "LEGACY: Use use_harness_code instead"
  type        = bool
  default     = false
}

variable "source_github_repo" {
  description = "LEGACY: Use github_repo_name instead"
  type        = string
  default     = ""
}

variable "create_canary_pipeline" {
  description = "LEGACY: Use create_strategy_pipeline instead"
  type        = bool
  default     = false
}

variable "create_harness_environment" {
  description = "LEGACY: Environments are always created"
  type        = bool
  default     = true
}

variable "create_eks_cluster" {
  description = "LEGACY: EKS stack assumes existing cluster"
  type        = bool
  default     = false
}

variable "create_harness_service" {
  description = "LEGACY: Service is always created"
  type        = bool
  default     = true
}

variable "create_connectors" {
  description = "LEGACY: Connectors are always created"
  type        = bool
  default     = true
}

variable "workspace_id" {
  description = "LEGACY: Workspace identifier metadata stamped by the provisioner"
  type        = string
  default     = ""
}

variable "created_at" {
  description = "LEGACY: Workspace creation timestamp metadata stamped by the provisioner"
  type        = string
  default     = ""
}

variable "last_touched_at" {
  description = "LEGACY: Workspace last touched timestamp metadata stamped by the provisioner"
  type        = string
  default     = ""
}

variable "ttl_days" {
  description = "LEGACY: Workspace TTL metadata stamped by the provisioner"
  type        = string
  default     = ""
}

variable "deployment_target" {
  description = "LEGACY: Deployment target metadata stamped by the provisioner"
  type        = string
  default     = "eks"
}

variable "sandbox_profile" {
  description = "LEGACY: Sandbox profile metadata stamped by the provisioner"
  type        = string
  default     = ""
}
