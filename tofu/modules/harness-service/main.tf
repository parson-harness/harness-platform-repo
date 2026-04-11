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

  yaml = var.deployment_type == "Asg" ? local.asg_service_yaml : (
    var.artifact_registry_type == "har" ? local.har_service_yaml : local.ecr_service_yaml
  )

  depends_on = [
    harness_platform_file_store_folder.asg_startup_script,
    harness_platform_file_store_file.asg_startup_script
  ]
}

resource "harness_platform_file_store_folder" "asg_startup_script" {
  count = var.deployment_type == "Asg" && var.asg_startup_script_use_file_store ? 1 : 0

  identifier        = local.asg_file_store_folder_identifier
  name              = local.asg_file_store_folder_name
  description       = "ASG service files"
  org_id            = var.org_id
  project_id        = var.project_id
  parent_identifier = "Root"
}

resource "harness_platform_file_store_file" "asg_startup_script" {
  count = var.deployment_type == "Asg" && var.asg_startup_script_use_file_store ? 1 : 0

  identifier        = replace(replace(basename(var.asg_startup_script_path), ".", "_"), "-", "_")
  name              = basename(var.asg_startup_script_path)
  description       = "ASG startup script"
  org_id            = var.org_id
  project_id        = var.project_id
  parent_identifier = harness_platform_file_store_folder.asg_startup_script[0].identifier
  file_content_path = var.asg_startup_script_local_file_path
  mime_type         = "text/x-shellscript"
  file_usage        = "SCRIPT"
}

locals {
  # Tags formatted for YAML
  tags_yaml = join("\n", [for tag in var.tags : "    ${split(":", tag)[0]}: \"${try(split(":", tag)[1], "")}\""])
  tags_map  = { for tag in var.tags : split(":", tag)[0] => try(split(":", tag)[1], "") }

  # Service variables formatted for YAML
  service_vars_yaml = length(var.service_variables) == 0 ? "      variables: []" : join("\n", concat(
    ["      variables:"],
    [for v in var.service_variables : "        - name: ${v.name}\n          type: ${v.type}\n          value: \"${v.value}\""]
  ))

  # Determine repo name based on store type
  asg_file_store_folder_identifier = substr(replace("${var.service_id}_asg", "-", "_"), 0, 128)
  asg_file_store_folder_name       = local.asg_file_store_folder_identifier
  effective_repo_name              = var.manifest_store_type == "HarnessCode" ? var.harness_code_repo_name : var.git_repo_name
  effective_asg_startup_repo_name  = var.asg_startup_script_use_git ? var.asg_startup_script_git_repo_name : local.effective_repo_name
  effective_asg_startup_store_type = var.asg_startup_script_use_file_store ? "Harness" : (var.asg_startup_script_use_git ? "Github" : (var.manifest_store_type == "HarnessCode" ? "HarnessCode" : "Github"))
  asg_manifest_repo_spec = var.manifest_store_type == "HarnessCode" ? {
    repoName = local.effective_repo_name
  } : {
    connectorRef = var.git_connector_ref
    repoName     = local.effective_repo_name
  }
  asg_launch_template_store = {
    type = var.manifest_store_type == "HarnessCode" ? "HarnessCode" : "Github"
    spec = merge({
      gitFetchType = "Branch"
      branch       = var.git_branch
      paths        = [var.asg_launch_template_path]
    }, local.asg_manifest_repo_spec)
  }
  asg_config_store = {
    type = var.manifest_store_type == "HarnessCode" ? "HarnessCode" : "Github"
    spec = merge({
      gitFetchType = "Branch"
      branch       = var.git_branch
      paths        = [var.asg_config_path]
    }, local.asg_manifest_repo_spec)
  }
  asg_artifact_source = {
    identifier = "primary"
    type       = "AmazonMachineImage"
    spec = {
      connectorRef = var.artifact_connector_ref
      region       = var.aws_region
      filters = [
        {
          name  = "tag:Application"
          value = "harness-demo-app-${var.asg_ami_owner_tag}"
        }
      ]
      version = "<+pipeline.variables.ami_name>"
    }
  }
  asg_startup_script_repo_spec = var.asg_startup_script_use_file_store ? {} : (
    var.asg_startup_script_use_git ? {
      connectorRef = var.asg_startup_script_git_connector_ref
      repoName     = local.effective_asg_startup_repo_name
    } : (
      var.manifest_store_type == "HarnessCode" ? {
        repoName = local.effective_asg_startup_repo_name
      } : {
        connectorRef = var.git_connector_ref
        repoName     = local.effective_asg_startup_repo_name
      }
    )
  )
  asg_startup_script_base_spec = var.asg_startup_script_use_file_store ? {
    files = ["/${local.asg_file_store_folder_name}/${harness_platform_file_store_file.asg_startup_script[0].name}"]
  } : {
    gitFetchType = "Branch"
    branch       = var.git_branch
    paths        = [var.asg_startup_script_path]
  }
  asg_startup_script_store = {
    type = local.effective_asg_startup_store_type
    spec = merge(local.asg_startup_script_base_spec, local.asg_startup_script_repo_spec)
  }

  # Manifest store spec - different for HarnessCode vs external Git
  manifest_store_harness_code = chomp(<<-EOT
              store:
                type: HarnessCode
                spec:
                  gitFetchType: Branch
                  branch: ${var.git_branch}
                  paths:
${join("\n", [for path in var.manifest_paths : "                    - ${path}"])}
                  repoName: ${local.effective_repo_name}
EOT
  )

  manifest_store_github = chomp(<<-EOT
              store:
                type: Github
                spec:
                  connectorRef: ${var.git_connector_ref}
                  gitFetchType: Branch
                  branch: ${var.git_branch}
                  paths:
${join("\n", [for path in var.manifest_paths : "                    - ${path}"])}
                  repoName: ${local.effective_repo_name}
EOT
  )

  # Select manifest store based on type
  manifest_store_spec = var.manifest_store_type == "HarnessCode" ? local.manifest_store_harness_code : local.manifest_store_github

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
${local.manifest_store_spec}
              valuesPaths:
                - k8s/values.yaml
              skipResourceVersioning: false
              enableDeclarativeRollback: false
${local.service_vars_yaml}
EOT

  # ASG service YAML
  # Uses AmazonMachineImage artifact - Packer bakes the JAR into the AMI.
  # image_tag = full AMI name (e.g., harness-demo-app-owner-13) from CI Packer build.
  # AsgLaunchTemplate + AsgConfiguration manifests are REQUIRED by Harness for all ASG strategies.
  # startupScript provides the user-data that runs on each new instance at startup.
  asg_service_yaml = yamlencode({
    service = {
      name        = var.service_name
      identifier  = var.service_id
      description = var.service_description
      tags        = local.tags_map
      serviceDefinition = {
        type = "Asg"
        spec = {
          manifests = [
            {
              manifest = {
                identifier = "launchTemplate"
                type       = "AsgLaunchTemplate"
                spec = {
                  store = local.asg_launch_template_store
                }
              }
            },
            {
              manifest = {
                identifier = "asgConfig"
                type       = "AsgConfiguration"
                spec = {
                  store = local.asg_config_store
                }
              }
            }
          ]
          artifacts = {
            primary = {
              primaryArtifactRef = "primary"
              sources            = [local.asg_artifact_source]
            }
          }
          startupScript = {
            store = local.asg_startup_script_store
          }
          variables = var.service_variables
        }
      }
    }
  })

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
${local.manifest_store_spec}
              valuesPaths:
                - k8s/values.yaml
              skipResourceVersioning: false
              enableDeclarativeRollback: false
${local.service_vars_yaml}
EOT
}
