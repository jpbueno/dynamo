#!/bin/bash
# GPU Operator Stack Setup Script
# Installs: Kubernetes, GPU Operator, Prometheus, Grafana
# For Ubuntu 22.04

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
POD_NETWORK_CIDR="10.244.0.0/16"
KUBERNETES_VERSION="v1.31"
GPU_OPERATOR_NAMESPACE="gpu-operator"
MONITORING_NAMESPACE="monitoring"

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

diagnose_api_server() {
    # Comprehensive API server diagnostics
    log_info "Diagnosing API server issues..."
    
    echo ""
    log_info "=== API Server Diagnostics ==="
    
    # Check kubelet status
    log_info "1. Checking kubelet service..."
    if sudo systemctl is-active kubelet &>/dev/null; then
        log_info "   ✓ kubelet is running"
    else
        log_error "   ✗ kubelet is not running"
        log_info "   Attempting to start kubelet..."
        sudo systemctl start kubelet
        sleep 5
    fi
    
    # Check etcd first (API server depends on it)
    log_info "2. Checking etcd container..."
    ETCD_RUNNING=$(sudo crictl ps 2>/dev/null | grep etcd | awk '{print $1}' | head -1)
    ETCD_EXITED=$(sudo crictl ps -a 2>/dev/null | grep etcd | grep Exited | tail -1 | awk '{print $1}')
    
    if [ -n "$ETCD_RUNNING" ]; then
        log_info "   ✓ etcd is running: $ETCD_RUNNING"
    elif [ -n "$ETCD_EXITED" ]; then
        log_error "   ✗ etcd container exited, checking logs..."
        sudo crictl logs --tail 30 "$ETCD_EXITED" 2>/dev/null | tail -15 || true
        log_warn "   etcd must be running for API server to start"
    else
        log_warn "   ⚠ etcd container not found"
    fi
    
    # Check API server container
    log_info "3. Checking API server container..."
    API_CONTAINER=$(sudo crictl ps 2>/dev/null | grep kube-apiserver | awk '{print $1}' | head -1)
    if [ -n "$API_CONTAINER" ]; then
        log_info "   ✓ API server container found: $API_CONTAINER"
        log_info "   Checking container logs..."
        sudo crictl logs --tail 20 "$API_CONTAINER" 2>/dev/null | tail -5 || true
    else
        log_warn "   ⚠ API server container not running"
        log_info "   Checking exited containers..."
        EXITED=$(sudo crictl ps -a 2>/dev/null | grep kube-apiserver | grep Exited | tail -1)
        if [ -n "$EXITED" ]; then
            log_warn "   Found exited API server container, checking logs..."
            EXITED_ID=$(echo "$EXITED" | awk '{print $1}')
            sudo crictl logs --tail 30 "$EXITED_ID" 2>/dev/null | tail -15 || true
        fi
    fi
    
    # Check port 6443
    log_info "4. Checking port 6443..."
    if sudo ss -tlnp 2>/dev/null | grep -q ":6443"; then
        log_info "   ✓ Port 6443 is listening"
    else
        log_warn "   ⚠ Port 6443 is not listening"
    fi
    
    # Check system resources
    log_info "5. Checking system resources..."
    MEM_AVAIL=$(free -m | awk '/^Mem:/ {print $7}')
    DISK_AVAIL=$(df -h / | awk 'NR==2 {print $4}')
    log_info "   Available memory: ${MEM_AVAIL}MB"
    log_info "   Available disk: $DISK_AVAIL"
    
    # Check kubelet logs
    log_info "6. Recent kubelet errors..."
    sudo journalctl -u kubelet --no-pager -n 20 2>/dev/null | grep -iE "error|fail" | tail -5 || log_info "   No recent errors"
    
    echo ""
}

wait_for_etcd_stable() {
    # Wait for etcd to be stable before checking API server
    local max_attempts=30
    local attempt=0
    local consecutive_etcd_ok=0
    
    log_info "Waiting for etcd to be stable..."
    
    while [ $attempt -lt $max_attempts ]; do
        ETCD_RUNNING=$(sudo crictl ps 2>/dev/null | grep etcd | awk '{print $1}' | head -1)
        if [ -n "$ETCD_RUNNING" ]; then
            consecutive_etcd_ok=$((consecutive_etcd_ok + 1))
            if [ $consecutive_etcd_ok -ge 3 ]; then
                log_info "✓ etcd is stable"
                return 0
            fi
        else
            consecutive_etcd_ok=0
        fi
        attempt=$((attempt + 1))
        sleep 2
    done
    
    log_warn "etcd did not stabilize, but continuing..."
    return 1
}

wait_for_api_server() {
    # Wait for API server to be accessible and stable with comprehensive checks
    local max_attempts=${1:-90}  # Increased default timeout (60 -> 90)
    local attempt=0
    local consecutive_success=0
    local recovery_attempts=0
    local max_recovery_attempts=3
    
    log_info "Waiting for API server to be accessible and stable..."
    
    # First, ensure etcd is stable (API server depends on it)
    wait_for_etcd_stable
    
    while [ $attempt -lt $max_attempts ]; do
        # Test API server accessibility
        if kubectl cluster-info &>/dev/null 2>&1; then
            consecutive_success=$((consecutive_success + 1))
            
            # Require 5 consecutive successful checks for stability
            if [ $consecutive_success -ge 5 ]; then
                # Final comprehensive check
                if kubectl get nodes &>/dev/null 2>&1 && \
                   kubectl get namespaces &>/dev/null 2>&1 && \
                   kubectl cluster-info &>/dev/null 2>&1; then
                    log_info "✓ API server is fully operational and stable"
                    log_info "  - Cluster info accessible"
                    log_info "  - Nodes API working"
                    log_info "  - Namespaces API working"
                    return 0
                fi
            fi
            
            if [ $((attempt % 10)) -eq 0 ] && [ $attempt -gt 0 ]; then
                echo -n "."
            fi
        else
            consecutive_success=0
            
            # If we've had failures and haven't tried recovery yet
            if [ $attempt -gt 10 ] && [ $recovery_attempts -lt $max_recovery_attempts ]; then
                recovery_attempts=$((recovery_attempts + 1))
                log_warn "API server became unreachable, attempting recovery #$recovery_attempts..."
                diagnose_api_server
                
                # Ensure etcd is stable before restarting kubelet
                wait_for_etcd_stable
                
                log_info "Restarting kubelet..."
                sudo systemctl restart kubelet
                log_info "Waiting 30 seconds for components to stabilize after kubelet restart..."
                sleep 30
                
                # Wait for etcd to stabilize again after restart
                wait_for_etcd_stable
                
                # Check if recovery worked
                if kubectl cluster-info &>/dev/null 2>&1; then
                    log_info "✓ Recovery successful, API server is responding"
                    consecutive_success=1
                else
                    log_warn "Recovery attempt $recovery_attempts did not immediately restore API server"
                fi
            fi
        fi
        
        attempt=$((attempt + 1))
        sleep 2
    done
    
    # Final diagnosis before giving up
    log_error "API server did not become stable after $((max_attempts * 2)) seconds"
    log_error "Performing final diagnostics..."
    diagnose_api_server
    
    log_error ""
    log_error "API server troubleshooting steps:"
    log_error "1. Check kubelet: sudo systemctl status kubelet"
    log_error "2. Check API server logs: sudo crictl ps -a | grep kube-apiserver"
    log_error "3. Check etcd: sudo crictl ps | grep etcd"
    log_error "4. Restart kubelet: sudo systemctl restart kubelet"
    log_error "5. Check system resources: free -h && df -h"
    
    return 1
}

wait_for_pods_ready() {
    # Wait for pods to be ready in a namespace
    local namespace=$1
    local selector=$2
    local timeout=${3:-600}  # Default 10 minutes
    local check_interval=${4:-10}  # Default 10 seconds
    local max_attempts=$((timeout / check_interval))
    local attempt=0
    local api_failures=0
    local max_api_failures=5
    
    while [ $attempt -lt $max_attempts ]; do
        # Check API server accessibility first
        if ! kubectl cluster-info &>/dev/null 2>&1; then
            api_failures=$((api_failures + 1))
            if [ $api_failures -ge $max_api_failures ]; then
                log_warn "API server became unreachable during pod wait. Attempting recovery..."
                diagnose_api_server
                log_info "Restarting kubelet to recover API server..."
                sudo systemctl restart kubelet
                sleep 10
                
                # Wait for API server to recover
                if wait_for_api_server 30; then
                    log_info "✓ API server recovered, continuing pod wait..."
                    api_failures=0
                else
                    log_error "API server recovery failed. Cannot continue waiting for pods."
                    return 1
                fi
            else
                log_warn "API server temporarily unreachable (failure $api_failures/$max_api_failures), retrying..."
                sleep 5
                attempt=$((attempt + 1))
                continue
            fi
        else
            api_failures=0  # Reset failure counter on success
        fi
        
        READY=$(kubectl get pods -n "$namespace" $selector --no-headers 2>/dev/null | grep -v "Completed" | awk '{print $2}' | grep -E "^[0-9]+/[0-9]+$" | wc -l)
        TOTAL=$(kubectl get pods -n "$namespace" $selector --no-headers 2>/dev/null | grep -v "Completed" | wc -l)
        
        if [ "$TOTAL" -gt 0 ] && [ "$READY" -eq "$TOTAL" ]; then
            return 0
        fi
        
        attempt=$((attempt + 1))
        if [ $((attempt % 6)) -eq 0 ]; then
            echo -n "."
        fi
        sleep $check_interval
    done
    
    return 1
}

log_section() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

# Progress tracking
PROGRESS_STEP=0
TOTAL_STEPS=10

show_progress() {
    PROGRESS_STEP=$((PROGRESS_STEP + 1))
    echo ""
    echo -e "${BLUE}[$PROGRESS_STEP/$TOTAL_STEPS]${NC} $1"
    echo "----------------------------------------"
}

check_root() {
    if [ "$EUID" -eq 0 ]; then 
        log_error "Please run as regular user (not root). Sudo will be used when needed."
        exit 1
    fi
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    if [ ! -f /etc/os-release ]; then
        log_error "Cannot detect OS version"
        exit 1
    fi
    
    source /etc/os-release
    if [ "$ID" != "ubuntu" ] || [ "$VERSION_ID" != "22.04" ]; then
        log_warn "This script is tested on Ubuntu 22.04. Proceeding anyway..."
    fi
    
    if ! ping -c 1 8.8.8.8 &>/dev/null; then
        log_error "No internet connectivity. Please check your network."
        exit 1
    fi
    
    if command -v kubeadm &>/dev/null; then
        log_warn "Kubernetes tools already installed. Skipping installation..."
        return 1
    fi
    
    return 0
}

install_prerequisites() {
    log_info "Installing prerequisites..."
    
    sudo apt-get update
    sudo apt-get install -y apt-transport-https ca-certificates curl gpg conntrack
    
    sudo modprobe br_netfilter
    echo "br_netfilter" | sudo tee -a /etc/modules-load.d/k8s.conf
    
    cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
    sudo sysctl --system
    
    sudo swapoff -a
    sudo sed -i '/swap/s/^/#/' /etc/fstab
    
    log_info "Prerequisites installed"
}

install_kubernetes() {
    log_info "Installing Kubernetes tools..."
    
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
    
    sudo apt-get update
    sudo apt-get install -y kubelet kubeadm kubectl
    sudo apt-mark hold kubelet kubeadm kubectl
    
    log_info "Kubernetes tools installed"
}

install_containerd() {
    log_info "Configuring containerd..."
    
    if ! command -v containerd &>/dev/null; then
        log_info "Installing containerd..."
        sudo apt-get install -y containerd
    fi
    
    sudo mkdir -p /etc/containerd
    containerd config default | sudo tee /etc/containerd/config.toml
    sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
    
    sudo systemctl restart containerd
    sudo systemctl enable containerd
    
    log_info "Containerd configured"
}

configure_kubectl_shell() {
    log_info "Configuring kubectl shell integration..."
    
    if ! grep -q "alias k=kubectl" ~/.bashrc 2>/dev/null; then
        cat <<'EOF' >> ~/.bashrc

# kubectl alias and completion
if command -v kubectl &> /dev/null; then
    alias k=kubectl
    source <(kubectl completion bash 2>/dev/null) || true
    complete -F __start_kubectl k 2>/dev/null || true
fi
EOF
        log_info "Added kubectl alias and completion to ~/.bashrc"
    else
        log_info "kubectl alias and completion already configured"
    fi
    
    # Load alias in current shell session immediately
    if command -v kubectl &> /dev/null; then
        alias k=kubectl 2>/dev/null || true
        if [ -n "$BASH_VERSION" ]; then
            # Load completion in current shell
            source <(kubectl completion bash 2>/dev/null) || true
            complete -F __start_kubectl k 2>/dev/null || true
        fi
        log_info "✓ Alias 'k' loaded in current shell - you can use 'k' command now"
    else
        log_warn "kubectl not found, alias not loaded"
    fi
    
    log_info "Shell integration configured. Run 'source ~/.bashrc' or start a new shell to use 'k' alias"
}

initialize_cluster() {
    log_info "Initializing Kubernetes cluster..."
    
    if [ -f /etc/kubernetes/admin.conf ] || [ -f /etc/kubernetes/super-admin.conf ]; then
        log_info "Kubernetes admin config found, setting up kubeconfig..."
        mkdir -p $HOME/.kube
        if [ -f /etc/kubernetes/super-admin.conf ]; then
            sudo cp -i /etc/kubernetes/super-admin.conf $HOME/.kube/config 2>/dev/null || true
        else
            sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config 2>/dev/null || true
        fi
        sudo chown $(id -u):$(id -g) $HOME/.kube/config 2>/dev/null || true
        
        if kubectl cluster-info &>/dev/null 2>&1; then
            log_warn "Kubernetes cluster already initialized and accessible. Skipping initialization..."
            configure_kubectl_shell
            return 0
        fi
    fi
    
    # Check for partial initialization
    if [ -f /etc/kubernetes/manifests/kube-apiserver.yaml ]; then
        log_warn "Kubernetes manifests exist. Checking if cluster is accessible..."
        mkdir -p $HOME/.kube
        if [ -f /etc/kubernetes/super-admin.conf ]; then
            sudo cp -i /etc/kubernetes/super-admin.conf $HOME/.kube/config 2>/dev/null || true
        elif [ -f /etc/kubernetes/admin.conf ]; then
            sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config 2>/dev/null || true
        fi
        sudo chown $(id -u):$(id -g) $HOME/.kube/config 2>/dev/null || true
        
        # Wait for API server to be ready (up to 2 minutes)
        log_info "Waiting for API server to be ready..."
        for i in {1..24}; do
            if kubectl cluster-info &>/dev/null 2>&1; then
                log_info "Cluster is accessible. Continuing with configuration..."
                configure_kubectl_shell
                return 0
            fi
            sleep 5
        done
        
        log_error "Cluster files exist but cluster is not responding after 2 minutes."
        log_error "This may indicate a problem with the API server."
        log_info "Attempting to reset and reinitialize..."
        sudo kubeadm reset -f 2>/dev/null || true
        sudo rm -rf /etc/kubernetes /var/lib/etcd /var/lib/kubelet 2>/dev/null || true
        sudo systemctl restart kubelet
        sleep 5
    fi
    
    log_info "Initializing Kubernetes cluster with kubeadm..."
    sudo kubeadm init --pod-network-cidr=$POD_NETWORK_CIDR || {
        log_error "kubeadm init failed"
        return 1
    }
    
    mkdir -p $HOME/.kube
    if [ -f /etc/kubernetes/super-admin.conf ]; then
        sudo cp -i /etc/kubernetes/super-admin.conf $HOME/.kube/config
    else
        sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    fi
    sudo chown $(id -u):$(id -g) $HOME/.kube/config
    
    configure_kubectl_shell
    
    # Wait for API server to be fully ready (comprehensive check)
    log_info "Verifying API server is fully operational..."
    if ! wait_for_api_server 60; then
        log_error "API server did not become fully operational after initialization"
        log_error "The cluster may be in an unstable state."
        log_error ""
        log_error "Troubleshooting steps:"
        log_error "1. Check kubelet: sudo systemctl status kubelet"
        log_error "2. Check API server container: sudo crictl ps -a | grep kube-apiserver"
        log_error "3. Check kubelet logs: sudo journalctl -u kubelet --no-pager -n 50"
        log_error "4. Check system resources: free -h && df -h"
        log_error "5. Try manual recovery: sudo systemctl restart kubelet && sleep 15"
        return 1
    fi
    
    # Final verification before proceeding
    log_info "Performing final API server verification..."
    if ! kubectl get nodes &>/dev/null 2>&1; then
        log_error "Final verification failed: cannot query nodes"
        return 1
    fi
    
    if ! kubectl get namespaces &>/dev/null 2>&1; then
        log_error "Final verification failed: cannot query namespaces"
        return 1
    fi
    
    log_info "✓ Kubernetes cluster initialized and API server is 100% operational"
}

configure_cluster() {
    log_info "Configuring cluster..."
    
    kubectl taint nodes --all node-role.kubernetes.io/control-plane- 2>/dev/null || true
    kubectl taint nodes --all node-role.kubernetes.io/master- 2>/dev/null || true
    
    log_info "Configuring firewall rules..."
    NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
    
    sudo iptables -I INPUT 1 -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
    sudo iptables -I INPUT 1 -s 10.244.0.0/16 -d $NODE_IP -p tcp --dport 6443 -j ACCEPT 2>/dev/null || true
    sudo iptables -I INPUT 1 -s 10.244.0.0/16 -d 10.96.0.1 -p tcp --dport 443 -j ACCEPT 2>/dev/null || true
    
    if command -v netfilter-persistent &>/dev/null; then
        sudo netfilter-persistent save 2>/dev/null || true
    fi
    
    log_info "Cluster configured"
}

install_cni() {
    log_info "Installing Flannel CNI..."
    
    if kubectl get namespace kube-flannel &>/dev/null 2>&1; then
        FLANNEL_PODS=$(kubectl get pods -n kube-flannel --no-headers 2>/dev/null | wc -l)
        if [ "$FLANNEL_PODS" -gt 0 ]; then
            log_warn "Flannel CNI already installed. Verifying it's working..."
            kubectl wait --for=condition=ready pod -l app=flannel -n kube-flannel --timeout=60s 2>/dev/null || true
            
            if kubectl get nodes -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; then
                log_info "Flannel CNI is working (node is Ready)"
                return 0
            else
                log_warn "Flannel installed but node not Ready. Reinstalling..."
            fi
        fi
    fi
    
    # Ensure API server is accessible before applying Flannel
    log_info "Verifying API server is operational before installing Flannel..."
    if ! wait_for_api_server 30; then
        log_error "API server is not operational. Cannot install Flannel."
        return 1
    fi
    
    log_info "Applying Flannel CNI manifest..."
    local flannel_apply_attempts=0
    local max_flannel_apply_attempts=3
    
    while [ $flannel_apply_attempts -lt $max_flannel_apply_attempts ]; do
        if kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml 2>/dev/null; then
            log_info "✓ Flannel manifest applied successfully"
            break
        else
            flannel_apply_attempts=$((flannel_apply_attempts + 1))
            if [ $flannel_apply_attempts -ge $max_flannel_apply_attempts ]; then
                log_error "Failed to apply Flannel manifest after $max_flannel_apply_attempts attempts"
                return 1
            fi
            
            log_warn "Flannel apply failed (attempt $flannel_apply_attempts/$max_flannel_apply_attempts), checking API server..."
            if ! wait_for_api_server 20; then
                log_error "API server recovery failed"
                return 1
            fi
            sleep 5
        fi
    done
    
    log_info "Waiting for Flannel pods to be ready..."
    sleep 5
    
    # Ensure API server is accessible before checking pods (comprehensive check)
    log_info "Verifying API server is operational before checking Flannel pods..."
    if ! wait_for_api_server 30; then
        log_error "API server is not operational. Cannot verify Flannel installation."
        log_error "Flannel may have been installed but verification failed."
        return 1
    fi
    
    local max_wait=60
    local waited=0
    while [ $waited -lt $max_wait ]; do
        if kubectl get pods -n kube-flannel --no-headers 2>/dev/null | wc -l | grep -q "[1-9]"; then
            break
        fi
        sleep 2
        waited=$((waited + 2))
    done
    
    # Wait for Flannel pods with API server recovery
    local flannel_wait_attempts=0
    local max_flannel_wait=60
    while [ $flannel_wait_attempts -lt $max_flannel_wait ]; do
        # Check API server before kubectl wait
        if ! kubectl cluster-info &>/dev/null 2>&1; then
            log_warn "API server became unreachable during Flannel wait, attempting recovery..."
            diagnose_api_server
            sudo systemctl restart kubelet
            sleep 10
            if ! wait_for_api_server 30; then
                log_error "API server recovery failed"
                return 1
            fi
            continue
        fi
        
        # Try kubectl wait with short timeout
        if kubectl wait --for=condition=ready pod -l app=flannel -n kube-flannel --timeout=10s 2>/dev/null; then
            log_info "✓ Flannel pods are ready"
            break
        fi
        
        flannel_wait_attempts=$((flannel_wait_attempts + 1))
        sleep 5
    done
    
    if [ $flannel_wait_attempts -ge $max_flannel_wait ]; then
        log_warn "Flannel pods may not be ready yet, checking status..."
        if kubectl cluster-info &>/dev/null 2>&1; then
            kubectl get pods -n kube-flannel 2>/dev/null || true
        else
            log_warn "Cannot check Flannel pods (API server is unreachable)"
        fi
    fi
    
    log_info "Waiting for node to become Ready (CNI initialization)..."
    local max_attempts=30
    local attempt=0
    while [ $attempt -lt $max_attempts ]; do
        if kubectl get nodes -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; then
            log_info "Node is Ready! CNI is working."
            kubectl get nodes
            return 0
        fi
        attempt=$((attempt + 1))
        echo -n "."
        sleep 2
    done
    echo ""
    
    log_warn "Node did not become Ready within expected time, but continuing..."
    kubectl get nodes
}

install_helm() {
    log_info "Installing Helm..."
    
    if command -v helm &>/dev/null; then
        log_warn "Helm already installed. Skipping..."
        return 0
    fi
    
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    log_info "Helm installed"
}

install_gpu_operator() {
    log_info "Installing NVIDIA GPU Operator..."
    
    helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
    log_info "Updating Helm repository..."
    helm repo update nvidia
    
    kubectl create namespace $GPU_OPERATOR_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
    
    if helm list -n $GPU_OPERATOR_NAMESPACE 2>/dev/null | grep -q gpu-operator; then
        log_warn "GPU Operator already installed. Skipping..."
        return 0
    fi
    
    log_info "Installing GPU Operator (this may take 5-10 minutes)..."
    # Install without --wait to avoid timeout, we'll check manually
    helm install gpu-operator \
        nvidia/gpu-operator \
        --namespace $GPU_OPERATOR_NAMESPACE \
        --set operator.defaultRuntime=containerd \
        --timeout 10m || {
        log_error "GPU Operator Helm installation failed"
        return 1
    }
    
    log_info "Waiting for GPU Operator pods to be ready (this may take several minutes)..."
    if wait_for_pods_ready "$GPU_OPERATOR_NAMESPACE" "-l app=gpu-operator" 600 10; then
        log_info "✓ GPU Operator is ready"
    else
        log_warn "GPU Operator not fully ready after 10 minutes, but continuing..."
        kubectl get pods -n $GPU_OPERATOR_NAMESPACE | head -10
    fi
    
    log_info "Checking GPU Operator status..."
    kubectl get pods -n $GPU_OPERATOR_NAMESPACE
    
    log_info "✓ GPU Operator installed successfully"
}

install_prometheus_grafana() {
    log_info "Installing Prometheus and Grafana..."
    
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    log_info "Updating Helm repository..."
    helm repo update prometheus-community
    
    kubectl create namespace $MONITORING_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
    
    if helm list -n $MONITORING_NAMESPACE 2>/dev/null | grep -q kube-prometheus-stack; then
        log_warn "Prometheus/Grafana already installed. Skipping..."
        return 0
    fi
    
    log_info "Installing Prometheus/Grafana stack (this may take 5-10 minutes)..."
    # Install without --wait to avoid timeout, we'll check manually
    helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
        --namespace $MONITORING_NAMESPACE \
        --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
        --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false \
        --set prometheus.prometheusSpec.ruleSelectorNilUsesHelmValues=false \
        --timeout 10m || {
        log_error "Prometheus/Grafana Helm installation failed"
        return 1
    }
    
    log_info "Waiting for Prometheus/Grafana pods to be ready (this may take several minutes)..."
    sleep 10
    
    # Wait for Prometheus
    log_info "  Waiting for Prometheus..."
    if wait_for_pods_ready "$MONITORING_NAMESPACE" "-l app.kubernetes.io/name=prometheus" 600 10; then
        log_info "  ✓ Prometheus is ready"
    else
        log_warn "  Prometheus not fully ready after 10 minutes"
    fi
    
    # Wait for Grafana
    log_info "  Waiting for Grafana..."
    if wait_for_pods_ready "$MONITORING_NAMESPACE" "-l app.kubernetes.io/name=grafana" 600 10; then
        log_info "  ✓ Grafana is ready"
    else
        log_warn "  Grafana not fully ready after 10 minutes"
    fi
    
    kubectl get pods -n $MONITORING_NAMESPACE | head -10
    
    log_info "✓ Prometheus and Grafana installed successfully"
}

configure_dcgm_service_monitor() {
    log_info "Configuring DCGM Exporter ServiceMonitor..."
    
    log_info "Waiting for DCGM Exporter pod to be ready..."
    # DCGM Exporter may take time to appear
    local dcgm_attempts=0
    while [ $dcgm_attempts -lt 30 ]; do
        if kubectl get pods -n $GPU_OPERATOR_NAMESPACE -l app=nvidia-dcgm-exporter --no-headers 2>/dev/null | grep -q .; then
            break
        fi
        dcgm_attempts=$((dcgm_attempts + 1))
        sleep 2
    done
    
    if kubectl get pods -n $GPU_OPERATOR_NAMESPACE -l app=nvidia-dcgm-exporter --no-headers 2>/dev/null | grep -q .; then
        if wait_for_pods_ready "$GPU_OPERATOR_NAMESPACE" "-l app=nvidia-dcgm-exporter" 300 5; then
            log_info "✓ DCGM Exporter is ready"
        else
            log_warn "DCGM Exporter pod not ready yet, but continuing..."
            kubectl get pods -n $GPU_OPERATOR_NAMESPACE -l app=nvidia-dcgm-exporter
        fi
    else
        log_warn "DCGM Exporter pod not found yet, but continuing..."
    fi
    
    log_info "Creating ServiceMonitor for DCGM metrics..."
    cat <<EOF | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: nvidia-dcgm-exporter
  namespace: $GPU_OPERATOR_NAMESPACE
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
    
    log_info "Verifying ServiceMonitor was created..."
    kubectl get servicemonitor -n $GPU_OPERATOR_NAMESPACE
    
    log_info "✓ DCGM Exporter ServiceMonitor configured"
}

verify_installation() {
    log_info "Verifying installation..."
    
    echo ""
    echo "=== Kubernetes Cluster ==="
    kubectl get nodes
    kubectl get pods --all-namespaces | grep -E "Running|Completed" | wc -l | xargs echo "Running pods:"
    
    echo ""
    echo "=== GPU Operator ==="
    kubectl get pods -n $GPU_OPERATOR_NAMESPACE
    
    echo ""
    echo "=== Prometheus/Grafana ==="
    kubectl get pods -n $MONITORING_NAMESPACE
    
    echo ""
    echo "=== GPU Resources ==="
    kubectl get nodes -o json | jq -r '.items[0].status.capacity | to_entries[] | select(.key | contains("gpu"))' 2>/dev/null || echo "No GPU resources detected yet"
}

print_access_info() {
    echo ""
    echo "=========================================="
    echo "Installation Complete!"
    echo "=========================================="
    echo ""
    echo "Access Information:"
    echo ""
    echo "=== For Brev / Remote Server Access (from local machine) ==="
    echo ""
    echo "For Brev Environments:"
    echo "1. On your LOCAL machine, create SSH tunnels:"
    echo "   Terminal 1: brev ssh <workspace-name> -L 3000:localhost:3000"
    echo "   Terminal 2: brev ssh <workspace-name> -L 9090:localhost:9090"
    echo ""
    echo "2. Then in your BREV workspace, run port-forwards:"
    echo "   Terminal 1: kubectl port-forward -n $MONITORING_NAMESPACE svc/kube-prometheus-stack-grafana 3000:80"
    echo "   Terminal 2: kubectl port-forward -n $MONITORING_NAMESPACE svc/kube-prometheus-stack-prometheus 9090:9090"
    echo ""
    echo "For Generic Remote Servers:"
    echo "1. On your LOCAL machine, create SSH tunnels:"
    echo "   Terminal 1: ssh -L 3000:localhost:3000 user@$(hostname -I | awk '{print $1}')"
    echo "   Terminal 2: ssh -L 9090:localhost:9090 user@$(hostname -I | awk '{print $1}')"
    echo ""
    echo "2. Then on the REMOTE server, run port-forwards:"
    echo "   Terminal 1: kubectl port-forward -n $MONITORING_NAMESPACE svc/kube-prometheus-stack-grafana 3000:80"
    echo "   Terminal 2: kubectl port-forward -n $MONITORING_NAMESPACE svc/kube-prometheus-stack-prometheus 9090:9090"
    echo ""
    echo "3. Access from your LOCAL machine:"
    echo "   Grafana: http://localhost:3000"
    echo "   Prometheus: http://localhost:9090"
    echo ""
    echo "=== For Local Access (same machine) ==="
    echo ""
    echo "Prometheus UI:"
    echo "  kubectl port-forward -n $MONITORING_NAMESPACE svc/kube-prometheus-stack-prometheus 9090:9090"
    echo "  Then visit: http://localhost:9090"
    echo ""
    echo "Grafana UI:"
    echo "  kubectl port-forward -n $MONITORING_NAMESPACE svc/kube-prometheus-stack-grafana 3000:80"
    echo "  Then visit: http://localhost:3000"
    echo "  Username: admin"
    echo "  Password: kubectl get secret -n $MONITORING_NAMESPACE kube-prometheus-stack-grafana -o jsonpath=\"{.data.admin-password}\" | base64 -d"
    echo ""
    echo "DCGM Exporter Metrics:"
    echo "  kubectl port-forward -n $GPU_OPERATOR_NAMESPACE svc/nvidia-dcgm-exporter 9400:9400"
    echo "  Then visit: http://localhost:9400/metrics"
    echo ""
}

# Main execution
main() {
    log_section "GPU Operator Stack Setup"
    log_info "This will install: Kubernetes, GPU Operator, Prometheus, Grafana"
    log_info "Estimated time: 15-20 minutes"
    echo ""
    
    check_root
    
    show_progress "Installing Prerequisites"
    if check_prerequisites; then
        install_prerequisites
        install_kubernetes
        install_containerd
    else
        log_info "Prerequisites check skipped (already installed)"
    fi
    
    show_progress "Initializing Kubernetes Cluster"
    initialize_cluster
    configure_cluster
    
    show_progress "Waiting for CoreDNS"
    log_info "Verifying API server is still operational before proceeding..."
    if ! wait_for_api_server 30; then
        log_error "API server became unstable. Cannot proceed with CoreDNS setup."
        log_error "Please fix the API server issue before continuing."
        return 1
    fi
    
    log_info "Waiting for CoreDNS to be ready..."
    # CoreDNS may not exist immediately after cluster init
    local coredns_attempts=0
    while [ $coredns_attempts -lt 30 ]; do
        # Check API server before each iteration
        if ! kubectl cluster-info &>/dev/null 2>&1; then
            log_warn "API server became unreachable, attempting recovery..."
            diagnose_api_server
            sudo systemctl restart kubelet
            sleep 10
            if ! wait_for_api_server 30; then
                log_error "API server recovery failed during CoreDNS wait"
                return 1
            fi
        fi
        
        if kubectl get pods -n kube-system -l k8s-app=kube-dns --no-headers 2>/dev/null | grep -q .; then
            break
        fi
        coredns_attempts=$((coredns_attempts + 1))
        sleep 2
    done
    
    if kubectl get pods -n kube-system -l k8s-app=kube-dns --no-headers 2>/dev/null | grep -q .; then
        # Wait for CoreDNS pods with API server recovery
        local coredns_wait_attempts=0
        local max_coredns_wait=60
        while [ $coredns_wait_attempts -lt $max_coredns_wait ]; do
            # Check API server before kubectl wait
            if ! kubectl cluster-info &>/dev/null 2>&1; then
                log_warn "API server became unreachable during CoreDNS wait, attempting recovery..."
                diagnose_api_server
                sudo systemctl restart kubelet
                sleep 10
                if ! wait_for_api_server 30; then
                    log_error "API server recovery failed"
                    return 1
                fi
                continue
            fi
            
            # Try kubectl wait with short timeout
            if kubectl wait --for=condition=ready pod -l k8s-app=kube-dns -n kube-system --timeout=10s 2>/dev/null; then
                log_info "✓ CoreDNS pods are ready"
                break
            fi
            
            coredns_wait_attempts=$((coredns_wait_attempts + 1))
            sleep 5
        done
        
        if [ $coredns_wait_attempts -ge $max_coredns_wait ]; then
            log_warn "CoreDNS pods did not become ready within expected time"
            if kubectl cluster-info &>/dev/null 2>&1; then
                kubectl get pods -n kube-system -l k8s-app=kube-dns 2>/dev/null || true
            fi
            log_info "Continuing with installation..."
        fi
    else
        log_warn "CoreDNS pods not found yet, but continuing..."
    fi
    log_info "CoreDNS check complete"
    
    show_progress "Installing Flannel CNI"
    install_cni
    
    # Wait for node to become Ready
    log_info "Waiting for node to become Ready..."
    local node_ready_attempts=0
    while [ $node_ready_attempts -lt 60 ]; do
        if kubectl get nodes -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; then
            log_info "✓ Node is Ready - CNI is working"
            return 0
        fi
        node_ready_attempts=$((node_ready_attempts + 1))
        if [ $((node_ready_attempts % 12)) -eq 0 ]; then
            echo -n "."
        fi
        sleep 5
    done
    echo ""
    log_warn "Node did not become Ready after 5 minutes"
    log_info "This may affect subsequent installations, but continuing..."
    
    show_progress "Installing Helm"
    log_info "Verifying API server before Helm installation..."
    if ! wait_for_api_server 20; then
        log_error "API server is not stable. Cannot install Helm charts."
        return 1
    fi
    install_helm
    
    show_progress "Installing GPU Operator"
    log_info "Verifying API server before GPU Operator installation..."
    if ! wait_for_api_server 20; then
        log_error "API server is not stable. Cannot install GPU Operator."
        return 1
    fi
    log_info "This may take 5-10 minutes..."
    install_gpu_operator
    
    show_progress "Installing Prometheus and Grafana"
    log_info "Verifying API server before Prometheus/Grafana installation..."
    if ! wait_for_api_server 20; then
        log_error "API server is not stable. Cannot install Prometheus/Grafana."
        return 1
    fi
    log_info "This may take 5-10 minutes..."
    install_prometheus_grafana
    
    show_progress "Configuring DCGM ServiceMonitor"
    log_info "Verifying API server before ServiceMonitor configuration..."
    if ! wait_for_api_server 15; then
        log_error "API server is not stable. Cannot configure ServiceMonitor."
        return 1
    fi
    configure_dcgm_service_monitor
    
    show_progress "Verifying Installation"
    log_info "Final API server verification before installation verification..."
    if ! wait_for_api_server 20; then
        log_error "API server is not stable. Installation verification may be incomplete."
        log_warn "Continuing with verification, but results may be inaccurate..."
    fi
    log_info "Waiting for components to stabilize..."
    sleep 30
    
    verify_installation
    
    # Final comprehensive API server health check before declaring success
    show_progress "Final API Server Health Check"
    log_info "Performing final comprehensive API server health check..."
    if ! wait_for_api_server 30; then
        log_error "API server health check failed. Installation may be incomplete."
        log_error "Please verify the cluster is operational before using it."
        return 1
    fi
    
    # Test all critical Kubernetes APIs
    log_info "Testing all critical Kubernetes APIs..."
    if ! kubectl get nodes &>/dev/null 2>&1; then
        log_error "✗ Nodes API test failed"
        return 1
    fi
    log_info "  ✓ Nodes API working"
    
    if ! kubectl get namespaces &>/dev/null 2>&1; then
        log_error "✗ Namespaces API test failed"
        return 1
    fi
    log_info "  ✓ Namespaces API working"
    
    if ! kubectl get pods --all-namespaces &>/dev/null 2>&1; then
        log_error "✗ Pods API test failed"
        return 1
    fi
    log_info "  ✓ Pods API working"
    
    if ! kubectl get services --all-namespaces &>/dev/null 2>&1; then
        log_error "✗ Services API test failed"
        return 1
    fi
    log_info "  ✓ Services API working"
    
    log_info "✓ All critical APIs are operational"
    
    show_progress "Installation Complete!"
    print_access_info
    
    echo ""
    log_info "=========================================="
    log_info "Setup completed successfully!"
    log_info "=========================================="
    echo ""
    echo "Next Steps:"
    echo "  1. Reload your shell configuration:"
    echo "     source ~/.bashrc"
    echo ""
    echo "  2. Or start a new terminal session to use 'k' alias"
    echo ""
    echo "  3. Verify everything works:"
    echo "     kubectl get nodes"
    echo "     kubectl get pods -n gpu-operator"
    echo "     kubectl get pods -n monitoring"
    echo ""
    echo "  4. Follow DYNAMO_WORKSHOP_GUIDE.md for the workshop exercises"
    echo ""
    echo "Your environment is now 100% ready for the GPU saturation workshop!"
    echo ""
}

main "$@"

