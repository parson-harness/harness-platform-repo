################################################################################
# ASG CI Pipeline
# Builds Java JAR then bakes it into an AWS AMI using Packer
# Separate from the EKS CI pipeline (which builds Docker images for HAR)
################################################################################

resource "harness_platform_pipeline" "asg_ci_build" {
  count       = var.create_asg_ci_pipeline ? 1 : 0
  identifier  = var.asg_ci_pipeline_id
  name        = var.asg_ci_pipeline_name
  org_id      = var.org_id
  project_id  = var.project_id
  description = var.asg_ci_pipeline_description
  tags        = ["pipeline-type:ci", "build:packer", "deployment:asg"]

  yaml = <<-CI_EOT
    pipeline:
      name: ${var.asg_ci_pipeline_name}
      identifier: ${var.asg_ci_pipeline_id}
      projectIdentifier: ${var.project_id}
      orgIdentifier: ${var.org_id}
      description: ${var.asg_ci_pipeline_description}
      tags:
        pipeline-type: ci
        build: packer
        deployment: asg
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
      properties:
        ci:
          codebase:
            repoName: ${var.harness_code_repo_name}
            build: <+input>
            sparseCheckout: []
      stages:
        - stage:
            name: Build AMI
            identifier: build_ami
            description: Build Java JAR and bake into AWS AMI using Packer
            type: CI
            spec:
              cloneCodebase: true
              platform:
                os: Linux
                arch: Amd64
              runtime:
                type: Cloud
                spec: {}
              execution:
                steps:
                  - step:
                      type: Run
                      name: Build Java App
                      identifier: build_java
                      spec:
                        connectorRef: account.harnessImage
                        image: maven:3.9-eclipse-temurin-17
                        shell: Bash
                        command: |
                          echo "========================================"
                          echo "  BUILDING JAVA APPLICATION"
                          echo "========================================"
                          echo "Java version:"
                          java -version
                          echo ""
                          echo "Maven version:"
                          mvn -version
                          echo ""
                          echo "Running: mvn clean package -DskipTests"
                          mvn clean package -DskipTests
                          ls -la target/*.jar
                          echo "Build complete!"
                  - step:
                      type: Run
                      name: Build Info
                      identifier: build_info
                      spec:
                        shell: Bash
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
                          echo "AMI Version Tag: $IMAGE_TAG"
                        outputVariables:
                          - name: IMAGE_TAG
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
                          echo "Owner:       $OWNER"
                          echo "Region:      $AWS_DEFAULT_REGION"
                          echo ""

                          JAR_PATH=$(find /harness/target -name "*.jar" ! -name "*.original" | head -1)
                          echo "JAR path: $JAR_PATH"
                          ls -la "$JAR_PATH"

                          cd asg/packer
                          packer init ami.pkr.hcl
                          packer build \
                            -var "app_version=$APP_VERSION" \
                            -var "owner=$OWNER" \
                            -var "ami_name_prefix=harness-demo-app-$OWNER" \
                            -var "aws_region=$AWS_DEFAULT_REGION" \
                            -var "jar_source=$JAR_PATH" \
                            ami.pkr.hcl | tee /tmp/packer_output.txt

                          AMI_ID=$(grep -oE 'ami-[0-9a-f]+' /tmp/packer_output.txt | tail -1)
                          if [ -z "$AMI_ID" ]; then
                            echo "ERROR: Packer build failed or AMI ID not found in output"
                            exit 1
                          fi
                          echo "AMI_ID: $AMI_ID"
                        envVariables:
                          APP_VERSION: <+execution.steps.build_info.output.outputVariables.IMAGE_TAG>
                          OWNER: ${var.asg_packer_owner}
                          AWS_ACCESS_KEY_ID: <+secrets.getValue("${var.asg_aws_access_key_secret}")>
                          AWS_SECRET_ACCESS_KEY: <+secrets.getValue("${var.asg_aws_secret_key_secret}")>
                          AWS_DEFAULT_REGION: ${var.asg_packer_region}
                        outputVariables:
                          - name: AMI_ID
                  - step:
                      type: Run
                      name: Build Summary
                      identifier: build_summary
                      spec:
                        shell: Bash
                        command: |
                          echo "========================================"
                          echo "  BUILD COMPLETE"
                          echo "========================================"
                          echo "AMI Version Tag: <+execution.steps.build_info.output.outputVariables.IMAGE_TAG>"
                          echo "AMI ID:          <+execution.steps.packer_build_ami.output.outputVariables.AMI_ID>"
                          echo ""
                          echo "New EC2 instances start the JAR (baked into AMI) via systemd."
                          echo ""
                          echo "To deploy this AMI, run the ASG strategy pipeline:"
                          echo "  Use image_tag: <+execution.steps.build_info.output.outputVariables.IMAGE_TAG>"
                          echo "========================================="
                  - step:
                      type: Run
                      name: Trigger CD Pipeline
                      identifier: trigger_cd
                      spec:
                        shell: Bash
                        command: |
                          if [ "$AUTO_DEPLOY" = "true" ]; then
                            echo "========================================"
                            echo "  AUTO-DEPLOYING (Rolling Strategy)"
                            echo "========================================"
                            echo "Triggering ASG deployment with image tag: $IMAGE_TAG"

                            WEBHOOK_URL="$HARNESS_ENDPOINT/pipeline/api/webhook/custom/v2?accountIdentifier=$ACCOUNT_ID&orgIdentifier=$ORG_ID&projectIdentifier=$PROJECT_ID&pipelineIdentifier=${var.asg_strategy_pipeline_id}&triggerIdentifier=asg_auto_deploy_webhook"

                            response=$(curl -s -w "\n%%{http_code}" -X POST "$WEBHOOK_URL" \
                              -H "Content-Type: application/json" \
                              -d "{\"image_tag\": \"$IMAGE_TAG\"}")

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
                          IMAGE_TAG: <+execution.steps.build_info.output.outputVariables.IMAGE_TAG>
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
