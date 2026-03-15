# Shared Infrastructure

This directory contains **account-wide shared resources** that are created **once per AWS account** and shared across all SE sandboxes and customer POVs.

## What's Created

- **Shared ALB** - Single Application Load Balancer for all demo apps
- **Security Group** - Allows HTTP/HTTPS traffic
- **Default Listener** - Returns 404 for unmatched requests

## Architecture

```
                    ┌─────────────────────────┐
                    │   Route 53 (optional)   │
                    │   *.demo.harness.io     │
                    └───────────┬─────────────┘
                                │
                    ┌───────────▼─────────────┐
                    │   Shared ALB            │
                    │   (one per account)     │
                    └───────────┬─────────────┘
                                │
        ┌───────────────────────┼───────────────────────┐
        │                       │                       │
   ┌────▼────┐             ┌────▼────┐             ┌────▼────┐
   │ parson  │             │ smith   │             │ acme    │
   │ sandbox │             │ sandbox │             │  POV    │
   └─────────┘             └─────────┘             └─────────┘
   parson.demo.harness.io  smith.demo.harness.io   acme.demo.harness.io
```

## Prerequisites

1. VPC with public subnets (use existing EKS VPC)
2. (Optional) ACM certificate for HTTPS
3. (Optional) Route 53 hosted zone

## Usage

### First Time Setup (Once per AWS Account)

```bash
cd tofu/shared

# Initialize
tofu init

# Create terraform.tfvars
cat > terraform.tfvars <<EOF
aws_region        = "us-east-1"
vpc_id            = "vpc-xxxxxxxxx"        # Your EKS VPC
public_subnet_ids = ["subnet-aaa", "subnet-bbb"]
certificate_arn   = ""                      # Optional: ACM cert ARN
domain_name       = "demo.harness.io"       # Your demo domain
EOF

# Apply
tofu apply
```

### Outputs

After applying, you'll get:
- `alb_dns_name` - Use this for DNS CNAME records
- `http_listener_arn` - Sandboxes register listener rules here
- `alb_arn` - For reference in sandbox modules

## How Sandboxes Register

Each sandbox/POV adds a **listener rule** to route traffic based on hostname:

```hcl
# In sandbox's main.tf
data "terraform_remote_state" "shared" {
  backend = "s3"
  config = {
    bucket = "harness-demo-shared-tfstate"
    key    = "shared/terraform.tfstate"
    region = "us-east-1"
  }
}

resource "aws_lb_listener_rule" "sandbox" {
  listener_arn = data.terraform_remote_state.shared.outputs.http_listener_arn
  priority     = 100  # Unique per sandbox

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }

  condition {
    host_header {
      values = ["${var.owner}.demo.harness.io"]
    }
  }
}
```

## Cost

- **One ALB**: ~$20/month (shared across all sandboxes)
- **Per sandbox**: ~$0.008/hour per target group (negligible)

## vs Per-Sandbox ALB

| Approach | Cost (10 sandboxes) | Complexity |
|----------|---------------------|------------|
| Shared ALB | ~$25/month | Low |
| Per-sandbox ALB | ~$200/month | High |
