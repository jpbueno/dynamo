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
bash install-gpu-operator-stack.sh
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

# Query baseline GPU utilization
curl -s 'http://localhost:9090/api/v1/query?query=DCGM_FI_DEV_GPU_UTIL' | jq '.data.result[0].value[1]'

# Query baseline memory usage
curl -s 'http://localhost:9090/api/v1/query?query=DCGM_FI_DEV_FB_USED' | jq '.data.result[0].value[1]'

# Document baseline values
echo "Baseline Metrics:" > metrics-baseline.txt
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

#### Panel 4: SM Occupancy
- **Query:** `DCGM_FI_DEV_SM_OCCUPANCY{instance=~".*"}`
- **Visualization:** Time series
- **Y-axis:** 0-100%
- **Title:** "SM Occupancy (%)"

#### Panel 5: Power Usage
- **Query:** `DCGM_FI_DEV_POWER_USAGE{instance=~".*"}`
- **Visualization:** Time series
- **Title:** "Power Usage (Watts)"

#### Panel 6: Temperature
- **Query:** `DCGM_FI_DEV_GPU_TEMP{instance=~".*"}`
- **Visualization:** Time series
- **Title:** "GPU Temperature (°C)"

#### Panel 7: PCIe RX Throughput
- **Query:** `DCGM_FI_DEV_PCIE_RX_THROUGHPUT{instance=~".*"}`
- **Visualization:** Time series
- **Title:** "PCIe RX Throughput (Bytes/s)"

#### Panel 8: PCIe TX Throughput
- **Query:** `DCGM_FI_DEV_PCIE_TX_THROUGHPUT{instance=~".*"}`
- **Visualization:** Time series
- **Title:** "PCIe TX Throughput (Bytes/s)"

### Step 4.4: Observe Saturation Metrics

Watch the dashboard for 5-10 minutes and document:

```bash
# Create saturation metrics file
cat > metrics-saturation.txt <<EOF
Saturation Metrics (after 5 minutes of load):
============================================
GPU Utilization: ______%
Memory Utilization: ______%
SM Occupancy: ______%
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

#### Scenario A: Compute-Bound Workload
**Indicators:**
- GPU Utilization: **>90%**
- Memory Utilization: **<50%**
- SM Occupancy: **>80%**
- Power Usage: **High (near TDP)**

**Root Cause:** Workload is limited by compute capacity, not memory bandwidth.

**Solutions:**
- Optimize compute kernels
- Use Tensor Cores (if available)
- Increase batch size
- Use mixed precision (FP16/BF16)

#### Scenario B: Memory-Bound Workload
**Indicators:**
- GPU Utilization: **>90%**
- Memory Utilization: **>80%**
- Memory Used: **Near total GPU memory**
- SM Occupancy: **Lower (<50%) due to memory stalls**

**Root Cause:** Workload is limited by memory bandwidth or capacity.

**Solutions:**
- Reduce memory footprint
- Optimize memory access patterns
- Use mixed precision to reduce memory usage
- Increase memory bandwidth utilization

#### Scenario C: I/O-Bound Workload
**Indicators:**
- GPU Utilization: **<50%**
- PCIe RX/TX: **High (>30% of PCIe bandwidth)**
- Memory Utilization: **Variable**

**Root Cause:** Data transfer bottleneck between CPU and GPU.

**Solutions:**
- Optimize data pipeline
- Use data prefetching
- Increase batch size
- Use pinned memory
- Overlap computation and data transfer

#### Scenario D: Thermal Throttling
**Indicators:**
- Temperature: **>85°C**
- Power Usage: **May drop due to throttling**
- GPU Utilization: **May fluctuate**

**Root Cause:** GPU is overheating and throttling performance.

**Solutions:**
- Improve cooling
- Reduce power limit
- Optimize workload to reduce heat generation
- Check thermal paste and fans

#### Scenario E: Kernel Efficiency Issues
**Indicators:**
- GPU Utilization: **>90%**
- SM Occupancy: **<50%**
- Memory Utilization: **Variable**

**Root Cause:** Kernels are not efficiently utilizing GPU resources.

**Solutions:**
- Optimize kernel launch configuration
- Increase occupancy (reduce register usage)
- Improve thread block size
- Reduce kernel overhead

### Step 5.2: Prometheus Queries for Analysis

Use these queries in Prometheus to analyze your workload:

```promql
# Average GPU Utilization (5 minutes)
avg_over_time(DCGM_FI_DEV_GPU_UTIL[5m])

# Memory utilization percentage
(avg_over_time(DCGM_FI_DEV_FB_USED[5m]) / avg_over_time(DCGM_FI_DEV_FB_TOTAL[5m])) * 100

# Power efficiency (utilization per watt)
avg_over_time(DCGM_FI_DEV_GPU_UTIL[5m]) / avg_over_time(DCGM_FI_DEV_POWER_USAGE[5m])

# Check for thermal throttling
DCGM_FI_DEV_GPU_TEMP > 85

# PCIe bandwidth utilization (assuming PCIe 3.0 x16 = 16 GB/s)
(avg_over_time(DCGM_FI_DEV_PCIE_RX_THROUGHPUT[5m]) + avg_over_time(DCGM_FI_DEV_PCIE_TX_THROUGHPUT[5m])) / 16e9 * 100

# SM Occupancy
avg_over_time(DCGM_FI_DEV_SM_OCCUPANCY[5m])
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
Scenario Identified: [A/B/C/D/E]
Evidence:
- [List key metrics that support your conclusion]

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

### Key Metrics for Saturation Analysis

| Metric | Field ID | Unit | Good Range | What It Tells You |
|--------|----------|------|------------|-------------------|
| GPU Utilization | 155 | % | 70-95% | How busy the GPU is |
| Memory Utilization | 150 | % | 40-70% | Memory controller activity |
| Memory Used | 100 | Bytes | 60-80% of total | Actual GPU memory usage |
| SM Occupancy | 155 | % | 50-80% | Streaming Multiprocessor utilization |
| Power Usage | 203 | W | 80-95% TDP | Power consumption |
| Temperature | 252 | °C | 70-85°C | Thermal status |
| PCIe RX | - | B/s | <30% capacity | Data input rate |
| PCIe TX | - | B/s | <30% capacity | Data output rate |

### Metric Interpretation Guide

**GPU Utilization:**
- **0-50%**: Underutilized, may indicate I/O bottleneck
- **50-90%**: Good utilization
- **90-100%**: High utilization, check for bottlenecks

**Memory Utilization:**
- **<50%**: Compute-bound workload
- **50-80%**: Balanced workload
- **>80%**: Memory-bound workload

**SM Occupancy:**
- **<50%**: Kernel efficiency issues
- **50-80%**: Good occupancy
- **>80%**: Excellent occupancy

**Temperature:**
- **<70°C**: Cool, no throttling risk
- **70-85°C**: Normal operating range
- **>85°C**: Risk of thermal throttling

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
