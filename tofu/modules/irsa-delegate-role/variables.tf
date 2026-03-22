variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "owner" {
  description = "Owner name for tagging (SE last name or POV name)"
  type        = string
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "delegate_namespace" {
  description = "Kubernetes namespace where delegate will run"
  type        = string
  default     = "harness-delegate-ng"
}

variable "delegate_service_account" {
  description = "Kubernetes service account name for delegate"
  type        = string
  default     = "harness-delegate"
}

variable "ecr_repository_arns" {
  description = "List of ECR repository ARNs the delegate can push to"
  type        = list(string)
  default     = ["*"]
}

variable "s3_bucket_arns" {
  description = "List of S3 bucket ARNs the delegate can access"
  type        = list(string)
  default     = []
}

variable "cross_account_role_arns" {
  description = "List of cross-account IAM role ARNs the delegate can assume"
  type        = list(string)
  default     = []
}

variable "enable_ecs_permissions" {
  description = "Enable ECS deployment permissions"
  type        = bool
  default     = false
}

variable "enable_lambda_permissions" {
  description = "Enable Lambda deployment permissions"
  type        = bool
  default     = false
}

variable "enable_asg_permissions" {
  description = "Enable ASG/EC2/ALB deployment permissions (required for ASG deployment target)"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
