################################################################################
# Harness Code Repository Module
# Creates a Harness Code repo and populates it by cloning from another
# Harness Code repo (git.harness.io) using the Harness API key for auth.
# source_repo should be the git.harness.io path: accountId/org/project/repo
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
# Create and Populate Repository in Harness Code
################################################################################

resource "terraform_data" "import_repo" {
  count = var.import_repo ? 1 : 0

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
        echo "Repo '${var.repo_identifier}' already exists in Harness Code, skipping"
        exit 0
      fi

      echo "Creating Harness Code repo '${var.repo_identifier}'..."
      CREATE_RESP=$(curl -s -w "\n%%{http_code}" -X POST \
        "${var.harness_endpoint}/code/api/v1/repos?accountIdentifier=${var.harness_account_id}&orgIdentifier=${var.org_id}&projectIdentifier=${var.project_id}" \
        -H "Content-Type: application/json" \
        -H "x-api-key: ${var.harness_api_key}" \
        -d "{\"identifier\": \"${var.repo_identifier}\", \"description\": \"${var.repo_description}\", \"is_public\": false, \"default_branch\": \"main\"}")
      CREATE_CODE=$(echo "$CREATE_RESP" | tail -n1)
      echo "Create response code: $CREATE_CODE"
      if [ "$CREATE_CODE" != "200" ] && [ "$CREATE_CODE" != "201" ]; then
        echo "Failed to create repo: $(echo "$CREATE_RESP" | head -n -1)"
        exit 1
      fi

      echo "Cloning from Harness Code source '${var.source_repo}'..."
      TEMP_DIR=$(mktemp -d)
      git clone "https://token:${var.harness_api_key}@git.harness.io/${var.source_repo}.git" "$TEMP_DIR/source" --quiet
      if [ $? -ne 0 ]; then
        echo "Failed to clone source repo '${var.source_repo}'"
        rm -rf "$TEMP_DIR"
        exit 1
      fi
      cd "$TEMP_DIR/source"
      git remote set-url origin "https://token:${var.harness_api_key}@git.harness.io/${var.harness_account_id}/${var.org_id}/${var.project_id}/${var.repo_identifier}.git"
      git push origin main --quiet
      PUSH_RESULT=$?
      cd /tmp
      rm -rf "$TEMP_DIR"
      if [ $PUSH_RESULT -ne 0 ]; then
        echo "Failed to push to destination repo"
        exit 1
      fi
      echo "Repo '${var.repo_identifier}' created and populated from '${var.source_repo}' successfully"
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
