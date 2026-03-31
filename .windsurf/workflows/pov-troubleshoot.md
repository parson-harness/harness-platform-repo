---
description: Troubleshoot common POV provisioner and destroyer failures
---

# POV Troubleshooting Workflow

## Quick Diagnosis

1. **Check which pipeline failed**: Provisioner or Destroyer?
2. **Check which stage failed**: Use `harness_diagnose` with the execution URL
3. **Match error to known issue below**

## Common Provisioner Failures

### IRSA Role Already Exists
**Error**: `EntityAlreadyExists: Role with name harness-demo-{owner}-delegate-irsa-role already exists`

**Cause**: Destroyer didn't clean up the IRSA role (chicken-and-egg problem)

**Fix**:
```bash
# Delete inline policies first
aws iam list-role-policies --role-name harness-demo-{owner}-delegate-irsa-role
aws iam delete-role-policy --role-name harness-demo-{owner}-delegate-irsa-role --policy-name delegate-base-permissions
aws iam delete-role-policy --role-name harness-demo-{owner}-delegate-irsa-role --policy-name delegate-self-assume

# Then delete the role
aws iam delete-role --role-name harness-demo-{owner}-delegate-irsa-role
```

### Route53 Record Already Exists
**Error**: `InvalidChangeBatch: Tried to create resource record set but it already exists`

**Cause**: DNS record exists outside Terraform state

**Fix**:
```bash
# Find the record
aws route53 list-resource-record-sets --hosted-zone-id Z031547912F6D8STOXRA2 \
  --query "ResourceRecordSets[?Name=='{owner}.harness-demo.dev.']"

# Delete it (note the TTL must match exactly)
aws route53 change-resource-record-sets --hosted-zone-id Z031547912F6D8STOXRA2 \
  --change-batch '{"Changes":[{"Action":"DELETE","ResourceRecordSet":{"Name":"{owner}.harness-demo.dev","Type":"CNAME","TTL":60,"ResourceRecords":[{"Value":"k8s-harnessdemo-xxx.us-east-1.elb.amazonaws.com"}]}}]}'
```

### HAR Registry Already Exists
**Error**: `registry with identifier har-{owner} already exists`

**Cause**: Registry exists outside Terraform state

**Fix**: Delete via Harness UI or API, then re-run provisioner

### JSON Parsing Error in Workspace Creation
**Error**: `invalid character 'a' after object key:value pair`

**Cause**: Secret value being interpolated directly instead of referenced

**Fix**: Ensure `harness_api_key` uses `value_type: secret` with the secret name, not the value

## Common Destroyer Failures

### Terraform Destroy Skipped
**Symptom**: "Terraform Destroy" stage shows "Skipped"

**Cause**: State health check failed (`state_healthy == false`)

**What to do**: The AWS Cleanup and Cleanup Orphans stages should still run. Check if resources were cleaned up. If not, run destroyer again or clean up manually.

### AWS Cleanup Failed
**Symptom**: IACM stage "AWS Cleanup" fails

**Cause**: Usually OIDC credential issues or workspace doesn't exist

**Fix**: Clean up AWS resources manually (see IRSA and Route53 commands above)

### Workspace Not Found
**Error**: 404 on workspace check

**Cause**: Workspace was already deleted or never created

**What to do**: This is usually fine - the destroyer will skip to cleanup orphans

## CI Pipeline Failures

### Base Image Not Found
**Error**: `pkg.harness.io/.../eclipse-temurin:17-jre: not found`

**Cause**: HAR upstream proxy not linked to virtual registry

**Fix**: 
1. Check if upstream proxy exists: Look for `{owner}-dockerhub-proxy` in HAR
2. If missing, re-run provisioner (fix was applied to remove timestamp() trigger)
3. If exists but not linked, update virtual registry to include it in upstream_proxies

### OPA Policy Failure on Non-Provisioner Pipeline
**Error**: Policy evaluation failed on GitHub Mirror or other pipeline

**Cause**: OPA policies applying to all pipelines instead of just `managed-by:provisioner`

**Fix**: Re-run provisioner to update OPA policies with corrected scoping logic

## Delegate Issues

### CrashLoopBackOff with Null Token
**Error**: Delegate pod in CrashLoopBackOff, logs show null token

**Cause**: Double base64 encoding of delegate token

**Fix**:
```bash
# Get the raw token
kubectl get secret harness-delegate-token-{owner} -n harness-delegate-ng-{owner} \
  -o jsonpath='{.data.DELEGATE_TOKEN}' | base64 -d | base64 -d

# Helm upgrade with decoded token
helm upgrade delegate-{owner} harness-delegate-ng \
  --repo https://app.harness.io/storage/harness-download/delegate-helm-chart/ \
  -n harness-delegate-ng-{owner} \
  --set delegateToken={raw-token} --reuse-values
```

### IRSA Annotation Missing
**Symptom**: Delegate can't access AWS (permission denied)

**Cause**: Helm upgrade wiped the IRSA annotation

**Fix**:
```bash
kubectl annotate serviceaccount delegate-{owner} \
  -n harness-delegate-ng-{owner} \
  eks.amazonaws.com/role-arn=arn:aws:iam::759984737373:role/harness-demo-{owner}-delegate-irsa-role \
  --overwrite

kubectl rollout restart deployment delegate-{owner} -n harness-delegate-ng-{owner}
```

## Nuclear Option: Full Manual Cleanup

If all else fails, clean up everything manually:

```bash
OWNER="{owner}"

# 1. Delete K8s resources
kubectl delete namespace harness-demo-${OWNER} --wait=false
kubectl delete namespace harness-delegate-ng-${OWNER} --wait=false
kubectl delete clusterrolebinding harness-delegate-admin-${OWNER}

# 2. Delete AWS resources
aws iam list-role-policies --role-name harness-demo-${OWNER}-delegate-irsa-role | \
  jq -r '.PolicyNames[]' | \
  xargs -I {} aws iam delete-role-policy --role-name harness-demo-${OWNER}-delegate-irsa-role --policy-name {}
aws iam delete-role --role-name harness-demo-${OWNER}-delegate-irsa-role

# 3. Delete Route53 records (get TTL and value first)
# ... see Route53 section above

# 4. Delete Harness resources via API
# Pipelines, service, environments, infrastructures, connectors, delegate, HAR registry
# Use the Cleanup Orphans stage script as reference

# 5. Delete IACM workspace
curl -X DELETE "https://app.harness.io/gratis/iacm/api/orgs/sandbox/projects/parson/workspaces/${OWNER}_pov" \
  -H "Harness-Account: {account_id}" \
  -H "x-api-key: {api_key}"
```

Then re-run the provisioner.
