################################################################################
# ASG Stack - Harness Entities for EC2 Auto Scaling Group Deployments
#
# This stack provisions:
#   - AWS infrastructure: VPC, ALB, ASG, Launch Template
#   - Harness entities: Service, Environment, Pipelines
#
# Use Cases:
#   - ASG deployments with Blue/Green, Canary, or Rolling strategies
#   - Packer-built AMIs (JAR baked into AMI, no Docker)
#
# Prerequisites:
#   - Existing delegate with IRSA role (from shared-infra)
#   - Harness org/project (can be created by this stack or pre-existing)
################################################################################

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    harness = {
      source  = "harness/harness"
      version = "~> 0.30"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.25"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
  }
}

################################################################################
# Providers
################################################################################

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

provider "harness" {
  endpoint         = var.harness_endpoint
  account_id       = var.harness_account_id
  platform_api_key = var.harness_api_key
}

data "aws_caller_identity" "current" {}

################################################################################
# Data Sources - Shared EKS Cluster (for delegate deployment)
################################################################################

data "aws_eks_cluster" "shared" {
  count = var.create_delegate ? 1 : 0
  name  = var.eks_cluster_name
}

data "aws_eks_cluster_auth" "shared" {
  count = var.create_delegate ? 1 : 0
  name  = var.eks_cluster_name
}

provider "kubernetes" {
  host                   = var.create_delegate ? data.aws_eks_cluster.shared[0].endpoint : ""
  cluster_ca_certificate = var.create_delegate ? base64decode(data.aws_eks_cluster.shared[0].certificate_authority[0].data) : ""
  token                  = var.create_delegate ? data.aws_eks_cluster_auth.shared[0].token : ""
}

provider "helm" {
  kubernetes {
    host                   = var.create_delegate ? data.aws_eks_cluster.shared[0].endpoint : ""
    cluster_ca_certificate = var.create_delegate ? base64decode(data.aws_eks_cluster.shared[0].certificate_authority[0].data) : ""
    token                  = var.create_delegate ? data.aws_eks_cluster_auth.shared[0].token : ""
  }
}

################################################################################
# Local Variables
################################################################################

locals {
  name_prefix           = "harness-demo-${var.owner}"
  delegate_selector     = "delegate-${var.owner}"
  har_registry_id       = "har-${var.owner}"
  har_upstream_proxy_id = "${var.owner}-dockerhub-proxy"
  har_image_name        = "${var.owner}demoapp"
  packer_ci_role_name   = "harness-packer-ci-${var.owner}"
  harness_oidc_provider_url = "app.harness.io/ng/api/oidc/account/${var.harness_account_id}"
  harness_oidc_provider_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${local.harness_oidc_provider_url}"

  common_tags = {
    Project     = "harness-demo"
    Environment = var.environment
    ManagedBy   = "tofu"
    Owner       = var.owner
    Stack       = "asg"
  }

  common_tags_with_workspace = merge(
    local.common_tags,
    var.workspace_id != "" ? {
      WorkspaceId = var.workspace_id
    } : {},
    var.workspace_template_id != "" ? {
      WorkspaceTemplateId = var.workspace_template_id
    } : {}
  )

  asg_alb_name_source      = "${local.name_prefix}-asg-alb"
  asg_prod_tg_name_source  = "${local.name_prefix}-asg-prod-tg"
  asg_stage_tg_name_source = "${local.name_prefix}-asg-stage-tg"
  asg_alb_name             = length(local.asg_alb_name_source) <= 32 ? local.asg_alb_name_source : "${substr(local.asg_alb_name_source, 0, 23)}-${substr(md5(local.asg_alb_name_source), 0, 8)}"
  asg_prod_tg_name         = length(local.asg_prod_tg_name_source) <= 32 ? local.asg_prod_tg_name_source : "${substr(local.asg_prod_tg_name_source, 0, 23)}-${substr(md5(local.asg_prod_tg_name_source), 0, 8)}"
  asg_stage_tg_name        = length(local.asg_stage_tg_name_source) <= 32 ? local.asg_stage_tg_name_source : "${substr(local.asg_stage_tg_name_source, 0, 23)}-${substr(md5(local.asg_stage_tg_name_source), 0, 8)}"
}

################################################################################
# Harness Organization and Project (optional creation)
################################################################################

module "harness_org_project" {
  source = "../../modules/harness-org-project"

  create_organization      = var.create_harness_org
  existing_org_id          = var.harness_org_id
  organization_id          = var.new_harness_org_id
  organization_name        = var.new_harness_org_name
  organization_description = "Reference architecture for Harness CI/CD demonstrations - ${var.owner}"

  create_project      = var.create_harness_project
  existing_project_id = var.harness_project_id
  project_id          = var.new_harness_project_id != "" ? var.new_harness_project_id : "${var.owner}_demo"
  project_name        = var.new_harness_project_name != "" ? var.new_harness_project_name : "${title(var.owner)} Demo"
  project_description = "Demo project for ${var.owner}"

  tags = ["tofu-managed", var.owner, "asg"]
}

locals {
  resolved_org_id     = module.harness_org_project.org_id
  resolved_project_id = module.harness_org_project.project_id
}

module "harness_code_repo" {
  source = "../../modules/harness-code-repo"
  count  = var.use_harness_code ? 1 : 0

  harness_account_id = var.harness_account_id
  org_id             = local.resolved_org_id
  project_id         = local.resolved_project_id

  repo_identifier  = "${var.owner}-demo-app"
  repo_description = "Demo app for ${var.owner} POV - imported from GitHub"
  default_branch   = "main"

  import_from_scm = true
  source_provider = "github"
  source_host     = "https://github.com"
  source_repo     = var.github_repo_name
  source_username = "x-access-token"
  source_password = var.github_repo_is_public ? "" : var.github_pat

  depends_on = [module.harness_org_project]
}

################################################################################
# AWS Infrastructure - VPC, ALB, ASG
################################################################################

resource "terraform_data" "cleanup_existing_asg_named_resources" {
  triggers_replace = {
    recovery_run_id = var.last_touched_at != "" ? var.last_touched_at : var.created_at
  }

  lifecycle {
    create_before_destroy = true
  }

  provisioner "local-exec" {
    interpreter = ["/bin/sh", "-c"]
    command     = <<-EOT
      set +e
      AWS_REGION="${var.aws_region}"
      IAM_AUTH_USER="$${AWS_ACCESS_KEY_ID}:$${AWS_SECRET_ACCESS_KEY}"
      STATE_FILE="${path.root}/terraform.tfstate"
      ASG_PREFIX="${local.name_prefix}-asg"
      ALB_NAME="${local.asg_alb_name}"
      PROD_TG_NAME="${local.asg_prod_tg_name}"
      STAGE_TG_NAME="${local.asg_stage_tg_name}"
      AMI_PREFIX="harness-demo-app-${var.owner}"
      BASE_ASG_NAME="${local.name_prefix}-asg-base"
      LAUNCH_TEMPLATE_NAME="${local.name_prefix}-asg-lt"
      INSTANCE_PROFILE_NAME="${local.name_prefix}-asg-instance-profile"
      INSTANCE_ROLE_NAME="${local.name_prefix}-asg-instance-role"
      VPC_NAME="${local.name_prefix}-asg-vpc"

      STATE_CONTENT=""
      if [ -f "$${STATE_FILE}" ]; then
        STATE_CONTENT=$(tr -d '\n\r\t ' < "$${STATE_FILE}" 2>/dev/null || true)
      fi

      state_tracks_resource() {
        RESOURCE_MODULE="$1"
        RESOURCE_TYPE="$2"
        RESOURCE_NAME="$3"
        RESOURCE_FRAGMENT="\"module\":\"$${RESOURCE_MODULE}\",\"mode\":\"managed\",\"type\":\"$${RESOURCE_TYPE}\",\"name\":\"$${RESOURCE_NAME}\""

        if [ -z "$${STATE_CONTENT}" ]; then
          return 1
        fi

        echo "$${STATE_CONTENT}" | grep -Fq "$${RESOURCE_FRAGMENT}"
      }

      iam_get() {
        curl -s --aws-sigv4 "aws:amz:us-east-1:iam" \
          --user "$${IAM_AUTH_USER}" \
          -H "x-amz-security-token: $${AWS_SESSION_TOKEN}" \
          "https://iam.amazonaws.com/$1"
      }
      iam_post() {
        curl -s --aws-sigv4 "aws:amz:us-east-1:iam" \
          --user "$${IAM_AUTH_USER}" \
          -H "x-amz-security-token: $${AWS_SESSION_TOKEN}" \
          -d "$1" "https://iam.amazonaws.com/"
      }
      autoscaling_post() {
        curl -s --aws-sigv4 "aws:amz:$${AWS_REGION}:autoscaling" \
          --user "$${IAM_AUTH_USER}" \
          -H "x-amz-security-token: $${AWS_SESSION_TOKEN}" \
          -d "$1" "https://autoscaling.$${AWS_REGION}.amazonaws.com/"
      }
      ec2_post() {
        curl -s --aws-sigv4 "aws:amz:$${AWS_REGION}:ec2" \
          --user "$${IAM_AUTH_USER}" \
          -H "x-amz-security-token: $${AWS_SESSION_TOKEN}" \
          -d "$1" "https://ec2.$${AWS_REGION}.amazonaws.com/"
      }
      elbv2_get() {
        curl -s --aws-sigv4 "aws:amz:$${AWS_REGION}:elasticloadbalancing" \
          --user "$${IAM_AUTH_USER}" \
          -H "x-amz-security-token: $${AWS_SESSION_TOKEN}" \
          "https://elasticloadbalancing.$${AWS_REGION}.amazonaws.com/$1"
      }
      elbv2_post() {
        curl -s --aws-sigv4 "aws:amz:$${AWS_REGION}:elasticloadbalancing" \
          --user "$${IAM_AUTH_USER}" \
          -H "x-amz-security-token: $${AWS_SESSION_TOKEN}" \
          -d "$1" "https://elasticloadbalancing.$${AWS_REGION}.amazonaws.com/"
      }

      wait_for_asg_deletion() {
        TARGET_ASG_NAME="$1"
        for _ in $(seq 1 30); do
          RESPONSE=$(autoscaling_post "Action=DescribeAutoScalingGroups&AutoScalingGroupNames.member.1=$${TARGET_ASG_NAME}&Version=2011-01-01" 2>&1)
          if ! echo "$${RESPONSE}" | grep -q "<AutoScalingGroupName>$${TARGET_ASG_NAME}</AutoScalingGroupName>"; then
            return 0
          fi
          sleep 5
        done
        return 0
      }

      wait_for_lb_deletion() {
        for _ in $(seq 1 30); do
          RESPONSE=$(elbv2_get "?Action=DescribeLoadBalancers&Names.member.1=$${ALB_NAME}&Version=2015-12-01" 2>&1)
          if echo "$${RESPONSE}" | grep -q "LoadBalancerNotFound"; then
            return 0
          fi
          if ! echo "$${RESPONSE}" | grep -q "<LoadBalancerArn>"; then
            return 0
          fi
          sleep 5
        done
        return 0
      }

      wait_for_target_group_deletion() {
        TARGET_GROUP_NAME="$1"
        for _ in $(seq 1 30); do
          RESPONSE=$(elbv2_get "?Action=DescribeTargetGroups&Names.member.1=$${TARGET_GROUP_NAME}&Version=2015-12-01" 2>&1)
          if echo "$${RESPONSE}" | grep -q "TargetGroupNotFound"; then
            return 0
          fi
          if ! echo "$${RESPONSE}" | grep -q "<TargetGroupArn>"; then
            return 0
          fi
          sleep 5
        done
        return 0
      }

      delete_target_group_by_name() {
        TARGET_GROUP_NAME="$1"
        TARGET_GROUP_XML=$(elbv2_get "?Action=DescribeTargetGroups&Names.member.1=$${TARGET_GROUP_NAME}&Version=2015-12-01" 2>&1)
        TARGET_GROUP_ARN=$(echo "$${TARGET_GROUP_XML}" | grep -o '<TargetGroupArn>[^<]*</TargetGroupArn>' | sed 's/<[^>]*>//g' | head -1)
        if [ -n "$${TARGET_GROUP_ARN}" ]; then
          elbv2_post "Action=DeleteTargetGroup&TargetGroupArn=$${TARGET_GROUP_ARN}&Version=2015-12-01" >/dev/null 2>&1 || true
          wait_for_target_group_deletion "$${TARGET_GROUP_NAME}"
        fi
      }

      delete_launch_templates_by_prefix() {
        LAUNCH_TEMPLATE_XML=$(ec2_post "Action=DescribeLaunchTemplates&Version=2016-11-15" 2>&1)
        for LAUNCH_TEMPLATE_ID in $(echo "$${LAUNCH_TEMPLATE_XML}" | awk -v prefix="$${ASG_PREFIX}" 'BEGIN{RS="<item>"} /<launchTemplateId>/ && /<launchTemplateName>/ { id=$0; sub(/.*<launchTemplateId>/, "", id); sub(/<.*/, "", id); name=$0; sub(/.*<launchTemplateName>/, "", name); sub(/<.*/, "", name); if (index(name, prefix) == 1) print id }'); do
          ec2_post "Action=DeleteLaunchTemplate&LaunchTemplateId=$${LAUNCH_TEMPLATE_ID}&Version=2016-11-15" >/dev/null 2>&1 || true
        done
      }

      wait_for_launch_template_cleanup() {
        for _ in $(seq 1 30); do
          REMAINING_LAUNCH_TEMPLATES=$(ec2_post "Action=DescribeLaunchTemplates&Version=2016-11-15" 2>&1 | awk -v prefix="$${ASG_PREFIX}" 'BEGIN{RS="<item>"} /<launchTemplateName>/ { name=$0; sub(/.*<launchTemplateName>/, "", name); sub(/<.*/, "", name); if (index(name, prefix) == 1) print name }')
          if [ -z "$${REMAINING_LAUNCH_TEMPLATES}" ]; then
            return 0
          fi
          echo "Retrying launch template cleanup: $${REMAINING_LAUNCH_TEMPLATES}"
          delete_launch_templates_by_prefix
          sleep 10
        done
        return 0
      }

      delete_amis_and_snapshots() {
        AMI_IDS=$(aws ec2 describe-images --owners self --query "Images[?starts_with(Name, '$${AMI_PREFIX}-')].ImageId" --output text 2>/dev/null || true)
        if [ -z "$${AMI_IDS}" ] || [ "$${AMI_IDS}" = "None" ]; then
          return 0
        fi

        for AMI_ID in $${AMI_IDS}; do
          AMI_NAME=$(aws ec2 describe-images --image-ids "$${AMI_ID}" --query 'Images[0].Name' --output text 2>/dev/null || true)
          SNAPSHOT_IDS=$(aws ec2 describe-images --image-ids "$${AMI_ID}" --query 'Images[0].BlockDeviceMappings[?Ebs.SnapshotId!=null].Ebs.SnapshotId' --output text 2>/dev/null || true)
          echo "AMI $${AMI_NAME:-$${AMI_ID}}: deregistering"
          aws ec2 deregister-image --image-id "$${AMI_ID}" 2>/dev/null || true
          if [ -n "$${SNAPSHOT_IDS}" ] && [ "$${SNAPSHOT_IDS}" != "None" ]; then
            for SNAPSHOT_ID in $${SNAPSHOT_IDS}; do
              echo "Snapshot $${SNAPSHOT_ID}: deleting"
              aws ec2 delete-snapshot --snapshot-id "$${SNAPSHOT_ID}" 2>/dev/null || true
            done
          fi
        done
      }

      wait_for_ami_cleanup() {
        for _ in $(seq 1 30); do
          REMAINING_AMIS=$(aws ec2 describe-images --owners self --query "Images[?starts_with(Name, '$${AMI_PREFIX}-')].ImageId" --output text 2>/dev/null || true)
          if [ -z "$${REMAINING_AMIS}" ] || [ "$${REMAINING_AMIS}" = "None" ]; then
            return 0
          fi
          echo "Waiting for AMIs to deregister: $${REMAINING_AMIS}"
          delete_amis_and_snapshots
          sleep 10
        done
        return 0
      }

      get_vpc_id_by_name() {
        VPC_XML=$(ec2_post "Action=DescribeVpcs&Filter.1.Name=tag:Name&Filter.1.Value.1=$${VPC_NAME}&Version=2016-11-15" 2>&1)
        echo "$${VPC_XML}" | grep -o '<vpcId>[^<]*</vpcId>' | sed 's/<[^>]*>//g' | head -1
      }

      cleanup_vpc_dependencies() {
        TARGET_VPC_ID="$1"
        for _ in $(seq 1 30); do
          CURRENT_VPC=$(ec2_post "Action=DescribeVpcs&Filter.1.Name=vpc-id&Filter.1.Value.1=$${TARGET_VPC_ID}&Version=2016-11-15" 2>&1 | grep -o '<vpcId>[^<]*</vpcId>' | sed 's/<[^>]*>//g' | head -1)
          if [ -z "$${CURRENT_VPC}" ]; then
            return 0
          fi

          ENI_XML=$(ec2_post "Action=DescribeNetworkInterfaces&Filter.1.Name=vpc-id&Filter.1.Value.1=$${TARGET_VPC_ID}&Version=2016-11-15" 2>&1)
          if echo "$${ENI_XML}" | grep -q '<networkInterfaceId>'; then
            echo "Waiting for VPC ENIs to detach in $${TARGET_VPC_ID}"
            sleep 10
            continue
          fi

          SECURITY_GROUP_XML=$(ec2_post "Action=DescribeSecurityGroups&Filter.1.Name=vpc-id&Filter.1.Value.1=$${TARGET_VPC_ID}&Version=2016-11-15" 2>&1)
          for GROUP_ID in $(echo "$${SECURITY_GROUP_XML}" | awk 'BEGIN{RS="<item>"} /<groupId>/ && /<groupName>/ { id=$0; sub(/.*<groupId>/, "", id); sub(/<.*/, "", id); name=$0; sub(/.*<groupName>/, "", name); sub(/<.*/, "", name); if (name != "default") print id }'); do
            ec2_post "Action=DeleteSecurityGroup&GroupId=$${GROUP_ID}&Version=2016-11-15" >/dev/null 2>&1 || true
          done

          SUBNET_XML=$(ec2_post "Action=DescribeSubnets&Filter.1.Name=vpc-id&Filter.1.Value.1=$${TARGET_VPC_ID}&Version=2016-11-15" 2>&1)
          for SUBNET_ID in $(echo "$${SUBNET_XML}" | grep -o '<subnetId>[^<]*</subnetId>' | sed 's/<[^>]*>//g'); do
            ec2_post "Action=DeleteSubnet&SubnetId=$${SUBNET_ID}&Version=2016-11-15" >/dev/null 2>&1 || true
          done

          ROUTE_TABLE_XML=$(ec2_post "Action=DescribeRouteTables&Filter.1.Name=vpc-id&Filter.1.Value.1=$${TARGET_VPC_ID}&Version=2016-11-15" 2>&1)
          for ASSOCIATION_ID in $(echo "$${ROUTE_TABLE_XML}" | awk 'BEGIN{RS="<item>"} /<routeTableAssociationId>/ && $0 !~ /<main>true<\/main>/ { id=$0; sub(/.*<routeTableAssociationId>/, "", id); sub(/<.*/, "", id); print id }'); do
            ec2_post "Action=DisassociateRouteTable&AssociationId=$${ASSOCIATION_ID}&Version=2016-11-15" >/dev/null 2>&1 || true
          done
          for ROUTE_TABLE_ID in $(echo "$${ROUTE_TABLE_XML}" | awk 'BEGIN{RS="<item>"} /<routeTableId>/ && $0 !~ /<main>true<\/main>/ { id=$0; sub(/.*<routeTableId>/, "", id); sub(/<.*/, "", id); print id }'); do
            ec2_post "Action=DeleteRouteTable&RouteTableId=$${ROUTE_TABLE_ID}&Version=2016-11-15" >/dev/null 2>&1 || true
          done

          INTERNET_GATEWAY_XML=$(ec2_post "Action=DescribeInternetGateways&Filter.1.Name=attachment.vpc-id&Filter.1.Value.1=$${TARGET_VPC_ID}&Version=2016-11-15" 2>&1)
          for INTERNET_GATEWAY_ID in $(echo "$${INTERNET_GATEWAY_XML}" | grep -o '<internetGatewayId>[^<]*</internetGatewayId>' | sed 's/<[^>]*>//g'); do
            ec2_post "Action=DetachInternetGateway&InternetGatewayId=$${INTERNET_GATEWAY_ID}&VpcId=$${TARGET_VPC_ID}&Version=2016-11-15" >/dev/null 2>&1 || true
            ec2_post "Action=DeleteInternetGateway&InternetGatewayId=$${INTERNET_GATEWAY_ID}&Version=2016-11-15" >/dev/null 2>&1 || true
          done

          ec2_post "Action=DeleteVpc&VpcId=$${TARGET_VPC_ID}&Version=2016-11-15" >/dev/null 2>&1 || true
          sleep 10
        done
        return 0
      }

      if ! state_tracks_resource "module.asg" "aws_autoscaling_group" "base"; then
        ASG_XML=$(autoscaling_post "Action=DescribeAutoScalingGroups&Version=2011-01-01" 2>&1)
        for ASG_NAME in $(echo "$${ASG_XML}" | grep -o '<AutoScalingGroupName>[^<]*</AutoScalingGroupName>' | sed 's/<[^>]*>//g'); do
          case "$${ASG_NAME}" in
            "$${ASG_PREFIX}"*)
              autoscaling_post "Action=UpdateAutoScalingGroup&AutoScalingGroupName=$${ASG_NAME}&MinSize=0&MaxSize=0&DesiredCapacity=0&Version=2011-01-01" >/dev/null 2>&1 || true
              autoscaling_post "Action=DeleteAutoScalingGroup&AutoScalingGroupName=$${ASG_NAME}&ForceDelete=true&Version=2011-01-01" >/dev/null 2>&1 || true
              wait_for_asg_deletion "$${ASG_NAME}"
              ;;
          esac
        done
      fi

      if ! state_tracks_resource "module.asg" "aws_launch_template" "main"; then
        wait_for_launch_template_cleanup
      fi

      if ! state_tracks_resource "module.asg" "aws_lb" "main"; then
        LOAD_BALANCER_XML=$(elbv2_get "?Action=DescribeLoadBalancers&Names.member.1=$${ALB_NAME}&Version=2015-12-01" 2>&1)
        LOAD_BALANCER_ARN=$(echo "$${LOAD_BALANCER_XML}" | grep -o '<LoadBalancerArn>[^<]*</LoadBalancerArn>' | sed 's/<[^>]*>//g' | head -1)
        if [ -n "$${LOAD_BALANCER_ARN}" ]; then
          elbv2_post "Action=DeleteLoadBalancer&LoadBalancerArn=$${LOAD_BALANCER_ARN}&Version=2015-12-01" >/dev/null 2>&1 || true
          wait_for_lb_deletion
        fi
      fi

      if ! state_tracks_resource "module.asg" "aws_lb_target_group" "prod"; then
        delete_target_group_by_name "$${PROD_TG_NAME}"
      fi
      if ! state_tracks_resource "module.asg" "aws_lb_target_group" "stage"; then
        delete_target_group_by_name "$${STAGE_TG_NAME}"
      fi

      if ! state_tracks_resource "module.asg" "aws_iam_instance_profile" "app"; then
        INSTANCE_PROFILE_XML=$(iam_get "?Action=GetInstanceProfile&InstanceProfileName=$${INSTANCE_PROFILE_NAME}&Version=2010-05-08" 2>&1)
        if echo "$${INSTANCE_PROFILE_XML}" | grep -q "<InstanceProfileName>$${INSTANCE_PROFILE_NAME}</InstanceProfileName>"; then
          for ROLE_NAME in $(echo "$${INSTANCE_PROFILE_XML}" | grep -o '<RoleName>[^<]*</RoleName>' | sed 's/<[^>]*>//g'); do
            iam_post "Action=RemoveRoleFromInstanceProfile&InstanceProfileName=$${INSTANCE_PROFILE_NAME}&RoleName=$${ROLE_NAME}&Version=2010-05-08" >/dev/null 2>&1 || true
          done
          iam_post "Action=DeleteInstanceProfile&InstanceProfileName=$${INSTANCE_PROFILE_NAME}&Version=2010-05-08" >/dev/null 2>&1 || true
        fi
      fi

      if ! state_tracks_resource "module.asg" "aws_iam_role" "instance"; then
        INSTANCE_ROLE_XML=$(iam_get "?Action=GetRole&RoleName=$${INSTANCE_ROLE_NAME}&Version=2010-05-08" 2>&1)
        if echo "$${INSTANCE_ROLE_XML}" | grep -q "<RoleName>$${INSTANCE_ROLE_NAME}</RoleName>"; then
          ATTACHED_XML=$(iam_get "?Action=ListAttachedRolePolicies&RoleName=$${INSTANCE_ROLE_NAME}&Version=2010-05-08" 2>&1)
          for ARN in $(echo "$${ATTACHED_XML}" | grep -o '<PolicyArn>[^<]*</PolicyArn>' | sed 's/<[^>]*>//g'); do
            iam_post "Action=DetachRolePolicy&RoleName=$${INSTANCE_ROLE_NAME}&PolicyArn=$${ARN}&Version=2010-05-08" >/dev/null 2>&1 || true
          done

          INLINE_XML=$(iam_get "?Action=ListRolePolicies&RoleName=$${INSTANCE_ROLE_NAME}&Version=2010-05-08" 2>&1)
          for POLICY in $(echo "$${INLINE_XML}" | grep -o '<member>[^<]*</member>' | sed 's/<[^>]*>//g'); do
            iam_post "Action=DeleteRolePolicy&RoleName=$${INSTANCE_ROLE_NAME}&PolicyName=$${POLICY}&Version=2010-05-08" >/dev/null 2>&1 || true
          done

          iam_post "Action=DeleteRole&RoleName=$${INSTANCE_ROLE_NAME}&Version=2010-05-08" >/dev/null 2>&1 || true
        fi
      fi

      if ! state_tracks_resource "module.asg" "aws_ami" "main"; then
        delete_amis_and_snapshots
        wait_for_ami_cleanup
      fi

      if ! state_tracks_resource "module.asg" "aws_vpc" "main"; then
        VPC_ID=$(get_vpc_id_by_name)
        if [ -n "$${VPC_ID}" ]; then
          cleanup_vpc_dependencies "$${VPC_ID}"
        fi
      fi

      exit 0
    EOT
  }
}

module "asg" {
  source = "../../modules/asg"

  name_prefix   = local.name_prefix
  owner         = var.owner
  aws_region    = var.aws_region
  vpc_cidr      = var.vpc_cidr
  instance_type = var.instance_type

  asg_min_size         = var.asg_min_size
  asg_desired_capacity = var.asg_desired_capacity
  asg_max_size         = var.asg_max_size

  create_dns_record = var.create_dns_record
  route53_zone_name = var.route53_zone_name
  acm_cert_arn      = var.acm_cert_arn

  tags = local.common_tags_with_workspace

  depends_on = [terraform_data.cleanup_existing_asg_named_resources]
}

################################################################################
# IAM User + Harness Secrets for Packer CI Builds
################################################################################

resource "terraform_data" "cleanup_existing_packer_ci_user" {
  provisioner "local-exec" {
    interpreter = ["/bin/sh", "-c"]
    command     = <<-EOT
      set +e
      USER_NAME="harness-packer-ci-${var.owner}"
      ROLE_NAME="harness-packer-ci-${var.owner}"
      IAM_ACCESS_KEY_ID="$${AWS_ACCESS_KEY_ID}"
      IAM_SECRET_ACCESS_KEY="$${AWS_SECRET_ACCESS_KEY}"
      IAM_AUTH_USER="$${IAM_ACCESS_KEY_ID}:$${IAM_SECRET_ACCESS_KEY}"

      iam_get() {
        curl -s --aws-sigv4 "aws:amz:us-east-1:iam" \
          --user "$${IAM_AUTH_USER}" \
          -H "x-amz-security-token: $${AWS_SESSION_TOKEN}" \
          "https://iam.amazonaws.com/$1"
      }
      iam_post() {
        curl -s --aws-sigv4 "aws:amz:us-east-1:iam" \
          --user "$${IAM_AUTH_USER}" \
          -H "x-amz-security-token: $${AWS_SESSION_TOKEN}" \
          -d "$1" "https://iam.amazonaws.com/"
      }

      RESPONSE=$(iam_get "?Action=GetUser&UserName=$${USER_NAME}&Version=2010-05-08" 2>&1)
      if echo "$${RESPONSE}" | grep -q "<UserName>"; then
        ACCESS_KEYS_XML=$(iam_get "?Action=ListAccessKeys&UserName=$${USER_NAME}&Version=2010-05-08" 2>&1)
        for KEY_ID in $(echo "$${ACCESS_KEYS_XML}" | grep -o '<AccessKeyId>[^<]*</AccessKeyId>' | sed 's/<[^>]*>//g'); do
          iam_post "Action=DeleteAccessKey&UserName=$${USER_NAME}&AccessKeyId=$${KEY_ID}&Version=2010-05-08" >/dev/null 2>&1 || true
        done

        POLICIES_XML=$(iam_get "?Action=ListUserPolicies&UserName=$${USER_NAME}&Version=2010-05-08" 2>&1)
        for POLICY in $(echo "$${POLICIES_XML}" | grep -o '<member>[^<]*</member>' | sed 's/<[^>]*>//g'); do
          iam_post "Action=DeleteUserPolicy&UserName=$${USER_NAME}&PolicyName=$${POLICY}&Version=2010-05-08" >/dev/null 2>&1 || true
        done

        ATTACHED_XML=$(iam_get "?Action=ListAttachedUserPolicies&UserName=$${USER_NAME}&Version=2010-05-08" 2>&1)
        for ARN in $(echo "$${ATTACHED_XML}" | grep -o '<PolicyArn>[^<]*</PolicyArn>' | sed 's/<[^>]*>//g'); do
          iam_post "Action=DetachUserPolicy&UserName=$${USER_NAME}&PolicyArn=$${ARN}&Version=2010-05-08" >/dev/null 2>&1 || true
        done

        GROUPS_XML=$(iam_get "?Action=ListGroupsForUser&UserName=$${USER_NAME}&Version=2010-05-08" 2>&1)
        for GROUP in $(echo "$${GROUPS_XML}" | grep -o '<GroupName>[^<]*</GroupName>' | sed 's/<[^>]*>//g'); do
          iam_post "Action=RemoveUserFromGroup&UserName=$${USER_NAME}&GroupName=$${GROUP}&Version=2010-05-08" >/dev/null 2>&1 || true
        done

        iam_post "Action=DeleteLoginProfile&UserName=$${USER_NAME}&Version=2010-05-08" >/dev/null 2>&1 || true
        iam_post "Action=DeleteUser&UserName=$${USER_NAME}&Version=2010-05-08" >/dev/null 2>&1 || true
      fi

      ROLE_RESPONSE=$(iam_get "?Action=GetRole&RoleName=$${ROLE_NAME}&Version=2010-05-08" 2>&1)
      if echo "$${ROLE_RESPONSE}" | grep -q "<RoleName>"; then
        ROLE_POLICIES_XML=$(iam_get "?Action=ListRolePolicies&RoleName=$${ROLE_NAME}&Version=2010-05-08" 2>&1)
        for POLICY in $(echo "$${ROLE_POLICIES_XML}" | grep -o '<member>[^<]*</member>' | sed 's/<[^>]*>//g'); do
          iam_post "Action=DeleteRolePolicy&RoleName=$${ROLE_NAME}&PolicyName=$${POLICY}&Version=2010-05-08" >/dev/null 2>&1 || true
        done

        ROLE_ATTACHED_XML=$(iam_get "?Action=ListAttachedRolePolicies&RoleName=$${ROLE_NAME}&Version=2010-05-08" 2>&1)
        for ARN in $(echo "$${ROLE_ATTACHED_XML}" | grep -o '<PolicyArn>[^<]*</PolicyArn>' | sed 's/<[^>]*>//g'); do
          iam_post "Action=DetachRolePolicy&RoleName=$${ROLE_NAME}&PolicyArn=$${ARN}&Version=2010-05-08" >/dev/null 2>&1 || true
        done

        iam_post "Action=DeleteRole&RoleName=$${ROLE_NAME}&Version=2010-05-08" >/dev/null 2>&1 || true
      fi

      exit 0
    EOT
  }
}

resource "aws_iam_role" "packer_ci" {
  name = local.packer_ci_role_name
  tags = local.common_tags_with_workspace

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = local.harness_oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${local.harness_oidc_provider_url}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  depends_on = [terraform_data.cleanup_existing_packer_ci_user]
}

resource "aws_iam_role_policy" "packer_ci" {
  name = "harness-packer-ci-policy"
  role = aws_iam_role.packer_ci.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "PackerAMIBuild"
        Effect = "Allow"
        Action = [
          "ec2:RunInstances",
          "ec2:StopInstances",
          "ec2:TerminateInstances",
          "ec2:CreateImage",
          "ec2:CreateTags",
          "ec2:DeleteTags",
          "ec2:ModifyImageAttribute",
          "ec2:DescribeImages",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceStatus",
          "ec2:DescribeRegions",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeVpcs",
          "ec2:DescribeVolumes",
          "ec2:CreateSecurityGroup",
          "ec2:DeleteSecurityGroup",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:CreateKeyPair",
          "ec2:DeleteKeyPair",
          "ec2:DescribeKeyPairs"
        ]
        Resource = "*"
      }
    ]
  })
}

################################################################################
# Harness Connectors
################################################################################

module "harness_connectors" {
  source = "../../modules/harness-connectors"

  environment_name   = var.environment
  harness_org_id     = local.resolved_org_id
  harness_project_id = local.resolved_project_id
  delegate_selectors = [local.delegate_selector]

  # AWS Connector (for AMI artifact resolution)
  create_aws_connector        = true
  aws_connector_id            = "${var.owner}_aws_reference_architecture"
  aws_connector_name          = "${title(var.owner)} AWS Reference Architecture"
  aws_connector_description   = "AWS connector for ${title(var.owner)} ASG stack"
  connector_tags              = ["tofu-managed:true", "owner:${var.owner}", "stack:asg"]
  aws_auth_type               = var.aws_auth_type
  aws_region                  = var.aws_region
  enable_cross_account_access = var.enable_cross_account_access
  cross_account_role_arn      = var.cross_account_role_arn
  cross_account_external_id   = var.cross_account_external_id

  # GitHub Connector
  create_github_connector = var.github_token_ref != ""
  github_connector_id     = "${var.owner}_github_reference_architecture"
  github_connector_name   = "${title(var.owner)} GitHub Reference Architecture"
  github_url              = var.github_url
  github_username         = var.github_username
  github_token_ref        = var.github_token_ref

  # No K8s or Docker connectors for ASG
  create_k8s_connector    = false
  create_docker_connector = false

  depends_on = [module.harness_org_project]
}

module "har" {
  source = "../../modules/harness-artifact-registry"
  count  = var.artifact_registry_type == "har" ? 1 : 0

  account_id = var.harness_account_id
  org_id     = local.resolved_org_id
  project_id = local.resolved_project_id

  registry_id          = local.har_registry_id
  registry_description = "Docker registry for ${var.owner} demo app"

  create_dockerhub_upstream     = var.create_dockerhub_upstream
  dockerhub_upstream_id         = local.har_upstream_proxy_id
  dockerhub_username            = var.dockerhub_username
  dockerhub_password_secret_ref = var.dockerhub_password_secret_ref
  dockerhub_secret_space_path   = var.harness_account_id

  harness_endpoint = var.harness_endpoint
  harness_api_key  = var.harness_api_key

  depends_on = [module.harness_org_project]
}

################################################################################
# Harness ASG Service
################################################################################

module "harness_service_asg" {
  source = "../../modules/harness-service"

  service_id          = "${var.owner}_demo_app_asg"
  service_name        = "${title(var.owner)} Demo App ASG"
  service_description = "ASG demo application for ${var.owner} - Blue/Green, Canary, Rolling on EC2"
  org_id              = local.resolved_org_id
  project_id          = local.resolved_project_id

  deployment_type = "Asg"

  # ASG artifact = Packer-built AMI
  artifact_registry_type = "ecr" # Uses AWS connector for AMI resolution
  artifact_connector_ref = "${var.owner}_aws_reference_architecture"
  aws_region             = var.aws_region
  asg_ami_owner_tag      = var.owner

  # Startup script in repo
  asg_startup_script_path            = "asg/user-data.sh"
  asg_startup_script_use_file_store  = var.asg_startup_script_use_file_store
  asg_startup_script_local_file_path = "${path.root}/../../../asg/user-data.sh"
  manifest_store_type                = var.use_harness_code ? "HarnessCode" : "Github"
  git_connector_ref = var.use_harness_code ? "" : (
    var.github_token_ref != "" ? "${var.owner}_github_reference_architecture" : var.github_connector_ref
  )
  git_repo_name                        = var.use_harness_code ? "" : var.github_repo_name
  harness_code_repo_name               = var.use_harness_code ? "${var.owner}-demo-app" : ""
  asg_startup_script_use_git           = var.github_token_ref != "" || var.github_connector_ref != ""
  asg_startup_script_git_connector_ref = var.github_token_ref != "" ? "${var.owner}_github_reference_architecture" : var.github_connector_ref
  asg_startup_script_git_repo_name     = var.github_repo_name
  git_branch                           = var.git_branch

  tags = ["tofu-managed", var.owner, "asg"]

  service_variables = [
    {
      name  = "appUrl"
      type  = "String"
      value = module.asg.app_url
    },
    {
      name  = "stageUrl"
      type  = "String"
      value = module.asg.stage_url
    },
    {
      name  = "instanceProfileName"
      type  = "String"
      value = module.asg.instance_profile_name
    },
    {
      name  = "securityGroupId"
      type  = "String"
      value = module.asg.instance_security_group_id
    },
    {
      name  = "subnetIds"
      type  = "String"
      value = join(",", module.asg.public_subnet_ids)
    },
    {
      name  = "baseAsgName"
      type  = "String"
      value = module.asg.base_asg_name
    }
  ]

  depends_on = [module.harness_connectors, module.asg, module.harness_code_repo]
}

################################################################################
# Harness Environment and Infrastructure
################################################################################

module "harness_environment_dev" {
  source = "../../modules/harness-environment"

  environment_id          = "${var.owner}_asg_dev"
  environment_name        = "${title(var.owner)} ASG Dev"
  environment_description = "Development environment for ${var.owner} ASG"
  org_id                  = local.resolved_org_id
  project_id              = local.resolved_project_id
  environment_type        = "PreProduction"

  # ASG infrastructure
  create_asg_infrastructure = true
  asg_infra_id              = "${var.owner}_asg_dev"
  asg_infra_name            = "${title(var.owner)} ASG Dev"
  aws_connector_ref         = "${var.owner}_aws_reference_architecture"
  aws_region                = var.aws_region
  asg_base_asg_name         = module.asg.base_asg_name
  asg_load_balancer_name    = module.asg.alb_name
  asg_prod_listener_arn     = module.asg.prod_listener_arn
  asg_stage_listener_arn    = module.asg.stage_listener_arn

  # No K8s, ECS, or Lambda infrastructure
  create_k8s_infrastructure    = false
  create_ecs_infrastructure    = false
  create_lambda_infrastructure = false

  tags = ["tofu-managed", var.owner, "asg"]

  depends_on = [module.harness_connectors, module.asg]
}

################################################################################
# Harness Pipelines
################################################################################

module "harness_pipelines_asg" {
  source = "../../modules/harness-pipeline"

  org_id     = local.resolved_org_id
  project_id = local.resolved_project_id

  # Required by module but unused for ASG-only pipelines
  service_ref        = ""
  environment_ref    = "${var.owner}_asg_dev"
  environment_name   = "ASG Dev"
  infrastructure_ref = ""

  # ASG strategy pipeline
  create_asg_strategy_pipeline      = var.create_asg_strategy_pipeline
  asg_strategy_pipeline_id          = "${var.owner}_asg_strategy_deploy"
  asg_strategy_pipeline_name        = "${title(var.owner)} Application Delivery - ASG"
  asg_strategy_pipeline_description = "Unified ASG deployment pipeline with runtime strategy selection for customer demos"
  asg_service_ref                   = "${var.owner}_demo_app_asg"
  asg_infrastructure_ref            = "${var.owner}_asg_dev"
  asg_canary_instance_count         = var.asg_canary_instance_count
  asg_prod_asg_name                 = replace(module.asg.base_asg_name, "-base", "")

  # ALB configuration for Blue-Green deployments
  asg_alb_name                = module.asg.alb_name
  asg_prod_listener_arn       = module.asg.prod_listener_arn
  asg_prod_listener_rule_arn  = module.asg.prod_listener_rule_arn
  asg_stage_listener_arn      = module.asg.stage_listener_arn
  asg_stage_listener_rule_arn = module.asg.stage_listener_rule_arn

  # Disable all K8s pipelines
  create_canary_pipeline     = false
  create_blue_green_pipeline = false
  create_strategy_pipeline   = false
  create_ci_pipeline         = false

  # ASG CI pipeline: Gradle + CI Intelligence + security scans → Packer AMI build
  create_asg_ci_pipeline           = var.create_asg_ci_pipeline && (var.use_harness_code || var.github_token_ref != "" || var.github_connector_ref != "")
  asg_ci_pipeline_id               = "${var.owner}_asg_ci_build"
  asg_ci_pipeline_name             = "${title(var.owner)} ASG CI Build"
  asg_ci_pipeline_description      = "Enterprise CI pipeline: Gradle build, Test Intelligence, Security Scanning, and Packer AMI bake"
  git_connector_ref                = var.github_token_ref != "" ? "${var.owner}_github_reference_architecture" : var.github_connector_ref
  git_repo_name                    = var.github_repo_name
  use_harness_code                 = var.use_harness_code
  harness_code_repo_name           = var.use_harness_code ? "${var.owner}-demo-app" : ""
  harness_account_id               = var.harness_account_id
  harness_org_id                   = local.resolved_org_id
  harness_project_id               = local.resolved_project_id
  harness_api_key                  = var.harness_api_key
  standard_ci_gradle_test_packages = var.standard_ci_gradle_test_packages

  asg_packer_owner          = var.owner
  asg_packer_region         = var.aws_region
  asg_aws_oidc_role_arn     = aws_iam_role.packer_ci.arn

  enable_change_governance = var.enable_change_governance
  delegate_selector        = local.delegate_selector
  pipeline_tags            = ["tofu-managed:true", "owner:${var.owner}", "deployment-target:asg", "managed-by:provisioner"]

  har_registry_ref       = var.artifact_registry_type == "har" ? local.har_registry_id : ""
  har_upstream_proxy_ref = var.artifact_registry_type == "har" && var.create_dockerhub_upstream ? local.har_upstream_proxy_id : ""
  har_image_name         = local.har_image_name

  depends_on = [module.harness_service_asg, module.harness_environment_dev, module.harness_code_repo, module.har]
}

################################################################################
# Outputs
################################################################################

output "org_id" {
  description = "Harness organization ID"
  value       = local.resolved_org_id
}

output "project_id" {
  description = "Harness project ID"
  value       = local.resolved_project_id
}

output "service_id" {
  description = "Harness ASG service ID"
  value       = module.harness_service_asg.service_id
}

output "environment_id" {
  description = "Harness environment ID"
  value       = module.harness_environment_dev.environment_id
}

output "app_url" {
  description = "Production application URL"
  value       = module.asg.app_url
}

output "stage_url" {
  description = "Stage application URL"
  value       = module.asg.stage_url
}

output "alb_name" {
  description = "ALB name"
  value       = module.asg.alb_name
}

output "base_asg_name" {
  description = "Base ASG name"
  value       = module.asg.base_asg_name
}

output "prod_asg_name" {
  description = "Production ASG name (Harness-managed)"
  value       = replace(module.asg.base_asg_name, "-base", "")
}

output "delegate_name" {
  description = "Delegate name"
  value       = var.create_delegate ? "delegate-${var.owner}" : null
}

output "delegate_irsa_role_arn" {
  description = "IRSA role ARN for the delegate"
  value       = var.create_delegate ? module.irsa_delegate_role[0].role_arn : null
}

################################################################################
# IRSA Role for Delegate (AWS permissions via service account)
################################################################################

module "irsa_delegate_role" {
  source = "../../modules/irsa-delegate-role"
  count  = var.create_delegate ? 1 : 0

  name_prefix              = local.name_prefix
  owner                    = var.owner
  cluster_name             = var.eks_cluster_name
  delegate_namespace       = "harness-delegate-ng-${var.owner}"
  delegate_service_account = "delegate-${var.owner}"

  # ECR access for CI builds
  ecr_repository_arns = ["*"]

  # Enable ASG deployment permissions
  enable_ecs_permissions    = false
  enable_asg_permissions    = true
  enable_lambda_permissions = false

  tags = local.common_tags_with_workspace
}

################################################################################
# Delegate Token
################################################################################

resource "random_id" "delegate_token_suffix" {
  count       = var.create_delegate ? 1 : 0
  byte_length = 4
}

resource "harness_platform_delegatetoken" "delegate" {
  count      = var.create_delegate ? 1 : 0
  name       = "${var.owner}-delegate-token-${random_id.delegate_token_suffix[0].hex}"
  account_id = var.harness_account_id
  org_id     = local.resolved_org_id
  project_id = local.resolved_project_id
}

################################################################################
# Harness Delegate
################################################################################

module "harness_delegate" {
  source = "../../modules/harness-delegate"
  count  = var.create_delegate ? 1 : 0

  owner                    = var.owner
  delegate_name            = "delegate"
  harness_account_id       = var.harness_account_id
  harness_api_key          = var.harness_api_key
  delegate_token           = harness_platform_delegatetoken.delegate[0].value
  harness_manager_endpoint = var.harness_endpoint

  create_namespace     = true
  delegate_replicas    = var.delegate_replicas
  grant_cluster_admin  = true
  fetch_latest_version = true

  # IRSA configuration - bind delegate SA to IAM role with ASG permissions
  enable_irsa_annotations = true
  irsa_role_arn           = module.irsa_delegate_role[0].role_arn

  # Tags for delegate selection - includes delegate-{owner} for CD pipeline
  delegate_tags = ["delegate-${var.owner}"]

  depends_on = [
    module.harness_org_project,
    module.irsa_delegate_role,
    harness_platform_delegatetoken.delegate
  ]
}
