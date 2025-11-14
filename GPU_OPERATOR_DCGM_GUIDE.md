# NVIDIA GPU Operator & DCGM Metrics - SME Learning Guide

> A comprehensive guide to becoming a Subject Matter Expert on NVIDIA GPU Operator with focus on DCGM metrics interpretation for profiling

## 📖 Table of Contents

1. [Overview](#overview)
2. [NVIDIA GPU Operator Fundamentals](#nvidia-gpu-operator-fundamentals)
3. [DCGM (Data Center GPU Manager) Deep Dive](#dcgm-data-center-gpu-manager-deep-dive)
4. [DCGM Metrics for Profiling](#dcgm-metrics-for-profiling)
5. [Interpreting Metrics](#interpreting-metrics)
6. [Practical Examples](#practical-examples)
7. [Troubleshooting](#troubleshooting)
8. [Resources & Next Steps](#resources--next-steps)

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

```bash
# Add NVIDIA Helm repository
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update

# Install GPU Operator
helm install --wait gpu-operator \
  nvidia/gpu-operator \
  --namespace gpu-operator \
  --create-namespace \
  --set operator.defaultRuntime=containerd

# Verify installation
kubectl get pods -n gpu-operator
kubectl get nodes -l nvidia.com/gpu.present=true
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

