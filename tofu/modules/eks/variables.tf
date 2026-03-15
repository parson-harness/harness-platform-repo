variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for the EKS cluster"
  type        = list(string)
}

variable "kubernetes_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.29"
}

variable "endpoint_public_access" {
  description = "Enable public access to the EKS API endpoint"
  type        = bool
  default     = true
}

variable "enabled_cluster_log_types" {
  description = "List of EKS cluster log types to enable"
  type        = list(string)
  default     = ["api", "audit", "authenticator"]
}

variable "node_instance_types" {
  description = "Instance types for the node group"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_capacity_type" {
  description = "Capacity type for the node group (ON_DEMAND or SPOT)"
  type        = string
  default     = "ON_DEMAND"
}

variable "node_desired_size" {
  description = "Desired number of nodes"
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum number of nodes"
  type        = number
  default     = 4
}

variable "node_min_size" {
  description = "Minimum number of nodes"
  type        = number
  default     = 1
}

variable "node_labels" {
  description = "Labels to apply to nodes"
  type        = map(string)
  default     = {}
}

variable "create_namespace" {
  description = "Create a Kubernetes namespace for the demo app"
  type        = bool
  default     = true
}

variable "namespace" {
  description = "Kubernetes namespace for the demo app"
  type        = string
  default     = "harness-demo"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
