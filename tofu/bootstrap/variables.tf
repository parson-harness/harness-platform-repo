################################################################################
# Variables
################################################################################

variable "aws_region" {
  description = "AWS region for state bucket"
  type        = string
  default     = "us-east-1"
}

variable "owner" {
  description = "Owner name (SE last name or POV name)"
  type        = string
}

variable "bucket_prefix" {
  description = "Prefix for the S3 bucket name"
  type        = string
  default     = "harness-demo-tfstate"
}

variable "coverage_bucket_prefix" {
  description = "Prefix for the shared coverage artifact S3 bucket name"
  type        = string
  default     = "harness-demo-coverage-artifacts"
}

variable "coverage_report_artifact_path_prefix" {
  description = "Prefix within the shared coverage artifact bucket where published reports are stored"
  type        = string
  default     = "coverage-reports"
}

variable "coverage_artifact_retention_days" {
  description = "Number of days to retain published coverage artifacts in the shared bucket"
  type        = number
  default     = 30
}

################################################################################
# Harness Integration Variables
# Required to automatically push cert ARN into the POV_Provisioner IACM template
################################################################################

variable "harness_endpoint" {
  description = "Harness API endpoint"
  type        = string
  default     = "https://app.harness.io/gratis"
}

variable "harness_account_id" {
  description = "Harness account ID"
  type        = string
  default     = ""
}

variable "harness_org_id" {
  description = "Harness org where the POV_Provisioner template lives"
  type        = string
  default     = "sandbox"
}

variable "harness_project_id" {
  description = "Harness project where the POV_Provisioner template lives"
  type        = string
  default     = "parson"
}

variable "harness_api_key" {
  description = "Harness API key — used to push acm_cert_arn into the POV_Provisioner template"
  type        = string
  default     = ""
  sensitive   = true
}

variable "harness_template_id" {
  description = "IACM workspace template identifier to update with the cert ARN"
  type        = string
  default     = "POV_Provisioner"
}

variable "alb_dns_name" {
  description = "Shared ALB DNS hostname. Get AFTER first CD deployment: kubectl get ingress -A -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}'. ALB name is auto-generated per cluster and changes on rebuild."
  type        = string
  default     = ""
}
