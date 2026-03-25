# Harness OPA Policies Module

This module creates Open Policy Agent (OPA) policies and policy sets for enforcing CI/CD governance standards in Harness pipelines.

## Features

### CI Pipeline Standards
- **Require Tests**: Ensures CI pipelines include test steps (RunTests or Test type)
- **Require Cache Intelligence**: Recommends enabling Cache Intelligence for faster builds
- **Require Harness Cloud**: Recommends using Harness Cloud build infrastructure
- **Require Docker Layer Caching**: Ensures Docker build steps have caching enabled

### Security Standards
- **No Hardcoded Secrets**: Detects potential hardcoded secrets in pipeline YAML
- **Recommend Artifact Scanning**: Suggests adding STO for container image scanning

### Build Quality Gates
- **Require Test Reports**: Ensures test steps publish JUnit reports
- **Require Pipeline Tags**: Enforces pipeline tagging for organization

## Usage

```hcl
module "opa_policies" {
  source = "../../modules/harness-opa-policies"

  org_id     = var.org_id
  project_id = var.project_id

  # Policy creation flags
  create_ci_policies       = true
  create_security_policies = true
  create_quality_policies  = true

  # Policy set creation flags
  create_ci_policy_set       = true
  create_security_policy_set = true
  create_quality_policy_set  = true

  # Enforcement flags
  enforce_ci_policies       = true
  enforce_security_policies = true
  enforce_quality_policies  = true
}
```

## Policy Sets

| Policy Set | Event | Severity | Description |
|------------|-------|----------|-------------|
| CI Pipeline Standards | On Save | Warning | Recommends CI best practices |
| CI Pipeline Standards (On Run) | On Run | Error | Enforces test requirement at runtime |
| Security Standards | On Save | Error/Warning | Prevents security issues |
| Build Quality Gates | On Save | Warning | Enforces quality standards |

## Harness CI Intelligence Features

These policies help enforce the use of Harness CI's differentiating features:

1. **Test Intelligence** - Run only tests affected by code changes (up to 90% faster)
2. **Cache Intelligence** - Auto-cache dependencies for Maven, Gradle, Node, etc.
3. **Docker Layer Caching** - Reuse Docker image layers across builds
4. **Harness Cloud** - Hosted build infrastructure with resource classes

## Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| org_id | Harness organization identifier | string | - |
| project_id | Harness project identifier | string | - |
| create_ci_policies | Create CI pipeline standard policies | bool | true |
| create_security_policies | Create security standard policies | bool | true |
| create_quality_policies | Create build quality gate policies | bool | true |
| create_ci_policy_set | Create CI standards policy set | bool | true |
| create_security_policy_set | Create security standards policy set | bool | true |
| create_quality_policy_set | Create quality gates policy set | bool | true |
| enforce_ci_policies | Enable enforcement of CI policies | bool | true |
| enforce_security_policies | Enable enforcement of security policies | bool | true |
| enforce_quality_policies | Enable enforcement of quality gate policies | bool | true |

## Outputs

| Name | Description |
|------|-------------|
| ci_policy_ids | IDs of created CI policies |
| security_policy_ids | IDs of created security policies |
| quality_policy_ids | IDs of created quality gate policies |
| policy_set_ids | IDs of created policy sets |
