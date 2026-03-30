output "role_arn" {
  description = "ARN of the delegate IRSA role"
  value       = local.role_arn
}

output "role_name" {
  description = "Name of the delegate IRSA role"
  value       = local.role_name
}

output "service_account_annotation" {
  description = "Annotation to add to the Kubernetes service account"
  value       = "eks.amazonaws.com/role-arn: ${local.role_arn}"
}
