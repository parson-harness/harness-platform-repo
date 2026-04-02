################################################################################
# Harness OPA Policies Module
# Creates OPA policies and policy sets for CI/CD governance
#
# Policy Categories:
# 1. CI Pipeline Standards - Enforce best practices for CI pipelines
# 2. Security Standards - Ensure security requirements are met
# 3. Build Quality Gates - Enforce quality standards
#
# Policy Scope:
# By default, policies only apply to pipelines with the tag specified in
# var.policy_scope_tag (default: "managed-by:provisioner"). This prevents
# the policies from affecting other pipelines in the project.
################################################################################

terraform {
  required_providers {
    harness = {
      source  = "harness/harness"
      version = ">= 0.31.0"
    }
  }
}

locals {
  # Parse the scope tag into key and value
  scope_tag_parts = var.policy_scope_tag != "" ? split(":", var.policy_scope_tag) : []
  scope_tag_key   = length(local.scope_tag_parts) >= 1 ? local.scope_tag_parts[0] : ""
  scope_tag_value = length(local.scope_tag_parts) >= 2 ? local.scope_tag_parts[1] : ""

  # Rego snippet to check if pipeline has the required scope tag
  # If no scope tag is configured, this evaluates to true (apply to all)
  # 
  # IMPORTANT: in_scope is ONLY true when the pipeline has the required tag.
  # Pipelines WITHOUT the tag are NOT in scope, so deny rules won't fire.
  scope_check_rego_with_tag = <<-REGO
    # Only apply to pipelines with the required scope tag
    # Pipelines without this tag will NOT match, so deny rules won't fire
    in_scope {
      input.pipeline.tags["${local.scope_tag_key}"] == "${local.scope_tag_value}"
    }
  REGO

  scope_check_rego_all = <<-REGO
    # No scope tag configured - apply to all pipelines
    in_scope { true }
  REGO

  scope_check_rego = var.policy_scope_tag != "" ? local.scope_check_rego_with_tag : local.scope_check_rego_all
}

################################################################################
# CI Pipeline Standards Policies
################################################################################

# Policy: Require Test Step in CI Pipelines
resource "harness_platform_policy" "require_tests" {
  count      = var.create_ci_policies ? 1 : 0
  identifier = "require_tests_in_ci"
  name       = "Require Tests in CI Pipeline"
  org_id     = var.org_id
  project_id = var.project_id

  rego = <<-REGO
    package pipeline

    ${local.scope_check_rego}

    # Deny CI pipelines that don't have a test step (only if in scope)
    deny[msg] {
      in_scope
      input.pipeline.stages[i].stage.type == "CI"
      stage := input.pipeline.stages[i].stage
      not has_test_step(stage)
      msg := sprintf("CI stage '%s' must include a test step (RunTests or Test type). Test Intelligence can reduce test time by up to 90%%.", [stage.name])
    }

    # Check if stage has a test step
    has_test_step(stage) {
      stage.spec.execution.steps[_].step.type == "RunTests"
    }

    has_test_step(stage) {
      stage.spec.execution.steps[_].step.type == "Test"
    }

    has_test_step(stage) {
      stage.spec.execution.steps[_].stepGroup.steps[_].step.type == "RunTests"
    }

    has_test_step(stage) {
      stage.spec.execution.steps[_].stepGroup.steps[_].step.type == "Test"
    }

    # Check for RunTests inside parallel blocks within stepGroups
    has_test_step(stage) {
      stage.spec.execution.steps[_].stepGroup.steps[_].parallel[_].step.type == "RunTests"
    }

    has_test_step(stage) {
      stage.spec.execution.steps[_].stepGroup.steps[_].parallel[_].step.type == "Test"
    }
  REGO
}

# Policy: Require Cache Intelligence
resource "harness_platform_policy" "require_cache_intelligence" {
  count      = var.create_ci_policies ? 1 : 0
  identifier = "require_cache_intelligence"
  name       = "Require Cache Intelligence"
  org_id     = var.org_id
  project_id = var.project_id

  rego = <<-REGO
    package pipeline

    ${local.scope_check_rego}

    # Warn if CI stage doesn't have Cache Intelligence enabled (only if in scope)
    warn[msg] {
      in_scope
      input.pipeline.stages[i].stage.type == "CI"
      stage := input.pipeline.stages[i].stage
      not cache_enabled(stage)
      msg := sprintf("CI stage '%s' should enable Cache Intelligence (caching.enabled: true) to speed up builds by caching dependencies.", [stage.name])
    }

    cache_enabled(stage) {
      stage.spec.caching.enabled == true
    }
  REGO
}

# Policy: Require Harness Cloud for CI
resource "harness_platform_policy" "require_harness_cloud" {
  count      = var.create_ci_policies ? 1 : 0
  identifier = "require_harness_cloud"
  name       = "Recommend Harness Cloud Build Infrastructure"
  org_id     = var.org_id
  project_id = var.project_id

  rego = <<-REGO
    package pipeline

    ${local.scope_check_rego}

    # Warn if not using Harness Cloud (only if in scope)
    warn[msg] {
      in_scope
      input.pipeline.stages[i].stage.type == "CI"
      stage := input.pipeline.stages[i].stage
      not uses_harness_cloud(stage)
      msg := sprintf("CI stage '%s' is not using Harness Cloud. Consider using Harness Cloud for faster builds with Test Intelligence, Cache Intelligence, and Docker Layer Caching.", [stage.name])
    }

    uses_harness_cloud(stage) {
      stage.spec.runtime.type == "Cloud"
    }
  REGO
}

# Policy: Require Docker Layer Caching
resource "harness_platform_policy" "require_docker_caching" {
  count      = var.create_ci_policies ? 1 : 0
  identifier = "require_docker_layer_caching"
  name       = "Require Docker Layer Caching"
  org_id     = var.org_id
  project_id = var.project_id

  rego = <<-REGO
    package pipeline

    ${local.scope_check_rego}

    # Warn if BuildAndPush steps don't have caching enabled (only if in scope)
    warn[msg] {
      in_scope
      input.pipeline.stages[i].stage.type == "CI"
      stage := input.pipeline.stages[i].stage
      step := stage.spec.execution.steps[_].step
      is_build_push_step(step)
      not docker_caching_enabled(step)
      msg := sprintf("Docker build step '%s' should enable caching (caching: true) to reuse image layers and speed up builds.", [step.name])
    }

    is_build_push_step(step) {
      step.type == "BuildAndPushDockerRegistry"
    }

    is_build_push_step(step) {
      step.type == "BuildAndPushECR"
    }

    is_build_push_step(step) {
      step.type == "BuildAndPushGCR"
    }

    is_build_push_step(step) {
      step.type == "BuildAndPushACR"
    }

    docker_caching_enabled(step) {
      step.spec.caching == true
    }
  REGO
}

################################################################################
# Security Standards Policies
################################################################################

# Policy: No Hardcoded Secrets
resource "harness_platform_policy" "no_hardcoded_secrets" {
  count      = var.create_security_policies ? 1 : 0
  identifier = "no_hardcoded_secrets"
  name       = "No Hardcoded Secrets in Pipelines"
  org_id     = var.org_id
  project_id = var.project_id

  rego = <<-REGO
    package pipeline

    import future.keywords.in

    ${local.scope_check_rego}

    # Deny pipelines with potential hardcoded secrets (only if in scope)
    deny[msg] {
      in_scope
      walk(input.pipeline, [path, value])
      is_string(value)
      looks_like_secret(value)
      not is_harness_expression(value)
      msg := sprintf("Potential hardcoded secret found at path %v. Use Harness Secrets Manager instead.", [path])
    }

    # Patterns that look like secrets
    looks_like_secret(value) {
      # AWS Access Key pattern
      regex.match(`AKIA[0-9A-Z]{16}`, value)
    }

    looks_like_secret(value) {
      # Generic API key pattern (long alphanumeric strings)
      regex.match(`^[a-zA-Z0-9]{32,}$`, value)
    }

    looks_like_secret(value) {
      # Password-like field values
      contains(lower(value), "password=")
    }

    # Check if value is a Harness expression (safe)
    is_harness_expression(value) {
      contains(value, "<+")
    }
  REGO
}

# Policy: Require Artifact Scanning (placeholder for STO)
resource "harness_platform_policy" "recommend_artifact_scanning" {
  count      = var.create_security_policies ? 1 : 0
  identifier = "recommend_artifact_scanning"
  name       = "Recommend Artifact Scanning"
  org_id     = var.org_id
  project_id = var.project_id

  rego = <<-REGO
    package pipeline

    ${local.scope_check_rego}

    # Advisory: Recommend STO scanning for production pipelines (only if in scope)
    warn[msg] {
      in_scope
      input.pipeline.stages[i].stage.type == "CI"
      has_docker_build(input.pipeline.stages[i].stage)
      not has_security_scan(input.pipeline)
      msg := "Consider adding Security Testing Orchestration (STO) to scan container images for vulnerabilities before deployment."
    }

    has_docker_build(stage) {
      stage.spec.execution.steps[_].step.type == "BuildAndPushDockerRegistry"
    }

    has_docker_build(stage) {
      stage.spec.execution.steps[_].step.type == "BuildAndPushECR"
    }

    has_security_scan(pipeline) {
      pipeline.stages[_].stage.type == "SecurityTests"
    }

    has_security_scan(pipeline) {
      pipeline.stages[_].stage.spec.execution.steps[_].step.type == "Security"
    }
  REGO
}

################################################################################
# Build Quality Gates Policies
################################################################################

# Policy: Require JUnit Test Reports
resource "harness_platform_policy" "require_test_reports" {
  count      = var.create_quality_policies ? 1 : 0
  identifier = "require_test_reports"
  name       = "Require Test Reports"
  org_id     = var.org_id
  project_id = var.project_id

  rego = <<-REGO
    package pipeline

    ${local.scope_check_rego}

    # Warn if test steps don't publish reports (only if in scope)
    warn[msg] {
      in_scope
      input.pipeline.stages[i].stage.type == "CI"
      stage := input.pipeline.stages[i].stage
      step := stage.spec.execution.steps[_].step
      is_test_step(step)
      not has_reports(step)
      msg := sprintf("Test step '%s' should publish JUnit reports for visibility in the Tests tab.", [step.name])
    }

    warn[msg] {
      in_scope
      input.pipeline.stages[i].stage.type == "CI"
      stage := input.pipeline.stages[i].stage
      step := stage.spec.execution.steps[_].stepGroup.steps[_].step
      is_test_step(step)
      not has_reports(step)
      msg := sprintf("Test step '%s' should publish JUnit reports for visibility in the Tests tab.", [step.name])
    }

    is_test_step(step) {
      step.type == "RunTests"
    }

    is_test_step(step) {
      step.type == "Test"
    }

    has_reports(step) {
      step.spec.reports
    }
  REGO
}

# Policy: Require Harness Security Scanners
resource "harness_platform_policy" "require_harness_scanners" {
  count      = var.create_security_policies ? 1 : 0
  identifier = "require_harness_scanners"
  name       = "Require Harness Security Scanners"
  org_id     = var.org_id
  project_id = var.project_id

  rego = <<-REGO
    package pipeline

    ${local.scope_check_rego}

    # Deny CI pipelines that build containers but don't have required Harness scanners (only if in scope)
    deny[msg] {
      in_scope
      input.pipeline.stages[i].stage.type == "CI"
      stage := input.pipeline.stages[i].stage
      has_docker_build(stage)
      not has_gitleaks(stage)
      msg := sprintf("CI stage '%s' must include Gitleaks secret scanning step for security compliance.", [stage.name])
    }

    deny[msg] {
      in_scope
      input.pipeline.stages[i].stage.type == "CI"
      stage := input.pipeline.stages[i].stage
      has_docker_build(stage)
      not has_harness_sast(stage)
      msg := sprintf("CI stage '%s' must include HarnessSAST step for static application security testing.", [stage.name])
    }

    deny[msg] {
      in_scope
      input.pipeline.stages[i].stage.type == "CI"
      stage := input.pipeline.stages[i].stage
      has_docker_build(stage)
      not has_harness_sca(stage)
      msg := sprintf("CI stage '%s' must include HarnessSCA step for software composition analysis.", [stage.name])
    }

    # Check for Docker build steps
    has_docker_build(stage) {
      stage.spec.execution.steps[_].step.type == "BuildAndPushDockerRegistry"
    }

    has_docker_build(stage) {
      stage.spec.execution.steps[_].step.type == "BuildAndPushECR"
    }

    # Check for Gitleaks
    has_gitleaks(stage) {
      stage.spec.execution.steps[_].step.type == "Gitleaks"
    }

    has_gitleaks(stage) {
      stage.spec.execution.steps[_].stepGroup.steps[_].step.type == "Gitleaks"
    }

    # Check for HarnessSAST
    has_harness_sast(stage) {
      stage.spec.execution.steps[_].step.type == "HarnessSAST"
    }

    has_harness_sast(stage) {
      stage.spec.execution.steps[_].stepGroup.steps[_].step.type == "HarnessSAST"
    }

    has_harness_sast(stage) {
      stage.spec.execution.steps[_].stepGroup.steps[_].parallel[_].step.type == "HarnessSAST"
    }

    # Check for HarnessSCA
    has_harness_sca(stage) {
      stage.spec.execution.steps[_].step.type == "HarnessSCA"
    }

    has_harness_sca(stage) {
      stage.spec.execution.steps[_].stepGroup.steps[_].step.type == "HarnessSCA"
    }

    has_harness_sca(stage) {
      stage.spec.execution.steps[_].stepGroup.steps[_].parallel[_].step.type == "HarnessSCA"
    }
  REGO
}

# Policy: Require Code Coverage
resource "harness_platform_policy" "require_code_coverage" {
  count      = var.create_quality_policies ? 1 : 0
  identifier = "require_code_coverage"
  name       = "Require Code Coverage"
  org_id     = var.org_id
  project_id = var.project_id

  rego = <<-REGO
    package pipeline

    ${local.scope_check_rego}

    # Warn if CI pipeline doesn't have code coverage step (only if in scope)
    warn[msg] {
      in_scope
      input.pipeline.stages[i].stage.type == "CI"
      stage := input.pipeline.stages[i].stage
      has_test_step(stage)
      not has_coverage_step(stage)
      msg := sprintf("CI stage '%s' should include a code coverage step (e.g., JaCoCo) to track test coverage metrics.", [stage.name])
    }

    has_test_step(stage) {
      stage.spec.execution.steps[_].step.type == "RunTests"
    }

    has_test_step(stage) {
      stage.spec.execution.steps[_].stepGroup.steps[_].step.type == "RunTests"
    }

    has_test_step(stage) {
      stage.spec.execution.steps[_].stepGroup.steps[_].parallel[_].step.type == "RunTests"
    }

    # Check for coverage step (Run step with "coverage" or "jacoco" in name/identifier)
    has_coverage_step(stage) {
      step := stage.spec.execution.steps[_].step
      step.type == "Run"
      contains(lower(step.identifier), "coverage")
    }

    has_coverage_step(stage) {
      step := stage.spec.execution.steps[_].step
      step.type == "Run"
      contains(lower(step.name), "coverage")
    }

    has_coverage_step(stage) {
      step := stage.spec.execution.steps[_].step
      step.type == "Run"
      contains(lower(step.identifier), "jacoco")
    }
  REGO
}

# Policy: Require Pipeline Tags
resource "harness_platform_policy" "require_pipeline_tags" {
  count      = var.create_quality_policies ? 1 : 0
  identifier = "require_pipeline_tags"
  name       = "Require Pipeline Tags"
  org_id     = var.org_id
  project_id = var.project_id

  rego = <<-REGO
    package pipeline

    ${local.scope_check_rego}

    # Warn if pipeline doesn't have required tags (only if in scope)
    warn[msg] {
      in_scope
      not input.pipeline.tags
      msg := "Pipeline should have tags for better organization and filtering (e.g., pipeline-type, team, environment)."
    }

    warn[msg] {
      in_scope
      input.pipeline.tags
      not has_pipeline_type_tag
      msg := "Pipeline should have a 'pipeline-type' tag (e.g., ci, cd, security) for categorization."
    }

    has_pipeline_type_tag {
      input.pipeline.tags["pipeline-type"]
    }
  REGO
}

################################################################################
# Change Governance Policies
################################################################################

resource "harness_platform_policy" "change_readiness_guardrails" {
  count      = var.create_change_governance_policies ? 1 : 0
  identifier = "change_readiness_guardrails"
  name       = "Change Readiness Guardrails"
  org_id     = var.org_id
  project_id = var.project_id

  rego = <<-REGO
    package change_governance

    deny[msg] {
      input.change.freeze_window_active == true
      msg := "Change falls inside an active freeze window. Manual CAB approval is required."
    }

    deny[msg] {
      input.validation.operations.rollback_ready != true
      msg := "Rollback readiness must be verified before the change can auto-approve."
    }

    deny[msg] {
      lower(input.change.environment) == "prod"
      input.change.requires_data_migration == true
      msg := "Production changes with data migration require manual CAB review."
    }
  REGO
}

resource "harness_platform_policy" "change_validation_quality" {
  count      = var.create_change_governance_policies ? 1 : 0
  identifier = "change_validation_quality"
  name       = "Change Validation Quality"
  org_id     = var.org_id
  project_id = var.project_id

  rego = <<-REGO
    package change_governance

    deny[msg] {
      input.validation.tests.pass_rate < 95
      msg := sprintf("Automated test pass rate %.1f%% is below the 95%% threshold.", [input.validation.tests.pass_rate])
    }

    deny[msg] {
      input.validation.security.critical_vulns > 0
      msg := sprintf("Critical vulnerabilities detected: %v.", [input.validation.security.critical_vulns])
    }

    deny[msg] {
      input.validation.security.high_vulns > 2
      msg := sprintf("High vulnerabilities (%v) exceed the allowed threshold of 2 for auto-approval.", [input.validation.security.high_vulns])
    }

    deny[msg] {
      input.validation.operations.open_failures > 0
      msg := sprintf("There are %v unresolved operational issues tied to this release.", [input.validation.operations.open_failures])
    }
  REGO
}

resource "harness_platform_policy" "change_risk_score" {
  count      = var.create_change_governance_policies ? 1 : 0
  identifier = "change_risk_score"
  name       = "Change Risk Score"
  org_id     = var.org_id
  project_id = var.project_id

  rego = <<-REGO
    package change_governance

    blast_radius_score := 1 {
      lower(input.change.blast_radius) == "low"
    }

    blast_radius_score := 2 {
      lower(input.change.blast_radius) == "medium"
    }

    blast_radius_score := 3 {
      lower(input.change.blast_radius) == "high"
    }

    environment_score := 1 {
      lower(input.change.environment) != "prod"
    }

    environment_score := 3 {
      lower(input.change.environment) == "prod"
    }

    deployment_strategy_score := 1 {
      lower(input.change.deployment_strategy) == "canary"
    }

    deployment_strategy_score := 1 {
      lower(input.change.deployment_strategy) == "bluegreen"
    }

    deployment_strategy_score := 2 {
      lower(input.change.deployment_strategy) == "rolling"
    }

    deployment_strategy_score := 2 {
      lower(input.change.deployment_strategy) == "recreate"
    }

    data_migration_score := 0 {
      input.change.requires_data_migration != true
    }

    data_migration_score := 2 {
      input.change.requires_data_migration == true
    }

    vulnerability_score := 0 {
      input.validation.security.high_vulns <= 0
    }

    vulnerability_score := 1 {
      input.validation.security.high_vulns == 1
    }

    vulnerability_score := 2 {
      input.validation.security.high_vulns >= 2
    }

    risk_score := blast_radius_score + environment_score + deployment_strategy_score + data_migration_score + vulnerability_score

    deny[msg] {
      risk_score >= 7
      msg := sprintf("Calculated change risk score is %v, which requires manual approval.", [risk_score])
    }
  REGO
}

################################################################################
# Policy Sets
################################################################################

# CI Standards Policy Set - Applied On Save
resource "harness_platform_policyset" "ci_standards" {
  count      = var.create_ci_policy_set ? 1 : 0
  identifier = "ci_pipeline_standards"
  name       = "CI Pipeline Standards"
  org_id     = var.org_id
  project_id = var.project_id
  action     = "onsave"
  type       = "pipeline"
  enabled    = var.enforce_ci_policies

  policies {
    identifier = harness_platform_policy.require_tests[0].identifier
    severity   = "warning"
  }

  policies {
    identifier = harness_platform_policy.require_cache_intelligence[0].identifier
    severity   = "warning"
  }

  policies {
    identifier = harness_platform_policy.require_harness_cloud[0].identifier
    severity   = "warning"
  }

  policies {
    identifier = harness_platform_policy.require_docker_caching[0].identifier
    severity   = "warning"
  }

  depends_on = [
    harness_platform_policy.require_tests,
    harness_platform_policy.require_cache_intelligence,
    harness_platform_policy.require_harness_cloud,
    harness_platform_policy.require_docker_caching
  ]
}

# CI Standards Policy Set - Applied On Run (stricter)
resource "harness_platform_policyset" "ci_standards_on_run" {
  count      = var.create_ci_policy_set ? 1 : 0
  identifier = "ci_pipeline_standards_on_run"
  name       = "CI Pipeline Standards (On Run)"
  org_id     = var.org_id
  project_id = var.project_id
  action     = "onrun"
  type       = "pipeline"
  enabled    = var.enforce_ci_policies

  policies {
    identifier = harness_platform_policy.require_tests[0].identifier
    severity   = "error"
  }

  depends_on = [
    harness_platform_policy.require_tests
  ]
}

# Security Policy Set
resource "harness_platform_policyset" "security_standards" {
  count      = var.create_security_policy_set ? 1 : 0
  identifier = "security_standards"
  name       = "Security Standards"
  org_id     = var.org_id
  project_id = var.project_id
  action     = "onsave"
  type       = "pipeline"
  enabled    = var.enforce_security_policies

  policies {
    identifier = harness_platform_policy.no_hardcoded_secrets[0].identifier
    severity   = "error"
  }

  policies {
    identifier = harness_platform_policy.recommend_artifact_scanning[0].identifier
    severity   = "warning"
  }

  policies {
    identifier = harness_platform_policy.require_harness_scanners[0].identifier
    severity   = "warning"
  }

  depends_on = [
    harness_platform_policy.no_hardcoded_secrets,
    harness_platform_policy.recommend_artifact_scanning,
    harness_platform_policy.require_harness_scanners
  ]
}

# Security Policy Set - On Run (stricter enforcement)
resource "harness_platform_policyset" "security_standards_on_run" {
  count      = var.create_security_policy_set ? 1 : 0
  identifier = "security_standards_on_run"
  name       = "Security Standards (On Run)"
  org_id     = var.org_id
  project_id = var.project_id
  action     = "onrun"
  type       = "pipeline"
  enabled    = var.enforce_security_policies

  policies {
    identifier = harness_platform_policy.require_harness_scanners[0].identifier
    severity   = "error"
  }

  depends_on = [
    harness_platform_policy.require_harness_scanners
  ]
}

# Quality Gates Policy Set
resource "harness_platform_policyset" "quality_gates" {
  count      = var.create_quality_policy_set ? 1 : 0
  identifier = "build_quality_gates"
  name       = "Build Quality Gates"
  org_id     = var.org_id
  project_id = var.project_id
  action     = "onsave"
  type       = "pipeline"
  enabled    = var.enforce_quality_policies

  policies {
    identifier = harness_platform_policy.require_test_reports[0].identifier
    severity   = "warning"
  }

  policies {
    identifier = harness_platform_policy.require_pipeline_tags[0].identifier
    severity   = "warning"
  }

  policies {
    identifier = harness_platform_policy.require_code_coverage[0].identifier
    severity   = "warning"
  }

  depends_on = [
    harness_platform_policy.require_test_reports,
    harness_platform_policy.require_pipeline_tags,
    harness_platform_policy.require_code_coverage
  ]
}

resource "harness_platform_policyset" "change_governance_on_step" {
  count      = var.create_change_governance_policies && var.create_change_governance_policy_set ? 1 : 0
  identifier = "change_risk_guardrails"
  name       = "Change Risk Guardrails"
  org_id     = var.org_id
  project_id = var.project_id
  action     = "onstep"
  type       = "custom"
  enabled    = var.enforce_change_governance_policies

  policies {
    identifier = harness_platform_policy.change_readiness_guardrails[0].identifier
    severity   = "error"
  }

  policies {
    identifier = harness_platform_policy.change_validation_quality[0].identifier
    severity   = "error"
  }

  policies {
    identifier = harness_platform_policy.change_risk_score[0].identifier
    severity   = "error"
  }

  depends_on = [
    harness_platform_policy.change_readiness_guardrails,
    harness_platform_policy.change_validation_quality,
    harness_platform_policy.change_risk_score
  ]
}
