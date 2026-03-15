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

  yaml = var.artifact_registry_type == "har" ? local.har_service_yaml : local.ecr_service_yaml
}

locals {
  # Tags formatted for YAML
  tags_yaml = join("\n", [for tag in var.tags : "    ${split(":", tag)[0]}: \"${try(split(":", tag)[1], "")}\""])

  # HAR service YAML (using heredoc to avoid yamlencode quoting)
  har_service_yaml = <<-EOT
service:
  name: ${var.service_name}
  identifier: ${var.service_id}
  description: ${var.service_description}
  tags:
${local.tags_yaml}
  serviceDefinition:
    type: ${var.deployment_type}
    spec:
      artifacts:
        primary:
          primaryArtifactRef: primary
          sources:
            - identifier: primary
              type: Har
              spec:
                registryRef: ${var.har_registry_ref}
                type: docker
                spec:
                  imagePath: ${var.har_image_path}
                  tag: <+pipeline.variables.image_tag>
                  digest: ""
      manifests:
        - manifest:
            identifier: k8s_manifests
            type: ${var.manifest_type}
            spec:
              store:
                type: Github
                spec:
                  connectorRef: ${var.git_connector_ref}
                  gitFetchType: Branch
                  branch: ${var.git_branch}
                  paths:
${join("\n", [for path in var.manifest_paths : "                    - ${path}"])}
                  repoName: ${var.git_repo_name}
              valuesPaths:
                - k8s/values.yaml
      variables: []
EOT

  # ECR service YAML
  ecr_service_yaml = <<-EOT
service:
  name: ${var.service_name}
  identifier: ${var.service_id}
  description: ${var.service_description}
  tags:
${local.tags_yaml}
  serviceDefinition:
    type: ${var.deployment_type}
    spec:
      artifacts:
        primary:
          primaryArtifactRef: primary
          sources:
            - identifier: primary
              type: Ecr
              spec:
                connectorRef: ${var.artifact_connector_ref}
                imagePath: ${var.ecr_image_path}
                region: ${var.aws_region}
                tag: <+input>
      manifests:
        - manifest:
            identifier: k8s_manifests
            type: ${var.manifest_type}
            spec:
              store:
                type: Github
                spec:
                  connectorRef: ${var.git_connector_ref}
                  gitFetchType: Branch
                  branch: ${var.git_branch}
                  paths:
${join("\n", [for path in var.manifest_paths : "                    - ${path}"])}
                  repoName: ${var.git_repo_name}
              valuesPaths:
                - k8s/values.yaml
      variables: []
EOT
}
