################################################################################
# Outputs
################################################################################

output "state_bucket_name" {
  description = "S3 bucket name for terraform state"
  value       = aws_s3_bucket.tfstate.id
}

output "state_bucket_arn" {
  description = "S3 bucket ARN for terraform state"
  value       = aws_s3_bucket.tfstate.arn
}

output "dynamodb_table_name" {
  description = "DynamoDB table name for state locking"
  value       = aws_dynamodb_table.tfstate_lock.name
}

output "backend_config" {
  description = "Backend configuration to add to your environment"
  value       = <<-EOT
    # Add this to your environment's main.tf:
    terraform {
      backend "s3" {
        bucket         = "${aws_s3_bucket.tfstate.id}"
        key            = "harness-demo/<environment>/terraform.tfstate"
        region         = "${var.aws_region}"
        encrypt        = true
        dynamodb_table = "${aws_dynamodb_table.tfstate_lock.name}"
      }
    }
  EOT
}

output "hosted_zone_id" {
  description = "Route53 hosted zone ID - needed for ACM DNS validation"
  value       = aws_route53_zone.harness_demo.zone_id
}

output "name_servers" {
  description = "Nameservers for the shared demo domain. Point your registrar here if registered outside Route53."
  value       = aws_route53_zone.harness_demo.name_servers
}

output "wildcard_cname_status" {
  description = "Status of the wildcard CNAME record"
  value       = var.alb_dns_name != "" ? "Active: ${local.wildcard_domain} → ${var.alb_dns_name}" : "Pending: run again with -var=\"alb_dns_name=<your-alb-hostname>\""
}

output "next_step_alb_dns_command" {
  description = "Run this after first Harness deployment to get the ALB hostname for the wildcard CNAME"
  value       = "kubectl get ingress -A -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}'"
}

output "acm_cert_arn" {
  description = "ACM wildcard cert ARN - add to sandbox tfvars as: acm_cert_arn = \"<value>\""
  value       = data.aws_acm_certificate.wildcard.arn
}

output "harness_oidc_role_arn" {
  description = "ARN of the Harness OIDC role — paste into the Harness IACM AWS connector"
  value       = aws_iam_role.harness_oidc.arn
}
