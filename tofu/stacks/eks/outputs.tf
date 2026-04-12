################################################################################
# Outputs
################################################################################

output "org_id" {
  description = "Harness organization ID"
  value       = local.resolved_org_id
}

output "project_id" {
  description = "Harness project ID"
  value       = local.resolved_project_id
}

output "service_id" {
  description = "Harness service ID"
  value       = module.harness_service.service_id
}

output "environment_id" {
  description = "Harness environment ID"
  value       = module.harness_environment_dev.environment_id
}

output "k8s_namespace" {
  description = "Kubernetes namespace for the application"
  value       = local.k8s_namespace
}

output "app_url" {
  description = "Application URL"
  value       = "https://${var.owner}.harness-demo.dev"
}

output "stage_url" {
  description = "Stage application URL"
  value       = "https://${var.owner}-stage.harness-demo.dev"
}

output "delegate_name" {
  description = "Delegate name"
  value       = var.create_delegate ? "delegate-${var.owner}" : null
}

output "delegate_irsa_role_arn" {
  description = "IRSA role ARN for the delegate"
  value       = var.create_delegate ? module.irsa_delegate_role[0].role_arn : null
}

output "alb_dns_name" {
  description = "Shared ALB DNS name used for this sandbox's Route53 records when manage_dns is enabled"
  value       = var.shared_alb_dns_name != "" ? var.shared_alb_dns_name : null
}

output "dns_record" {
  description = "Primary per-sandbox DNS record created by this stack when manage_dns is enabled"
  value       = local.create_dns_record ? "${var.owner}.${var.dns_domain} -> ${var.shared_alb_dns_name}" : null
}

output "opa_policy_sets" {
  description = "OPA policy sets created for CI/CD governance"
  value       = var.create_opa_policies ? module.opa_policies[0].policy_set_ids : null
}
