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

locals {
  pipeline_delegate_yaml = var.delegate_selector != "" ? "            delegateSelectors:\n              - ${var.delegate_selector}\n" : ""
  pipeline_change_governance_dev_yaml = var.enable_change_governance ? format("%s\n", <<-EOT
                  - stepGroup:
                      name: Change Governance
                      identifier: change_governance
                      steps:
                        - step:
                            type: ShellScript
                            name: Assemble Change Context
                            identifier: assemble_change_context
                            timeout: 10m
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
                                        "service": "<+service.identifier>",
                                        "environment": "<+env.identifier>",
                                        "environment_type": "<+env.type>",
                                        "deployment_strategy": "blue-green",
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
                        - step:
                            type: Policy
                            name: Evaluate Change Risk
                            identifier: evaluate_change_risk
                            timeout: 10m
                            spec:
                              policySets:
                                - ${var.change_governance_policy_set}
                              type: Custom
                              policySpec:
                                payload: <+execution.steps.change_governance.steps.assemble_change_context.output.outputVariables.change_context>
                            failureStrategies:
                              - onFailure:
                                  errors:
                                    - PolicyEvaluationFailure
                                  action:
                                    type: MarkAsSuccess
                        - step:
                            type: HarnessApproval
                            name: Governance Approval
                            identifier: governance_approval
                            timeout: 1d
                            spec:
                              approvalMessage: |
                                Change governance policies flagged this deployment for manual approval.

                                Policy evaluation status: <+execution.steps.change_governance.steps.evaluate_change_risk.output.status>
                                Review the Evaluate Change Risk step for the full policy decision details.

                                Release summary:
                                - Service: <+service.identifier>
                                - Environment: <+env.identifier>
                                - Strategy: blue-green
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
                              approvers:
                                userGroups:
                                  - ${var.change_governance_approver_group}
                                minimumCount: 1
                                disallowPipelineExecutor: false
                              approverInputs: []
                            when:
                              stageStatus: All
                              condition: <+execution.steps.change_governance.steps.evaluate_change_risk.output.status> == "error"
    EOT
  ) : ""
  pipeline_change_governance_prod_yaml = var.enable_change_governance ? format("%s\n", <<-EOT
                  - stepGroup:
                      name: Change Governance
                      identifier: change_governance
                      steps:
                        - step:
                            type: ShellScript
                            name: Assemble Change Context
                            identifier: assemble_change_context
                            timeout: 10m
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
                                        "service": "<+service.identifier>",
                                        "environment": "<+env.identifier>",
                                        "environment_type": "<+env.type>",
                                        "deployment_strategy": "canary",
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
                                      }
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
                        - step:
                            type: Policy
                            name: Evaluate Change Risk
                            identifier: evaluate_change_risk
                            timeout: 10m
                            spec:
                              policySets:
                                - ${var.change_governance_policy_set}
                              type: Custom
                              policySpec:
                                payload: <+execution.steps.change_governance.steps.assemble_change_context.output.outputVariables.change_context>
                            failureStrategies:
                              - onFailure:
                                  errors:
                                    - PolicyEvaluationFailure
                                  action:
                                    type: MarkAsSuccess
                        - step:
                            type: HarnessApproval
                            name: Governance Approval
                            identifier: governance_approval
                            timeout: 1d
                            spec:
                              approvalMessage: |
                                Change governance policies flagged this deployment for manual approval.

                                Policy evaluation status: <+execution.steps.change_governance.steps.evaluate_change_risk.output.status>
                                Review the Evaluate Change Risk step for the full policy decision details.

                                Release summary:
                                - Service: <+service.identifier>
                                - Environment: <+env.identifier>
                                - Strategy: canary
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
                              approvers:
                                userGroups:
                                  - ${var.change_governance_approver_group}
                                minimumCount: 1
                                disallowPipelineExecutor: false
                              approverInputs: []
                            when:
                              stageStatus: All
                              condition: <+execution.steps.change_governance.steps.evaluate_change_risk.output.status> == "error"
    EOT
  ) : ""
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
        - name: change_blast_radius
          type: String
          description: Expected blast radius for the deployment
          required: false
          value: <+input>.default(medium).allowedValues(low,medium,high)
        - name: test_pass_rate
          type: String
          description: Aggregated automated test pass rate percentage from CI
          required: false
          value: <+input>.default(100)
        - name: critical_vulnerabilities
          type: String
          description: Critical vulnerability count provided to change governance
          required: false
          value: <+input>.default(0)
        - name: high_vulnerabilities
          type: String
          description: High vulnerability count provided to change governance
          required: false
          value: <+input>.default(0)
        - name: open_change_failures
          type: String
          description: Number of unresolved release issues for the proposed change
          required: false
          value: <+input>.default(0)
        - name: rollback_ready
          type: String
          description: Whether rollback readiness has been verified
          required: false
          value: <+input>.default(true).allowedValues(true,false)
        - name: change_freeze_active
          type: String
          description: Whether a change freeze window is currently active
          required: false
          value: <+input>.default(false).allowedValues(true,false)
        - name: requires_data_migration
          type: String
          description: Whether the deployment includes a database or data migration
          required: false
          value: <+input>.default(false).allowedValues(true,false)
        - name: release_candidate_evidence
          type: String
          description: JSON release-candidate evidence bundle; auto-populated from CI/webhook runs or entered manually for demo/manual runs
          required: false
          value: <+input>.default({"artifact":{"image":"manual-demo","tag":"manual"},"attestations":{"sbom":"unknown","slsa_provenance":"unknown"}})
      stages:
        - stage:
            name: BlueGreen to Dev
            identifier: blue_green_dev
            description: Blue-Green deployment to Dev environment
            type: Deployment
${local.pipeline_delegate_yaml}            spec:
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
${local.pipeline_change_governance_dev_yaml}
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
                            - ${var.change_governance_approver_group}
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
${local.pipeline_delegate_yaml}            spec:
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
${local.pipeline_change_governance_prod_yaml}
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
                                  - ${var.change_governance_approver_group}
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
