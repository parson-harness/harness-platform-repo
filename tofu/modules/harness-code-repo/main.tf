################################################################################
# Harness Code Repository Import Module
# Imports a GitHub repository into Harness Code for POV-in-a-box scenarios
################################################################################

terraform {
  required_providers {
    http = {
      source  = "hashicorp/http"
      version = ">= 3.0"
    }
  }
}

################################################################################
# Import Repository to Harness Code
################################################################################

resource "terraform_data" "import_repo" {
  count = var.import_repo ? 1 : 0

  # Trigger reimport if source repo changes
  triggers_replace = [
    var.source_repo,
    var.repo_identifier,
  ]

  provisioner "local-exec" {
    command = <<-EOT
      # Check if repo already exists
      EXISTING=$(curl -s -o /dev/null -w "%%{http_code}" \
        "${var.harness_endpoint}/code/api/v1/repos/${var.repo_identifier}?accountIdentifier=${var.harness_account_id}&orgIdentifier=${var.org_id}&projectIdentifier=${var.project_id}" \
        -H "x-api-key: ${var.harness_api_key}")
      if [ "$EXISTING" = "200" ]; then
        echo "Repo '${var.repo_identifier}' already exists in Harness Code, skipping import"
        exit 0
      fi
      echo "Importing '${var.source_repo}' to Harness Code as '${var.repo_identifier}'..."
      RESP=$(curl -s -w "\n%%{http_code}" -X POST \
        "${var.harness_endpoint}/code/api/v1/repos/import?accountIdentifier=${var.harness_account_id}&orgIdentifier=${var.org_id}&projectIdentifier=${var.project_id}" \
        -H "Content-Type: application/json" \
        -H "x-api-key: ${var.harness_api_key}" \
        -d '{
          "identifier": "${var.repo_identifier}",
          "description": "${var.repo_description}",
          "provider": {
            "type": "${var.source_provider}",
            "host": "${var.source_host}",
            "username": "${var.source_username}",
            "password": "${var.source_password}"
          },
          "provider_repo": "${var.source_repo}"
        }')
      HTTP_CODE=$(echo "$RESP" | tail -n1)
      echo "Import response code: $HTTP_CODE"
      if [ "$HTTP_CODE" != "200" ] && [ "$HTTP_CODE" != "201" ] && [ "$HTTP_CODE" != "202" ]; then
        echo "Import failed: $(echo "$RESP" | head -n -1)"
        exit 1
      fi
      echo "Import initiated successfully"
    EOT
  }
}

################################################################################
# Wait for import to complete and get repo details
################################################################################

data "http" "repo_details" {
  count = var.import_repo ? 1 : 0
  depends_on = [terraform_data.import_repo]

  url = "${var.harness_endpoint}/code/api/v1/repos/${var.repo_identifier}?accountIdentifier=${var.harness_account_id}&orgIdentifier=${var.org_id}&projectIdentifier=${var.project_id}"

  request_headers = {
    "x-api-key" = var.harness_api_key
  }

  # Retry to allow import to complete
  retry {
    attempts     = 10
    min_delay_ms = 3000
    max_delay_ms = 10000
  }
}

locals {
  # Parse repo details from response
  repo_response = var.import_repo && length(data.http.repo_details) > 0 ? jsondecode(data.http.repo_details[0].response_body) : {}
  
  # Build the Harness Code connector reference format
  harness_code_repo_url = var.import_repo ? "https://git.harness.io/${var.harness_account_id}/${var.org_id}/${var.project_id}/${var.repo_identifier}" : ""
}
