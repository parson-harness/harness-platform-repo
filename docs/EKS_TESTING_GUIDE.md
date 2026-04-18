# EKS Testing & Verification Guide

This guide walks through testing the full EKS deployment workflow before expanding to ECS, Lambda, and ASG.

## Prerequisites

- AWS CLI configured with appropriate credentials
- kubectl installed
- Docker installed (for local builds)
- OpenTofu/Terraform installed

## Step 1: Deploy Infrastructure

```bash
cd tofu/stacks/eks

# Configure variables
cp terraform.tfvars.example terraform.tfvars
# Edit with your values:
# - owner
# - eks_cluster_name
# - harness_account_id
# - harness_api_key
# - harness_api_key_email

# Deploy
tofu init
tofu apply
```

**Expected outputs:**
- EKS cluster name and endpoint
- Artifact registry type and URL
- Delegate name
- Kubernetes namespace
- Harness org/project and connector IDs

## Step 2: Configure kubectl

```bash
# Use the deployed stack outputs
aws eks update-kubeconfig \
  --region us-east-1 \
  --name "$(tofu output -raw cluster_name)"
```

Verify:
```bash
kubectl cluster-info
kubectl get nodes
```

## Step 3: Verify Delegate

```bash
# Check delegate pods
kubectl get pods -n "$(tofu output -raw delegate_namespace)"

# Check delegate logs
kubectl logs -f -l app=harness-delegate -n "$(tofu output -raw delegate_namespace)"
```

**In Harness UI:**
1. Go to Project Settings → Delegates
2. Verify delegate shows as "Connected"
3. Test connector connectivity

## Step 4: Build and Push Image

```bash
# Build and push using the stack-based helper defaults
./scripts/build-and-push.sh 1.0.0

# Push a second version for deployment testing
./scripts/build-and-push.sh 2.0.0
```

The script reads `tofu/stacks/eks/terraform.tfvars` by default and uses `tofu output` for registry details when available.

## Step 5: Verify Harness Resources

In Harness UI:
1. Go to the org/project returned by `tofu output`
2. Verify the generated service, environment, and infrastructure exist
3. Verify the delegate shows as Connected
4. Test the generated connectors if needed

## Step 6: Run the Generated Pipeline

Run the deployment pipeline created by the stack and provide the image tag you pushed in the previous step.

## Step 7: Run Verification Script

```bash
OWNER=<your-owner> ./scripts/test-eks-deployment.sh
```

This checks:
- Cluster connectivity
- Delegate status
- Deployment status
- Service reachability
- Application endpoints
- HAR or ECR registry configuration

## Step 8: Test CV Rollback (Optional)

1. Deploy version 1.0.0 as stable
2. Start canary deployment of 2.0.0
3. During CV verification, trigger chaos:
   ```bash
   kubectl port-forward svc/<service-name> 8081:8080 -n "$(tofu output -raw k8s_namespace)"
   curl -X POST "http://localhost:8081/api/chaos/enable?errorRate=0.5&latencyMs=1000"
   ```
4. Watch CV detect degradation and trigger rollback

## Verification Checklist

| Component | Test | Expected Result |
|-----------|------|-----------------|
| **Infrastructure** | | |
| EKS | `tofu output -raw cluster_name` | Cluster name returned |
| EKS | `kubectl get nodes` | Nodes in Ready state |
| Registry | `tofu output -raw artifact_registry_url` | Registry URL returned |
| **Harness** | | |
| Delegate | Check Harness UI | Connected status |
| K8s Connector | Test connection | Success |
| AWS Connector | Test connection | Success |
| **Application** | | |
| Namespace | `tofu output -raw k8s_namespace` | Namespace returned |
| Deployment | `kubectl get deploy -n "$(tofu output -raw k8s_namespace)"` | Running |
| Service | `kubectl get svc -n "$(tofu output -raw k8s_namespace)"` | Service present |
| Health | `curl <lb>/actuator/health` | `{"status":"UP"}` |
| Metrics | `curl <lb>/actuator/prometheus` | Prometheus metrics |
| **Pipeline** | | |
| CI (if used) | Run pipeline | Image pushed to configured registry |
| CD Canary | Run pipeline | Canary + rolling deploy |
| CV | Enable chaos | Detects degradation |

## Troubleshooting

### Delegate not connecting
```bash
# Check pod status
kubectl describe pod -l app=harness-delegate -n "$(tofu output -raw delegate_namespace)"

# Check logs for errors
kubectl logs -l app=harness-delegate -n "$(tofu output -raw delegate_namespace)" --tail=100
```

### EKS access denied
```bash
# Verify IAM identity
aws sts get-caller-identity

# Update kubeconfig
aws eks update-kubeconfig --region us-east-1 --name <cluster-name>
```

### LoadBalancer pending
```bash
# Check service events
kubectl describe svc <service-name> -n "$(tofu output -raw k8s_namespace)"

# May need to wait 2-3 minutes for AWS ALB provisioning
```

### Image pull errors
```bash
# Verify configured registry
tofu output -raw artifact_registry_type
tofu output -raw artifact_registry_url

# If using ECR, check image exists
aws ecr list-images --repository-name <owner-specific-ecr-repo>
```

## Next Steps After EKS Verification

Once EKS is working:

1. **ECS** - Add ECS task definition and service modules
2. **Lambda** - Add Lambda function module with API Gateway
3. **ASG** - Add Auto Scaling Group with launch template

Each will follow the same pattern:
1. Add tofu module
2. Add Harness pipeline template
3. Test deployment
4. Document
