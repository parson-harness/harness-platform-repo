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

  depends_on = [harness_platform_har_registry.dockerhub_upstream]

  parent_ref = "${var.account_id}/${var.org_id}/${var.project_id}"

  lifecycle {
    prevent_destroy = false
  }
}
