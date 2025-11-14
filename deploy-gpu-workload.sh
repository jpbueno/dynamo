#!/bin/bash
# GPU Workload Deployment Script
# Deploys different types of GPU workloads for saturation testing

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

WORKLOAD_TYPE="${1:-compute}"
WORKLOAD_NAME="gpu-workload-${WORKLOAD_TYPE}"

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

show_usage() {
    cat <<EOF
GPU Workload Deployment Script

Usage: $0 [workload_type]

Workload Types:
  compute    - Compute-intensive workload (matrix multiplications)
  memory     - Memory-intensive workload (large memory allocations)
  io         - I/O-bound workload (frequent data transfers)
  custom     - Custom workload (interactive)

Examples:
  $0 compute    # Deploy compute-intensive workload
  $0 memory     # Deploy memory-intensive workload
  $0 io         # Deploy I/O-bound workload
  $0 custom     # Interactive custom workload

EOF
}

deploy_compute_workload() {
    log_info "Deploying compute-intensive GPU workload..."
    
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: ${WORKLOAD_NAME}
  labels:
    workload-type: compute
spec:
  restartPolicy: Never
  containers:
  - name: cuda-workload
    image: nvidia/cuda:12.0.0-base-ubuntu22.04
    command: ["/bin/bash", "-c"]
    args:
    - |
      apt-get update -qq && apt-get install -y -qq python3 python3-pip > /dev/null 2>&1
      pip3 install -q numpy
      nvidia-smi -l 1 &
      python3 <<PYTHON
import time
import numpy as np
print("Starting compute-intensive workload...")
print("This workload performs large matrix multiplications")
while True:
    # Large matrices for compute-intensive operations
    a = np.random.rand(10000, 10000).astype(np.float32)
    b = np.random.rand(10000, 10000).astype(np.float32)
    # Multiple iterations to keep GPU busy
    for _ in range(100):
        c = np.dot(a, b)
    time.sleep(0.1)
PYTHON
    resources:
      limits:
        nvidia.com/gpu: 1
EOF
    
    log_info "Compute workload deployed: ${WORKLOAD_NAME}"
}

deploy_memory_workload() {
    log_info "Deploying memory-intensive GPU workload..."
    
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: ${WORKLOAD_NAME}
  labels:
    workload-type: memory
spec:
  restartPolicy: Never
  containers:
  - name: cuda-workload
    image: nvidia/cuda:12.0.0-base-ubuntu22.04
    command: ["/bin/bash", "-c"]
    args:
    - |
      apt-get update -qq && apt-get install -y -qq python3 python3-pip > /dev/null 2>&1
      pip3 install -q numpy
      nvidia-smi -l 1 &
      python3 <<PYTHON
import time
import numpy as np
print("Starting memory-intensive workload...")
print("This workload allocates large amounts of GPU memory")
# Allocate large arrays to stress memory bandwidth
arrays = []
try:
    while True:
        # Allocate large arrays (memory-intensive)
        for _ in range(10):
            arr = np.random.rand(5000, 5000).astype(np.float32)
            arrays.append(arr)
        # Perform operations that stress memory bandwidth
        for arr in arrays[-10:]:
            _ = arr * 2 + 1
        time.sleep(0.5)
        # Keep some arrays to maintain memory pressure
        if len(arrays) > 50:
            arrays = arrays[-30:]
except MemoryError:
    print("Memory limit reached, continuing with available memory...")
    while True:
        for arr in arrays:
            _ = arr * 2 + 1
        time.sleep(0.5)
PYTHON
    resources:
      limits:
        nvidia.com/gpu: 1
EOF
    
    log_info "Memory workload deployed: ${WORKLOAD_NAME}"
}

deploy_io_workload() {
    log_info "Deploying I/O-bound GPU workload..."
    
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: ${WORKLOAD_NAME}
  labels:
    workload-type: io
spec:
  restartPolicy: Never
  containers:
  - name: cuda-workload
    image: nvidia/cuda:12.0.0-base-ubuntu22.04
    command: ["/bin/bash", "-c"]
    args:
    - |
      apt-get update -qq && apt-get install -y -qq python3 python3-pip > /dev/null 2>&1
      pip3 install -q numpy
      nvidia-smi -l 1 &
      python3 <<PYTHON
import time
import numpy as np
print("Starting I/O-bound workload...")
print("This workload performs frequent small data transfers")
while True:
    # Small batches to stress I/O
    for _ in range(100):
        # Small arrays transferred frequently
        a = np.random.rand(1000, 1000).astype(np.float32)
        b = np.random.rand(1000, 1000).astype(np.float32)
        c = np.dot(a, b)
        # Small delay to simulate I/O wait
        time.sleep(0.01)
PYTHON
    resources:
      limits:
        nvidia.com/gpu: 1
EOF
    
    log_info "I/O workload deployed: ${WORKLOAD_NAME}"
}

deploy_custom_workload() {
    log_info "Custom workload deployment"
    echo ""
    echo "Please provide your custom workload YAML:"
    echo "Press Ctrl+D when done, or provide a file path"
    echo ""
    
    read -p "Enter YAML file path (or paste YAML): " input
    
    if [ -f "$input" ]; then
        kubectl apply -f "$input"
    else
        echo "$input" | kubectl apply -f -
    fi
}

wait_for_pod() {
    log_info "Waiting for pod to be ready..."
    kubectl wait --for=condition=Ready pod/${WORKLOAD_NAME} --timeout=120s || {
        log_error "Pod did not become ready"
        kubectl describe pod/${WORKLOAD_NAME}
        exit 1
    }
    
    log_info "Pod is ready!"
    kubectl get pod/${WORKLOAD_NAME}
}

show_status() {
    echo ""
    log_info "Workload Status:"
    kubectl get pod/${WORKLOAD_NAME} -o wide
    
    echo ""
    log_info "GPU Usage (from pod):"
    kubectl exec ${WORKLOAD_NAME} -- nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu --format=csv,noheader 2>/dev/null || log_warn "nvidia-smi not available yet"
    
    echo ""
    log_info "To view logs:"
    echo "  kubectl logs -f ${WORKLOAD_NAME}"
    echo ""
    log_info "To delete workload:"
    echo "  kubectl delete pod ${WORKLOAD_NAME}"
    echo ""
}

# Main execution
case "$WORKLOAD_TYPE" in
    compute)
        deploy_compute_workload
        wait_for_pod
        show_status
        ;;
    memory)
        deploy_memory_workload
        wait_for_pod
        show_status
        ;;
    io)
        deploy_io_workload
        wait_for_pod
        show_status
        ;;
    custom)
        deploy_custom_workload
        ;;
    help|--help|-h)
        show_usage
        ;;
    *)
        log_error "Unknown workload type: $WORKLOAD_TYPE"
        echo ""
        show_usage
        exit 1
        ;;
esac

