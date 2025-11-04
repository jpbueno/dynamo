# NVIDIA Dynamo Platform - Workshop Setup Guide

## 📋 Overview

This guide will walk you through deploying the NVIDIA Dynamo Platform v0.6.0, a comprehensive AI/ML orchestration platform designed for managing distributed workloads and inference at scale.

**Workshop Date:** Friday, November 7, 2025  
**Platform Version:** Dynamo Platform v0.6.0

---

## 🎯 What You'll Deploy

The Dynamo Platform consists of several integrated components:

1. **Dynamo Operator** - Core platform controller for managing Dynamo resources
2. **etcd** - Distributed key-value store for configuration and state management
3. **NATS** - High-performance messaging system with JetStream persistence
4. **KAI Scheduler** - Advanced Kubernetes AI workload scheduler
5. **Grove Operator** - Multi-node inference orchestration system

---

## ✅ Prerequisites

### Required Infrastructure

- **Kubernetes Cluster**: v1.25+ recommended
- **kubectl**: Configured and authenticated to your cluster
- **Helm**: v3.10+ installed locally
- **Storage Class**: Dynamic provisioning capable (NFS or similar)
- **Cluster Resources**:
  - Minimum 4 CPU cores available
  - Minimum 8GB RAM available
  - Persistent storage capability (15GB+ total)

### Required Permissions

- Cluster-admin access or equivalent permissions to:
  - Create namespaces
  - Install CRDs (Custom Resource Definitions)
  - Create cluster-scoped resources (ClusterRoles, ClusterRoleBindings)
  - Manage RBAC resources

### Network Requirements

- Container registry access to:
  - `nvcr.io` (NVIDIA Container Registry)
  - `docker.io` (Docker Hub)
  - `ghcr.io` (GitHub Container Registry)

---

## 🚀 Installation Steps

### Step 1: Set Up Your Environment

```bash
# Set your working directory
cd /Users/jbuenosantan/Library/CloudStorage/OneDrive-NVIDIACorporation/NVIDIA/Inference/dynamo

# Verify kubectl is working
kubectl cluster-info

# Verify Helm is installed
helm version
```

### Step 2: Create the Namespace

```bash
# Create the dynamo-system namespace
kubectl create namespace dynamo-system

# Set it as your default context (optional)
kubectl config set-context --current --namespace=dynamo-system
```

### Step 3: Add NVIDIA Helm Repository

```bash
# Add the NVIDIA Helm repository
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia

# Update your Helm repositories
helm repo update

# Verify the dynamo-platform chart is available
helm search repo nvidia/dynamo-platform
```

### Step 4: Configure Installation Values

Create a custom values file for your deployment:

```bash
cat > dynamo-values.yaml <<EOF
# NVIDIA Dynamo Platform Configuration
# Version: 0.6.0

# Dynamo Operator Configuration
dynamoOperator:
  enabled: true
  image:
    repository: nvcr.io/nvidia/ai-dynamo/kubernetes-operator
    tag: 0.6.0
  resources:
    limits:
      cpu: 1024m
      memory: 2Gi
    requests:
      cpu: 100m
      memory: 128Mi
  mpi:
    sshKeyGeneration: true

# etcd Configuration
etcd:
  enabled: true
  replicaCount: 1  # Use 3 for production HA
  image:
    repository: docker.io/bitnami/etcd
    tag: 3.5.18-debian-12-r5
  persistence:
    enabled: true
    size: 1Gi
  service:
    clientPort: 2379
    peerPort: 2380

# NATS Messaging Configuration
nats:
  enabled: true
  replicaCount: 1  # Use 3 for production HA
  image:
    repository: nats
    tag: 2.10.21-alpine
  jetstream:
    enabled: true
    storage:
      size: 10Gi
  service:
    port: 4222
    monitorPort: 8222

# KAI Scheduler Configuration
kaiScheduler:
  enabled: true
  version: v0.9.4
  components:
    scheduler:
      enabled: true
    operator:
      enabled: true
    binder:
      enabled: true
    admission:
      enabled: true
    podGrouper:
      enabled: true
    queueController:
      enabled: true
    podGroupController:
      enabled: true

# Grove Operator Configuration
grove:
  enabled: true
  image:
    repository: ghcr.io/nvidia/grove/grove-operator
    tag: v0.1.0-alpha.3

# Monitoring Configuration
monitoring:
  prometheus:
    enabled: true
    podMonitor: true
EOF
```

### Step 5: Install the Dynamo Platform

```bash
# Install the Dynamo Platform using Helm
helm install dynamo-platform nvidia/dynamo-platform \
  --namespace dynamo-system \
  --version 0.6.0 \
  --values dynamo-values.yaml \
  --wait \
  --timeout 10m

# Expected output:
# NAME: dynamo-platform
# NAMESPACE: dynamo-system
# STATUS: deployed
# REVISION: 1
```

### Step 6: Verify the Installation

```bash
# Check all pods in the namespace
kubectl get pods -n dynamo-system

# Expected pods (all should be Running):
# - dynamo-platform-dynamo-operator-controller-manager-*
# - dynamo-platform-etcd-0
# - dynamo-platform-nats-0
# - scheduler-*
# - kai-operator-*
# - binder-*
# - admission-*
# - pod-grouper-*
# - queue-controller-*
# - podgroup-controller-*
# - grove-operator-*
```

Check the detailed status:

```bash
# View all resources
kubectl get all -n dynamo-system

# Check CRDs installed
kubectl get crds | grep dynamo

# Check services
kubectl get svc -n dynamo-system

# Check persistent volumes
kubectl get pvc -n dynamo-system
```

---

## 🔍 Component Verification

### Verify Dynamo Operator

```bash
# Check operator logs
kubectl logs -n dynamo-system deployment/dynamo-platform-dynamo-operator-controller-manager

# Verify SSH keys were generated (for MPI support)
kubectl get secrets -n dynamo-system | grep ssh

# Check operator status
kubectl describe deployment -n dynamo-system dynamo-platform-dynamo-operator-controller-manager
```

### Verify etcd

```bash
# Check etcd pod status
kubectl get statefulset -n dynamo-system dynamo-platform-etcd

# Test etcd connectivity
kubectl exec -n dynamo-system dynamo-platform-etcd-0 -- etcdctl \
  --endpoints=http://localhost:2379 \
  endpoint health

# Check etcd logs
kubectl logs -n dynamo-system dynamo-platform-etcd-0
```

### Verify NATS

```bash
# Check NATS status
kubectl get statefulset -n dynamo-system dynamo-platform-nats

# Check NATS JetStream status
kubectl exec -n dynamo-system dynamo-platform-nats-0 -- nats-server --version

# View NATS logs
kubectl logs -n dynamo-system dynamo-platform-nats-0
```

### Verify KAI Scheduler

```bash
# Check all KAI components
kubectl get deployments -n dynamo-system | grep -E 'scheduler|binder|admission|kai-operator'

# Check scheduler logs
kubectl logs -n dynamo-system deployment/scheduler

# Verify scheduler is registered
kubectl get leases -n kube-system | grep scheduler
```

### Verify Grove Operator

```bash
# Check Grove operator status
kubectl get deployment -n dynamo-system grove-operator

# View Grove logs
kubectl logs -n dynamo-system deployment/grove-operator

# Check Grove CRDs
kubectl get crds | grep grove
```

---

## ⚠️ Known Issues and Troubleshooting

### Issue 1: Dynamo Operator Restart Loop

**Symptoms:**
- Operator pod shows `CrashLoopBackOff` or `Back-off restarting failed container`
- Multiple restarts in pod events

**Diagnosis:**

```bash
# Check current status
kubectl get pods -n dynamo-system | grep dynamo-operator

# View recent logs
kubectl logs -n dynamo-system deployment/dynamo-platform-dynamo-operator-controller-manager --tail=100

# Check previous container logs (if crashed)
kubectl logs -n dynamo-system deployment/dynamo-platform-dynamo-operator-controller-manager --previous

# View detailed events
kubectl describe pod -n dynamo-system -l app.kubernetes.io/name=dynamo-operator
```

**Common Causes:**

1. **Insufficient Resources**
   ```bash
   # Check node resources
   kubectl top nodes
   
   # Check if pod is pending due to resources
   kubectl describe pod -n dynamo-system -l app.kubernetes.io/name=dynamo-operator | grep -A 10 Events
   ```

2. **CRD Installation Issues**
   ```bash
   # Verify all Dynamo CRDs are installed
   kubectl get crds | grep dynamo.nvidia.com
   
   # Check CRD versions
   kubectl get crds -o custom-columns=NAME:.metadata.name,VERSION:.spec.versions[*].name | grep dynamo
   ```

3. **RBAC Permission Issues**
   ```bash
   # Check service account
   kubectl get sa -n dynamo-system | grep dynamo-operator
   
   # Check cluster role bindings
   kubectl get clusterrolebinding | grep dynamo-operator
   ```

**Solutions:**

```bash
# Solution 1: Restart the operator pod
kubectl rollout restart deployment/dynamo-platform-dynamo-operator-controller-manager -n dynamo-system

# Solution 2: Increase resources if needed
kubectl patch deployment dynamo-platform-dynamo-operator-controller-manager -n dynamo-system \
  --type='json' -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/resources/limits/memory", "value": "4Gi"}]'

# Solution 3: Reinstall if CRDs are corrupted
helm uninstall dynamo-platform -n dynamo-system
kubectl delete namespace dynamo-system
# Wait 30 seconds, then repeat installation from Step 2
```

### Issue 2: etcd Not Starting

**Diagnosis:**

```bash
kubectl logs -n dynamo-system dynamo-platform-etcd-0
kubectl describe statefulset -n dynamo-system dynamo-platform-etcd
```

**Common Causes:**
- PVC not bound
- Insufficient storage
- Network policies blocking peer communication

**Solutions:**

```bash
# Check PVC status
kubectl get pvc -n dynamo-system

# Check storage class
kubectl get storageclass

# If PVC is pending, check events
kubectl describe pvc -n dynamo-system
```

### Issue 3: NATS Connection Issues

**Diagnosis:**

```bash
kubectl logs -n dynamo-system dynamo-platform-nats-0
kubectl exec -n dynamo-system dynamo-platform-nats-0 -- nats-server -v
```

**Solutions:**

```bash
# Test NATS connectivity from within cluster
kubectl run nats-test --image=nats:alpine --rm -it --restart=Never -- \
  nats sub -s nats://dynamo-platform-nats.dynamo-system.svc.cluster.local:4222 test

# Check service endpoints
kubectl get endpoints -n dynamo-system dynamo-platform-nats
```

---

## 📊 Monitoring and Health Checks

### Quick Health Check Script

Create a health check script:

```bash
cat > check-dynamo-health.sh <<'SCRIPT'
#!/bin/bash

echo "=== NVIDIA Dynamo Platform Health Check ==="
echo ""

NAMESPACE="dynamo-system"

# Check namespace exists
if ! kubectl get namespace $NAMESPACE &> /dev/null; then
    echo "❌ Namespace $NAMESPACE does not exist"
    exit 1
fi

echo "✅ Namespace: $NAMESPACE exists"
echo ""

# Check pods
echo "📦 Pod Status:"
kubectl get pods -n $NAMESPACE -o wide

echo ""
echo "🔍 Component Health:"

# Function to check component
check_component() {
    local name=$1
    local selector=$2
    local ready=$(kubectl get pods -n $NAMESPACE -l "$selector" -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
    
    if [[ "$ready" == *"True"* ]]; then
        echo "  ✅ $name: Healthy"
        return 0
    else
        echo "  ❌ $name: Not Ready"
        return 1
    fi
}

check_component "Dynamo Operator" "app.kubernetes.io/name=dynamo-operator"
check_component "etcd" "app.kubernetes.io/name=etcd"
check_component "NATS" "app.kubernetes.io/name=nats"
check_component "KAI Scheduler" "app=scheduler"
check_component "Grove Operator" "app.kubernetes.io/name=grove-operator"

echo ""
echo "💾 Storage Status:"
kubectl get pvc -n $NAMESPACE

echo ""
echo "🌐 Services:"
kubectl get svc -n $NAMESPACE

echo ""
echo "=== Health Check Complete ==="
SCRIPT

chmod +x check-dynamo-health.sh

# Run the health check
./check-dynamo-health.sh
```

### Continuous Monitoring

```bash
# Watch pod status in real-time
watch -n 2 'kubectl get pods -n dynamo-system'

# Monitor events
kubectl get events -n dynamo-system --sort-by='.lastTimestamp' --watch

# View resource usage
kubectl top pods -n dynamo-system
```

---

## 🧪 Testing the Deployment

### Test 1: Create a Simple Dynamo Workload

```bash
# Create a test workload YAML
cat > test-workload.yaml <<EOF
apiVersion: dynamo.nvidia.com/v1alpha1
kind: Workload
metadata:
  name: test-workload
  namespace: dynamo-system
spec:
  replicas: 1
  template:
    spec:
      containers:
      - name: test
        image: nvidia/cuda:12.2.0-base-ubuntu22.04
        command: ["nvidia-smi"]
EOF

# Apply the workload
kubectl apply -f test-workload.yaml

# Check workload status
kubectl get workloads -n dynamo-system
kubectl describe workload test-workload -n dynamo-system

# Clean up
kubectl delete -f test-workload.yaml
```

### Test 2: Verify KAI Scheduler Integration

```bash
# Create a test pod with scheduling annotations
cat > test-scheduled-pod.yaml <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: test-kai-pod
  namespace: dynamo-system
  labels:
    kai-scheduling: "true"
spec:
  schedulerName: kai-scheduler
  containers:
  - name: test
    image: busybox
    command: ["sleep", "3600"]
EOF

# Apply the pod
kubectl apply -f test-scheduled-pod.yaml

# Verify it was scheduled by KAI
kubectl get pod test-kai-pod -n dynamo-system -o yaml | grep schedulerName

# Check scheduling events
kubectl describe pod test-kai-pod -n dynamo-system | grep -A 5 Events

# Clean up
kubectl delete pod test-kai-pod -n dynamo-system
```

---

## 📚 Architecture Overview

### Component Interaction Flow

```
┌─────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                        │
│                                                              │
│  ┌────────────────────────────────────────────────────┐    │
│  │            dynamo-system Namespace                  │    │
│  │                                                     │    │
│  │  ┌──────────────────┐      ┌──────────────────┐  │    │
│  │  │ Dynamo Operator  │◄────►│  etcd (State)    │  │    │
│  │  │  (Controller)    │      │                  │  │    │
│  │  └────────┬─────────┘      └──────────────────┘  │    │
│  │           │                                        │    │
│  │           │ Manages                                │    │
│  │           ▼                                        │    │
│  │  ┌──────────────────┐      ┌──────────────────┐  │    │
│  │  │ Workload CRDs    │      │  NATS (Events)   │  │    │
│  │  │                  │◄────►│  + JetStream     │  │    │
│  │  └──────────────────┘      └──────────────────┘  │    │
│  │           │                                        │    │
│  │           │ Schedules                              │    │
│  │           ▼                                        │    │
│  │  ┌──────────────────┐      ┌──────────────────┐  │    │
│  │  │  KAI Scheduler   │      │ Grove Operator   │  │    │
│  │  │  (AI Workloads)  │      │ (Multi-Node)     │  │    │
│  │  └──────────────────┘      └──────────────────┘  │    │
│  │                                                     │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

### Resource Allocation Summary

| Component | CPU Request | CPU Limit | Memory Request | Memory Limit | Storage |
|-----------|-------------|-----------|----------------|--------------|---------|
| Dynamo Operator | 100m | 1024m | 128Mi | 2Gi | - |
| etcd | Default | Default | Default | Default | 1Gi |
| NATS | Default | Default | Default | Default | 10Gi |
| KAI Components | Default | Default | Default | Default | - |
| Grove Operator | Default | Default | Default | Default | - |

---

## 🎓 Workshop Exercises

### Exercise 1: Explore the Platform (15 minutes)

1. List all CRDs installed by Dynamo
2. Examine the Dynamo operator deployment configuration
3. Check the etcd cluster membership
4. View NATS JetStream configuration
5. Inspect KAI scheduler configuration

### Exercise 2: Deploy a Workload (20 minutes)

1. Create a simple inference workload
2. Monitor its scheduling through KAI
3. Check logs and events
4. Scale the workload
5. Clean up resources

### Exercise 3: Troubleshoot Issues (25 minutes)

1. Simulate a pod failure
2. Use logs to diagnose the issue
3. Verify platform resilience
4. Check monitoring metrics
5. Document findings

---

## 🔧 Cleanup and Uninstallation

### Option 1: Preserve Data (Soft Cleanup)

```bash
# Delete workloads only
kubectl delete workloads --all -n dynamo-system

# Delete test resources
kubectl delete pods -l test=true -n dynamo-system
```

### Option 2: Complete Uninstallation

```bash
# Uninstall the Helm release
helm uninstall dynamo-platform -n dynamo-system

# Wait for resources to be cleaned up
sleep 30

# Delete the namespace (this will delete PVCs)
kubectl delete namespace dynamo-system

# Clean up CRDs (optional, only if you want complete removal)
kubectl get crds | grep dynamo.nvidia.com | awk '{print $1}' | xargs kubectl delete crd
kubectl get crds | grep kai.io | awk '{print $1}' | xargs kubectl delete crd
kubectl get crds | grep grove.nvidia.com | awk '{print $1}' | xargs kubectl delete crd
```

### Verification

```bash
# Verify namespace is deleted
kubectl get namespace dynamo-system

# Verify CRDs are removed (if you deleted them)
kubectl get crds | grep -E 'dynamo|kai|grove'

# Check for any remaining resources
kubectl api-resources --verbs=list --namespaced -o name | \
  xargs -n 1 kubectl get --show-kind --ignore-not-found -n dynamo-system
```

---

## 📖 Additional Resources

### Official Documentation

- [NVIDIA Dynamo Platform Documentation](https://docs.nvidia.com/dynamo/)
- [KAI Scheduler Documentation](https://github.com/NVIDIA/KAI)
- [Grove Multi-Node Orchestration](https://github.com/NVIDIA/grove)
- [NATS Documentation](https://docs.nats.io/)
- [etcd Documentation](https://etcd.io/docs/)

### Useful Commands Cheat Sheet

```bash
# Quick status check
kubectl get all -n dynamo-system

# View all Dynamo resources
kubectl api-resources | grep dynamo

# Get logs from all operator pods
kubectl logs -n dynamo-system -l app.kubernetes.io/name=dynamo-operator --tail=50

# Port forward to NATS for local testing
kubectl port-forward -n dynamo-system svc/dynamo-platform-nats 4222:4222

# Port forward to etcd for local testing
kubectl port-forward -n dynamo-system svc/dynamo-platform-etcd 2379:2379

# Export Helm values
helm get values dynamo-platform -n dynamo-system > current-values.yaml

# Check Helm release history
helm history dynamo-platform -n dynamo-system

# Rollback to previous version
helm rollback dynamo-platform -n dynamo-system
```

---

## ✅ Pre-Workshop Checklist

Use this checklist to ensure you're ready for the workshop:

- [ ] Kubernetes cluster is accessible and healthy
- [ ] kubectl is configured correctly
- [ ] Helm v3.10+ is installed
- [ ] dynamo-system namespace is created
- [ ] NVIDIA Helm repository is added
- [ ] Dynamo Platform v0.6.0 is installed
- [ ] All pods are in Running state (check for restart loops)
- [ ] etcd is healthy and accessible
- [ ] NATS is running with JetStream enabled
- [ ] KAI Scheduler components are deployed
- [ ] Grove Operator is running
- [ ] Health check script runs successfully
- [ ] Test workload deploys and runs
- [ ] You can access logs from all components
- [ ] You understand the troubleshooting steps
- [ ] You've reviewed the architecture diagram

---

## 🆘 Getting Help

### During the Workshop

If you encounter issues during the workshop:

1. Check the troubleshooting section above
2. Run the health check script
3. Review component logs
4. Ask your workshop instructor

### After the Workshop

- NVIDIA Developer Forums: https://forums.developer.nvidia.com/
- GitHub Issues: Check respective component repositories
- Internal NVIDIA Slack: #dynamo-platform

---

## 📝 Notes and Observations

Use this section to document your findings during the workshop:

### Deployment Timeline
- Deployment started: ________________
- All pods running: ________________
- Issues encountered: ________________

### Resource Usage
- Node CPU utilization: ________________
- Node memory utilization: ________________
- Storage provisioned: ________________

### Specific Observations
```
[Add your notes here]
```

---

**Document Version:** 1.0  
**Last Updated:** November 7, 2025  
**Workshop Date:** Friday, November 7, 2025  
**Platform Version:** NVIDIA Dynamo Platform v0.6.0

---

Thank you for participating in the workshop! 🚀

