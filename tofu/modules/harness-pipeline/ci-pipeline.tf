################################################################################
# CI Pipeline for Demo App
# Builds Docker image and pushes to Harness Artifact Registry (HAR)
# Uses GitClone step for public repos (no connector required)
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
        - name: git_branch
          type: String
          description: Git branch to build
          required: true
          value: <+input>.default(main)
        - name: git_repo_url
          type: String
          description: Git repository URL
          required: true
          value: <+input>.default(https://github.com/${var.git_repo_name}.git)
      stages:
        - stage:
            name: Build and Push
            identifier: build_and_push
            description: Build Docker image and push to Harness Artifact Registry
            type: CI
            spec:
              cloneCodebase: false
              platform:
                os: Linux
                arch: Amd64
              runtime:
                type: Cloud
                spec: {}
              execution:
                steps:
                  - step:
                      type: GitClone
                      name: Clone Repository
                      identifier: clone_repo
                      spec:
                        repoName: demo-app
                        cloneDirectory: /harness/demo-app
                        build:
                          type: branch
                          spec:
                            branch: <+pipeline.variables.git_branch>
                        url: <+pipeline.variables.git_repo_url>
                  - step:
                      type: Run
                      name: Build Info
                      identifier: build_info
                      spec:
                        shell: Bash
                        command: |
                          cd /harness/demo-app
                          echo "========================================"
                          echo "  BUILD INFORMATION"
                          echo "========================================"
                          echo "Pipeline: <+pipeline.name>"
                          echo "Build Number: <+pipeline.sequenceId>"
                          echo "Branch: <+pipeline.variables.git_branch>"
                          echo "Repo: <+pipeline.variables.git_repo_url>"
                          echo "========================================"
                          
                          # Set image tag based on branch and build number
                          if [ "<+pipeline.variables.git_branch>" = "main" ]; then
                            IMAGE_TAG="<+pipeline.sequenceId>"
                          else
                            BRANCH_SAFE=$(echo "<+pipeline.variables.git_branch>" | sed 's/[^a-zA-Z0-9]/-/g')
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
                        connectorRef: account.harnessImage
                        repo: app.harness.io/${var.har_registry_ref}/${var.har_image_name}
                        tags:
                          - <+execution.steps.build_info.output.outputVariables.IMAGE_TAG>
                          - latest
                        dockerfile: /harness/demo-app/Dockerfile
                        context: /harness/demo-app
                        optimize: true
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
            failureStrategies:
              - onFailure:
                  errors:
                    - AllErrors
                  action:
                    type: StageRollback
  CI_EOT
}
