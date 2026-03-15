################################################################################
# Harness Delegate Module
# Deploys a Harness Delegate to an EKS cluster using Helm
# Supports IRSA, dynamic versioning, and owner-based namespacing
################################################################################

locals {
  # Namespace includes owner suffix for isolation
  namespace = var.create_namespace ? "harness-delegate-ng-${var.owner}" : var.namespace
  
  # Service account name - matches what the Helm chart creates
  service_account_name = "${var.delegate_name}-${var.owner}"
  
  # Resolve delegate image - use provided or fetch latest
  delegate_image = var.delegate_image != "" ? var.delegate_image : (
    var.delegate_version != "" ? "${var.delegate_image_prefix}:${var.delegate_version}" : null
  )
}

################################################################################
# Fetch Latest Delegate Version (if not provided)
################################################################################

data "http" "delegate_version" {
  count = var.delegate_image == "" && var.delegate_version == "" && var.fetch_latest_version ? 1 : 0
  
  url = "${var.harness_manager_endpoint}/ng/api/delegate-setup/latest-supported-version?accountIdentifier=${var.harness_account_id}"
  
  request_headers = {
    "x-api-key" = var.harness_api_key
  }
}

locals {
  # Parse version from API response or use default
  fetched_version = try(
    regex("\"data\":\"([0-9]{2}\\.[0-9]{2}\\.[0-9]{5})\"", data.http.delegate_version[0].response_body)[0],
    ""
  )
  
  final_delegate_image = coalesce(
    local.delegate_image,
    local.fetched_version != "" ? "${var.delegate_image_prefix}:${local.fetched_version}" : "${var.delegate_image_prefix}:latest"
  )
}

################################################################################
# Namespace with Owner Label
################################################################################

resource "kubernetes_namespace" "delegate" {
  count = var.create_namespace ? 1 : 0

  metadata {
    name = local.namespace

    labels = {
      "app.kubernetes.io/managed-by" = "tofu"
      "harness.io/component"         = "delegate"
      "owner"                         = var.owner
    }
  }
}

################################################################################
# IRSA Annotation on Helm-created Service Account
# Applied after Helm creates the SA (named {delegate_name}-{owner})
################################################################################

resource "kubernetes_annotations" "delegate_irsa" {
  count = var.irsa_role_arn != "" && var.create_delegate ? 1 : 0

  api_version = "v1"
  kind        = "ServiceAccount"

  metadata {
    name      = local.service_account_name
    namespace = var.create_namespace ? kubernetes_namespace.delegate[0].metadata[0].name : var.namespace
  }

  annotations = {
    "eks.amazonaws.com/role-arn" = var.irsa_role_arn
  }

  depends_on = [helm_release.delegate]
}

################################################################################
# Cluster Admin RBAC (Optional - for POV convenience)
################################################################################

resource "kubernetes_cluster_role_binding" "delegate_admin" {
  count = var.grant_cluster_admin ? 1 : 0

  metadata {
    name = "harness-delegate-admin-${var.owner}"
    
    labels = {
      "owner" = var.owner
    }
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }

  subject {
    kind      = "ServiceAccount"
    name      = local.service_account_name
    namespace = var.create_namespace ? kubernetes_namespace.delegate[0].metadata[0].name : var.namespace
  }
}

################################################################################
# Delegate Token Secret
################################################################################

resource "kubernetes_secret" "delegate_token" {
  metadata {
    name      = "harness-delegate-token-${var.owner}"
    namespace = var.create_namespace ? kubernetes_namespace.delegate[0].metadata[0].name : var.namespace
    
    labels = {
      "owner" = var.owner
    }
  }

  data = {
    DELEGATE_TOKEN  = var.delegate_token
    UPGRADER_TOKEN  = var.delegate_token
  }

  type = "Opaque"
}

################################################################################
# Helm Release
################################################################################

resource "helm_release" "delegate" {
  count = var.create_delegate ? 1 : 0

  name       = "${var.delegate_name}-${var.owner}"
  namespace  = var.create_namespace ? kubernetes_namespace.delegate[0].metadata[0].name : var.namespace
  repository = "https://app.harness.io/storage/harness-download/delegate-helm-chart/"
  chart      = "harness-delegate-ng"
  version    = var.delegate_helm_version

  values = [
    yamlencode({
      delegateName        = "${var.delegate_name}-${var.owner}"
      accountId           = var.harness_account_id
      delegateToken       = var.delegate_token
      managerEndpoint     = var.harness_manager_endpoint
      delegateDockerImage = local.final_delegate_image
      replicas            = var.delegate_replicas
      
      # Service account created by the Helm chart (same name used for IRSA)
      k8sServiceAccount   = local.service_account_name
      
      upgrader = {
        enabled = var.enable_upgrader
      }

      resources = {
        limits = {
          cpu    = var.delegate_cpu_limit
          memory = var.delegate_memory_limit
        }
        requests = {
          cpu    = var.delegate_cpu_request
          memory = var.delegate_memory_request
        }
      }

      delegateType = "KUBERNETES"
      
      k8sPermissionsType = var.k8s_permissions_type

      initScript = var.init_script
      
      # Tags for delegate selection
      delegateTags = join(",", concat(
        [var.owner, var.delegate_name],
        var.delegate_tags
      ))
    })
  ]

  # Do not wait for pod readiness - delegate connects to Harness asynchronously
  # and may take several minutes to register. Monitor via Harness UI or kubectl logs.
  wait    = false
  timeout = 600

  depends_on = [
    kubernetes_secret.delegate_token,
    kubernetes_namespace.delegate
  ]
}
