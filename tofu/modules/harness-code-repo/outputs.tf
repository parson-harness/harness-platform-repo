################################################################################
# Harness Code Repository Module - Outputs
################################################################################

output "repo_identifier" {
  description = "Identifier of the repository in Harness Code"
  value       = var.create_repo ? var.repo_identifier : ""
}

output "repo_name" {
  description = "Name of the repository (same as identifier for Harness Code)"
  value       = local.repo_name
}

output "harness_code_repo_url" {
  description = "Git URL of the repository in Harness Code"
  value       = local.harness_code_repo_url
}

output "git_url" {
  description = "Git URL from the Harness platform repo resource"
  value       = var.create_repo && length(harness_platform_repo.main) > 0 ? harness_platform_repo.main[0].git_url : ""
}

output "is_harness_code_repo" {
  description = "Whether this is a Harness Code repository"
  value       = var.create_repo
}
