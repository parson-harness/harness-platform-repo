################################################################################
# Kubernetes Strategy Choice Pipeline (Single pipeline with runtime strategy)
# Allows user to choose: blue-green, canary, or rolling at runtime
################################################################################

locals {
  # Emits a delegateSelectors YAML block for ShellScript steps that must run on the shared EKS delegate.
  strategy_shell_step_delegate_yaml = var.delegate_selector != "" ? "                        delegateSelectors:\n                          - ${var.delegate_selector}\n" : ""
  strategy_pipeline_tag_keys = distinct([for tag in local.explicit_pipeline_tags : regex("^([^:]+):(.*)$", tag)[0]])
  strategy_pipeline_tag_objects = [
    for key in local.strategy_pipeline_tag_keys : {
      key   = key
      value = regex("^([^:]+):(.*)$", one([for tag in local.explicit_pipeline_tags : tag if regex("^([^:]+):(.*)$", tag)[0] == key]))[1]
    }
  ]
  strategy_pipeline_yaml_tags       = join("\n", [for tag in local.strategy_pipeline_tag_objects : format("        %s: %s", tag.key, jsonencode(tag.value))])
  strategy_servicenow_ticket_number = "<+pipeline.stages.approval.spec.execution.steps.servicenow_create_ticket.ticket.ticketNumber>"
  strategy_servicenow_create_yaml = var.enable_change_governance && var.enable_servicenow ? format("%s", <<-EOT
                  - step:
                      type: ServiceNowCreate
                      name: Open Change Request
                      identifier: servicenow_create_ticket
                      timeout: 10m
                      spec:
                        connectorRef: ${var.servicenow_connector_ref}
                        ticketType: change_request
                        createType: Normal
                        fields:
                          - name: short_description
                            value: "Begin deployment of ${var.service_ref} to ${var.environment_name}"
                          - name: description
                            value: |-
                              Harness automated deployment initiated.
                              Service: ${var.service_ref}
                              Environment: ${var.environment_name} (${var.environment_type})
                              Strategy: <+pipeline.variables.deployment_strategy>
                              Image tag: <+pipeline.variables.image_tag>
                              Pipeline: <+pipeline.name>
                              Execution URL: <+pipeline.executionUrl>
                          - name: assignment_group
                            value: ${var.servicenow_assignment_group}
                          - name: justification
                            value: Standard change requested by Harness deployment automation.
    EOT
  ) : ""
  strategy_servicenow_approval_yaml = var.enable_change_governance && var.enable_servicenow ? format("%s", <<-EOT
                  - step:
                      type: ServiceNowApproval
                      name: ServiceNow Approval
                      identifier: servicenow_approval
                      timeout: 1d
                      spec:
                        connectorRef: ${var.servicenow_connector_ref}
                        ticketType: change_request
                        ticketNumber: ${local.strategy_servicenow_ticket_number}
                        retryInterval: 1m
                        approvalCriteria:
                          type: KeyValues
                          spec:
                            matchAnyCondition: true
                            conditions:
                              - key: state
                                operator: equals
                                value: Implement
                        rejectionCriteria:
                          type: KeyValues
                          spec:
                            matchAnyCondition: true
                            conditions: []
                        changeWindow:
                          startField: work_start
                          endField: end_date
    EOT
  ) : ""
  strategy_servicenow_approval_governance_yaml = var.enable_change_governance && var.enable_servicenow ? format("%s", <<-EOT
                            - step:
                                type: ServiceNowApproval
                                name: ServiceNow Approval
                                identifier: servicenow_approval
                                timeout: 1d
                                spec:
                                  connectorRef: ${var.servicenow_connector_ref}
                                  ticketType: change_request
                                  ticketNumber: ${local.strategy_servicenow_ticket_number}
                                  retryInterval: 1m
                                  approvalCriteria:
                                    type: KeyValues
                                    spec:
                                      matchAnyCondition: true
                                      conditions:
                                        - key: state
                                          operator: equals
                                          value: Implement
                                  rejectionCriteria:
                                    type: KeyValues
                                    spec:
                                      matchAnyCondition: true
                                      conditions: []
                                  changeWindow:
                                    startField: work_start
                                    endField: end_date
    EOT
  ) : ""
  strategy_servicenow_mark_implement_yaml = var.enable_change_governance && var.enable_servicenow ? format("%s", <<-EOT
                  - step:
                      type: ServiceNowUpdate
                      name: Move Change Request to Implement
                      identifier: servicenow_move_to_implement
                      timeout: 10m
                      spec:
                        useServiceNowTemplate: false
                        connectorRef: ${var.servicenow_connector_ref}
                        ticketType: change_request
                        ticketNumber: ${local.strategy_servicenow_ticket_number}
                        fields:
                          - name: state
                            value: Implement
                          - name: implementation_plan
                            value: |-
                              Harness deployment starting.
                              Service: ${var.service_ref}
                              Environment: ${var.environment_name}
                              Strategy: <+pipeline.variables.deployment_strategy>
                              Artifact: <+artifacts.primary.image>
                              Execution URL: <+pipeline.executionUrl>
                          - name: backout_plan
                            value: Harness automated rollback.
                          - name: work_notes
                            value: |-
                              Starting deployment of <+artifacts.primary.image> for ${var.service_ref} to ${var.environment_name}.
                              Pipeline execution: <+pipeline.executionUrl>
                          - name: assignment_group
                            value: ${var.servicenow_assignment_group}
    EOT
  ) : ""
  strategy_servicenow_mark_implement_governance_yaml = var.enable_change_governance && var.enable_servicenow ? format("%s", <<-EOT
                            - step:
                                type: ServiceNowUpdate
                                name: Move Change Request to Implement
                                identifier: servicenow_move_to_implement
                                timeout: 10m
                                spec:
                                  useServiceNowTemplate: false
                                  connectorRef: ${var.servicenow_connector_ref}
                                  ticketType: change_request
                                  ticketNumber: ${local.strategy_servicenow_ticket_number}
                                  fields:
                                    - name: state
                                      value: Implement
                                    - name: implementation_plan
                                      value: |-
                                        Harness deployment starting.
                                        Service: ${var.service_ref}
                                        Environment: ${var.environment_name}
                                        Strategy: <+pipeline.variables.deployment_strategy>
                                        Artifact: <+artifacts.primary.image>
                                        Execution URL: <+pipeline.executionUrl>
                                    - name: backout_plan
                                      value: Harness automated rollback.
                                    - name: work_notes
                                      value: |-
                                        Starting deployment of <+artifacts.primary.image> for ${var.service_ref} to ${var.environment_name}.
                                        Pipeline execution: <+pipeline.executionUrl>
                                    - name: assignment_group
                                      value: ${var.servicenow_assignment_group}
    EOT
  ) : ""
  strategy_servicenow_approval_stage_yaml = var.enable_change_governance && var.enable_servicenow ? format("%s\n", <<-EOT
        - stage:
            name: Approval
            identifier: approval
            description: Create the ServiceNow change record before governance evaluation
            type: Custom
            when:
              pipelineStatus: Success
            spec:
              execution:
                steps:
${local.strategy_servicenow_create_yaml}
            tags: {}
            failureStrategies:
              - onFailure:
                  errors:
                    - AllErrors
                  action:
                    type: StageRollback

    EOT
  ) : ""
  strategy_governance_manual_approval_yaml = var.enable_change_governance ? (var.enable_servicenow ? local.strategy_servicenow_approval_governance_yaml : format("%s", <<-EOT
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
                          - Service: ${var.service_ref}
                          - Environment: ${var.environment_name}
                          - Strategy: <+pipeline.variables.deployment_strategy>
                          - Image tag: <+pipeline.variables.image_tag>
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
    EOT
  )) : ""
  strategy_governance_auto_path_yaml = var.enable_change_governance ? (var.enable_servicenow ? local.strategy_servicenow_mark_implement_governance_yaml : format("%s", <<-EOT
                  - step:
                      type: ShellScript
                      name: Record Auto Approval
                      identifier: record_auto_approval
                      spec:
                        shell: Bash
                        executionTarget: {}
${local.strategy_shell_step_delegate_yaml}                        source:
                          type: Inline
                          spec:
                            script: |
                              echo "Policy evaluation passed."
                              echo "Service: ${var.service_ref}"
                              echo "Environment: ${var.environment_name}"
                              echo "Strategy: <+pipeline.variables.deployment_strategy>"
                        environmentVariables: []
                        outputVariables: []
                      timeout: 10m
                      when:
                        stageStatus: All
    EOT
  )) : ""
  strategy_servicenow_close_success_yaml = var.enable_change_governance && var.enable_servicenow ? format("%s", <<-EOT
                  - step:
                      type: ServiceNowUpdate
                      name: Close Change Request
                      identifier: servicenow_close_ticket
                      timeout: 10m
                      spec:
                        useServiceNowTemplate: false
                        connectorRef: ${var.servicenow_connector_ref}
                        ticketType: change_request
                        ticketNumber: ${local.strategy_servicenow_ticket_number}
                        fields:
                          - name: state
                            value: "3"
                          - name: close_code
                            value: successful
                          - name: close_notes
                            value: |-
                              Deployment successful for <+artifacts.primary.image> to ${var.environment_name}.
                              Pipeline execution: <+pipeline.executionUrl>
                          - name: work_notes
                            value: |-
                              Deployment completed successfully.
                              Strategy: <+pipeline.variables.deployment_strategy>
    EOT
  ) : ""
  strategy_servicenow_close_failure_yaml = var.enable_change_governance && var.enable_servicenow ? format("%s", <<-EOT
                  - step:
                      type: ServiceNowUpdate
                      name: Close Change Request
                      identifier: servicenow_close_ticket
                      timeout: 10m
                      spec:
                        useServiceNowTemplate: false
                        connectorRef: ${var.servicenow_connector_ref}
                        ticketType: change_request
                        ticketNumber: ${local.strategy_servicenow_ticket_number}
                        fields:
                          - name: state
                            value: "3"
                          - name: close_code
                            value: unsuccessful
                          - name: close_notes
                            value: |-
                              Deployment failed for <+artifacts.primary.image> to ${var.environment_name}.
                              Harness initiated rollback.
                              Pipeline execution: <+pipeline.executionUrl>
                          - name: work_notes
                            value: |-
                              Deployment failed and rollback was triggered.
                              Strategy: <+pipeline.variables.deployment_strategy>
    EOT
  ) : ""
  strategy_governance_stage_yaml = var.enable_change_governance ? format("%s\n", <<-EOT
        - stage:
            name: Release Governance
            identifier: change_governance
            description: Policy-driven approval gate for deployment risk evaluation
            type: Custom
            when:
              pipelineStatus: Success
            spec:
              execution:
                steps:
                  - step:
                      type: ShellScript
                      name: Assemble Change Context
                      identifier: assemble_change_context
                      spec:
                        shell: Bash
                        executionTarget: {}
${local.strategy_shell_step_delegate_yaml}                        source:
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
                                  "service": "${var.service_ref}",
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
${local.strategy_governance_manual_approval_yaml}
                          when:
                            stageStatus: All
                            condition: <+execution.steps.governance.steps.evaluate_change_risk.output.status> == "error"
                      - stepGroup:
                          name: Auto Approval Path
                          identifier: auto_approval_path
                          steps:
${local.strategy_governance_auto_path_yaml}
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

resource "harness_platform_pipeline" "k8s_strategy" {
  count       = var.create_strategy_pipeline ? 1 : 0
  identifier  = var.strategy_pipeline_id
  name        = var.strategy_pipeline_name
  org_id      = var.org_id
  project_id  = var.project_id
  description = var.strategy_pipeline_description
  tags        = concat(["deployment-type:kubernetes", "strategy:multi-strategy"], local.explicit_pipeline_tags)

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
${local.strategy_pipeline_yaml_tags != "" ? "${local.strategy_pipeline_yaml_tags}\n" : ""}
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
          description: JSON release-candidate evidence bundle; auto-populated from CI on webhook runs or entered manually for demo/manual runs
          required: false
          value: <+input>.default({"artifact":{"image":"manual-demo","tag":"manual"},"attestations":{"sbom":"unknown","slsa_provenance":"unknown"}})
      stages:
${local.strategy_servicenow_approval_stage_yaml}
${local.strategy_governance_stage_yaml}
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
                      name: Reset Strategy State
                      identifier: reset_strategy_state
                      timeout: 5m
                      spec:
                        shell: Bash
                        executionTarget: {}
${local.strategy_shell_step_delegate_yaml}                        source:
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
                                echo "No B/G color selector - removing non-B/G resources for fresh B/G setup"
                                kubectl delete service "$${SVC}-service" -n "$${NAMESPACE}" --ignore-not-found=true
                                kubectl delete service "$${SVC}-service-stage" -n "$${NAMESPACE}" --ignore-not-found=true
                                kubectl delete configmap "$${RELEASE}" -n "$${NAMESPACE}" --ignore-not-found=true
                                kubectl delete deployment "$${SVC}-deployment" -n "$${NAMESPACE}" --ignore-not-found=true
                              else
                                echo "B/G services exist (color=$${COLOR}) - preserving services and ConfigMap for zero-downtime re-run"
                              fi
                              kubectl delete deployment "$${SVC}-deployment-canary" -n "$${NAMESPACE}" --ignore-not-found=true
                              echo "Done."
                        environmentVariables: []
                        outputVariables: []
                  - step:
                      type: ShellScript
                      name: Print Variables
                      identifier: print_variables
                      timeout: 10m
                      spec:
                        shell: Bash
                        executionTarget: {}
${local.strategy_shell_step_delegate_yaml}                        source:
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

                          Artifact:
                            Image tag: <+pipeline.variables.image_tag>

                          Validate the new version on the Stage environment:
                            Stage URL:   https://<+serviceVariables.ingressStageHost>

                          Current production traffic continues to:
                            Primary URL: https://<+serviceVariables.ingressHost>

                          Approve to swap traffic to the new version. Reject to abort.
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
                      timeout: 1m
                      spec:
                        shell: Bash
                        executionTarget: {}
${local.strategy_shell_step_delegate_yaml}                        source:
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
${local.strategy_servicenow_close_success_yaml}
                rollbackSteps:
${local.strategy_servicenow_close_failure_yaml}
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
                      name: Reset Strategy State
                      identifier: reset_strategy_state
                      timeout: 5m
                      spec:
                        shell: Bash
                        executionTarget: {}
${local.strategy_shell_step_delegate_yaml}                        source:
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
                  - step:
                      type: ShellScript
                      name: Print Variables
                      identifier: print_variables
                      timeout: 10m
                      spec:
                        shell: Bash
                        executionTarget: {}
${local.strategy_shell_step_delegate_yaml}                        source:
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
                      timeout: 10m
                      spec:
                        shell: Bash
                        executionTarget: {}
${local.strategy_shell_step_delegate_yaml}                        source:
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
                  - step:
                      name: Approval
                      identifier: canary_approval
                      type: HarnessApproval
                      timeout: 1d
                      spec:
                        approvalMessage: |
                          Canary deployment complete.

                          Artifact:
                            Image tag: <+pipeline.variables.image_tag>

                          Validation target:
                            App URL: https://<+serviceVariables.ingressHost>
                          Traffic split: ~<+execution.steps.get_validation_urls.output.outputVariables.CANARY_PCT>% canary, ~<+execution.steps.get_validation_urls.output.outputVariables.STABLE_PCT>% stable

                          Approve to promote canary to 100% of pods. Reject to roll back.
                        includePipelineExecutionHistory: true
                        approvers:
                          userGroups:
                            - ${var.change_governance_approver_group}
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
                      timeout: 1m
                      spec:
                        shell: Bash
                        executionTarget: {}
${local.strategy_shell_step_delegate_yaml}                        source:
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
${local.strategy_servicenow_close_success_yaml}
                rollbackSteps:
                  - step:
                      name: Canary Delete
                      identifier: strategy_rollback_canary_delete
                      type: K8sCanaryDelete
                      timeout: 10m
                      spec: {}
${local.strategy_servicenow_close_failure_yaml}
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
                      name: Reset Strategy State
                      identifier: reset_strategy_state
                      timeout: 5m
                      spec:
                        shell: Bash
                        executionTarget: {}
${local.strategy_shell_step_delegate_yaml}                        source:
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
                  - step:
                      type: ShellScript
                      name: Print Variables
                      identifier: print_variables
                      timeout: 10m
                      spec:
                        shell: Bash
                        executionTarget: {}
${local.strategy_shell_step_delegate_yaml}                        source:
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
                      timeout: 10m
                      spec:
                        shell: Bash
                        executionTarget: {}
${local.strategy_shell_step_delegate_yaml}                        source:
                          type: Inline
                          spec:
                            script: |
                              echo "========================================"
                              echo "  ROLLING DEPLOYMENT COMPLETE"
                              echo "App URL: https://<+serviceVariables.ingressHost>"
                              echo "========================================"
                        environmentVariables: []
                        outputVariables: []
${local.strategy_servicenow_close_success_yaml}
                rollbackSteps:
                  - step:
                      name: Rolling Rollback
                      identifier: strategy_rolling_rollback
                      type: K8sRollingRollback
                      timeout: 10m
                      spec: {}
${local.strategy_servicenow_close_failure_yaml}
            failureStrategies:
              - onFailure:
                  errors:
                    - AllErrors
                  action:
                    type: StageRollback
  STRATEGY_EOT
}
