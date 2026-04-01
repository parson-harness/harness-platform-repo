# Bootstrap - S3 Backend for Terraform State

Run this **once per AWS account** to create the S3 bucket and DynamoDB table for storing Terraform state.

## Usage

```bash
cd tofu/bootstrap

# Initialize
tofu init

# Apply (replace 'parson' with your name)
tofu apply -var="owner=parson"
```

## Output

After running, you'll get a `backend_config` output showing what to add to your environment's `main.tf`:

```hcl
terraform {
  backend "s3" {
    bucket         = "harness-demo-tfstate-parson-abc123"
    key            = "harness-demo/sandbox/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "harness-demo-tfstate-lock-parson"
  }
}
```

## Notes

- The bucket has `prevent_destroy = true` to avoid accidental deletion
- Versioning is enabled for state file recovery
- Server-side encryption is enabled
- Public access is blocked
- DynamoDB table uses pay-per-request billing (minimal cost)

## Current Scope

This directory now contains the long-lived bootstrap resources for the demo account:

- `main.tf` - S3 backend bucket + DynamoDB lock table
- `dns.tf` - Route53 zone, ACM validation records, shared DNS records, and template update helper wiring
- `oidc-role.tf` - AWS IAM role for Harness IACM OIDC access
- `SETUP.md` - account-specific setup notes and operational runbook

If you are looking for the full DNS/certificate flow or the manual/account-specific setup history, start with `SETUP.md`.
