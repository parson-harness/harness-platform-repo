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

variable "create_ci_policies" {
  description = "Create CI pipeline standard policies"
  type        = bool
  default     = true
}

variable "create_security_policies" {
  description = "Create security standard policies"
  type        = bool
  default     = true
}

variable "create_quality_policies" {
  description = "Create build quality gate policies"
  type        = bool
  default     = true
}

variable "create_change_governance_policies" {
  description = "Create custom change governance policies"
  type        = bool
  default     = true
}

variable "create_ci_policy_set" {
  description = "Create the CI standards policy set"
  type        = bool
  default     = true
}

variable "create_security_policy_set" {
  description = "Create the security standards policy set"
  type        = bool
  default     = true
}

variable "create_quality_policy_set" {
  description = "Create the quality gates policy set"
  type        = bool
  default     = true
}

variable "create_change_governance_policy_set" {
  description = "Create the change governance policy set"
  type        = bool
  default     = true
}

variable "enforce_ci_policies" {
  description = "Enable enforcement of CI policies"
  type        = bool
  default     = true
}

variable "enforce_security_policies" {
  description = "Enable enforcement of security policies"
  type        = bool
  default     = true
}

variable "enforce_quality_policies" {
  description = "Enable enforcement of quality policies"
  type        = bool
  default     = true
}

variable "enforce_change_governance_policies" {
  description = "Enable enforcement of change governance policies"
  type        = bool
  default     = true
}

variable "policy_scope_tag" {
  description = "Policy scope tag applied to managed pipelines"
  type        = string
  default     = "managed-by:provisioner"
}
