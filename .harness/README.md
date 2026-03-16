# Harness POV Provisioning with IACM

This directory contains Harness pipeline definitions for provisioning POV-in-a-box environments using Infrastructure as Code Management (IACM).

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  IDP Workflow Form (Future)                                     │
│  └── Collects: owner, account_id, org, project, etc.            │
└─────────────────────────────────────────────────────────────────┘
                               ↓
┌─────────────────────────────────────────────────────────────────┐
│  Pipeline: pov_provisioning                                     │
│  └── Variables passed as runtime inputs                         │
└─────────────────────────────────────────────────────────────────┘
                               ↓
┌─────────────────────────────────────────────────────────────────┐
│  IACM Workspace: pov-sandbox                                    │
│  └── Terraform variables reference pipeline variables           │
└─────────────────────────────────────────────────────────────────┘
                               ↓
┌─────────────────────────────────────────────────────────────────┐
│  OpenTofu: tofu/environments/sandbox                            │
│  └── Creates: Delegate, Connectors, Services, Pipelines, etc.   │
└─────────────────────────────────────────────────────────────────┘
```

## Setup Instructions

### Step 1: Create IACM Workspace

1. Navigate to **Infrastructure as Code Management** module
2. Select **Workspaces** → **New Workspace**
3. Configure:

   **About Workspace:**
   - Name: `pov-sandbox`
   - Description: `POV-in-a-box provisioning workspace`
   - Enable Cost Estimation: `Yes` (optional)

   **Repository:**
   - Git Provider: `Third-party Git provider`
   - Git Connector: Your GitHub connector
   - Branch: `main`
   - Folder Path: `tofu/environments/sandbox`

   **Provisioner:**
   - Connector: AWS connector with OIDC/IRSA
   - Workspace Type: `OpenTofu`
   - Version: `1.9.0` or latest

### Step 2: Configure Workspace Variables

In the workspace **Variables** tab, add these Terraform variables that reference pipeline variables:

| Variable Name | Type | Value |
|--------------|------|-------|
| `owner` | String | `<+pipeline.variables.owner>` |
| `harness_account_id` | String | `<+pipeline.variables.harness_account_id>` |
| `harness_endpoint` | String | `<+pipeline.variables.harness_endpoint>` |
| `harness_api_key` | Secret | `<+pipeline.variables.harness_api_key>` |
| `harness_api_key_email` | String | `<+pipeline.variables.harness_api_key_email>` |
| `deployment_targets` | HCL | `[<+pipeline.variables.deployment_targets>]` |
| `create_harness_org` | String | `<+pipeline.variables.create_harness_org>` |
| `harness_org_id` | String | `<+pipeline.variables.harness_org_id>` |
| `create_harness_project` | String | `<+pipeline.variables.create_harness_project>` |
| `harness_project_id` | String | `<+pipeline.variables.harness_project_id>` |
| `create_eks_cluster` | String | `<+pipeline.variables.create_eks_cluster>` |
| `existing_cluster_name` | String | `<+pipeline.variables.existing_cluster_name>` |
| `github_token_ref` | String | `<+pipeline.variables.github_token_ref>` |

**Environment Variables:**
| Variable Name | Type | Value |
|--------------|------|-------|
| `AWS_REGION` | String | `us-east-1` |

### Step 3: Import the Pipeline

Import the pipeline from `.harness/pipelines/pov_provisioning.yaml`:

1. Navigate to **Pipelines** → **Create Pipeline**
2. Select **Import from Git**
3. Select your connector and repo
4. Path: `.harness/pipelines/pov_provisioning.yaml`

Or create manually using the YAML as reference.

### Step 4: Run the Pipeline

1. Click **Run Pipeline**
2. Fill in the runtime inputs:
   - **owner**: Your name (lowercase, e.g., `todd`)
   - **harness_account_id**: Target account ID
   - **harness_org_id**: Target org ID
   - **harness_project_id**: Target project ID
   - **workspace**: Select `pov-sandbox`
   - etc.
3. Review the plan in the first stage
4. Approve to apply

## Pipeline Variables Reference

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `owner` | Yes | - | Owner name for resource naming |
| `harness_account_id` | Yes | - | Target Harness account |
| `harness_endpoint` | Yes | `https://app.harness.io` | Harness platform URL |
| `harness_api_key` | Yes | - | API key secret reference |
| `harness_api_key_email` | Yes | - | Email for API key |
| `deployment_targets` | Yes | `eks` | Comma-separated targets |
| `create_harness_org` | No | `false` | Create new org |
| `harness_org_id` | Yes | - | Existing org ID |
| `create_harness_project` | No | `false` | Create new project |
| `harness_project_id` | Yes | - | Existing project ID |
| `create_eks_cluster` | No | `false` | Create new EKS cluster |
| `existing_cluster_name` | No | - | Existing cluster name |
| `github_token_ref` | No | `""` | GitHub PAT secret ref |

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
