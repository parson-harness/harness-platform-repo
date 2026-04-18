################################################################################
# Outputs
################################################################################

output "cluster_name" {
  description = "EKS cluster name"
  value       = var.eks_cluster_name
}

output "cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = data.aws_eks_cluster.cluster.endpoint
}

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

output "artifact_registry_type" {
  description = "Artifact registry type (har or ecr)"
  value       = var.artifact_registry_type
}

output "artifact_registry_url" {
  description = "Artifact registry URL (HAR or ECR)"
  value       = var.artifact_registry_type == "har" ? module.har[0].registry_url : "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/${local.ecr_image_path}"
}

output "ecr_repository_url" {
  description = "Derived ECR repository URL when artifact_registry_type=ecr"
  value       = var.artifact_registry_type == "ecr" ? "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/${local.ecr_image_path}" : null
}

output "har_registry_id" {
  description = "Harness Artifact Registry ID when artifact_registry_type=har"
  value       = var.artifact_registry_type == "har" ? module.har[0].registry_id : null
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

output "delegate_namespace" {
  description = "Harness delegate namespace"
  value       = var.create_delegate ? "harness-delegate-ng-${var.owner}" : null
}

output "delegate_selector" {
  description = "Delegate selector to use in Harness"
  value       = local.delegate_selector
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

output "k8s_connector_id" {
  description = "Harness Kubernetes connector ID"
  value       = module.harness_connectors.k8s_connector_id
}

output "aws_connector_id" {
  description = "Harness AWS connector ID in use (created by this stack or supplied as a shared connector ref)"
  value       = local.effective_aws_connector_id
}

output "github_connector_id" {
  description = "Harness GitHub connector ID in use when not using Harness Code"
  value       = var.use_harness_code ? null : local.effective_github_connector_id
}
