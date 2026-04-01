################################################################################
# DNS Management - Wildcard CNAME for *.harness-demo.dev
# Automatically updates the wildcard DNS to point to the shared ALB
################################################################################

data "aws_route53_zone" "harness_demo" {
  count = var.manage_dns ? 1 : 0
  name  = "${var.dns_domain}."
}

# DNS management for EKS ingress ALB
# Creates individual DNS record: {owner}.harness-demo.dev → shared ALB
# This is consistent with ASG pattern: {owner}-asg.harness-demo.dev → dedicated ALB
#
# The shared ALB is created by AWS Load Balancer Controller when the first ingress
# in the "harness-demo" group is deployed. Its DNS name is passed via shared_alb_dns_name.
locals {
  # Create individual DNS record if manage_dns=true and shared_alb_dns_name is provided
  create_dns_record = var.manage_dns && var.shared_alb_dns_name != ""
}

# Individual DNS record for this sandbox: {owner}.harness-demo.dev → shared ALB
resource "aws_route53_record" "app" {
  count           = local.create_dns_record ? 1 : 0
  zone_id         = var.route53_hosted_zone_id != "" ? var.route53_hosted_zone_id : data.aws_route53_zone.harness_demo[0].zone_id
  name            = "${var.owner}.${var.dns_domain}"
  type            = "CNAME"
  ttl             = 60
  records         = [var.shared_alb_dns_name]
  allow_overwrite = true

  lifecycle {
    create_before_destroy = true
  }
}

# Stage environment DNS record: {owner}-stage.harness-demo.dev → shared ALB
resource "aws_route53_record" "app_stage" {
  count           = local.create_dns_record ? 1 : 0
  zone_id         = var.route53_hosted_zone_id != "" ? var.route53_hosted_zone_id : data.aws_route53_zone.harness_demo[0].zone_id
  name            = "${var.owner}-stage.${var.dns_domain}"
  type            = "CNAME"
  ttl             = 60
  records         = [var.shared_alb_dns_name]
  allow_overwrite = true

  lifecycle {
    create_before_destroy = true
  }
}
