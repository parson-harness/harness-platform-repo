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
# Kubernetes Canary Pipeline
################################################################################

resource "harness_platform_pipeline" "k8s_canary" {
  count       = var.create_canary_pipeline ? 1 : 0
  identifier  = var.canary_pipeline_id
  name        = var.canary_pipeline_name
  org_id      = var.org_id
  project_id  = var.project_id
  description = var.canary_pipeline_description
  tags        = ["deployment-type:kubernetes", "strategy:canary"]

  yaml = <<-EOT
    pipeline:
      name: ${var.canary_pipeline_name}
      identifier: ${var.canary_pipeline_id}
      projectIdentifier: ${var.project_id}
      orgIdentifier: ${var.org_id}
      description: ${var.canary_pipeline_description}
      tags:
        deployment-type: kubernetes
        strategy: canary
      stages:
        - stage:
            name: Deploy to ${var.environment_name}
            identifier: deploy_to_${replace(lower(var.environment_name), " ", "_")}
            description: Canary deployment to Kubernetes
            type: Deployment
            spec:
              deploymentType: Kubernetes
              service:
                serviceRef: ${var.service_ref}
                serviceInputs:
                  serviceDefinition:
                    type: Kubernetes
                    spec:
                      artifacts:
                        primary:
                          primaryArtifactRef: <+input>
                          sources: <+input>
              environment:
                environmentRef: ${var.environment_ref}
                deployToAll: false
                infrastructureDefinitions:
                  - identifier: ${var.infrastructure_ref}
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
                            name: Approval
                            identifier: approval
                            type: HarnessApproval
                            timeout: 1d
                            spec:
                              approvalMessage: |
                                Canary deployment complete.
                                Review metrics and logs before proceeding to full rollout.
                                Approve to deploy to all instances.
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

################################################################################
# Kubernetes Blue/Green Pipeline
################################################################################

resource "harness_platform_pipeline" "k8s_blue_green" {
  count       = var.create_blue_green_pipeline ? 1 : 0
  identifier  = var.blue_green_pipeline_id
  name        = var.blue_green_pipeline_name
  org_id      = var.org_id
  project_id  = var.project_id
  description = var.blue_green_pipeline_description
  tags        = ["deployment-type:kubernetes", "strategy:blue-green"]

  yaml = <<-EOT
    pipeline:
      name: ${var.blue_green_pipeline_name}
      identifier: ${var.blue_green_pipeline_id}
      projectIdentifier: ${var.project_id}
      orgIdentifier: ${var.org_id}
      description: ${var.blue_green_pipeline_description}
      tags:
        deployment-type: kubernetes
        strategy: blue-green
      stages:
        - stage:
            name: Deploy to ${var.environment_name}
            identifier: deploy_to_${replace(lower(var.environment_name), " ", "_")}
            description: Blue/Green deployment to Kubernetes
            type: Deployment
            spec:
              deploymentType: Kubernetes
              service:
                serviceRef: ${var.service_ref}
                serviceInputs:
                  serviceDefinition:
                    type: Kubernetes
                    spec:
                      artifacts:
                        primary:
                          primaryArtifactRef: <+input>
                          sources: <+input>
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
                      identifier: approval
                      type: HarnessApproval
                      timeout: 1d
                      spec:
                        approvalMessage: |
                          Blue/Green deployment complete. Stage environment is running.
                          Review metrics and logs before swapping to production.
                          Approve to shift all traffic to new version.
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
                rollbackSteps:
                  - step:
                      name: Swap Rollback
                      identifier: swap_rollback
                      type: K8sBlueGreenRollback
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
