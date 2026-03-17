################################################################################
# CI Pipeline for Demo App
# Builds Docker image and pushes to Harness Artifact Registry (HAR)
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
      properties:
        ci:
          codebase:
            connectorRef: ${var.git_connector_ref}
            repoName: ${var.git_repo_name}
            build: <+input>
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
                          echo "Trigger: <+pipeline.triggerType>"
                          echo "Branch: <+codebase.branch>"
                          echo "Commit: <+codebase.commitSha>"
                          echo "Commit Message: <+codebase.commitMessage>"
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
                      type: BuildAndPushToHar
                      name: Build and Push to HAR
                      identifier: build_push_har
                      spec:
                        connectorRef: account.harnessImage
                        registry: ${var.har_registry_ref}
                        imageName: ${var.har_image_name}
                        tags:
                          - <+execution.steps.build_info.output.outputVariables.IMAGE_TAG>
                          - latest
                        dockerfile: Dockerfile
                        context: .
                        optimize: true
                      when:
                        stageStatus: Success
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
  CI_EOT
}
