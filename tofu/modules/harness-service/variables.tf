################################################################################
# Required Variables
################################################################################

variable "service_id" {
  description = "Identifier for the service (lowercase, underscores)"
  type        = string
}

variable "service_name" {
  description = "Display name for the service"
  type        = string
}

variable "org_id" {
  description = "Harness Organization ID"
  type        = string
}

variable "project_id" {
  description = "Harness Project ID"
  type        = string
}

################################################################################
# Service Configuration
################################################################################

variable "service_description" {
  description = "Description of the service"
  type        = string
  default     = ""
}

variable "deployment_type" {
  description = "Deployment type: Kubernetes, ECS, NativeHelm, ServerlessAwsLambda"
  type        = string
  default     = "Kubernetes"

  validation {
    condition     = contains(["Kubernetes", "ECS", "NativeHelm", "ServerlessAwsLambda"], var.deployment_type)
    error_message = "deployment_type must be one of: Kubernetes, ECS, NativeHelm, ServerlessAwsLambda"
  }
}

variable "tags" {
  description = "Tags for the service (format: key:value)"
  type        = list(string)
  default     = ["tofu-managed"]
}

################################################################################
# Manifest Configuration (Kubernetes/Helm)
################################################################################

variable "manifest_type" {
  description = "Manifest type: K8sManifest, HelmChart, Values"
  type        = string
  default     = "K8sManifest"
}

variable "git_connector_ref" {
  description = "Reference to Git connector for manifests"
  type        = string
  default     = ""
}

variable "git_repo_name" {
  description = "Git repository name"
  type        = string
  default     = ""
}

variable "git_branch" {
  description = "Git branch for manifests"
  type        = string
  default     = "main"
}

variable "manifest_paths" {
  description = "Paths to Kubernetes manifest files"
  type        = list(string)
  default     = ["k8s/"]
}

variable "values_paths" {
  description = "Paths to values files (for Helm or K8s)"
  type        = list(string)
  default     = []
}

variable "helm_chart_path" {
  description = "Path to Helm chart in repository"
  type        = string
  default     = ""
}

variable "helm_chart_name" {
  description = "Helm chart name"
  type        = string
  default     = ""
}

variable "helm_chart_version" {
  description = "Helm chart version"
  type        = string
  default     = ""
}

################################################################################
# ECS Configuration
################################################################################

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

################################################################################
# Artifact Configuration
################################################################################

variable "artifact_source_type" {
  description = "Artifact source type: Ecr, DockerRegistry, or empty for none"
  type        = string
  default     = "Ecr"
}

variable "artifact_connector_ref" {
  description = "Reference to artifact connector (ECR or Docker)"
  type        = string
  default     = ""
}

variable "ecr_image_path" {
  description = "ECR image path (without tag)"
  type        = string
  default     = ""
}

variable "docker_image_path" {
  description = "Docker image path (without tag)"
  type        = string
  default     = ""
}

variable "aws_region" {
  description = "AWS region for ECR"
  type        = string
  default     = "us-east-1"
}

################################################################################
# Service Variables
################################################################################

variable "service_variables" {
  description = "Service-level variables"
  type = list(object({
    name  = string
    type  = string
    value = string
  }))
  default = []
}
