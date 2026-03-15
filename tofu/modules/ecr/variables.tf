variable "repository_name" {
  description = "Name of the ECR repository"
  type        = string
}

variable "image_tag_mutability" {
  description = "Image tag mutability setting (MUTABLE or IMMUTABLE)"
  type        = string
  default     = "MUTABLE"
}

variable "scan_on_push" {
  description = "Enable image scanning on push"
  type        = bool
  default     = true
}

variable "encryption_type" {
  description = "Encryption type (AES256 or KMS)"
  type        = string
  default     = "AES256"
}

variable "kms_key_arn" {
  description = "ARN of KMS key for encryption (if encryption_type is KMS)"
  type        = string
  default     = null
}

variable "enable_lifecycle_policy" {
  description = "Enable lifecycle policy to clean up old images"
  type        = bool
  default     = true
}

variable "max_image_count" {
  description = "Maximum number of images to keep"
  type        = number
  default     = 30
}

variable "cross_account_arns" {
  description = "List of AWS account ARNs for cross-account access"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
