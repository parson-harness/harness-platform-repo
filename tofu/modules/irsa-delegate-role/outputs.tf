output "role_arn" {
  description = "ARN of the delegate IRSA role"
  value       = aws_iam_role.delegate.arn
}

output "role_name" {
  description = "Name of the delegate IRSA role"
  value       = aws_iam_role.delegate.name
}

output "service_account_annotation" {
  description = "Annotation to add to the Kubernetes service account"
  value       = "eks.amazonaws.com/role-arn: ${aws_iam_role.delegate.arn}"
}
