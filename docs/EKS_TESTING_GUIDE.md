# EKS Testing & Verification Guide

This guide walks through testing the full EKS deployment workflow before expanding to ECS, Lambda, and ASG.

## Prerequisites

- AWS CLI configured with appropriate credentials
- kubectl installed
- Docker installed (for local builds)
- OpenTofu/Terraform installed

## Step 1: Deploy Infrastructure

```bash
cd tofu/environments/sandbox

# Configure variables
cp terraform.tfvars.example terraform.tfvars
# Edit with your Harness account details

# Deploy
tofu init
tofu apply
```

**Expected outputs:**
- VPC ID
- EKS cluster name and endpoint
- ECR repository URL
- Delegate name
- Connector IDs

## Step 2: Configure kubectl

```bash
# Get the command from tofu output
aws eks update-kubeconfig --region us-east-1 --name harness-demo-sandbox-eks
```

Verify:
```bash
kubectl cluster-info
kubectl get nodes
```

## Step 3: Verify Delegate

```bash
# Check delegate pods
kubectl get pods -n harness-delegate-ng

# Check delegate logs
kubectl logs -f -l app=harness-delegate -n harness-delegate-ng
```

**In Harness UI:**
1. Go to Project Settings → Delegates
2. Verify delegate shows as "Connected"
3. Test connector connectivity

## Step 4: Build and Push Image

```bash
# Build locally
./scripts/build-local.sh -v 1.0.0

# Push to ECR (get registry URL from tofu output)
./scripts/build-local.sh -v 1.0.0 -r <ecr-registry-url> -p

# Push a second version for deployment testing
./scripts/build-local.sh -v 2.0.0 -r <ecr-registry-url> -p
```

## Step 5: Create Harness Service

In Harness UI:
1. Go to **Services** → **New Service**
2. Name: `harness-demo-app`
3. Deployment Type: Kubernetes
4. Add artifact source:
   - Type: ECR
   - Connector: Use the one created by tofu
   - Region: us-east-1
   - Repository: harness-demo-app

## Step 6: Create Harness Environment

1. Go to **Environments** → **New Environment**
2. Name: `sandbox-eks`
3. Type: Pre-Production
4. Add Infrastructure Definition:
   - Type: Kubernetes
   - Connector: Use K8s connector from tofu
   - Namespace: `harness-demo`
   - Release Name: `harness-demo-app`

## Step 7: Deploy via Pipeline

### Option A: Import Pipeline Template

```bash
# Import the canary pipeline
harness pipeline create --file harness/pipelines/cd-eks-canary.yaml \
  --project <project-id> --org <org-id>
```

### Option B: Create Manually

1. Create new pipeline
2. Add Deployment stage
3. Select service and environment
4. Use Canary deployment strategy
5. Add Verify step after canary deploy

## Step 8: Run Verification Script

```bash
./scripts/test-eks-deployment.sh
```

This checks:
- Cluster connectivity
- Delegate status
- Deployment status
- Service/LoadBalancer
- Application endpoints
- ECR images

## Step 9: Test CV Rollback (Optional)

1. Deploy version 1.0.0 as stable
2. Start canary deployment of 2.0.0
3. During CV verification, trigger chaos:
   ```bash
   kubectl port-forward svc/harness-demo-app-canary 8081:8080 -n harness-demo
   curl -X POST "http://localhost:8081/api/chaos/enable?errorRate=0.5&latencyMs=1000"
   ```
4. Watch CV detect degradation and trigger rollback

## Verification Checklist

| Component | Test | Expected Result |
|-----------|------|-----------------|
| **Infrastructure** | | |
| VPC | `tofu output vpc_id` | VPC ID returned |
| EKS | `kubectl get nodes` | Nodes in Ready state |
| ECR | `aws ecr describe-repositories` | Repository exists |
| **Harness** | | |
| Delegate | Check Harness UI | Connected status |
| K8s Connector | Test connection | Success |
| AWS Connector | Test connection | Success |
| **Application** | | |
| Deployment | `kubectl get deploy -n harness-demo` | Running |
| Service | `kubectl get svc -n harness-demo` | LoadBalancer IP |
| Health | `curl <lb>/actuator/health` | `{"status":"UP"}` |
| Metrics | `curl <lb>/actuator/prometheus` | Prometheus metrics |
| **Pipeline** | | |
| CI (if used) | Run pipeline | Image pushed to ECR |
| CD Canary | Run pipeline | Canary + rolling deploy |
| CV | Enable chaos | Detects degradation |

## Troubleshooting

### Delegate not connecting
```bash
# Check pod status
kubectl describe pod -l app=harness-delegate -n harness-delegate-ng

# Check logs for errors
kubectl logs -l app=harness-delegate -n harness-delegate-ng --tail=100
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
kubectl describe svc harness-demo-app -n harness-demo

# May need to wait 2-3 minutes for AWS ALB provisioning
```

### Image pull errors
```bash
# Verify ECR login
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <registry>

# Check image exists
aws ecr list-images --repository-name harness-demo-app
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
