---
description: Recover a broken or misconfigured Harness delegate
---

# Delegate Recovery Workflow

## Symptoms

- Delegate pod in `CrashLoopBackOff`
- Delegate shows "Not Connected" in Harness UI
- AWS operations fail with "Access Denied" or "Unable to assume role"
- Delegate token errors in logs

## Step 1: Check Pod Status

```bash
OWNER="{owner}"
kubectl get pods -n harness-delegate-ng-${OWNER}
kubectl logs -n harness-delegate-ng-${OWNER} -l app.kubernetes.io/name=delegate-${OWNER} --tail=100
```

## Step 2: Identify the Issue

### Issue A: Null Token / CrashLoopBackOff

**Symptom**: Logs show null token or authentication failure

**Cause**: Double base64 encoding of delegate token

**Fix**:
```bash
# Decode the token (it's double-encoded)
RAW_TOKEN=$(kubectl get secret harness-delegate-token-${OWNER} \
  -n harness-delegate-ng-${OWNER} \
  -o jsonpath='{.data.DELEGATE_TOKEN}' | base64 -d | base64 -d)

echo "Raw token: $RAW_TOKEN"

# Helm upgrade with the decoded token
helm upgrade delegate-${OWNER} harness-delegate-ng \
  --repo https://app.harness.io/storage/harness-download/delegate-helm-chart/ \
  -n harness-delegate-ng-${OWNER} \
  --set delegateToken=${RAW_TOKEN} \
  --reuse-values
```

### Issue B: IRSA Annotation Missing

**Symptom**: AWS operations fail with permission errors

**Check**:
```bash
kubectl get serviceaccount delegate-${OWNER} \
  -n harness-delegate-ng-${OWNER} \
  -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}'
```

If empty or wrong, **fix**:
```bash
ROLE_ARN="arn:aws:iam::759984737373:role/harness-demo-${OWNER}-delegate-irsa-role"

kubectl annotate serviceaccount delegate-${OWNER} \
  -n harness-delegate-ng-${OWNER} \
  eks.amazonaws.com/role-arn=${ROLE_ARN} \
  --overwrite

# Restart to pick up new credentials
kubectl rollout restart deployment delegate-${OWNER} -n harness-delegate-ng-${OWNER}
```

### Issue C: IRSA Role Doesn't Exist

**Symptom**: Annotation is correct but AWS still fails

**Check**:
```bash
aws iam get-role --role-name harness-demo-${OWNER}-delegate-irsa-role
```

If role doesn't exist, re-run the provisioner to create it.

### Issue D: Delegate Not Registered

**Symptom**: Pod is running but delegate not visible in Harness

**Check**:
1. Verify delegate token is correct
2. Check network connectivity to Harness
3. Look for registration errors in logs

```bash
kubectl logs -n harness-delegate-ng-${OWNER} -l app.kubernetes.io/name=delegate-${OWNER} | grep -i "register\|connect\|error"
```

## Step 3: Verify Recovery

```bash
# Check pod is running
kubectl get pods -n harness-delegate-ng-${OWNER}

# Check delegate is connected in Harness
# Use Harness UI: Project Settings → Delegates

# Test AWS access (if IRSA)
kubectl exec -it -n harness-delegate-ng-${OWNER} \
  $(kubectl get pod -n harness-delegate-ng-${OWNER} -l app.kubernetes.io/name=delegate-${OWNER} -o jsonpath='{.items[0].metadata.name}') \
  -- aws sts get-caller-identity
```

## Full Delegate Reinstall

If nothing else works:

```bash
# Delete the delegate
helm uninstall delegate-${OWNER} -n harness-delegate-ng-${OWNER}
kubectl delete namespace harness-delegate-ng-${OWNER}

# Re-run provisioner to recreate
```

Or manually reinstall:

```bash
# Get values from Harness UI: Project Settings → Delegates → New Delegate → Helm
helm upgrade -i delegate-${OWNER} harness-delegate-ng \
  --repo https://app.harness.io/storage/harness-download/delegate-helm-chart/ \
  --namespace harness-delegate-ng-${OWNER} \
  --create-namespace \
  --set delegateName=delegate-${OWNER} \
  --set accountId={account_id} \
  --set delegateToken={token} \
  --set managerEndpoint=https://app.harness.io/gratis \
  --set delegateDockerImage=harness/delegate:latest \
  --set replicas=1 \
  --set upgrader.enabled=true
```

Then add IRSA annotation (see Issue B above).
