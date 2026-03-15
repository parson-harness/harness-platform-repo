# Terraform configuration for Harness POV Demo App
# Useful for IACM demonstrations

terraform {
  required_version = ">= 1.0.0"
  
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.25"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
  }
}

variable "namespace" {
  description = "Kubernetes namespace for deployment"
  type        = string
  default     = "harness-pov"
}

variable "app_version" {
  description = "Application version to deploy"
  type        = string
  default     = "1.0.0"
}

variable "deployment_variant" {
  description = "Deployment variant (blue, green, canary, stable)"
  type        = string
  default     = "stable"
}

variable "variant_color" {
  description = "Color for the deployment variant"
  type        = string
  default     = "#3B82F6"
}

variable "replicas" {
  description = "Number of replicas"
  type        = number
  default     = 2
}

variable "customer_name" {
  description = "Customer name for personalization"
  type        = string
  default     = "Harness Customer"
}

resource "kubernetes_namespace" "app" {
  metadata {
    name = var.namespace
    labels = {
      app         = "harness-pov-app"
      managed-by  = "terraform"
    }
  }
}

resource "kubernetes_deployment" "app" {
  metadata {
    name      = "harness-pov-app"
    namespace = kubernetes_namespace.app.metadata[0].name
    labels = {
      app     = "harness-pov-app"
      version = var.app_version
      variant = var.deployment_variant
    }
  }

  spec {
    replicas = var.replicas

    selector {
      match_labels = {
        app = "harness-pov-app"
      }
    }

    template {
      metadata {
        labels = {
          app     = "harness-pov-app"
          version = var.app_version
          variant = var.deployment_variant
        }
        annotations = {
          "prometheus.io/scrape" = "true"
          "prometheus.io/port"   = "8080"
          "prometheus.io/path"   = "/actuator/prometheus"
        }
      }

      spec {
        container {
          name  = "harness-pov-app"
          image = "harness-pov-app:${var.app_version}"

          port {
            container_port = 8080
            name           = "http"
          }

          env {
            name  = "APP_VERSION"
            value = var.app_version
          }
          env {
            name  = "DEPLOYMENT_VARIANT"
            value = var.deployment_variant
          }
          env {
            name  = "VARIANT_COLOR"
            value = var.variant_color
          }
          env {
            name  = "CUSTOMER_NAME"
            value = var.customer_name
          }
          env {
            name = "NAMESPACE"
            value_from {
              field_ref {
                field_path = "metadata.namespace"
              }
            }
          }

          resources {
            requests = {
              memory = "256Mi"
              cpu    = "250m"
            }
            limits = {
              memory = "512Mi"
              cpu    = "500m"
            }
          }

          liveness_probe {
            http_get {
              path = "/actuator/health/liveness"
              port = 8080
            }
            initial_delay_seconds = 30
            period_seconds        = 10
          }

          readiness_probe {
            http_get {
              path = "/actuator/health/readiness"
              port = 8080
            }
            initial_delay_seconds = 10
            period_seconds        = 5
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "app" {
  metadata {
    name      = "harness-pov-app"
    namespace = kubernetes_namespace.app.metadata[0].name
  }

  spec {
    selector = {
      app = "harness-pov-app"
    }

    port {
      port        = 80
      target_port = 8080
      protocol    = "TCP"
      name        = "http"
    }

    type = "ClusterIP"
  }
}

output "namespace" {
  value = kubernetes_namespace.app.metadata[0].name
}

output "service_name" {
  value = kubernetes_service.app.metadata[0].name
}

output "deployment_variant" {
  value = var.deployment_variant
}
