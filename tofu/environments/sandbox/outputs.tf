################################################################################
# Outputs
################################################################################

output "cluster_name" {
  description = "EKS cluster name (new or existing)"
  value       = local.cluster_name
}

output "cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = local.cluster_endpoint
}

output "vpc_id" {
  description = "VPC ID (only if new cluster created)"
  value       = var.create_eks_cluster ? module.vpc[0].vpc_id : null
}

output "artifact_registry_type" {
  description = "Artifact registry type (har or ecr)"
  value       = var.artifact_registry_type
}

output "artifact_registry_url" {
  description = "Artifact registry URL (HAR or ECR)"
  value       = local.artifact_registry_url
}

output "ecr_repository_url" {
  description = "ECR repository URL (only if artifact_registry_type=ecr)"
  value       = var.artifact_registry_type == "ecr" && length(module.ecr) > 0 ? module.ecr[0].repository_url : null
}

output "har_registry_id" {
  description = "Harness Artifact Registry ID (only if artifact_registry_type=har)"
  value       = var.artifact_registry_type == "har" && length(module.har) > 0 ? module.har[0].registry_id : null
}

output "delegate_namespace" {
  description = "Harness Delegate namespace"
  value       = var.create_delegate ? "harness-delegate-ng-${var.owner}" : null
}

output "delegate_name" {
  description = "Harness Delegate name"
  value       = var.create_delegate ? "delegate-${var.owner}" : null
}

output "delegate_selector" {
  description = "Delegate selector to use in Harness"
  value       = local.delegate_selector
}

output "irsa_role_arn" {
  description = "IRSA role ARN for delegate"
  value       = var.create_delegate && var.enable_irsa && length(module.irsa_delegate_role) > 0 ? module.irsa_delegate_role[0].role_arn : null
}

output "k8s_connector_id" {
  description = "Harness K8s connector ID"
  value       = var.create_connectors ? module.harness_connectors[0].k8s_connector_id : null
}

output "aws_connector_id" {
  description = "Harness AWS connector ID"
  value       = var.create_connectors ? module.harness_connectors[0].aws_connector_id : null
}

output "kubeconfig_command" {
  description = "Command to configure kubectl"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${local.cluster_name}"
}

output "owner" {
  description = "Owner name used for resource naming"
  value       = var.owner
}

output "harness_org_id" {
  description = "Harness Organization ID (created or existing)"
  value       = local.resolved_org_id
}

output "harness_project_id" {
  description = "Harness Project ID (created or existing)"
  value       = local.resolved_project_id
}

output "harness_org_created" {
  description = "Whether the Harness organization was created"
  value       = module.harness_org_project.org_created
}

output "harness_project_created" {
  description = "Whether the Harness project was created"
  value       = module.harness_org_project.project_created
}

output "harness_service_id" {
  description = "ID of the Harness service"
  value       = var.create_harness_service && (local.enable_eks || local.enable_ecs || local.enable_lambda) ? module.harness_service[0].service_id : null
}

output "strategy_pipeline_id" {
  description = "Identifier of the strategy deployment pipeline"
  value       = var.create_harness_service && var.create_harness_environment && (local.enable_eks || local.enable_ecs || local.enable_lambda) ? module.harness_pipelines_dev[0].strategy_pipeline_identifier : null
}

output "standard_ci_gradle_id" {
  description = "Identifier of the standard Gradle CI pipeline"
  value       = var.create_harness_service && var.create_harness_environment && (local.enable_eks || local.enable_ecs || local.enable_lambda) ? module.harness_pipelines_dev[0].standard_ci_gradle_identifier : null
}

output "harness_dev_environment_id" {
  description = "Harness Dev Environment ID"
  value       = var.create_harness_environment ? module.harness_environment_dev[0].environment_id : null
}

output "harness_prod_environment_id" {
  description = "Harness Prod Environment ID"
  value       = var.create_harness_environment && var.create_prod_environment ? module.harness_environment_prod[0].environment_id : null
}

output "harness_k8s_dev_infra_id" {
  description = "Harness K8s Dev Infrastructure ID"
  value       = var.create_harness_environment ? module.harness_environment_dev[0].k8s_infrastructure_id : null
}

output "harness_k8s_prod_infra_id" {
  description = "Harness K8s Prod Infrastructure ID"
  value       = var.create_harness_environment && var.create_prod_environment ? module.harness_environment_prod[0].k8s_infrastructure_id : null
}

################################################################################
# ASG Outputs (when deployment_targets includes "asg")
################################################################################

output "asg_app_url" {
  description = "ASG demo app production URL (HTTPS port 443, or raw ALB if no DNS record)"
  value       = local.enable_asg && length(module.asg) > 0 ? module.asg[0].app_url : null
}

output "asg_stage_url" {
  description = "ASG stage URL for B/G validation (HTTP port 8080)"
  value       = local.enable_asg && length(module.asg) > 0 ? module.asg[0].stage_url : null
}

output "asg_alb_dns_name" {
  description = "Raw ALB DNS name for the ASG demo app"
  value       = local.enable_asg && length(module.asg) > 0 ? module.asg[0].alb_dns_name : null
}

output "asg_base_asg_name" {
  description = "Base/seed ASG name (referenced in Harness infrastructure definition)"
  value       = local.enable_asg && length(module.asg) > 0 ? module.asg[0].base_asg_name : null
}

output "asg_pipeline_id" {
  description = "ID of the ASG strategy pipeline"
  value       = local.enable_asg && var.create_harness_service && var.create_harness_environment && var.create_asg_strategy_pipeline ? module.harness_pipelines_asg[0].asg_strategy_pipeline_identifier : null
}

################################################################################
# TTL Outputs (for cleanup automation)
################################################################################

output "ttl_days" {
  description = "TTL in days (0 = never auto-cleanup)"
  value       = var.ttl_days
}

output "ttl_enabled" {
  description = "Whether TTL-based cleanup is enabled for this sandbox"
  value       = var.ttl_days > 0
}

output "created_at" {
  description = "ISO8601 timestamp when sandbox was created"
  value       = var.created_at != "" ? var.created_at : timestamp()
}

output "expires_at" {
  description = "ISO8601 timestamp when sandbox expires (null if TTL disabled)"
  value       = var.ttl_days > 0 ? timeadd(var.created_at != "" ? var.created_at : timestamp(), "${var.ttl_days * 24}h") : null
}
