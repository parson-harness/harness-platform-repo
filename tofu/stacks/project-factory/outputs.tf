output "org_id" {
  description = "Harness organization ID"
  value       = local.resolved_org_id
}

output "project_id" {
  description = "Harness project ID"
  value       = local.resolved_project_id
}

output "shared_aws_connector_id" {
  description = "Shared project-level AWS connector identifier in use"
  value       = local.should_create_shared_aws_connector ? module.harness_connectors.aws_connector_id : local.shared_aws_connector_id
}

output "shared_github_connector_id" {
  description = "Shared project-level GitHub connector identifier in use"
  value       = local.should_create_shared_github_connector ? module.harness_connectors.github_connector_id : (var.shared_github_connector_id != "" ? var.shared_github_connector_id : null)
}

output "shared_har_registry_id" {
  description = "Shared project-level Harness Artifact Registry identifier in use"
  value       = local.should_create_shared_har_registry ? module.shared_har[0].registry_id : (var.shared_har_registry_id != "" ? var.shared_har_registry_id : null)
}

output "shared_har_dockerhub_upstream_id" {
  description = "Shared project-level DockerHub upstream proxy identifier in use"
  value       = local.should_create_shared_har_registry ? module.shared_har[0].dockerhub_upstream_id : (var.shared_har_dockerhub_upstream_id != "" ? var.shared_har_dockerhub_upstream_id : null)
}

output "shared_harness_code_repo_identifier" {
  description = "Shared project-level Harness Code repository identifier in use"
  value       = local.should_create_shared_harness_code_repo ? module.shared_harness_code_repo.repo_identifier : (var.shared_harness_code_repo_identifier != "" ? var.shared_harness_code_repo_identifier : null)
}

output "shared_delegate_selector" {
  description = "Stable delegate selector used by the shared project-level connectors"
  value       = var.shared_delegate_selector
}
