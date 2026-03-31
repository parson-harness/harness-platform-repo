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

  depends_on = [terraform_data.cleanup_existing_registry]

  parent_ref = "${var.account_id}/${var.org_id}/${var.project_id}"

  lifecycle {
    prevent_destroy = false
    # If the resource was deleted outside of Terraform, recreate it
    create_before_destroy = true
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
      RESP=$(curl -s -w "\n%%{http_code}" -X DELETE "$HARNESS_ENDPOINT/har/api/v1/registry/$REGISTRY_REF" \
        -H "x-api-key: $HARNESS_API_KEY" \
        -H "Content-Type: application/json")
      HTTP_CODE=$(echo "$RESP" | tail -n1)
      BODY=$(echo "$RESP" | head -n -1)
      echo "  ${var.registry_id}: $HTTP_CODE"
      [ -n "$BODY" ] && echo "  Response: $BODY"
      
      # Delete upstream proxy if it exists
      echo "Cleaning up existing upstream proxy: ${var.dockerhub_upstream_id}"
      UPSTREAM_REF="${var.account_id}/${var.org_id}/${var.project_id}/${var.dockerhub_upstream_id}/+"
      RESP=$(curl -s -w "\n%%{http_code}" -X DELETE "$HARNESS_ENDPOINT/har/api/v1/registry/$UPSTREAM_REF" \
        -H "x-api-key: $HARNESS_API_KEY" \
        -H "Content-Type: application/json")
      HTTP_CODE=$(echo "$RESP" | tail -n1)
      BODY=$(echo "$RESP" | head -n -1)
      echo "  ${var.dockerhub_upstream_id}: $HTTP_CODE"
      [ -n "$BODY" ] && echo "  Response: $BODY"
      
      # Small delay to ensure deletion is processed
      sleep 2
      exit 0
    EOT

    environment = {
      HARNESS_API_KEY  = var.harness_api_key
      HARNESS_ENDPOINT = var.harness_endpoint
    }
  }

  triggers_replace = [
    var.registry_id,
    var.account_id,
    var.org_id,
    var.project_id
    # Removed timestamp() - cleanup should only run when identifiers change,
    # not on every apply (which would delete resources before recreating them)
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
