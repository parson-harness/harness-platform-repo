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
locals {
  asg_delegate_yaml = var.delegate_selector != "" ? "            delegateSelectors:\n              - ${var.delegate_selector}\n" : ""
  asg_pipeline_tag_objects = [
    for tag in local.explicit_pipeline_tags : {
      key   = regex("^([^:]+):(.*)$", tag)[0]
      value = regex("^([^:]+):(.*)$", tag)[1]
    }
  ]
  asg_pipeline_yaml_tags = join("\n", [for tag in local.asg_pipeline_tag_objects : format("        %s: %s", tag.key, jsonencode(tag.value))])
  asg_change_governance_yaml = var.enable_change_governance ? format("%s\n", <<-EOT
        - stage:
            name: Release Governance
            identifier: release_governance
            description: Policy-driven approval gate for deployment risk evaluation
            type: Custom
            when:
              pipelineStatus: Success
${local.asg_delegate_yaml}            spec:
              execution:
                steps:
                  - step:
                      type: ShellScript
                      name: Assemble Change Context
                      identifier: assemble_change_context
                      spec:
                        shell: Bash
                        executionTarget: {}
                        source:
                          type: Inline
                          spec:
                            script: |
                              cat <<'EOF' > change_context.json
                              {
                                "pipeline": {
                                  "identifier": "<+pipeline.identifier>",
                                  "execution_id": "<+pipeline.executionId>",
                                  "sequence_id": "<+pipeline.sequenceId>"
                                },
                                "change": {
                                  "request_id": "<+pipeline.identifier>-<+pipeline.sequenceId>",
                                  "service": "${var.asg_service_ref}",
                                  "environment": "${var.environment_name}",
                                  "environment_type": "${var.environment_type}",
                                  "deployment_strategy": "<+pipeline.variables.deployment_strategy>",
                                  "blast_radius": "<+pipeline.variables.change_blast_radius>",
                                  "freeze_window_active": <+pipeline.variables.change_freeze_active>,
                                  "requires_data_migration": <+pipeline.variables.requires_data_migration>
                                },
                                "validation": {
                                  "tests": {
                                    "pass_rate": <+pipeline.variables.test_pass_rate>
                                  },
                                  "security": {
                                    "critical_vulns": <+pipeline.variables.critical_vulnerabilities>,
                                    "high_vulns": <+pipeline.variables.high_vulnerabilities>
                                  },
                                  "operations": {
                                    "open_failures": <+pipeline.variables.open_change_failures>,
                                    "rollback_ready": <+pipeline.variables.rollback_ready>
                                  }
                                },
                                "release_candidate": <+pipeline.variables.release_candidate_evidence>
                              }
                              EOF

                              change_context="$(tr -d '\n' < change_context.json)"
                              export change_context
                              echo "$change_context"
                        environmentVariables: []
                        outputVariables:
                          - name: change_context
                            type: String
                            value: change_context
                      timeout: 10m
                  - stepGroup:
                      name: Governance
                      identifier: governance
                      steps:
                        - step:
                            type: Policy
                            name: Evaluate Change Risk
                            identifier: evaluate_change_risk
                            spec:
                              policySets:
                                - ${var.change_governance_policy_set}
                              type: Custom
                              policySpec:
                                payload: <+execution.steps.assemble_change_context.output.outputVariables.change_context>
                            timeout: 10m
                            failureStrategies:
                              - onFailure:
                                  errors:
                                    - PolicyEvaluationFailure
                                  action:
                                    type: MarkAsSuccess
                  - parallel:
                      - stepGroup:
                          name: Manual Approval Required
                          identifier: manual_approval_required
                          steps:
                            - step:
                                type: HarnessApproval
                                name: Governance Approval
                                identifier: governance_approval
                                spec:
                                  approvalMessage: |
                                    Release governance policies flagged this deployment for manual approval.

                                    Policy evaluation status: <+execution.steps.governance.steps.evaluate_change_risk.output.status>
                                    Review the Evaluate Change Risk step for the full policy decision details.

                                    Release summary:
                                    - Service: ${var.asg_service_ref}
                                    - Environment: ${var.environment_name}
                                    - Strategy: <+pipeline.variables.deployment_strategy>
                                    - AMI name: <+pipeline.variables.ami_name>
                                    - Test pass rate: <+pipeline.variables.test_pass_rate>
                                    - Critical vulnerabilities: <+pipeline.variables.critical_vulnerabilities>
                                    - High vulnerabilities: <+pipeline.variables.high_vulnerabilities>
                                    - Rollback ready: <+pipeline.variables.rollback_ready>
                                    - Open change failures: <+pipeline.variables.open_change_failures>
                                    - Change freeze active: <+pipeline.variables.change_freeze_active>
                                    - Requires data migration: <+pipeline.variables.requires_data_migration>

                                    Release candidate evidence:
                                    <+pipeline.variables.release_candidate_evidence>
                                  includePipelineExecutionHistory: true
                                  isAutoRejectEnabled: false
                                  approvers:
                                    userGroups:
                                      - ${var.change_governance_approver_group}
                                    minimumCount: 1
                                    disallowPipelineExecutor: false
                                  approverInputs: []
                                timeout: 10m
                                when:
                                  stageStatus: All
                          when:
                            stageStatus: All
                            condition: <+execution.steps.governance.steps.evaluate_change_risk.output.status> == "error"
                      - stepGroup:
                          name: Auto Approval Path
                          identifier: auto_approval_path
                          steps:
                            - step:
                                type: ShellScript
                                name: Record Auto Approval
                                identifier: record_auto_approval
                                spec:
                                  shell: Bash
                                  executionTarget: {}
                                  source:
                                    type: Inline
                                    spec:
                                      script: |
                                        echo "Policy evaluation passed."
                                        echo "Service: ${var.asg_service_ref}"
                                        echo "Environment: ${var.environment_name}"
                                        echo "Strategy: <+pipeline.variables.deployment_strategy>"
                                  environmentVariables: []
                                  outputVariables: []
                                timeout: 10m
                                when:
                                  stageStatus: All
                          when:
                            stageStatus: All
                            condition: <+execution.steps.governance.steps.evaluate_change_risk.output.status> != "error"
            tags: {}
            failureStrategies:
              - onFailure:
                  errors:
                    - AllErrors
                  action:
                    type: StageRollback

    EOT
  ) : ""
}

resource "harness_platform_pipeline" "asg_strategy" {
  count       = var.create_asg_strategy_pipeline ? 1 : 0
  identifier  = var.asg_strategy_pipeline_id
  name        = var.asg_strategy_pipeline_name
  org_id      = var.org_id
  project_id  = var.project_id
  description = var.asg_strategy_pipeline_description
  tags        = concat(["deployment-type:asg", "strategy:multi-strategy"], local.explicit_pipeline_tags)

  yaml = <<-ASG_EOT
    pipeline:
      name: ${var.asg_strategy_pipeline_name}
      identifier: ${var.asg_strategy_pipeline_id}
      projectIdentifier: ${var.project_id}
      orgIdentifier: ${var.org_id}
      description: "${var.asg_strategy_pipeline_description}"
      tags:
        deployment-type: asg
        strategy: multi-strategy
${local.asg_pipeline_yaml_tags != "" ? "${local.asg_pipeline_yaml_tags}\n" : ""}
      variables:
        - name: deployment_strategy
          type: String
          description: Deployment strategy to use
          required: true
          value: <+input>.allowedValues(blue-green,canary,rolling)
        - name: ami_name
          type: String
          description: Full AMI name to deploy (from CI Packer build, e.g. harness-demo-app-owner-42, not app version 1.0.1)
          required: true
          value: <+input>
        - name: change_blast_radius
          type: String
          description: Expected blast radius for the deployment
          required: false
          value: <+input>.default(medium).allowedValues(low,medium,high)
        - name: test_pass_rate
          type: String
          description: Aggregated automated test pass rate percentage; auto-populated from CI on webhook runs or entered manually for demo/manual runs
          required: false
          value: <+input>.default(100)
        - name: critical_vulnerabilities
          type: String
          description: Critical vulnerability count; auto-populated from CI on webhook runs or entered manually for demo/manual runs
          required: false
          value: <+input>.default(0)
        - name: high_vulnerabilities
          type: String
          description: High vulnerability count; auto-populated from CI on webhook runs or entered manually for demo/manual runs
          required: false
          value: <+input>.default(0)
        - name: open_change_failures
          type: String
          description: Demo-time count of unresolved change failures for the proposed change; typically sourced from ITSM in production
          required: false
          value: <+input>.default(0)
        - name: rollback_ready
          type: String
          description: Whether rollback readiness has been verified; currently runtime-controlled for demo/manual runs and a good candidate for future automation
          required: false
          value: <+input>.default(true).allowedValues(true,false)
        - name: change_freeze_active
          type: String
          description: Whether a change freeze window is currently active; provided by CI/webhook or entered manually for demo/manual runs
          required: false
          value: <+input>.default(false).allowedValues(true,false)
        - name: requires_data_migration
          type: String
          description: Whether the deployment includes a database or data migration; provided by CI/webhook or entered manually for demo/manual runs
          required: false
          value: <+input>.default(false).allowedValues(true,false)
        - name: release_candidate_evidence
          type: String
          description: JSON release-candidate evidence bundle; auto-populated from CI/webhook runs or entered manually for demo/manual runs
          required: false
          value: <+input>.default({"artifact":{"image":"manual-demo","tag":"manual"},"attestations":{"sbom":"unknown","slsa_provenance":"unknown"}})
      stages:
${local.asg_change_governance_yaml}
        - stage:
            name: Blue-Green Deployment
            identifier: asg_blue_green
            description: "Creates new (green) ASG, validates via stage listener, swaps ALB traffic"
            type: Deployment
            when:
              pipelineStatus: Success
              condition: <+pipeline.variables.deployment_strategy> == "blue-green"
${local.asg_delegate_yaml}            spec:
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
                              echo "AMI Name:  <+pipeline.variables.ami_name>"
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
                        asgName: ${var.asg_prod_asg_name}
                        useAlreadyRunningInstances: false
                        loadBalancers:
                          - loadBalancer: ${var.asg_alb_name}
                            prodListener: ${var.asg_prod_listener_arn}
                            prodListenerRuleArn: ${var.asg_prod_listener_rule_arn}
                            stageListener: ${var.asg_stage_listener_arn}
                            stageListenerRuleArn: ${var.asg_stage_listener_rule_arn}
                  - step:
                      name: Validate Stage
                      identifier: validate_stage_bg
                      type: HarnessApproval
                      timeout: 1d
                      spec:
                        approvalMessage: |
                          Blue/Green deployment staged successfully.

                          Artifact:
                            AMI Name: <+pipeline.variables.ami_name>

                          Validate the new version on the Stage environment:
                            Stage URL: <+serviceVariables.stageUrl>

                          Current production traffic continues to:
                            Prod URL:  <+serviceVariables.appUrl>

                          Approve to swap traffic to the new version. Reject to abort.
                        includePipelineExecutionHistory: true
                        approvers:
                          userGroups:
                            - ${var.change_governance_approver_group}
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
${local.asg_delegate_yaml}            spec:
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
                              echo "AMI Name:  <+pipeline.variables.ami_name>"
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
                        asgName: ${var.asg_prod_asg_name}
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
                          Canary deployment complete.

                          Artifact:
                            AMI Name:  <+pipeline.variables.ami_name>
                            Canary ASG: ${var.asg_prod_asg_name}__Canary

                          Validation target:
                            App URL:   <+serviceVariables.appUrl>

                          ${var.asg_canary_instance_count} canary instance(s) are live alongside the stable fleet.
                          Inspect the temporary canary ASG in AWS using the name above.

                          Approve to promote canary to 100% of instances. Reject to roll back.
                        includePipelineExecutionHistory: true
                        approvers:
                          userGroups:
                            - ${var.change_governance_approver_group}
                          minimumCount: 1
                          disallowPipelineExecutor: false
                  - step:
                      name: Canary Delete
                      identifier: asg_canary_delete
                      type: AsgCanaryDelete
                      timeout: 20m
                      spec: {}
                  - step:
                      name: Rolling Deploy Promote
                      identifier: asg_canary_promote
                      type: AsgRollingDeploy
                      timeout: 20m
                      spec:
                        asgName: ${var.asg_prod_asg_name}
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
                      name: Canary Delete Rollback
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
${local.asg_delegate_yaml}            spec:
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
                              echo "AMI Name:  <+pipeline.variables.ami_name>"
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
                        asgName: ${var.asg_prod_asg_name}
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
