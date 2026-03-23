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

locals {
  oidc_provider_arn = data.aws_iam_openid_connect_provider.cluster.arn
  oidc_provider_url = replace(data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer, "https://", "")
  account_id        = data.aws_caller_identity.current.account_id
}

################################################################################
# IAM Role for Delegate (IRSA)
################################################################################

resource "aws_iam_role" "delegate" {
  name = "${var.name_prefix}-delegate-irsa-role"

  # Trust policy allows:
  # 1. EKS OIDC provider to assume role via IRSA (for delegate pods)
  # 2. Self-assume for Harness AWS connector cross-account access (required for AmazonMachineImage artifact type)
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
      },
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${local.account_id}:role/${var.name_prefix}-delegate-irsa-role"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(var.tags, {
    Name  = "${var.name_prefix}-delegate-irsa-role"
    Owner = var.owner
  })
}

################################################################################
# Base AWS Permissions for Delegate
################################################################################

resource "aws_iam_role_policy" "delegate_base" {
  name = "delegate-base-permissions"
  role = aws_iam_role.delegate.id

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
          Sid      = "STSAssumeRoleSelf"
          Effect   = "Allow"
          Action   = "sts:AssumeRole"
          Resource = aws_iam_role.delegate.arn
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
  role = aws_iam_role.delegate.id

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
  role = aws_iam_role.delegate.id

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
  role = aws_iam_role.delegate.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ASGDeployment"
        Effect = "Allow"
        Action = ["autoscaling:*"]
        Resource = "*"
      },
      {
        Sid    = "LaunchTemplateManagement"
        Effect = "Allow"
        Action = [
          "ec2:CreateLaunchTemplate",
          "ec2:CreateLaunchTemplateVersion",
          "ec2:DescribeLaunchTemplates",
          "ec2:DescribeLaunchTemplateVersions",
          "ec2:DeleteLaunchTemplate",
          "ec2:DeleteLaunchTemplateVersions",
          "ec2:ModifyLaunchTemplate",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeImages",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeVpcs",
          "ec2:RunInstances",
          "ec2:TerminateInstances",
          "ec2:CreateTags"
        ]
        Resource = "*"
      },
      {
        Sid    = "ALBManagement"
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:DescribeRules",
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeTargetHealth",
          "elasticloadbalancing:ModifyListener",
          "elasticloadbalancing:ModifyRule",
          "elasticloadbalancing:RegisterTargets",
          "elasticloadbalancing:DeregisterTargets"
        ]
        Resource = "*"
      },
      {
        Sid      = "ASGPassRole"
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
  role = aws_iam_role.delegate.id

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
