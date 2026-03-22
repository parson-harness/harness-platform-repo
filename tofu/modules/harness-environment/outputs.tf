output "environment_id" {
  description = "Environment identifier"
  value       = harness_platform_environment.main.identifier
}

output "environment_name" {
  description = "Environment name"
  value       = harness_platform_environment.main.name
}

output "k8s_infrastructure_id" {
  description = "Kubernetes infrastructure identifier"
  value       = var.create_k8s_infrastructure ? harness_platform_infrastructure.kubernetes[0].identifier : null
}

output "ecs_infrastructure_id" {
  description = "ECS infrastructure identifier"
  value       = var.create_ecs_infrastructure ? harness_platform_infrastructure.ecs[0].identifier : null
}

output "lambda_infrastructure_id" {
  description = "Lambda infrastructure identifier"
  value       = var.create_lambda_infrastructure ? harness_platform_infrastructure.lambda[0].identifier : null
}

output "asg_infrastructure_id" {
  description = "ASG infrastructure identifier"
  value       = var.create_asg_infrastructure ? harness_platform_infrastructure.asg[0].identifier : null
}
