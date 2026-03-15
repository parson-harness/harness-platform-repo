#!/bin/bash
set -e

# Configuration
ECR_REPO="759984737373.dkr.ecr.us-east-1.amazonaws.com/harness-demo-app-parson"
AWS_REGION="us-east-1"
IMAGE_TAG="${1:-latest}"

echo "Building Java application..."
mvn clean package -DskipTests

echo "Building Docker image for linux/amd64 (EKS compatibility)..."
docker build --platform linux/amd64 -t harness-demo-app:${IMAGE_TAG} .

echo "Tagging image for ECR..."
docker tag harness-demo-app:${IMAGE_TAG} ${ECR_REPO}:${IMAGE_TAG}

echo "Authenticating to ECR..."
aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${ECR_REPO}

echo "Pushing image to ECR..."
docker push ${ECR_REPO}:${IMAGE_TAG}

echo "✅ Successfully pushed ${ECR_REPO}:${IMAGE_TAG}"
echo ""
echo "You can now run the Canary pipeline in Harness with tag: ${IMAGE_TAG}"
