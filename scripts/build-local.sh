#!/bin/bash
set -e

################################################################################
# Local Build Script for Harness Demo App
# Use this for CD-only POVs where you don't need Harness CI
################################################################################

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
VERSION="${VERSION:-1.0.0}"
REGISTRY="${REGISTRY:-}"
REPO_NAME="${REPO_NAME:-harness-demo-app}"
AWS_REGION="${AWS_REGION:-us-east-1}"
PUSH="${PUSH:-false}"
SKIP_TESTS="${SKIP_TESTS:-false}"

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Build the Harness Demo App locally and optionally push to ECR"
    echo ""
    echo "Options:"
    echo "  -v, --version VERSION    Image version tag (default: 1.0.0)"
    echo "  -r, --registry REGISTRY  ECR registry URL (e.g., 123456789.dkr.ecr.us-east-1.amazonaws.com)"
    echo "  -n, --name REPO_NAME     Repository name (default: harness-demo-app)"
    echo "  -p, --push               Push to registry after build"
    echo "  -s, --skip-tests         Skip Maven tests"
    echo "  --region REGION          AWS region for ECR login (default: us-east-1)"
    echo "  -h, --help               Show this help message"
    echo ""
    echo "Examples:"
    echo "  # Build locally only"
    echo "  $0 -v 1.0.0"
    echo ""
    echo "  # Build and push to ECR"
    echo "  $0 -v 2.0.0 -r 123456789.dkr.ecr.us-east-1.amazonaws.com -p"
    echo ""
    echo "  # Build multiple versions for demo"
    echo "  $0 -v 1.0.0 -r \$ECR_REGISTRY -p"
    echo "  $0 -v 1.1.0 -r \$ECR_REGISTRY -p"
    echo "  $0 -v 2.0.0 -r \$ECR_REGISTRY -p"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--version)
            VERSION="$2"
            shift 2
            ;;
        -r|--registry)
            REGISTRY="$2"
            shift 2
            ;;
        -n|--name)
            REPO_NAME="$2"
            shift 2
            ;;
        -p|--push)
            PUSH="true"
            shift
            ;;
        -s|--skip-tests)
            SKIP_TESTS="true"
            shift
            ;;
        --region)
            AWS_REGION="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            usage
            exit 1
            ;;
    esac
done

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Harness Demo App - Local Build${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Version:    $VERSION"
echo "Repository: $REPO_NAME"
echo "Push:       $PUSH"
if [ -n "$REGISTRY" ]; then
    echo "Registry:   $REGISTRY"
fi
echo ""

# Step 1: Build JAR
echo -e "${YELLOW}[1/4] Building JAR with Maven...${NC}"
if [ "$SKIP_TESTS" = "true" ]; then
    ./mvnw clean package -DskipTests -q
else
    ./mvnw clean package -q
fi
echo -e "${GREEN}✓ JAR built successfully${NC}"

# Step 2: Build Docker image
echo -e "${YELLOW}[2/4] Building Docker image...${NC}"
docker build -t "${REPO_NAME}:${VERSION}" -t "${REPO_NAME}:latest" .
echo -e "${GREEN}✓ Docker image built: ${REPO_NAME}:${VERSION}${NC}"

# Step 3: Tag for registry (if pushing)
if [ "$PUSH" = "true" ]; then
    if [ -z "$REGISTRY" ]; then
        echo -e "${RED}Error: Registry URL required for push. Use -r or --registry${NC}"
        exit 1
    fi

    echo -e "${YELLOW}[3/4] Logging into ECR...${NC}"
    aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$REGISTRY"
    echo -e "${GREEN}✓ ECR login successful${NC}"

    echo -e "${YELLOW}[4/4] Tagging and pushing to ECR...${NC}"
    FULL_IMAGE="${REGISTRY}/${REPO_NAME}"
    
    docker tag "${REPO_NAME}:${VERSION}" "${FULL_IMAGE}:${VERSION}"
    docker tag "${REPO_NAME}:${VERSION}" "${FULL_IMAGE}:latest"
    
    docker push "${FULL_IMAGE}:${VERSION}"
    docker push "${FULL_IMAGE}:latest"
    
    echo -e "${GREEN}✓ Pushed to ECR:${NC}"
    echo "  - ${FULL_IMAGE}:${VERSION}"
    echo "  - ${FULL_IMAGE}:latest"
else
    echo -e "${YELLOW}[3/4] Skipping ECR login (not pushing)${NC}"
    echo -e "${YELLOW}[4/4] Skipping push (use -p to push)${NC}"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Build Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Local image: ${REPO_NAME}:${VERSION}"

if [ "$PUSH" = "true" ]; then
    echo "ECR image:   ${REGISTRY}/${REPO_NAME}:${VERSION}"
fi

echo ""
echo "To run locally:"
echo "  docker run -p 8080:8080 ${REPO_NAME}:${VERSION}"
echo ""
echo "To run with custom branding:"
echo "  docker run -p 8080:8080 \\"
echo "    -e CUSTOMER_NAME=\"Acme Corp\" \\"
echo "    -e DEPLOYMENT_VARIANT=canary \\"
echo "    ${REPO_NAME}:${VERSION}"
