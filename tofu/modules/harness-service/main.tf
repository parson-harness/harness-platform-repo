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
  # Artifact spec - ECR
  ecr_artifact_spec = {
    connectorRef = var.artifact_connector_ref
    imagePath    = var.ecr_image_path
    region       = var.aws_region
    tag          = "<+input>"
  }

  # Common artifacts block
  artifacts_block = var.artifact_source_type != "" ? {
    primary = {
      primaryArtifactRef = "<+input>"
      sources = [
        {
          identifier = "primary"
          type       = var.artifact_source_type
          spec       = local.ecr_artifact_spec
        }
      ]
    }
  } : null

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
