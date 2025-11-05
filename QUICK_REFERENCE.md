# Dynamo Platform - Quick Reference Card

## 🚀 Quick Start Commands

```bash
# 1. Create namespace
kubectl create namespace dynamo-system

# 2. Add Helm repo
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update

# 3. Install Dynamo
helm install dynamo-platform nvidia/dynamo-platform \
  --namespace dynamo-system \
  --version 0.6.0 \
  --wait

# 4. Verify installation
kubectl get pods -n dynamo-system
```

## 📊 Essential Status Commands

```bash
# All pods
kubectl get pods -n dynamo-system

# All resources
kubectl get all -n dynamo-system

# Component logs
kubectl logs -n dynamo-system deployment/dynamo-platform-dynamo-operator-controller-manager

# Health check
./check-dynamo-health.sh

# Watch pod status
watch kubectl get pods -n dynamo-system
```

## 🔍 Component-Specific Commands

### Dynamo Operator
```bash
# Status
kubectl get deployment -n dynamo-system | grep dynamo-operator

# Logs
kubectl logs -n dynamo-system -l app.kubernetes.io/name=dynamo-operator --tail=100

# Restart
kubectl rollout restart deployment/dynamo-platform-dynamo-operator-controller-manager -n dynamo-system

# Describe
kubectl describe deployment -n dynamo-system dynamo-platform-dynamo-operator-controller-manager
```

### etcd
```bash
# Status
kubectl get statefulset -n dynamo-system dynamo-platform-etcd

# Health check
kubectl exec -n dynamo-system dynamo-platform-etcd-0 -- \
  etcdctl --endpoints=http://localhost:2379 endpoint health

# Member list
kubectl exec -n dynamo-system dynamo-platform-etcd-0 -- \
  etcdctl --endpoints=http://localhost:2379 member list

# Logs
kubectl logs -n dynamo-system dynamo-platform-etcd-0
```

### NATS
```bash
# Status
kubectl get statefulset -n dynamo-system dynamo-platform-nats

# Server info
kubectl exec -n dynamo-system dynamo-platform-nats-0 -- nats-server --version

# Logs
kubectl logs -n dynamo-system dynamo-platform-nats-0

# Port forward for testing
kubectl port-forward -n dynamo-system svc/dynamo-platform-nats 4222:4222
```

### KAI Scheduler
```bash
# All KAI components
kubectl get deployments -n dynamo-system | grep -E 'scheduler|binder|admission|kai'

# Scheduler logs
kubectl logs -n dynamo-system deployment/scheduler --tail=100

# Operator logs
kubectl logs -n dynamo-system deployment/kai-operator --tail=100
```

### Grove Operator
```bash
# Status
kubectl get deployment -n dynamo-system grove-operator

# Logs
kubectl logs -n dynamo-system deployment/grove-operator --tail=100

# Describe
kubectl describe deployment -n dynamo-system grove-operator
```

## 🐛 Troubleshooting Commands

### Helm "No Space Left on Device" Error
```bash
# Quick fix: Clean Helm cache
helm repo remove nvidia 2>/dev/null || true
rm -rf ~/.cache/helm/repository/nvidia-index.yaml
rm -rf ~/.cache/helm/repository/cache/*.tgz
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update

# Check disk space
df -h /home

# Fix kubeconfig permissions warning
chmod 600 ~/.kube/config
```

### Check for Issues
```bash
# Pod restarts
kubectl get pods -n dynamo-system -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.containerStatuses[0].restartCount}{"\n"}{end}'

# Failed pods
kubectl get pods -n dynamo-system --field-selector=status.phase!=Running

# Recent events
kubectl get events -n dynamo-system --sort-by='.lastTimestamp' | tail -20

# Pod resource usage
kubectl top pods -n dynamo-system

# Node resources
kubectl top nodes
```

### Get Previous Logs (for crashed containers)
```bash
kubectl logs -n dynamo-system <pod-name> --previous
```

### Describe Pod for Events
```bash
kubectl describe pod -n dynamo-system <pod-name>
```

### Check Resource Constraints
```bash
# Pod resource limits
kubectl get pods -n dynamo-system -o custom-columns=NAME:.metadata.name,CPU_REQ:.spec.containers[0].resources.requests.cpu,MEM_REQ:.spec.containers[0].resources.requests.memory,CPU_LIM:.spec.containers[0].resources.limits.cpu,MEM_LIM:.spec.containers[0].resources.limits.memory
```

## 🧪 Testing Commands

### Create Test Workload
```bash
cat <<EOF | kubectl apply -f -
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
        image: busybox
        command: ["sleep", "3600"]
EOF

# Check it
kubectl get workloads -n dynamo-system
kubectl describe workload test-workload -n dynamo-system

# Delete it
kubectl delete workload test-workload -n dynamo-system
```

### Test KAI Scheduler
```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: test-kai-pod
  namespace: dynamo-system
spec:
  schedulerName: kai-scheduler
  containers:
  - name: test
    image: busybox
    command: ["sleep", "3600"]
EOF

# Verify scheduling
kubectl get pod test-kai-pod -n dynamo-system -o yaml | grep schedulerName

# Delete
kubectl delete pod test-kai-pod -n dynamo-system
```

## 🔧 Maintenance Commands

### Restart Components
```bash
# Restart specific deployment
kubectl rollout restart deployment/<deployment-name> -n dynamo-system

# Restart all deployments
kubectl rollout restart deployment -n dynamo-system

# Restart statefulset
kubectl rollout restart statefulset/<statefulset-name> -n dynamo-system
```

### Scale Components
```bash
# Scale etcd (for HA)
kubectl scale statefulset dynamo-platform-etcd -n dynamo-system --replicas=3

# Scale NATS (for HA)
kubectl scale statefulset dynamo-platform-nats -n dynamo-system --replicas=3
```

### View Helm Release
```bash
# Get values
helm get values dynamo-platform -n dynamo-system

# Get manifest
helm get manifest dynamo-platform -n dynamo-system

# Get status
helm status dynamo-platform -n dynamo-system

# History
helm history dynamo-platform -n dynamo-system
```

## 🗑️ Cleanup Commands

### Soft Cleanup
```bash
# Delete workloads only
kubectl delete workloads --all -n dynamo-system

# Delete test resources
kubectl delete pods -l test=true -n dynamo-system
```

### Complete Removal
```bash
# Uninstall Helm release
helm uninstall dynamo-platform -n dynamo-system

# Delete namespace
kubectl delete namespace dynamo-system

# Clean CRDs (optional)
kubectl get crds | grep -E 'dynamo|kai|grove' | awk '{print $1}' | xargs kubectl delete crd
```

## 📝 CRD Commands

```bash
# List all Dynamo CRDs
kubectl get crds | grep dynamo.nvidia.com

# List all KAI CRDs
kubectl get crds | grep kai.io

# List all Grove CRDs
kubectl get crds | grep grove.nvidia.com

# Get all resources of a specific CRD
kubectl get <crd-name> -A

# Describe a CRD
kubectl describe crd <crd-name>
```

## 🔐 Security & RBAC

```bash
# List service accounts
kubectl get sa -n dynamo-system

# Check cluster roles
kubectl get clusterrole | grep dynamo

# Check cluster role bindings
kubectl get clusterrolebinding | grep dynamo

# Check secrets
kubectl get secrets -n dynamo-system

# View SSH keys (for MPI)
kubectl get secrets -n dynamo-system | grep ssh
```

## 📊 Monitoring & Metrics

```bash
# PodMonitors (if Prometheus enabled)
kubectl get podmonitor -n dynamo-system

# Services with metrics endpoints
kubectl get svc -n dynamo-system -o wide

# Port forward to metrics
kubectl port-forward -n dynamo-system svc/<service-name> 8080:8080
```

## 🌐 Network & Services

```bash
# List services
kubectl get svc -n dynamo-system

# Service endpoints
kubectl get endpoints -n dynamo-system

# Service details
kubectl describe svc <service-name> -n dynamo-system

# Test service connectivity
kubectl run test-curl --image=curlimages/curl -it --rm -- \
  curl http://<service-name>.<namespace>.svc.cluster.local:<port>
```

## 💾 Storage

```bash
# PVCs
kubectl get pvc -n dynamo-system

# PVs
kubectl get pv | grep dynamo-system

# Storage classes
kubectl get storageclass

# PVC details
kubectl describe pvc <pvc-name> -n dynamo-system
```

## 📈 Common Troubleshooting Patterns

### Pattern 1: Pod CrashLoopBackOff
```bash
kubectl logs -n dynamo-system <pod-name> --previous
kubectl describe pod -n dynamo-system <pod-name>
kubectl get events -n dynamo-system --field-selector involvedObject.name=<pod-name>
```

### Pattern 2: ImagePullBackOff
```bash
kubectl describe pod -n dynamo-system <pod-name> | grep -A 10 Events
# Check image name and credentials
```

### Pattern 3: Pending Pod
```bash
kubectl describe pod -n dynamo-system <pod-name>
# Check node resources, PVC binding, node selectors
kubectl get nodes
kubectl top nodes
```

### Pattern 4: Service Not Accessible
```bash
kubectl get svc -n dynamo-system
kubectl get endpoints -n dynamo-system <service-name>
kubectl describe svc -n dynamo-system <service-name>
```

## 🎯 Workshop Day Commands

```bash
# Morning check
./check-dynamo-health.sh
kubectl get pods -n dynamo-system -o wide

# During workshop
watch -n 5 'kubectl get pods -n dynamo-system'
kubectl get events -n dynamo-system --watch

# Emergency restart
kubectl rollout restart deployment -n dynamo-system

# Quick logs
kubectl logs -n dynamo-system -l app.kubernetes.io/name=dynamo-operator --tail=20 -f
```

---

**Pro Tips:**
- Use aliases: `alias k=kubectl` and `alias kgp='kubectl get pods -n dynamo-system'`
- Keep the health check script running in a separate terminal
- Bookmark this file for quick reference during the workshop
- Practice the troubleshooting commands during the workshop

**Workshop Date:** Friday, November 7, 2025  
**Good luck!** 🚀

