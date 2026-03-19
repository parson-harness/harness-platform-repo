################################################################################
# Pipeline Triggers
# Custom webhook trigger on CD pipeline, called from CI pipeline on success
################################################################################

resource "harness_platform_triggers" "cd_webhook_trigger" {
  count       = var.create_ci_completion_trigger && var.create_ci_pipeline && var.create_canary_pipeline ? 1 : 0
  identifier  = "auto_deploy_webhook"
  name        = "Auto-Deploy Webhook"
  org_id      = var.org_id
  project_id  = var.project_id
  target_id   = harness_platform_pipeline.k8s_canary[0].identifier
  description = "Custom webhook trigger for auto-deployment from CI pipeline"
  tags        = ["trigger-type:webhook", "auto-deploy:true"]

  # Explicit dependency to ensure pipeline is fully created before trigger
  depends_on = [harness_platform_pipeline.k8s_canary]

  yaml = <<-TRIGGER_EOT
    trigger:
      name: Auto-Deploy Webhook
      identifier: auto_deploy_webhook
      enabled: ${var.ci_completion_trigger_enabled}
      description: Custom webhook trigger for auto-deployment from CI pipeline
      tags:
        trigger-type: webhook
        auto-deploy: "true"
      orgIdentifier: ${var.org_id}
      projectIdentifier: ${var.project_id}
      pipelineIdentifier: ${harness_platform_pipeline.k8s_canary[0].identifier}
      source:
        type: Webhook
        spec:
          type: Custom
          spec:
            payloadConditions: []
            headerConditions: []
      inputYaml: |
        pipeline:
          identifier: ${harness_platform_pipeline.k8s_canary[0].identifier}
          variables:
            - name: image_tag
              type: String
              value: <+trigger.payload.image_tag>
  TRIGGER_EOT
}
