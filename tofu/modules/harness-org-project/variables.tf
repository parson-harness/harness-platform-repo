################################################################################
# Organization Variables
################################################################################

variable "create_organization" {
  description = "Create a new Harness organization (false = use existing)"
  type        = bool
  default     = false
}

variable "existing_org_id" {
  description = "Existing organization ID (required if create_organization=false)"
  type        = string
  default     = ""
}

variable "organization_id" {
  description = "Identifier for new organization (lowercase, no spaces)"
  type        = string
  default     = "harness_reference_architecture"
}

variable "organization_name" {
  description = "Display name for new organization"
  type        = string
  default     = "Harness Reference Architecture"
}

variable "organization_description" {
  description = "Description for new organization"
  type        = string
  default     = "Reference architecture for Harness CI/CD demonstrations"
}

################################################################################
# Project Variables
################################################################################

variable "create_project" {
  description = "Create a new Harness project (false = use existing)"
  type        = bool
  default     = false
}

variable "existing_project_id" {
  description = "Existing project ID (required if create_project=false)"
  type        = string
  default     = ""
}

variable "project_id" {
  description = "Identifier for new project (lowercase, no spaces)"
  type        = string
  default     = "demo"
}

variable "project_name" {
  description = "Display name for new project"
  type        = string
  default     = "Demo"
}

variable "project_description" {
  description = "Description for new project"
  type        = string
  default     = "Demo project for Harness CI/CD pipelines"
}

variable "project_color" {
  description = "Color for the project in Harness UI"
  type        = string
  default     = "#0063F7"
}

################################################################################
# Common Variables
################################################################################

variable "tags" {
  description = "Tags to apply to resources"
  type        = list(string)
  default     = ["tofu-managed"]
}
