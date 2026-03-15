################################################################################
# Harness Service Definition Module
# Creates a Harness Service with Kubernetes or ECS deployment configuration
################################################################################

resource "harness_platform_service" "main" {
  identifier  = var.service_id
  name        = var.service_name
  description = var.service_description
  org_id      = var.org_id
  project_id  = var.project_id

  yaml = yamlencode({
    service = {
      name        = var.service_name
      identifier  = var.service_id
      description = var.service_description
      tags        = { for tag in var.tags : split(":", tag)[0] => try(split(":", tag)[1], "") }
      
      serviceDefinition = {
        type = var.deployment_type
        spec = local.service_spec
      }
    }
  })
}

locals {
  # Use JSON encoding to bypass Terraform's strict type checking
  # ECR artifacts block as JSON
  ecr_artifacts_json = jsonencode({
    primary = {
      primaryArtifactRef = "<+input>"
      sources = [{
        identifier = "primary"
        type       = "Ecr"
        spec = {
          connectorRef = var.artifact_connector_ref
          imagePath    = var.ecr_image_path
          region       = var.aws_region
          tag          = "<+input>"
        }
      }]
    }
  })

  # HAR artifacts block as JSON
  har_artifacts_json = jsonencode({
    primary = {
      primaryArtifactRef = "<+input>"
      sources = [{
        identifier = "primary"
        type       = "Har"
        spec = {
          registryRef = var.har_registry_ref
          type        = "docker"
          spec = {
            imagePath = var.har_image_path
            tag       = "<+input>"
            digest    = ""
          }
        }
      }]
    }
  })

  # Select artifacts block based on registry type (or null if neither)
  has_artifact_config = var.artifact_source_type != "" || var.artifact_registry_type != ""
  artifacts_json      = local.has_artifact_config ? (var.artifact_registry_type == "har" ? local.har_artifacts_json : local.ecr_artifacts_json) : null
  artifacts_block     = local.artifacts_json != null ? jsondecode(local.artifacts_json) : null

  # K8s manifest configuration
  k8s_manifests_block = var.deployment_type == "Kubernetes" && var.git_connector_ref != "" ? {
    manifests = [
      {
        manifest = {
          identifier = "k8s_manifests"
          type       = var.manifest_type
          spec = {
            store = {
              type = "Github"
              spec = {
                connectorRef = var.git_connector_ref
                gitFetchType = "Branch"
                branch       = var.git_branch
                paths        = var.manifest_paths
                repoName     = var.git_repo_name
              }
            }
            valuesPaths = ["k8s/values.yaml"]
          }
        }
      }
    ]
  } : null

  # Common variables block
  variables_block = [
    for v in var.service_variables : {
      name  = v.name
      type  = v.type
      value = v.value
    }
  ]

  # Service spec - merge artifacts, manifests, and variables
  service_spec = merge(
    local.artifacts_block != null ? { artifacts = local.artifacts_block } : {},
    local.k8s_manifests_block != null ? local.k8s_manifests_block : {},
    { variables = local.variables_block }
  )
}
