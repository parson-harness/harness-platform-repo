#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TOFU_DIR="${TOFU_DIR:-${PROJECT_ROOT}/tofu/stacks/eks}"
TFVARS_FILE="${TFVARS_FILE:-${TOFU_DIR}/terraform.tfvars}"

IMAGE_TAG="${1:-latest}"
IMAGE_NAME="harness-demo-app"

# Helper function to extract value from tfvars
get_tfvar() {
    local key="$1"
    grep "^${key}[[:space:]]*=" "$TFVARS_FILE" 2>/dev/null | sed 's/.*=[[:space:]]*"\([^"]*\)".*/\1/' | head -1
}

# Get registry configuration from tofu outputs (if available) or tfvars
echo "Reading registry configuration..."
cd "$TOFU_DIR"
REGISTRY_TYPE=$(tofu output -raw artifact_registry_type 2>/dev/null || get_tfvar "artifact_registry_type" || echo "har")
REGISTRY_URL=$(tofu output -raw artifact_registry_url 2>/dev/null || echo "")

# Get Harness configuration from tfvars if not in environment
if [ -z "$HARNESS_API_KEY" ]; then
    HARNESS_API_KEY=$(get_tfvar "harness_api_key")
fi
HARNESS_ACCOUNT_ID=$(get_tfvar "harness_account_id")
OWNER=$(get_tfvar "owner")
cd "$PROJECT_ROOT"

# If no REGISTRY_URL from tofu outputs, construct from tfvars for HAR
if [ -z "$REGISTRY_URL" ] && [ "$REGISTRY_TYPE" = "har" ]; then
    if [ -n "$HARNESS_ACCOUNT_ID" ] && [ -n "$OWNER" ]; then
        REGISTRY_URL="pkg.harness.io/$(echo "$HARNESS_ACCOUNT_ID" | tr '[:upper:]' '[:lower:]')/har-${OWNER}"
        echo "Constructed HAR URL from tfvars"
    fi
fi

if [ -z "$REGISTRY_URL" ]; then
    echo "❌ Error: Could not determine registry URL"
    echo "   Either run 'tofu apply' in ${TOFU_DIR} or ensure tfvars has harness_account_id and owner"
    exit 1
fi

echo "Registry Type: ${REGISTRY_TYPE}"
echo "Registry URL: ${REGISTRY_URL}"
echo "Image Tag: ${IMAGE_TAG}"
echo ""

echo "Building Java application..."
mvn clean package -DskipTests

echo "Building Docker image for linux/amd64 (EKS compatibility)..."
docker build --platform linux/amd64 -t ${IMAGE_NAME}:${IMAGE_TAG} .

if [ "$REGISTRY_TYPE" = "har" ]; then
    # Harness Artifact Registry
    echo "Authenticating to Harness Artifact Registry..."
    
    # HAR uses Harness API key for authentication (already loaded from tfvars above)
    if [ -z "$HARNESS_API_KEY" ]; then
        echo "❌ Error: HARNESS_API_KEY not found in environment or tfvars"
        echo "   Set it with: export HARNESS_API_KEY=<your-api-key>"
        echo "   Or add harness_api_key to ${TFVARS_FILE}"
        exit 1
    fi
    
    # HAR URL format: pkg.harness.io/<account_id_lowercase>/<registry_id>/<image>:<tag>
    HAR_HOST="pkg.harness.io"
    
    # Get account ID (lowercase) and registry ID from the URL
    # Use HARNESS_ACCOUNT_ID from tfvars if available, otherwise extract from URL
    ACCOUNT_ID=$(echo "${HARNESS_ACCOUNT_ID:-$(echo "$REGISTRY_URL" | cut -d'/' -f2)}" | tr '[:upper:]' '[:lower:]')
    REGISTRY_ID=$(echo "$REGISTRY_URL" | rev | cut -d'/' -f1 | rev)
    
    HAR_IMAGE_URL="${HAR_HOST}/${ACCOUNT_ID}/${REGISTRY_ID}/${IMAGE_NAME}"
    
    echo "HAR Image URL: ${HAR_IMAGE_URL}:${IMAGE_TAG}"
    
    echo "$HARNESS_API_KEY" | docker login "$HAR_HOST" -u x-api-key --password-stdin
    
    echo "Tagging image for HAR..."
    docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${HAR_IMAGE_URL}:${IMAGE_TAG}
    
    echo "Pushing image to HAR..."
    docker push ${HAR_IMAGE_URL}:${IMAGE_TAG}
    
    echo ""
    echo "✅ Successfully pushed ${HAR_IMAGE_URL}:${IMAGE_TAG}"
else
    # AWS ECR
    AWS_REGION="${AWS_REGION:-us-east-1}"
    
    echo "Authenticating to ECR..."
    ECR_HOST=$(echo "$REGISTRY_URL" | cut -d'/' -f1)
    aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${ECR_HOST}
    
    echo "Tagging image for ECR..."
    docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${REGISTRY_URL}:${IMAGE_TAG}
    
    echo "Pushing image to ECR..."
    docker push ${REGISTRY_URL}:${IMAGE_TAG}
    
    echo ""
    echo "✅ Successfully pushed ${REGISTRY_URL}:${IMAGE_TAG}"
fi

echo ""
echo "You can now run the pipeline in Harness with tag: ${IMAGE_TAG}"
