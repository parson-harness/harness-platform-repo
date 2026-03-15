################################################################################
# Harness Environment and Infrastructure Definition Module
# Creates Environment with Infrastructure definitions for K8s, ECS, etc.
################################################################################

resource "harness_platform_environment" "main" {
  identifier  = var.environment_id
  name        = var.environment_name
  description = var.environment_description
  org_id      = var.org_id
  project_id  = var.project_id
  type        = var.environment_type
  color       = var.environment_color

  yaml = yamlencode({
    environment = {
      name              = var.environment_name
      identifier        = var.environment_id
      description       = var.environment_description
      type              = var.environment_type
      orgIdentifier     = var.org_id
      projectIdentifier = var.project_id
      tags              = { for tag in var.tags : split(":", tag)[0] => try(split(":", tag)[1], "") }

      variables = [
        for v in var.environment_variables : {
          name  = v.name
          type  = v.type
          value = v.value
        }
      ]
    }
  })
}

################################################################################
# Kubernetes Namespace
################################################################################

resource "kubernetes_namespace" "app" {
  count = var.create_k8s_infrastructure && var.create_k8s_namespace ? 1 : 0

  metadata {
    name = var.k8s_namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "harness.io/environment"       = var.environment_id
    }
  }
}

################################################################################
# Kubernetes Infrastructure Definition
################################################################################

resource "harness_platform_infrastructure" "kubernetes" {
  count = var.create_k8s_infrastructure ? 1 : 0
  
  depends_on = [kubernetes_namespace.app]

  identifier      = var.k8s_infra_id
  name            = var.k8s_infra_name
  org_id          = var.org_id
  project_id      = var.project_id
  env_id          = harness_platform_environment.main.identifier
  type            = "KubernetesDirect"
  deployment_type = "Kubernetes"

  yaml = yamlencode({
    infrastructureDefinition = {
      name        = var.k8s_infra_name
      identifier  = var.k8s_infra_id
      description = "Kubernetes infrastructure for ${var.environment_name}"
      tags        = { for tag in var.tags : split(":", tag)[0] => try(split(":", tag)[1], "") }
      orgIdentifier     = var.org_id
      projectIdentifier = var.project_id
      environmentRef    = harness_platform_environment.main.identifier
      deploymentType    = "Kubernetes"
      type              = "KubernetesDirect"
      spec = {
        connectorRef = var.k8s_connector_ref
        namespace    = var.k8s_namespace
        releaseName  = var.k8s_release_name != "" ? var.k8s_release_name : "release-<+INFRA_KEY_SHORT_ID>"
      }
      allowSimultaneousDeployments = var.allow_simultaneous_deployments
    }
  })
}

################################################################################
# ECS Infrastructure Definition
################################################################################

resource "harness_platform_infrastructure" "ecs" {
  count = var.create_ecs_infrastructure ? 1 : 0

  identifier      = var.ecs_infra_id
  name            = var.ecs_infra_name
  org_id          = var.org_id
  project_id      = var.project_id
  env_id          = harness_platform_environment.main.identifier
  type            = "ECS"
  deployment_type = "ECS"

  yaml = yamlencode({
    infrastructureDefinition = {
      name        = var.ecs_infra_name
      identifier  = var.ecs_infra_id
      description = "ECS infrastructure for ${var.environment_name}"
      tags        = { for tag in var.tags : split(":", tag)[0] => try(split(":", tag)[1], "") }
      orgIdentifier     = var.org_id
      projectIdentifier = var.project_id
      environmentRef    = harness_platform_environment.main.identifier
      deploymentType    = "ECS"
      type              = "ECS"
      spec = {
        connectorRef = var.aws_connector_ref
        region       = var.aws_region
        cluster      = var.ecs_cluster_name
      }
      allowSimultaneousDeployments = var.allow_simultaneous_deployments
    }
  })
}

################################################################################
# Serverless Lambda Infrastructure Definition
################################################################################

resource "harness_platform_infrastructure" "lambda" {
  count = var.create_lambda_infrastructure ? 1 : 0

  identifier      = var.lambda_infra_id
  name            = var.lambda_infra_name
  org_id          = var.org_id
  project_id      = var.project_id
  env_id          = harness_platform_environment.main.identifier
  type            = "ServerlessAwsLambda"
  deployment_type = "ServerlessAwsLambda"

  yaml = yamlencode({
    infrastructureDefinition = {
      name        = var.lambda_infra_name
      identifier  = var.lambda_infra_id
      description = "Lambda infrastructure for ${var.environment_name}"
      tags        = { for tag in var.tags : split(":", tag)[0] => try(split(":", tag)[1], "") }
      orgIdentifier     = var.org_id
      projectIdentifier = var.project_id
      environmentRef    = harness_platform_environment.main.identifier
      deploymentType    = "ServerlessAwsLambda"
      type              = "ServerlessAwsLambda"
      spec = {
        connectorRef = var.aws_connector_ref
        region       = var.aws_region
        stage        = var.lambda_stage
      }
      allowSimultaneousDeployments = var.allow_simultaneous_deployments
    }
  })
}
