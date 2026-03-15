################################################################################
# Harness Connectors Module
# Creates Harness connectors for K8s, AWS, Docker Registry, and Git
################################################################################

################################################################################
# Kubernetes Cluster Connector
################################################################################

resource "harness_platform_connector_kubernetes" "cluster" {
  count = var.create_k8s_connector ? 1 : 0

  identifier  = var.k8s_connector_id
  name        = var.k8s_connector_name
  description = "Kubernetes cluster connector for ${var.environment_name}"
  org_id      = var.harness_org_id
  project_id  = var.harness_project_id

  inherit_from_delegate {
    delegate_selectors = var.delegate_selectors
  }

  tags = var.connector_tags
}

################################################################################
# AWS Connector (for ECR, S3, etc.) - IRSA with Cross-Account STS Support
################################################################################

resource "harness_platform_connector_aws" "main" {
  count = var.create_aws_connector ? 1 : 0

  identifier  = var.aws_connector_id
  name        = var.aws_connector_name
  description = var.aws_connector_description != "" ? var.aws_connector_description : "AWS connector for ${var.environment_name} (${var.aws_auth_type})"
  org_id      = var.harness_org_id
  project_id  = var.harness_project_id

  # Inherit from Delegate (uses EC2 instance profile)
  dynamic "inherit_from_delegate" {
    for_each = var.aws_auth_type == "delegate" ? [1] : []
    content {
      delegate_selectors = var.delegate_selectors
    }
  }

  # Manual credentials (access key + secret)
  dynamic "manual" {
    for_each = var.aws_auth_type == "manual" ? [1] : []
    content {
      access_key_ref     = var.aws_access_key_ref
      secret_key_ref     = var.aws_secret_key_ref
      delegate_selectors = var.delegate_selectors
    }
  }

  # IRSA - IAM Roles for Service Accounts (recommended for EKS)
  dynamic "irsa" {
    for_each = var.aws_auth_type == "irsa" ? [1] : []
    content {
      delegate_selectors = var.delegate_selectors
      region             = var.aws_region
    }
  }

  # Cross-Account STS Access (works with all auth types)
  dynamic "cross_account_access" {
    for_each = var.enable_cross_account_access ? [1] : []
    content {
      role_arn    = var.cross_account_role_arn
      external_id = var.cross_account_external_id
    }
  }

  tags = var.connector_tags
}

################################################################################
# Docker Registry Connector (for ECR)
################################################################################

resource "harness_platform_connector_docker" "ecr" {
  count = var.create_docker_connector ? 1 : 0

  identifier  = var.docker_connector_id
  name        = var.docker_connector_name
  description = "ECR Docker registry connector for ${var.environment_name}"
  org_id      = var.harness_org_id
  project_id  = var.harness_project_id

  type               = "Other"
  url                = var.docker_registry_url
  delegate_selectors = var.delegate_selectors

  credentials {
    username_ref = var.docker_username_ref
    password_ref = var.docker_password_ref
  }

  tags = var.connector_tags
}

################################################################################
# Git Connector (for pipeline/manifest repos)
################################################################################
# TODO: GitHub Connector Fork Pattern
# When repo moves to GitHub (e.g., harness-community/harness-demo-app):
# - Add default github_url pointing to upstream repo
# - Add github_fork_owner variable for SE/customer forks
# - Auto-construct URL: https://github.com/${var.github_fork_owner}/harness-demo-app
# - Document PAT token setup in README (repo scope needed)
# - Consider GitHub App auth as alternative to PAT
################################################################################

resource "harness_platform_connector_github" "repo" {
  count = var.create_github_connector ? 1 : 0

  identifier  = var.github_connector_id
  name        = var.github_connector_name
  description = "GitHub connector for ${var.environment_name}"
  org_id      = var.harness_org_id
  project_id  = var.harness_project_id

  url                = var.github_url
  connection_type    = var.github_connection_type
  validation_repo    = var.github_validation_repo
  delegate_selectors = var.delegate_selectors

  credentials {
    http {
      username   = var.github_username
      token_ref  = var.github_token_ref
    }
  }

  api_authentication {
    token_ref = var.github_token_ref
  }

  tags = var.connector_tags
}

################################################################################
# Prometheus Connector (for CV/Observability)
################################################################################

resource "harness_platform_connector_prometheus" "monitoring" {
  count = var.create_prometheus_connector ? 1 : 0

  identifier  = var.prometheus_connector_id
  name        = var.prometheus_connector_name
  description = "Prometheus connector for ${var.environment_name}"
  org_id      = var.harness_org_id
  project_id  = var.harness_project_id

  url                = var.prometheus_url
  delegate_selectors = var.delegate_selectors

  tags = var.connector_tags
}
