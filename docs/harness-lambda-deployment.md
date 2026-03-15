# Harness Lambda Deployment Overview

## What Harness Needs

Harness Lambda deployments require two manifest files stored in your Git repository:

### 1. Function Definition (`function-definition.json`)

The Lambda configuration that tells Harness *what* to deploy:
- Function name
- IAM role ARN
- Memory size
- Timeout
- Package type (Image or Zip)

Example:
```json
{
  "functionName": "my-function",
  "role": "arn:aws:iam::123456789012:role/my-lambda-role",
  "packageType": "Image",
  "memorySize": 1024,
  "timeout": 30
}
```

### 2. Alias Definition (`alias-definition.json`)

The traffic routing configuration that enables canary/blue-green deployments:
- Alias name (e.g., `live`)
- Acts as a stable pointer to Lambda versions
- Harness updates the alias to shift traffic between versions

Example:
```json
{
  "name": "live",
  "description": "Production traffic alias for canary deployments"
}
```

## For Existing Lambda Functions

| Existing Setup | Harness Requirement | Action Needed |
|----------------|---------------------|---------------|
| No aliases | Alias required for canary | Create `live` alias pointing to current version |
| Deploys to `$LATEST` | Versioned deployments | Harness auto-creates versions |
| IAM role exists | Role ARN in manifest | Reference existing role in function-definition.json |
| Existing env vars | Preserve in manifest | Add to function-definition.json |

### Steps to Onboard Existing Lambda

1. **Get current config:**
   ```bash
   aws lambda get-function --function-name existing-function
   ```

2. **Create function-definition.json** from their settings

3. **Create alias** (one-time):
   ```bash
   aws lambda publish-version --function-name existing-function
   aws lambda create-alias --function-name existing-function --name live --function-version 1
   ```

## How Deployment Works

1. Harness reads manifests from Git
2. Creates/updates Lambda function with new container image or code
3. Publishes a new immutable **version**
4. Updates the **alias** to point to the new version
5. For canary: gradually shifts traffic (e.g., 10% → 50% → 100%)
6. Rollback = point alias back to previous version

## Traffic Flow

```
API Gateway / Function URL
        ↓
   Alias: "live"
        ↓
   Version: N (or weighted between versions for canary)
```

## Key Points

- No changes to Lambda **code** required
- Manifests are lightweight JSON config
- Main shift: "deploy to $LATEST" → "publish version + update alias"
- Enables canary deployments and instant rollback
