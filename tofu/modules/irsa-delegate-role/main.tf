################################################################################
# IRSA Delegate Role Module
# Creates IAM role for Harness Delegate with IRSA and cross-account STS support
################################################################################

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

################################################################################
# OIDC Provider Data (from existing EKS cluster)
################################################################################

data "aws_eks_cluster" "cluster" {
  name = var.cluster_name
}

data "aws_iam_openid_connect_provider" "cluster" {
  url = data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer
}

################################################################################
# Auto-detect if IRSA role already exists (handles EntityAlreadyExists)
# This covers the case where a previous destroyer run couldn't delete the
# role (e.g., delegate lacked IAM permissions) and state was lost.
################################################################################

data "aws_iam_roles" "existing_delegate" {
  name_regex = "^${var.name_prefix}-delegate-irsa-role$"
}

data "aws_iam_role" "existing" {
  count = local.should_adopt ? 1 : 0
  name  = "${var.name_prefix}-delegate-irsa-role"
}

locals {
  oidc_provider_arn = data.aws_iam_openid_connect_provider.cluster.arn
  oidc_provider_url = replace(data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer, "https://", "")
  account_id        = data.aws_caller_identity.current.account_id

  # Auto-detect: if the role already exists in AWS, adopt it instead of creating
  role_preexists = length(data.aws_iam_roles.existing_delegate.names) > 0
  should_adopt   = local.role_preexists || var.import_existing_role
  should_create  = !local.should_adopt

  # Use existing role if adopting, otherwise use the created role
  role_arn  = local.should_adopt ? data.aws_iam_role.existing[0].arn : aws_iam_role.delegate[0].arn
  role_name = local.should_adopt ? data.aws_iam_role.existing[0].name : aws_iam_role.delegate[0].name
  role_id   = local.should_adopt ? data.aws_iam_role.existing[0].id : aws_iam_role.delegate[0].id
}

################################################################################
# IAM Role for Delegate (IRSA)
################################################################################

resource "aws_iam_role" "delegate" {
  # Only create if role doesn't already exist in AWS
  count = local.should_create ? 1 : 0
  name  = "${var.name_prefix}-delegate-irsa-role"

  # Trust policy allows EKS OIDC provider to assume role via IRSA (for delegate pods)
  # Note: Self-assume is added via aws_iam_role_policy after role creation
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = local.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${local.oidc_provider_url}:aud" = "sts.amazonaws.com"
            "${local.oidc_provider_url}:sub" = "system:serviceaccount:${var.delegate_namespace}:${var.delegate_service_account}"
          }
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name  = "${var.name_prefix}-delegate-irsa-role"
    Owner = var.owner
  })
}

################################################################################
# Update Trust Policy to Add Self-Assume (after role creation)
# This is needed for Harness AWS connector cross-account access
################################################################################

resource "aws_iam_role_policy" "self_assume" {
  name = "delegate-self-assume"
  role = local.role_id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AllowSelfAssume"
        Effect   = "Allow"
        Action   = "sts:AssumeRole"
        Resource = local.role_arn
      }
    ]
  })
}

################################################################################
# Base AWS Permissions for Delegate
################################################################################

resource "aws_iam_role_policy" "delegate_base" {
  name = "delegate-base-permissions"
  role = local.role_id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Sid      = "DescribeRegions"
          Effect   = "Allow"
          Action   = ["ec2:DescribeRegions"]
          Resource = "*"
        },
        {
          Sid    = "ECRReadOnly"
          Effect = "Allow"
          Action = [
            "ecr:GetAuthorizationToken",
            "ecr:BatchCheckLayerAvailability",
            "ecr:GetDownloadUrlForLayer",
            "ecr:BatchGetImage",
            "ecr:DescribeRepositories",
            "ecr:ListImages",
            "ecr:DescribeImages"
          ]
          Resource = "*"
        },
        {
          Sid    = "EKSDescribe"
          Effect = "Allow"
          Action = [
            "eks:DescribeCluster",
            "eks:ListClusters"
          ]
          Resource = "*"
        }
      ],
      # ECR Push - only if ECR repos specified
      length(var.ecr_repository_arns) > 0 ? [
        {
          Sid    = "ECRPush"
          Effect = "Allow"
          Action = [
            "ecr:InitiateLayerUpload",
            "ecr:UploadLayerPart",
            "ecr:CompleteLayerUpload",
            "ecr:PutImage"
          ]
          Resource = var.ecr_repository_arns
        }
      ] : [],
      # S3 Access - only if S3 buckets specified
      length(var.s3_bucket_arns) > 0 ? [
        {
          Sid    = "S3Access"
          Effect = "Allow"
          Action = [
            "s3:GetObject",
            "s3:PutObject",
            "s3:ListBucket",
            "s3:DeleteObject"
          ]
          Resource = concat(
            [for bucket in var.s3_bucket_arns : bucket],
            [for bucket in var.s3_bucket_arns : "${bucket}/*"]
          )
        }
      ] : []
    )
  })
}

################################################################################
# Cross-Account STS AssumeRole Permission
################################################################################

resource "aws_iam_role_policy" "delegate_cross_account" {
  count = length(var.cross_account_role_arns) > 0 ? 1 : 0

  name = "delegate-cross-account-sts"
  role = local.role_id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AssumeRoleCrossAccount"
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Resource = var.cross_account_role_arns
      }
    ]
  })
}

################################################################################
# Optional: ECS Permissions (for ECS deployments)
################################################################################

resource "aws_iam_role_policy" "delegate_ecs" {
  count = var.enable_ecs_permissions ? 1 : 0

  name = "delegate-ecs-permissions"
  role = local.role_id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECSDeployment"
        Effect = "Allow"
        Action = [
          "ecs:DescribeClusters",
          "ecs:DescribeServices",
          "ecs:DescribeTaskDefinition",
          "ecs:DescribeTasks",
          "ecs:ListClusters",
          "ecs:ListServices",
          "ecs:ListTaskDefinitions",
          "ecs:ListTasks",
          "ecs:RegisterTaskDefinition",
          "ecs:DeregisterTaskDefinition",
          "ecs:CreateService",
          "ecs:UpdateService",
          "ecs:DeleteService",
          "ecs:RunTask",
          "ecs:StopTask",
          "ecs:TagResource"
        ]
        Resource = "*"
      },
      {
        Sid    = "ECSPassRole"
        Effect = "Allow"
        Action = "iam:PassRole"
        Resource = "*"
        Condition = {
          StringLike = {
            "iam:PassedToService" = "ecs-tasks.amazonaws.com"
          }
        }
      }
    ]
  })
}

################################################################################
# Optional: ASG Permissions (for ASG deployments)
################################################################################

resource "aws_iam_role_policy" "delegate_asg" {
  count = var.enable_asg_permissions ? 1 : 0

  name = "delegate-asg-permissions"
  role = local.role_id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ASGDeployment"
        Effect   = "Allow"
        Action   = ["autoscaling:*"]
        Resource = "*"
      },
      {
        Sid      = "EC2Full"
        Effect   = "Allow"
        Action   = ["ec2:*"]
        Resource = "*"
      },
      {
        Sid      = "ALBManagement"
        Effect   = "Allow"
        Action   = ["elasticloadbalancing:*"]
        Resource = "*"
      },
      {
        Sid      = "IAMPassRole"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = "*"
      }
    ]
  })
}

################################################################################
# Optional: Lambda Permissions (for Lambda deployments)
################################################################################

resource "aws_iam_role_policy" "delegate_lambda" {
  count = var.enable_lambda_permissions ? 1 : 0

  name = "delegate-lambda-permissions"
  role = local.role_id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "LambdaDeployment"
        Effect = "Allow"
        Action = [
          "lambda:GetFunction",
          "lambda:CreateFunction",
          "lambda:UpdateFunctionCode",
          "lambda:UpdateFunctionConfiguration",
          "lambda:PublishVersion",
          "lambda:CreateAlias",
          "lambda:UpdateAlias",
          "lambda:ListAliases",
          "lambda:ListVersionsByFunction",
          "lambda:GetAlias",
          "lambda:DeleteFunction",
          "lambda:InvokeFunction",
          "lambda:TagResource"
        ]
        Resource = "*"
      },
      {
        Sid    = "LambdaPassRole"
        Effect = "Allow"
        Action = "iam:PassRole"
        Resource = "*"
        Condition = {
          StringLike = {
            "iam:PassedToService" = "lambda.amazonaws.com"
          }
        }
      }
    ]
  })
}
