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
NC='\033[0m' # No Color

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

cmd_cleanup() {
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
    
    # Remove Helm releases
    if command -v helm &>/dev/null; then
        log_info "Removing Helm releases..."
        
        if helm list -n $MONITORING_NAMESPACE 2>/dev/null | grep -q kube-prometheus-stack; then
            helm uninstall kube-prometheus-stack -n $MONITORING_NAMESPACE 2>/dev/null || true
        fi
        
        if helm list -n $GPU_OPERATOR_NAMESPACE 2>/dev/null | grep -q gpu-operator; then
            helm uninstall gpu-operator -n $GPU_OPERATOR_NAMESPACE 2>/dev/null || true
        fi
        
        # Remove namespaces
        kubectl delete namespace $MONITORING_NAMESPACE --ignore-not-found=true 2>/dev/null || true
        kubectl delete namespace $GPU_OPERATOR_NAMESPACE --ignore-not-found=true 2>/dev/null || true
        
        # Clean Helm repos
        helm repo remove nvidia 2>/dev/null || true
        helm repo remove prometheus-community 2>/dev/null || true
    fi
    
    # Remove CNI
    if kubectl get pods -n kube-flannel &>/dev/null 2>&1; then
        log_info "Removing Flannel CNI..."
        kubectl delete -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml --ignore-not-found=true 2>/dev/null || true
        kubectl delete namespace kube-flannel --ignore-not-found=true 2>/dev/null || true
    fi
    
    # Reset Kubernetes cluster
    if kubectl cluster-info &>/dev/null 2>&1; then
        log_info "Resetting Kubernetes cluster..."
        sudo kubeadm reset -f 2>/dev/null || true
        
        # Remove kubectl config
        rm -rf ~/.kube 2>/dev/null || true
        
        # Remove Kubernetes config files
        sudo rm -rf /etc/kubernetes 2>/dev/null || true
        sudo rm -rf /var/lib/etcd 2>/dev/null || true
        sudo rm -rf /var/lib/kubelet 2>/dev/null || true
        
        # Remove CNI config
        sudo rm -rf /etc/cni/net.d 2>/dev/null || true
        sudo rm -rf /opt/cni/bin 2>/dev/null || true
    fi
    
    # Clean Helm cache
    log_info "Cleaning Helm cache..."
    rm -rf ~/.cache/helm 2>/dev/null || true
    
    # Remove system configurations (be careful - only remove what we added)
    log_info "Cleaning system configurations..."
    
    # Remove Kubernetes-specific firewall rules (keep others)
    if [ -f /tmp/iptables-backup-$(date +%Y%m%d).txt ]; then
        log_info "Backing up current iptables..."
        sudo iptables-save > /tmp/iptables-backup-$(date +%Y%m%d).txt
    fi
    
    # Remove our specific rules (be careful - these might not exist)
    sudo iptables -D INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
    sudo iptables -D INPUT -s 10.244.0.0/16 -d 10.96.0.1 -p tcp --dport 443 -j ACCEPT 2>/dev/null || true
    
    # Clean containerd (reset to defaults)
    log_info "Resetting containerd configuration..."
    if [ -f /etc/containerd/config.toml ]; then
        sudo cp /etc/containerd/config.toml /etc/containerd/config.toml.backup.$(date +%Y%m%d) 2>/dev/null || true
        containerd config default | sudo tee /etc/containerd/config.toml > /dev/null 2>&1 || true
        sudo systemctl restart containerd 2>/dev/null || true
    fi
    
    # Remove ServiceMonitor
    kubectl delete servicemonitor -n $GPU_OPERATOR_NAMESPACE nvidia-dcgm-exporter --ignore-not-found=true 2>/dev/null || true
    
    # Clean up any remaining pods/resources (if cluster still exists)
    if kubectl cluster-info &>/dev/null 2>&1; then
        log_info "Cleaning up remaining resources..."
        kubectl delete --all pods --all-namespaces --grace-period=0 --force 2>/dev/null || true
        
        # Remove any remaining namespaces (except system ones)
        for ns in $(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
            if [[ "$ns" != "default" && "$ns" != "kube-system" && "$ns" != "kube-public" && "$ns" != "kube-node-lease" ]]; then
                kubectl delete namespace "$ns" --ignore-not-found=true 2>/dev/null || true
            fi
        done
    fi
    
    log_info "Cleanup complete!"
    echo ""
    echo "Remaining components:"
    echo "  - Kubernetes tools (kubectl, kubeadm, kubelet) - kept for reinstall"
    echo "  - Helm - kept for reinstall"
    echo "  - System configurations - partially kept for reinstall"
    echo ""
    echo "To fully remove Kubernetes tools, run manually:"
    echo "  sudo apt-get purge -y kubelet kubeadm kubectl kubernetes-cni"
    echo ""
    echo "To reinstall, run: bash install-gpu-operator-stack.sh"
}

# Run cleanup
cmd_cleanup

