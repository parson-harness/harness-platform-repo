#!/bin/bash
#
# Create Kubernetes secret for Harness Artifact Registry (HAR) authentication
# This script generates the dockercfg secret needed to pull images from HAR
#
# Usage: ./scripts/create-har-secret.sh [namespace]
#
# Prerequisites:
#   - HARNESS_API_KEY environment variable set (PAT or SAT)
#   - HARNESS_ACCOUNT_ID environment variable set (or reads from tfvars)
#   - kubectl configured to access the target cluster
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TFVARS_FILE="$PROJECT_ROOT/tofu/environments/sandbox/terraform.tfvars"

# Function to extract value from tfvars
get_tfvar() {
    local key=$1
    if [ -f "$TFVARS_FILE" ]; then
        grep "^${key}" "$TFVARS_FILE" 2>/dev/null | sed 's/.*=\s*"\(.*\)"/\1/' | head -1
    fi
}

# Get configuration
NAMESPACE="${1:-}"
HARNESS_API_KEY="${HARNESS_API_KEY:-$(get_tfvar 'harness_api_key')}"
HARNESS_ACCOUNT_ID="${HARNESS_ACCOUNT_ID:-$(get_tfvar 'harness_account_id')}"
OWNER="${OWNER:-$(get_tfvar 'owner')}"
EMAIL="${HARNESS_EMAIL:-$(get_tfvar 'harness_api_key_email')}"

# Validate required variables
if [ -z "$HARNESS_API_KEY" ]; then
    echo -e "${RED}Error: HARNESS_API_KEY not set${NC}"
    echo "Set it via environment variable or in terraform.tfvars"
    exit 1
fi

if [ -z "$EMAIL" ]; then
    echo -e "${RED}Error: Email not set${NC}"
    echo "Set HARNESS_EMAIL env var or harness_api_key_email in terraform.tfvars"
    exit 1
fi

if [ -z "$NAMESPACE" ]; then
    if [ -n "$OWNER" ]; then
        NAMESPACE="harness-demo-${OWNER}"
        echo -e "${YELLOW}No namespace specified, using: ${NAMESPACE}${NC}"
    else
        echo -e "${RED}Error: Namespace required${NC}"
        echo "Usage: $0 <namespace>"
        exit 1
    fi
fi

# Secret name based on namespace
SECRET_NAME="${OWNER:-harness}demoapp-dockercfg"

echo -e "${GREEN}Creating HAR pull secret...${NC}"
echo "  Namespace: $NAMESPACE"
echo "  Secret: $SECRET_NAME"
echo "  Email: $EMAIL"

# Create the base64 encoded auth string (email:PAT)
AUTH_STRING=$(echo -n "${EMAIL}:${HARNESS_API_KEY}" | base64)

# Create the dockercfg JSON
DOCKERCFG_JSON=$(cat <<EOF
{
  "pkg.harness.io": {
    "username": "${EMAIL}",
    "password": "${HARNESS_API_KEY}",
    "email": "${EMAIL}",
    "auth": "${AUTH_STRING}"
  }
}
EOF
)

# Base64 encode the dockercfg (for Kubernetes secret)
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    DOCKERCFG_BASE64=$(echo -n "$DOCKERCFG_JSON" | base64)
else
    # Linux
    DOCKERCFG_BASE64=$(echo -n "$DOCKERCFG_JSON" | base64 -w 0)
fi

# Check if namespace exists
if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
    echo -e "${YELLOW}Namespace $NAMESPACE does not exist. Creating...${NC}"
    kubectl create namespace "$NAMESPACE"
fi

# Create or update the secret
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: ${SECRET_NAME}
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/managed-by: harness-demo-scripts
type: kubernetes.io/dockercfg
data:
  .dockercfg: ${DOCKERCFG_BASE64}
EOF

echo -e "${GREEN}✅ Secret created successfully!${NC}"
echo ""
echo "To use this secret in your deployment, add to your values.yaml:"
echo -e "${YELLOW}  dockercfg: <+artifact.imagePullSecret>${NC}"
echo ""
echo "Or reference it directly in your deployment spec:"
echo -e "${YELLOW}  imagePullSecrets:"
echo "    - name: ${SECRET_NAME}${NC}"
