################################################################################
# Harness CD Pipeline Module
# Creates deployment pipelines (Canary, Blue/Green)
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
# Kubernetes Canary Pipeline (DEPRECATED)
# Use the Strategy Choice pipeline with deployment_strategy=canary instead.
# This resource is kept for backward compatibility but create_canary_pipeline
# should be set to false for new deployments.
################################################################################

resource "harness_platform_pipeline" "k8s_canary" {
  count       = var.create_canary_pipeline ? 1 : 0
  identifier  = var.canary_pipeline_id
  name        = "${var.canary_pipeline_name} - Deprecated"
  org_id      = var.org_id
  project_id  = var.project_id
  description = "DEPRECATED: Use ${var.strategy_pipeline_id} with deployment_strategy=canary instead. ${var.canary_pipeline_description}"
  tags        = ["deployment-type:kubernetes", "strategy:canary", "deprecated:true", "managed-by:provisioner"]

  yaml = <<-EOT
    pipeline:
      name: ${var.canary_pipeline_name} - Deprecated
      identifier: ${var.canary_pipeline_id}
      projectIdentifier: ${var.project_id}
      orgIdentifier: ${var.org_id}
      description: "DEPRECATED: Use ${var.strategy_pipeline_id} with deployment_strategy=canary instead. ${var.canary_pipeline_description}"
      tags:
        deployment-type: kubernetes
        strategy: canary
        deprecated: "true"
        managed-by: provisioner
      variables:
        - name: image_tag
          type: String
          description: Docker image tag to deploy
          required: true
          value: <+input>
      stages:
        - stage:
            name: Redirect to Strategy Pipeline
            identifier: redirect_notice
            description: This pipeline is deprecated
            type: Custom
            spec:
              execution:
                steps:
                  - step:
                      type: ShellScript
                      name: Deprecation Notice
                      identifier: deprecation_notice
                      spec:
                        shell: Bash
                        executionTarget: {}
                        source:
                          type: Inline
                          spec:
                            script: |
                              echo "========================================"
                              echo "  THIS PIPELINE IS DEPRECATED"
                              echo "========================================"
                              echo ""
                              echo "Please use the Strategy Choice pipeline instead:"
                              echo "  Pipeline: ${var.strategy_pipeline_id}"
                              echo "  Set deployment_strategy = canary"
                              echo ""
                              echo "The Strategy Choice pipeline includes:"
                              echo "  - Reset strategy state (handles B/G leftovers)"
                              echo "  - Traffic split calculation"
                              echo "  - Enhanced approval messages"
                              echo "  - Deployment complete summary"
                              echo "========================================"
                              exit 1
                        environmentVariables: []
                        outputVariables: []
                      timeout: 1m
  EOT
}

################################################################################
# Kubernetes Blue/Green + Canary Pipeline (2-stage)
# Stage 1: Blue/Green deployment to Dev environment
# Stage 2: Canary deployment to Prod environment
################################################################################

resource "harness_platform_pipeline" "k8s_blue_green_canary" {
  count       = var.create_blue_green_pipeline ? 1 : 0
  identifier  = var.blue_green_pipeline_id
  name        = var.blue_green_pipeline_name
  org_id      = var.org_id
  project_id  = var.project_id
  description = var.blue_green_pipeline_description
  tags        = ["deployment-type:kubernetes", "strategy:blue-green-canary", "managed-by:provisioner"]

  yaml = <<-EOT
    pipeline:
      name: ${var.blue_green_pipeline_name}
      identifier: ${var.blue_green_pipeline_id}
      projectIdentifier: ${var.project_id}
      orgIdentifier: ${var.org_id}
      description: ${var.blue_green_pipeline_description}
      tags:
        deployment-type: kubernetes
        strategy: blue-green-canary
        managed-by: provisioner
      variables:
        - name: image_tag
          type: String
          description: Docker image tag to deploy
          required: true
          value: <+input>
      stages:
        - stage:
            name: BlueGreen to Dev
            identifier: blue_green_dev
            description: Blue-Green deployment to Dev environment
            type: Deployment
            spec:
              deploymentType: Kubernetes
              service:
                serviceRef: ${var.service_ref}
              environment:
                environmentRef: ${var.environment_ref}
                deployToAll: false
                infrastructureDefinitions:
                  - identifier: ${var.infrastructure_ref}
              execution:
                steps:
                  - step:
                      name: Stage Deployment
                      identifier: stage_deployment
                      type: K8sBlueGreenDeploy
                      timeout: 10m
                      spec:
                        skipDryRun: false
                  - step:
                      name: Approval
                      identifier: dev_approval
                      type: HarnessApproval
                      timeout: 1d
                      spec:
                        approvalMessage: |
                          Blue/Green deployment to Dev complete.
                          Stage environment is running the new version.
                          Review metrics and logs before swapping traffic.
                          Approve to shift all Dev traffic to new version.
                        includePipelineExecutionHistory: true
                        approvers:
                          userGroups:
                            - _project_all_users
                          minimumCount: 1
                          disallowPipelineExecutor: false
                  - step:
                      name: Swap Primary
                      identifier: swap_primary
                      type: K8sBGSwapServices
                      timeout: 10m
                      spec:
                        skipDryRun: false
                rollbackSteps: []
            failureStrategies:
              - onFailure:
                  errors:
                    - AllErrors
                  action:
                    type: StageRollback
        - stage:
            name: Canary to Prod
            identifier: canary_prod
            description: Canary deployment to Prod environment
            type: Deployment
            spec:
              deploymentType: Kubernetes
              service:
                serviceRef: ${var.service_ref}
              environment:
                environmentRef: ${var.prod_environment_ref}
                deployToAll: false
                infrastructureDefinitions:
                  - identifier: ${var.prod_infrastructure_ref}
              execution:
                steps:
                  - stepGroup:
                      name: Canary Deployment
                      identifier: canary_deployment
                      steps:
                        - step:
                            name: Canary Deployment
                            identifier: canary_deploy
                            type: K8sCanaryDeploy
                            timeout: 10m
                            spec:
                              instanceSelection:
                                type: Count
                                spec:
                                  count: ${var.canary_instance_count}
                              skipDryRun: false
                        - step:
                            name: Prod Approval
                            identifier: prod_approval
                            type: HarnessApproval
                            timeout: 1d
                            spec:
                              approvalMessage: |
                                Canary deployment to Prod complete.
                                ${var.canary_instance_count} canary instance(s) running.
                                Review metrics and logs before full rollout.
                                Approve to deploy to all Prod instances.
                              includePipelineExecutionHistory: true
                              approvers:
                                userGroups:
                                  - _project_all_users
                                minimumCount: 1
                                disallowPipelineExecutor: false
                  - stepGroup:
                      name: Primary Deployment
                      identifier: primary_deployment
                      steps:
                        - step:
                            name: Canary Delete
                            identifier: canary_delete
                            type: K8sCanaryDelete
                            timeout: 10m
                            spec: {}
                        - step:
                            name: Rolling Deployment
                            identifier: rolling_deploy
                            type: K8sRollingDeploy
                            timeout: 10m
                            spec:
                              skipDryRun: false
                rollbackSteps:
                  - step:
                      name: Canary Delete
                      identifier: rollback_canary_delete
                      type: K8sCanaryDelete
                      timeout: 10m
                      spec: {}
                  - step:
                      name: Rolling Rollback
                      identifier: rolling_rollback
                      type: K8sRollingRollback
                      timeout: 10m
                      spec: {}
            failureStrategies:
              - onFailure:
                  errors:
                    - AllErrors
                  action:
                    type: StageRollback
  EOT
}
