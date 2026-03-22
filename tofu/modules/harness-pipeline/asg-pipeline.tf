################################################################################
# Harness ASG Strategy Choice Pipeline
#
# Single pipeline with runtime strategy selection for AWS Auto Scaling Group:
#   blue-green  - Creates new (green) ASG, validates via stage listener, swaps ALB traffic
#   canary      - Creates smaller canary ASG, shifts partial traffic, promotes on approval
#   rolling     - Rolling update of the existing ASG instances
#
# Demo flow:
#   1. CI pipeline runs Packer → builds AMI → outputs AMI name (e.g., harness-demo-app-owner-42)
#   2. Run this pipeline → select strategy + enter image_tag (AMI name from CI)
#   3. Harness resolves the AmazonMachineImage artifact and creates a new Launch Template version
#   4. User-data writes env vars and starts the pre-installed systemd service
#   5. For B/G: validate on <stageUrl> before approving traffic swap to <appUrl>
#   6. For Canary: observe partial traffic before promoting to 100%
################################################################################

resource "harness_platform_pipeline" "asg_strategy" {
  count       = var.create_asg_strategy_pipeline ? 1 : 0
  identifier  = var.asg_strategy_pipeline_id
  name        = var.asg_strategy_pipeline_name
  org_id      = var.org_id
  project_id  = var.project_id
  description = var.asg_strategy_pipeline_description
  tags        = ["deployment-type:asg", "strategy:multi-strategy"]

  yaml = <<-ASG_EOT
    pipeline:
      name: ${var.asg_strategy_pipeline_name}
      identifier: ${var.asg_strategy_pipeline_id}
      projectIdentifier: ${var.project_id}
      orgIdentifier: ${var.org_id}
      description: ${var.asg_strategy_pipeline_description}
      tags:
        deployment-type: asg
        strategy: multi-strategy
      variables:
        - name: deployment_strategy
          type: String
          description: Deployment strategy to use
          required: true
          value: <+input>.allowedValues(blue-green,canary,rolling)
        - name: image_tag
          type: String
          description: AMI name to deploy (from CI Packer build, e.g. harness-demo-app-owner-42)
          required: true
          value: <+input>
      stages:
        - stage:
            name: Blue-Green Deployment
            identifier: asg_blue_green
            description: "Creates new (green) ASG, validates via stage listener, swaps ALB traffic"
            type: Deployment
            when:
              pipelineStatus: Success
              condition: <+pipeline.variables.deployment_strategy> == "blue-green"
            spec:
              deploymentType: Asg
              service:
                serviceRef: ${var.asg_service_ref}
              environment:
                environmentRef: ${var.environment_ref}
                deployToAll: false
                infrastructureDefinitions:
                  - identifier: ${var.asg_infrastructure_ref}
              execution:
                steps:
                  - step:
                      type: ShellScript
                      name: Print Variables
                      identifier: print_variables_bg
                      timeout: 5m
                      spec:
                        shell: Bash
                        executionTarget: {}
                        source:
                          type: Inline
                          spec:
                            script: |
                              echo "========================================"
                              echo "  HARNESS ASG PIPELINE - BLUE/GREEN"
                              echo "========================================"
                              echo "Pipeline:  <+pipeline.name>"
                              echo "Service:   <+service.name>"
                              echo "AMI:       <+artifact.metadata.ami>"
                              echo "AMI Name:  <+pipeline.variables.image_tag>"
                              echo "Strategy:  <+pipeline.variables.deployment_strategy>"
                              echo "Env:       <+env.name> (<+env.type>)"
                              echo ""
                              echo "Prod URL:  <+serviceVariables.appUrl>"
                              echo "Stage URL: <+serviceVariables.stageUrl>"
                              echo ""
                              echo "New EC2 instances start the JAR (baked into AMI) via systemd."
                              echo "========================================"
                        environmentVariables: []
                        outputVariables: []
                  - step:
                      name: Blue Green Deploy
                      identifier: asg_blue_green_deploy
                      type: AsgBlueGreenDeploy
                      timeout: 20m
                      spec:
                        useAlreadyRunningInstances: false
                        loadBalancers:
                          - loadBalancerName: <+infra.loadBalancers[0].loadBalancerName>
                            prodListenerArn: <+infra.loadBalancers[0].prodListenerArn>
                            stageListenerArn: <+infra.loadBalancers[0].stageListenerArn>
                            prodListenerRuleArn: ""
                            stageListenerRuleArn: ""
                  - step:
                      name: Validate Stage
                      identifier: validate_stage_bg
                      type: HarnessApproval
                      timeout: 1d
                      spec:
                        approvalMessage: |
                          Blue/Green deployment staged successfully!

                          NEW version is running on the STAGE environment:
                            Stage URL: <+serviceVariables.stageUrl>

                          CURRENT production traffic continues on:
                            Prod URL:  <+serviceVariables.appUrl>

                          Open the Stage URL to validate the new version, then:
                            - APPROVE to swap production traffic to the new version
                            - REJECT to abort (production unchanged)
                        includePipelineExecutionHistory: true
                        approvers:
                          userGroups:
                            - _project_all_users
                          minimumCount: 1
                          disallowPipelineExecutor: false
                  - step:
                      name: Swap Service
                      identifier: asg_swap_service
                      type: AsgBlueGreenSwapService
                      timeout: 20m
                      spec:
                        downsizeOldAsg: true
                  - step:
                      type: ShellScript
                      name: Deployment Complete
                      identifier: bg_deployment_complete
                      timeout: 2m
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
                              echo "Prod URL:  <+serviceVariables.appUrl>"
                              echo ""
                              echo "Traffic swapped to new version."
                              echo "Old ASG scaled down."
                              echo "========================================"
                        environmentVariables: []
                        outputVariables: []
                rollbackSteps:
                  - step:
                      name: Blue Green Rollback
                      identifier: asg_blue_green_rollback
                      type: AsgBlueGreenRollback
                      timeout: 20m
                      spec: {}
            failureStrategies:
              - onFailure:
                  errors:
                    - AllErrors
                  action:
                    type: StageRollback

        - stage:
            name: Canary Deployment
            identifier: asg_canary
            description: "Creates smaller canary ASG, shifts partial traffic, promotes on approval"
            type: Deployment
            when:
              pipelineStatus: Success
              condition: <+pipeline.variables.deployment_strategy> == "canary"
            spec:
              deploymentType: Asg
              service:
                serviceRef: ${var.asg_service_ref}
              environment:
                environmentRef: ${var.environment_ref}
                deployToAll: false
                infrastructureDefinitions:
                  - identifier: ${var.asg_infrastructure_ref}
              execution:
                steps:
                  - step:
                      type: ShellScript
                      name: Print Variables
                      identifier: print_variables_canary
                      timeout: 5m
                      spec:
                        shell: Bash
                        executionTarget: {}
                        source:
                          type: Inline
                          spec:
                            script: |
                              echo "========================================"
                              echo "  HARNESS ASG PIPELINE - CANARY"
                              echo "========================================"
                              echo "Pipeline:  <+pipeline.name>"
                              echo "Service:   <+service.name>"
                              echo "AMI:       <+artifact.metadata.ami>"
                              echo "AMI Name:  <+pipeline.variables.image_tag>"
                              echo "Strategy:  <+pipeline.variables.deployment_strategy>"
                              echo "Env:       <+env.name>"
                              echo ""
                              echo "App URL:   <+serviceVariables.appUrl>"
                              echo ""
                              echo "${var.asg_canary_instance_count} canary instance(s) will receive partial traffic."
                              echo "========================================"
                        environmentVariables: []
                        outputVariables: []
                  - step:
                      name: Canary Deploy
                      identifier: asg_canary_deploy
                      type: AsgCanaryDeploy
                      timeout: 20m
                      spec:
                        instanceSelection:
                          type: Count
                          spec:
                            count: ${var.asg_canary_instance_count}
                  - step:
                      name: Validate Canary
                      identifier: validate_canary
                      type: HarnessApproval
                      timeout: 1d
                      spec:
                        approvalMessage: |
                          Canary deployment running!

                          ${var.asg_canary_instance_count} canary instance(s) are live alongside the stable fleet.
                          A portion of traffic is being served by the new version.

                          App URL: <+serviceVariables.appUrl>

                          Validate the new version is behaving correctly, then:
                            - APPROVE to promote canary to 100% (replace all instances)
                            - REJECT to roll back (remove canary instances, stable fleet unchanged)
                        includePipelineExecutionHistory: true
                        approvers:
                          userGroups:
                            - _project_all_users
                          minimumCount: 1
                          disallowPipelineExecutor: false
                  - step:
                      name: Canary Delete
                      identifier: asg_canary_delete
                      type: AsgCanaryDelete
                      timeout: 20m
                      spec: {}
                  - step:
                      name: Rolling Deploy (Promote)
                      identifier: asg_canary_promote
                      type: AsgRollingDeploy
                      timeout: 20m
                      spec:
                        useAlreadyRunningInstances: false
                        skipMatching: true
                  - step:
                      type: ShellScript
                      name: Deployment Complete
                      identifier: canary_deployment_complete
                      timeout: 2m
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
                              echo "App URL: <+serviceVariables.appUrl>"
                              echo ""
                              echo "Canary validated and promoted to 100%."
                              echo "All instances now running the new version."
                              echo "========================================"
                        environmentVariables: []
                        outputVariables: []
                rollbackSteps:
                  - step:
                      name: Canary Delete (Rollback)
                      identifier: asg_canary_delete_rollback
                      type: AsgCanaryDelete
                      timeout: 20m
                      spec: {}
            failureStrategies:
              - onFailure:
                  errors:
                    - AllErrors
                  action:
                    type: StageRollback

        - stage:
            name: Rolling Deployment
            identifier: asg_rolling
            description: "Standard rolling update of the existing ASG instances"
            type: Deployment
            when:
              pipelineStatus: Success
              condition: <+pipeline.variables.deployment_strategy> == "rolling"
            spec:
              deploymentType: Asg
              service:
                serviceRef: ${var.asg_service_ref}
              environment:
                environmentRef: ${var.environment_ref}
                deployToAll: false
                infrastructureDefinitions:
                  - identifier: ${var.asg_infrastructure_ref}
              execution:
                steps:
                  - step:
                      type: ShellScript
                      name: Print Variables
                      identifier: print_variables_rolling
                      timeout: 5m
                      spec:
                        shell: Bash
                        executionTarget: {}
                        source:
                          type: Inline
                          spec:
                            script: |
                              echo "========================================"
                              echo "  HARNESS ASG PIPELINE - ROLLING"
                              echo "========================================"
                              echo "Pipeline:  <+pipeline.name>"
                              echo "Service:   <+service.name>"
                              echo "AMI:       <+artifact.metadata.ami>"
                              echo "AMI Name:  <+pipeline.variables.image_tag>"
                              echo "Strategy:  <+pipeline.variables.deployment_strategy>"
                              echo "Env:       <+env.name>"
                              echo ""
                              echo "App URL:   <+serviceVariables.appUrl>"
                              echo "========================================"
                        environmentVariables: []
                        outputVariables: []
                  - step:
                      name: Rolling Deploy
                      identifier: asg_rolling_deploy
                      type: AsgRollingDeploy
                      timeout: 20m
                      spec:
                        useAlreadyRunningInstances: false
                        skipMatching: true
                  - step:
                      type: ShellScript
                      name: Deployment Complete
                      identifier: rolling_deployment_complete
                      timeout: 2m
                      spec:
                        shell: Bash
                        executionTarget: {}
                        source:
                          type: Inline
                          spec:
                            script: |
                              echo "========================================"
                              echo "  ROLLING DEPLOYMENT COMPLETE"
                              echo "App URL: <+serviceVariables.appUrl>"
                              echo "========================================"
                        environmentVariables: []
                        outputVariables: []
                rollbackSteps:
                  - step:
                      name: Rolling Rollback
                      identifier: asg_rolling_rollback
                      type: AsgRollingRollback
                      timeout: 20m
                      spec: {}
            failureStrategies:
              - onFailure:
                  errors:
                    - AllErrors
                  action:
                    type: StageRollback
  ASG_EOT
}
