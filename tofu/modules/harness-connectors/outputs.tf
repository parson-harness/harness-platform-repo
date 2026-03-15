output "k8s_connector_id" {
  description = "ID of the Kubernetes connector"
  value       = var.create_k8s_connector ? harness_platform_connector_kubernetes.cluster[0].identifier : null
}

output "aws_connector_id" {
  description = "ID of the AWS connector"
  value       = var.create_aws_connector ? harness_platform_connector_aws.main[0].identifier : null
}

output "docker_connector_id" {
  description = "ID of the Docker registry connector"
  value       = var.create_docker_connector ? harness_platform_connector_docker.ecr[0].identifier : null
}

output "github_connector_id" {
  description = "ID of the GitHub connector"
  value       = var.create_github_connector ? harness_platform_connector_github.repo[0].identifier : null
}

output "prometheus_connector_id" {
  description = "ID of the Prometheus connector"
  value       = var.create_prometheus_connector ? harness_platform_connector_prometheus.monitoring[0].identifier : null
}
