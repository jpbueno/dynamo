# NVIDIA GPU Operator & DCGM Metrics - SME Learning Guide

> A comprehensive guide to becoming a Subject Matter Expert on NVIDIA GPU Operator with focus on DCGM metrics interpretation for profiling

## 📖 Table of Contents

1. [Overview](#overview)
2. [Quick Start Guide](#quick-start-guide)
3. [NVIDIA GPU Operator Fundamentals](#nvidia-gpu-operator-fundamentals)
4. [DCGM (Data Center GPU Manager) Deep Dive](#dcgm-data-center-gpu-manager-deep-dive)
5. [DCGM Metrics for Profiling](#dcgm-metrics-for-profiling)
6. [Interpreting Metrics](#interpreting-metrics)
7. [Setting Up Prometheus and Grafana for DCGM Metrics](#setting-up-prometheus-and-grafana-for-dcgm-metrics)
8. [Practical Examples](#practical-examples)
9. [Troubleshooting](#troubleshooting)
10. [Resources & Next Steps](#resources--next-steps)

---

## Overview

### What is NVIDIA GPU Operator?

The **NVIDIA GPU Operator** is a Kubernetes operator that manages GPU resources in Kubernetes clusters. It automates the deployment and management of:

- **NVIDIA Device Plugin** - Exposes GPUs to Kubernetes
- **NVIDIA Container Toolkit** - Enables GPU access in containers
- **NVIDIA Driver** - GPU drivers for the host
- **DCGM Exporter** - Exposes GPU metrics to Prometheus
- **GPU Feature Discovery** - Labels nodes with GPU capabilities
- **Node Feature Discovery** - Detects hardware features

### Why DCGM Matters

**DCGM (Data Center GPU Manager)** is NVIDIA's tool for monitoring, managing, and profiling GPUs in data centers. It provides:

- **Real-time GPU metrics** - Performance, health, and utilization
- **Profiling capabilities** - Detailed performance analysis
- **Health monitoring** - Early detection of issues
- **Telemetry** - Integration with monitoring stacks (Prometheus, Grafana)

---

## Quick Start Guide

### Complete Stack Installation (15-20 minutes)

For a fresh Ubuntu 22.04 server, you can install everything with a single script:

```bash
# Clone the repository
git clone https://github.com/jpbueno/dynamo.git
cd dynamo

# Run the automated installation script
bash install-gpu-operator-stack.sh
```

**What gets installed:**
- ✅ Kubernetes cluster (kubeadm)
- ✅ GPU Operator with DCGM Exporter
- ✅ Prometheus and Grafana monitoring stack
- ✅ All necessary configurations and fixes

**After installation:**
1. Access Grafana: `kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80`
2. Get Grafana password: `kubectl get secret -n monitoring kube-prometheus-stack-grafana -o jsonpath="{.data.admin-password}" | base64 -d`
3. Configure Prometheus data source in Grafana (see [Prometheus/Grafana Setup](#setting-up-prometheus-and-grafana-for-dcgm-metrics))
4. Start profiling GPU workloads!

**Prerequisites:**
- Ubuntu 22.04 server
- GPU with NVIDIA driver support
- Internet connectivity
- Sudo access

For detailed manual installation or troubleshooting, see the sections below.

---

## NVIDIA GPU Operator Fundamentals

### Architecture Components

```
┌─────────────────────────────────────────────────┐
│         Kubernetes Cluster                      │
├─────────────────────────────────────────────────┤
│  GPU Operator (Controller)                     │
│  ├── Device Plugin                              │
│  ├── Driver Manager                            │
│  ├── DCGM Exporter                             │
│  ├── GPU Feature Discovery                     │
│  └── Node Feature Discovery                    │
├─────────────────────────────────────────────────┤
│  GPU Nodes                                       │
│  ├── NVIDIA Driver                              │
│  ├── Container Toolkit                          │
│  └── DCGM Agent                                 │
└─────────────────────────────────────────────────┘
```

### Key Components Explained

#### 1. Device Plugin
- Exposes GPUs as Kubernetes resources
- Handles GPU allocation to pods
- Manages GPU lifecycle

#### 2. DCGM Exporter
- Exposes GPU metrics via Prometheus endpoint
- Runs as a DaemonSet on GPU nodes
- Provides `/metrics` endpoint for scraping

#### 3. GPU Feature Discovery
- Labels nodes with GPU capabilities
- Enables node selectors for GPU workloads
- Provides GPU model, memory, and compute capability info

### Installation

#### Option 1: Automated Installation (Recommended)

For a complete setup including Kubernetes, GPU Operator, Prometheus, and Grafana, use the automated installation script:

```bash
# Clone the repository (if not already done)
git clone https://github.com/jpbueno/dynamo.git
cd dynamo

# Run the installation script
bash install-gpu-operator-stack.sh
```

**What the script installs:**
- Kubernetes cluster (kubeadm)
- Containerd runtime configuration
- Flannel CNI plugin
- GPU Operator with DCGM Exporter
- Prometheus and Grafana stack
- ServiceMonitor for DCGM metrics
- All necessary firewall and system configurations

**Script features:**
- Automatic prerequisite installation
- Cluster initialization and configuration
- Taint removal for single-node clusters
- Firewall rule configuration
- Complete verification and status reporting

The script will take approximately 15-20 minutes to complete. After completion, you'll have a fully functional monitoring stack ready for GPU profiling.

#### Option 2: Manual Installation

If you prefer manual installation or already have a Kubernetes cluster:

**Prerequisites:**
- Ubuntu 22.04 (or compatible Linux distribution)
- Root or sudo access
- Internet connectivity
- GPU with NVIDIA driver support

**Step 1: Install Kubernetes**

```bash
# Install prerequisites
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gpg conntrack

# Load kernel modules
sudo modprobe br_netfilter
echo "br_netfilter" | sudo tee -a /etc/modules-load.d/k8s.conf

# Configure sysctl
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
sudo sysctl --system

# Disable swap
sudo swapoff -a
sudo sed -i '/swap/s/^/#/' /etc/fstab

# Install Kubernetes tools
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

# Configure containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd

# Initialize cluster
sudo kubeadm init --pod-network-cidr=10.244.0.0/16

# Configure kubectl
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Remove control-plane taint (for single-node clusters)
kubectl taint nodes --all node-role.kubernetes.io/control-plane-

# Install Flannel CNI
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

# Configure firewall (if needed)
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
sudo iptables -I INPUT 1 -m state --state ESTABLISHED,RELATED -j ACCEPT
sudo iptables -I INPUT 1 -s 10.244.0.0/16 -d $NODE_IP -p tcp --dport 6443 -j ACCEPT
sudo iptables -I INPUT 1 -s 10.244.0.0/16 -d 10.96.0.1 -p tcp --dport 443 -j ACCEPT
```

**Step 2: Install Helm**

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

**Step 3: Install GPU Operator**

```bash
# Add NVIDIA Helm repository
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update

# Install GPU Operator
helm install --wait gpu-operator \
  nvidia/gpu-operator \
  --namespace gpu-operator \
  --create-namespace \
  --set operator.defaultRuntime=containerd \
  --timeout 10m

# Verify installation
kubectl get pods -n gpu-operator
```

**Step 4: Install Prometheus and Grafana**

See the [Setting Up Prometheus and Grafana](#setting-up-prometheus-and-grafana-for-dcgm-metrics) section for detailed instructions.

### Troubleshooting Installation Issues

#### Issue: Control-Plane Node Taint Preventing Pod Scheduling

**Symptoms:**
- Pods stuck in `Pending` state
- Error: `0/1 nodes are available: 1 node(s) had untolerated taint`

**Solution:**
```bash
# Remove control-plane taint
kubectl taint nodes --all node-role.kubernetes.io/control-plane-
kubectl taint nodes --all node-role.kubernetes.io/master-  # For older k8s versions
```

#### Issue: Pods Cannot Reach Kubernetes API Server

**Symptoms:**
- CoreDNS pods not ready
- GPU Operator pods in `CrashLoopBackOff`
- Error: `dial tcp 10.96.0.1:443: i/o timeout`

**Solution:**
```bash
# Get node IP
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

# Add firewall rules to allow pod-to-host communication
sudo iptables -I INPUT 1 -m state --state ESTABLISHED,RELATED -j ACCEPT
sudo iptables -I INPUT 1 -s 10.244.0.0/16 -d $NODE_IP -p tcp --dport 6443 -j ACCEPT
sudo iptables -I INPUT 1 -s 10.244.0.0/16 -d 10.96.0.1 -p tcp --dport 443 -j ACCEPT

# Restart CoreDNS pods
kubectl delete pods -n kube-system -l k8s-app=kube-dns
```

#### Issue: CoreDNS Not Ready

**Symptoms:**
- CoreDNS pods running but not ready
- DNS queries failing

**Solution:**
```bash
# Check CoreDNS logs
kubectl logs -n kube-system -l k8s-app=kube-dns

# Verify API server connectivity
kubectl get endpoints kubernetes -n default

# Restart CoreDNS
kubectl rollout restart deployment/coredns -n kube-system
```

#### Issue: GPU Operator Pods Failing

**Symptoms:**
- GPU Operator pods in `CrashLoopBackOff`
- Cannot connect to Kubernetes API

**Solution:**
1. Ensure control-plane taint is removed (see above)
2. Ensure firewall rules are configured (see above)
3. Wait for CoreDNS to be ready
4. Restart GPU Operator pods:
   ```bash
   kubectl delete pods -n gpu-operator -l app=gpu-operator
   ```

#### Issue: Port Conflict with Node Exporter

**Symptoms:**
- `prometheus-node-exporter` pod in `CrashLoopBackOff`
- Error: `bind: address already in use` on port 9100

**Solution:**
```bash
# Option 1: Delete Kubernetes node-exporter (if host one exists)
kubectl delete daemonset -n monitoring kube-prometheus-stack-prometheus-node-exporter

# Option 2: Stop host node-exporter
sudo systemctl stop node_exporter
sudo systemctl disable node_exporter
```

### Verification

```bash
# Check GPU Operator components
kubectl get pods -n gpu-operator

# Verify GPU nodes
kubectl get nodes -o json | jq '.items[] | select(.status.capacity."nvidia.com/gpu")'

# Check DCGM Exporter
kubectl get pods -n gpu-operator -l app=nvidia-dcgm-exporter
kubectl get svc -n gpu-operator -l app=nvidia-dcgm-exporter

# Test GPU access
kubectl run gpu-test --rm -it --image=nvidia/cuda:12.0.0-base-ubuntu22.04 \
  --limits=nvidia.com/gpu=1 -- nvidia-smi
```

---

## DCGM (Data Center GPU Manager) Deep Dive

### What is DCGM?

**DCGM** is a collection of tools, libraries, and APIs for managing and monitoring NVIDIA GPUs in cluster environments. It provides:

1. **DCGM Agent** - Collects metrics from GPUs
2. **DCGM Library** - C API for programmatic access
3. **DCGM CLI** - Command-line interface
4. **DCGM Exporter** - Prometheus metrics exporter

### DCGM Architecture

```
┌─────────────────────────────────────────┐
│         DCGM Agent                      │
│  ├── Collects metrics from GPUs         │
│  ├── Manages GPU health                 │
│  └── Provides REST API                  │
├─────────────────────────────────────────┤
│         DCGM Exporter                   │
│  ├── Scrapes DCGM Agent                 │
│  ├── Exposes Prometheus metrics          │
│  └── Runs as DaemonSet                   │
├─────────────────────────────────────────┤
│         Monitoring Stack                │
│  ├── Prometheus (scrapes metrics)       │
│  ├── Grafana (visualization)            │
│  └── Alertmanager (alerts)              │
└─────────────────────────────────────────┘
```

### DCGM Metrics Categories

DCGM provides metrics in several categories:

1. **Performance Metrics** - Utilization, throughput, efficiency
2. **Health Metrics** - Temperature, power, errors
3. **Memory Metrics** - Usage, bandwidth, fragmentation
4. **Compute Metrics** - SM utilization, tensor core usage
5. **PCIe Metrics** - Bandwidth, errors, utilization
6. **NVLink Metrics** - Bandwidth, errors (for multi-GPU)

---

## DCGM Metrics for Profiling

### Core Profiling Metrics

#### 1. GPU Utilization (`DCGM_FI_DEV_GPU_UTIL`)

**What it measures:** Percentage of time GPU was busy processing kernels

**Interpretation:**
- **0-30%**: Underutilized - GPU is idle or waiting
- **30-70%**: Moderate utilization - may indicate bottlenecks
- **70-95%**: Good utilization - GPU is actively working
- **95-100%**: Maximum utilization - may indicate compute-bound workload

**Example:**
```
DCGM_FI_DEV_GPU_UTIL: 85%
→ GPU is actively processing 85% of the time
→ Good utilization for training workloads
```

#### 2. Memory Utilization (`DCGM_FI_DEV_MEM_COPY_UTIL`)

**What it measures:** Percentage of time GPU memory controller was busy

**Interpretation:**
- **High (>80%)**: Memory-bound workload - data transfer is bottleneck
- **Low (<30%)**: Compute-bound workload - GPU processing is bottleneck
- **Balanced (40-60%)**: Good balance between compute and memory

**Example:**
```
DCGM_FI_DEV_MEM_COPY_UTIL: 45%
→ Memory controller busy 45% of time
→ Balanced workload, not memory-bound
```

#### 3. SM (Streaming Multiprocessor) Utilization (`DCGM_FI_DEV_SM_OCCUPANCY`)

**What it measures:** Average SM occupancy percentage

**Interpretation:**
- **Low (<50%)**: Underutilized SMs - may need more threads/blocks
- **Medium (50-80%)**: Good occupancy
- **High (>80%)**: Excellent occupancy - SMs fully utilized

**Example:**
```
DCGM_FI_DEV_SM_OCCUPANCY: 72%
→ SMs are 72% occupied on average
→ Good occupancy, kernels are well-scheduled
```

#### 4. Tensor Core Utilization (`DCGM_FI_DEV_TENSOR_ACTIVE`)

**What it measures:** Percentage of time tensor cores are active

**Interpretation:**
- **0%**: Not using tensor cores - using CUDA cores instead
- **>0%**: Using tensor cores - good for AI/ML workloads
- **High (>50%)**: Efficient use of tensor cores for matrix operations

**Example:**
```
DCGM_FI_DEV_TENSOR_ACTIVE: 65%
→ Tensor cores active 65% of time
→ Workload is efficiently using tensor cores
```

#### 5. Memory Used (`DCGM_FI_DEV_FB_USED`)

**What it measures:** GPU memory currently in use (bytes)

**Interpretation:**
- Compare with total memory (`DCGM_FI_DEV_FB_TOTAL`)
- **High usage (>90%)**: May cause OOM errors
- **Low usage (<30%)**: May indicate inefficient memory usage
- **Optimal (60-80%)**: Good memory utilization

**Example:**
```
DCGM_FI_DEV_FB_USED: 20GB
DCGM_FI_DEV_FB_TOTAL: 24GB
→ Using 83% of GPU memory
→ Good utilization, but monitor for OOM
```

#### 6. Power Draw (`DCGM_FI_DEV_POWER_USAGE`)

**What it measures:** Current power consumption (watts)

**Interpretation:**
- Compare with TDP (Thermal Design Power)
- **High (>90% TDP)**: Maximum performance mode
- **Low (<50% TDP)**: Power-saving mode or idle
- **Fluctuating**: Workload has varying compute intensity

**Example:**
```
DCGM_FI_DEV_POWER_USAGE: 280W
TDP: 300W
→ Using 93% of TDP
→ GPU is running at high performance
```

#### 7. Temperature (`DCGM_FI_DEV_GPU_TEMP`)

**What it measures:** Current GPU temperature (Celsius)

**Interpretation:**
- **<70°C**: Cool - GPU has thermal headroom
- **70-85°C**: Normal operating temperature
- **85-95°C**: Warm - monitor for throttling
- **>95°C**: Hot - GPU may throttle performance

**Example:**
```
DCGM_FI_DEV_GPU_TEMP: 78°C
→ Normal operating temperature
→ No thermal throttling expected
```

#### 8. PCIe Bandwidth (`DCGM_FI_DEV_PCIE_TX_THROUGHPUT`, `DCGM_FI_DEV_PCIE_RX_THROUGHPUT`)

**What it measures:** PCIe data transfer rates (bytes/second)

**Interpretation:**
- **High TX**: GPU sending data to CPU/host
- **High RX**: GPU receiving data from CPU/host
- **Sustained high**: May indicate PCIe bottleneck
- **Low**: Data already in GPU memory or compute-bound

**Example:**
```
DCGM_FI_DEV_PCIE_RX_THROUGHPUT: 8GB/s
PCIe 3.0 x16 max: ~16GB/s
→ Using 50% of PCIe bandwidth
→ Not PCIe-bound
```

#### 9. NVLink Bandwidth (Multi-GPU)

**What it measures:** NVLink data transfer rates between GPUs

**Interpretation:**
- **High**: Good multi-GPU communication
- **Low**: May indicate inefficient multi-GPU usage
- **Compare with PCIe**: NVLink should be faster for GPU-to-GPU

**Example:**
```
DCGM_FI_DEV_NVLink_TX_THROUGHPUT: 45GB/s
NVLink 3.0 max: ~50GB/s
→ Excellent GPU-to-GPU bandwidth
→ Multi-GPU workload is well-optimized
```

#### 10. ECC Errors (`DCGM_FI_DEV_ECC_DBE_VOL_TOTAL`, `DCGM_FI_DEV_ECC_SBE_VOL_TOTAL`)

**What it measures:** ECC (Error-Correcting Code) errors

**Interpretation:**
- **SBE (Single Bit Error)**: Corrected automatically - monitor trend
- **DBE (Double Bit Error)**: Uncorrectable - critical issue
- **Increasing**: May indicate hardware degradation
- **Zero**: No errors detected

**Example:**
```
DCGM_FI_DEV_ECC_SBE_VOL_TOTAL: 5
→ 5 single-bit errors corrected
→ Monitor for increasing trend
→ If increasing, may indicate hardware issue
```

---

## Interpreting Metrics

### Profiling Workflow

1. **Baseline Measurement**
   - Measure metrics during idle state
   - Establish normal operating ranges

2. **Workload Execution**
   - Run your workload
   - Collect metrics over time

3. **Analysis**
   - Compare against baseline
   - Identify bottlenecks
   - Look for anomalies

4. **Optimization**
   - Address identified bottlenecks
   - Re-measure after changes

### Common Profiling Scenarios

#### Scenario 1: Training Workload

**Expected Metrics:**
- GPU Utilization: 85-95%
- Memory Utilization: 60-80%
- Tensor Core Usage: 50-80%
- Power: 80-95% TDP
- Temperature: 70-85°C

**Red Flags:**
- Low GPU utilization (<50%) → CPU bottleneck or data loading issue
- Low memory usage (<30%) → Batch size too small
- High PCIe usage → Data loading bottleneck
- Temperature >90°C → Thermal throttling risk

#### Scenario 2: Inference Workload

**Expected Metrics:**
- GPU Utilization: 30-60% (varies by batch size)
- Memory Utilization: 40-70%
- Power: 50-70% TDP
- Temperature: 60-75°C

**Red Flags:**
- Very low utilization (<20%) → May not need GPU
- High memory usage (>90%) → Risk of OOM
- High latency → May need optimization

#### Scenario 3: Multi-GPU Training

**Expected Metrics:**
- All GPUs: Similar utilization (within 5%)
- NVLink bandwidth: High (>80% capacity)
- PCIe bandwidth: Low (<30% capacity)
- Synchronization overhead: Minimal

**Red Flags:**
- Uneven GPU utilization → Load imbalance
- Low NVLink usage → Inefficient multi-GPU communication
- High PCIe usage → Using PCIe instead of NVLink

### Metric Relationships

Understanding how metrics relate helps identify root causes:

**High GPU Utilization + Low Memory Utilization**
→ Compute-bound workload
→ Solution: Optimize kernels, use mixed precision

**Low GPU Utilization + High Memory Utilization**
→ Memory-bound workload
→ Solution: Optimize data access patterns, increase batch size

**High GPU Utilization + High Temperature**
→ Thermal throttling risk
→ Solution: Improve cooling, reduce power limit

**High PCIe Usage + Low GPU Utilization**
→ Data loading bottleneck
→ Solution: Optimize data pipeline, use faster storage

---

## Setting Up Prometheus and Grafana for DCGM Metrics

This section provides step-by-step instructions for setting up Prometheus and Grafana to collect and visualize DCGM metrics from the GPU Operator.

### Prerequisites

- GPU Operator installed and DCGM Exporter running
- Helm 3.x installed
- kubectl configured with cluster access
- Sufficient cluster resources (2+ CPU cores, 4GB+ RAM recommended)

### Step 1: Install Prometheus and Grafana Stack

We'll use the `kube-prometheus-stack` Helm chart which includes Prometheus, Grafana, Alertmanager, and all necessary components.

```bash
# Add Prometheus Community Helm repository
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update prometheus-community

# Create monitoring namespace
kubectl create namespace monitoring

# Install kube-prometheus-stack
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.ruleSelectorNilUsesHelmValues=false \
  --wait --timeout 10m

# Verify installation
kubectl get pods -n monitoring
```

**Expected Output:**
- `prometheus-kube-prometheus-stack-prometheus-0` - Prometheus server
- `kube-prometheus-stack-grafana-*` - Grafana dashboard
- `alertmanager-kube-prometheus-stack-alertmanager-0` - Alertmanager
- Other supporting components

### Step 2: Create ServiceMonitor for DCGM Exporter

Create a ServiceMonitor resource to tell Prometheus to scrape DCGM Exporter metrics:

```bash
# Create ServiceMonitor YAML file (or use the provided file in the repo)
cat > dcgm-servicemonitor.yaml <<EOF
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: nvidia-dcgm-exporter
  namespace: gpu-operator
  labels:
    app: nvidia-dcgm-exporter
spec:
  selector:
    matchLabels:
      app: nvidia-dcgm-exporter
  endpoints:
  - port: gpu-metrics
    interval: 15s
    path: /metrics
EOF

# Apply the ServiceMonitor
kubectl apply -f dcgm-servicemonitor.yaml

# Verify ServiceMonitor was created
kubectl get servicemonitor -n gpu-operator
```

**Note:** The DCGM Exporter service already has the `prometheus.io/scrape: "true"` annotation, but using a ServiceMonitor provides more control and is the recommended approach with Prometheus Operator.

### Step 3: Verify Prometheus is Scraping DCGM Metrics

Wait a few minutes for Prometheus to discover and start scraping the DCGM Exporter, then verify:

```bash
# Port-forward Prometheus UI
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090

# In another terminal, check targets (should show nvidia-dcgm-exporter as "up")
curl -s "http://localhost:9090/api/v1/targets" | jq '.data.activeTargets[] | select(.labels.job | contains("dcgm"))'

# Query a DCGM metric
curl -s "http://localhost:9090/api/v1/query?query=DCGM_FI_DEV_GPU_UTIL" | jq '.data.result'
```

**Expected Result:**
- Target status: `"health": "up"`
- Metrics should return with labels like `gpu`, `UUID`, `Hostname`, etc.

### Step 4: Access Grafana Dashboard

```bash
# Get Grafana admin password
kubectl get secret -n monitoring kube-prometheus-stack-grafana \
  -o jsonpath="{.data.admin-password}" | base64 -d && echo

# Port-forward Grafana (default port 3000)
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
```

**Access Grafana:**
- URL: `http://localhost:3000`
- Username: `admin`
- Password: (from command above)

### Step 5: Configure Prometheus Data Source in Grafana

1. Log into Grafana
2. Go to **Configuration** → **Data Sources**
3. Click **Add data source**
4. Select **Prometheus**
5. Set URL to: `http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090`
6. Click **Save & Test** (should show "Data source is working")

### Step 6: Create DCGM Metrics Dashboard

Create a new dashboard or import a pre-built one:

**Option A: Create Dashboard Manually**

1. Go to **Dashboards** → **New Dashboard**
2. Add panels with these PromQL queries:

**Panel 1: GPU Utilization**
```promql
DCGM_FI_DEV_GPU_UTIL
```
- Visualization: Time series
- Unit: Percent (0-100)
- Legend: `{{gpu}} - {{modelName}}`

**Panel 2: Memory Utilization**
```promql
(DCGM_FI_DEV_FB_USED / DCGM_FI_DEV_FB_TOTAL) * 100
```
- Visualization: Time series
- Unit: Percent (0-100)

**Panel 3: GPU Temperature**
```promql
DCGM_FI_DEV_GPU_TEMP
```
- Visualization: Time series
- Unit: Celsius
- Thresholds: Green < 70, Yellow 70-85, Red > 85

**Panel 4: Power Usage**
```promql
DCGM_FI_DEV_POWER_USAGE
```
- Visualization: Time series
- Unit: Watts

**Panel 5: Memory Clock**
```promql
DCGM_FI_DEV_MEM_CLOCK
```
- Visualization: Time series
- Unit: MHz

**Panel 6: SM Clock**
```promql
DCGM_FI_DEV_SM_CLOCK
```
- Visualization: Time series
- Unit: MHz

**Panel 7: Tensor Core Utilization**
```promql
DCGM_FI_DEV_TENSOR_ACTIVE
```
- Visualization: Time series
- Unit: Percent

**Panel 8: PCIe RX Throughput**
```promql
DCGM_FI_DEV_PCIE_RX_THROUGHPUT
```
- Visualization: Time series
- Unit: Bytes/sec (convert to GB/s)

**Panel 9: PCIe TX Throughput**
```promql
DCGM_FI_DEV_PCIE_TX_THROUGHPUT
```
- Visualization: Time series
- Unit: Bytes/sec (convert to GB/s)

**Option B: Import Pre-built Dashboard**

You can also create a JSON dashboard file and import it. See the "Grafana Dashboard JSON" section below for a complete example.

### Step 7: Verify Metrics Collection

Test that metrics are flowing correctly:

```bash
# Query GPU utilization via Prometheus API
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090

# In another terminal
curl -s "http://localhost:9090/api/v1/query?query=DCGM_FI_DEV_GPU_UTIL" | \
  jq '.data.result[] | {gpu: .metric.gpu, value: .value[1], model: .metric.modelName}'

# Check all available DCGM metrics
curl -s "http://localhost:9090/api/v1/label/__name__/values" | \
  jq '.data[] | select(. | startswith("DCGM"))'
```

### Troubleshooting Prometheus/Grafana Setup

#### Issue: Prometheus Not Scraping DCGM Exporter

**Symptoms:**
- No DCGM metrics in Prometheus
- Target shows as "down" in Prometheus UI

**Diagnosis:**
```bash
# Check ServiceMonitor exists
kubectl get servicemonitor -n gpu-operator nvidia-dcgm-exporter

# Check DCGM Exporter service
kubectl get svc -n gpu-operator nvidia-dcgm-exporter

# Check DCGM Exporter pods
kubectl get pods -n gpu-operator -l app=nvidia-dcgm-exporter

# Check Prometheus targets
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# Then visit http://localhost:9090/targets
```

**Solution:**
- Verify ServiceMonitor namespace matches DCGM Exporter namespace
- Ensure ServiceMonitor selector matches service labels
- Check Prometheus logs: `kubectl logs -n monitoring prometheus-kube-prometheus-stack-prometheus-0`

#### Issue: No Metrics in Grafana

**Symptoms:**
- Grafana loads but shows "No data"

**Diagnosis:**
```bash
# Verify Prometheus data source is configured correctly
# Check Grafana logs
kubectl logs -n monitoring -l app.kubernetes.io/name=grafana

# Test Prometheus query directly
curl -s "http://localhost:9090/api/v1/query?query=DCGM_FI_DEV_GPU_UTIL"
```

**Solution:**
- Verify Prometheus data source URL is correct
- Ensure time range in Grafana includes data points
- Check that metrics exist in Prometheus first

### Quick Reference: Accessing Prometheus and Grafana

```bash
# Prometheus UI
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# Access at: http://localhost:9090

# Grafana UI
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
# Access at: http://localhost:3000
# Username: admin
# Password: kubectl get secret -n monitoring kube-prometheus-stack-grafana -o jsonpath="{.data.admin-password}" | base64 -d

# Check Prometheus targets
curl -s "http://localhost:9090/api/v1/targets" | jq '.data.activeTargets[] | select(.labels.job | contains("dcgm"))'

# Query DCGM metrics
curl -s "http://localhost:9090/api/v1/query?query=DCGM_FI_DEV_GPU_UTIL" | jq '.data.result'
```

---

## Practical Examples

### Example 1: Querying DCGM Metrics via Prometheus

```bash
# Port-forward DCGM Exporter
kubectl port-forward -n gpu-operator svc/nvidia-dcgm-exporter 9400:9400

# Query GPU utilization
curl http://localhost:9400/metrics | grep DCGM_FI_DEV_GPU_UTIL

# Query memory usage
curl http://localhost:9400/metrics | grep DCGM_FI_DEV_FB_USED
```

### Example 2: Using DCGM CLI

```bash
# Install DCGM CLI (if not already installed)
# On GPU node:
docker run --rm --gpus all nvcr.io/nvidia/k8s/dcgm:3.1.8-3.1.5-ubuntu22.04 dcgmi

# Monitor GPU in real-time
dcgmi dmon -e 155,150,100,203,252,155 -d 1

# Field IDs:
# 155 = GPU Utilization
# 150 = Memory Utilization  
# 100 = Memory Used
# 203 = Power Usage
# 252 = Temperature
# 155 = SM Occupancy
```

### Example 3: Prometheus Queries

```promql
# GPU Utilization (average across all GPUs)
avg(DCGM_FI_DEV_GPU_UTIL) by (instance, uuid)

# Memory Usage Percentage
(DCGM_FI_DEV_FB_USED / DCGM_FI_DEV_FB_TOTAL) * 100

# Power Usage (watts)
DCGM_FI_DEV_POWER_USAGE

# Temperature
DCGM_FI_DEV_GPU_TEMP

# Tensor Core Utilization
DCGM_FI_DEV_TENSOR_ACTIVE

# PCIe Bandwidth Utilization
(DCGM_FI_DEV_PCIE_RX_THROUGHPUT + DCGM_FI_DEV_PCIE_TX_THROUGHPUT) / PCIe_Max_Bandwidth * 100
```

### Example 4: Grafana Dashboard

Create a Grafana dashboard with these panels:

1. **GPU Utilization** - Line graph, 0-100%
2. **Memory Usage** - Gauge, 0-100%
3. **Power Draw** - Line graph, watts
4. **Temperature** - Line graph, Celsius
5. **Tensor Core Usage** - Line graph, 0-100%
6. **PCIe Bandwidth** - Line graph, GB/s
7. **ECC Errors** - Counter, total errors

### Example 5: Profiling Script

```bash
#!/bin/bash
# Profile GPU workload

# Start monitoring
kubectl port-forward -n gpu-operator svc/nvidia-dcgm-exporter 9400:9400 &
PF_PID=$!

# Wait for port-forward
sleep 2

# Collect metrics for 60 seconds
for i in {1..60}; do
    echo "=== Sample $i ===" >> metrics.log
    curl -s http://localhost:9400/metrics | grep -E "DCGM_FI_DEV_GPU_UTIL|DCGM_FI_DEV_FB_USED|DCGM_FI_DEV_POWER_USAGE" >> metrics.log
    sleep 1
done

# Stop port-forward
kill $PF_PID

# Analyze results
echo "=== Analysis ==="
grep DCGM_FI_DEV_GPU_UTIL metrics.log | awk '{print $2}' | awk '{sum+=$1; count++} END {print "Avg GPU Util:", sum/count"%"}'
```

---

## Troubleshooting

### Common Issues

#### Issue 1: DCGM Exporter Not Collecting Metrics

**Symptoms:**
- No metrics in Prometheus
- DCGM Exporter pod not running

**Diagnosis:**
```bash
# Check DCGM Exporter pod
kubectl get pods -n gpu-operator -l app=nvidia-dcgm-exporter

# Check logs
kubectl logs -n gpu-operator -l app=nvidia-dcgm-exporter

# Check if DCGM Agent is running
kubectl exec -n gpu-operator <dcgm-exporter-pod> -- dcgmi discovery -l
```

**Solution:**
```bash
# Restart DCGM Exporter
kubectl rollout restart daemonset/nvidia-dcgm-exporter -n gpu-operator

# Verify GPU Operator is healthy
kubectl get pods -n gpu-operator
```

#### Issue 2: Metrics Show Zero or Incorrect Values

**Symptoms:**
- All metrics showing 0
- Metrics not updating

**Diagnosis:**
```bash
# Check if GPU is accessible
kubectl exec -n gpu-operator <dcgm-exporter-pod> -- nvidia-smi

# Check DCGM Agent connection
kubectl exec -n gpu-operator <dcgm-exporter-pod> -- dcgmi health -c
```

**Solution:**
- Verify GPU Operator installation
- Check GPU driver is installed
- Restart DCGM components

#### Issue 3: High GPU Utilization but Low Performance

**Symptoms:**
- GPU utilization >90%
- But workload is slow

**Analysis:**
```bash
# Check memory utilization
# Low memory util + high GPU util = compute-bound
# High memory util + high GPU util = balanced
# Check for throttling
dcgmi dmon -e 203,252 -d 1
# Look for power throttling or thermal throttling
```

**Solution:**
- Check for thermal throttling (temperature >90°C)
- Check for power throttling
- Optimize kernel efficiency
- Check for memory bandwidth bottlenecks

---

## Resources & Next Steps

### Official Documentation

1. **NVIDIA GPU Operator**
   - GitHub: https://github.com/NVIDIA/gpu-operator
   - Documentation: https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/

2. **DCGM Documentation**
   - User Guide: https://docs.nvidia.com/datacenter/dcgm/latest/dcgm-user-guide/
   - API Reference: https://docs.nvidia.com/datacenter/dcgm/latest/dcgm-api/

3. **DCGM Exporter**
   - GitHub: https://github.com/NVIDIA/dcgm-exporter
   - Metrics Reference: https://github.com/NVIDIA/dcgm-exporter#metrics

### Training & Certification

1. **NVIDIA DLI Courses**
   - Accelerating Applications with CUDA C/C++
   - Fundamentals of Accelerated Computing with CUDA Python

2. **NVIDIA Developer Blog**
   - GPU profiling articles
   - Performance optimization guides

### Tools

1. **NVIDIA Nsight Systems** - System-wide performance analysis
2. **NVIDIA Nsight Compute** - Kernel-level profiling
3. **NVIDIA Nsight Graphics** - Graphics debugging
4. **Prometheus** - Metrics collection
5. **Grafana** - Visualization

### Practice Exercises

1. **Exercise 1: Basic Profiling**
   - Deploy GPU Operator
   - Set up DCGM Exporter
   - Collect baseline metrics
   - Run sample workload
   - Analyze metrics

2. **Exercise 2: Identify Bottlenecks**
   - Run training workload
   - Identify if compute-bound or memory-bound
   - Propose optimizations
   - Measure improvement

3. **Exercise 3: Multi-GPU Profiling**
   - Deploy multi-GPU workload
   - Monitor NVLink usage
   - Identify load imbalance
   - Optimize data distribution

### Next Steps

1. **Week 1-2: Foundation**
   - Install and configure GPU Operator
   - Learn DCGM basics
   - Set up monitoring stack

2. **Week 3-4: Metrics Deep Dive**
   - Study each metric category
   - Practice interpreting metrics
   - Build Grafana dashboards

3. **Week 5-6: Profiling**
   - Profile real workloads
   - Identify bottlenecks
   - Optimize performance

4. **Week 7-8: Advanced Topics**
   - Multi-GPU profiling
   - Troubleshooting complex issues
   - Best practices

---

## Quick Reference

### Key Metrics Summary

| Metric | Field ID | Unit | Good Range | What It Tells You |
|--------|----------|------|------------|-------------------|
| GPU Utilization | 155 | % | 70-95% | How busy GPU is |
| Memory Utilization | 150 | % | 40-70% | Memory controller activity |
| Memory Used | 100 | Bytes | 60-80% of total | GPU memory usage |
| SM Occupancy | 155 | % | 50-80% | SM utilization |
| Tensor Core Active | - | % | 50-80% | Tensor core usage |
| Power Usage | 203 | W | 80-95% TDP | Power consumption |
| Temperature | 252 | °C | 70-85°C | Thermal status |
| PCIe RX | - | B/s | <30% capacity | Data input rate |
| PCIe TX | - | B/s | <30% capacity | Data output rate |
| NVLink BW | - | B/s | >80% capacity | Multi-GPU bandwidth |

### Common Commands

```bash
# Check GPU Operator status
kubectl get pods -n gpu-operator

# Check DCGM Exporter
kubectl get pods -n gpu-operator -l app=nvidia-dcgm-exporter

# Port-forward DCGM Exporter
kubectl port-forward -n gpu-operator svc/nvidia-dcgm-exporter 9400:9400

# Query metrics
curl http://localhost:9400/metrics | grep DCGM

# DCGM CLI health check
dcgmi health -c

# Monitor GPU in real-time
dcgmi dmon -e 155,150,100,203,252 -d 1
```

---

**Last Updated:** November 2025  
**Author:** SME Learning Guide  
**Version:** 1.0

