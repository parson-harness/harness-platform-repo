#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TOFU_DIR="${PROJECT_ROOT}/tofu/environments/sandbox"

IMAGE_TAG="${1:-latest}"
IMAGE_NAME="harness-demo-app"

# Get registry configuration from tofu outputs
echo "Reading registry configuration from tofu..."
cd "$TOFU_DIR"
REGISTRY_TYPE=$(tofu output -raw artifact_registry_type 2>/dev/null || echo "ecr")
REGISTRY_URL=$(tofu output -raw artifact_registry_url 2>/dev/null | tr '[:upper:]' '[:lower:]' || echo "")
cd "$PROJECT_ROOT"

if [ -z "$REGISTRY_URL" ]; then
    echo "❌ Error: Could not determine registry URL from tofu outputs"
    echo "   Run 'tofu apply' in ${TOFU_DIR} first"
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
    
    # HAR uses Harness API key for authentication
    if [ -z "$HARNESS_API_KEY" ]; then
        echo "❌ Error: HARNESS_API_KEY environment variable not set"
        echo "   Set it with: export HARNESS_API_KEY=<your-api-key>"
        exit 1
    fi
    
    # Extract the base registry URL (pkg.harness.io)
    HAR_HOST=$(echo "$REGISTRY_URL" | cut -d'/' -f1)
    
    echo "$HARNESS_API_KEY" | docker login "$HAR_HOST" -u x-api-key --password-stdin
    
    echo "Tagging image for HAR..."
    docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${REGISTRY_URL}/${IMAGE_NAME}:${IMAGE_TAG}
    
    echo "Pushing image to HAR..."
    docker push ${REGISTRY_URL}/${IMAGE_NAME}:${IMAGE_TAG}
    
    echo ""
    echo "✅ Successfully pushed ${REGISTRY_URL}/${IMAGE_NAME}:${IMAGE_TAG}"
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
