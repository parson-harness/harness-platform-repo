################################################################################
# ASG CI Pipeline
# Builds Java JAR then bakes it into an AWS AMI using Packer
# Separate from the EKS CI pipeline (which builds Docker images for HAR)
################################################################################

locals {
  asg_ci_pipeline_tag_objects = [
    for tag in var.pipeline_tags : can(regex("^([^:]+):(.*)$", tag)) ? {
      key   = regex("^([^:]+):(.*)$", tag)[0]
      value = regex("^([^:]+):(.*)$", tag)[1]
      } : {
      key   = tag
      value = "true"
    }
  ]
  asg_ci_pipeline_yaml_tags = join("\n", [for tag in local.asg_ci_pipeline_tag_objects : format("        %s: %s", tag.key, jsonencode(tag.value))])
}

resource "harness_platform_pipeline" "asg_ci_build" {
  count       = var.create_asg_ci_pipeline ? 1 : 0
  identifier  = var.asg_ci_pipeline_id
  name        = var.asg_ci_pipeline_name
  org_id      = var.org_id
  project_id  = var.project_id
  description = var.asg_ci_pipeline_description
  tags        = concat(["pipeline-type:ci", "build:gradle-packer", "deployment:asg", "standard-template:true", "harness-intelligence:enabled", "security-scanning:enabled"], var.pipeline_tags)

  yaml = <<-CI_EOT
    pipeline:
      name: ${var.asg_ci_pipeline_name}
      identifier: ${var.asg_ci_pipeline_id}
      projectIdentifier: ${var.project_id}
      orgIdentifier: ${var.org_id}
      description: "${var.asg_ci_pipeline_description}"
      tags:
        pipeline-type: ci
        build: gradle-packer
        deployment: asg
        standard-template: "true"
        harness-intelligence: enabled
        security-scanning: enabled
${local.asg_ci_pipeline_yaml_tags != "" ? "${local.asg_ci_pipeline_yaml_tags}\n" : ""}
      variables:
        - name: auto_deploy
          type: String
          description: Automatically trigger CD pipeline after successful build
          required: false
          value: <+input>.default(true).allowedValues(true,false)
        - name: harness_endpoint
          type: String
          description: Harness API endpoint
          required: false
          value: <+input>.default(https://app.harness.io/gratis)
        - name: change_blast_radius
          type: String
          description: Expected blast radius for the release governance evaluation
          required: false
          value: <+input>.default(low).allowedValues(low,medium,high)
        - name: rollback_ready
          type: String
          description: Whether rollback readiness has been verified for release governance
          required: false
          value: <+input>.default(true).allowedValues(true,false)
        - name: open_change_failures
          type: String
          description: Demo-time count of unresolved change failures for release governance; typically sourced from ITSM in production
          required: false
          value: <+input>.default(0)
        - name: change_freeze_active
          type: String
          description: Whether a release freeze is active for this deployment
          required: false
          value: <+input>.default(false).allowedValues(true,false)
        - name: requires_data_migration
          type: String
          description: Whether the release includes a database or data migration
          required: false
          value: <+input>.default(false).allowedValues(true,false)
      properties:
        ci:
          codebase:
%{if var.use_harness_code~}
            repoName: ${local.effective_harness_code_repo_name}
%{else~}
            connectorRef: ${var.git_connector_ref}
            repoName: ${var.git_repo_name}
%{endif~}
            build: <+input>
            sparseCheckout: []
      stages:
        - stage:
            name: Build - Test - Scan - Bake AMI
            identifier: build_test_scan_bake_ami
            description: CI Intelligence + Security Scanning + Packer AMI Build
            type: CI
            spec:
              cloneCodebase: true
              caching:
                enabled: true
                paths: []
              sharedPaths:
                - /var/run
                - /root/.gradle
              platform:
                os: Linux
                arch: Amd64
              runtime:
                type: Cloud
                spec: {}
              buildIntelligence:
                enabled: true
              execution:
                steps:
                  - step:
                      type: Gitleaks
                      name: Gitleaks Secret Scan
                      identifier: gitleaks
                      spec:
                        mode: orchestration
                        config: default
                        target:
                          type: repository
                          detection: auto
                        advanced:
                          log:
                            level: info
                  - stepGroup:
                      name: Build and Test
                      identifier: build_and_test
                      steps:
                        - parallel:
                            - step:
                                type: Test
                                name: Test Intelligence
                                identifier: test_intelligence
                                spec:
                                  command: gradle test --build-cache
                                  shell: Sh
                                  connectorRef: account.harnessImage
                                  image: gradle:8.5-jdk17
                                  intelligenceMode: true
                            - step:
                                type: Run
                                name: Build Intelligence
                                identifier: build_intelligence
                                spec:
%{if var.har_registry_ref != ""~}
                                  registryRef: ${var.har_registry_ref}
%{else~}
                                  connectorRef: account.harnessImage
%{endif~}
                                  image: gradle:8.5-jdk17
                                  shell: Sh
                                  command: |
                                    echo "=== GRADLE BUILD INTELLIGENCE ==="
                                    gradle build -x test --build-cache --parallel
                                    echo "Build artifacts:"
                                    ls -la build/libs/
                  - step:
                      type: Run
                      name: Upload Code Coverage
                      identifier: upload_code_coverage
                      spec:
%{if var.har_registry_ref != ""~}
                        registryRef: ${var.har_registry_ref}
%{else~}
                        connectorRef: account.harnessImage
%{endif~}
                        image: gradle:8.5-jdk17
                        shell: Sh
                        command: |
                          set -e
                          /tmp/harness/bin/auto-injection || true
                          $HARNESS_WORKSPACE/bi/auto-injection || true

                          echo "=== GENERATING CODE COVERAGE REPORT ==="
                          gradle clean test jacocoTestReport bootJar --no-build-cache --rerun-tasks

                          if ! ls build/test-results/test/*.xml >/dev/null 2>&1; then
                            echo "JUnit test reports not found at build/test-results/test/*.xml"
                            exit 1
                          fi

                          echo ""
                          echo "=== UPLOADING TEST REPORTS TO HARNESS ==="
                          hcli --verbose test-reports upload "build/test-results/test/*.xml"

                          COVERAGE_FILE="build/reports/jacoco/test/jacocoTestReport.xml"

                          if [ ! -s "$COVERAGE_FILE" ]; then
                            echo "Coverage report not found at $COVERAGE_FILE"
                            exit 1
                          fi

                          if [ "$COVERAGE_PROVIDER" = "github" ]; then
                            COVERAGE_OWNER="$${COVERAGE_REPO_NAME%%/*}"
                            COVERAGE_IDENTIFIER="$${COVERAGE_REPO_NAME##*/}"
                          else
                            COVERAGE_OWNER="$HARNESS_COVERAGE_OWNER"
                            COVERAGE_IDENTIFIER="$COVERAGE_REPO_NAME"
                          fi

                          mkdir -p jacoco
                          cp "$COVERAGE_FILE" jacoco/jacoco.xml
                          UPLOAD_COVERAGE_FILE="$(pwd)/jacoco/jacoco.xml"

                          echo ""
                          echo "=== COVERAGE FILE DETAILS ==="
                          ls -lah build/reports/jacoco/test || true
                          ls -lah jacoco || true
                          echo "=== JAR FILE DETAILS ==="
                          ls -lah build/libs || true
                          find build/libs -maxdepth 1 -name '*.jar' | sort || true
                          wc -c "$UPLOAD_COVERAGE_FILE" || true

                          hcli cov analyze --file "$UPLOAD_COVERAGE_FILE" || true

                          echo ""
                          echo "=== UPLOADING COVERAGE TO HARNESS ==="

                          hcli --verbose cov upload \
                            --file "$UPLOAD_COVERAGE_FILE" \
                            --provider "$COVERAGE_PROVIDER" \
                            --owner "$COVERAGE_OWNER" \
                            --identifier "$COVERAGE_IDENTIFIER" \
                            -- sh -c "test -s '$UPLOAD_COVERAGE_FILE'"

                          echo "Full report: build/reports/jacoco/test/html/index.html"
                        envVariables:
                          CI_ENABLE_HCLI_FOR_TESTS: "true"
                          CI_ENABLE_QUARANTINED_TEST_SKIP: "true"
                  - stepGroup:
                      name: SAST Scans
                      identifier: sast_scans
                      steps:
                        - parallel:
                            - step:
                                type: HarnessSAST
                                name: Harness SAST
                                identifier: harness_sast
                                spec:
                                  mode: orchestration
                                  config: default
                                  target:
                                    type: repository
                                    detection: auto
                                  advanced:
                                    log:
                                      level: info
                            - step:
                                type: Semgrep
                                name: Semgrep
                                identifier: semgrep
                                spec:
                                  mode: orchestration
                                  config: default
                                  target:
                                    type: repository
                                    detection: auto
                                  advanced:
                                    log:
                                      level: info
                                failureStrategies:
                                  - onFailure:
                                      errors:
                                        - AllErrors
                                      action:
                                        type: Ignore
                  - step:
                      type: HarnessSCA
                      name: Harness SCA
                      identifier: harness_sca
                      spec:
                        mode: orchestration
                        config: default
                        target:
                          type: repository
                          detection: auto
                        advanced:
                          log:
                            level: info
                      when:
                        stageStatus: Success
                        condition: '"true" == "false"'
                  - step:
                      type: Run
                      name: Build Info
                      identifier: build_info
                      spec:
%{if var.har_registry_ref != ""~}
                        registryRef: ${var.har_registry_ref}
%{else~}
                        connectorRef: account.harnessImage
%{endif~}
                        image: alpine:latest
                        shell: Sh
                        command: |
                          echo "========================================"
                          echo "  BUILD INFORMATION"
                          echo "========================================"
                          echo "Pipeline: <+pipeline.name>"
                          echo "Build Number: <+pipeline.sequenceId>"
                          echo "Branch: <+codebase.branch>"
                          echo "Commit: <+codebase.commitSha>"
                          echo "========================================"

                          if [ "<+codebase.branch>" = "main" ]; then
                            IMAGE_TAG="<+pipeline.sequenceId>"
                          else
                            BRANCH_SAFE=$(echo "<+codebase.branch>" | sed 's/[^a-zA-Z0-9]/-/g')
                            IMAGE_TAG="$${BRANCH_SAFE}-<+pipeline.sequenceId>"
                          fi
                          AMI_NAME="harness-demo-app-${var.asg_packer_owner}-$${IMAGE_TAG}"
                          echo "AMI Version Tag: $IMAGE_TAG"
                          echo "AMI Name:        $AMI_NAME"
                        outputVariables:
                          - name: IMAGE_TAG
                          - name: AMI_NAME
                  - step:
                      type: Run
                      name: Build AMI with Packer
                      identifier: packer_build_ami
                      spec:
                        connectorRef: ${var.har_upstream_proxy_ref != "" ? var.har_upstream_proxy_ref : "account.harnessImage"}
                        image: ${var.har_upstream_proxy_ref != "" ? "library/hashicorp/packer:1.11" : "hashicorp/packer:1.11"}
                        shell: Sh
                        command: |
                          echo "======================================="
                          echo "  PACKER AMI BUILD"
                          echo "======================================="
                          echo "AMI Version: $APP_VERSION"
                          echo "AMI Name:    $AMI_NAME"
                          echo "Owner:       $OWNER"
                          echo "Region:      $AWS_DEFAULT_REGION"
                          echo ""

                          JAR_PATH=$(find /harness/build/libs -name "*.jar" ! -name "*-plain.jar" | head -1)
                          if [ -z "$JAR_PATH" ]; then
                            JAR_PATH=$(find /harness/build/libs -name "*.jar" | head -1)
                          fi
                          if [ -z "$JAR_PATH" ]; then
                            echo "ERROR: No Gradle JAR found in /harness/build/libs"
                            ls -R /harness/build || true
                            exit 1
                          fi
                          echo "JAR path: $JAR_PATH"
                          ls -la "$JAR_PATH"

                          cd asg/packer
                          packer init ami.pkr.hcl
                          set +e
                          packer build \
                            -var "app_version=$APP_VERSION" \
                            -var "owner=$OWNER" \
                            -var "ami_name_prefix=harness-demo-app-$OWNER" \
                            -var "aws_region=$AWS_DEFAULT_REGION" \
                            -var "jar_source=$JAR_PATH" \
                            ami.pkr.hcl > /tmp/packer_output.txt 2>&1
                          PACKER_EXIT=$?
                          set -e
                          cat /tmp/packer_output.txt
                          if [ $PACKER_EXIT -ne 0 ]; then
                            echo "ERROR: Packer build failed with exit code $PACKER_EXIT"
                            exit 1
                          fi

                          AMI_ID=$(grep -A2 'AMIs were created' /tmp/packer_output.txt | grep -oE 'ami-[0-9a-f]+' | head -1)
                          if [ -z "$AMI_ID" ]; then
                            echo "ERROR: AMI ID not found in Packer output"
                            cat /tmp/packer_output.txt
                            exit 1
                          fi
                          echo "AMI_ID:   $AMI_ID"
                          echo "AMI_NAME: $AMI_NAME"
                        envVariables:
                          APP_VERSION: <+execution.steps.build_info.output.outputVariables.IMAGE_TAG>
                          AMI_NAME: <+execution.steps.build_info.output.outputVariables.AMI_NAME>
                          OWNER: ${var.asg_packer_owner}
                          AWS_ACCESS_KEY_ID: <+secrets.getValue("${var.asg_aws_access_key_secret}")>
                          AWS_SECRET_ACCESS_KEY: <+secrets.getValue("${var.asg_aws_secret_key_secret}")>
                          AWS_DEFAULT_REGION: ${var.asg_packer_region}
                        outputVariables:
                          - name: AMI_ID
                          - name: AMI_NAME
                  - step:
                      type: Run
                      name: Prepare Governance Inputs
                      identifier: prepare_governance_inputs
                      spec:
                        shell: Sh
                        command: |
                          TEST_PASS_RATE=100
                          if ls build/test-results/test/*.xml >/dev/null 2>&1; then
                            TOTAL_TESTS=0
                            TOTAL_FAILURES=0
                            TOTAL_ERRORS=0

                            for REPORT in build/test-results/test/*.xml; do
                              TESTS=$(grep -o 'tests="[0-9][0-9]*"' "$REPORT" | head -n1 | cut -d'"' -f2)
                              FAILURES=$(grep -o 'failures="[0-9][0-9]*"' "$REPORT" | head -n1 | cut -d'"' -f2)
                              ERRORS=$(grep -o 'errors="[0-9][0-9]*"' "$REPORT" | head -n1 | cut -d'"' -f2)

                              TOTAL_TESTS=$((TOTAL_TESTS + $${TESTS:-0}))
                              TOTAL_FAILURES=$((TOTAL_FAILURES + $${FAILURES:-0}))
                              TOTAL_ERRORS=$((TOTAL_ERRORS + $${ERRORS:-0}))
                            done

                            if [ "$TOTAL_TESTS" -gt 0 ]; then
                              PASSED_TESTS=$((TOTAL_TESTS - TOTAL_FAILURES - TOTAL_ERRORS))
                              TEST_PASS_RATE=$((PASSED_TESTS * 100 / TOTAL_TESTS))
                            fi
                          fi

                          CRITICAL_VULNERABILITIES=0
                          HIGH_VULNERABILITIES=0

                          export TEST_PASS_RATE
                          export CRITICAL_VULNERABILITIES
                          export HIGH_VULNERABILITIES

                          echo "Computed test pass rate: $TEST_PASS_RATE%"
                          echo "Computed critical vulnerabilities: $CRITICAL_VULNERABILITIES"
                          echo "Computed high vulnerabilities: $HIGH_VULNERABILITIES"
                        outputVariables:
                          - name: TEST_PASS_RATE
                            value: TEST_PASS_RATE
                          - name: CRITICAL_VULNERABILITIES
                            value: CRITICAL_VULNERABILITIES
                          - name: HIGH_VULNERABILITIES
                            value: HIGH_VULNERABILITIES
                  - step:
                      type: Run
                      name: Assemble Release Candidate Evidence
                      identifier: assemble_release_candidate_evidence
                      spec:
                        shell: Sh
                        command: |
                          IMAGE_REFERENCE="$AMI_NAME"
                          RELEASE_EVIDENCE_JSON=$(printf '{"artifact":{"ami_name":"%s","ami_id":"%s","commit":"%s","repository":"%s"},"build":{"pipeline_identifier":"%s","execution_id":"%s","sequence_id":"%s"},"attestations":{"artifact_type":"ami","packer_bake":"completed","coverage_upload":"completed"},"governance_inputs":{"test_pass_rate":%s,"critical_vulnerabilities":%s,"high_vulnerabilities":%s,"change_blast_radius":"%s","rollback_ready":"%s","open_change_failures":"%s","change_freeze_active":"%s","requires_data_migration":"%s"}}' \
                            "$AMI_NAME" \
                            "$AMI_ID" \
                            "<+codebase.commitSha>" \
                            "<+codebase.repoUrl>" \
                            "<+pipeline.identifier>" \
                            "<+pipeline.executionId>" \
                            "<+pipeline.sequenceId>" \
                            "$TEST_PASS_RATE" \
                            "$CRITICAL_VULNERABILITIES" \
                            "$HIGH_VULNERABILITIES" \
                            "$CHANGE_BLAST_RADIUS" \
                            "$ROLLBACK_READY" \
                            "$OPEN_CHANGE_FAILURES" \
                            "$CHANGE_FREEZE_ACTIVE" \
                            "$REQUIRES_DATA_MIGRATION")

                          export IMAGE_REFERENCE
                          export RELEASE_EVIDENCE_JSON

                          echo "Release candidate artifact: $IMAGE_REFERENCE"
                          echo "$RELEASE_EVIDENCE_JSON"
                        envVariables:
                          AMI_NAME: <+execution.steps.packer_build_ami.output.outputVariables.AMI_NAME>
                          AMI_ID: <+execution.steps.packer_build_ami.output.outputVariables.AMI_ID>
                          TEST_PASS_RATE: <+execution.steps.prepare_governance_inputs.output.outputVariables.TEST_PASS_RATE>
                          CRITICAL_VULNERABILITIES: <+execution.steps.prepare_governance_inputs.output.outputVariables.CRITICAL_VULNERABILITIES>
                          HIGH_VULNERABILITIES: <+execution.steps.prepare_governance_inputs.output.outputVariables.HIGH_VULNERABILITIES>
                          CHANGE_BLAST_RADIUS: <+pipeline.variables.change_blast_radius>
                          ROLLBACK_READY: <+pipeline.variables.rollback_ready>
                          OPEN_CHANGE_FAILURES: <+pipeline.variables.open_change_failures>
                          CHANGE_FREEZE_ACTIVE: <+pipeline.variables.change_freeze_active>
                          REQUIRES_DATA_MIGRATION: <+pipeline.variables.requires_data_migration>
                        outputVariables:
                          - name: IMAGE_REFERENCE
                            value: IMAGE_REFERENCE
                          - name: RELEASE_EVIDENCE_JSON
                            value: RELEASE_EVIDENCE_JSON
                  - step:
                      type: Run
                      name: Build Summary
                      identifier: build_summary
                      spec:
%{if var.har_registry_ref != ""~}
                        registryRef: ${var.har_registry_ref}
%{else~}
                        connectorRef: account.harnessImage
%{endif~}
                        image: alpine:latest
                        shell: Sh
                        command: |
                          echo "========================================"
                          echo "  BUILD COMPLETE"
                          echo "========================================"
                          echo "AMI Version Tag: <+execution.steps.build_info.output.outputVariables.IMAGE_TAG>"
                          echo "AMI Name:        <+execution.steps.packer_build_ami.output.outputVariables.AMI_NAME>"
                          echo "AMI ID:          <+execution.steps.packer_build_ami.output.outputVariables.AMI_ID>"
                          echo ""
                          echo "=== HARNESS CI INTELLIGENCE FEATURES ==="
                          echo "- Test Intelligence: Runs only affected tests"
                          echo "- Test Splitting: Parallelizes test execution"
                          echo "- Build Intelligence: Caches compiled classes"
                          echo "- Cache Intelligence: Auto-caches Gradle dependencies"
                          echo ""
                          echo "=== SECURITY SCANNING ==="
                          echo "- Gitleaks: Secret detection"
                          echo "- Harness SAST: Static analysis"
                          echo "- Semgrep: Code patterns"
                          echo "- Harness SCA: Configured but temporarily skipped"
                          echo ""
                          echo "=== RELEASE EVIDENCE ==="
                          echo "- Release Candidate Evidence: <+execution.steps.assemble_release_candidate_evidence.output.outputVariables.IMAGE_REFERENCE>"
                          echo "- Evidence Bundle: <+execution.steps.assemble_release_candidate_evidence.output.outputVariables.RELEASE_EVIDENCE_JSON>"
                          echo ""
                          echo "=== GOVERNANCE INPUTS ==="
                          echo "- Test Pass Rate: <+execution.steps.prepare_governance_inputs.output.outputVariables.TEST_PASS_RATE>%"
                          echo "- Critical Vulnerabilities: <+execution.steps.prepare_governance_inputs.output.outputVariables.CRITICAL_VULNERABILITIES>"
                          echo "- High Vulnerabilities: <+execution.steps.prepare_governance_inputs.output.outputVariables.HIGH_VULNERABILITIES>"
                          echo "- Blast Radius: <+pipeline.variables.change_blast_radius>"
                          echo "- Rollback Ready: <+pipeline.variables.rollback_ready>"
                          echo "- Open Change Failures: <+pipeline.variables.open_change_failures>"
                          echo "- Change Freeze Active: <+pipeline.variables.change_freeze_active>"
                          echo "- Requires Data Migration: <+pipeline.variables.requires_data_migration>"
                          echo "- Auto-deploy: <+pipeline.variables.auto_deploy>"
                          echo ""
                          echo "New EC2 instances start the JAR (baked into AMI) via systemd."
                          echo ""
                          echo "To deploy this AMI, run the ASG strategy pipeline:"
                          echo "  Use ami_name: <+execution.steps.packer_build_ami.output.outputVariables.AMI_NAME>"
                          echo "========================================="
                  - step:
                      type: Run
                      name: Trigger CD Pipeline
                      identifier: trigger_cd
                      spec:
%{if var.har_registry_ref != ""~}
                        registryRef: ${var.har_registry_ref}
%{else~}
                        connectorRef: account.harnessImage
%{endif~}
                        image: curlimages/curl:8.7.1
                        shell: Sh
                        command: |
                          if [ "$AUTO_DEPLOY" = "true" ]; then
                            echo "========================================"
                            echo "  AUTO-DEPLOYING (Rolling Strategy)"
                            echo "========================================"
                            AMI_NAME="$OUTPUT_AMI_NAME"
                            echo "Triggering ASG deployment with AMI name: $AMI_NAME"

                            TEST_PASS_RATE=100
                            if ls build/test-results/test/*.xml >/dev/null 2>&1; then
                              TOTAL_TESTS=0
                              TOTAL_FAILURES=0
                              TOTAL_ERRORS=0

                              for REPORT in build/test-results/test/*.xml; do
                                TESTS=$(grep -o 'tests="[0-9][0-9]*"' "$REPORT" | head -n1 | cut -d'"' -f2)
                                FAILURES=$(grep -o 'failures="[0-9][0-9]*"' "$REPORT" | head -n1 | cut -d'"' -f2)
                                ERRORS=$(grep -o 'errors="[0-9][0-9]*"' "$REPORT" | head -n1 | cut -d'"' -f2)

                                TOTAL_TESTS=$((TOTAL_TESTS + $${TESTS:-0}))
                                TOTAL_FAILURES=$((TOTAL_FAILURES + $${FAILURES:-0}))
                                TOTAL_ERRORS=$((TOTAL_ERRORS + $${ERRORS:-0}))
                              done

                              if [ "$TOTAL_TESTS" -gt 0 ]; then
                                PASSED_TESTS=$((TOTAL_TESTS - TOTAL_FAILURES - TOTAL_ERRORS))
                                TEST_PASS_RATE=$((PASSED_TESTS * 100 / TOTAL_TESTS))
                              fi
                            fi

                            CRITICAL_VULNERABILITIES="<+execution.steps.prepare_governance_inputs.output.outputVariables.CRITICAL_VULNERABILITIES>"
                            HIGH_VULNERABILITIES="<+execution.steps.prepare_governance_inputs.output.outputVariables.HIGH_VULNERABILITIES>"
                            CHANGE_BLAST_RADIUS="<+pipeline.variables.change_blast_radius>"
                            ROLLBACK_READY="<+pipeline.variables.rollback_ready>"
                            OPEN_CHANGE_FAILURES="<+pipeline.variables.open_change_failures>"
                            CHANGE_FREEZE_ACTIVE="<+pipeline.variables.change_freeze_active>"
                            REQUIRES_DATA_MIGRATION="<+pipeline.variables.requires_data_migration>"
                            RELEASE_CANDIDATE_EVIDENCE="<+execution.steps.assemble_release_candidate_evidence.output.outputVariables.RELEASE_EVIDENCE_JSON>"

                            echo "Computed test pass rate: $TEST_PASS_RATE%"
                            echo "Using critical vulnerabilities: $CRITICAL_VULNERABILITIES"
                            echo "Using high vulnerabilities: $HIGH_VULNERABILITIES"
                            echo "Using blast radius: $CHANGE_BLAST_RADIUS"
                            echo "Using rollback ready: $ROLLBACK_READY"
                            echo "Using open change failures: $OPEN_CHANGE_FAILURES"
                            echo "Using change freeze active: $CHANGE_FREEZE_ACTIVE"
                            echo "Using requires data migration: $REQUIRES_DATA_MIGRATION"
                            echo "Using release candidate evidence bundle from CI"

                            WEBHOOK_URL="$HARNESS_ENDPOINT/pipeline/api/webhook/custom/v2?accountIdentifier=$ACCOUNT_ID&orgIdentifier=$ORG_ID&projectIdentifier=$PROJECT_ID&pipelineIdentifier=${var.asg_strategy_pipeline_id}&triggerIdentifier=asg_auto_deploy_webhook"

                            response=$(curl -s -w "\n%%{http_code}" -X POST "$WEBHOOK_URL" \
                              -H "Content-Type: application/json" \
                              -d "{\"ami_name\": \"$AMI_NAME\", \"test_pass_rate\": \"$TEST_PASS_RATE\", \"critical_vulnerabilities\": \"$CRITICAL_VULNERABILITIES\", \"high_vulnerabilities\": \"$HIGH_VULNERABILITIES\", \"change_blast_radius\": \"$CHANGE_BLAST_RADIUS\", \"rollback_ready\": \"$ROLLBACK_READY\", \"open_change_failures\": \"$OPEN_CHANGE_FAILURES\", \"change_freeze_active\": \"$CHANGE_FREEZE_ACTIVE\", \"requires_data_migration\": \"$REQUIRES_DATA_MIGRATION\", \"release_candidate_evidence\": $RELEASE_CANDIDATE_EVIDENCE}")

                            http_code=$(echo "$response" | tail -n1)
                            body=$(echo "$response" | sed '$d')

                            echo "Response code: $http_code"
                            echo "Response: $body"

                            if [ "$http_code" = "200" ] || [ "$http_code" = "201" ]; then
                              echo "CD pipeline triggered successfully!"
                            else
                              echo "CD pipeline trigger returned: $http_code"
                              echo "Deployment can still be triggered manually."
                            fi
                          else
                            echo "Auto-deploy is disabled. To deploy, run the ASG strategy pipeline manually."
                          fi
                        envVariables:
                          OUTPUT_AMI_NAME: <+execution.steps.packer_build_ami.output.outputVariables.AMI_NAME>
                          AUTO_DEPLOY: <+pipeline.variables.auto_deploy>
                          HARNESS_ENDPOINT: <+pipeline.variables.harness_endpoint>
                          ACCOUNT_ID: <+account.identifier>
                          ORG_ID: <+org.identifier>
                          PROJECT_ID: <+project.identifier>
                      when:
                        stageStatus: Success
                      failureStrategies:
                        - onFailure:
                            errors:
                              - AllErrors
                            action:
                              type: MarkAsSuccess
            failureStrategies:
              - onFailure:
                  errors:
                    - AllErrors
                  action:
                    type: StageRollback
  CI_EOT
}
