################################################################################
# Harness Code Repository Module
# Creates a Harness Code repo using the native Terraform provider resource.
# Supports importing from GitHub, GitLab, Bitbucket, etc.
# 
# This uses harness_platform_repo which properly tracks state, allowing
# terraform destroy to clean up the repo (unlike the old local-exec approach).
################################################################################

terraform {
  required_providers {
    harness = {
      source  = "harness/harness"
      version = ">= 0.30"
    }
  }
}

################################################################################
# Create Harness Code Repository (with optional import from external SCM)
################################################################################

resource "harness_platform_repo" "main" {
  count = var.create_repo ? 1 : 0

  identifier     = var.repo_identifier
  org_id         = var.org_id
  project_id     = var.project_id
  default_branch = var.default_branch
  description    = var.repo_description

  # Import from external SCM provider (GitHub, GitLab, etc.)
  dynamic "source" {
    for_each = var.import_from_scm ? [1] : []
    content {
      type     = var.source_provider
      host     = var.source_host
      repo     = var.source_repo
      username = var.source_username
      password = var.source_password
    }
  }
}

################################################################################
# Outputs
################################################################################

locals {
  # Build the Harness Code git URL
  harness_code_repo_url = var.create_repo ? "https://git.harness.io/${var.harness_account_id}/${var.org_id}/${var.project_id}/${var.repo_identifier}" : ""
  
  # Repo identifier for use in pipelines
  repo_name = var.create_repo ? var.repo_identifier : ""
}
