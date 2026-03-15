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
