################################################################################
# EKS Stack Variables
################################################################################

################################################################################
# Required Variables
################################################################################

variable "owner" {
  description = "Owner name for resource naming (e.g., 'todd')"
  type        = string
}

variable "eks_cluster_name" {
  description = "Name of the existing EKS cluster to deploy to"
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

variable "harness_api_key_email" {
  description = "Email associated with the Harness API key (for HAR auth)"
  type        = string
}

################################################################################
# AWS Configuration
################################################################################

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
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
  description = "Existing Harness organization ID (used if create_harness_org = false)"
  type        = string
  default     = "default"
}

variable "new_harness_org_id" {
  description = "New Harness organization ID (used if create_harness_org = true)"
  type        = string
  default     = ""
}

variable "new_harness_org_name" {
  description = "New Harness organization name (used if create_harness_org = true)"
  type        = string
  default     = ""
}

variable "create_harness_project" {
  description = "Create a new Harness project"
  type        = bool
  default     = false
}

variable "harness_project_id" {
  description = "Existing Harness project ID (used if create_harness_project = false)"
  type        = string
  default     = ""
}

variable "new_harness_project_id" {
  description = "New Harness project ID (used if create_harness_project = true)"
  type        = string
  default     = ""
}

variable "new_harness_project_name" {
  description = "New Harness project name (used if create_harness_project = true)"
  type        = string
  default     = ""
}

################################################################################
# Connector Configuration
################################################################################

variable "create_aws_connector" {
  description = "Create AWS connector"
  type        = bool
  default     = true
}

variable "aws_connector_ref" {
  description = "Existing AWS connector reference to reuse instead of creating an owner-scoped connector"
  type        = string
  default     = ""
}

variable "aws_auth_type" {
  description = "AWS connector auth type: 'irsa' or 'delegate'"
  type        = string
  default     = "irsa"
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
  description = "Existing GitHub connector reference (if not creating)"
  type        = string
  default     = ""
}

################################################################################
# Artifact Registry Configuration
################################################################################

variable "artifact_registry_type" {
  description = "Artifact registry type: 'har' (Harness Artifact Registry) or 'ecr'"
  type        = string
  default     = "har"

  validation {
    condition     = var.artifact_registry_type == "har"
    error_message = "artifact_registry_type must remain 'har' for the EKS sandbox stack"
  }
}

variable "create_dockerhub_upstream" {
  description = "Create DockerHub upstream proxy in HAR (required for pulling base images through HAR)"
  type        = bool
  default     = true

  validation {
    condition     = var.create_dockerhub_upstream == true
    error_message = "create_dockerhub_upstream must remain true for the EKS sandbox stack"
  }
}

variable "dockerhub_username" {
  description = "DockerHub username for upstream proxy"
  type        = string
  default     = ""
}

variable "dockerhub_password_secret_ref" {
  description = "Harness secret reference for DockerHub password"
  type        = string
  default     = ""
}

################################################################################
# Harness Code Repository Configuration
################################################################################

variable "use_harness_code" {
  description = "Use Harness Code Repository instead of GitHub. When true, creates a Harness Code repo and imports from GitHub."
  type        = bool
  default     = true

  validation {
    condition     = var.use_harness_code == true
    error_message = "use_harness_code must remain true for the EKS sandbox stack"
  }
}

variable "github_repo_name" {
  description = "GitHub repository name (org/repo format) - used as source for Harness Code import or direct GitHub access"
  type        = string
  default     = "parson-harness/harness-demo-app"
}

variable "github_pat" {
  description = "GitHub PAT for importing repo to Harness Code (needs repo read access). Only required for private repos."
  type        = string
  default     = ""
  sensitive   = true
}

variable "github_repo_is_public" {
  description = "Whether the source GitHub repo is public (no auth needed for import)"
  type        = bool
  default     = true
}

variable "git_branch" {
  description = "Git branch for manifests"
  type        = string
  default     = "main"
}

variable "manifest_paths" {
  description = "Paths to Kubernetes manifests"
  type        = list(string)
  default     = ["k8s/"]
}

variable "acm_cert_arn" {
  description = "ACM certificate ARN for HTTPS ingress"
  type        = string
  default     = ""
}

################################################################################
# Pipeline Configuration
################################################################################

variable "create_strategy_pipeline" {
  description = "Create the strategy choice deployment pipeline"
  type        = bool
  default     = true
}

variable "create_ci_pipeline" {
  description = "LEGACY compatibility placeholder for the retired Maven CI pipeline"
  type        = bool
  default     = false
}

variable "create_standard_ci_gradle" {
  description = "Create Standard CI Gradle pipeline (Gradle build, Test Intelligence, security scanning, supply chain)"
  type        = bool
  default     = true
  nullable    = true
}

variable "standard_ci_gradle_test_packages" {
  description = "Java packages to scan for Test Intelligence (e.g., io.harness.demo)"
  type        = string
  default     = "io.harness.demo"
}

variable "publish_coverage_report_artifact" {
  description = "Publish the JaCoCo HTML coverage report to the Artifacts tab via S3"
  type        = bool
  default     = false
}

variable "coverage_report_artifact_bucket" {
  description = "S3 bucket used to host the coverage HTML report artifact"
  type        = string
  default     = ""
}

variable "coverage_report_artifact_region" {
  description = "AWS region for the coverage report artifact bucket"
  type        = string
  default     = "us-east-1"
}

variable "coverage_report_artifact_base_url" {
  description = "Public base URL for the published coverage report artifacts. Defaults to the standard S3 HTTPS URL when empty"
  type        = string
  default     = ""
}

variable "coverage_report_artifact_path_prefix" {
  description = "Prefix within the artifact bucket where coverage report artifacts are stored"
  type        = string
  default     = "coverage-reports"
}

################################################################################
# Delegate Configuration
################################################################################

variable "create_delegate" {
  description = "Create a Harness delegate for this POV"
  type        = bool
  default     = true
}

variable "delegate_replicas" {
  description = "Number of delegate replicas"
  type        = number
  default     = 1
}

variable "enable_asg_permissions" {
  description = "Enable ASG/EC2/ALB permissions in delegate IRSA role (for combined EKS+ASG deployments)"
  type        = bool
  default     = false
}

variable "import_existing_irsa_role" {
  description = "If true, use an existing IRSA role instead of creating a new one. Set to true when the role already exists outside of Terraform state (e.g., from a previous failed apply)."
  type        = bool
  default     = false
}

################################################################################
# DNS Configuration
################################################################################

variable "manage_dns" {
  description = "Create individual Route53 DNS record for {owner}.harness-demo.dev pointing to shared ALB"
  type        = bool
  default     = true
}

variable "dns_domain" {
  description = "Base domain for DNS records"
  type        = string
  default     = "harness-demo.dev"
}

variable "route53_hosted_zone_id" {
  description = "Route53 hosted zone ID for dns_domain. If empty, will be looked up by domain name."
  type        = string
  default     = ""
}

variable "shared_alb_dns_name" {
  description = "DNS name of the shared ALB for EKS ingress (e.g., k8s-harnessdemo-xxx.us-east-1.elb.amazonaws.com). Required when manage_dns=true."
  type        = string
  default     = ""
}

################################################################################
# Workspace Metadata Compatibility
################################################################################

variable "workspace_id" {
  description = "Workspace identifier metadata stamped by the provisioner"
  type        = string
  default     = ""
}

variable "created_at" {
  description = "Workspace creation timestamp metadata stamped by the provisioner"
  type        = string
  default     = ""
}

variable "last_touched_at" {
  description = "Workspace last touched timestamp metadata stamped by the provisioner"
  type        = string
  default     = ""
}

variable "ttl_days" {
  description = "Workspace TTL metadata stamped by the provisioner"
  type        = string
  default     = ""
}

variable "deployment_target" {
  description = "Deployment target metadata stamped by the provisioner"
  type        = string
  default     = "eks"
}

variable "sandbox_profile" {
  description = "Sandbox profile metadata stamped by the provisioner"
  type        = string
  default     = ""
}

variable "workspace_template_id" {
  description = "Workspace template identifier metadata stamped by the provisioner"
  type        = string
  default     = ""
}

################################################################################
# OPA Policy Configuration
################################################################################

variable "create_opa_policies" {
  description = "Create project-scoped OPA policies from this stack. Leave false for sandbox workspaces that should reuse a separate governance workspace."
  type        = bool
  default     = false
}

variable "enable_change_governance" {
  description = "Enable policy-driven change governance gates in generated deployment pipelines. This does not create the project policy resources."
  type        = bool
  default     = true
}

variable "manage_shared_change_governance" {
  description = "Manage shared change-governance policies and policy set from this stack. Leave false for sandbox workspaces that should reuse project-level governance assets."
  type        = bool
  default     = false
}

variable "enforce_ci_policies" {
  description = "Enable enforcement of CI pipeline policies"
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
