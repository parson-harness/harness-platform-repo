# Harness Demo Stacks

This directory contains **decoupled, per-tech-stack Terraform configurations** for deploying Harness demo environments.

## Architecture

```
tofu/
├── modules/              # Reusable Terraform modules
├── shared-infra/         # Long-lived shared infrastructure (EKS, delegate)
├── stacks/               # Per-tech-stack deployments (THIS DIRECTORY)
│   ├── eks/              # Kubernetes deployments to existing EKS
│   ├── asg/              # EC2 Auto Scaling Group deployments
│   └── lambda/           # AWS Lambda deployments (future)
└── environments/         # Legacy monolithic environment (sandbox/)
```

## Use Cases

### Use Case #1: SE Sandbox (Same Harness Account)
Deploy to shared EKS cluster in the same Harness account.

```bash
cd tofu/stacks/eks
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
tofu init
tofu apply
```

### Use Case #2: POV-in-a-Box (Shared AWS, Customer Harness Account)
Deploy to shared EKS cluster, but provision Harness entities in customer's account.

```bash
cd tofu/stacks/eks
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars:
#   - harness_account_id = "<customer-account-id>"
#   - harness_api_key = "<customer-api-key>"
#   - create_harness_org = true (or use existing)
#   - create_harness_project = true
tofu init
tofu apply
```

### Use Case #3: POV-in-a-Box (Customer AWS + Customer Harness)
Deploy to customer's AWS infrastructure and Harness account.

For this use case, use the **ASG stack** which creates its own AWS infrastructure:

```bash
cd tofu/stacks/asg
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with customer's AWS and Harness credentials
tofu init
tofu apply
```

## Stacks

### EKS Stack (`stacks/eks/`)

Deploys Harness entities for **Kubernetes deployments** to an **existing EKS cluster**.

**Creates:**
- Harness Org/Project (optional)
- Kubernetes namespace
- Harness connectors (K8s, AWS, GitHub)
- Harness Artifact Registry (HAR)
- HAR pull secret in K8s
- Harness Service (Kubernetes deployment type)
- Harness Environment + Infrastructure
- CI/CD Pipelines (Strategy Choice, CI Build)

**Prerequisites:**
- Existing EKS cluster
- Existing delegate with IRSA role

**Key Variables:**
| Variable | Description | Default |
|----------|-------------|---------|
| `owner` | Owner name for resource naming | (required) |
| `eks_cluster_name` | Existing EKS cluster name | (required) |
| `harness_account_id` | Harness account ID | (required) |
| `harness_api_key` | Harness API key | (required) |
| `artifact_registry_type` | `har` or `ecr` | `har` |
| `create_strategy_pipeline` | Create deploy pipeline | `true` |
| `create_ci_pipeline` | Create CI pipeline | `true` |

### ASG Stack (`stacks/asg/`)

Deploys **complete AWS infrastructure** and Harness entities for **EC2 ASG deployments**.

**Creates:**
- AWS VPC, subnets, security groups
- Application Load Balancer (ALB) with prod/stage listeners
- Auto Scaling Group with Launch Template
- Route53 DNS record (optional)
- IAM user for Packer CI builds
- Harness Org/Project (optional)
- Harness connectors (AWS, GitHub)
- Harness Service (ASG deployment type)
- Harness Environment + Infrastructure
- CI/CD Pipelines (ASG Strategy, ASG CI Build)

**Key Variables:**
| Variable | Description | Default |
|----------|-------------|---------|
| `owner` | Owner name for resource naming | (required) |
| `harness_account_id` | Harness account ID | (required) |
| `harness_api_key` | Harness API key | (required) |
| `vpc_cidr` | VPC CIDR block | `10.1.0.0/16` |
| `instance_type` | EC2 instance type | `t3.small` |
| `asg_min_size` | Min ASG instances | `1` |
| `create_dns_record` | Create Route53 record | `true` |

### Lambda Stack (`stacks/lambda/`) - Future

Will deploy AWS Lambda functions with Harness CD.

## Migration from Legacy Sandbox

The legacy `environments/sandbox/` directory uses a monolithic approach with `deployment_targets` to toggle features. The new stacks approach:

| Aspect | Legacy (sandbox/) | New (stacks/) |
|--------|-------------------|---------------|
| Structure | Single main.tf with conditionals | Separate directory per stack |
| Complexity | High (1000+ lines) | Low (~400 lines each) |
| State | Single state file | Separate state per stack |
| Flexibility | All-or-nothing | Mix and match stacks |
| POV Support | Complex variable passing | Simple, focused configs |

## IACM Integration

Each stack can be used with Harness IACM:

1. Create a workspace template per stack type
2. Point to `tofu/stacks/<stack>/` as the Terraform path
3. Define tfvars in the workspace template
4. Use IDP workflows to trigger provisioning

Example workspace template configuration:
```yaml
repository:
  connector: parsongh
  repo: harness-demo-app
  branch: main
  path: tofu/stacks/eks

provisioner:
  type: OpenTofu
  version: 1.11.2
```
