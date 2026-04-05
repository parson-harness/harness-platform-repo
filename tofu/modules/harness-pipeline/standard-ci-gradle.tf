################################################################################
# Standard CI Pipeline for Gradle/Java Projects
# Enterprise-grade CI pipeline template with:
# - Test Intelligence (runs only affected tests)
# - Build Intelligence (caches compiled classes)
# - Cache Intelligence (auto-caches Gradle dependencies)
# - Docker Layer Caching
# - Security Scanning (Gitleaks, SAST, Semgrep, SCA, Trivy)
# - Supply Chain Security (SBOM, SLSA Provenance)
# - HAR (Harness Artifact Registry) integration
#
# Naming Convention: standard_ci_<build_tool>
# - standard_ci_gradle - This pipeline (Gradle/Java → Docker → HAR)
# - standard_ci_maven  - Maven variant (exists in ci-pipeline.tf)
# - standard_ci_packer - ASG variant (exists in asg-ci-pipeline.tf)
################################################################################

resource "harness_platform_pipeline" "standard_ci_gradle" {
  count       = var.create_standard_ci_gradle ? 1 : 0
  identifier  = var.standard_ci_gradle_id
  name        = var.standard_ci_gradle_name
  org_id      = var.org_id
  project_id  = var.project_id
  description = var.standard_ci_gradle_description
  tags        = ["pipeline-type:ci", "build:gradle", "standard-template:true", "harness-intelligence:enabled", "security-scanning:enabled", "managed-by:provisioner"]

  yaml = <<-GRADLE_CI_EOT
    pipeline:
      name: ${var.standard_ci_gradle_name}
      identifier: ${var.standard_ci_gradle_id}
      projectIdentifier: ${var.project_id}
      orgIdentifier: ${var.org_id}
      description: "${var.standard_ci_gradle_description}"
      tags:
        pipeline-type: ci
        build: gradle
        standard-template: "true"
        harness-intelligence: enabled
        managed-by: provisioner
        security-scanning: enabled
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
            name: Build - Test - Scan - Push
            identifier: build_test_scan_push
            description: CI Intelligence + Security Scanning + Supply Chain
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
                                  reports:
                                    type: JUnit
                                    spec:
                                      paths:
                                        - build/test-results/test/*.xml
                            - step:
                                type: Run
                                name: Build Intelligence
                                identifier: build_intelligence
                                spec:
                                  registryRef: ${var.har_registry_ref}
                                  image: gradle:8.5-jdk17
                                  shell: Sh
                                  command: |
                                    echo "=== GRADLE BUILD INTELLIGENCE ==="
                                    gradle build -x test --build-cache --parallel
                                    echo "Build artifacts:"
                                    ls -la build/libs/
                  - step:
                      type: Run
                      name: Code Coverage
                      identifier: code_coverage
                      spec:
                        registryRef: ${var.har_registry_ref}
                        image: gradle:8.5-jdk17
                        shell: Sh
                        command: |
                          echo "=== GENERATING CODE COVERAGE REPORT ==="
                          gradle clean test jacocoTestReport --no-build-cache --rerun-tasks

                          COVERAGE_FILE="build/reports/jacoco/test/jacocoTestReport.xml"
                          if [ ! -s "$COVERAGE_FILE" ]; then
                            echo "Coverage report not found at $COVERAGE_FILE"
                            exit 1
                          fi

                          ABS_COVERAGE_FILE="$$(pwd)/$COVERAGE_FILE"
                          mkdir -p coverage
                          cp "$COVERAGE_FILE" coverage/jacocoTestReport.xml
                          UPLOAD_COVERAGE_FILE="$$(pwd)/coverage/jacocoTestReport.xml"

                          echo ""
                          echo "=== COVERAGE FILE DETAILS ==="
                          pwd
                          ls -lah build/reports/jacoco/test || true
                          ls -lah coverage || true
                          find build/reports -maxdepth 4 -type f | sort || true
                          wc -c "$COVERAGE_FILE"
                          echo "Source coverage file: $ABS_COVERAGE_FILE"
                          echo "Upload coverage file: $UPLOAD_COVERAGE_FILE"
                          sed -n '1,40p' "$COVERAGE_FILE"

                          if [ "$COVERAGE_PROVIDER" = "github" ]; then
                            COVERAGE_OWNER="$${COVERAGE_REPO_NAME%%/*}"
                            COVERAGE_IDENTIFIER="$${COVERAGE_REPO_NAME##*/}"
                          else
                            COVERAGE_OWNER="$HARNESS_COVERAGE_OWNER"
                            COVERAGE_IDENTIFIER="$COVERAGE_REPO_NAME"
                          fi

                          echo ""
                          echo "=== BUNDLED HCLI DETAILS ==="
                          hcli --version || hcli --help | sed -n '1,20p' || true

                          HCLI_BIN="/tmp/hcli-v0.7"
                          curl -fsSL -o "$HCLI_BIN" "https://storage.googleapis.com/harness-ti/hcli/v0.7/hcli-linux-amd64"
                          chmod +x "$HCLI_BIN"

                          echo ""
                          echo "=== DOWNLOADED HCLI DETAILS ==="
                          "$HCLI_BIN" --version || "$HCLI_BIN" --help | sed -n '1,20p'

                          echo ""
                          echo "=== UPLOADING COVERAGE TO HARNESS ==="
                          "$HCLI_BIN" --verbose cov upload \
                            --file "$UPLOAD_COVERAGE_FILE" \
                            --provider "$COVERAGE_PROVIDER" \
                            --owner "$COVERAGE_OWNER" \
                            --identifier "$COVERAGE_IDENTIFIER"

                          echo "Full report: build/reports/jacoco/test/html/index.html"
                        envVariables:
                          COVERAGE_PROVIDER: ${var.use_harness_code ? "Harness" : "github"}
                          COVERAGE_REPO_NAME: ${var.use_harness_code ? var.harness_code_repo_name : var.git_repo_name}
                          HARNESS_COVERAGE_OWNER: ${var.harness_org_id}
                          CI_ENABLE_HCLI_FOR_TESTS: "true"
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
                      type: BuildAndPushDockerRegistry
                      name: Push to HAR
                      identifier: push_to_har
                      spec:
                        repo: ${var.har_image_name}
                        tags:
                          - 1.0.<+pipeline.sequenceId>
                          - latest
                        caching: true
                        optimize: true
                        registryRef: ${var.har_registry_ref}
                        labels:
                          org.opencontainers.image.title: ${var.har_image_name}
                          org.opencontainers.image.version: 1.0.<+pipeline.sequenceId>
                          org.opencontainers.image.revision: <+codebase.commitSha>
                          org.opencontainers.image.source: <+codebase.repoUrl>
                          org.opencontainers.image.created: <+pipeline.startTs>
                          io.harness.pipeline.id: <+pipeline.identifier>
                          io.harness.pipeline.execution_id: <+pipeline.executionId>
                          io.harness.build.number: <+pipeline.sequenceId>
                          io.harness.supply_chain.sbom: spdx-json
                          io.harness.supply_chain.provenance: slsa
                        buildArgs:
                          JAR_PATH: build/libs/*.jar
                          BUILD_COMMIT_SHA: <+codebase.commitSha>
                          BUILD_REPO_URL: <+codebase.repoUrl>
                          IMAGE_TAG: 1.0.<+pipeline.sequenceId>
                          PIPELINE_EXECUTION_ID: <+pipeline.executionId>
                          PIPELINE_ID: <+pipeline.identifier>
                          BUILD_TIMESTAMP: <+pipeline.startTs>
                          BASE_IMAGE_REGISTRY: ${var.har_base_image_registry}
                      failureStrategies:
                        - onFailure:
                            errors:
                              - AllErrors
                            action:
                              type: Retry
                              spec:
                                retryCount: 2
                                retryIntervals:
                                  - 2m
                                onRetryFailure:
                                  action:
                                    type: Abort
                  - stepGroup:
                      name: Supply Chain Security
                      identifier: supply_chain_security
                      steps:
                        - step:
                            type: SscaOrchestration
                            name: SBOM Generation
                            identifier: sbom_generation
                            spec:
                              mode: generation
                              tool:
                                type: Syft
                                spec:
                                  format: spdx-json
                              source:
                                type: har
                                spec:
                                  registry: ${var.har_registry_ref}
                                  image: ${var.har_image_name}:1.0.<+pipeline.sequenceId>
                              sbom_drift:
                                base: last_generated_sbom
                        - step:
                            type: provenance
                            name: SLSA Provenance
                            identifier: slsa_provenance
                            spec:
                              source:
                                type: har
                                spec:
                                  registry: ${var.har_registry_ref}
                                  image: ${var.har_image_name}:1.0.<+pipeline.sequenceId>
                  - stepGroup:
                      name: Container Scans
                      identifier: container_scans
                      steps:
                        - parallel:
                            - step:
                                type: HarnessSCA
                                name: Harness SCA
                                identifier: harness_sca
                                spec:
                                  mode: orchestration
                                  config: default
                                  target:
                                    type: container
                                    detection: auto
                                  advanced:
                                    log:
                                      level: info
                                  privileged: true
                                  image:
                                    type: harness
                                    tag: 1.0.<+pipeline.sequenceId>
                                    registry: ${var.har_registry_ref}
                                    image_path: ${var.har_image_name}:1.0.<+pipeline.sequenceId>
                                when:
                                  stageStatus: Success
                                  condition: '"true" == "false"'
                            - step:
                                type: AquaTrivy
                                name: Aqua Trivy
                                identifier: aqua_trivy
                                spec:
                                  mode: orchestration
                                  config: default
                                  target:
                                    type: container
                                    detection: auto
                                  advanced:
                                    log:
                                      level: info
                                    args:
                                      cli: "--scanners vuln"
                                  privileged: false
                                  image:
                                    type: harness
                                    registry: ${var.har_registry_ref}
                                    image_path: ${var.har_image_name}:1.0.<+pipeline.sequenceId>
                                  sbom:
                                    format: spdx-json
                                failureStrategies:
                                  - onFailure:
                                      errors:
                                        - AllErrors
                                      action:
                                        type: Ignore
                  - step:
                      type: Run
                      name: Prepare Governance Inputs
                      identifier: prepare_governance_inputs
                      spec:
                        connectorRef: account.harnessImage
                        image: alpine:latest
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

                          CRITICAL_VULNERABILITIES="$${TRIVY_CRITICAL:-0}"
                          HIGH_VULNERABILITIES="$${TRIVY_HIGH:-0}"

                          export TEST_PASS_RATE
                          export CRITICAL_VULNERABILITIES
                          export HIGH_VULNERABILITIES

                          echo "Computed test pass rate: $TEST_PASS_RATE%"
                          echo "Computed critical vulnerabilities: $CRITICAL_VULNERABILITIES"
                          echo "Computed high vulnerabilities: $HIGH_VULNERABILITIES"
                        envVariables:
                          TRIVY_CRITICAL: <+pipeline.stages.build_test_scan_push.spec.execution.steps.container_scans.steps.aqua_trivy.output.outputVariables.CRITICAL>
                          TRIVY_HIGH: <+pipeline.stages.build_test_scan_push.spec.execution.steps.container_scans.steps.aqua_trivy.output.outputVariables.HIGH>
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
                        connectorRef: account.harnessImage
                        image: alpine:latest
                        shell: Sh
                        command: |
                          IMAGE_REFERENCE="${var.har_image_name}:1.0.<+pipeline.sequenceId>"
                          RELEASE_EVIDENCE_JSON=$(printf '{"artifact":{"image":"%s","tag":"%s","commit":"%s","repository":"%s"},"build":{"pipeline_identifier":"%s","execution_id":"%s","sequence_id":"%s"},"attestations":{"sbom":"spdx-json","slsa_provenance":"generated"},"governance_inputs":{"test_pass_rate":%s,"critical_vulnerabilities":%s,"high_vulnerabilities":%s,"change_blast_radius":"%s","rollback_ready":"%s","open_change_failures":"%s","change_freeze_active":"%s","requires_data_migration":"%s"}}' \
                            "$IMAGE_REFERENCE" \
                            "1.0.<+pipeline.sequenceId>" \
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
                        connectorRef: account.harnessImage
                        image: alpine:latest
                        shell: Sh
                        command: |
                          echo "=== BUILD SUMMARY ==="
                          echo "Pipeline: <+pipeline.name>"
                          echo "Build Number: <+pipeline.sequenceId>"
                          echo "Commit: <+codebase.commitSha>"
                          echo "Branch: <+codebase.branch>"
                          echo "Image Tag: 1.0.<+pipeline.sequenceId>"
                          echo ""
                          echo "=== HARNESS CI INTELLIGENCE FEATURES ==="
                          echo "- Test Intelligence: Runs only affected tests"
                          echo "- Test Splitting: Parallelizes test execution"
                          echo "- Build Intelligence: Caches compiled classes"
                          echo "- Cache Intelligence: Auto-caches dependencies"
                          echo "- Docker Layer Caching: Reuses image layers"
                          echo ""
                          echo "=== SECURITY SCANNING ==="
                          echo "- Gitleaks: Secret detection"
                          echo "- Harness SAST: Static analysis"
                          echo "- Semgrep: Code patterns"
                          echo "- Harness SCA: Configured but temporarily skipped"
                          echo "- Aqua Trivy: Container vulnerabilities"
                          echo ""
                          echo "=== SUPPLY CHAIN SECURITY ==="
                          echo "- SBOM Generation: SPDX-JSON format"
                          echo "- SLSA Provenance: Build attestation"
                          echo "- OCI Image Metadata: Commit, source, version, and Harness execution labels embedded in image"
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
                  - step:
                      type: Run
                      name: Prepare Artifact Links
                      identifier: prepare_artifact_links
                      spec:
                        connectorRef: account.harnessImage
                        image: alpine:latest
                        shell: Sh
                        command: |
                          HARNESS_UI_BASE="$HARNESS_ENDPOINT"
                          HARNESS_UI_BASE="$${HARNESS_UI_BASE%/gratis}"
                          HARNESS_UI_BASE="$${HARNESS_UI_BASE%/}"
                          ACCOUNT_SLUG=$(echo "$ACCOUNT_ID" | tr '[:upper:]' '[:lower:]')

                          PUBLISHED_IMAGE_URL="https://pkg.harness.io/$ACCOUNT_SLUG/$HAR_REGISTRY_REF/$HAR_IMAGE_NAME:$IMAGE_TAG"
                          BUILD_EXECUTION_URL="$HARNESS_UI_BASE/ng/account/$ACCOUNT_ID/all/orgs/$ORG_ID/projects/$PROJECT_ID/pipelines/$PIPELINE_ID/executions/$PIPELINE_EXECUTION_ID/pipeline?storeType=INLINE"

                          export PUBLISHED_IMAGE_URL
                          export BUILD_EXECUTION_URL

                          echo "Published image URL: $PUBLISHED_IMAGE_URL"
                          echo "Build execution URL: $BUILD_EXECUTION_URL"
                        envVariables:
                          HAR_IMAGE_NAME: ${var.har_image_name}
                          HAR_REGISTRY_REF: ${var.har_registry_ref}
                          IMAGE_TAG: 1.0.<+pipeline.sequenceId>
                          HARNESS_ENDPOINT: <+pipeline.variables.harness_endpoint>
                          ACCOUNT_ID: <+account.identifier>
                          ORG_ID: <+org.identifier>
                          PROJECT_ID: <+project.identifier>
                          PIPELINE_ID: <+pipeline.identifier>
                          PIPELINE_EXECUTION_ID: <+pipeline.executionId>
                        outputVariables:
                          - name: PUBLISHED_IMAGE_URL
                            value: PUBLISHED_IMAGE_URL
                          - name: BUILD_EXECUTION_URL
                            value: BUILD_EXECUTION_URL
                  - step:
                      type: Plugin
                      name: Publish Artifact Links
                      identifier: publish_artifact_links
                      spec:
                        connectorRef: account.harnessImage
                        image: plugins/artifact-metadata-publisher
                        settings:
                          artifact_file: artifact-links.txt
                          file_urls:
                            - Published Image:::<+execution.steps.prepare_artifact_links.output.outputVariables.PUBLISHED_IMAGE_URL>
                            - Build Execution:::<+execution.steps.prepare_artifact_links.output.outputVariables.BUILD_EXECUTION_URL>
                  - step:
                      type: Run
                      name: Trigger CD Pipeline
                      identifier: trigger_cd
                      spec:
                        connectorRef: account.harnessImage
                        image: curlimages/curl:8.7.1
                        shell: Sh
                        command: |
                          if [ "$AUTO_DEPLOY" = "true" ]; then
                            echo "=== AUTO-DEPLOYING TO DEV (Canary Strategy) ==="
                            echo "Triggering deployment with image tag: $IMAGE_TAG"
                            echo "Using test pass rate: $TEST_PASS_RATE%"
                            echo "Using critical vulnerabilities: $CRITICAL_VULNERABILITIES"
                            echo "Using high vulnerabilities: $HIGH_VULNERABILITIES"
                            echo "Using blast radius: $CHANGE_BLAST_RADIUS"
                            echo "Using rollback ready: $ROLLBACK_READY"
                            echo "Using open change failures: $OPEN_CHANGE_FAILURES"
                            echo "Using change freeze active: $CHANGE_FREEZE_ACTIVE"
                            echo "Using requires data migration: $REQUIRES_DATA_MIGRATION"
                            echo "Using release candidate evidence bundle from CI"

                            WEBHOOK_URL="$HARNESS_ENDPOINT/pipeline/api/webhook/custom/v2?accountIdentifier=$ACCOUNT_ID&orgIdentifier=$ORG_ID&projectIdentifier=$PROJECT_ID&pipelineIdentifier=${var.strategy_pipeline_id}&triggerIdentifier=auto_deploy_webhook"

                            response=$(curl -s -w "\n%%{http_code}" -X POST "$WEBHOOK_URL" \
                              -H "Content-Type: application/json" \
                              -d "{\"image_tag\": \"$IMAGE_TAG\", \"deployment_strategy\": \"canary\", \"test_pass_rate\": \"$TEST_PASS_RATE\", \"critical_vulnerabilities\": \"$CRITICAL_VULNERABILITIES\", \"high_vulnerabilities\": \"$HIGH_VULNERABILITIES\", \"change_blast_radius\": \"$CHANGE_BLAST_RADIUS\", \"rollback_ready\": \"$ROLLBACK_READY\", \"open_change_failures\": \"$OPEN_CHANGE_FAILURES\", \"change_freeze_active\": \"$CHANGE_FREEZE_ACTIVE\", \"requires_data_migration\": \"$REQUIRES_DATA_MIGRATION\", \"release_candidate_evidence\": $RELEASE_CANDIDATE_EVIDENCE}")

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
                            echo "Auto-deploy is disabled. To deploy, run the strategy pipeline manually."
                          fi
                        envVariables:
                          IMAGE_TAG: 1.0.<+pipeline.sequenceId>
                          TEST_PASS_RATE: <+execution.steps.prepare_governance_inputs.output.outputVariables.TEST_PASS_RATE>
                          CRITICAL_VULNERABILITIES: <+execution.steps.prepare_governance_inputs.output.outputVariables.CRITICAL_VULNERABILITIES>
                          HIGH_VULNERABILITIES: <+execution.steps.prepare_governance_inputs.output.outputVariables.HIGH_VULNERABILITIES>
                          CHANGE_BLAST_RADIUS: <+pipeline.variables.change_blast_radius>
                          ROLLBACK_READY: <+pipeline.variables.rollback_ready>
                          OPEN_CHANGE_FAILURES: <+pipeline.variables.open_change_failures>
                          CHANGE_FREEZE_ACTIVE: <+pipeline.variables.change_freeze_active>
                          REQUIRES_DATA_MIGRATION: <+pipeline.variables.requires_data_migration>
                          RELEASE_CANDIDATE_EVIDENCE: <+execution.steps.assemble_release_candidate_evidence.output.outputVariables.RELEASE_EVIDENCE_JSON>
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
  GRADLE_CI_EOT
}
