################################################################################
# Harness Artifact Registry Module
# Creates a Docker registry in Harness Artifact Registry with optional
# upstream proxy for DockerHub
################################################################################

terraform {
  required_providers {
    harness = {
      source  = "harness/harness"
      version = "~> 0.38.0"
    }
  }
}

locals {
  harness_api_endpoint = trimsuffix(trimsuffix(var.harness_endpoint, "/"), "/gateway")
}

################################################################################
# DockerHub Upstream Proxy (project-level, for isolated POV environments)
################################################################################

resource "terraform_data" "dockerhub_upstream" {
  count = var.create_dockerhub_upstream ? 1 : 0

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      UPSTREAM_PATH="$HARNESS_API_ENDPOINT/har/api/v1/registry/${var.account_id}/${var.org_id}/${var.project_id}/${var.dockerhub_upstream_id}/%2B"
      RESP=$(curl -s -w "\n%%{http_code}" "$UPSTREAM_PATH" -H "x-api-key: $HARNESS_API_KEY")
      HTTP_CODE=$(echo "$RESP" | tail -n1)

      if [ "$HTTP_CODE" = "200" ]; then
        exit 0
      fi

      if [ "$HTTP_CODE" != "404" ]; then
        echo "$RESP"
        exit 1
      fi

      if [ -n "${var.dockerhub_username}" ]; then
        PAYLOAD=$(cat <<'JSON'
{"identifier":"${var.dockerhub_upstream_id}","packageType":"DOCKER","parentRef":"${var.account_id}/${var.org_id}/${var.project_id}","description":"DockerHub upstream proxy for ${var.project_id}","config":{"type":"UPSTREAM","source":"Dockerhub","authType":"UserPassword","userName":"${var.dockerhub_username}","secretIdentifier":"${var.dockerhub_password_secret_ref}","secretSpacePath":"${var.dockerhub_secret_space_path}"}}
JSON
)
      else
        PAYLOAD=$(cat <<'JSON'
{"identifier":"${var.dockerhub_upstream_id}","packageType":"DOCKER","parentRef":"${var.account_id}/${var.org_id}/${var.project_id}","description":"DockerHub upstream proxy for ${var.project_id}","config":{"type":"UPSTREAM","source":"Dockerhub","authType":"Anonymous"}}
JSON
)
      fi

      RESP=$(curl -s -w "\n%%{http_code}" -X POST "$HARNESS_API_ENDPOINT/har/api/v1/registry?space_ref=${var.account_id}/${var.org_id}/${var.project_id}/%2B" -H "x-api-key: $HARNESS_API_KEY" -H "Content-Type: application/json" -d "$PAYLOAD")
      HTTP_CODE=$(echo "$RESP" | tail -n1)

      case "$HTTP_CODE" in
        200|201|409) exit 0 ;;
        *) echo "$RESP"; exit 1 ;;
      esac
    EOT

    environment = {
      HARNESS_API_ENDPOINT = local.harness_api_endpoint
      HARNESS_API_KEY      = var.harness_api_key
    }
  }

  input = {
    identifier = var.dockerhub_upstream_id
  }
}

################################################################################
# Pre-Create Cleanup: Delete existing registry if it exists outside of state
# This handles the case where a previous failed run created the registry
# but it wasn't tracked in Terraform state
################################################################################

resource "terraform_data" "cleanup_existing_registry" {
  count = 0
}

################################################################################
# Project-Level Docker Registry (VIRTUAL type with project-level upstream proxy)
################################################################################

resource "terraform_data" "registry" {
  provisioner "local-exec" {
    command = <<-EOT
      set -e
      REGISTRY_PATH="$HARNESS_API_ENDPOINT/har/api/v1/registry/${var.account_id}/${var.org_id}/${var.project_id}/${var.registry_id}/%2B"
      RESP=$(curl -s -w "\n%%{http_code}" "$REGISTRY_PATH" -H "x-api-key: $HARNESS_API_KEY")
      HTTP_CODE=$(echo "$RESP" | tail -n1)
      BODY=$(echo "$RESP" | head -n -1)

      if [ "$HTTP_CODE" = "200" ]; then
        if [ "${var.create_dockerhub_upstream}" != "true" ] || echo "$BODY" | grep -q '"${var.dockerhub_upstream_id}"'; then
          exit 0
        fi

        PAYLOAD=$(cat <<'JSON'
{"identifier":"${var.registry_id}","packageType":"DOCKER","parentRef":"${var.account_id}/${var.org_id}/${var.project_id}","description":"${var.registry_description}","config":{"type":"VIRTUAL","upstreamProxies":["${var.dockerhub_upstream_id}"]}}
JSON
)
        RESP=$(curl -s -w "\n%%{http_code}" -X PUT "$REGISTRY_PATH" -H "x-api-key: $HARNESS_API_KEY" -H "Content-Type: application/json" -d "$PAYLOAD")
        HTTP_CODE=$(echo "$RESP" | tail -n1)

        case "$HTTP_CODE" in
          200|201) exit 0 ;;
          *) echo "$RESP"; exit 1 ;;
        esac
      fi

      if [ "$HTTP_CODE" != "404" ]; then
        echo "$RESP"
        exit 1
      fi

      if [ "${var.create_dockerhub_upstream}" = "true" ]; then
        PAYLOAD=$(cat <<'JSON'
{"identifier":"${var.registry_id}","packageType":"DOCKER","parentRef":"${var.account_id}/${var.org_id}/${var.project_id}","description":"${var.registry_description}","config":{"type":"VIRTUAL","upstreamProxies":["${var.dockerhub_upstream_id}"]}}
JSON
)
      else
        PAYLOAD=$(cat <<'JSON'
{"identifier":"${var.registry_id}","packageType":"DOCKER","parentRef":"${var.account_id}/${var.org_id}/${var.project_id}","description":"${var.registry_description}","config":{"type":"VIRTUAL","upstreamProxies":[]}}
JSON
)
      fi
      RESP=$(curl -s -w "\n%%{http_code}" -X POST "$HARNESS_API_ENDPOINT/har/api/v1/registry?space_ref=${var.account_id}/${var.org_id}/${var.project_id}/%2B" -H "x-api-key: $HARNESS_API_KEY" -H "Content-Type: application/json" -d "$PAYLOAD")
      HTTP_CODE=$(echo "$RESP" | tail -n1)

      case "$HTTP_CODE" in
        200|201|409) exit 0 ;;
        *) echo "$RESP"; exit 1 ;;
      esac
    EOT

    environment = {
      HARNESS_API_ENDPOINT = local.harness_api_endpoint
      HARNESS_API_KEY      = var.harness_api_key
    }
  }

  depends_on = [
    terraform_data.dockerhub_upstream,
    terraform_data.cleanup_existing_registry
  ]

  input = {
    identifier = var.registry_id
  }
}
