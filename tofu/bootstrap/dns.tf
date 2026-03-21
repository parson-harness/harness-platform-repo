################################################################################
# harness-demo.dev DNS Setup
#
# Creates the Route53 hosted zone for harness-demo.dev, optionally registers
# the domain via Route53 Domains, and adds the wildcard CNAME once the shared
# ALB DNS name is known.
#
# Usage:
#   Step 1 - Create hosted zone:
#     tofu apply -var="owner=parson"
#
#   Step 2 - Register harness-demo.dev at an external registrar:
#     Route53 Domains does NOT support .dev (Google TLD).
#     Use: Google Domains, Namecheap, Squarespace Domains, or Cloudflare.
#     Then point the registrar's nameservers to the `name_servers` output.
#
#   Step 3 - After first deployment, get ALB DNS and add wildcard CNAME:
#     kubectl get ingress -A -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}'
#     tofu apply -var="owner=parson" -var="alb_dns_name=<alb-hostname>"
#
# Note: .dev is HSTS-preloaded. Browsers enforce HTTPS. HTTP works for curl.
# Add the ACM cert to enable HTTPS for browsers.
################################################################################

################################################################################
# Variables
################################################################################

################################################################################
# Harness Integration Variables
# Required to automatically push cert ARN into the POV_Provisioner IACM template
################################################################################

variable "harness_endpoint" {
  description = "Harness API endpoint"
  type        = string
  default     = "https://app.harness.io/gratis"
}

variable "harness_account_id" {
  description = "Harness account ID"
  type        = string
  default     = ""
}

variable "harness_org_id" {
  description = "Harness org where the POV_Provisioner template lives"
  type        = string
  default     = "sandbox"
}

variable "harness_project_id" {
  description = "Harness project where the POV_Provisioner template lives"
  type        = string
  default     = "parson"
}

variable "harness_api_key" {
  description = "Harness API key — used to push acm_cert_arn into the POV_Provisioner template"
  type        = string
  default     = ""
  sensitive   = true
}

variable "harness_template_id" {
  description = "IACM workspace template identifier to update with the cert ARN"
  type        = string
  default     = "POV_Provisioner"
}

variable "alb_dns_name" {
  description = "Shared ALB DNS hostname. Get AFTER first CD deployment: kubectl get ingress -A -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}'. ALB name is auto-generated per cluster and changes on rebuild."
  type        = string
  default     = ""
}

################################################################################
# Route53 Hosted Zone
################################################################################

resource "aws_route53_zone" "harness_demo" {
  name = "harness-demo.dev"

  tags = {
    Name    = "harness-demo.dev"
    Purpose = "Shared demo app domain for Harness SE sandboxes and POVs"
  }
}

################################################################################
# Wildcard CNAME → Shared ALB
# Set alb_dns_name after first deployment to activate.
# Get the value with:
#   kubectl get ingress -A -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}'
################################################################################

resource "aws_route53_record" "wildcard" {
  count   = var.alb_dns_name != "" ? 1 : 0
  zone_id = aws_route53_zone.harness_demo.zone_id
  name    = "*.harness-demo.dev"
  type    = "CNAME"
  ttl     = 300
  records = [var.alb_dns_name]
}

################################################################################
# ACM Wildcard Certificate (*.harness-demo.dev)
# Certificate was requested via CLI - referenced here as a data source.
# This adds the DNS validation record to Route53 and waits for issuance.
################################################################################

data "aws_acm_certificate" "wildcard" {
  domain   = "*.harness-demo.dev"
  statuses = ["PENDING_VALIDATION", "ISSUED"]
}

resource "aws_route53_record" "acm_validation" {
  zone_id = aws_route53_zone.harness_demo.zone_id
  name    = "_d29c1e3c5b9cf27b1a10c48d5b5bab19.harness-demo.dev"
  type    = "CNAME"
  ttl     = 300
  records = ["_946fe72819dcd6df0b2d21cd5144857b.jkddzztszm.acm-validations.aws."]
}

resource "aws_acm_certificate_validation" "wildcard" {
  certificate_arn         = data.aws_acm_certificate.wildcard.arn
  validation_record_fqdns = [aws_route53_record.acm_validation.fqdn]
}

################################################################################
# Push cert ARN into POV_Provisioner IACM template
# Runs whenever the cert ARN changes (effectively once per account).
# Requires harness_api_key and harness_account_id to be set.
################################################################################

resource "terraform_data" "push_cert_arn_to_harness" {
  triggers_replace = [data.aws_acm_certificate.wildcard.arn]

  provisioner "local-exec" {
    command = <<-EOT
      python3 ${path.module}/update_harness_template.py \
        "${var.harness_endpoint}" \
        "${var.harness_account_id}" \
        "${var.harness_org_id}" \
        "${var.harness_project_id}" \
        "${var.harness_api_key}" \
        "${var.harness_template_id}" \
        "${data.aws_acm_certificate.wildcard.arn}"
    EOT
  }

  depends_on = [aws_acm_certificate_validation.wildcard]
}

################################################################################
# Outputs
################################################################################

output "hosted_zone_id" {
  description = "Route53 hosted zone ID - needed for ACM DNS validation"
  value       = aws_route53_zone.harness_demo.zone_id
}

output "name_servers" {
  description = "Nameservers for harness-demo.dev. Point your registrar here if registered outside Route53."
  value       = aws_route53_zone.harness_demo.name_servers
}

output "wildcard_cname_status" {
  description = "Status of the wildcard CNAME record"
  value       = var.alb_dns_name != "" ? "Active: *.harness-demo.dev → ${var.alb_dns_name}" : "Pending: run again with -var=\"alb_dns_name=<your-alb-hostname>\""
}

output "next_step_alb_dns_command" {
  description = "Run this after first Harness deployment to get the ALB hostname for the wildcard CNAME"
  value       = "kubectl get ingress -A -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}'"
}

output "acm_cert_arn" {
  description = "ACM wildcard cert ARN - add to sandbox tfvars as: acm_cert_arn = \"<value>\""
  value       = data.aws_acm_certificate.wildcard.arn
}
