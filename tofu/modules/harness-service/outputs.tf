output "service_id" {
  description = "Service identifier"
  value       = harness_platform_service.main.identifier
}

output "service_name" {
  description = "Service name"
  value       = harness_platform_service.main.name
}
