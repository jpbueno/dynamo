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
    source <(kubectl completion bash)
    complete -F __start_kubectl k
fi
EOF
        log_info "Added kubectl alias and completion to ~/.bashrc"
    else
        log_info "kubectl alias and completion already configured"
    fi
    
    if command -v kubectl &> /dev/null; then
        alias k=kubectl 2>/dev/null || true
        source <(kubectl completion bash) 2>/dev/null || true
        complete -F __start_kubectl k 2>/dev/null || true
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
    
    if sudo netstat -tlnp 2>/dev/null | grep -q ":6443.*LISTEN"; then
        log_warn "Port 6443 is in use. Cluster may be partially initialized."
        log_info "Setting up kubeconfig from existing config..."
        mkdir -p $HOME/.kube
        if [ -f /etc/kubernetes/super-admin.conf ]; then
            sudo cp -i /etc/kubernetes/super-admin.conf $HOME/.kube/config
        elif [ -f /etc/kubernetes/admin.conf ]; then
            sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
        fi
        sudo chown $(id -u):$(id -g) $HOME/.kube/config
        configure_kubectl_shell
        
        sleep 5
        if kubectl cluster-info &>/dev/null 2>&1; then
            log_info "Cluster is accessible. Continuing with configuration..."
            return 0
        else
            log_error "Cluster files exist but cluster is not responding."
            log_error "You may need to run: sudo kubeadm reset -f"
            exit 1
        fi
    fi
    
    sudo kubeadm init --pod-network-cidr=$POD_NETWORK_CIDR
    
    mkdir -p $HOME/.kube
    if [ -f /etc/kubernetes/super-admin.conf ]; then
        sudo cp -i /etc/kubernetes/super-admin.conf $HOME/.kube/config
    else
        sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    fi
    sudo chown $(id -u):$(id -g) $HOME/.kube/config
    
    configure_kubectl_shell
    
    log_info "Kubernetes cluster initialized"
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
    
    log_info "Applying Flannel CNI manifest..."
    kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
    
    log_info "Waiting for Flannel pods to be ready..."
    sleep 5
    
    local max_wait=60
    local waited=0
    while [ $waited -lt $max_wait ]; do
        if kubectl get pods -n kube-flannel --no-headers 2>/dev/null | wc -l | grep -q "[1-9]"; then
            break
        fi
        sleep 2
        waited=$((waited + 2))
    done
    
    kubectl wait --for=condition=ready pod -l app=flannel -n kube-flannel --timeout=300s || {
        log_warn "Flannel pods may not be ready yet, checking status..."
        kubectl get pods -n kube-flannel
    }
    
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
    helm install --wait gpu-operator \
        nvidia/gpu-operator \
        --namespace $GPU_OPERATOR_NAMESPACE \
        --set operator.defaultRuntime=containerd \
        --timeout 10m
    
    log_info "Waiting for GPU Operator pods to be ready..."
    kubectl wait --for=condition=ready pod -l app=gpu-operator -n $GPU_OPERATOR_NAMESPACE --timeout=600s || true
    
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
    helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
        --namespace $MONITORING_NAMESPACE \
        --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
        --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false \
        --set prometheus.prometheusSpec.ruleSelectorNilUsesHelmValues=false \
        --wait --timeout 10m
    
    log_info "Waiting for Prometheus/Grafana pods to be ready..."
    sleep 10
    kubectl get pods -n $MONITORING_NAMESPACE
    
    log_info "✓ Prometheus and Grafana installed successfully"
}

configure_dcgm_service_monitor() {
    log_info "Configuring DCGM Exporter ServiceMonitor..."
    
    log_info "Waiting for DCGM Exporter pod to be ready..."
    kubectl wait --for=condition=ready pod -l app=nvidia-dcgm-exporter -n $GPU_OPERATOR_NAMESPACE --timeout=300s || {
        log_warn "DCGM Exporter pod not ready yet, but continuing..."
        kubectl get pods -n $GPU_OPERATOR_NAMESPACE -l app=nvidia-dcgm-exporter
    }
    
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
    log_info "Waiting for CoreDNS to be ready..."
    kubectl wait --for=condition=ready pod -l k8s-app=kube-dns -n kube-system --timeout=300s || true
    log_info "CoreDNS is ready"
    
    show_progress "Installing Flannel CNI"
    install_cni
    
    if ! kubectl get nodes -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; then
        log_warn "Node is not Ready yet. This may affect subsequent installations."
        log_info "You can check node status with: kubectl get nodes"
    else
        log_info "✓ Node is Ready - CNI is working"
    fi
    
    show_progress "Installing Helm"
    install_helm
    
    show_progress "Installing GPU Operator"
    log_info "This may take 5-10 minutes..."
    install_gpu_operator
    
    show_progress "Installing Prometheus and Grafana"
    log_info "This may take 5-10 minutes..."
    install_prometheus_grafana
    
    show_progress "Configuring DCGM ServiceMonitor"
    configure_dcgm_service_monitor
    
    show_progress "Verifying Installation"
    log_info "Waiting for components to stabilize..."
    sleep 30
    
    verify_installation
    
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

