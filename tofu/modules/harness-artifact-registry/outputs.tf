################################################################################
# Harness Artifact Registry Module - Outputs
################################################################################

output "registry_id" {
  description = "The identifier of the created registry"
  value       = harness_platform_har_registry.registry.identifier
}

output "registry_url" {
  description = "The URL to push/pull images from the registry"
  value       = "pkg.harness.io/${var.account_id}/${var.org_id}/${var.project_id}/${var.registry_id}"
}

output "dockerhub_upstream_id" {
  description = "The identifier of the DockerHub upstream proxy (if created)"
  value       = var.create_dockerhub_upstream ? harness_platform_har_registry.dockerhub_upstream[0].identifier : null
}
