# Harness POV Provisioning with IACM

This directory contains Harness pipeline definitions for provisioning POV-in-a-box environments using Infrastructure as Code Management (IACM).

## Resource Lifecycle Management

### Philosophy: Terraform State is the Source of Truth

All POV resources are managed by Terraform state. The pipelines are designed to:

1. **Use Terraform destroy** when cleaning up existing resources (not API calls)
2. **Only use API cleanup** for true orphans (resources with no workspace/state)
3. **Preserve state integrity** by never deleting resources outside of Terraform

### Provisioner Behavior

The `idp_pov_provisioner` pipeline handles three scenarios:

| Scenario | Workspace Exists? | force_recreate | Behavior |
|----------|-------------------|----------------|----------|
| Fresh provision | No | N/A | Create workspace, apply Terraform |
| Update existing | Yes | false | Apply Terraform to existing state |
| Clean slate | Yes | true | Terraform destroy → delete workspace → create fresh |
| Orphan cleanup | No (but resources exist) | N/A | API cleanup → create workspace → apply |

### Destroyer Behavior

The `idp_pov_destroyer_v2` pipeline:

1. **Unblock Destroy**: Delete K8s deployments (removes "active instances" from Harness service)
2. **Terraform Destroy**: Let Terraform delete resources with proper dependency ordering
3. **Cleanup Orphans**: API-delete any resources Terraform couldn't remove
4. **Delete Workspace**: Remove IACM workspace after successful cleanup

### Sandbox Janitor Behavior

The scheduled janitor uses the linked IACM workspace as the source of truth instead of maintaining a separate sandbox inventory.

1. **Query linked workspaces**: Read all `_pov` and `_sandbox` workspaces in the project
2. **Classify by template metadata**: Use `workspace_template_id`, `deployment_target`, `sandbox_profile`, `ttl_days`, and `created_at`
3. **Audit first**: `sandbox_ttl_cleanup` with `dry_run=true` reports expired sandboxes without deleting anything
4. **Audit orphaned ASG VPCs**: The janitor also scans AWS for `tofu`-managed ASG VPCs whose `Owner` tag no longer has an active linked workspace
5. **Destroy through the robust path**: Expired workspaces and orphaned ASG VPC cleanup are both handed to `idp_pov_destroyer_v2`, not the legacy `pov_destroy` pipeline
6. **Preserve template linkage**: Template-family filtering stays aligned with `POV_Provisioner` and `Sandbox_Provisioner_ASG`

### Why API Cleanup Still Exists

API cleanup is a **fallback**, not the primary mechanism. It handles:

- Resources Terraform couldn't delete (dependency issues, API errors)
- Resources created outside Terraform
- True orphans (workspace deleted but resources remain)

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  IDP Workflow Form                                              │
│  └── Collects: owner, account_id, org, project, etc.            │
│  └── File: workflows/pov_provisioner_workflow.yaml              │
└─────────────────────────────────────────────────────────────────┘
                               ↓
┌─────────────────────────────────────────────────────────────────┐
│  Pipeline: idp_pov_provisioner                                  │
│  └── Creates workspace from POV_Provisioner template            │
│  └── Links workspace with "Use Template" for central mgmt       │
└─────────────────────────────────────────────────────────────────┘
                               ↓
┌─────────────────────────────────────────────────────────────────┐
│  IACM Workspace Template: POV_Provisioner (v1.0)                │
│  └── Centrally managed workspace configuration                  │
│  └── Changes propagate to all linked workspaces                 │
└─────────────────────────────────────────────────────────────────┘
                               ↓
┌─────────────────────────────────────────────────────────────────┐
│  IACM Workspace: {owner}_pov                                    │
│  └── Created dynamically per POV owner                          │
│  └── Inherits config from template, overrides runtime vars      │
└─────────────────────────────────────────────────────────────────┘
                               ↓
┌─────────────────────────────────────────────────────────────────┐
│  OpenTofu: tofu/stacks/eks                                      │
│  └── Creates: Namespace, Connectors, Service, Environment, etc. │
│  └── Uses EXISTING EKS cluster and delegate                     │
└─────────────────────────────────────────────────────────────────┘
```

## Workspace Template Architecture

### Why Templates?

The POV provisioner uses IACM **Workspace Templates** with "Use Template" linkage for:

1. **Central Management**: Update the template once, changes propagate to all POV workspaces
2. **Consistency**: All POVs use the same base configuration
3. **Simplified Pipeline**: Pipeline only passes runtime-specific variables (owner, API keys)
4. **No State Management Needed**: Workspace metadata is Harness platform state, not Terraform

### Template vs Workspace State

| What | Where State Lives | Managed By |
|------|-------------------|------------|
| Workspace Template | Harness Platform | You (via UI/API) |
| Workspace Metadata | Harness Platform | IDP Pipeline |
| Terraform State | IACM Backend | Each Workspace |
| Provisioned Resources | AWS/Harness | Terraform |

**Key Insight**: You do NOT need a separate IACM workspace to manage POV workspaces. The workspace creation is a Harness API call, not a Terraform resource.

### Templates Available

| Template | Version | Use Case |
|----------|---------|----------|
| `POV_Provisioner` | 1.0 | POV-in-a-Box (shared EKS, cross-account) |
| `Sandbox_Provisioner_ASG` | 1.0 | Self-contained ASG POV sandboxes |
| `Project_Governance` | 1.0 | Project-scoped governance workspace |

### Template Metadata for Janitor and Bulk Operations

The janitor and bulk-update flows rely on workspace metadata that is persisted into each linked workspace:

| Variable | Purpose |
|----------|---------|
| `workspace_template_id` | Template family classifier (`POV_Provisioner` or `Sandbox_Provisioner_ASG`) |
| `deployment_target` | Distinguishes `eks` vs `asg` cleanup behavior |
| `sandbox_profile` | Lets the janitor scope by recommended profile |
| `ttl_days` | Cleanup retention window (`0` means protected) |
| `created_at` | TTL start timestamp |
| `last_touched_at` | Last reconciliation timestamp |

### Adding Variables to Template

To add a new tfvar that should be centrally managed:

1. Go to **Templates** → **POV_Provisioner** → **Open in Template Studio**
2. Add the variable in the **Variables** tab
3. Set `locked: false` if workspaces can override, `locked: true` if not
4. Save a new version (e.g., `1.1`)
5. Update pipeline to reference new version

## Setup Instructions

### Step 1: Verify Workspace Template Exists

The `POV_Provisioner` template should already exist in the `sandbox/parson` project. To verify:

1. Navigate to **Project Settings** → **Templates**
2. Look for `POV_Provisioner` (type: Workspace)
3. If missing, create it with these settings:

   **Repository:**
   - Git Connector: `parsongh`
   - Repository: `harness-demo-app`
   - Branch: `main`
   - Path: `tofu/stacks/eks`

   **Provisioner:**
   - Type: `OpenTofu`
   - Version: `1.11.2`
   - Provider Connector: `aws_oidc_iacm`

   **Default Pipelines:**
   - Plan/Apply: `pov_provisioning`
   - Destroy: `pov_destroy`

## Repeatable Test Intelligence demo guidance

The Toddfour live pipeline now has a validated Test Intelligence flow in the `sandbox/parson` project using Harness Code pull requests.

Validated success signals from the working run:

- Total tests known by Harness: `88`
- Selected tests: `41`
- Time saved: `5s`
- Correlated with code changes: `26`
- Updated tests: `15`
- New tests: `0`

Use the following approach to keep future demos consistent and easy to explain.

### Recommended demo flow

1. Use Harness Code as the end-to-end system of record for the demo.
2. Create the demo branch in the Harness Code repo, not only in the GitHub source repo.
3. Open a Harness Code PR that targets `main`.
4. Make a narrow production-code-only change in a class with existing focused tests.
5. Avoid editing test files if the goal is to show code-to-test correlation as clearly as possible.
6. Let the PR pipeline finish and use the **Tests** tab as the primary demo artifact.
7. Merge the PR so Test Intelligence can update the `main` baseline before the next demo PR.

### Best type of change for a TI demo

Choose a small implementation-only change with an obvious test surface area:

- small constant extraction
- tag normalization change
- narrow conditional branch change
- local method refactor with unchanged public behavior

Avoid broad changes that touch shared frameworks, dependency versions, or common utility code used by most of the application. Those changes can legitimately select a much larger portion of the test suite and weaken the demo.

### What to show during the demo

In the **Tests** tab, focus on these fields:

- **Selected Tests**
- **Time Saved**
- **Correlated with Code Changes**
- **Updated Tests**
- **New Tests**

The cleanest success pattern is:

- selected tests is less than total known tests
- correlated-with-code-changes is non-zero
- new tests is zero or very low

### Important baseline behavior

After a significant TI configuration change, a new step identifier, or a report ingestion fix, the next run may behave like a baseline or relearning run. In that case Harness may run the full suite and classify tests as `New Tests`.

That does not necessarily mean TI is broken. The next fresh PR after that successful baseline run is usually the run that demonstrates real test selection.

### Keep this stable between demo runs

Do not change these items between demo PRs unless you are intentionally re-validating TI configuration:

- Test step identifier
- repository used by the PR trigger
- target branch for the PR flow
- report paths and report format
- clone strategy for the codebase

For the Toddfour live pipeline, selective test execution depends on the same basic shape remaining intact across runs.

### Mirror-pipeline guidance

If GitHub changes are being mirrored into Harness Code, do not rely on the mirror for the live TI demo itself.

The safest demo pattern is:

1. branch in Harness Code
2. open PR in Harness Code
3. run PR pipeline in Harness Code
4. merge in Harness Code

This keeps the PR event stream, branch lineage, and `main` baseline in one system. If the GitHub mirror is active, avoid landing unrelated mirrored `main` updates in the middle of a TI demo sequence.

### Common ways to get a noisy TI demo

- editing both production code and many tests in the same PR
- using a broad refactor that touches shared code paths everywhere
- changing TI step configuration immediately before the demo
- relying on a first post-config-change run as the proof point
- re-running tests in a later coverage or packaging step, which can hide the effect of TI

### Recommended talk track

For a reliable live demo, use a two-PR story:

1. baseline-establishing PR if TI config was just changed
2. a second narrow PR that shows selected tests and time saved

If TI is already warm and stable, a single narrow production-code-only PR is usually enough.

### Step 2: Add Variables to Template (EKS Stack)

The template needs these tfvars (add via Template Studio → Variables tab):

**Required Runtime Variables:**
| Variable | Description | Locked |
|----------|-------------|--------|
| `owner` | Owner name for resource naming | No |
| `eks_cluster_name` | Existing EKS cluster name | No |
| `harness_account_id` | Target Harness account ID | No |
| `harness_api_key` | Harness API key | No |
| `harness_api_key_email` | Email for HAR authentication | No |
| `harness_org_id` | Target org ID | No |
| `harness_project_id` | Target project ID | No |

**Optional Variables:**
| Variable | Default | Description | Locked |
|----------|---------|-------------|--------|
| `harness_endpoint` | `https://app.harness.io/gateway` | Harness platform URL | Yes |
| `create_harness_org` | `false` | Create new org | No |
| `create_harness_project` | `false` | Create new project | No |
| `artifact_registry_type` | `har` | `har` or `ecr` | No |
| `create_strategy_pipeline` | `true` | Create deploy pipeline | No |
| `create_ci_pipeline` | `true` | Create CI pipeline | No |
| `use_harness_code` | `false` | Use Harness Code repo | Yes |
| `github_repo_name` | `parson-harness/harness-demo-app` | Source repo | No |

### Step 3: Import the IDP Pipeline

Import the pipeline from `.harness/pipelines/idp_pov_provisioner.yaml`:

1. Navigate to **Pipelines** → **Create Pipeline**
2. Select **Import from Git**
3. Select connector `parsongh`, repo `harness-demo-app`
4. Path: `.harness/pipelines/idp_pov_provisioner.yaml`

### Deferred live PR-trigger automation

The Toddfour PR-created trigger and companion input sets under `.harness/triggers/` and `.harness/input_sets/` are intentionally being validated as a live Git Experience workflow first. Do not port that trigger/input-set shape into `tofu/stacks/eks` or the provisioner-managed Terraform path until the shared `harness-demo-app` repo flow, PR status checks, and repeatable Test Intelligence demo behavior have been proven in the live project.

## Sandbox Janitor Entry Points

### Manual Audit or Cleanup

- **Workflow**: `.harness/workflows/sandbox_cleanup_workflow.yaml`
- **Pipeline**: `.harness/pipelines/sandbox_ttl_cleanup.yaml`

Recommended usage:

1. Run with `dry_run=true`
2. Filter by `template_id`, `owner_filter`, `sandbox_profile_filter`, or `deployment_target_filter`
3. Review the expired workspace report
4. Review any orphaned ASG VPC findings
5. Re-run with `dry_run=false` to trigger `idp_pov_destroyer_v2` for the expired matches and orphaned ASG VPC cleanup actions

### Scheduled Cleanup

- **Trigger**: `.harness/triggers/sandbox_ttl_cleanup_cron.yaml`

This weekly trigger runs the same janitor pipeline against all managed linked workspaces. The cleanup still flows through the robust destroyer so Terraform state-aware cleanup remains the primary mechanism.

### Step 4: Create IDP Workflow (Optional)

Import the IDP workflow from `.harness/workflows/pov_provisioner_workflow.yaml`:

1. Navigate to **IDP** → **Workflows**
2. Create new workflow from YAML
3. This provides a user-friendly form for triggering provisioning

### Step 5: Run via IDP or Pipeline

**Via IDP Workflow:**
1. Go to IDP → Workflows → "POV in a Box Provisioner"
2. Fill in the form fields
3. Click "Provision POV"

**Via Pipeline Directly:**
1. Go to Pipelines → `idp_pov_provisioner`
2. Click **Run Pipeline**
3. Fill in runtime inputs:
   - **owner**: Your name (lowercase, e.g., `todd`)
   - **harness_account_id**: Target account ID
   - **harness_org_id**: Target org ID
   - **harness_project_id**: Target project ID
4. Review the plan and approve

## Pipeline Variables Reference (EKS Stack)

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `owner` | Yes | - | Owner name for resource naming |
| `eks_cluster_name` | Yes | `harness-eks-parson` | Existing EKS cluster name |
| `harness_account_id` | Yes | Current account | Target Harness account |
| `harness_endpoint` | Yes | `https://app.harness.io/gratis` | Harness platform URL |
| `target_api_key` | Yes | Provisioner SAT | API key for target account |
| `target_api_key_email` | Yes | Service account email | Email for HAR auth |
| `harness_org_id` | Yes | Current org | Target org ID |
| `harness_project_id` | Yes | Current project | Target project ID |
| `create_harness_org` | No | `false` | Create new org |
| `create_harness_project` | No | `false` | Create new project |
| `artifact_registry_type` | No | `har` | `har` or `ecr` |
| `create_strategy_pipeline` | No | `true` | Create deploy pipeline |
| `create_ci_pipeline` | No | `true` | Create CI pipeline |
| `acm_cert_arn` | No | - | ACM cert for HTTPS ingress |

## Future: IDP Workflow Integration

The pipeline is designed to be triggered by an IDP workflow. The workflow form would:

1. Collect user inputs via a form UI
2. Map form fields to pipeline variables
3. Trigger the pipeline with those inputs
4. Track provisioning status in the IDP catalog

Example IDP workflow trigger:
```yaml
apiVersion: scaffolder.backstage.io/v1beta3
kind: Template
metadata:
  name: pov-provisioning
  title: Provision POV Environment
spec:
  parameters:
    - title: POV Configuration
      properties:
        owner:
          type: string
          title: Owner Name
        # ... more fields
  steps:
    - id: trigger-pipeline
      action: harness:pipeline:trigger
      input:
        pipelineIdentifier: pov_provisioning
        variables:
          owner: ${{ parameters.owner }}
          # ... map other variables
```

## QA Playwright custom runner lifecycle

The QA Playwright gate can run from a custom container image that already contains the Playwright smoke suite. In that baked-runner model, the CD stage should not clone the repository or install Node dependencies at runtime. Instead, rebuild the runner image whenever the contents of the baked test harness change.

### Rebuild the runner image when these files change

| File or path | Why it changes | Why rebuild is required |
|-------------|----------------|-------------------------|
| `package.json` | Playwright version changes, new helper libraries are added, or npm scripts are updated | The image needs the updated dependency manifest baked in |
| `package-lock.json` | The resolved dependency tree changes after an npm install or version bump | The image should keep deterministic dependency versions |
| `playwright.config.js` | Timeouts, retries, workers, reporters, browser projects, or base URL behavior change | The image should run the updated Playwright execution policy |
| `playwright-tests/**` | UI selectors, API assertions, smoke coverage, or environment-aware test logic changes | The image should contain the current smoke suite |

### Usually does not require a runner rebuild

These changes are typically pipeline concerns, not image-content concerns:

- Harness annotation formatting
- approval message text
- connector references
- runtime base URL wiring in the pipeline
- PR comment behavior in the pipeline shell step

### Operational guidance

- Rebuild the runner image after any change to the baked Playwright harness files listed above
- Rebuild periodically to pick up base-image security updates even if the tests did not change
- Prefer versioned image tags over relying only on `latest` so the validated runner can be tied to a specific change set

## Troubleshooting

### Common Issues

1. **Workspace not found**: Ensure the workspace identifier matches exactly
2. **Variable not resolved**: Check JEXL expression syntax in workspace variables
3. **AWS auth failed**: Verify OIDC connector has correct trust policy
4. **Plan fails**: Check that all required variables have values

### Logs

- Pipeline execution logs: Available in Harness UI
- Terraform logs: Check the IACM step outputs
- State file: Managed by IACM workspace
