# OpenTofu Infrastructure

This directory contains OpenTofu (Terraform-compatible) code to provision AWS infrastructure and Harness resources for the demo application.

## Key Features

- **Use existing or create new EKS cluster** - Skip cluster creation for faster setup
- **IRSA support** - IAM Roles for Service Accounts for secure AWS access
- **Cross-account STS** - Deploy to different AWS accounts
- **Owner-based namespacing** - Isolate resources by SE/POV name
- **Dynamic delegate versioning** - Automatically fetch latest delegate version
- **S3 backend** - Remote state storage with locking

## Directory Structure

```
tofu/
├── bootstrap/               # S3 backend setup (run once per account)
├── modules/
│   └── ...                  # Reusable stack building blocks
├── shared-infra/            # Long-lived shared infrastructure
└── stacks/
    ├── eks/                 # Harness + app resources targeting an existing EKS cluster
    ├── asg/                 # Customer-AWS Auto Scaling Group deployment path
    └── lambda/              # Future stack
```

## Prerequisites

1. **OpenTofu or Terraform** >= 1.6.0
2. **AWS CLI** configured with appropriate credentials
3. **kubectl** for Kubernetes access
4. **Harness Account** with:
   - API Key
   - Delegate Token
   - Organization and Project created

## Quick Start (Existing EKS Cluster)

```bash
cd tofu/stacks/eks

# Copy and configure variables
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars - set your values:
# - owner = "your-lastname"
# - eks_cluster_name = "your-eks-cluster"
# - Harness credentials

# Initialize and apply
tofu init
tofu apply
```

## Quick Start (Customer AWS via ASG Stack)

```bash
cd tofu/stacks/asg

# Copy and configure variables
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars with customer AWS and Harness values

tofu init
tofu apply
```

## What Gets Created

### EKS Stack
- **Existing EKS cluster target** provided via `eks_cluster_name`
- **Kubernetes namespace** for the owner sandbox
- **IRSA IAM role** for delegate access when delegate creation is enabled

### Harness Resources
- **Delegate** in namespace `harness-delegate-ng-<owner>` when `create_delegate = true`
- **Kubernetes Connector** using delegate credentials
- **AWS Connector** with IRSA and optional ECR usage
- **GitHub Connector** (optional) for pipeline source
- **HAR registry integration** or ECR image path wiring depending on `artifact_registry_type`
- **Harness Service, Environment, Infrastructure, and pipelines**

## Cost Optimization

For development/POV environments, prefer stack-specific sizing and registry options in the chosen stack's `terraform.tfvars.example`. The EKS stack assumes an existing cluster, while the ASG stack owns its own AWS footprint and is the right place to tune cost-sensitive infrastructure defaults.

## Creating a New POV Environment

Use a stack directory directly instead of copying a legacy environment:

1. Choose the stack:
   - `tofu/stacks/eks` for shared-EKS demos
   - `tofu/stacks/asg` for customer-AWS demos

2. Copy the example tfvars and set owner/project values.

3. Apply the chosen stack in its own directory.

## Cleanup

```bash
# Destroy all resources
tofu destroy

# Or destroy specific modules
tofu destroy -target=module.harness_delegate
```

## Troubleshooting

### Delegate not connecting
- Check delegate token is correct
- Verify EKS cluster is accessible
- Check delegate pod logs: `kubectl logs -n harness-delegate-ng -l app=harness-delegate`

### EKS access denied
- Update kubeconfig: `aws eks update-kubeconfig --region us-east-1 --name <cluster-name>`
- Verify IAM permissions

### Connector test fails
- Ensure delegate is healthy
- Check delegate selectors match
