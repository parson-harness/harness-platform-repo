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
    enabled         = var.enabled
    tags            = var.tags

    health_sources {
      name       = var.health_source_name
      identifier = var.health_source_id
      type       = "Prometheus"
      spec = jsonencode({
        connectorRef = var.prometheus_connector_ref
        metricDefinitions = [
          {
            identifier = "cpu_usage"
            metricName = "CPU Usage"
            riskProfile = {
              riskCategory   = "Performance_Other"
              thresholdTypes = ["ACT_WHEN_HIGHER"]
            }
            analysis = {
              liveMonitoring = {
                enabled = var.enable_live_monitoring
              }
              deploymentVerification = {
                enabled                  = true
                serviceInstanceFieldName = "pod"
              }
            }
            query         = "avg(rate(container_cpu_usage_seconds_total{namespace=\"${var.namespace}\", pod=~\"${var.app_name}.*\"}[5m])) by (pod)"
            groupName     = "Infrastructure"
            isManualQuery = true
          },
          {
            identifier = "memory_usage"
            metricName = "Memory Usage"
            riskProfile = {
              riskCategory   = "Performance_Other"
              thresholdTypes = ["ACT_WHEN_HIGHER"]
            }
            analysis = {
              liveMonitoring = {
                enabled = var.enable_live_monitoring
              }
              deploymentVerification = {
                enabled                  = true
                serviceInstanceFieldName = "pod"
              }
            }
            query         = "avg(container_memory_working_set_bytes{namespace=\"${var.namespace}\", pod=~\"${var.app_name}.*\"}) by (pod)"
            groupName     = "Infrastructure"
            isManualQuery = true
          },
          {
            identifier = "http_requests"
            metricName = "HTTP Request Rate"
            riskProfile = {
              riskCategory   = "Performance_Throughput"
              thresholdTypes = ["ACT_WHEN_LOWER"]
            }
            analysis = {
              liveMonitoring = {
                enabled = var.enable_live_monitoring
              }
              deploymentVerification = {
                enabled                  = true
                serviceInstanceFieldName = "pod"
              }
            }
            query         = "sum(rate(http_server_requests_seconds_count{namespace=\"${var.namespace}\", pod=~\"${var.app_name}.*\"}[5m])) by (pod)"
            groupName     = "Performance"
            isManualQuery = true
          },
          {
            identifier = "http_errors"
            metricName = "HTTP Error Rate"
            riskProfile = {
              riskCategory   = "Errors"
              thresholdTypes = ["ACT_WHEN_HIGHER"]
            }
            analysis = {
              liveMonitoring = {
                enabled = var.enable_live_monitoring
              }
              deploymentVerification = {
                enabled                  = true
                serviceInstanceFieldName = "pod"
              }
            }
            query         = "sum(rate(http_server_requests_seconds_count{namespace=\"${var.namespace}\", pod=~\"${var.app_name}.*\", status=~\"5..\"}[5m])) by (pod)"
            groupName     = "Errors"
            isManualQuery = true
          }
        ]
        metricPacks = [
          {
            identifier = "Custom"
            metricThresholds = [
              {
                type = "FailImmediately"
                spec = {
                  action = "FailImmediately"
                  spec   = {}
                }
                criteria = {
                  type = "Absolute"
                  spec = {
                    greaterThan = var.memory_threshold_bytes
                  }
                }
                metricType = "Custom"
                metricName = "Memory Usage"
              }
            ]
          }
        ]
      })
    }
  }
}
