#!/bin/bash

# NVIDIA Dynamo Platform Health Check Script
# Usage: ./check-dynamo-health.sh [namespace]

NAMESPACE="${1:-dynamo-system}"
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== NVIDIA Dynamo Platform Health Check ===${NC}"
echo -e "${BLUE}Namespace: ${NAMESPACE}${NC}"
echo ""

# Check namespace exists
if ! kubectl get namespace $NAMESPACE &> /dev/null; then
    echo -e "${RED}❌ Namespace $NAMESPACE does not exist${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Namespace exists${NC}"
echo ""

# Check pods
echo -e "${BLUE}📦 Pod Status:${NC}"
kubectl get pods -n $NAMESPACE -o wide

echo ""
echo -e "${BLUE}🔍 Component Health:${NC}"

# Function to check component
check_component() {
    local name=$1
    local selector=$2
    local pods=$(kubectl get pods -n $NAMESPACE -l "$selector" --no-headers 2>/dev/null | wc -l | tr -d ' ')
    
    if [ "$pods" -eq 0 ]; then
        echo -e "  ${YELLOW}⚠️  $name: No pods found${NC}"
        return 1
    fi
    
    local ready=$(kubectl get pods -n $NAMESPACE -l "$selector" -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
    local running=$(kubectl get pods -n $NAMESPACE -l "$selector" -o jsonpath='{.items[*].status.phase}' 2>/dev/null)
    
    if [[ "$ready" == *"True"* ]] && [[ "$running" == *"Running"* ]]; then
        echo -e "  ${GREEN}✅ $name: Healthy ($pods pods)${NC}"
        return 0
    elif [[ "$running" == *"Running"* ]]; then
        echo -e "  ${YELLOW}⚠️  $name: Running but not ready ($pods pods)${NC}"
        return 1
    else
        echo -e "  ${RED}❌ $name: Not healthy ($pods pods)${NC}"
        kubectl get pods -n $NAMESPACE -l "$selector" --no-headers | grep -v "Running.*1/1"
        return 1
    fi
}

# Check each component
HEALTHY=0

check_component "Dynamo Operator" "app.kubernetes.io/name=dynamo-operator" || ((HEALTHY++))
check_component "etcd" "app.kubernetes.io/name=etcd" || ((HEALTHY++))
check_component "NATS" "app.kubernetes.io/name=nats" || ((HEALTHY++))
check_component "KAI Scheduler" "app=scheduler" || ((HEALTHY++))
check_component "KAI Operator" "app=kai-operator" || ((HEALTHY++))
check_component "Binder" "app=binder" || ((HEALTHY++))
check_component "Admission Controller" "app=admission" || ((HEALTHY++))
check_component "Grove Operator" "app.kubernetes.io/name=grove-operator" || ((HEALTHY++))

echo ""
echo -e "${BLUE}💾 Storage Status:${NC}"
kubectl get pvc -n $NAMESPACE 2>/dev/null || echo "No PVCs found"

echo ""
echo -e "${BLUE}🌐 Services:${NC}"
kubectl get svc -n $NAMESPACE

echo ""
echo -e "${BLUE}📜 Recent Events (last 10):${NC}"
kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp' | tail -10

echo ""
echo -e "${BLUE}🔧 CRDs Installed:${NC}"
kubectl get crds | grep -E 'dynamo|kai|grove' | wc -l | xargs echo "Total Dynamo-related CRDs:"

echo ""
if [ $HEALTHY -eq 0 ]; then
    echo -e "${GREEN}=== ✅ All Components Healthy ===${NC}"
    exit 0
else
    echo -e "${YELLOW}=== ⚠️  $HEALTHY Component(s) Need Attention ===${NC}"
    echo ""
    echo "Run these commands to investigate:"
    echo "  kubectl describe pods -n $NAMESPACE"
    echo "  kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=dynamo-operator --tail=50"
    echo "  kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp'"
    exit 1
fi

