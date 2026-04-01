################################################################################
# EKS Stack - Harness Entities for Kubernetes Deployments
#
# This stack provisions Harness entities for deploying to an EXISTING EKS cluster.
# It does NOT create the EKS cluster itself - use shared-infra/eks-cluster for that.
#
# Use Cases:
#   #1 - SE Sandbox: Deploy to shared EKS cluster in same Harness account
#   #2 - POV-in-a-Box: Deploy to shared EKS cluster, customer Harness account
#
# Prerequisites:
#   - Existing EKS cluster (from shared-infra or external)
#   - Existing delegate with IRSA role (from shared-infra)
#   - Harness org/project (can be created by this stack or pre-existing)
################################################################################
