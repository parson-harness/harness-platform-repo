################################################################################
# Variables for Harness OPA Policies Module
################################################################################

variable "org_id" {
  description = "Harness organization identifier"
  type        = string
}

variable "project_id" {
  description = "Harness project identifier"
  type        = string
}

################################################################################
# Policy Creation Flags
################################################################################

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

################################################################################
# Policy Set Creation Flags
################################################################################

variable "create_ci_policy_set" {
  description = "Create CI standards policy set"
  type        = bool
  default     = true
}

variable "create_security_policy_set" {
  description = "Create security standards policy set"
  type        = bool
  default     = true
}

variable "create_quality_policy_set" {
  description = "Create quality gates policy set"
  type        = bool
  default     = true
}

################################################################################
# Policy Enforcement Flags
################################################################################

variable "enforce_ci_policies" {
  description = "Enable enforcement of CI policies (if false, policies are created but not enforced)"
  type        = bool
  default     = true
}

variable "enforce_security_policies" {
  description = "Enable enforcement of security policies"
  type        = bool
  default     = true
}

variable "enforce_quality_policies" {
  description = "Enable enforcement of quality gate policies"
  type        = bool
  default     = true
}

################################################################################
# Policy Scope Configuration
################################################################################

variable "policy_scope_tag" {
  description = "Only apply policies to pipelines with this tag. If empty, applies to all pipelines. Format: 'key:value' (e.g., 'managed-by:provisioner')"
  type        = string
  default     = "managed-by:provisioner"
}
