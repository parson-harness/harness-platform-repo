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

cat > /etc/harness-demo-app.env <<'ENVEOF'
DEPLOYMENT_TARGET=asg
APP_VERSION=<+pipeline.variables.ami_name>
APP_ENVIRONMENT=<+env.name>
DEPLOYMENT_STRATEGY=<+pipeline.variables.deployment_strategy>
DEPLOYED_AMI=<+artifact.metadata.ami>
ENVEOF

chown harness-app:harness-app /etc/harness-demo-app.env

systemctl restart harness-demo-app
