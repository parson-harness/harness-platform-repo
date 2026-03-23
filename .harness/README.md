# Harness POV Provisioning with IACM

This directory contains Harness pipeline definitions for provisioning POV-in-a-box environments using Infrastructure as Code Management (IACM).

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
| `SE_Sandbox_Provisioner` | 1.0 | SE personal sandboxes |

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
