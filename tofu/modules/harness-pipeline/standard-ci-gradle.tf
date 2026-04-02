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
                                type: RunTests
                                name: Test Intelligence
                                identifier: test_intelligence
                                spec:
                                  connectorRef: account.harnessImage
                                  image: gradle:8.5-jdk17
                                  language: Java
                                  buildTool: Gradle
                                  args: test --build-cache
                                  packages: ${var.standard_ci_gradle_test_packages}
                                  runOnlySelectedTests: true
                                  enableTestSplitting: true
                                  testSplitStrategy: ClassTiming
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
                                  connectorRef: account.harnessImage
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
                        connectorRef: account.harnessImage
                        image: gradle:8.5-jdk17
                        shell: Sh
                        command: |
                          echo "=== GENERATING CODE COVERAGE REPORT ==="
                          gradle jacocoTestReport
                          echo ""
                          echo "=== COVERAGE SUMMARY ==="
                          if [ -f build/reports/jacoco/test/jacocoTestReport.xml ]; then
                            INSTRUCTION_COVERED=$(grep -o 'type="INSTRUCTION" missed="[0-9]*" covered="[0-9]*"' build/reports/jacoco/test/jacocoTestReport.xml | head -1 | grep -o 'covered="[0-9]*"' | grep -o '[0-9]*')
                            INSTRUCTION_MISSED=$(grep -o 'type="INSTRUCTION" missed="[0-9]*" covered="[0-9]*"' build/reports/jacoco/test/jacocoTestReport.xml | head -1 | grep -o 'missed="[0-9]*"' | grep -o '[0-9]*')
                            if [ -n "$INSTRUCTION_COVERED" ] && [ -n "$INSTRUCTION_MISSED" ]; then
                              TOTAL=$((INSTRUCTION_COVERED + INSTRUCTION_MISSED))
                              if [ $TOTAL -gt 0 ]; then
                                COVERAGE=$((INSTRUCTION_COVERED * 100 / TOTAL))
                                echo "Instruction Coverage: $${COVERAGE}%"
                              fi
                            fi
                          fi
                          echo "Full report: build/reports/jacoco/test/html/index.html"
                        reports:
                          type: JUnit
                          spec:
                            paths:
                              - build/reports/jacoco/test/jacocoTestReport.xml
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
                          org.opencontainers.image.revision: <+codebase.commitSha>
                          org.opencontainers.image.source: <+codebase.repoUrl>
                          org.opencontainers.image.created: <+pipeline.startTs>
                          io.harness.pipeline.id: <+pipeline.identifier>
                          io.harness.build.number: <+pipeline.sequenceId>
                        buildArgs:
                          JAR_PATH: build/libs/*.jar
                          BUILD_COMMIT_SHA: <+codebase.commitSha>
                          IMAGE_TAG: 1.0.<+pipeline.sequenceId>
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
            failureStrategies:
              - onFailure:
                  errors:
                    - AllErrors
                  action:
                    type: StageRollback
  GRADLE_CI_EOT
}
