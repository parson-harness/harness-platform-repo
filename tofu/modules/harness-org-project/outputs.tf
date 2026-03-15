output "org_id" {
  description = "Organization ID (created or existing)"
  value       = local.org_id
}

output "project_id" {
  description = "Project ID (created or existing)"
  value       = local.project_id
}

output "org_created" {
  description = "Whether the organization was created by this module"
  value       = var.create_organization
}

output "project_created" {
  description = "Whether the project was created by this module"
  value       = var.create_project
}
