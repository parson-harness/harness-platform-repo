#!/bin/bash
################################################################################
# Harness Demo App - EC2 User Data / Startup Script
#
# The application JAR and systemd service are already baked into the AMI by
# Packer. This script only writes runtime environment variables and starts
# the pre-installed service.
#
# Harness renders these expressions at deploy time before embedding in the
# Launch Template UserData, so each new ASG instance starts with the correct
# context for the active deployment:
#
#   <+pipeline.variables.deployment_strategy> - blue-green | canary | rolling
#   <+env.name>                               - Environment name (dev | prod)
#   <+artifact.metadata.ami>                  - AMI ID that was deployed
################################################################################
set -euo pipefail

DEPLOYMENT_VARIANT=""
DEPLOYMENT_TRACK="stable"
METADATA_TOKEN="$(curl -sS -m 2 -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" || true)"
METADATA_HEADERS=()
if [ -n "$METADATA_TOKEN" ]; then
  METADATA_HEADERS=(-H "X-aws-ec2-metadata-token: ${METADATA_TOKEN}")
fi

INSTANCE_ID="$(curl -sS -m 2 "${METADATA_HEADERS[@]}" "http://169.254.169.254/latest/meta-data/instance-id" || true)"
IDENTITY_DOCUMENT="$(curl -sS -m 2 "${METADATA_HEADERS[@]}" "http://169.254.169.254/latest/dynamic/instance-identity/document" || true)"
REGION="$(printf '%s' "$IDENTITY_DOCUMENT" | tr -d '\n' | sed -n 's/.*"region"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"

if command -v aws >/dev/null 2>&1 && [ -n "$INSTANCE_ID" ] && [ -n "$REGION" ]; then
  ASG_NAME=""
  BG_VERSION=""
  for _ in $(seq 1 12); do
    ASG_NAME="$(aws autoscaling describe-auto-scaling-instances --instance-ids "$INSTANCE_ID" --region "$REGION" --query 'AutoScalingInstances[0].AutoScalingGroupName' --output text 2>/dev/null || true)"
    if [ -n "$ASG_NAME" ] && [ "$ASG_NAME" != "None" ] && [ "$ASG_NAME" != "null" ]; then
      break
    fi
    sleep 5
  done

  case "$ASG_NAME" in
    *__Canary)
      DEPLOYMENT_TRACK="canary"
      ;;
  esac

  if [ -n "$ASG_NAME" ] && [ "$ASG_NAME" != "None" ] && [ "$ASG_NAME" != "null" ]; then
    BG_VERSION="$(aws autoscaling describe-tags --region "$REGION" --filters "Name=auto-scaling-group,Values=$ASG_NAME" "Name=key,Values=BG_VERSION" --query 'Tags[0].Value' --output text 2>/dev/null || true)"
    case "$BG_VERSION" in
      BLUE|Blue|blue)
        DEPLOYMENT_VARIANT="blue"
        DEPLOYMENT_TRACK="stable"
        ;;
      GREEN|Green|green)
        DEPLOYMENT_VARIANT="green"
        DEPLOYMENT_TRACK="stable"
        ;;
    esac
  fi
fi

cat > /etc/harness-demo-app.env <<ENVEOF
DEPLOYMENT_TARGET=asg
APP_VERSION=<+pipeline.variables.ami_name>
APP_ENVIRONMENT=<+env.name>
DEPLOYMENT_STRATEGY=<+pipeline.variables.deployment_strategy>
DEPLOYMENT_VARIANT=${DEPLOYMENT_VARIANT}
DEPLOYMENT_TRACK=${DEPLOYMENT_TRACK}
PUBLIC_URL=<+serviceVariables.appUrl>
STAGE_URL=<+serviceVariables.stageUrl>
DEPLOYED_AMI=<+artifact.metadata.ami>
ENVEOF

chown harness-app:harness-app /etc/harness-demo-app.env

systemctl restart harness-demo-app
