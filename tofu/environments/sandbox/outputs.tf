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
  value       = var.create_harness_service ? module.harness_service[0].service_id : null
}

output "canary_pipeline_id" {
  description = "ID of the Canary deployment pipeline"
  value       = var.create_harness_service && var.create_harness_environment ? module.harness_pipelines_dev[0].canary_pipeline_identifier : null
}

output "blue_green_pipeline_id" {
  description = "ID of the Blue/Green deployment pipeline"
  value       = var.create_blue_green_pipeline && var.create_harness_service && var.create_harness_environment ? module.harness_pipelines_dev[0].blue_green_pipeline_identifier : null
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
