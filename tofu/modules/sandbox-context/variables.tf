variable "owner" {
  type = string
}

variable "environment" {
  type = string
}

variable "stack" {
  type = string
}

variable "workspace_id" {
  type    = string
  default = ""
}

variable "workspace_template_id" {
  type    = string
  default = ""
}

variable "project_name" {
  type    = string
  default = "harness-demo"
}

variable "managed_by" {
  type    = string
  default = "tofu"
}

variable "extra_common_tags" {
  type    = map(string)
  default = {}
}

variable "base_tag_values" {
  type    = list(string)
  default = []
}
