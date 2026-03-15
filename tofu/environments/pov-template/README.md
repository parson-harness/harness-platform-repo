# POV Environment Template

This directory serves as a template for creating new POV environments.

## Creating a New POV Environment

1. Copy this directory to a new folder:
   ```bash
   cp -r tofu/environments/pov-template tofu/environments/pov-<customer-name>
   ```

2. Copy and configure variables:
   ```bash
   cd tofu/environments/pov-<customer-name>
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with customer-specific values
   ```

3. Initialize and apply:
   ```bash
   tofu init
   tofu plan
   tofu apply
   ```

## Variables to Customize

| Variable | Description | Example |
|----------|-------------|---------|
| `environment` | POV identifier | `pov-acme` |
| `owner` | Your name/email | `todd.parson` |
| `harness_project_id` | Harness project for this POV | `acme_pov` |

## Notes

- Each POV gets its own isolated AWS resources
- Delegate and connectors are created in the specified Harness project
- Use SPOT instances for cost savings during POVs
