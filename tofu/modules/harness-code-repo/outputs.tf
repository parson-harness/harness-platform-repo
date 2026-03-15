################################################################################
# Harness Code Repository Import Module - Outputs
################################################################################

output "repo_identifier" {
  description = "Identifier of the imported repository"
  value       = var.import_repo ? var.repo_identifier : ""
}

output "harness_code_repo_url" {
  description = "URL of the repository in Harness Code"
  value       = local.harness_code_repo_url
}

output "is_harness_code_repo" {
  description = "Whether this is a Harness Code repository (for connector configuration)"
  value       = var.import_repo
}
