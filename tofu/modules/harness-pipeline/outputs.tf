################################################################################
# Harness Pipeline Module Outputs
################################################################################

output "canary_pipeline_id" {
  description = "ID of the Canary deployment pipeline"
  value       = var.create_canary_pipeline ? harness_platform_pipeline.k8s_canary[0].id : null
}

output "canary_pipeline_identifier" {
  description = "Identifier of the Canary deployment pipeline"
  value       = var.create_canary_pipeline ? harness_platform_pipeline.k8s_canary[0].identifier : null
}

output "blue_green_pipeline_id" {
  description = "ID of the Blue/Green + Canary deployment pipeline"
  value       = var.create_blue_green_pipeline ? harness_platform_pipeline.k8s_blue_green_canary[0].id : null
}

output "blue_green_pipeline_identifier" {
  description = "Identifier of the Blue/Green + Canary deployment pipeline"
  value       = var.create_blue_green_pipeline ? harness_platform_pipeline.k8s_blue_green_canary[0].identifier : null
}

output "strategy_pipeline_id" {
  description = "ID of the Strategy Choice deployment pipeline"
  value       = var.create_strategy_pipeline ? harness_platform_pipeline.k8s_strategy[0].id : null
}

output "strategy_pipeline_identifier" {
  description = "Identifier of the Strategy Choice deployment pipeline"
  value       = var.create_strategy_pipeline ? harness_platform_pipeline.k8s_strategy[0].identifier : null
}

output "ci_pipeline_id" {
  description = "ID of the CI build pipeline"
  value       = var.create_ci_pipeline ? harness_platform_pipeline.ci_build[0].id : null
}

output "ci_pipeline_identifier" {
  description = "Identifier of the CI build pipeline"
  value       = var.create_ci_pipeline ? harness_platform_pipeline.ci_build[0].identifier : null
}

output "cd_webhook_trigger_id" {
  description = "ID of the CD webhook trigger for auto-deploy"
  value       = var.create_ci_completion_trigger && var.create_ci_pipeline && var.create_canary_pipeline ? harness_platform_triggers.cd_webhook_trigger[0].id : null
}

output "cd_webhook_trigger_identifier" {
  description = "Identifier of the CD webhook trigger for auto-deploy"
  value       = var.create_ci_completion_trigger && var.create_ci_pipeline && var.create_canary_pipeline ? harness_platform_triggers.cd_webhook_trigger[0].identifier : null
}

output "asg_ci_pipeline_id" {
  description = "ID of the ASG CI build pipeline (Packer AMI)"
  value       = var.create_asg_ci_pipeline ? harness_platform_pipeline.asg_ci_build[0].id : null
}

output "asg_ci_pipeline_identifier" {
  description = "Identifier of the ASG CI build pipeline"
  value       = var.create_asg_ci_pipeline ? harness_platform_pipeline.asg_ci_build[0].identifier : null
}

output "asg_strategy_pipeline_id" {
  description = "ID of the ASG strategy pipeline"
  value       = var.create_asg_strategy_pipeline ? harness_platform_pipeline.asg_strategy[0].id : null
}

output "asg_strategy_pipeline_identifier" {
  description = "Identifier of the ASG strategy pipeline"
  value       = var.create_asg_strategy_pipeline ? harness_platform_pipeline.asg_strategy[0].identifier : null
}
