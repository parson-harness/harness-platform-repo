terraform {
  required_version = ">= 1.6.0"

  required_providers {
    harness = {
      source  = "harness/harness"
      version = "~> 0.38.0"
    }
  }
}

provider "harness" {
  endpoint         = "${trimsuffix(trimsuffix(trimsuffix(var.harness_endpoint, "/"), "/gratis"), "/gateway")}/gateway"
  account_id       = var.harness_account_id
  platform_api_key = var.harness_api_key
}

locals {
  governance_tags = ["tofu-managed", "project-governance", var.harness_project_id]
}

module "harness_org_project" {
  source = "../../modules/harness-org-project"

  create_organization      = var.create_harness_org
  existing_org_id          = var.harness_org_id
  organization_id          = var.harness_org_id
  organization_name        = title(replace(var.harness_org_id, "_", " "))
  organization_description = "Project-scoped governance bootstrap for ${var.harness_org_id}"

  create_project      = var.create_harness_project
  existing_project_id = var.harness_project_id
  project_id          = var.harness_project_id
  project_name        = title(replace(var.harness_project_id, "_", " "))
  project_description = "Project-scoped governance bootstrap for ${var.harness_project_id}"

  tags = local.governance_tags
}

locals {
  resolved_org_id     = module.harness_org_project.org_id
  resolved_project_id = module.harness_org_project.project_id
}

resource "terraform_data" "adopt_existing_project_governance" {
  triggers_replace = {
    account_id = var.harness_account_id
    org_id     = local.resolved_org_id
    project_id = local.resolved_project_id
  }

  depends_on = [module.harness_org_project]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail

      api_delete() {
        identifier="$1"
        url="$2"
        response_file=$(mktemp)
        headers_file=$(mktemp)
        curl -s -D "$headers_file" -o "$response_file" -X DELETE "$url" \
          -H "Harness-Account: ${var.harness_account_id}" \
          -H "x-api-key: ${var.harness_api_key}" >/dev/null
        status_code=$(awk 'toupper($1) ~ /^HTTP\// { code = $2 } END { print code }' "$headers_file")

        if [ "$status_code" != "200" ] && [ "$status_code" != "204" ] && [ "$status_code" != "404" ]; then
          echo "Failed to delete $${identifier} (HTTP $${status_code})"
          cat "$response_file"
          rm -f "$headers_file"
          rm -f "$response_file"
          exit 1
        fi

        rm -f "$headers_file"
        rm -f "$response_file"
      }

      for policy_set in ci_pipeline_standards ci_pipeline_standards_on_run security_standards security_standards_on_run build_quality_gates change_risk_guardrails; do
        api_delete "$policy_set" "${var.harness_endpoint}/pm/api/v1/policysets/$${policy_set}?accountIdentifier=${var.harness_account_id}&orgIdentifier=${local.resolved_org_id}&projectIdentifier=${local.resolved_project_id}"
      done

      for policy in require_tests_in_ci require_cache_intelligence require_harness_cloud require_docker_layer_caching no_hardcoded_secrets recommend_artifact_scanning require_test_reports require_harness_scanners require_pipeline_tags change_readiness_guardrails change_validation_quality change_qa_playwright_gate change_risk_score; do
        api_delete "$policy" "${var.harness_endpoint}/pm/api/v1/policies/$${policy}?accountIdentifier=${var.harness_account_id}&orgIdentifier=${local.resolved_org_id}&projectIdentifier=${local.resolved_project_id}"
      done
    EOT
  }
}

module "opa_policies" {
  source = "../../modules/harness-opa-policies"

  org_id     = local.resolved_org_id
  project_id = local.resolved_project_id

  create_ci_policies                  = var.create_ci_policies
  create_security_policies            = var.create_security_policies
  create_quality_policies             = var.create_quality_policies
  create_change_governance_policies   = var.create_change_governance_policies
  create_ci_policy_set                = var.create_ci_policy_set
  create_security_policy_set          = var.create_security_policy_set
  create_quality_policy_set           = var.create_quality_policy_set
  create_change_governance_policy_set = var.create_change_governance_policy_set
  enforce_ci_policies                 = var.enforce_ci_policies
  enforce_security_policies           = var.enforce_security_policies
  enforce_quality_policies            = var.enforce_quality_policies
  enforce_change_governance_policies  = var.enforce_change_governance_policies
  policy_scope_tag                    = var.policy_scope_tag

  depends_on = [module.harness_org_project, terraform_data.adopt_existing_project_governance]
}
