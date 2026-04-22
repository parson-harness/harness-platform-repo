################################################################################
# Outputs for Harness OPA Policies Module
################################################################################

output "ci_policy_ids" {
  description = "IDs of created CI policies"
  value = {
    require_tests              = var.create_ci_policies ? harness_platform_policy.require_tests[0].identifier : null
    require_cache_intelligence = var.create_ci_policies ? harness_platform_policy.require_cache_intelligence[0].identifier : null
    require_harness_cloud      = var.create_ci_policies ? harness_platform_policy.require_harness_cloud[0].identifier : null
    require_docker_caching     = var.create_ci_policies ? harness_platform_policy.require_docker_caching[0].identifier : null
  }
}

output "security_policy_ids" {
  description = "IDs of created security policies"
  value = {
    no_hardcoded_secrets        = var.create_security_policies ? harness_platform_policy.no_hardcoded_secrets[0].identifier : null
    recommend_artifact_scanning = var.create_security_policies ? harness_platform_policy.recommend_artifact_scanning[0].identifier : null
    require_harness_scanners    = var.create_security_policies ? harness_platform_policy.require_harness_scanners[0].identifier : null
  }
}

output "quality_policy_ids" {
  description = "IDs of created quality gate policies"
  value = {
    require_test_reports  = var.create_quality_policies ? harness_platform_policy.require_test_reports[0].identifier : null
    require_pipeline_tags = var.create_quality_policies ? harness_platform_policy.require_pipeline_tags[0].identifier : null
  }
}

output "change_governance_policy_ids" {
  description = "IDs of created change governance policies"
  value = {
    change_readiness_guardrails = var.create_change_governance_policies ? harness_platform_policy.change_readiness_guardrails[0].identifier : null
    change_validation_quality   = var.create_change_governance_policies ? harness_platform_policy.change_validation_quality[0].identifier : null
    change_qa_playwright_gate   = var.create_change_governance_policies ? harness_platform_policy.change_qa_playwright_gate[0].identifier : null
    change_risk_score           = var.create_change_governance_policies ? harness_platform_policy.change_risk_score[0].identifier : null
  }
}

output "policy_set_ids" {
  description = "IDs of created policy sets"
  value = {
    ci_standards              = var.create_ci_policy_set ? harness_platform_policyset.ci_standards[0].identifier : null
    ci_standards_on_run       = var.create_ci_policy_set ? harness_platform_policyset.ci_standards_on_run[0].identifier : null
    security_standards        = var.create_security_policy_set ? harness_platform_policyset.security_standards[0].identifier : null
    security_standards_on_run = var.create_security_policy_set ? harness_platform_policyset.security_standards_on_run[0].identifier : null
    quality_gates             = var.create_quality_policy_set ? harness_platform_policyset.quality_gates[0].identifier : null
    change_risk_guardrails    = var.create_change_governance_policies && var.create_change_governance_policy_set ? harness_platform_policyset.change_governance_on_step[0].identifier : null
  }
}
