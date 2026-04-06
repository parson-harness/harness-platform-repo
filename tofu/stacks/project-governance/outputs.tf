output "org_id" {
  description = "Harness organization ID"
  value       = local.resolved_org_id
}

output "project_id" {
  description = "Harness project ID"
  value       = local.resolved_project_id
}

output "policy_set_ids" {
  description = "OPA policy set identifiers created for the project"
  value       = module.opa_policies.policy_set_ids
}

output "change_governance_policy_ids" {
  description = "Change governance policy identifiers created for the project"
  value       = module.opa_policies.change_governance_policy_ids
}
