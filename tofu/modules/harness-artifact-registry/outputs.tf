################################################################################
# Harness Artifact Registry Module - Outputs
################################################################################

output "registry_id" {
  description = "The identifier of the created registry"
  value       = var.registry_id
}

output "registry_url" {
  description = "The URL to push/pull images from the registry (lowercase account ID for Docker compatibility)"
  value       = "pkg.harness.io/${lower(var.account_id)}/${var.registry_id}"
}

output "dockerhub_upstream_id" {
  description = "The identifier of the DockerHub upstream proxy (if created)"
  value       = var.create_dockerhub_upstream ? var.dockerhub_upstream_id : null
}
