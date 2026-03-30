################################################################################
# Pipeline Triggers
# Custom webhook trigger on Strategy pipeline, called from CI pipeline on success
# Uses canary deployment strategy by default for auto-deploy
################################################################################

resource "harness_platform_triggers" "cd_webhook_trigger" {
  count       = var.create_ci_completion_trigger && var.create_ci_pipeline && var.create_strategy_pipeline ? 1 : 0
  identifier  = "auto_deploy_webhook"
  name        = "Auto-Deploy Webhook"
  org_id      = var.org_id
  project_id  = var.project_id
  target_id   = harness_platform_pipeline.k8s_strategy[0].identifier
  description = "Custom webhook trigger for auto-deployment from CI pipeline (uses canary strategy)"
  tags        = ["trigger-type:webhook", "auto-deploy:true"]

  # Explicit dependency to ensure pipeline is fully created before trigger
  depends_on = [harness_platform_pipeline.k8s_strategy]

  yaml = <<-TRIGGER_EOT
    trigger:
      name: Auto-Deploy Webhook
      identifier: auto_deploy_webhook
      enabled: ${var.ci_completion_trigger_enabled}
      description: Custom webhook trigger for auto-deployment from CI pipeline (uses canary strategy)
      tags:
        trigger-type: webhook
        auto-deploy: "true"
      orgIdentifier: ${var.org_id}
      projectIdentifier: ${var.project_id}
      pipelineIdentifier: ${harness_platform_pipeline.k8s_strategy[0].identifier}
      source:
        type: Webhook
        spec:
          type: Custom
          spec:
            payloadConditions: []
            headerConditions: []
      inputYaml: |
        pipeline:
          identifier: ${harness_platform_pipeline.k8s_strategy[0].identifier}
          variables:
            - name: deployment_strategy
              type: String
              value: canary
            - name: image_tag
              type: String
              value: <+trigger.payload.image_tag>
  TRIGGER_EOT
}

resource "harness_platform_triggers" "asg_cd_webhook_trigger" {
  count       = var.create_ci_completion_trigger && var.create_asg_ci_pipeline && var.create_asg_strategy_pipeline ? 1 : 0
  identifier  = "asg_auto_deploy_webhook"
  name        = "ASG Auto-Deploy Webhook"
  org_id      = var.org_id
  project_id  = var.project_id
  target_id   = harness_platform_pipeline.asg_strategy[0].identifier
  description = "Custom webhook trigger for auto-deployment from ASG CI pipeline (uses rolling strategy)"
  tags        = ["trigger-type:webhook", "auto-deploy:true", "deployment:asg"]

  depends_on = [harness_platform_pipeline.asg_strategy]

  yaml = <<-TRIGGER_EOT
    trigger:
      name: ASG Auto-Deploy Webhook
      identifier: asg_auto_deploy_webhook
      enabled: ${var.ci_completion_trigger_enabled}
      description: Custom webhook trigger for auto-deployment from ASG CI pipeline (uses rolling strategy)
      tags:
        trigger-type: webhook
        auto-deploy: "true"
        deployment: asg
      orgIdentifier: ${var.org_id}
      projectIdentifier: ${var.project_id}
      pipelineIdentifier: ${harness_platform_pipeline.asg_strategy[0].identifier}
      source:
        type: Webhook
        spec:
          type: Custom
          spec:
            payloadConditions: []
            headerConditions: []
      inputYaml: |
        pipeline:
          identifier: ${harness_platform_pipeline.asg_strategy[0].identifier}
          variables:
            - name: deployment_strategy
              type: String
              value: rolling
            - name: image_tag
              type: String
              value: <+trigger.payload.image_tag>
  TRIGGER_EOT
}

################################################################################
# HAR Artifact Trigger for Rolling Deployment
# Triggers CD pipeline with Rolling strategy when new artifact is pushed to HAR
# This enables automatic first deployment after CI completes
#
# NOTE: DISABLED - The "Har" artifact type is not yet supported in the Harness
# triggers API. Supported types: GithubPackageRegistry, ArtifactoryRegistry,
# CustomArtifact, AmazonS3, GoogleArtifactRegistry, Acr, Nexus3Registry,
# AzureArtifacts, Ecr, Jenkins, AmazonMachineImage, DockerRegistry,
# GoogleCloudStorage, Nexus2Registry, GceImage, Bamboo, Gcr
#
# TODO: Re-enable when HAR artifact triggers are supported
################################################################################

resource "harness_platform_triggers" "har_artifact_trigger" {
  # DISABLED: Har artifact type not supported in triggers API yet
  count       = false && var.create_har_artifact_trigger && var.create_strategy_pipeline && var.har_registry_ref != "" ? 1 : 0
  identifier  = "har_artifact_rolling_deploy"
  name        = "HAR Artifact - Rolling Deploy"
  org_id      = var.org_id
  project_id  = var.project_id
  target_id   = harness_platform_pipeline.k8s_strategy[0].identifier
  description = "Triggers Rolling deployment when new artifact is pushed to HAR registry"
  tags        = ["trigger-type:artifact", "auto-deploy:true", "strategy:rolling"]

  depends_on = [harness_platform_pipeline.k8s_strategy]

  yaml = <<-TRIGGER_EOT
    trigger:
      name: HAR Artifact - Rolling Deploy
      identifier: har_artifact_rolling_deploy
      enabled: ${var.har_artifact_trigger_enabled}
      description: Triggers Rolling deployment when new artifact is pushed to HAR registry
      tags:
        trigger-type: artifact
        auto-deploy: "true"
        strategy: rolling
      orgIdentifier: ${var.org_id}
      projectIdentifier: ${var.project_id}
      pipelineIdentifier: ${harness_platform_pipeline.k8s_strategy[0].identifier}
      source:
        type: Artifact
        spec:
          type: Har
          spec:
            connectorRef: account.Harness_Artifact_Registry
            registryRef: ${var.har_registry_ref}
            imagePath: ${var.har_image_name}
            tag: <+trigger.artifact.build>
            eventConditions: []
      inputYaml: |
        pipeline:
          identifier: ${harness_platform_pipeline.k8s_strategy[0].identifier}
          variables:
            - name: deployment_strategy
              type: String
              value: rolling
            - name: image_tag
              type: String
              value: <+trigger.artifact.build>
  TRIGGER_EOT
}
