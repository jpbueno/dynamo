#!/bin/bash
# GPU Operator Stack Cleanup Script
# Removes: Kubernetes cluster, GPU Operator, Prometheus, Grafana
# For Ubuntu 22.04

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
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

log_section() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

wait_for_api_server() {
    # Helper function to wait for API server to be accessible
    local max_attempts=30
    local attempt=0
    while [ $attempt -lt $max_attempts ]; do
        if kubectl cluster-info &>/dev/null 2>&1; then
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 2
    done
    return 1
}

main() {
    log_section "Cleaning Up GPU Operator Stack"
    
    log_warn "This will remove:"
    echo "  - Kubernetes cluster"
    echo "  - GPU Operator"
    echo "  - Prometheus/Grafana stack"
    echo "  - Helm releases"
    echo "  - System configurations (some)"
    echo ""
    log_warn "This action cannot be undone. Press Ctrl+C to cancel..."
    sleep 5
    
    # Remove Helm releases (only if API server is accessible)
    if command -v helm &>/dev/null; then
        log_info "Removing Helm releases..."
        
        if wait_for_api_server; then
            if helm list -n $MONITORING_NAMESPACE 2>/dev/null | grep -q kube-prometheus-stack; then
                log_info "  Uninstalling Prometheus/Grafana stack..."
                helm uninstall kube-prometheus-stack -n $MONITORING_NAMESPACE 2>/dev/null || true
            fi
            
            if helm list -n $GPU_OPERATOR_NAMESPACE 2>/dev/null | grep -q gpu-operator; then
                log_info "  Uninstalling GPU Operator..."
                helm uninstall gpu-operator -n $GPU_OPERATOR_NAMESPACE 2>/dev/null || true
            fi
            
            # Remove namespaces
            log_info "  Removing namespaces..."
            kubectl delete namespace $MONITORING_NAMESPACE --ignore-not-found=true --timeout=60s 2>/dev/null || true
            kubectl delete namespace $GPU_OPERATOR_NAMESPACE --ignore-not-found=true --timeout=60s 2>/dev/null || true
        else
            log_warn "API server not accessible, skipping Helm cleanup (will be cleaned by kubeadm reset)"
        fi
        
        # Clean Helm repos
        helm repo remove nvidia 2>/dev/null || true
        helm repo remove prometheus-community 2>/dev/null || true
    fi
    
    # Remove CNI (only if API server is accessible)
    if wait_for_api_server; then
        if kubectl get pods -n kube-flannel &>/dev/null 2>&1; then
            log_info "Removing Flannel CNI..."
            kubectl delete -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml --ignore-not-found=true --timeout=60s 2>/dev/null || true
            kubectl delete namespace kube-flannel --ignore-not-found=true --timeout=60s 2>/dev/null || true
        fi
    else
        log_warn "API server not accessible, skipping CNI cleanup (will be cleaned by kubeadm reset)"
    fi
    
    # Reset Kubernetes cluster
    log_info "Resetting Kubernetes cluster..."
    
    # Try kubeadm reset if cluster exists
    if wait_for_api_server; then
        log_info "  Running kubeadm reset..."
        sudo kubeadm reset -f 2>/dev/null || {
            log_warn "kubeadm reset had issues, continuing with force cleanup..."
        }
    else
        log_info "  API server not accessible, proceeding with force cleanup..."
    fi
    
    # Force cleanup even if kubeadm reset fails
    log_info "Force cleaning Kubernetes directories..."
    
    # Stop kubelet to release ports and prevent new pods
    log_info "  Stopping kubelet..."
    sudo systemctl stop kubelet 2>/dev/null || true
    sleep 2
    
    # Remove kubectl config
    log_info "  Removing kubectl config..."
    rm -rf ~/.kube 2>/dev/null || true
    
    # Remove Kubernetes config files (force)
    log_info "  Removing Kubernetes directories..."
    sudo rm -rf /etc/kubernetes 2>/dev/null || true
    sudo rm -rf /var/lib/etcd 2>/dev/null || true
    sudo rm -rf /var/lib/kubelet 2>/dev/null || true
    
    # Remove CNI config
    log_info "  Removing CNI configuration..."
    sudo rm -rf /etc/cni/net.d 2>/dev/null || true
    sudo rm -rf /opt/cni/bin 2>/dev/null || true
    
    # Clean up any remaining containerd/kubelet containers
    log_info "  Cleaning containerd containers..."
    sudo crictl rm -a -f 2>/dev/null || true
    
    # Clean up containerd images (optional, but helps with space)
    log_info "  Pruning containerd..."
    sudo crictl rmi --prune 2>/dev/null || true
    
    # Restart kubelet
    log_info "  Restarting kubelet..."
    sudo systemctl start kubelet 2>/dev/null || true
    sleep 2
    
    # Clean Helm cache
    log_info "Cleaning Helm cache..."
    rm -rf ~/.cache/helm 2>/dev/null || true
    
    # Remove system configurations
    log_info "Cleaning system configurations..."
    
    # Remove Kubernetes-specific firewall rules
    sudo iptables -D INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
    sudo iptables -D INPUT -s 10.244.0.0/16 -d 10.96.0.1 -p tcp --dport 443 -j ACCEPT 2>/dev/null || true
    
    # Clean containerd (reset to defaults)
    log_info "Resetting containerd configuration..."
    if [ -f /etc/containerd/config.toml ]; then
        sudo cp /etc/containerd/config.toml /etc/containerd/config.toml.backup.$(date +%Y%m%d) 2>/dev/null || true
        containerd config default | sudo tee /etc/containerd/config.toml > /dev/null 2>&1 || true
        sudo systemctl restart containerd 2>/dev/null || true
    fi
    
    # Remove ServiceMonitor (only if API server is accessible)
    if wait_for_api_server; then
        log_info "Removing ServiceMonitor..."
        kubectl delete servicemonitor -n $GPU_OPERATOR_NAMESPACE nvidia-dcgm-exporter --ignore-not-found=true --timeout=30s 2>/dev/null || true
    fi
    
    # Clean up any remaining pods/resources (only if API server is accessible)
    if wait_for_api_server; then
        log_info "Cleaning up remaining resources..."
        kubectl delete --all pods --all-namespaces --grace-period=0 --force --timeout=30s 2>/dev/null || true
        
        # Remove any remaining namespaces (except system ones)
        for ns in $(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
            if [[ "$ns" != "default" && "$ns" != "kube-system" && "$ns" != "kube-public" && "$ns" != "kube-node-lease" ]]; then
                kubectl delete namespace "$ns" --ignore-not-found=true --timeout=30s 2>/dev/null || true
            fi
        done
    fi
    
    log_info "Cleanup complete!"
    echo ""
    # Remove Kubernetes tools
    log_info "Removing Kubernetes tools..."
    if command -v kubeadm &>/dev/null || command -v kubectl &>/dev/null || command -v kubelet &>/dev/null; then
        log_info "  Purging Kubernetes packages..."
        sudo apt-get purge -y kubelet kubeadm kubectl kubernetes-cni 2>/dev/null || {
            log_warn "Some Kubernetes packages may not be installed via apt"
        }
        sudo apt-get autoremove -y 2>/dev/null || true
        log_info "  ✓ Kubernetes tools removed"
    else
        log_info "  Kubernetes tools not found, skipping removal"
    fi
    
    # Remove Helm (optional - comment out if you want to keep Helm)
    log_info "Removing Helm..."
    if command -v helm &>/dev/null; then
        log_info "  Removing Helm..."
        sudo rm -f /usr/local/bin/helm 2>/dev/null || true
        rm -rf ~/.helm 2>/dev/null || true
        log_info "  ✓ Helm removed"
    else
        log_info "  Helm not found, skipping removal"
    fi
    
    log_info ""
    log_info "=========================================="
    log_info "Cleanup completed successfully!"
    log_info "=========================================="
    log_info ""
    log_info "All components have been removed:"
    log_info "  ✓ Kubernetes cluster"
    log_info "  ✓ GPU Operator"
    log_info "  ✓ Prometheus/Grafana stack"
    log_info "  ✓ Helm releases"
    log_info "  ✓ Kubernetes tools (kubeadm, kubectl, kubelet)"
    log_info "  ✓ Helm"
    log_info "  ✓ System configurations"
    log_info ""
    log_info "To reinstall, run: bash setup.sh"
}

main "$@"

