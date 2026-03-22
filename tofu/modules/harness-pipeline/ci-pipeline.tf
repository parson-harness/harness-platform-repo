################################################################################
# CI Pipeline for Demo App
# Builds Docker image and pushes to Harness Artifact Registry (HAR)
# Uses native cloneCodebase with Harness Code repository
################################################################################

resource "harness_platform_pipeline" "ci_build" {
  count       = var.create_ci_pipeline ? 1 : 0
  identifier  = var.ci_pipeline_id
  name        = var.ci_pipeline_name
  org_id      = var.org_id
  project_id  = var.project_id
  description = var.ci_pipeline_description
  tags        = ["pipeline-type:ci", "build:docker"]

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
            name: Build and Push
            identifier: build_and_push
            description: Build Docker image and push to Harness Artifact Registry
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
                        connectorRef: ${var.har_upstream_proxy_ref != "" ? var.har_upstream_proxy_ref : "account.harnessImage"}
                        image: ${var.har_upstream_proxy_ref != "" ? "library/maven:3.9-eclipse-temurin-17" : "maven:3.9-eclipse-temurin-17"}
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

                          # Build the application
                          echo "Running: mvn clean package -DskipTests"
                          mvn clean package -DskipTests

                          # Verify JAR was created
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

                          # Set image tag based on branch and build number
                          if [ "<+codebase.branch>" = "main" ]; then
                            IMAGE_TAG="<+pipeline.sequenceId>"
                          else
                            BRANCH_SAFE=$(echo "<+codebase.branch>" | sed 's/[^a-zA-Z0-9]/-/g')
                            IMAGE_TAG="$${BRANCH_SAFE}-<+pipeline.sequenceId>"
                          fi
                          echo "Image Tag: $IMAGE_TAG"
                        envVariables:
                          DOCKER_BUILDKIT: "1"
                        outputVariables:
                          - name: IMAGE_TAG
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
%{if var.asg_packer_build_enabled~}
                  - step:
                      type: Run
                      name: Build AMI with Packer (ASG)
                      identifier: packer_build_ami
                      spec:
                        connectorRef: ${var.har_upstream_proxy_ref != "" ? var.har_upstream_proxy_ref : "account.harnessImage"}
                        image: ${var.har_upstream_proxy_ref != "" ? "library/hashicorp/packer:1.11" : "hashicorp/packer:1.11"}
                        shell: Sh
                        command: |
                          echo "======================================="
                          echo "  PACKER AMI BUILD"
                          echo "======================================="
                          echo "App Version: $APP_VERSION"
                          echo "Owner:       $OWNER"
                          echo "Region:      $AWS_DEFAULT_REGION"
                          echo ""

                          cd asg/packer
                          packer init ami.pkr.hcl
                          packer build \
                            -var "app_version=$$APP_VERSION" \
                            -var "owner=$$OWNER" \
                            -var "ami_name_prefix=harness-demo-app-$$OWNER" \
                            -var "aws_region=$$AWS_DEFAULT_REGION" \
                            -var "jar_source=../../target/harness-demo-app-1.0-SNAPSHOT.jar" \
                            ami.pkr.hcl

                          AMI_ID=$$(aws ec2 describe-images \
                            --owners self \
                            --filters "Name=tag:Application,Values=harness-demo-app-$$OWNER" \
                                      "Name=tag:Version,Values=$$APP_VERSION" \
                            --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
                            --output text)
                          echo "AMI_ID: $$AMI_ID"
                        envVariables:
                          APP_VERSION: <+execution.steps.build_info.output.outputVariables.IMAGE_TAG>
                          OWNER: ${var.asg_packer_owner}
                          AWS_ACCESS_KEY_ID: <+secrets.getValue("${var.asg_aws_access_key_secret}")>
                          AWS_SECRET_ACCESS_KEY: <+secrets.getValue("${var.asg_aws_secret_key_secret}")>
                          AWS_DEFAULT_REGION: ${var.asg_packer_region}
                        outputVariables:
                          - name: AMI_ID
%{endif~}
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
                          echo "Image: ${var.har_registry_ref}/${var.har_image_name}"
                          echo "Tags: <+execution.steps.build_info.output.outputVariables.IMAGE_TAG>, latest"
                          echo ""
                          echo "To deploy this image, run one of the CD pipelines:"
                          echo "  - Strategy Choice Pipeline"
                          echo "  - Blue-Green Pipeline"
                          echo "  - Canary Pipeline"
                          echo ""
                          echo "Use image_tag: <+execution.steps.build_info.output.outputVariables.IMAGE_TAG>"
                          echo "========================================"
                  - step:
                      type: Run
                      name: Trigger CD Pipeline
                      identifier: trigger_cd
                      spec:
                        shell: Bash
                        command: |
                          if [ "$AUTO_DEPLOY" = "true" ]; then
                            echo "========================================"
                            echo "  AUTO-DEPLOYING TO DEV (Canary Strategy)"
                            echo "========================================"
                            echo "Triggering deployment with image tag: $IMAGE_TAG"
                            
                            # Get the webhook URL for the strategy pipeline trigger
                            WEBHOOK_URL="$HARNESS_ENDPOINT/pipeline/api/webhook/custom/v2?accountIdentifier=$ACCOUNT_ID&orgIdentifier=$ORG_ID&projectIdentifier=$PROJECT_ID&pipelineIdentifier=${var.strategy_pipeline_id}&triggerIdentifier=auto_deploy_webhook"
                            
                            echo "Webhook URL: $WEBHOOK_URL"
                            
                            # Trigger the CD pipeline (custom webhooks don't require API key auth)
                            # Strategy pipeline uses canary by default for CI-triggered deployments
                            response=$(curl -s -w "\n%%{http_code}" -X POST "$WEBHOOK_URL" \
                              -H "Content-Type: application/json" \
                              -d "{\"image_tag\": \"$IMAGE_TAG\", \"deployment_strategy\": \"canary\"}")
                            
                            http_code=$(echo "$response" | tail -n1)
                            body=$(echo "$response" | sed '$d')
                            
                            echo "Response code: $http_code"
                            echo "Response: $body"
                            
                            if [ "$http_code" = "200" ] || [ "$http_code" = "201" ]; then
                              echo "✓ CD pipeline triggered successfully!"
                            else
                              echo "⚠ CD pipeline trigger returned: $http_code"
                              echo "Deployment can still be triggered manually."
                            fi
                          else
                            echo "Auto-deploy is disabled. To deploy, run a CD pipeline manually."
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
