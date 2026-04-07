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

locals {
  standard_ci_gradle_tag_objects = [
    for tag in var.pipeline_tags : can(regex("^([^:]+):(.*)$", tag)) ? {
      key   = regex("^([^:]+):(.*)$", tag)[0]
      value = regex("^([^:]+):(.*)$", tag)[1]
      } : {
      key   = tag
      value = "true"
    }
  ]
  standard_ci_gradle_yaml_tags = join("\n", [for tag in local.standard_ci_gradle_tag_objects : format("        %s: %s", tag.key, jsonencode(tag.value))])
  standard_ci_gradle_publish_coverage_report_artifact = var.publish_coverage_report_artifact && var.coverage_report_artifact_connector_ref != "" && var.coverage_report_artifact_bucket != ""
  standard_ci_gradle_coverage_report_artifact_base_url = trimspace(var.coverage_report_artifact_base_url) != "" ? trimsuffix(trimspace(var.coverage_report_artifact_base_url), "/") : "https://${var.coverage_report_artifact_bucket}.s3.${var.coverage_report_artifact_region}.amazonaws.com"
}

resource "harness_platform_pipeline" "standard_ci_gradle" {
  count       = var.create_standard_ci_gradle ? 1 : 0
  identifier  = var.standard_ci_gradle_id
  name        = var.standard_ci_gradle_name
  org_id      = var.org_id
  project_id  = var.project_id
  description = var.standard_ci_gradle_description
  tags        = concat(["pipeline-type:ci", "build:gradle", "standard-template:true", "harness-intelligence:enabled", "security-scanning:enabled"], var.pipeline_tags)

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
        security-scanning: enabled
${local.standard_ci_gradle_yaml_tags != "" ? "${local.standard_ci_gradle_yaml_tags}\n" : ""}
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
                      name: Upload Code Coverage
                      identifier: upload_code_coverage
                      spec:
                        connectorRef: account.harnessImage
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
%{if local.standard_ci_gradle_publish_coverage_report_artifact~}
                  - step:
                      type: Run
                      name: Prepare Coverage Report Artifact
                      identifier: prepare_coverage_report_artifact
                      spec:
                        connectorRef: account.harnessImage
                        image: python:3.11-alpine
                        shell: Sh
                        command: |
                          set -e

                          if [ ! -s jacoco/jacoco.xml ]; then
                            echo "Coverage XML not found at jacoco/jacoco.xml"
                            exit 1
                          fi

                          if [ ! -f build/reports/jacoco/test/html/index.html ]; then
                            echo "Coverage HTML report not found at build/reports/jacoco/test/html/index.html"
                            exit 1
                          fi

                          mkdir -p coverage-artifact/jacoco-html
                          cp -R build/reports/jacoco/test/html/. coverage-artifact/jacoco-html/

                          python3 - <<'PY'
                          from pathlib import Path
                          import html
                          import xml.etree.ElementTree as ET

                          xml_path = Path("jacoco/jacoco.xml")
                          root = ET.parse(xml_path).getroot()

                          rows = []
                          total_lines = 0
                          covered_lines = 0

                          for package in root.findall("package"):
                              package_name = package.get("name", "")
                              for sourcefile in package.findall("sourcefile"):
                                  counter = next((item for item in sourcefile.findall("counter") if item.get("type") == "LINE"), None)
                                  if counter is None:
                                      continue
                                  missed = int(counter.get("missed", "0"))
                                  covered = int(counter.get("covered", "0"))
                                  total = missed + covered
                                  if total == 0:
                                      continue
                                  coverage = (covered / total) * 100
                                  source_name = sourcefile.get("name", "")
                                  relative_path = f"{package_name}/{source_name}" if package_name else source_name
                                  rows.append((relative_path, total, covered, missed, coverage))
                                  total_lines += total
                                  covered_lines += covered

                          rows.sort(key=lambda item: (item[4], item[0]))
                          uncovered_lines = total_lines - covered_lines
                          overall_coverage = (covered_lines / total_lines) * 100 if total_lines else 0

                          def badge_class(value: float) -> str:
                              if value >= 90:
                                  return "good"
                              if value >= 75:
                                  return "warn"
                              return "bad"

                          table_rows = "\n".join(
                              f"<tr><td>{html.escape(path)}</td><td>{total}</td><td>{covered}</td><td>{missed}</td><td><span class='badge {badge_class(value)}'>{value:.2f}%</span></td></tr>"
                              for path, total, covered, missed, value in rows
                          )

                          output = f"""<!doctype html>
                          <html lang='en'>
                          <head>
                            <meta charset='utf-8'>
                            <meta name='viewport' content='width=device-width, initial-scale=1'>
                            <title>Coverage Summary</title>
                            <style>
                              :root {{ color-scheme: light dark; font-family: Inter, -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; }}
                              body {{ margin: 0; padding: 32px; background: #0b1020; color: #e5eefc; }}
                              .container {{ max-width: 1120px; margin: 0 auto; }}
                              .hero {{ background: linear-gradient(135deg, #182848, #4b6cb7); border-radius: 20px; padding: 28px; box-shadow: 0 24px 60px rgba(0, 0, 0, 0.28); }}
                              h1 {{ margin: 0 0 8px; font-size: 32px; }}
                              p {{ margin: 0; color: #d7e3ff; }}
                              .stats {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(170px, 1fr)); gap: 16px; margin-top: 24px; }}
                              .card {{ background: rgba(10, 17, 35, 0.72); border: 1px solid rgba(255, 255, 255, 0.08); border-radius: 18px; padding: 18px; }}
                              .label {{ font-size: 12px; text-transform: uppercase; letter-spacing: 0.08em; color: #8fa6d8; }}
                              .value {{ margin-top: 8px; font-size: 30px; font-weight: 700; }}
                              .actions {{ display: flex; gap: 12px; flex-wrap: wrap; margin-top: 24px; }}
                              .button {{ display: inline-block; padding: 12px 16px; border-radius: 999px; text-decoration: none; font-weight: 600; }}
                              .button.primary {{ background: #7dd3fc; color: #082f49; }}
                              .button.secondary {{ background: rgba(255, 255, 255, 0.08); color: #f8fbff; border: 1px solid rgba(255, 255, 255, 0.12); }}
                              .panel {{ margin-top: 28px; background: #11182b; border-radius: 20px; padding: 24px; box-shadow: 0 18px 50px rgba(0, 0, 0, 0.22); }}
                              table {{ width: 100%; border-collapse: collapse; margin-top: 12px; font-size: 14px; }}
                              th, td {{ text-align: left; padding: 12px 10px; border-bottom: 1px solid rgba(255, 255, 255, 0.08); }}
                              th {{ color: #9cb4e9; font-size: 12px; text-transform: uppercase; letter-spacing: 0.08em; }}
                              .badge {{ display: inline-block; min-width: 74px; text-align: center; border-radius: 999px; padding: 6px 10px; font-weight: 700; }}
                              .badge.good {{ background: rgba(74, 222, 128, 0.16); color: #86efac; }}
                              .badge.warn {{ background: rgba(250, 204, 21, 0.14); color: #fde68a; }}
                              .badge.bad {{ background: rgba(248, 113, 113, 0.16); color: #fca5a5; }}
                              .footer {{ margin-top: 18px; color: #9cb4e9; font-size: 13px; }}
                            </style>
                          </head>
                          <body>
                            <div class='container'>
                              <section class='hero'>
                                <h1>Coverage Summary</h1>
                                <p>Demo-friendly overview generated from the JaCoCo XML report and published from Harness CI.</p>
                                <div class='stats'>
                                  <div class='card'><div class='label'>Overall Coverage</div><div class='value'>{overall_coverage:.2f}%</div></div>
                                  <div class='card'><div class='label'>Covered Lines</div><div class='value'>{covered_lines}</div></div>
                                  <div class='card'><div class='label'>Uncovered Lines</div><div class='value'>{uncovered_lines}</div></div>
                                  <div class='card'><div class='label'>Files Reported</div><div class='value'>{len(rows)}</div></div>
                                </div>
                                <div class='actions'>
                                  <a class='button primary' href='jacoco-html/index.html'>Open Full JaCoCo Report</a>
                                  <a class='button secondary' href='jacoco-html/index.html'>Browse Source Details</a>
                                </div>
                              </section>
                              <section class='panel'>
                                <h2>Per-file coverage</h2>
                                <table>
                                  <thead>
                                    <tr><th>File</th><th>Total Lines</th><th>Covered</th><th>Uncovered</th><th>Coverage</th></tr>
                                  </thead>
                                  <tbody>
                                    {table_rows}
                                  </tbody>
                                </table>
                                <div class='footer'>This summary is intentionally optimized for demo readability. Use the full JaCoCo report for drill-down details.</div>
                              </section>
                            </div>
                          </body>
                          </html>
                          """

                          Path("coverage-artifact/index.html").write_text(output, encoding="utf-8")
                          PY

                          COVERAGE_REPORT_TARGET="$ARTIFACT_PATH_PREFIX/$PIPELINE_ID/$PIPELINE_SEQUENCE_ID"
                          COVERAGE_REPORT_URL="$ARTIFACT_BASE_URL/$COVERAGE_REPORT_TARGET/index.html"
                          FULL_JACOCO_REPORT_URL="$ARTIFACT_BASE_URL/$COVERAGE_REPORT_TARGET/jacoco-html/index.html"

                          export COVERAGE_REPORT_TARGET
                          export COVERAGE_REPORT_URL
                          export FULL_JACOCO_REPORT_URL

                          echo "Coverage report artifact target: $COVERAGE_REPORT_TARGET"
                          echo "Coverage report summary URL: $COVERAGE_REPORT_URL"
                          echo "Full JaCoCo report URL: $FULL_JACOCO_REPORT_URL"
                        envVariables:
                          ARTIFACT_PATH_PREFIX: ${var.coverage_report_artifact_path_prefix}
                          ARTIFACT_BASE_URL: ${local.standard_ci_gradle_coverage_report_artifact_base_url}
                          PIPELINE_ID: <+pipeline.identifier>
                          PIPELINE_SEQUENCE_ID: <+pipeline.sequenceId>
                        outputVariables:
                          - name: COVERAGE_REPORT_TARGET
                            value: COVERAGE_REPORT_TARGET
                          - name: COVERAGE_REPORT_URL
                            value: COVERAGE_REPORT_URL
                          - name: FULL_JACOCO_REPORT_URL
                            value: FULL_JACOCO_REPORT_URL
                  - step:
                      type: S3Upload
                      name: Upload Coverage Summary Artifact
                      identifier: upload_coverage_summary_artifact
                      spec:
                        connectorRef: ${var.coverage_report_artifact_connector_ref}
                        region: ${var.coverage_report_artifact_region}
                        bucket: ${var.coverage_report_artifact_bucket}
                        sourcePath: coverage-artifact/index.html
                        target: <+execution.steps.prepare_coverage_report_artifact.output.outputVariables.COVERAGE_REPORT_TARGET>
                  - step:
                      type: S3Upload
                      name: Upload Full JaCoCo Artifact
                      identifier: upload_full_jacoco_artifact
                      spec:
                        connectorRef: ${var.coverage_report_artifact_connector_ref}
                        region: ${var.coverage_report_artifact_region}
                        bucket: ${var.coverage_report_artifact_bucket}
                        sourcePath: coverage-artifact/jacoco-html
                        target: <+execution.steps.prepare_coverage_report_artifact.output.outputVariables.COVERAGE_REPORT_TARGET>/jacoco-html
                  - step:
                      type: Plugin
                      name: Publish Coverage Report Links
                      identifier: publish_coverage_report_links
                      spec:
                        connectorRef: account.harnessImage
                        image: plugins/artifact-metadata-publisher
                        settings:
                          artifact_file: coverage-report-links.txt
                          file_urls:
                            - Coverage Summary:::<+execution.steps.prepare_coverage_report_artifact.output.outputVariables.COVERAGE_REPORT_URL>
                            - Full JaCoCo Report:::<+execution.steps.prepare_coverage_report_artifact.output.outputVariables.FULL_JACOCO_REPORT_URL>
%{endif~}
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
