#!/bin/bash
set -e

################################################################################
# EKS Deployment Test Script
# Verifies the full EKS deployment workflow before iterating on ECS/Lambda/ASG
################################################################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

NAMESPACE="${NAMESPACE:-harness-demo}"
APP_NAME="${APP_NAME:-harness-demo-app}"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}EKS Deployment Verification${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check prerequisites
echo -e "${YELLOW}[Prerequisites]${NC}"

check_command() {
    if command -v "$1" &> /dev/null; then
        echo -e "  ${GREEN}✓${NC} $1 installed"
        return 0
    else
        echo -e "  ${RED}✗${NC} $1 not found"
        return 1
    fi
}

check_command kubectl || exit 1
check_command aws || exit 1
check_command curl || exit 1

echo ""

# Check cluster connection
echo -e "${YELLOW}[1/8] Checking EKS cluster connection...${NC}"
if kubectl cluster-info &> /dev/null; then
    CLUSTER=$(kubectl config current-context)
    echo -e "  ${GREEN}✓${NC} Connected to: $CLUSTER"
else
    echo -e "  ${RED}✗${NC} Cannot connect to cluster"
    echo "  Run: aws eks update-kubeconfig --region <region> --name <cluster-name>"
    exit 1
fi

# Check namespace
echo -e "${YELLOW}[2/8] Checking namespace...${NC}"
if kubectl get namespace "$NAMESPACE" &> /dev/null; then
    echo -e "  ${GREEN}✓${NC} Namespace '$NAMESPACE' exists"
else
    echo -e "  ${YELLOW}!${NC} Namespace '$NAMESPACE' not found, creating..."
    kubectl create namespace "$NAMESPACE"
fi

# Check Harness Delegate
echo -e "${YELLOW}[3/8] Checking Harness Delegate...${NC}"
DELEGATE_NS="harness-delegate-ng"
DELEGATE_PODS=$(kubectl get pods -n "$DELEGATE_NS" -l app=harness-delegate --no-headers 2>/dev/null | wc -l)
if [ "$DELEGATE_PODS" -gt 0 ]; then
    echo -e "  ${GREEN}✓${NC} Delegate running ($DELEGATE_PODS pod(s))"
    kubectl get pods -n "$DELEGATE_NS" -l app=harness-delegate --no-headers | while read line; do
        POD_NAME=$(echo "$line" | awk '{print $1}')
        POD_STATUS=$(echo "$line" | awk '{print $3}')
        echo -e "    - $POD_NAME: $POD_STATUS"
    done
else
    echo -e "  ${RED}✗${NC} No delegate pods found in $DELEGATE_NS"
    echo "  Check: kubectl get pods -n $DELEGATE_NS"
fi

# Check app deployment
echo -e "${YELLOW}[4/8] Checking application deployment...${NC}"
if kubectl get deployment "$APP_NAME" -n "$NAMESPACE" &> /dev/null; then
    READY=$(kubectl get deployment "$APP_NAME" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}')
    DESIRED=$(kubectl get deployment "$APP_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}')
    echo -e "  ${GREEN}✓${NC} Deployment found: $READY/$DESIRED replicas ready"
else
    echo -e "  ${YELLOW}!${NC} No deployment found (expected if not yet deployed)"
fi

# Check service
echo -e "${YELLOW}[5/8] Checking service...${NC}"
if kubectl get service "$APP_NAME" -n "$NAMESPACE" &> /dev/null; then
    SVC_TYPE=$(kubectl get service "$APP_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.type}')
    echo -e "  ${GREEN}✓${NC} Service found: $SVC_TYPE"
    
    if [ "$SVC_TYPE" = "LoadBalancer" ]; then
        LB_HOST=$(kubectl get service "$APP_NAME" -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
        if [ -n "$LB_HOST" ]; then
            echo -e "  ${GREEN}✓${NC} LoadBalancer: $LB_HOST"
            APP_URL="http://$LB_HOST:8080"
        else
            echo -e "  ${YELLOW}!${NC} LoadBalancer pending..."
        fi
    fi
else
    echo -e "  ${YELLOW}!${NC} No service found (expected if not yet deployed)"
fi

# Test app endpoints (if deployed)
echo -e "${YELLOW}[6/8] Testing application endpoints...${NC}"
if [ -n "$APP_URL" ]; then
    echo "  Testing: $APP_URL"
    
    # Health check
    if curl -s -o /dev/null -w "%{http_code}" "$APP_URL/actuator/health" | grep -q "200"; then
        echo -e "  ${GREEN}✓${NC} /actuator/health - OK"
    else
        echo -e "  ${RED}✗${NC} /actuator/health - Failed"
    fi
    
    # API info
    if curl -s -o /dev/null -w "%{http_code}" "$APP_URL/api/info" | grep -q "200"; then
        echo -e "  ${GREEN}✓${NC} /api/info - OK"
        echo "  Response:"
        curl -s "$APP_URL/api/info" | head -c 200
        echo ""
    else
        echo -e "  ${RED}✗${NC} /api/info - Failed"
    fi
    
    # Prometheus metrics
    if curl -s -o /dev/null -w "%{http_code}" "$APP_URL/actuator/prometheus" | grep -q "200"; then
        echo -e "  ${GREEN}✓${NC} /actuator/prometheus - OK"
    else
        echo -e "  ${RED}✗${NC} /actuator/prometheus - Failed"
    fi
else
    echo -e "  ${YELLOW}!${NC} Skipping (no accessible URL)"
    echo "  To test locally: kubectl port-forward svc/$APP_NAME 8080:8080 -n $NAMESPACE"
fi

# Check ECR images
echo -e "${YELLOW}[7/8] Checking ECR repository...${NC}"
ECR_REPO=$(aws ecr describe-repositories --repository-names harness-demo-app 2>/dev/null | jq -r '.repositories[0].repositoryUri' 2>/dev/null)
if [ -n "$ECR_REPO" ] && [ "$ECR_REPO" != "null" ]; then
    echo -e "  ${GREEN}✓${NC} ECR repo: $ECR_REPO"
    
    IMAGES=$(aws ecr list-images --repository-name harness-demo-app --query 'imageIds[*].imageTag' --output text 2>/dev/null | tr '\t' '\n' | head -5)
    if [ -n "$IMAGES" ]; then
        echo "  Available tags:"
        echo "$IMAGES" | while read tag; do
            echo "    - $tag"
        done
    else
        echo -e "  ${YELLOW}!${NC} No images pushed yet"
    fi
else
    echo -e "  ${YELLOW}!${NC} ECR repo not found or not accessible"
fi

# Summary
echo -e "${YELLOW}[8/8] Generating test commands...${NC}"
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Manual Test Commands${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "# Port-forward to test locally:"
echo "kubectl port-forward svc/$APP_NAME 8080:8080 -n $NAMESPACE"
echo ""
echo "# View logs:"
echo "kubectl logs -f deployment/$APP_NAME -n $NAMESPACE"
echo ""
echo "# Test chaos injection (for CV demo):"
echo "curl -X POST http://localhost:8080/api/chaos/enable?errorRate=0.3&latencyMs=500"
echo ""
echo "# Check delegate logs:"
echo "kubectl logs -f -l app=harness-delegate -n harness-delegate-ng"
echo ""
echo "# Scale deployment:"
echo "kubectl scale deployment/$APP_NAME --replicas=3 -n $NAMESPACE"
echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Verification Complete${NC}"
echo -e "${GREEN}========================================${NC}"
