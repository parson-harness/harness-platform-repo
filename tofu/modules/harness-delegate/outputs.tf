output "delegate_name" {
  description = "Name of the deployed delegate"
  value       = var.create_delegate ? helm_release.delegate[0].name : null
}

output "delegate_namespace" {
  description = "Namespace where the delegate is deployed"
  value       = var.create_delegate ? helm_release.delegate[0].namespace : null
}

output "delegate_status" {
  description = "Status of the Helm release"
  value       = var.create_delegate ? helm_release.delegate[0].status : null
}
