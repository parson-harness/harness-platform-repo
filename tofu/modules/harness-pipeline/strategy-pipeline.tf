################################################################################
# Kubernetes Strategy Choice Pipeline (Single pipeline with runtime strategy)
# Allows user to choose: blue-green, canary, or rolling at runtime
################################################################################

locals {
  # Emits a delegateSelectors YAML block when delegate_selector is set.
  # Placed at the stage level to pin ALL steps (K8sDelete, deploy, shell) to the right delegate.
  strategy_delegate_yaml = var.delegate_selector != "" ? "            delegateSelectors:\n              - ${var.delegate_selector}\n" : ""

  # Blue-Green reset:
  # - If the primary service has a harness.io/color selector → B/G re-run:
  #     preserve BOTH services and the ConfigMap. The ConfigMap is required by
  #     K8sBlueGreenStageScaleDown to locate the old color's ReplicaSet; deleting
  #     it causes the scale-down step to silently no-op and leaves old-color pods running.
  # - If no color selector → coming from canary/rolling:
  #     delete both services (wrong selector type would block K8sBlueGreenDeploy)
  #     and delete the ConfigMap (stale non-B/G release state).
  # Always delete any leftover canary deployment.
  reset_strategy_step_bg = <<-RESET_BG_EOT
                  - step:
                      type: ShellScript
                      name: Reset Strategy State
                      identifier: reset_strategy_state
                      timeout: 5m
                      spec:
                        shell: Bash
                        executionTarget: {}
                        source:
                          type: Inline
                          spec:
                            script: |
                              #!/bin/bash
                              NAMESPACE="<+infra.namespace>"
                              RELEASE="<+infra.releaseName>"
                              SVC="<+service.name.replace(" ", "").toLowerCase()>"
                              echo "Resetting B/G strategy state: svc=$${SVC} release=$${RELEASE} namespace=$${NAMESPACE}"
                              COLOR=$(kubectl get service "$${SVC}-service" -n "$${NAMESPACE}" -o jsonpath='{.spec.selector.harness\.io/color}' 2>/dev/null)
                              if [ -z "$${COLOR}" ]; then
                                echo "No B/G color selector — removing non-B/G resources for fresh B/G setup"
                                kubectl delete service "$${SVC}-service" -n "$${NAMESPACE}" --ignore-not-found=true
                                kubectl delete service "$${SVC}-service-stage" -n "$${NAMESPACE}" --ignore-not-found=true
                                kubectl delete configmap "$${RELEASE}" -n "$${NAMESPACE}" --ignore-not-found=true
                                kubectl delete deployment "$${SVC}-deployment" -n "$${NAMESPACE}" --ignore-not-found=true
                              else
                                echo "B/G services exist (color=$${COLOR}) — preserving services and ConfigMap for zero-downtime re-run"
                              fi
                              kubectl delete deployment "$${SVC}-deployment-canary" -n "$${NAMESPACE}" --ignore-not-found=true
                              echo "Done."
                        environmentVariables: []
                        outputVariables: []
  RESET_BG_EOT

  # Canary/Rolling reset:
  # - Do NOT delete the primary service — K8sCanaryDeploy and K8sRollingDeploy apply it
  #   in-place via manifest, updating selectors without a delete/recreate cycle. Deleting
  #   it here causes a 503 window while the deploy step runs.
  # - Delete service-stage: leftover from a prior B/G run, not used by canary/rolling.
  # - Delete the canary deployment: cleanup in case a previous canary was aborted mid-run.
  # - Delete the ConfigMap: resets Harness release tracking to a clean state for the new strategy.
  reset_strategy_step = <<-RESET_EOT
                  - step:
                      type: ShellScript
                      name: Reset Strategy State
                      identifier: reset_strategy_state
                      timeout: 5m
                      spec:
                        shell: Bash
                        executionTarget: {}
                        source:
                          type: Inline
                          spec:
                            script: |
                              #!/bin/bash
                              NAMESPACE="<+infra.namespace>"
                              RELEASE="<+infra.releaseName>"
                              SVC="<+service.name.replace(" ", "").toLowerCase()>"
                              echo "Resetting strategy state: svc=$${SVC} release=$${RELEASE} namespace=$${NAMESPACE}"
                              kubectl delete deployment "$${SVC}-deployment-canary" -n "$${NAMESPACE}" --ignore-not-found=true
                              kubectl delete deployment "$${SVC}-deployment-blue" -n "$${NAMESPACE}" --ignore-not-found=true
                              kubectl delete deployment "$${SVC}-deployment-green" -n "$${NAMESPACE}" --ignore-not-found=true
                              kubectl delete service "$${SVC}-service-stage" -n "$${NAMESPACE}" --ignore-not-found=true
                              kubectl delete configmap "$${RELEASE}" -n "$${NAMESPACE}" --ignore-not-found=true
                              echo "Done."
                        environmentVariables: []
                        outputVariables: []
  RESET_EOT
}

resource "harness_platform_pipeline" "k8s_strategy" {
  count       = var.create_strategy_pipeline ? 1 : 0
  identifier  = var.strategy_pipeline_id
  name        = var.strategy_pipeline_name
  org_id      = var.org_id
  project_id  = var.project_id
  description = var.strategy_pipeline_description
  tags        = ["deployment-type:kubernetes", "strategy:multi-strategy"]

  yaml = <<-STRATEGY_EOT
    pipeline:
      name: ${var.strategy_pipeline_name}
      identifier: ${var.strategy_pipeline_id}
      projectIdentifier: ${var.project_id}
      orgIdentifier: ${var.org_id}
      description: ${var.strategy_pipeline_description}
      tags:
        deployment-type: kubernetes
        strategy: multi-strategy
      variables:
        - name: deployment_strategy
          type: String
          description: Deployment strategy to use
          required: true
          value: <+input>.allowedValues(blue-green,canary,rolling)
        - name: image_tag
          type: String
          description: Docker image tag to deploy
          required: true
          value: <+input>
      stages:
        - stage:
            name: Blue-Green Deployment
            identifier: blue_green
            description: Blue-Green deployment with instant traffic swap
            type: Deployment
            when:
              pipelineStatus: Success
              condition: <+pipeline.variables.deployment_strategy> == "blue-green"
${local.strategy_delegate_yaml}            spec:
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
${local.reset_strategy_step_bg}                  - step:
                      type: ShellScript
                      name: Print Variables
                      identifier: print_variables
                      spec:
                        shell: Bash
                        executionTarget: {}
                        source:
                          type: Inline
                          spec:
                            script: |
                              echo "========================================"
                              echo "  HARNESS PIPELINE VARIABLES"
                              echo "========================================"
                              echo "Pipeline: <+pipeline.name> | Execution: <+pipeline.executionId>"
                              echo "Stage: <+stage.name> | Service: <+service.name>"
                              echo "Environment: <+env.name> (<+env.type>)"
                              echo "Infrastructure: <+infra.name> | Namespace: <+infra.namespace>"
                              echo "Artifact: <+artifacts.primary.image>"
                              echo "Strategy: <+pipeline.variables.deployment_strategy>"
                              echo "Primary URL: https://<+serviceVariables.ingressHost>"
                              echo "Stage URL:   https://<+serviceVariables.ingressStageHost>"
                              echo "========================================"
                        environmentVariables: []
                        outputVariables: []
                      timeout: 10m
                  - step:
                      name: Stage Deployment
                      identifier: stage_deployment
                      type: K8sBlueGreenDeploy
                      timeout: 10m
                      spec:
                        skipDryRun: false
                  - step:
                      name: Approval
                      identifier: bg_approval
                      type: HarnessApproval
                      timeout: 1d
                      spec:
                        approvalMessage: |
                          Blue/Green deployment staged successfully.

                          Validate the new version on the Stage environment:
                            Stage URL:   https://<+serviceVariables.ingressStageHost>

                          Current production traffic continues to:
                            Primary URL: https://<+serviceVariables.ingressHost>

                          Approve to swap traffic to the new version. Reject to abort.
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
                  - step:
                      name: Scale Down Old Version
                      identifier: scale_down_old
                      type: K8sBlueGreenStageScaleDown
                      timeout: 10m
                      spec: {}
                  - step:
                      type: ShellScript
                      name: Deployment Complete
                      identifier: deployment_complete
                      spec:
                        shell: Bash
                        executionTarget: {}
                        source:
                          type: Inline
                          spec:
                            script: |
                              echo "========================================"
                              echo "  BLUE-GREEN DEPLOYMENT COMPLETE"
                              echo "========================================"
                              echo ""
                              echo "Production URL: https://<+serviceVariables.ingressHost>"
                              echo "Stage URL:      https://<+serviceVariables.ingressStageHost>"
                              echo ""
                              echo "Traffic has been swapped to the new version."
                              echo "The old version has been scaled down."
                              echo "========================================"
                        environmentVariables: []
                        outputVariables: []
                      timeout: 1m
                rollbackSteps: []
            failureStrategies:
              - onFailure:
                  errors:
                    - AllErrors
                  action:
                    type: StageRollback
        - stage:
            name: Canary Deployment
            identifier: canary
            description: Canary deployment with gradual traffic shift
            type: Deployment
            when:
              pipelineStatus: Success
              condition: <+pipeline.variables.deployment_strategy> == "canary"
${local.strategy_delegate_yaml}            spec:
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
${local.reset_strategy_step}                  - step:
                      type: ShellScript
                      name: Print Variables
                      identifier: print_variables
                      spec:
                        shell: Bash
                        executionTarget: {}
                        source:
                          type: Inline
                          spec:
                            script: |
                              echo "========================================"
                              echo "  HARNESS PIPELINE VARIABLES"
                              echo "========================================"
                              echo "Pipeline: <+pipeline.name> | Execution: <+pipeline.executionId>"
                              echo "Stage: <+stage.name> | Service: <+service.name>"
                              echo "Environment: <+env.name> (<+env.type>)"
                              echo "Infrastructure: <+infra.name> | Namespace: <+infra.namespace>"
                              echo "Artifact: <+artifacts.primary.image>"
                              echo "Strategy: <+pipeline.variables.deployment_strategy>"
                              echo "App URL: https://<+serviceVariables.ingressHost>"
                              echo "========================================"
                        environmentVariables: []
                        outputVariables: []
                      timeout: 10m
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
                      type: ShellScript
                      name: Get Canary Traffic Split
                      identifier: get_validation_urls
                      spec:
                        shell: Bash
                        executionTarget: {}
                        source:
                          type: Inline
                          spec:
                            script: |
                              #!/bin/bash
                              NAMESPACE="<+infra.namespace>"
                              CANARY_PODS=$(kubectl get pods -n $NAMESPACE -l harness.io/track=canary --no-headers 2>/dev/null | wc -l | tr -d ' ')
                              STABLE_PODS=$(kubectl get pods -n $NAMESPACE -l harness.io/track=stable --no-headers 2>/dev/null | wc -l | tr -d ' ')
                              TOTAL=$((CANARY_PODS + STABLE_PODS))
                              if [ $TOTAL -gt 0 ]; then
                                CANARY_PCT=$((CANARY_PODS * 100 / TOTAL))
                                STABLE_PCT=$((STABLE_PODS * 100 / TOTAL))
                              else
                                CANARY_PCT=0
                                STABLE_PCT=100
                              fi
                              echo "App URL: https://<+serviceVariables.ingressHost>"
                              echo "Traffic: ~$${CANARY_PCT}% canary ($${CANARY_PODS} pods), ~$${STABLE_PCT}% stable ($${STABLE_PODS} pods)"
                        environmentVariables: []
                        outputVariables:
                          - name: CANARY_PCT
                            type: String
                            value: CANARY_PCT
                          - name: STABLE_PCT
                            type: String
                            value: STABLE_PCT
                      timeout: 10m
                  - step:
                      name: Approval
                      identifier: canary_approval
                      type: HarnessApproval
                      timeout: 1d
                      spec:
                        approvalMessage: |
                          Canary deployment complete.

                          App URL: https://<+serviceVariables.ingressHost>
                          Traffic split: ~<+execution.steps.get_validation_urls.output.outputVariables.CANARY_PCT>% canary, ~<+execution.steps.get_validation_urls.output.outputVariables.STABLE_PCT>% stable

                          Approve to promote canary to 100% of pods. Reject to roll back.
                        includePipelineExecutionHistory: true
                        approvers:
                          userGroups:
                            - _project_all_users
                          minimumCount: 1
                          disallowPipelineExecutor: false
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
                  - step:
                      type: ShellScript
                      name: Deployment Complete
                      identifier: deployment_complete
                      spec:
                        shell: Bash
                        executionTarget: {}
                        source:
                          type: Inline
                          spec:
                            script: |
                              echo "========================================"
                              echo "  CANARY DEPLOYMENT COMPLETE"
                              echo "========================================"
                              echo ""
                              echo "App URL: https://<+serviceVariables.ingressHost>"
                              echo ""
                              echo "Canary validated and promoted to 100%."
                              echo "All pods now running the new version."
                              echo "========================================"
                        environmentVariables: []
                        outputVariables: []
                      timeout: 1m
                rollbackSteps:
                  - step:
                      name: Canary Delete
                      identifier: strategy_rollback_canary_delete
                      type: K8sCanaryDelete
                      timeout: 10m
                      spec: {}
            failureStrategies:
              - onFailure:
                  errors:
                    - AllErrors
                  action:
                    type: StageRollback
        - stage:
            name: Rolling Deployment
            identifier: rolling
            description: Standard rolling update deployment
            type: Deployment
            when:
              pipelineStatus: Success
              condition: <+pipeline.variables.deployment_strategy> == "rolling"
${local.strategy_delegate_yaml}            spec:
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
${local.reset_strategy_step}                  - step:
                      type: ShellScript
                      name: Print Variables
                      identifier: print_variables
                      spec:
                        shell: Bash
                        executionTarget: {}
                        source:
                          type: Inline
                          spec:
                            script: |
                              echo "========================================"
                              echo "  HARNESS PIPELINE VARIABLES"
                              echo "========================================"
                              echo "Pipeline: <+pipeline.name> | Execution: <+pipeline.executionId>"
                              echo "Stage: <+stage.name> | Service: <+service.name>"
                              echo "Environment: <+env.name> (<+env.type>)"
                              echo "Infrastructure: <+infra.name> | Namespace: <+infra.namespace>"
                              echo "Artifact: <+artifacts.primary.image>"
                              echo "Strategy: <+pipeline.variables.deployment_strategy>"
                              echo "App URL: https://<+serviceVariables.ingressHost>"
                              echo "========================================"
                        environmentVariables: []
                        outputVariables: []
                      timeout: 10m
                  - step:
                      name: Rolling Deployment
                      identifier: rolling_deploy
                      type: K8sRollingDeploy
                      timeout: 10m
                      spec:
                        skipDryRun: false
                  - step:
                      type: ShellScript
                      name: Deployment Complete
                      identifier: get_validation_urls
                      spec:
                        shell: Bash
                        executionTarget: {}
                        source:
                          type: Inline
                          spec:
                            script: |
                              echo "========================================"
                              echo "  ROLLING DEPLOYMENT COMPLETE"
                              echo "App URL: https://<+serviceVariables.ingressHost>"
                              echo "========================================"
                        environmentVariables: []
                        outputVariables: []
                      timeout: 10m
                rollbackSteps:
                  - step:
                      name: Rolling Rollback
                      identifier: strategy_rolling_rollback
                      type: K8sRollingRollback
                      timeout: 10m
                      spec: {}
            failureStrategies:
              - onFailure:
                  errors:
                    - AllErrors
                  action:
                    type: StageRollback
  STRATEGY_EOT
}
