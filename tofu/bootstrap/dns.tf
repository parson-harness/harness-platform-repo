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

locals {
  dns_domain      = "harness-demo.dev"
  wildcard_domain = "*.${local.dns_domain}"
  sentinel_domain = "sentinel.${local.dns_domain}"
}

################################################################################
# Route53 Hosted Zone
################################################################################

resource "aws_route53_zone" "harness_demo" {
  name = local.dns_domain

  tags = {
    Name    = local.dns_domain
    Purpose = "Shared demo app domain for Harness SE sandboxes and POVs"
  }
}

################################################################################
# Sentinel DNS Record → Shared ALB
# The sentinel ingress (tofu/shared-infra/eks-cluster/sentinel-ingress.yaml)
# keeps the shared ALB alive even when all sandbox ingresses are deleted.
#
# Individual sandbox DNS records are created per-sandbox in tofu/stacks/eks/main.tf
# using the shared_alb_dns_name variable.
#
# Set alb_dns_name after applying the sentinel ingress:
#   kubectl apply -f tofu/shared-infra/eks-cluster/sentinel-ingress.yaml
#   kubectl get ingress -n harness-demo-sentinel -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}'
################################################################################

resource "aws_route53_record" "sentinel" {
  count   = var.alb_dns_name != "" ? 1 : 0
  zone_id = aws_route53_zone.harness_demo.zone_id
  name    = local.sentinel_domain
  type    = "CNAME"
  ttl     = 60
  records = [var.alb_dns_name]
}

################################################################################
# Wildcard CNAME → Shared ALB (LEGACY/FALLBACK)
# Individual sandbox DNS is now managed per-sandbox in Terraform.
# This wildcard is kept as a fallback for any subdomains not explicitly created.
################################################################################

resource "aws_route53_record" "wildcard" {
  count   = var.alb_dns_name != "" ? 1 : 0
  zone_id = aws_route53_zone.harness_demo.zone_id
  name    = local.wildcard_domain
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
  domain   = local.wildcard_domain
  statuses = ["PENDING_VALIDATION", "ISSUED"]
}

resource "aws_route53_record" "acm_validation" {
  zone_id = aws_route53_zone.harness_demo.zone_id
  name    = "_d29c1e3c5b9cf27b1a10c48d5b5bab19.${local.dns_domain}"
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
  triggers_replace = {
    cert_arn                   = data.aws_acm_certificate.wildcard.arn
    coverage_bucket_name       = aws_s3_bucket.coverage_artifacts.id
    coverage_bucket_region     = var.aws_region
    coverage_artifact_prefix   = var.coverage_report_artifact_path_prefix
  }

  provisioner "local-exec" {
    command = <<-EOT
      COVERAGE_BUCKET_NAME="${aws_s3_bucket.coverage_artifacts.id}" \
      COVERAGE_BUCKET_REGION="${var.aws_region}" \
      COVERAGE_ARTIFACT_PATH_PREFIX="${var.coverage_report_artifact_path_prefix}" \
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

  depends_on = [aws_acm_certificate_validation.wildcard, aws_s3_bucket.coverage_artifacts]
}
