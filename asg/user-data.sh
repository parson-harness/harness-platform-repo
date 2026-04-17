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

LOG_FILE="/var/log/harness-demo-user-data.log"
STATUS_FILE="/var/lib/harness-demo/user-data-status"
mkdir -p /var/lib/harness-demo
exec > >(tee -a "$LOG_FILE" | logger -t harness-demo-user-data -s 2>/dev/console) 2>&1

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
BUILD_ID=<+pipeline.executionId>
ENVEOF

chown harness-app:harness-app /etc/harness-demo-app.env

cat > "$STATUS_FILE" <<STATUSEOF
instance_id=${INSTANCE_ID}
region=${REGION}
asg_name=${ASG_NAME:-}
bg_version=${BG_VERSION:-}
deployment_variant=${DEPLOYMENT_VARIANT}
deployment_track=${DEPLOYMENT_TRACK}
app_version=<+pipeline.variables.ami_name>
environment=<+env.name>
deployment_strategy=<+pipeline.variables.deployment_strategy>
deployed_ami=<+artifact.metadata.ami>
execution_id=<+pipeline.executionId>
env_file_size=$(wc -c < /etc/harness-demo-app.env | tr -d ' ')
STATUSEOF

chmod 644 "$STATUS_FILE"

systemctl restart harness-demo-app
