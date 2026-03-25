################################################################################
# Harness Artifact Registry Module
# Creates a Docker registry in Harness Artifact Registry with optional
# upstream proxy for DockerHub
################################################################################

terraform {
  required_providers {
    harness = {
      source  = "harness/harness"
      version = "~> 0.30"
    }
  }
}

################################################################################
# DockerHub Upstream Proxy (project-level, for isolated POV environments)
################################################################################

resource "harness_platform_har_registry" "dockerhub_upstream" {
  count = var.create_dockerhub_upstream ? 1 : 0

  identifier   = var.dockerhub_upstream_id
  description  = "DockerHub upstream proxy for ${var.project_id}"
  space_ref    = "${var.account_id}/${var.org_id}/${var.project_id}"
  package_type = "DOCKER"

  config {
    type   = "UPSTREAM"
    source = "Dockerhub"
    url    = "https://index.docker.io/v2/"

    auth {
      auth_type         = var.dockerhub_username != "" ? "UserPassword" : "Anonymous"
      user_name         = var.dockerhub_username != "" ? var.dockerhub_username : null
      secret_identifier = var.dockerhub_username != "" ? var.dockerhub_password_secret_ref : null
      secret_space_path = var.dockerhub_username != "" ? var.dockerhub_secret_space_path : null
    }
  }

  parent_ref = "${var.account_id}/${var.org_id}/${var.project_id}"

  lifecycle {
    prevent_destroy = false
  }
}

################################################################################
# Pre-Create Cleanup: Delete existing registry if it exists outside of state
# This handles the case where a previous failed run created the registry
# but it wasn't tracked in Terraform state
################################################################################

resource "terraform_data" "cleanup_existing_registry" {
  count = var.harness_api_key != "" ? 1 : 0

  provisioner "local-exec" {
    command = <<-EOT
      # Delete main registry first (it depends on upstream)
      echo "Cleaning up existing HAR registry: ${var.registry_id}"
      REGISTRY_REF="${var.account_id}/${var.org_id}/${var.project_id}/${var.registry_id}/+"
      HTTP_CODE=$(curl -s -o /dev/null -w "%%{http_code}" -X DELETE "${var.harness_endpoint}/har/api/v1/v1/registry/$REGISTRY_REF" \
        -H "x-api-key: ${var.harness_api_key}" \
        -H "Content-Type: application/json" 2>/dev/null)
      echo "  ${var.registry_id}: $HTTP_CODE"
      
      # Delete upstream proxy if it exists
      echo "Cleaning up existing upstream proxy: ${var.dockerhub_upstream_id}"
      UPSTREAM_REF="${var.account_id}/${var.org_id}/${var.project_id}/${var.dockerhub_upstream_id}/+"
      HTTP_CODE=$(curl -s -o /dev/null -w "%%{http_code}" -X DELETE "${var.harness_endpoint}/har/api/v1/v1/registry/$UPSTREAM_REF" \
        -H "x-api-key: ${var.harness_api_key}" \
        -H "Content-Type: application/json" 2>/dev/null)
      echo "  ${var.dockerhub_upstream_id}: $HTTP_CODE"
      
      # Small delay to ensure deletion is processed
      sleep 2
      exit 0
    EOT
  }

  triggers_replace = [
    var.registry_id,
    var.account_id,
    var.org_id,
    var.project_id,
    timestamp()  # Force cleanup to run on every apply
  ]
}

################################################################################
# Project-Level Docker Registry (VIRTUAL type with project-level upstream proxy)
################################################################################

resource "harness_platform_har_registry" "registry" {
  identifier   = var.registry_id
  description  = var.registry_description
  space_ref    = "${var.account_id}/${var.org_id}/${var.project_id}"
  package_type = "DOCKER"

  config {
    type             = "VIRTUAL"
    upstream_proxies = var.create_dockerhub_upstream ? [var.dockerhub_upstream_id] : var.upstream_proxy_ids
  }

  depends_on = [
    harness_platform_har_registry.dockerhub_upstream,
    terraform_data.cleanup_existing_registry
  ]

  parent_ref = "${var.account_id}/${var.org_id}/${var.project_id}"

  lifecycle {
    prevent_destroy = false
    # Ignore changes to allow re-import if registry already exists
    ignore_changes = [description]
  }
}
