# GPU Saturation Measurement Workshop

> **Complete hands-on workshop**: Learn the best practices for measuring GPU saturation and identifying root causes using DCGM metrics, Prometheus, and Grafana on Kubernetes.

## 📖 Table of Contents

1. [Workshop Overview](#workshop-overview)
2. [Prerequisites](#prerequisites)
3. [Phase 1: Environment Setup](#phase-1-environment-setup)
4. [Phase 2: Verification](#phase-2-verification)
5. [Phase 3: Deploy GPU Workload](#phase-3-deploy-gpu-workload)
6. [Phase 4: Generate Load & Measure Saturation](#phase-4-generate-load--measure-saturation)
7. [Phase 5: Root Cause Analysis](#phase-5-root-cause-analysis)
8. [Understanding DCGM Metrics](#understanding-dcgm-metrics)
9. [Troubleshooting](#troubleshooting)
10. [Workshop Cleanup](#workshop-cleanup)
11. [Resources & Next Steps](#resources--next-steps)

---

## Workshop Overview

### Objectives

By the end of this workshop, you will:

1. ✅ **Set up a complete GPU monitoring environment** on Kubernetes
2. ✅ **Deploy GPU workloads** that saturate GPU resources
3. ✅ **Collect and visualize DCGM metrics** using Prometheus and Grafana
4. ✅ **Identify root causes** of GPU saturation using data-driven analysis
5. ✅ **Apply best practices** for GPU performance measurement and optimization

### Workshop Structure

This workshop is organized into 5 phases:

1. **Environment Setup** (15-20 min) - Install Kubernetes, GPU Operator, monitoring stack
2. **Verification** (5 min) - Verify all components are working
3. **Deploy GPU Workload** (10 min) - Deploy a model that will use GPU resources
4. **Generate Load & Measure** (20 min) - Generate load and observe saturation metrics
5. **Root Cause Analysis** (30 min) - Analyze metrics to identify bottlenecks

**Total Time:** ~90 minutes

### What You'll Learn

- How to set up GPU monitoring on Kubernetes
- How to deploy GPU workloads
- How to interpret DCGM metrics
- How to identify compute-bound vs memory-bound workloads
- How to detect I/O bottlenecks and thermal throttling
- Best practices for GPU performance measurement

---

## Prerequisites

### Hardware Requirements

- **GPU-enabled server** (any NVIDIA GPU supported)
- **Ubuntu 22.04** (other Linux distributions may work but not tested)
- **Minimum Resources:**
  - 4 CPU cores
  - 8GB RAM
  - 20GB disk space
  - 1 NVIDIA GPU (any model)

### Software Requirements

- **Internet connectivity** (for downloading images and packages)
- **Sudo access** (for system configuration)
- **Basic Linux knowledge** (command line, file editing)
- **Basic Kubernetes knowledge** (helpful but not required)

### Pre-installation Check

```bash
# Check GPU availability
nvidia-smi

# Check OS version
cat /etc/os-release | grep VERSION_ID

# Check disk space
df -h

# Check internet connectivity
ping -c 3 8.8.8.8
```

---

## Phase 1: Environment Setup

### Step 1.1: Clone Repository

```bash
# Clone the repository
git clone https://github.com/jpbueno/dynamo.git
cd dynamo

# Verify scripts are present
ls -la *.sh
```

### Step 1.2: Run Installation Script

The installation script will set up everything automatically:

```bash
# Run the automated installation
bash setup.sh
```

**What gets installed:**
- ✅ Kubernetes cluster (kubeadm)
- ✅ Flannel CNI plugin
- ✅ NVIDIA GPU Operator
- ✅ DCGM Exporter
- ✅ Prometheus monitoring stack
- ✅ Grafana visualization
- ✅ ServiceMonitor for DCGM metrics
- ✅ kubectl alias (`k`) and autocomplete

**Installation Progress:**
The script shows progress with `[1/10]` through `[10/10]` indicators. You'll see:
- Prerequisites installation
- Kubernetes cluster initialization
- CNI installation
- GPU Operator installation (5-10 minutes)
- Prometheus/Grafana installation (5-10 minutes)

**Expected Output:**
```
[1/10] Installing Prerequisites
[2/10] Initializing Kubernetes Cluster
[3/10] Waiting for CoreDNS
[4/10] Installing Flannel CNI
[5/10] Installing Helm
[6/10] Installing GPU Operator
[7/10] Installing Prometheus and Grafana
[8/10] Configuring DCGM ServiceMonitor
[9/10] Verifying Installation
[10/10] Installation Complete!
```

### Step 1.3: Configure Shell

After installation, reload your shell to use the `k` alias:

```bash
# Reload shell configuration
source ~/.bashrc

# Verify kubectl alias works
k get nodes
```

---

## Phase 2: Verification

### Step 2.1: Verify Kubernetes Cluster

```bash
# Check cluster status
k get nodes

# Expected output: Node should show STATUS=Ready
# Example:
# NAME         STATUS   ROLES           AGE   VERSION
# shadecloud   Ready    control-plane   5m    v1.31.14
```

### Step 2.2: Verify GPU Operator

```bash
# Check GPU Operator pods
k get pods -n gpu-operator

# Expected: All pods should be Running
# Key pods to check:
# - gpu-operator-*
# - nvidia-device-plugin-daemonset-*
# - nvidia-dcgm-exporter-*
```

### Step 2.3: Verify DCGM Exporter

```bash
# Check DCGM Exporter pod
k get pods -n gpu-operator -l app=nvidia-dcgm-exporter

# Port-forward to test metrics endpoint
k port-forward -n gpu-operator svc/nvidia-dcgm-exporter 9400:9400 &
sleep 2

# Query metrics (in another terminal)
curl http://localhost:9400/metrics | grep DCGM | head -10

# Stop port-forward
pkill -f "port-forward.*9400"
```

### Step 2.4: Verify Prometheus

```bash
# Check Prometheus pods
k get pods -n monitoring | grep prometheus
```

#### Access Prometheus from Local Machine (Brev / Remote Server)

**For Brev Environments:**

**Option 1: Brev SSH with Port Forwarding**

On your **local machine**:

```bash
# Create SSH tunnel using Brev CLI
brev ssh <workspace-name> -L 9090:localhost:9090

# Keep this running, then in your Brev workspace, start port-forward:
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
```

Then visit `http://localhost:9090` on your **local machine** and search for: `DCGM_FI_DEV_GPU_UTIL`

**Option 2: Direct SSH Tunnel (Generic)**

On your **local machine**:

```bash
# For Brev: use your Brev SSH command
# For generic server: use standard SSH
ssh -L 9090:localhost:9090 user@remote-server-ip \
  "kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090"
```

#### Access Prometheus Locally (Same Machine)

```bash
# Port-forward Prometheus
k port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090 &

# Visit http://localhost:9090 in your browser
# Search for: DCGM_FI_DEV_GPU_UTIL
# You should see DCGM metrics if ServiceMonitor is working
```

### Step 2.5: Verify Grafana

```bash
# Get Grafana password
kubectl get secret -n monitoring kube-prometheus-stack-grafana \
  -o jsonpath="{.data.admin-password}" | base64 -d
echo ""
```

#### Access Grafana from Local Machine (Brev / Remote Server)

If you're running the workshop on a **Brev environment** or remote server and want to access Grafana from your local computer:

**For Brev Environments:**

**Option 1: Brev SSH with Port Forwarding (Recommended)**

On your **local machine**, create an SSH tunnel:

```bash
# Using Brev CLI - forward Grafana port (3000) from Brev workspace to local machine
brev ssh <workspace-name> -L 3000:localhost:3000

# Keep this running, then in your Brev workspace (another terminal), start port-forward:
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
```

Then visit `http://localhost:3000` on your **local machine**.

**Option 2: Direct SSH Tunnel (Single Command)**

On your **local machine**:

```bash
# Create SSH tunnel and port-forward in one command (Brev)
brev ssh <workspace-name> -L 3000:localhost:3000 \
  "kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80"
```

Then visit `http://localhost:3000` on your **local machine**.

**For Generic Remote Servers:**

**Option 1: SSH Port Forwarding**

On your **local machine**:

```bash
# Forward Grafana port (3000) from remote server to local machine
ssh -L 3000:localhost:3000 user@remote-server-ip

# In another terminal on the remote server, start port-forward
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
```

**Option 2: Port Forward on Remote Server**

If you're already SSH'd into the remote server:

```bash
# On remote server - start port-forward
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

# Keep this running, then on your LOCAL machine, create SSH tunnel:
# ssh -L 3000:localhost:3000 user@remote-server-ip
```

#### Access Grafana Locally (Same Machine)

If you're running everything on the same machine:

```bash
# Port-forward Grafana
k port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80 &

# Visit http://localhost:3000
# Login: admin / <password from above>
```

### Step 2.6: Configure Prometheus Data Source in Grafana

1. Go to **Configuration** → **Data Sources**
2. Click **Add data source**
3. Select **Prometheus**
4. Set URL: `http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090`
5. Click **Save & Test**
6. You should see "Data source is working"

---

## Phase 3: Deploy GPU Workload

### Step 3.1: Deploy a GPU Workload Script

We'll use a helper script to deploy a GPU workload:

```bash
# Deploy a compute-intensive workload
bash deploy-gpu-workload.sh compute

# Or deploy a memory-intensive workload
bash deploy-gpu-workload.sh memory

# Or deploy a custom workload
bash deploy-gpu-workload.sh custom
```

### Step 3.2: Manual Deployment (Alternative)

If you prefer manual deployment:

```bash
# Create a compute-intensive workload
cat <<EOF | k apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: gpu-workload-compute
spec:
  restartPolicy: Never
  containers:
  - name: cuda-workload
    image: nvidia/cuda:12.0.0-base-ubuntu22.04
    command: ["/bin/bash", "-c"]
    args:
    - |
      apt-get update && apt-get install -y python3 python3-pip
      pip3 install numpy
      nvidia-smi -l 1 &
      python3 <<PYTHON
import time
import numpy as np
# Compute-intensive: Large matrix multiplications
while True:
    a = np.random.rand(10000, 10000).astype(np.float32)
    b = np.random.rand(10000, 10000).astype(np.float32)
    for _ in range(100):
        c = np.dot(a, b)
    time.sleep(0.1)
PYTHON
    resources:
      limits:
        nvidia.com/gpu: 1
EOF
```

### Step 3.3: Verify Workload is Running

```bash
# Check pod status
k get pods | grep gpu-workload

# Check GPU usage
k exec -it gpu-workload-compute -- nvidia-smi

# View logs
k logs gpu-workload-compute -f
```

---

## Phase 4: Generate Load & Measure Saturation

### Step 4.1: Collect Baseline Metrics

**Before generating load**, collect baseline metrics:

```bash
# Port-forward Prometheus
k port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090 &

# Query baseline metrics (focus on the 3 key signals)
curl -s 'http://localhost:9090/api/v1/query?query=DCGM_FI_PROF_SM_ACTIVE' | jq '.data.result[0].value[1]'
curl -s 'http://localhost:9090/api/v1/query?query=DCGM_FI_PROF_DRAM_ACTIVE' | jq '.data.result[0].value[1]'
curl -s 'http://localhost:9090/api/v1/query?query=DCGM_FI_PROF_PIPE_TENSOR_ACTIVE' | jq '.data.result[0].value[1]'

# Document baseline values
echo "Baseline Metrics:" > metrics-baseline.txt
echo "SM Active: $(curl -s 'http://localhost:9090/api/v1/query?query=DCGM_FI_PROF_SM_ACTIVE' | jq -r '.data.result[0].value[1]')%" >> metrics-baseline.txt
echo "DRAM Active: $(curl -s 'http://localhost:9090/api/v1/query?query=DCGM_FI_PROF_DRAM_ACTIVE' | jq -r '.data.result[0].value[1]')%" >> metrics-baseline.txt
echo "Tensor Active: $(curl -s 'http://localhost:9090/api/v1/query?query=DCGM_FI_PROF_PIPE_TENSOR_ACTIVE' | jq -r '.data.result[0].value[1]')%" >> metrics-baseline.txt
echo "GPU Utilization: $(curl -s 'http://localhost:9090/api/v1/query?query=DCGM_FI_DEV_GPU_UTIL' | jq -r '.data.result[0].value[1]')%" >> metrics-baseline.txt
echo "Memory Used: $(curl -s 'http://localhost:9090/api/v1/query?query=DCGM_FI_DEV_FB_USED' | jq -r '.data.result[0].value[1]') bytes" >> metrics-baseline.txt
cat metrics-baseline.txt
```

### Step 4.2: Generate Load

The workload should already be running from Phase 3. If not:

```bash
# Deploy workload
bash deploy-gpu-workload.sh compute

# Wait for metrics to stabilize (2-3 minutes)
sleep 180
```

### Step 4.3: Create Grafana Dashboard

Create a comprehensive dashboard in Grafana:

1. Go to **Dashboards** → **New Dashboard**
2. Add the following panels:

#### Panel 1: GPU Utilization
- **Query:** `DCGM_FI_DEV_GPU_UTIL{instance=~".*"}`
- **Visualization:** Time series
- **Y-axis:** 0-100%
- **Title:** "GPU Utilization (%)"

#### Panel 2: Memory Utilization
- **Query:** `(DCGM_FI_DEV_FB_USED{instance=~".*"} / DCGM_FI_DEV_FB_TOTAL{instance=~".*"}) * 100`
- **Visualization:** Time series
- **Y-axis:** 0-100%
- **Title:** "GPU Memory Utilization (%)"

#### Panel 3: Memory Used vs Total
- **Query:** 
  - `DCGM_FI_DEV_FB_USED{instance=~".*"}`
  - `DCGM_FI_DEV_FB_TOTAL{instance=~".*"}`
- **Visualization:** Time series
- **Title:** "GPU Memory Usage (Bytes)"

#### Panel 4: SM Active (⭐ Critical - Real Compute Saturation)
- **Query:** `DCGM_FI_PROF_SM_ACTIVE{instance=~".*"}`
- **Visualization:** Time series
- **Y-axis:** 0-100%
- **Title:** "SM Active (%) - Real Compute Saturation"
- **Note:** This is the most important metric for true saturation detection

#### Panel 5: DRAM Active (⭐ Memory Bandwidth Saturation)
- **Query:** `DCGM_FI_PROF_DRAM_ACTIVE{instance=~".*"}`
- **Visualization:** Time series
- **Y-axis:** 0-100%
- **Title:** "DRAM Active (%) - Memory Bandwidth Saturation"

#### Panel 6: Tensor Active (⭐ AI/LLM Workloads)
- **Query:** `DCGM_FI_PROF_PIPE_TENSOR_ACTIVE{instance=~".*"}`
- **Visualization:** Time series
- **Y-axis:** 0-100%
- **Title:** "Tensor Core Active (%) - AI Workload Saturation"

#### Panel 7: Power Usage
- **Query:** `DCGM_FI_DEV_POWER_USAGE{instance=~".*"}`
- **Visualization:** Time series
- **Title:** "Power Usage (Watts)"

#### Panel 8: Temperature
- **Query:** `DCGM_FI_DEV_GPU_TEMP{instance=~".*"}`
- **Visualization:** Time series
- **Title:** "GPU Temperature (°C)"

#### Panel 9: PCIe RX Throughput
- **Query:** `DCGM_FI_DEV_PCIE_RX_THROUGHPUT{instance=~".*"}`
- **Visualization:** Time series
- **Title:** "PCIe RX Throughput (Bytes/s)"

#### Panel 10: PCIe TX Throughput
- **Query:** `DCGM_FI_DEV_PCIE_TX_THROUGHPUT{instance=~".*"}`
- **Visualization:** Time series
- **Title:** "PCIe TX Throughput (Bytes/s)"

#### Panel 11: Saturation Index (Calculated)
- **Query:** 
```promql
# Combined saturation indicator (0-100%)
(
  avg_over_time(DCGM_FI_PROF_SM_ACTIVE[5m]) * 0.5 +
  avg_over_time(DCGM_FI_PROF_DRAM_ACTIVE[5m]) * 0.3 +
  avg_over_time(DCGM_FI_PROF_PIPE_TENSOR_ACTIVE[5m]) * 0.2
)
```
- **Visualization:** Gauge or Stat
- **Y-axis:** 0-100%
- **Title:** "GPU Saturation Index (%)"
- **Thresholds:** Green: 0-70%, Yellow: 70-85%, Red: 85-100%

### Step 4.4: Observe Saturation Metrics

Watch the dashboard for 5-10 minutes and document:

```bash
# Create saturation metrics file (focus on the 3 key signals)
cat > metrics-saturation.txt <<EOF
Saturation Metrics (after 5 minutes of load):
============================================
⭐ THE 3 KEY SIGNALS:
SM Active: ______% (Most important - real compute saturation)
DRAM Active: ______% (Memory bandwidth saturation)
Tensor Active: ______% (AI workload saturation)

Supporting Metrics:
GPU Utilization: ______%
Memory Utilization: ______%
Power Usage: ______W
Temperature: ______°C
PCIe RX: ______GB/s
PCIe TX: ______GB/s
EOF

# Fill in values from Grafana dashboard
```

---

## Phase 5: Root Cause Analysis

### Step 5.1: Use Decision Tree

Analyze your metrics using this decision tree:

#### Scenario A: Compute-Saturated (Ideal for AI/LLM workloads)
- **Root Cause:** Fully compute-bound workload
- **Key Indicators:**
  - **SM Active: ≥85-90%** ⭐ (Primary indicator)
  - **Tensor Active: ≥90%** (for AI workloads)
  - DRAM Active: Low (<50%)
  - GPU Utilization: High (>90%)
  - Power Usage: High (near TDP)
- **Interpretation:** GPU is fully fed and compute-saturated
- **Solution:** Already optimal! Consider: increase batch size, use mixed precision, optimize kernels

#### Scenario B: Memory-Bound
- **Root Cause:** Memory bandwidth is the bottleneck
- **Key Indicators:**
  - **DRAM Active: >80%** ⭐ (Primary indicator)
  - **SM Active: Low (<50%)** (stalled waiting for memory)
  - GPU Utilization: May appear high but not truly saturated
  - Memory Used: High (near total GPU memory)
  - Tensor Active: Low (<10%)
- **Interpretation:** GPU cores are waiting for memory, not compute-saturated
- **Solution:** Reduce memory footprint, optimize memory access patterns, use mixed precision, increase memory bandwidth utilization

#### Scenario C: Input-Bound (I/O Bottleneck)
- **Root Cause:** Data pipeline bottleneck (CPU, network, disk)
- **Key Indicators:**
  - **SM Active: Low (<20%)** ⭐ (Primary indicator)
  - **DRAM Active: Low (<10%)**
  - **Tensor Active: Low (<10%)**
  - PCIe RX/TX: May be high or low
  - GPU Utilization: Low (<50%)
- **Interpretation:** GPU is idle waiting for data
- **Solution:** Optimize data pipeline, use data prefetching, increase batch size, optimize data loader, check CPU/network bottlenecks

#### Scenario D: PCIe-Bound
- **Root Cause:** Data transfer bottleneck between CPU and GPU
- **Key Indicators:**
  - **PCIe RX/TX: High (>30% of PCIe bandwidth)** ⭐
  - **SM Active: Low (<50%)**
  - DRAM Active: Variable
  - GPU Utilization: Low (<50%)
- **Interpretation:** GPU is stalled waiting for host transfers
- **Solution:** Optimize data pipeline, use pinned memory, overlap computation and transfer, increase batch size

#### Scenario E: Thermal Throttling
- **Root Cause:** GPU overheating
- **Key Indicators:**
  - Temperature: **>85°C** ⭐
  - Power Usage: May drop due to throttling
  - SM Active: May fluctuate
  - GPU Utilization: May fluctuate
- **Interpretation:** GPU is throttling performance to prevent overheating
- **Solution:** Improve cooling, reduce power limit, optimize workload to reduce heat generation

#### Scenario F: Kernel Efficiency Issues
- **Root Cause:** Kernels not efficiently utilizing GPU resources
- **Key Indicators:**
  - **SM Active: Low (<50%)** despite high GPU Utilization ⭐
  - GPU Utilization: High (>90%) but misleading
  - DRAM Active: Variable
  - Power Usage: Lower than expected
- **Interpretation:** GPU appears busy but cores aren't doing useful work
- **Solution:** Optimize kernel launch configuration, increase occupancy, reduce register usage, check for kernel gaps (use Nsight Systems)


### Step 5.2: Prometheus Queries for Analysis

Use these queries in Prometheus to analyze your workload:

#### The 3 Critical Saturation Signals

```promql
# 1. SM Active - Real compute saturation (MOST IMPORTANT)
avg_over_time(DCGM_FI_PROF_SM_ACTIVE[5m])

# 2. DRAM Active - Memory bandwidth saturation
avg_over_time(DCGM_FI_PROF_DRAM_ACTIVE[5m])

# 3. Tensor Active - AI/LLM workload saturation
avg_over_time(DCGM_FI_PROF_PIPE_TENSOR_ACTIVE[5m])
```

#### Supporting Metrics

```promql
# GPU Utilization (coarse-grained, less accurate)
avg_over_time(DCGM_FI_DEV_GPU_UTIL[5m])

# Memory utilization percentage
(avg_over_time(DCGM_FI_DEV_FB_USED[5m]) / avg_over_time(DCGM_FI_DEV_FB_TOTAL[5m])) * 100

# Power efficiency (utilization per watt)
avg_over_time(DCGM_FI_PROF_SM_ACTIVE[5m]) / avg_over_time(DCGM_FI_DEV_POWER_USAGE[5m])

# Check for thermal throttling (temperature > 85°C)
DCGM_FI_DEV_GPU_TEMP > 85

# PCIe bandwidth utilization
(avg_over_time(DCGM_FI_DEV_PCIE_RX_THROUGHPUT[5m]) + avg_over_time(DCGM_FI_DEV_PCIE_TX_THROUGHPUT[5m])) / 16e9 * 100

# Combined Saturation Index
(
  avg_over_time(DCGM_FI_PROF_SM_ACTIVE[5m]) * 0.5 +
  avg_over_time(DCGM_FI_PROF_DRAM_ACTIVE[5m]) * 0.3 +
  avg_over_time(DCGM_FI_PROF_PIPE_TENSOR_ACTIVE[5m]) * 0.2
)
```

#### Saturation Detection Queries

```promql
# Is GPU compute-saturated? (SM Active >= 85%)
DCGM_FI_PROF_SM_ACTIVE >= 85

# Is GPU memory-bound? (DRAM Active > 80% AND SM Active < 50%)
DCGM_FI_PROF_DRAM_ACTIVE > 80 and DCGM_FI_PROF_SM_ACTIVE < 50

# Is GPU input-bound? (SM Active < 20% AND DRAM Active < 10%)
DCGM_FI_PROF_SM_ACTIVE < 20 and DCGM_FI_PROF_DRAM_ACTIVE < 10

# Is GPU PCIe-bound? (High PCIe usage AND low SM Active)
(avg_over_time(DCGM_FI_DEV_PCIE_RX_THROUGHPUT[5m]) + avg_over_time(DCGM_FI_DEV_PCIE_TX_THROUGHPUT[5m])) / 16e9 * 100 > 30 
  and DCGM_FI_PROF_SM_ACTIVE < 50
```

### Step 5.3: Create Analysis Report

Document your findings:

```bash
cat > analysis-report.txt <<EOF
GPU Saturation Analysis Report
==============================

Baseline Metrics:
-----------------
$(cat metrics-baseline.txt)

Saturation Metrics:
--------------------
$(cat metrics-saturation.txt)

Root Cause Analysis:
--------------------
Scenario Identified: [A/B/C/D/E/F]
Evidence:
- [List key metrics that support your conclusion]
- **Which of the 3 key signals (SM Active, DRAM Active, Tensor Active) were most indicative?**
- Is the GPU truly saturated or just appearing busy?

Recommendations:
----------------
1. [Optimization recommendation 1]
2. [Optimization recommendation 2]
3. [Additional metrics to monitor]

Additional Notes:
-----------------
[Any other observations]
EOF

cat analysis-report.txt
```

---

## Understanding DCGM Metrics

### The 3 Signals That Truly Indicate GPU Saturation

> **Important**: GPU saturation is a **multi-dimensional condition**. Never rely on a single metric. You must look at both **macro-level utilization metrics** and **micro-level profiling counters** to understand if the GPU is fully fed, compute-bound, memory-bound, latency-bound, input-bound, network/PCIe-bound, or simply idle.

#### 1️⃣ SM Utilization + SM Active (DCGM Profiling) → "Are the cores busy?"

**Macro metric (always available):**
- `DCGM_FI_DEV_GPU_UTIL` - Measures overall GPU utilization (coarse-grained)

**Profiling metric (more accurate):**
- `DCGM_FI_PROF_SM_ACTIVE` - Measures % of cycles where Streaming Multiprocessors (SMs) were doing active work
  - This is the **real** compute saturation indicator
  - **If SM Active ≥ 85–90%, the GPU is compute-saturated**

#### 2️⃣ DRAM Active → "Is memory the bottleneck?"

- `DCGM_FI_PROF_DRAM_ACTIVE` - Measures memory subsystem saturation (global memory bandwidth)
  - **If DRAM Active is high (>80%) but SM Active is low → memory-bound workload**
  - GPU is not compute-saturated, even if overall GPU Utilization looks high

#### 3️⃣ Tensor/FP pipelines → "Are the tensor cores or ALUs saturated?"

For LLMs and training workloads:
- `DCGM_FI_PROF_PIPE_TENSOR_ACTIVE` - Tensor Core activity
- `DCGM_FI_PROF_PIPE_FP16_ACTIVE` - FP16 pipeline activity
- `DCGM_FI_PROF_PIPE_FP32_ACTIVE` - FP32 pipeline activity
- `DCGM_FI_PROF_PIPE_FP64_ACTIVE` - FP64 pipeline activity

**Tensor Core Active near 90% → true saturation for AI/LLM workloads.**

If this is low but SM Active is also low → input pipeline bottleneck (CPU, network, data loader, inference batching).

### The Golden Rule

> **Real GPU saturation = High SM Active AND high relevant pipeline activity AND no starvation signals.**

You need all three signals to confirm true saturation.

### Saturation Interpretation Matrix

| SM Active | DRAM Active | Tensor Active | Interpretation |
|-----------|-------------|---------------|----------------|
| 95% | 30% | 90% | ✅ Perfect compute-bound, saturated AI workload |
| 40% | 95% | <10% | ⚠️ Memory-bound (not compute-saturated) |
| 20% | 10% | 10% | ⚠️ Input-bound (CPU, disk, network bottleneck) |
| 90% | 90% | 90% | ✅ Fully saturated across all dimensions |

### Key Metrics Reference

| Metric | DCGM Field | Unit | Saturation Indicator | What It Tells You |
|--------|------------|------|---------------------|-------------------|
| **SM Active** | `DCGM_FI_PROF_SM_ACTIVE` | % | **≥85-90%** | Real compute saturation |
| **DRAM Active** | `DCGM_FI_PROF_DRAM_ACTIVE` | % | **>80%** | Memory bandwidth saturation |
| **Tensor Active** | `DCGM_FI_PROF_PIPE_TENSOR_ACTIVE` | % | **≥90%** | Tensor core saturation (AI/LLM) |
| GPU Utilization | `DCGM_FI_DEV_GPU_UTIL` | % | 70-95% | Coarse-grained utilization |
| Memory Used | `DCGM_FI_DEV_FB_USED` | Bytes | 60-80% of total | GPU memory usage |
| Power Usage | `DCGM_FI_DEV_POWER_USAGE` | W | 80-95% TDP | Power consumption |
| Temperature | `DCGM_FI_DEV_GPU_TEMP` | °C | 70-85°C | Thermal status |
| PCIe RX | `DCGM_FI_DEV_PCIE_RX_THROUGHPUT` | B/s | <30% capacity | Data input rate |
| PCIe TX | `DCGM_FI_DEV_PCIE_TX_THROUGHPUT` | B/s | <30% capacity | Data output rate |

### How Pros Measure GPU Saturation (NVIDIA SA Methodology)

#### Step 1: Check SM Active
- **If <80%**: You are NOT saturated unless you're memory-bound
- **If ≥85-90%**: GPU is compute-saturated

#### Step 2: Check DRAM Active
- **If high (>80%) and SM is low**: Memory-bound workload (common in vector embeddings)
- **If both high**: Balanced workload

#### Step 3: Check Tensor Active (for LLM/AI workloads)
- **Low tensor activity**: Likely bad batching or mixed workloads
- **High tensor activity**: Proper utilization of specialized hardware

#### Step 4: Check PCIe Utilization
- **High PCIe usage**: GPU might be stalled waiting for host transfers
- **Low PCIe, low SM**: Input pipeline bottleneck

#### Step 5: Validate End-to-End Throughput
- **If GPU metrics are high but QPS is low**: Bottleneck is outside the GPU (CPU, network, data loader)

### Best Single Indicator

If you must pick ONE metric:

👉 **`DCGM_FI_PROF_SM_ACTIVE` (SM Active)**

Because it directly measures how many cycles the SMs spent doing useful work.

**But remember**: Real saturation means combining:
- ✔ SM Active
- ✔ DRAM Active  
- ✔ Tensor Active (for AI workloads)
- ✔ No kernel gaps (requires Nsight Systems)

---

## Troubleshooting

### Issue: DCGM Exporter Not Collecting Metrics

**Symptoms:**
- No metrics in Prometheus
- DCGM Exporter pod not running

**Solution:**
```bash
# Check DCGM Exporter pod
k get pods -n gpu-operator -l app=nvidia-dcgm-exporter

# Check logs
k logs -n gpu-operator -l app=nvidia-dcgm-exporter

# Restart if needed
k rollout restart daemonset/nvidia-dcgm-exporter -n gpu-operator
```

### Issue: Prometheus Not Scraping DCGM Metrics

**Symptoms:**
- DCGM Exporter is running
- No DCGM metrics in Prometheus

**Solution:**
```bash
# Check ServiceMonitor
k get servicemonitor -n gpu-operator

# Check Prometheus targets
# Port-forward Prometheus and visit http://localhost:9090/targets
# Look for nvidia-dcgm-exporter target

# Recreate ServiceMonitor if needed
k apply -f dcgm-servicemonitor.yaml
```

### Issue: GPU Workload Not Using GPU

**Symptoms:**
- Workload pod running but GPU utilization is 0%

**Solution:**
```bash
# Check GPU resources
k describe pod <pod-name> | grep -A 5 "Limits"

# Verify GPU is available
k get nodes -o json | jq '.items[0].status.capacity | keys | .[] | select(. | contains("gpu"))'

# Check device plugin
k get pods -n gpu-operator -l app=nvidia-device-plugin-daemonset
```

### Issue: Grafana Dashboard Not Showing Data

**Symptoms:**
- Dashboard panels show "No data"

**Solution:**
```bash
# Verify Prometheus data source is configured correctly
# Check data source URL in Grafana

# Test Prometheus query directly
k port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# Visit http://localhost:9090 and test query: DCGM_FI_DEV_GPU_UTIL
```

---

## Workshop Cleanup

### Automated Cleanup

When you're done with the workshop:

```bash
# Remove GPU workloads
k delete pod gpu-workload-compute 2>/dev/null || true
k delete pod gpu-workload-memory 2>/dev/null || true

# Clean up the entire stack
bash cleanup.sh
```

### Manual Cleanup

If you prefer manual cleanup:

```bash
# Remove workloads
k delete pod --all --field-selector=status.phase!=Succeeded

# Remove Helm releases
helm uninstall kube-prometheus-stack -n monitoring
helm uninstall gpu-operator -n gpu-operator

# Remove namespaces
k delete namespace monitoring
k delete namespace gpu-operator

# Reset cluster
sudo kubeadm reset -f
rm -rf ~/.kube
```

---

## Resources & Next Steps

### Official Documentation

- [NVIDIA GPU Operator](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/)
- [DCGM Documentation](https://docs.nvidia.com/datacenter/dcgm/)
- [DCGM Exporter](https://github.com/NVIDIA/dcgm-exporter)
- [Prometheus](https://prometheus.io/docs/)
- [Grafana](https://grafana.com/docs/)

### Next Steps

1. **Experiment with different workloads** - Try memory-bound, I/O-bound scenarios
2. **Build custom Grafana dashboards** - Create dashboards for your specific use cases
3. **Set up alerts** - Configure Prometheus alerts for GPU saturation
4. **Optimize workloads** - Apply the recommendations from your analysis
5. **Scale to multiple GPUs** - Learn about multi-GPU profiling

### Practice Exercises

1. Deploy a memory-intensive workload and identify it as memory-bound
2. Create a workload that causes thermal throttling
3. Build a Grafana dashboard with custom queries
4. Set up Prometheus alerts for GPU temperature
5. Profile a real ML inference workload

---

## Workshop Checklist

Use this checklist to track your progress:

### Phase 1: Environment Setup
- [ ] Cloned repository
- [ ] Ran installation script
- [ ] Installation completed successfully
- [ ] Shell configured with `k` alias

### Phase 2: Verification
- [ ] Kubernetes cluster is Ready
- [ ] GPU Operator pods are Running
- [ ] DCGM Exporter is collecting metrics
- [ ] Prometheus is scraping DCGM metrics
- [ ] Grafana is accessible
- [ ] Prometheus data source configured in Grafana

### Phase 3: Deploy GPU Workload
- [ ] GPU workload deployed
- [ ] Workload pod is Running
- [ ] GPU is being utilized (nvidia-smi shows activity)

### Phase 4: Generate Load & Measure
- [ ] Baseline metrics collected
- [ ] Load generated and running
- [ ] Grafana dashboard created
- [ ] Saturation metrics observed
- [ ] Metrics documented

### Phase 5: Root Cause Analysis
- [ ] Metrics analyzed using decision tree
- [ ] Root cause identified
- [ ] Analysis report created
- [ ] Recommendations documented

### Cleanup
- [ ] Workloads removed
- [ ] Environment cleaned up (optional)

---

**Workshop Complete!** 🎉

You've successfully learned how to measure GPU saturation and identify root causes using DCGM metrics, Prometheus, and Grafana. Apply these techniques to optimize your GPU workloads!

---

**Last Updated:** November 2024  
**Workshop Version:** 1.0
