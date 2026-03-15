################################################################################
# Harness Monitored Service Module - Variables
################################################################################

variable "org_id" {
  description = "Harness organization ID"
  type        = string
}

variable "project_id" {
  description = "Harness project ID"
  type        = string
}

################################################################################
# Monitored Service Configuration
################################################################################

variable "monitored_service_id" {
  description = "Identifier for the monitored service"
  type        = string
}

variable "monitored_service_name" {
  description = "Display name for the monitored service"
  type        = string
}

variable "monitored_service_description" {
  description = "Description for the monitored service"
  type        = string
  default     = "Monitored service for Continuous Verification"
}

variable "service_ref" {
  description = "Reference to the Harness service"
  type        = string
}

variable "environment_ref" {
  description = "Reference to the Harness environment"
  type        = string
}

variable "enabled" {
  description = "Enable the monitored service"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags for the monitored service"
  type        = list(string)
  default     = []
}

################################################################################
# Health Source Configuration
################################################################################

variable "health_source_name" {
  description = "Name for the health source"
  type        = string
  default     = "Prometheus Metrics"
}

variable "health_source_id" {
  description = "Identifier for the health source"
  type        = string
  default     = "prometheus_metrics"
}

variable "prometheus_connector_ref" {
  description = "Reference to the Prometheus connector"
  type        = string
}

variable "enable_live_monitoring" {
  description = "Enable live monitoring for metrics"
  type        = bool
  default     = true
}

################################################################################
# Application Configuration (for metric queries)
################################################################################

variable "namespace" {
  description = "Kubernetes namespace where the application runs"
  type        = string
}

variable "app_name" {
  description = "Application name (used in pod selector)"
  type        = string
}

################################################################################
# Thresholds
################################################################################

variable "memory_threshold_bytes" {
  description = "Memory threshold in bytes for fail-immediately condition"
  type        = number
  default     = 536870912  # 512MB
}
