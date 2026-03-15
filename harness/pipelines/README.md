# Harness Pipeline Templates

This directory contains Harness pipeline YAML templates for the demo application.

## Available Pipelines

| Pipeline | File | Description |
|----------|------|-------------|
| CI Build | `ci-build.yaml` | Build, test, scan, and push to ECR |
| CD EKS Canary | `cd-eks-canary.yaml` | Canary deployment to EKS with CV |
| CD EKS Blue-Green | `cd-eks-bluegreen.yaml` | Blue-Green deployment to EKS |
| CD ECS | `cd-ecs.yaml` | Rolling deployment to ECS |

## How to Use

### Option 1: Import via Harness UI

1. Go to your Harness project
2. Navigate to **Pipelines** → **Create Pipeline**
3. Select **Import from Git** or **YAML**
4. Paste the pipeline YAML content
5. Fill in the `<+input>` placeholders with your values

### Option 2: Import via Harness CLI

```bash
harness pipeline create --file harness/pipelines/ci-build.yaml \
  --project <project-id> \
  --org <org-id>
```

### Option 3: Use Harness Terraform Provider

```hcl
resource "harness_platform_pipeline" "ci_build" {
  org_id     = var.org_id
  project_id = var.project_id
  identifier = "ci_build_pipeline"
  name       = "CI Build Pipeline"
  yaml       = file("${path.module}/harness/pipelines/ci-build.yaml")
}
```

## Input Variables

These pipelines use `<+input>` for values that need to be provided at runtime or configured per environment:

| Variable | Description | Example |
|----------|-------------|---------|
| `projectIdentifier` | Harness Project ID | `my_project` |
| `orgIdentifier` | Harness Org ID | `default` |
| `connectorRef` | Git connector reference | `github_connector` |
| `serviceRef` | Service reference | `harness_demo_app` |
| `environmentRef` | Environment reference | `production` |

## CV Canary Rollback Demo

The `cd-eks-canary.yaml` pipeline includes an optional step to trigger chaos injection for demonstrating Continuous Verification rollback:

1. Set the "Trigger Chaos for CV Demo" step condition to `true`
2. Deploy a canary
3. The chaos endpoint will inject latency and errors
4. CV will detect the degradation
5. Pipeline will trigger automatic rollback

See `docs/CV_CANARY_ROLLBACK.md` for detailed instructions.

## Customization

### Adding STO Scanning

Add a Security Testing Orchestration stage:

```yaml
- stage:
    name: Security Scan
    identifier: security_scan
    type: SecurityTests
    spec:
      cloneCodebase: true
      execution:
        steps:
          - step:
              type: Owasp
              name: OWASP Scan
              identifier: owasp_scan
              spec:
                mode: orchestration
                config: default
                target:
                  type: repository
                  detection: auto
```

### Adding Approval Gates

Add a manual approval before production:

```yaml
- step:
    type: HarnessApproval
    name: Approval
    identifier: approval
    spec:
      approvalMessage: "Please review and approve deployment"
      approvers:
        userGroups:
          - account.Production_Approvers
        minimumCount: 1
      approverInputs: []
```
