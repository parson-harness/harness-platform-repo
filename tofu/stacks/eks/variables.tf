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
}

variable "create_dockerhub_upstream" {
  description = "Create DockerHub upstream proxy in HAR (required for pulling base images through HAR)"
  type        = bool
  default     = true
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
  default     = false
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
  description = "Create the CI build pipeline (Maven-based)"
  type        = bool
  default     = true
}

variable "create_standard_ci_gradle" {
  description = "Create Standard CI Gradle pipeline (Gradle build, Test Intelligence, security scanning, supply chain)"
  type        = bool
  default     = false
  nullable    = true
}

variable "standard_ci_gradle_test_packages" {
  description = "Java packages to scan for Test Intelligence (e.g., io.harness.demo)"
  type        = string
  default     = "io.harness.demo"
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
# OPA Policy Configuration
################################################################################

variable "create_opa_policies" {
  description = "Create OPA policies for CI/CD governance"
  type        = bool
  default     = true
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

################################################################################
# Legacy Variables (for backward compatibility with older workspaces)
# These are ignored but declared to prevent "undeclared variable" errors
################################################################################

variable "existing_cluster_name" {
  description = "LEGACY: Use eks_cluster_name instead"
  type        = string
  default     = ""
}

variable "asg_create_dns_record" {
  description = "LEGACY: ASG DNS record (not used in EKS stack)"
  type        = bool
  default     = false
}

variable "enable_irsa" {
  description = "LEGACY: IRSA is always enabled when create_delegate=true"
  type        = bool
  default     = true
}

variable "deployment_targets" {
  description = "LEGACY: EKS stack only supports K8s deployments"
  type        = list(string)
  default     = ["eks"]
}

variable "create_blue_green_pipeline" {
  description = "LEGACY: Use create_strategy_pipeline instead"
  type        = bool
  default     = false
}

variable "create_prod_environment" {
  description = "LEGACY: Prod environment is always created"
  type        = bool
  default     = true
}

variable "import_to_harness_code" {
  description = "LEGACY: Use use_harness_code instead"
  type        = bool
  default     = false
}

variable "source_github_repo" {
  description = "LEGACY: Use github_repo_name instead"
  type        = string
  default     = ""
}

variable "create_canary_pipeline" {
  description = "LEGACY: Use create_strategy_pipeline instead"
  type        = bool
  default     = false
}

variable "create_harness_environment" {
  description = "LEGACY: Environments are always created"
  type        = bool
  default     = true
}

variable "create_eks_cluster" {
  description = "LEGACY: EKS stack assumes existing cluster"
  type        = bool
  default     = false
}

variable "create_harness_service" {
  description = "LEGACY: Service is always created"
  type        = bool
  default     = true
}

variable "create_connectors" {
  description = "LEGACY: Connectors are always created"
  type        = bool
  default     = true
}
