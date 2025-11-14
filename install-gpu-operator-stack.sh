#!/bin/bash
# Complete GPU Operator Stack Installation Script
# Installs: Kubernetes, GPU Operator, Prometheus, Grafana
# For Ubuntu 22.04

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

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

check_root() {
    if [ "$EUID" -eq 0 ]; then 
        log_error "Please run as regular user (not root). Sudo will be used when needed."
        exit 1
    fi
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check OS
    if [ ! -f /etc/os-release ]; then
        log_error "Cannot detect OS version"
        exit 1
    fi
    
    source /etc/os-release
    if [ "$ID" != "ubuntu" ] || [ "$VERSION_ID" != "22.04" ]; then
        log_warn "This script is tested on Ubuntu 22.04. Proceeding anyway..."
    fi
    
    # Check internet connectivity
    if ! ping -c 1 8.8.8.8 &>/dev/null; then
        log_error "No internet connectivity. Please check your network."
        exit 1
    fi
    
    # Check if already installed
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
    
    # Load required kernel modules
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
    
    log_info "Prerequisites installed"
}

install_kubernetes() {
    log_info "Installing Kubernetes tools..."
    
    # Add Kubernetes repository
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
    
    sudo apt-get update
    sudo apt-get install -y kubelet kubeadm kubectl
    sudo apt-mark hold kubelet kubeadm kubectl
    
    log_info "Kubernetes tools installed"
}

install_containerd() {
    log_info "Configuring containerd..."
    
    # Check if containerd is installed
    if ! command -v containerd &>/dev/null; then
        log_info "Installing containerd..."
        sudo apt-get install -y containerd
    fi
    
    # Configure containerd
    sudo mkdir -p /etc/containerd
    containerd config default | sudo tee /etc/containerd/config.toml
    
    # Enable systemd cgroup driver
    sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
    
    sudo systemctl restart containerd
    sudo systemctl enable containerd
    
    log_info "Containerd configured"
}

initialize_cluster() {
    log_info "Initializing Kubernetes cluster..."
    
    # Check if cluster already exists
    if kubectl cluster-info &>/dev/null 2>&1; then
        log_warn "Kubernetes cluster already initialized. Skipping..."
        return 0
    fi
    
    sudo kubeadm init --pod-network-cidr=$POD_NETWORK_CIDR
    
    # Configure kubectl
    mkdir -p $HOME/.kube
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config
    
    log_info "Kubernetes cluster initialized"
}

configure_cluster() {
    log_info "Configuring cluster..."
    
    # Remove control-plane taint to allow pods to schedule
    kubectl taint nodes --all node-role.kubernetes.io/control-plane- 2>/dev/null || true
    kubectl taint nodes --all node-role.kubernetes.io/master- 2>/dev/null || true
    
    # Configure firewall to allow pod-to-host communication
    log_info "Configuring firewall rules..."
    
    # Get node IP
    NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
    
    # Add firewall rules for Kubernetes API
    sudo iptables -I INPUT 1 -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
    sudo iptables -I INPUT 1 -s 10.244.0.0/16 -d $NODE_IP -p tcp --dport 6443 -j ACCEPT 2>/dev/null || true
    sudo iptables -I INPUT 1 -s 10.244.0.0/16 -d 10.96.0.1 -p tcp --dport 443 -j ACCEPT 2>/dev/null || true
    
    # Make firewall rules persistent (if using iptables-persistent)
    if command -v netfilter-persistent &>/dev/null; then
        sudo netfilter-persistent save 2>/dev/null || true
    fi
    
    log_info "Cluster configured"
}

install_cni() {
    log_info "Installing Flannel CNI..."
    
    # Check if Flannel is already installed
    if kubectl get pods -n kube-flannel &>/dev/null 2>&1; then
        log_warn "Flannel CNI already installed. Skipping..."
        return 0
    fi
    
    kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
    
    # Wait for Flannel to be ready
    log_info "Waiting for Flannel to be ready..."
    kubectl wait --for=condition=ready pod -l app=flannel -n kube-flannel --timeout=300s || true
    
    log_info "Flannel CNI installed"
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
    
    # Add NVIDIA Helm repository
    helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
    helm repo update nvidia
    
    # Create namespace
    kubectl create namespace $GPU_OPERATOR_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
    
    # Install GPU Operator
    if helm list -n $GPU_OPERATOR_NAMESPACE | grep -q gpu-operator; then
        log_warn "GPU Operator already installed. Skipping..."
        return 0
    fi
    
    helm install --wait gpu-operator \
        nvidia/gpu-operator \
        --namespace $GPU_OPERATOR_NAMESPACE \
        --set operator.defaultRuntime=containerd \
        --timeout 10m
    
    # Wait for GPU Operator to be ready
    log_info "Waiting for GPU Operator to be ready..."
    kubectl wait --for=condition=ready pod -l app=gpu-operator -n $GPU_OPERATOR_NAMESPACE --timeout=600s || true
    
    log_info "GPU Operator installed"
}

install_prometheus_grafana() {
    log_info "Installing Prometheus and Grafana..."
    
    # Add Prometheus Community Helm repository
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo update prometheus-community
    
    # Create monitoring namespace
    kubectl create namespace $MONITORING_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
    
    # Install kube-prometheus-stack
    if helm list -n $MONITORING_NAMESPACE | grep -q kube-prometheus-stack; then
        log_warn "Prometheus/Grafana already installed. Skipping..."
        return 0
    fi
    
    helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
        --namespace $MONITORING_NAMESPACE \
        --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
        --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false \
        --set prometheus.prometheusSpec.ruleSelectorNilUsesHelmValues=false \
        --wait --timeout 10m
    
    log_info "Prometheus and Grafana installed"
}

configure_dcgm_service_monitor() {
    log_info "Configuring DCGM Exporter ServiceMonitor..."
    
    # Wait for DCGM Exporter to be ready
    kubectl wait --for=condition=ready pod -l app=nvidia-dcgm-exporter -n $GPU_OPERATOR_NAMESPACE --timeout=300s || true
    
    # Create ServiceMonitor
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
    
    log_info "DCGM Exporter ServiceMonitor configured"
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
    
    echo ""
    echo "=== DCGM Metrics ==="
    if kubectl get pods -n $GPU_OPERATOR_NAMESPACE -l app=nvidia-dcgm-exporter &>/dev/null; then
        log_info "DCGM Exporter is running"
        kubectl get svc -n $GPU_OPERATOR_NAMESPACE -l app=nvidia-dcgm-exporter
    else
        log_warn "DCGM Exporter not ready yet"
    fi
}

print_access_info() {
    echo ""
    echo "=========================================="
    echo "Installation Complete!"
    echo "=========================================="
    echo ""
    echo "Access Information:"
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
    echo "Next Steps:"
    echo "  1. Configure Prometheus data source in Grafana"
    echo "  2. Create DCGM metrics dashboard"
    echo "  3. Follow the guide in ~/dynamo/GPU_OPERATOR_DCGM_GUIDE.md"
    echo ""
}

# Main execution
main() {
    log_info "Starting GPU Operator Stack Installation"
    log_info "This will install: Kubernetes, GPU Operator, Prometheus, Grafana"
    echo ""
    
    check_root
    
    if check_prerequisites; then
        install_prerequisites
        install_kubernetes
        install_containerd
    else
        log_info "Prerequisites check skipped (already installed)"
    fi
    
    initialize_cluster
    configure_cluster
    install_cni
    
    # Wait for CoreDNS to be ready
    log_info "Waiting for CoreDNS to be ready..."
    kubectl wait --for=condition=ready pod -l k8s-app=kube-dns -n kube-system --timeout=300s || true
    
    install_helm
    install_gpu_operator
    install_prometheus_grafana
    configure_dcgm_service_monitor
    
    # Wait a bit for everything to stabilize
    log_info "Waiting for components to stabilize..."
    sleep 30
    
    verify_installation
    print_access_info
    
    log_info "Installation script completed!"
}

# Run main function
main "$@"

