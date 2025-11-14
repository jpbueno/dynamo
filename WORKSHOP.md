# GPU Operator & DCGM Metrics Workshop

> Hands-on workshop: Install Kubernetes with GPU Operator, configure DCGM metrics export to Prometheus/Grafana, and learn to identify GPU saturation root causes

## 📖 Table of Contents

1. [Workshop Objectives](#workshop-objectives)
2. [Workshop Quick Start](#workshop-quick-start)
3. [Phase 1: Installation](#phase-1-installation)
4. [Phase 2: Verification](#phase-2-verification)
5. [Phase 3: GPU Saturation Exercise](#phase-3-gpu-saturation-exercise)
6. [Understanding DCGM Metrics](#understanding-dcgm-metrics)
7. [Troubleshooting](#troubleshooting)
8. [Workshop Cleanup](#workshop-cleanup)
9. [Resources & Next Steps](#resources--next-steps)

---

## Workshop Objectives

By the end of this workshop, you will:

1. ✅ **Install and configure a fully operational Kubernetes cluster** on a GPU-enabled instance
2. ✅ **Install and configure NVIDIA GPU Operator** to manage GPU resources
3. ✅ **Configure DCGM Exporter** to export GPU metrics to Prometheus
4. ✅ **Set up Prometheus and Grafana** for metrics visualization
5. ✅ **Complete a hands-on exercise** to measure GPU saturation and identify root causes

### Workshop Overview

This workshop focuses on practical, hands-on experience with:
- **Kubernetes cluster setup** - Single-node kubeadm cluster
- **GPU Operator** - Automated GPU resource management
- **DCGM Metrics** - Real-time GPU performance data
- **Monitoring Stack** - Prometheus and Grafana integration
- **Root Cause Analysis** - Identifying GPU saturation bottlenecks

### Prerequisites

- Ubuntu 22.04 server with GPU support
- Internet connectivity
- Sudo access
- Basic understanding of Kubernetes and Linux

**Estimated Time:** 2-3 hours

---

## Workshop Quick Start

This workshop is structured in three main phases:
1. **Installation** - Set up Kubernetes cluster, GPU Operator, and monitoring stack
2. **Verification** - Verify DCGM metrics are being exported to Prometheus/Grafana
3. **Exercise** - Measure GPU saturation and identify root causes

### Step 1: Installation (15-20 minutes)

For a fresh Ubuntu 22.04 server, install everything with a single script:

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

### Step 2: Verification

After installation completes, verify everything is working:
1. Check Kubernetes cluster: `kubectl get nodes`
2. Check GPU Operator: `kubectl get pods -n gpu-operator`
3. Check DCGM Exporter: `kubectl get pods -n gpu-operator -l app=nvidia-dcgm-exporter`
4. Check Prometheus/Grafana: `kubectl get pods -n monitoring`

See [Phase 2: Verification](#phase-2-verification) for detailed verification steps.

### Step 3: Cleanup After Workshop

When you're done with the workshop, clean up all resources:

```bash
# Run the cleanup script
bash cleanup-gpu-operator-stack.sh
```

**What gets removed:**
- Kubernetes cluster
- GPU Operator
- Prometheus/Grafana stack
- Helm releases
- System configurations (some)

**Note:** Kubernetes tools (kubectl, kubeadm, kubelet) and Helm are kept for easy reinstallation. To fully remove them, run:
```bash
sudo apt-get purge -y kubelet kubeadm kubectl kubernetes-cni
```

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

**Related scripts:**
- `bash cleanup-gpu-operator-stack.sh` - Clean up all components after workshop
- `bash gpu-operator-stack.sh snapshot` - Create snapshot of current state
- `bash gpu-operator-stack.sh restore <dir>` - Restore from snapshot
- `bash gpu-operator-stack.sh status` - Show current stack status

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

## Phase 3: GPU Saturation Exercise

### Exercise Objective

**Goal:** Measure GPU saturation and identify the root cause of performance bottlenecks.

In this exercise, you will:
1. Deploy a GPU workload that causes saturation
2. Collect DCGM metrics using Prometheus
3. Analyze metrics in Grafana to identify root causes
4. Determine if the bottleneck is compute-bound, memory-bound, or I/O-bound

### Exercise Setup

#### Step 1: Deploy a GPU Workload

Create a sample GPU workload that will stress different GPU resources:

```bash
# Create a GPU workload manifest
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: gpu-workload
spec:
  restartPolicy: Never
  containers:
  - name: cuda-workload
    image: nvidia/cuda:12.0.0-base-ubuntu22.04
    command: ["/bin/bash", "-c"]
    args:
    - |
      nvidia-smi -l 1 &
      # Run compute-intensive workload
      while true; do
        python3 -c "
import time
import numpy as np
# Simulate compute-intensive operations
a = np.random.rand(10000, 10000).astype(np.float32)
b = np.random.rand(10000, 10000).astype(np.float32)
for _ in range(100):
    c = np.dot(a, b)
time.sleep(0.1)
        "
      done
    resources:
      limits:
        nvidia.com/gpu: 1
EOF
```

**Note:** This workload simulates compute-intensive operations. For real workloads, use your actual GPU application.

#### Step 2: Monitor GPU Metrics

Open Grafana and create a new dashboard with these panels:

**Panel 1: GPU Utilization**
```promql
DCGM_FI_DEV_GPU_UTIL{instance=~".*"}
```
- Visualization: Time series
- Y-axis: 0-100%
- Title: "GPU Utilization (%)"

**Panel 2: Memory Utilization**
```promql
(DCGM_FI_DEV_FB_USED{instance=~".*"} / DCGM_FI_DEV_FB_TOTAL{instance=~".*"}) * 100
```
- Visualization: Time series
- Y-axis: 0-100%
- Title: "GPU Memory Utilization (%)"

**Panel 3: Memory Used vs Total**
```promql
DCGM_FI_DEV_FB_USED{instance=~".*"}
DCGM_FI_DEV_FB_TOTAL{instance=~".*"}
```
- Visualization: Time series
- Title: "GPU Memory Usage (Bytes)"

**Panel 4: SM (Streaming Multiprocessor) Utilization**
```promql
DCGM_FI_DEV_SM_OCCUPANCY{instance=~".*"}
```
- Visualization: Time series
- Y-axis: 0-100%
- Title: "SM Occupancy (%)"

**Panel 5: Power Usage**
```promql
DCGM_FI_DEV_POWER_USAGE{instance=~".*"}
```
- Visualization: Time series
- Title: "Power Usage (Watts)"

**Panel 6: Temperature**
```promql
DCGM_FI_DEV_GPU_TEMP{instance=~".*"}
```
- Visualization: Time series
- Title: "GPU Temperature (°C)"

**Panel 7: PCIe RX Throughput**
```promql
DCGM_FI_DEV_PCIE_RX_THROUGHPUT{instance=~".*"}
```
- Visualization: Time series
- Title: "PCIe RX Throughput (Bytes/s)"

**Panel 8: PCIe TX Throughput**
```promql
DCGM_FI_DEV_PCIE_TX_THROUGHPUT{instance=~".*"}
```
- Visualization: Time series
- Title: "PCIe TX Throughput (Bytes/s)"

### Exercise Tasks

#### Task 1: Baseline Measurement

1. **Before starting the workload**, collect baseline metrics:
   ```bash
   # Query Prometheus for current GPU state
   kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090 &
   
   # In another terminal, query metrics
   curl 'http://localhost:9090/api/v1/query?query=DCGM_FI_DEV_GPU_UTIL' | jq
   ```

2. **Document baseline values:**
   - GPU Utilization: Should be near 0%
   - Memory Used: Should be minimal
   - Power Usage: Idle power consumption
   - Temperature: Idle temperature

#### Task 2: Run Workload and Observe Saturation

1. **Deploy the workload** (from Step 1 above)

2. **Wait 2-3 minutes** for metrics to stabilize

3. **Observe metrics in Grafana dashboard**

4. **Document saturation values:**
   - GPU Utilization: ______%
   - Memory Utilization: ______%
   - SM Occupancy: ______%
   - Power Usage: ______W
   - Temperature: ______°C

#### Task 3: Root Cause Analysis

Use the following decision tree to identify the root cause:

**Scenario A: High GPU Utilization (>90%) + Low Memory Utilization (<50%)**
- **Root Cause:** Compute-bound workload
- **Indicators:**
  - GPU Utilization: High (>90%)
  - Memory Utilization: Low (<50%)
  - SM Occupancy: High (>80%)
  - Power Usage: High (near TDP)
- **Solution:** Optimize compute kernels, use Tensor Cores, increase batch size

**Scenario B: High GPU Utilization (>90%) + High Memory Utilization (>80%)**
- **Root Cause:** Memory-bound workload
- **Indicators:**
  - GPU Utilization: High (>90%)
  - Memory Utilization: High (>80%)
  - Memory Used: Near total GPU memory
  - SM Occupancy: May be lower due to memory stalls
- **Solution:** Reduce memory footprint, optimize memory access patterns, use mixed precision

**Scenario C: Low GPU Utilization (<50%) + High PCIe Throughput**
- **Root Cause:** I/O-bound workload (data transfer bottleneck)
- **Indicators:**
  - GPU Utilization: Low (<50%)
  - PCIe RX/TX: High (>30% of PCIe bandwidth)
  - Memory Utilization: Variable
- **Solution:** Optimize data pipeline, use data prefetching, increase batch size

**Scenario D: High GPU Utilization + High Temperature (>85°C)**
- **Root Cause:** Thermal throttling
- **Indicators:**
  - Temperature: High (>85°C)
  - Power Usage: May drop due to throttling
  - GPU Utilization: May fluctuate
- **Solution:** Improve cooling, reduce power limit, optimize workload

**Scenario E: High GPU Utilization + Low SM Occupancy (<50%)**
- **Root Cause:** Kernel efficiency issues
- **Indicators:**
  - GPU Utilization: High (>90%)
  - SM Occupancy: Low (<50%)
  - Memory Utilization: Variable
- **Solution:** Optimize kernel launch configuration, increase occupancy, reduce register usage

#### Task 4: Create Analysis Report

Create a report documenting:

1. **Baseline Metrics:**
   ```
   GPU Utilization: X%
   Memory Used: X GB / X GB
   Power: X W
   Temperature: X°C
   ```

2. **Saturation Metrics:**
   ```
   GPU Utilization: X%
   Memory Utilization: X%
   SM Occupancy: X%
   Power: X W
   Temperature: X°C
   PCIe RX: X GB/s
   PCIe TX: X GB/s
   ```

3. **Root Cause Identification:**
   - Which scenario matches your workload? (A, B, C, D, or E)
   - What evidence supports this conclusion?
   - What metrics were most indicative?

4. **Recommendations:**
   - What optimizations would you recommend?
   - What additional metrics would help confirm the root cause?

### Exercise Prometheus Queries

Use these queries in Prometheus to analyze GPU saturation:

```promql
# Average GPU Utilization over last 5 minutes
avg_over_time(DCGM_FI_DEV_GPU_UTIL[5m])

# Memory utilization percentage
(avg_over_time(DCGM_FI_DEV_FB_USED[5m]) / avg_over_time(DCGM_FI_DEV_FB_TOTAL[5m])) * 100

# Power efficiency (utilization per watt)
avg_over_time(DCGM_FI_DEV_GPU_UTIL[5m]) / avg_over_time(DCGM_FI_DEV_POWER_USAGE[5m])

# Check for thermal throttling (temperature > 85°C)
DCGM_FI_DEV_GPU_TEMP > 85

# PCIe bandwidth utilization
(avg_over_time(DCGM_FI_DEV_PCIE_RX_THROUGHPUT[5m]) + avg_over_time(DCGM_FI_DEV_PCIE_TX_THROUGHPUT[5m])) / 32e9 * 100

# SM Occupancy (if available)
avg_over_time(DCGM_FI_DEV_SM_OCCUPANCY[5m])
```

### Exercise Checklist

- [ ] Kubernetes cluster is operational
- [ ] GPU Operator is installed and running
- [ ] DCGM Exporter is collecting metrics
- [ ] Prometheus is scraping DCGM metrics
- [ ] Grafana is configured with Prometheus data source
- [ ] Baseline metrics collected
- [ ] GPU workload deployed
- [ ] Saturation metrics observed
- [ ] Root cause identified using decision tree
- [ ] Analysis report created

### Expected Outcomes

After completing this exercise, you should be able to:
- ✅ Deploy GPU workloads on Kubernetes
- ✅ Collect and visualize DCGM metrics
- ✅ Identify GPU saturation patterns
- ✅ Determine root causes of performance bottlenecks
- ✅ Make data-driven optimization recommendations

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

## Workshop Cleanup

### Cleaning Up After the Workshop

After completing the workshop exercises, you should clean up all installed components to free up resources and return the server to a clean state.

### Automated Cleanup

Use the provided cleanup script to remove all components:

```bash
# Run the cleanup script
bash cleanup-gpu-operator-stack.sh
```

**What the cleanup script removes:**
- ✅ Kubernetes cluster (kubeadm reset)
- ✅ GPU Operator Helm release
- ✅ Prometheus/Grafana Helm release
- ✅ Flannel CNI plugin
- ✅ All custom namespaces
- ✅ Helm repositories
- ✅ Helm cache
- ✅ ServiceMonitor resources
- ✅ Containerd configuration (reset to defaults)
- ✅ Firewall rules (Kubernetes-specific)

**What is kept (for easy reinstallation):**
- Kubernetes tools (kubectl, kubeadm, kubelet)
- Helm binary
- System configurations (modules, sysctl) - partially kept

### Manual Cleanup Steps

If you prefer to clean up manually or the script doesn't cover everything:

```bash
# 1. Remove Helm releases
helm uninstall kube-prometheus-stack -n monitoring
helm uninstall gpu-operator -n gpu-operator

# 2. Remove namespaces
kubectl delete namespace monitoring
kubectl delete namespace gpu-operator
kubectl delete namespace kube-flannel

# 3. Remove Flannel CNI
kubectl delete -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

# 4. Reset Kubernetes cluster
sudo kubeadm reset -f

# 5. Remove Kubernetes config files
rm -rf ~/.kube
sudo rm -rf /etc/kubernetes
sudo rm -rf /var/lib/etcd
sudo rm -rf /var/lib/kubelet
sudo rm -rf /etc/cni/net.d
sudo rm -rf /opt/cni/bin

# 6. Clean Helm
helm repo remove nvidia
helm repo remove prometheus-community
rm -rf ~/.cache/helm

# 7. Reset containerd (optional)
sudo cp /etc/containerd/config.toml /etc/containerd/config.toml.backup
containerd config default | sudo tee /etc/containerd/config.toml
sudo systemctl restart containerd
```

### Complete Removal (Optional)

To completely remove Kubernetes tools and start fresh:

```bash
# Remove Kubernetes packages
sudo apt-mark unhold kubelet kubeadm kubectl
sudo apt-get purge -y kubelet kubeadm kubectl kubernetes-cni

# Remove Helm (optional)
sudo rm -f /usr/local/bin/helm

# Remove system configurations (optional)
sudo rm -f /etc/modules-load.d/k8s.conf
sudo rm -f /etc/sysctl.d/k8s.conf
```

### Verification

After cleanup, verify everything is removed:

```bash
# Check no Kubernetes cluster exists
kubectl cluster-info 2>&1 | grep -q "refused" && echo "Cluster removed" || echo "Cluster still exists"

# Check no Helm releases
helm list --all-namespaces

# Check no GPU Operator pods
kubectl get pods --all-namespaces | grep -i gpu || echo "No GPU Operator pods found"

# Check disk space freed
df -h /home
```

### Reinstallation

To reinstall everything after cleanup, simply run:

```bash
bash install-gpu-operator-stack.sh
```

The installation script will detect that Kubernetes tools are already installed and skip those steps, making reinstallation faster.

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

