################################################################################
# CI Pipeline for Demo App
# Builds Docker image and pushes to Harness Artifact Registry (HAR)
# Supports both GitHub (with connectorRef) and Harness Code (without connectorRef)
#
# HARNESS CI INTELLIGENCE FEATURES:
# - Test Intelligence: Runs only tests affected by code changes (up to 90% faster)
# - Cache Intelligence: Auto-caches Maven dependencies (.m2/repository)
# - Docker Layer Caching: Reuses Docker image layers for faster builds
# - Harness Cloud: Hosted build infrastructure with resource classes
# - OPA Policy Integration: Enforces CI standards and governance
################################################################################

locals {
  # Validate that we have a valid codebase source
  has_valid_codebase = var.use_harness_code || (var.git_connector_ref != "" && var.git_repo_name != "")

  # Effective repo name - use harness_code_repo_name if set, otherwise derive from git_repo_name
  effective_harness_code_repo_name = var.harness_code_repo_name != "" ? var.harness_code_repo_name : var.git_repo_name

  # Codebase configuration differs between GitHub and Harness Code
  # GitHub requires connectorRef + repoName; Harness Code only needs repoName
  ci_codebase_github = chomp(<<-EOT
          codebase:
            connectorRef: ${var.git_connector_ref}
            repoName: ${var.git_repo_name}
            build: <+input>
            sparseCheckout: []
EOT
  )

  ci_codebase_harness_code = chomp(<<-EOT
          codebase:
            repoName: ${local.effective_harness_code_repo_name}
            build: <+input>
            sparseCheckout: []
EOT
  )

  # Use Harness Code if specified, otherwise use GitHub (with validation)
  ci_codebase_spec = var.use_harness_code ? local.ci_codebase_harness_code : (
    local.has_valid_codebase ? local.ci_codebase_github : local.ci_codebase_harness_code
  )
}

resource "harness_platform_pipeline" "ci_build" {
  count       = var.create_ci_pipeline ? 1 : 0
  identifier  = var.ci_pipeline_id
  name        = var.ci_pipeline_name
  org_id      = var.org_id
  project_id  = var.project_id
  description = var.ci_pipeline_description
  tags        = ["pipeline-type:ci", "build:docker", "harness-intelligence:enabled", "managed-by:provisioner"]

  yaml = <<-CI_EOT
    pipeline:
      name: ${var.ci_pipeline_name}
      identifier: ${var.ci_pipeline_id}
      projectIdentifier: ${var.project_id}
      orgIdentifier: ${var.org_id}
      description: ${var.ci_pipeline_description}
      tags:
        pipeline-type: ci
        build: docker
        harness-intelligence: enabled
        managed-by: provisioner
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
          description: Number of unresolved release issues to pass into release governance
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
        - name: run_all_tests
          type: String
          description: Override Test Intelligence and run all tests
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
            name: Build and Test
            identifier: build_and_test
            description: "Build, test with Test Intelligence, and push to HAR"
            type: CI
            spec:
              cloneCodebase: true
              caching:
                enabled: true
              platform:
                os: Linux
                arch: Amd64
              runtime:
                type: Cloud
                spec:
                  size: medium
              execution:
                steps:
                  - step:
                      type: Run
                      name: Build Info
                      identifier: build_info
                      spec:
                        shell: Bash
                        command: |
                          echo "╔══════════════════════════════════════════════════════════════╗"
                          echo "║           HARNESS CI - BUILD INFORMATION                     ║"
                          echo "╠══════════════════════════════════════════════════════════════╣"
                          echo "║ Pipeline:     <+pipeline.name>"
                          echo "║ Build Number: <+pipeline.sequenceId>"
                          echo "║ Branch:       <+codebase.branch>"
                          echo "║ Commit:       <+codebase.commitSha>"
                          echo "║ Trigger:      <+pipeline.triggerType>"
                          echo "╠══════════════════════════════════════════════════════════════╣"
                          echo "║ HARNESS CI INTELLIGENCE FEATURES ENABLED:                    ║"
                          echo "║ ✓ Test Intelligence  - Run only affected tests               ║"
                          echo "║ ✓ Cache Intelligence - Auto-cache Maven dependencies         ║"
                          echo "║ ✓ Docker Layer Cache - Reuse image layers                    ║"
                          echo "║ ✓ Harness Cloud      - Hosted build infrastructure           ║"
                          echo "╚══════════════════════════════════════════════════════════════╝"

                          # Set image tag based on branch and build number
                          if [ "<+codebase.branch>" = "main" ]; then
                            IMAGE_TAG="<+pipeline.sequenceId>"
                          else
                            BRANCH_SAFE=$(echo "<+codebase.branch>" | sed 's/[^a-zA-Z0-9]/-/g')
                            IMAGE_TAG="$${BRANCH_SAFE}-<+pipeline.sequenceId>"
                          fi
                          echo ""
                          echo "Image Tag: $IMAGE_TAG"
                        outputVariables:
                          - name: IMAGE_TAG
                  - stepGroup:
                      name: Test with Intelligence
                      identifier: test_with_intelligence
                      steps:
                        - step:
                            type: RunTests
                            name: Run Tests with TI
                            identifier: run_tests_ti
                            spec:
                              connectorRef: ${var.har_upstream_proxy_ref != "" ? var.har_upstream_proxy_ref : "account.harnessImage"}
                              image: ${var.har_upstream_proxy_ref != "" ? "library/maven:3.9-eclipse-temurin-17" : "maven:3.9-eclipse-temurin-17"}
                              language: Java
                              buildTool: Maven
                              args: test -Dmaven.test.failure.ignore=true -DfailIfNoTests=false
                              packages: io.harness.demo
                              runOnlySelectedTests: "<+<+pipeline.variables.run_all_tests> == \"true\" ? false : true>"
                              postCommand: |
                                echo ""
                                echo "╔══════════════════════════════════════════════════════════════╗"
                                echo "║           TEST INTELLIGENCE RESULTS                          ║"
                                echo "╚══════════════════════════════════════════════════════════════╝"
                                echo "Test Intelligence analyzed code changes and selected relevant tests."
                                echo "View the Tests tab for detailed test selection visualization."
                                echo ""
                                # Generate JaCoCo coverage report
                                mvn jacoco:report -q || true
                              reports:
                                type: JUnit
                                spec:
                                  paths:
                                    - "target/surefire-reports/*.xml"
                              enableTestSplitting: false
                            timeout: 15m
                        - step:
                            type: Run
                            name: Code Coverage Summary
                            identifier: coverage_summary
                            spec:
                              shell: Bash
                              command: |
                                echo "╔══════════════════════════════════════════════════════════════╗"
                                echo "║           CODE COVERAGE REPORT                               ║"
                                echo "╚══════════════════════════════════════════════════════════════╝"
                                if [ -f target/site/jacoco/index.html ]; then
                                  # Extract coverage percentage from JaCoCo report
                                  COVERAGE=$(grep -oP 'Total.*?([0-9]+)%' target/site/jacoco/index.html | head -1 || echo "Coverage data available in JaCoCo report")
                                  echo "Coverage: $COVERAGE"
                                  echo ""
                                  echo "Full report available at: target/site/jacoco/index.html"
                                else
                                  echo "JaCoCo report not generated. Run with tests to see coverage."
                                fi
                            when:
                              stageStatus: Success
                            failureStrategies:
                              - onFailure:
                                  errors:
                                    - AllErrors
                                  action:
                                    type: MarkAsSuccess
                  - step:
                      type: Run
                      name: Build Application
                      identifier: build_app
                      spec:
                        connectorRef: ${var.har_upstream_proxy_ref != "" ? var.har_upstream_proxy_ref : "account.harnessImage"}
                        image: ${var.har_upstream_proxy_ref != "" ? "library/maven:3.9-eclipse-temurin-17" : "maven:3.9-eclipse-temurin-17"}
                        shell: Bash
                        command: |
                          echo "╔══════════════════════════════════════════════════════════════╗"
                          echo "║           BUILDING APPLICATION (with Cache Intelligence)     ║"
                          echo "╚══════════════════════════════════════════════════════════════╝"
                          echo ""
                          echo "Maven is using cached dependencies from ~/.m2/repository"
                          echo "Cache Intelligence automatically manages dependency caching."
                          echo ""
                          
                          # Package the application (tests already ran)
                          mvn package -DskipTests -q
                          
                          echo ""
                          echo "Build artifacts:"
                          ls -la target/*.jar
                          echo ""
                          echo "✓ Application build complete!"
                  - step:
                      type: BuildAndPushDockerRegistry
                      name: Build and Push to HAR
                      identifier: build_push_har
                      spec:
                        repo: ${var.har_image_name}
                        tags:
                          - <+execution.steps.build_info.output.outputVariables.IMAGE_TAG>
                          - latest
                        caching: true
                        dockerfile: Dockerfile
                        context: .
                        optimize: true
                        registryRef: ${var.har_registry_ref}
                  - step:
                      type: Run
                      name: Build Summary
                      identifier: build_summary
                      spec:
                        shell: Bash
                        command: |
                          echo ""
                          echo "╔══════════════════════════════════════════════════════════════╗"
                          echo "║           BUILD COMPLETE - SUMMARY                           ║"
                          echo "╠══════════════════════════════════════════════════════════════╣"
                          echo "║ Image: ${var.har_registry_ref}/${var.har_image_name}"
                          echo "║ Tags:  <+execution.steps.build_info.output.outputVariables.IMAGE_TAG>, latest"
                          echo "╠══════════════════════════════════════════════════════════════╣"
                          echo "║ HARNESS CI INTELLIGENCE SAVINGS:                             ║"
                          echo "║ • Test Intelligence: Only relevant tests executed            ║"
                          echo "║ • Cache Intelligence: Maven deps loaded from cache           ║"
                          echo "║ • Docker Layer Cache: Image layers reused                    ║"
                          echo "╠══════════════════════════════════════════════════════════════╣"
                          echo "║ NEXT STEPS:                                                  ║"
                          echo "║ • Auto-deploy: <+pipeline.variables.auto_deploy>"
                          echo "║ • Manual deploy: Run CD pipeline with tag below              ║"
                          echo "║ • Image Tag: <+execution.steps.build_info.output.outputVariables.IMAGE_TAG>"
                          echo "╚══════════════════════════════════════════════════════════════╝"
                  - step:
                      type: Run
                      name: Trigger CD Pipeline
                      identifier: trigger_cd
                      spec:
                        shell: Bash
                        command: |
                          if [ "$AUTO_DEPLOY" = "true" ]; then
                            echo "╔══════════════════════════════════════════════════════════════╗"
                            echo "║           AUTO-DEPLOYING TO DEV (Canary Strategy)            ║"
                            echo "╚══════════════════════════════════════════════════════════════╝"
                            echo "Triggering deployment with image tag: $IMAGE_TAG"

                            TEST_PASS_RATE=100
                            if ls target/surefire-reports/*.xml >/dev/null 2>&1; then
                              TOTAL_TESTS=0
                              TOTAL_FAILURES=0
                              TOTAL_ERRORS=0

                              for REPORT in target/surefire-reports/*.xml; do
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

                            echo "Computed test pass rate: $TEST_PASS_RATE%"
                            echo "Using blast radius: $CHANGE_BLAST_RADIUS"
                            echo "Using rollback ready: $ROLLBACK_READY"
                            echo "Using open change failures: $OPEN_CHANGE_FAILURES"
                            echo "Using change freeze active: $CHANGE_FREEZE_ACTIVE"
                            echo "Using requires data migration: $REQUIRES_DATA_MIGRATION"
                            
                            # Get the webhook URL for the strategy pipeline trigger
                            WEBHOOK_URL="$HARNESS_ENDPOINT/pipeline/api/webhook/custom/v2?accountIdentifier=$ACCOUNT_ID&orgIdentifier=$ORG_ID&projectIdentifier=$PROJECT_ID&pipelineIdentifier=${var.strategy_pipeline_id}&triggerIdentifier=auto_deploy_webhook"
                            
                            # Trigger the CD pipeline (custom webhooks don't require API key auth)
                            response=$(curl -s -w "\n%%{http_code}" -X POST "$WEBHOOK_URL" \
                              -H "Content-Type: application/json" \
                              -d "{\"image_tag\": \"$IMAGE_TAG\", \"deployment_strategy\": \"canary\", \"test_pass_rate\": \"$TEST_PASS_RATE\", \"critical_vulnerabilities\": \"0\", \"high_vulnerabilities\": \"0\", \"change_blast_radius\": \"$CHANGE_BLAST_RADIUS\", \"rollback_ready\": \"$ROLLBACK_READY\", \"open_change_failures\": \"$OPEN_CHANGE_FAILURES\", \"change_freeze_active\": \"$CHANGE_FREEZE_ACTIVE\", \"requires_data_migration\": \"$REQUIRES_DATA_MIGRATION\"}")
                            
                            http_code=$(echo "$response" | tail -n1)
                            body=$(echo "$response" | sed '$d')
                            
                            if [ "$http_code" = "200" ] || [ "$http_code" = "201" ]; then
                              echo "✓ CD pipeline triggered successfully!"
                              echo "Response: $body"
                            else
                              echo "⚠ CD pipeline trigger returned: $http_code"
                              echo "Deployment can still be triggered manually."
                            fi
                          else
                            echo "Auto-deploy is disabled. To deploy, run a CD pipeline manually."
                          fi
                        envVariables:
                          IMAGE_TAG: <+execution.steps.build_info.output.outputVariables.IMAGE_TAG>
                          CHANGE_BLAST_RADIUS: <+pipeline.variables.change_blast_radius>
                          ROLLBACK_READY: <+pipeline.variables.rollback_ready>
                          OPEN_CHANGE_FAILURES: <+pipeline.variables.open_change_failures>
                          CHANGE_FREEZE_ACTIVE: <+pipeline.variables.change_freeze_active>
                          REQUIRES_DATA_MIGRATION: <+pipeline.variables.requires_data_migration>
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
