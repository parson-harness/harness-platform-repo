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
│   ├── vpc/                 # VPC with public/private subnets
│   ├── eks/                 # EKS cluster with managed node group
│   ├── ecr/                 # ECR container registry
│   ├── irsa-delegate-role/  # IAM role for delegate IRSA
│   ├── harness-delegate/    # Harness Delegate deployment
│   └── harness-connectors/  # Harness connectors (K8s, AWS, Docker, GitHub)
└── environments/
    ├── sandbox/             # Personal sandbox environment
    └── pov-template/        # Template for customer POVs
```

## Prerequisites

1. **OpenTofu or Terraform** >= 1.6.0
2. **AWS CLI** configured with appropriate credentials
3. **kubectl** for Kubernetes access
4. **Harness Account** with:
   - API Key
   - Delegate Token
   - Organization and Project created

## Quick Start (Using Existing Cluster)

```bash
cd tofu/environments/sandbox

# Copy and configure variables
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars - set your values:
# - owner = "your-lastname"
# - existing_cluster_name = "your-eks-cluster"
# - create_eks_cluster = false
# - Harness credentials

# Initialize and apply
tofu init
tofu apply
```

## Quick Start (Creating New Cluster)

```bash
cd tofu/environments/sandbox

# Edit terraform.tfvars:
# - create_eks_cluster = true
# - enable_nat_gateway = true (or false to save costs)

tofu init
tofu apply  # Takes ~20 minutes
```

## What Gets Created

### AWS Resources (if creating new cluster)
- **VPC** with 3 public and 3 private subnets across AZs
- **NAT Gateway** for private subnet internet access
- **EKS Cluster** with managed node group

### AWS Resources (always)
- **ECR Repository** for container images (`harness-demo-app-<owner>`)
- **IRSA IAM Role** for delegate AWS access

### Harness Resources
- **Delegate** in namespace `harness-delegate-ng-<owner>`
- **Kubernetes Connector** using delegate credentials
- **AWS Connector** with IRSA and optional cross-account STS
- **Docker Connector** for ECR registry
- **GitHub Connector** (optional) for pipeline source

## Cost Optimization

For development/POV environments:

```hcl
# Use SPOT instances
node_capacity_type = "SPOT"

# Smaller instance types
node_instance_types = ["t3.small"]

# Fewer nodes
node_desired_size = 1
node_max_size     = 2

# Disable NAT Gateway (saves ~$30/month, but private subnets lose internet)
enable_nat_gateway = false
```

## Creating a New POV Environment

1. Copy the sandbox environment:
   ```bash
   cp -r tofu/environments/sandbox tofu/environments/pov-acme
   ```

2. Update `terraform.tfvars`:
   ```hcl
   environment        = "pov-acme"
   owner              = "your-name"
   harness_project_id = "acme_pov"
   ```

3. Apply:
   ```bash
   cd tofu/environments/pov-acme
   tofu init && tofu apply
   ```

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
