################################################################################
# Kubernetes Strategy Choice Pipeline (Single pipeline with runtime strategy)
# Allows user to choose: blue-green, canary, or rolling at runtime
################################################################################

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
                      type: ShellScript
                      name: Get Validation URLs
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
                              echo "========================================"
                              echo "  BLUE/GREEN VALIDATION"
                              echo "========================================"
                              # Wait for ingress to get ALB hostname (retry up to 30s)
                              for i in 1 2 3 4 5 6; do
                                INGRESS_HOST=$(kubectl get ingress -n $NAMESPACE -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
                                if [ -n "$INGRESS_HOST" ]; then break; fi
                                echo "Waiting for ingress hostname... (attempt $i)"
                                sleep 5
                              done
                              if [ -n "$INGRESS_HOST" ]; then
                                PRIMARY_URL="http://$${INGRESS_HOST}"
                                STAGE_URL="http://$${INGRESS_HOST}?stage=true"
                                echo "Primary URL: $PRIMARY_URL"
                                echo "Stage URL: $STAGE_URL"
                              else
                                PRIMARY_URL="URL_NOT_FOUND"
                                STAGE_URL="URL_NOT_FOUND"
                                echo "Could not find ingress hostname after retries"
                                kubectl get ingress -n $NAMESPACE -o wide
                              fi
                              echo "========================================"
                        environmentVariables: []
                        outputVariables:
                          - name: PRIMARY_URL
                            type: String
                            value: PRIMARY_URL
                          - name: STAGE_URL
                            type: String
                            value: STAGE_URL
                      timeout: 10m
                  - step:
                      name: Approval
                      identifier: bg_approval
                      type: HarnessApproval
                      timeout: 1d
                      spec:
                        approvalMessage: |
                          Blue/Green deployment complete. New version staged.
                          Primary: <+execution.steps.get_validation_urls.output.outputVariables.PRIMARY_URL>
                          Stage: <+execution.steps.get_validation_urls.output.outputVariables.STAGE_URL>
                          Approve to swap traffic to the new version.
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
                      name: Get Validation URLs
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
                              echo "========================================"
                              echo "  CANARY VALIDATION"
                              echo "========================================"
                              # Wait for ingress to get ALB hostname (retry up to 30s)
                              for i in 1 2 3 4 5 6; do
                                INGRESS_HOST=$(kubectl get ingress -n $NAMESPACE -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
                                if [ -n "$INGRESS_HOST" ]; then break; fi
                                echo "Waiting for ingress hostname... (attempt $i)"
                                sleep 5
                              done
                              CANARY_PODS=$(kubectl get pods -n $NAMESPACE -l harness.io/track=canary --no-headers 2>/dev/null | wc -l | tr -d ' ')
                              STABLE_PODS=$(kubectl get pods -n $NAMESPACE -l harness.io/track=stable --no-headers 2>/dev/null | wc -l | tr -d ' ')
                              TOTAL=$((CANARY_PODS + STABLE_PODS))
                              if [ $TOTAL -gt 0 ]; then CANARY_PCT=$((CANARY_PODS * 100 / TOTAL)); STABLE_PCT=$((STABLE_PODS * 100 / TOTAL)); else CANARY_PCT=0; STABLE_PCT=100; fi
                              if [ -n "$INGRESS_HOST" ]; then APP_URL="http://$${INGRESS_HOST}"; echo "URL: $APP_URL"; else APP_URL="URL_NOT_FOUND"; fi
                              echo "Traffic: ~$${CANARY_PCT}% canary, ~$${STABLE_PCT}% stable"
                              echo "========================================"
                        environmentVariables: []
                        outputVariables:
                          - name: APP_URL
                            type: String
                            value: APP_URL
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
                          URL: <+execution.steps.get_validation_urls.output.outputVariables.APP_URL>
                          Traffic: ~<+execution.steps.get_validation_urls.output.outputVariables.CANARY_PCT>% canary
                          Approve to promote canary to all pods.
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
                      name: Get Validation URLs
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
                              SERVICE_NAME="<+service.name>"
                              echo "========================================"
                              echo "  ROLLING DEPLOYMENT COMPLETE"
                              echo "========================================"
                              INGRESS_HOST=$(kubectl get ingress -n $NAMESPACE -o json | jq -r ".items[] | select(.metadata.name | contains(\"$${SERVICE_NAME}\")) | .status.loadBalancer.ingress[0].hostname // empty" | head -1)
                              if [ -z "$INGRESS_HOST" ]; then
                                INGRESS_HOST=$(kubectl get ingress -n $NAMESPACE -o json | jq -r '.items[] | select(.metadata.annotations["alb.ingress.kubernetes.io/group.name"] != null) | .status.loadBalancer.ingress[0].hostname // empty' | head -1)
                              fi
                              if [ -n "$INGRESS_HOST" ]; then APP_URL="http://$${INGRESS_HOST}"; echo "URL: $APP_URL"; else APP_URL="URL_NOT_FOUND"; fi
                              echo "All pods updated."
                              echo "========================================"
                        environmentVariables: []
                        outputVariables:
                          - name: APP_URL
                            type: String
                            value: APP_URL
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
