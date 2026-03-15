################################################################################
# Harness Monitored Service Module
# Creates a monitored service with health sources for Continuous Verification
################################################################################

terraform {
  required_providers {
    harness = {
      source  = "harness/harness"
      version = "~> 0.30"
    }
  }
}

################################################################################
# Monitored Service with Prometheus Health Source
################################################################################

resource "harness_platform_monitored_service" "main" {
  org_id     = var.org_id
  project_id = var.project_id
  identifier = var.monitored_service_id

  request {
    name            = var.monitored_service_name
    type            = "Application"
    description     = var.monitored_service_description
    service_ref     = var.service_ref
    environment_ref = var.environment_ref
    tags            = var.tags

    health_sources {
      name       = var.health_source_name
      identifier = var.health_source_id
      type       = "Prometheus"
      spec = jsonencode({
        connectorRef = var.prometheus_connector_ref
        metricDefinitions = [
          {
            identifier = "prometheus_metric"
            metricName = "Prometheus Metric"
            riskProfile = {
              riskCategory = "Performance_Other"
              thresholdTypes = [
                "ACT_WHEN_HIGHER"
              ]
            }
            analysis = {
              liveMonitoring = {
                enabled = true
              }
              deploymentVerification = {
                enabled                  = true
                serviceInstanceFieldName = "pod_name"
              }
            }
            query         = "avg(container_cpu_usage_seconds_total{namespace=\"${var.namespace}\", pod=~\"${var.app_name}.*\"})"
            groupName     = "Infrastructure"
            isManualQuery = true
          }
        ]
      })
    }
  }
}
