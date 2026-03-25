################################################################################
# ASG Stack Variables
################################################################################

################################################################################
# Required Variables
################################################################################

variable "owner" {
  description = "Owner name for resource naming (e.g., 'todd')"
  type        = string
}

variable "harness_account_id" {
  description = "Harness Account ID"
  type        = string
}

variable "harness_api_key" {
  description = "Harness Platform API Key"
  type        = string
  sensitive   = true
}

################################################################################
# AWS Configuration
################################################################################

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "VPC CIDR block for ASG infrastructure"
  type        = string
  default     = "10.1.0.0/16"
}

variable "instance_type" {
  description = "EC2 instance type for ASG"
  type        = string
  default     = "t3.small"
}

################################################################################
# ASG Configuration
################################################################################

variable "asg_min_size" {
  description = "Minimum number of instances in ASG"
  type        = number
  default     = 1
}

variable "asg_desired_capacity" {
  description = "Desired capacity for ASG"
  type        = number
  default     = 1
}

variable "asg_max_size" {
  description = "Maximum number of instances in ASG"
  type        = number
  default     = 4
}

variable "asg_canary_instance_count" {
  description = "Number of canary instances for canary deployments"
  type        = number
  default     = 1
}

################################################################################
# DNS and SSL Configuration
################################################################################

variable "create_dns_record" {
  description = "Create Route53 DNS record for ALB"
  type        = bool
  default     = true
}

variable "route53_zone_name" {
  description = "Route53 hosted zone name"
  type        = string
  default     = "harness-demo.dev"
}

variable "acm_cert_arn" {
  description = "ACM certificate ARN for HTTPS"
  type        = string
  default     = ""
}

################################################################################
# Harness Platform Configuration
################################################################################

variable "harness_endpoint" {
  description = "Harness Platform endpoint"
  type        = string
  default     = "https://app.harness.io/gateway"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

################################################################################
# Harness Organization and Project
################################################################################

variable "create_harness_org" {
  description = "Create a new Harness organization"
  type        = bool
  default     = false
}

variable "harness_org_id" {
  description = "Existing Harness organization ID"
  type        = string
  default     = "default"
}

variable "new_harness_org_id" {
  description = "New Harness organization ID (if creating)"
  type        = string
  default     = ""
}

variable "new_harness_org_name" {
  description = "New Harness organization name (if creating)"
  type        = string
  default     = ""
}

variable "create_harness_project" {
  description = "Create a new Harness project"
  type        = bool
  default     = false
}

variable "harness_project_id" {
  description = "Existing Harness project ID"
  type        = string
  default     = ""
}

variable "new_harness_project_id" {
  description = "New Harness project ID (if creating)"
  type        = string
  default     = ""
}

variable "new_harness_project_name" {
  description = "New Harness project name (if creating)"
  type        = string
  default     = ""
}

################################################################################
# Connector Configuration
################################################################################

variable "aws_auth_type" {
  description = "AWS connector auth type: 'irsa' or 'delegate'"
  type        = string
  default     = "irsa"
}

variable "enable_cross_account_access" {
  description = "Enable cross-account access for AWS connector"
  type        = bool
  default     = false
}

variable "cross_account_role_arn" {
  description = "Cross-account IAM role ARN"
  type        = string
  default     = ""
}

variable "cross_account_external_id" {
  description = "Cross-account external ID"
  type        = string
  default     = ""
}

variable "github_url" {
  description = "GitHub URL"
  type        = string
  default     = "https://github.com"
}

variable "github_username" {
  description = "GitHub username"
  type        = string
  default     = ""
}

variable "github_token_ref" {
  description = "Harness secret reference for GitHub token"
  type        = string
  default     = ""
}

variable "github_connector_ref" {
  description = "Existing GitHub connector reference"
  type        = string
  default     = ""
}

################################################################################
# Service Configuration
################################################################################

variable "use_harness_code" {
  description = "Use Harness Code Repository instead of GitHub"
  type        = bool
  default     = false
}

variable "github_repo_name" {
  description = "GitHub repository name (org/repo format)"
  type        = string
  default     = "parson-harness/harness-demo-app"
}

variable "git_branch" {
  description = "Git branch for manifests"
  type        = string
  default     = "main"
}

################################################################################
# Pipeline Configuration
################################################################################

variable "create_asg_strategy_pipeline" {
  description = "Create the ASG strategy choice deployment pipeline"
  type        = bool
  default     = true
}

variable "create_asg_ci_pipeline" {
  description = "Create the ASG CI build pipeline (Maven + Packer)"
  type        = bool
  default     = true
}

################################################################################
# Delegate Configuration
################################################################################

variable "eks_cluster_name" {
  description = "Name of the shared EKS cluster where delegate will run (required if create_delegate=true)"
  type        = string
  default     = ""
}

variable "create_delegate" {
  description = "Create a Harness delegate for this POV (set to false if using shared delegate from EKS stack)"
  type        = bool
  default     = false
}

variable "delegate_replicas" {
  description = "Number of delegate replicas"
  type        = number
  default     = 1
}
