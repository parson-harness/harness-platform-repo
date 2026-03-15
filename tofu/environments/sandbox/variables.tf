################################################################################
# Environment Variables
################################################################################

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "sandbox"
}

variable "owner" {
  description = "Owner name (SE last name or POV name) - used for resource naming and tagging"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

################################################################################
# Deployment Target (Use Case Selection)
################################################################################

variable "deployment_targets" {
  description = "List of deployment targets to configure: eks, ecs, lambda, asg"
  type        = list(string)
  default     = ["eks"]

  validation {
    condition     = alltrue([for t in var.deployment_targets : contains(["eks", "ecs", "lambda", "asg"], t)])
    error_message = "deployment_targets must be a list containing: eks, ecs, lambda, asg"
  }
}

locals {
  # Convenience flags based on deployment targets
  enable_eks    = contains(var.deployment_targets, "eks")
  enable_ecs    = contains(var.deployment_targets, "ecs")
  enable_lambda = contains(var.deployment_targets, "lambda")
  enable_asg    = contains(var.deployment_targets, "asg")

  # Primary deployment type for Service definition
  primary_deployment_type = (
    local.enable_eks ? "Kubernetes" :
    local.enable_ecs ? "ECS" :
    local.enable_lambda ? "ServerlessAwsLambda" :
    "Kubernetes"
  )
}

################################################################################
# Resource Creation Toggles
################################################################################

variable "create_eks_cluster" {
  description = "Create a new EKS cluster (false = use existing cluster)"
  type        = bool
  default     = false
}

variable "existing_cluster_name" {
  description = "Name of existing EKS cluster (required if create_eks_cluster=false)"
  type        = string
  default     = ""
}

variable "create_delegate" {
  description = "Create a new Harness delegate (false = use existing delegate)"
  type        = bool
  default     = true
}

variable "delegate_version" {
  description = "Delegate version tag (e.g., 26.02.88600). Leave empty to fetch latest automatically."
  type        = string
  default     = ""
}

variable "create_connectors" {
  description = "Create Harness connectors"
  type        = bool
  default     = true
}

################################################################################
# VPC Variables (only used if create_eks_cluster=true)
################################################################################

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway (costs money, disable for dev)"
  type        = bool
  default     = true
}

################################################################################
# EKS Variables (only used if create_eks_cluster=true)
################################################################################

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.29"
}

variable "node_instance_types" {
  description = "EC2 instance types for worker nodes"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_capacity_type" {
  description = "Capacity type: ON_DEMAND or SPOT"
  type        = string
  default     = "SPOT"
}

variable "node_desired_size" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum number of worker nodes"
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Maximum number of worker nodes"
  type        = number
  default     = 4
}

################################################################################
# Harness Variables
################################################################################

variable "harness_endpoint" {
  description = "Harness platform endpoint"
  type        = string
  default     = "https://app.harness.io"
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

variable "harness_delegate_token" {
  description = "Harness Delegate Token (optional - if not set, one is created automatically via harness_platform_delegatetoken)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "harness_org_id" {
  description = "Existing Harness Organization ID (used when create_harness_org=false)"
  type        = string
  default     = ""
}

variable "harness_project_id" {
  description = "Existing Harness Project ID (used when create_harness_project=false)"
  type        = string
  default     = ""
}

################################################################################
# Harness Org/Project Creation (optional)
################################################################################

variable "create_harness_org" {
  description = "Create a new Harness organization (false = use existing harness_org_id)"
  type        = bool
  default     = false
}

variable "new_harness_org_id" {
  description = "Identifier for new organization (lowercase, underscores)"
  type        = string
  default     = "harness_reference_architecture"
}

variable "new_harness_org_name" {
  description = "Display name for new organization"
  type        = string
  default     = "Harness Reference Architecture"
}

variable "create_harness_project" {
  description = "Create a new Harness project (false = use existing harness_project_id)"
  type        = bool
  default     = false
}

variable "new_harness_project_id" {
  description = "Identifier for new project (leave empty to auto-generate from owner)"
  type        = string
  default     = ""
}

variable "new_harness_project_name" {
  description = "Display name for new project (leave empty to auto-generate from owner)"
  type        = string
  default     = ""
}

################################################################################
# GitHub Variables
################################################################################

variable "github_url" {
  description = "GitHub organization or repo URL"
  type        = string
  default     = "https://github.com"
}

variable "github_token_ref" {
  description = "Reference to GitHub token secret in Harness"
  type        = string
  default     = ""
}

variable "github_username" {
  description = "GitHub username for HTTP authentication"
  type        = string
  default     = ""
}

################################################################################
# Pipeline Configuration
################################################################################

variable "create_canary_pipeline" {
  description = "Create Canary deployment pipeline"
  type        = bool
  default     = true
}

variable "create_blue_green_pipeline" {
  description = "Create Blue/Green deployment pipeline"
  type        = bool
  default     = false
}

################################################################################
# IRSA Configuration
################################################################################

variable "enable_irsa" {
  description = "Enable IAM Roles for Service Accounts for delegate"
  type        = bool
  default     = true
}

variable "s3_bucket_arns" {
  description = "S3 bucket ARNs the delegate can access"
  type        = list(string)
  default     = []
}

variable "cross_account_role_arns" {
  description = "Cross-account IAM role ARNs the delegate can assume"
  type        = list(string)
  default     = []
}

variable "enable_ecs_permissions" {
  description = "Enable ECS deployment permissions for delegate"
  type        = bool
  default     = false
}

variable "enable_lambda_permissions" {
  description = "Enable Lambda deployment permissions for delegate"
  type        = bool
  default     = false
}

################################################################################
# Cross-Account STS Access (for AWS Connector)
################################################################################

variable "enable_cross_account_access" {
  description = "Enable cross-account STS access for AWS connector"
  type        = bool
  default     = false
}

variable "cross_account_role_arn" {
  description = "ARN of the IAM role to assume in the target account"
  type        = string
  default     = ""
}

variable "cross_account_external_id" {
  description = "External ID for cross-account role assumption"
  type        = string
  default     = ""
}

################################################################################
# Harness Service Configuration
################################################################################

variable "create_harness_service" {
  description = "Create Harness Service definition"
  type        = bool
  default     = true
}

variable "service_git_repo" {
  description = "Git repository name for service manifests"
  type        = string
  default     = ""
}

variable "service_git_branch" {
  description = "Git branch for service manifests"
  type        = string
  default     = "main"
}

variable "service_manifest_paths" {
  description = "Paths to Kubernetes manifest files"
  type        = list(string)
  default     = ["k8s/"]
}

variable "ecs_task_definition_paths" {
  description = "Paths to ECS task definition files"
  type        = list(string)
  default     = ["ecs/taskdef.json"]
}

variable "ecs_service_definition_paths" {
  description = "Paths to ECS service definition files"
  type        = list(string)
  default     = ["ecs/servicedef.json"]
}

variable "github_connector_ref" {
  description = "Reference to existing GitHub connector (if not creating)"
  type        = string
  default     = ""
}

variable "aws_connector_ref" {
  description = "Reference to existing AWS connector (if not creating)"
  type        = string
  default     = ""
}

variable "k8s_connector_ref" {
  description = "Reference to existing K8s connector (if not creating)"
  type        = string
  default     = ""
}

################################################################################
# Harness Environment Configuration
################################################################################

variable "create_harness_environment" {
  description = "Create Harness Environment definitions"
  type        = bool
  default     = true
}

variable "create_prod_environment" {
  description = "Create Production environment in addition to Dev"
  type        = bool
  default     = true
}

variable "ecs_cluster_name" {
  description = "ECS cluster name for ECS infrastructure"
  type        = string
  default     = ""
}

################################################################################
# Artifact Registry Configuration
################################################################################

variable "artifact_registry_type" {
  description = "Artifact registry type: har (Harness Artifact Registry - default) or ecr (AWS ECR)"
  type        = string
  default     = "har"

  validation {
    condition     = contains(["har", "ecr"], var.artifact_registry_type)
    error_message = "artifact_registry_type must be one of: har, ecr"
  }
}

variable "create_dockerhub_upstream" {
  description = "Create DockerHub upstream proxy at org level (for HAR)"
  type        = bool
  default     = true
}

variable "dockerhub_username" {
  description = "DockerHub username for authenticated pulls (optional, for rate limit avoidance)"
  type        = string
  default     = ""
}

variable "dockerhub_password_secret_ref" {
  description = "Secret reference for DockerHub password in Harness"
  type        = string
  default     = ""
}

################################################################################
# Continuous Verification Configuration
################################################################################

variable "enable_cv" {
  description = "Enable Continuous Verification in canary pipeline"
  type        = bool
  default     = false
}

variable "cv_sensitivity" {
  description = "CV sensitivity level (High, Medium, Low)"
  type        = string
  default     = "Medium"

  validation {
    condition     = contains(["High", "Medium", "Low"], var.cv_sensitivity)
    error_message = "cv_sensitivity must be one of: High, Medium, Low"
  }
}

variable "cv_duration" {
  description = "CV analysis duration (e.g., 5m, 10m, 15m)"
  type        = string
  default     = "5m"
}

variable "prometheus_connector_ref" {
  description = "Reference to Prometheus connector for CV health source"
  type        = string
  default     = ""
}
