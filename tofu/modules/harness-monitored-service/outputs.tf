################################################################################
# Harness Monitored Service Module - Outputs
################################################################################

output "monitored_service_id" {
  description = "The identifier of the monitored service"
  value       = harness_platform_monitored_service.main.identifier
}

output "monitored_service_name" {
  description = "The name of the monitored service"
  value       = var.monitored_service_name
}
