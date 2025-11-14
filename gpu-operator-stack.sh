#!/bin/bash
# GPU Operator Stack Management Script
# Handles: Installation, Snapshot Creation, Restoration
# For Ubuntu 22.04

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

log_section() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

show_usage() {
    cat <<EOF
GPU Operator Stack Management Script

Usage: $0 [COMMAND] [OPTIONS]

Commands:
  install              Install complete stack (Kubernetes, GPU Operator, Prometheus, Grafana)
  snapshot             Create snapshot of current server state
  restore <dir>        Restore from snapshot (requires snapshot directory)
  status               Show current stack status
  health [namespace]   Check health of Dynamo Platform (default: dynamo-system)
  troubleshoot-helm    Troubleshoot Helm disk space issues
  push [token]         Create GitHub repo and push code (requires token)
  help                 Show this help message

Examples:
  $0 install                    # Install everything
  $0 snapshot                   # Create snapshot
  $0 restore ./snapshot         # Restore from snapshot
  $0 status                     # Check status
  $0 health dynamo-system       # Check Dynamo Platform health
  $0 troubleshoot-helm          # Fix Helm disk issues
  $0 push <github_token>        # Push to GitHub

EOF
}

# ============================================================================
# INSTALLATION FUNCTIONS
# ============================================================================

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

initialize_cluster() {
    log_info "Initializing Kubernetes cluster..."
    
    if kubectl cluster-info &>/dev/null 2>&1; then
        log_warn "Kubernetes cluster already initialized. Skipping..."
        return 0
    fi
    
    sudo kubeadm init --pod-network-cidr=$POD_NETWORK_CIDR
    
    mkdir -p $HOME/.kube
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config
    
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
    
    if kubectl get pods -n kube-flannel &>/dev/null 2>&1; then
        log_warn "Flannel CNI already installed. Skipping..."
        return 0
    fi
    
    kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
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
    
    helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
    helm repo update nvidia
    
    kubectl create namespace $GPU_OPERATOR_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
    
    if helm list -n $GPU_OPERATOR_NAMESPACE | grep -q gpu-operator; then
        log_warn "GPU Operator already installed. Skipping..."
        return 0
    fi
    
    helm install --wait gpu-operator \
        nvidia/gpu-operator \
        --namespace $GPU_OPERATOR_NAMESPACE \
        --set operator.defaultRuntime=containerd \
        --timeout 10m
    
    kubectl wait --for=condition=ready pod -l app=gpu-operator -n $GPU_OPERATOR_NAMESPACE --timeout=600s || true
    log_info "GPU Operator installed"
}

install_prometheus_grafana() {
    log_info "Installing Prometheus and Grafana..."
    
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo update prometheus-community
    
    kubectl create namespace $MONITORING_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
    
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
    
    kubectl wait --for=condition=ready pod -l app=nvidia-dcgm-exporter -n $GPU_OPERATOR_NAMESPACE --timeout=300s || true
    
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
}

cmd_install() {
    log_section "GPU Operator Stack Installation"
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
    
    log_info "Waiting for CoreDNS to be ready..."
    kubectl wait --for=condition=ready pod -l k8s-app=kube-dns -n kube-system --timeout=300s || true
    
    install_helm
    install_gpu_operator
    install_prometheus_grafana
    configure_dcgm_service_monitor
    
    log_info "Waiting for components to stabilize..."
    sleep 30
    
    verify_installation
    print_access_info
    
    log_info "Installation completed!"
}

# ============================================================================
# SNAPSHOT FUNCTIONS
# ============================================================================

cmd_snapshot() {
    log_section "Creating Server Snapshot"
    
    SNAPSHOT_DIR="$HOME/brev-snapshot-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$SNAPSHOT_DIR"
    
    log_info "Creating snapshot in $SNAPSHOT_DIR..."
    
    # System Information
    log_info "Capturing system information..."
    cat /etc/os-release > "$SNAPSHOT_DIR/os-release.txt"
    uname -a > "$SNAPSHOT_DIR/uname.txt"
    hostname > "$SNAPSHOT_DIR/hostname.txt"
    
    # Installed Packages
    log_info "Capturing installed packages..."
    dpkg --get-selections > "$SNAPSHOT_DIR/installed-packages.txt"
    apt-mark showhold > "$SNAPSHOT_DIR/held-packages.txt" 2>/dev/null || true
    
    # APT Sources
    log_info "Capturing APT sources..."
    cp -r /etc/apt/sources.list.d "$SNAPSHOT_DIR/apt-sources.d" 2>/dev/null || true
    cp /etc/apt/sources.list "$SNAPSHOT_DIR/apt-sources.list" 2>/dev/null || true
    
    # Helm Repositories
    log_info "Capturing Helm repositories..."
    helm repo list > "$SNAPSHOT_DIR/helm-repos.txt" 2>/dev/null || true
    mkdir -p "$SNAPSHOT_DIR/helm"
    cp -r ~/.config/helm "$SNAPSHOT_DIR/helm/config" 2>/dev/null || true
    
    # Kubernetes Configuration
    if kubectl cluster-info &>/dev/null; then
        log_info "Capturing Kubernetes configuration..."
        kubectl cluster-info > "$SNAPSHOT_DIR/k8s-cluster-info.txt" 2>/dev/null || true
        kubectl get nodes -o wide > "$SNAPSHOT_DIR/k8s-nodes.txt" 2>/dev/null || true
        kubectl get namespaces > "$SNAPSHOT_DIR/k8s-namespaces.txt" 2>/dev/null || true
        
        mkdir -p "$SNAPSHOT_DIR/k8s-resources"
        for ns in $(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}'); do
            log_info "  Exporting resources from namespace: $ns"
            mkdir -p "$SNAPSHOT_DIR/k8s-resources/$ns"
            kubectl get all -n "$ns" -o yaml > "$SNAPSHOT_DIR/k8s-resources/$ns/all-resources.yaml" 2>/dev/null || true
            kubectl get configmaps -n "$ns" -o yaml > "$SNAPSHOT_DIR/k8s-resources/$ns/configmaps.yaml" 2>/dev/null || true
            kubectl get secrets -n "$ns" -o yaml > "$SNAPSHOT_DIR/k8s-resources/$ns/secrets.yaml" 2>/dev/null || true
        done
        
        kubectl get clusterroles,clusterrolebindings -o yaml > "$SNAPSHOT_DIR/k8s-resources/cluster-roles.yaml" 2>/dev/null || true
        kubectl get crds -o yaml > "$SNAPSHOT_DIR/k8s-resources/crds.yaml" 2>/dev/null || true
    fi
    
    # Kubernetes Config Files
    log_info "Capturing Kubernetes config files..."
    mkdir -p "$SNAPSHOT_DIR/k8s-config"
    cp -r /etc/kubernetes "$SNAPSHOT_DIR/k8s-config/etc-kubernetes" 2>/dev/null || true
    cp -r ~/.kube "$SNAPSHOT_DIR/k8s-config/kube-config" 2>/dev/null || true
    
    # Containerd Configuration
    log_info "Capturing containerd configuration..."
    cp /etc/containerd/config.toml "$SNAPSHOT_DIR/containerd-config.toml" 2>/dev/null || true
    
    # System Configuration
    log_info "Capturing system configuration..."
    cp /etc/fstab "$SNAPSHOT_DIR/fstab" 2>/dev/null || true
    cp /etc/modules-load.d/k8s.conf "$SNAPSHOT_DIR/k8s-modules.conf" 2>/dev/null || true
    cp /etc/sysctl.d/k8s.conf "$SNAPSHOT_DIR/k8s-sysctl.conf" 2>/dev/null || true
    sysctl -a > "$SNAPSHOT_DIR/sysctl-all.txt" 2>/dev/null || true
    
    # Firewall Rules
    log_info "Capturing firewall rules..."
    sudo iptables-save > "$SNAPSHOT_DIR/iptables-rules.txt" 2>/dev/null || true
    sudo ip6tables-save > "$SNAPSHOT_DIR/ip6tables-rules.txt" 2>/dev/null || true
    
    # Git Repositories
    log_info "Capturing Git repositories..."
    mkdir -p "$SNAPSHOT_DIR/git-repos"
    if [ -d "$HOME/dynamo" ]; then
        cp -r "$HOME/dynamo" "$SNAPSHOT_DIR/git-repos/dynamo"
        sed -i '/credential/d' "$SNAPSHOT_DIR/git-repos/dynamo/.git/config" 2>/dev/null || true
    fi
    
    # Environment Variables and Shell Configuration
    log_info "Capturing shell configuration..."
    cp ~/.bashrc "$SNAPSHOT_DIR/bashrc" 2>/dev/null || true
    cp ~/.bash_aliases "$SNAPSHOT_DIR/bash_aliases" 2>/dev/null || true
    env > "$SNAPSHOT_DIR/environment.txt" 2>/dev/null || true
    
    # Service Status
    log_info "Capturing service status..."
    systemctl list-units --type=service --state=running > "$SNAPSHOT_DIR/running-services.txt" 2>/dev/null || true
    systemctl list-units --type=service --state=enabled > "$SNAPSHOT_DIR/enabled-services.txt" 2>/dev/null || true
    
    # Network Configuration
    log_info "Capturing network configuration..."
    ip addr show > "$SNAPSHOT_DIR/ip-addr.txt" 2>/dev/null || true
    ip route show > "$SNAPSHOT_DIR/ip-route.txt" 2>/dev/null || true
    
    # Create README
    cat > "$SNAPSHOT_DIR/README.md" <<EOF
# Brev Server Snapshot

Created: $(date)
Hostname: $(hostname)
OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)

## Contents

This snapshot contains:
- Installed packages list
- APT repository configuration
- Helm repositories
- Kubernetes cluster configuration and resources
- System configuration files
- Git repositories
- Shell configuration
- Firewall rules

## Restoration

To restore this snapshot on a new Ubuntu 22.04 server:

1. Copy this entire snapshot directory to the new server
2. Run: \`bash gpu-operator-stack.sh restore $(basename "$SNAPSHOT_DIR")\`
3. Follow the post-restoration steps shown at the end

## Manual Steps Required

Some steps require manual intervention:
- Kubernetes cluster initialization (kubeadm init)
- GPU Operator installation
- Prometheus/Grafana setup
- Firewall configuration (may need adjustment for new IP)

## Important Notes

- Secrets are included but may need to be regenerated
- IP addresses and hostnames will differ on new server
- Some certificates may need regeneration
- Check firewall rules for IP-specific configurations
EOF
    
    # Create archive
    log_info "Creating archive..."
    cd "$HOME"
    tar -czf "${SNAPSHOT_DIR}.tar.gz" "$(basename "$SNAPSHOT_DIR")" 2>/dev/null || \
        tar -czf "${SNAPSHOT_DIR}.tar.gz" -C "$HOME" "$(basename "$SNAPSHOT_DIR")"
    
    echo ""
    log_info "Snapshot created successfully!"
    echo "Location: $SNAPSHOT_DIR"
    echo "Archive: ${SNAPSHOT_DIR}.tar.gz"
    echo ""
    echo "To restore on a new server:"
    echo "  1. Copy ${SNAPSHOT_DIR}.tar.gz to the new server"
    echo "  2. Extract: tar -xzf ${SNAPSHOT_DIR}.tar.gz"
    echo "  3. Run: cd $(basename "$SNAPSHOT_DIR") && bash ../gpu-operator-stack.sh restore ."
}

# ============================================================================
# RESTORE FUNCTIONS
# ============================================================================

cmd_restore() {
    log_section "Restoring from Snapshot"
    
    if [ -z "$1" ]; then
        log_error "Please provide snapshot directory path"
        echo "Usage: $0 restore <snapshot-directory>"
        exit 1
    fi
    
    SNAPSHOT_DIR="$1"
    if [ ! -d "$SNAPSHOT_DIR" ]; then
        log_error "Snapshot directory not found: $SNAPSHOT_DIR"
        exit 1
    fi
    
    log_info "Starting restoration from $SNAPSHOT_DIR..."
    log_warn "This will modify system configuration. Press Ctrl+C to cancel..."
    sleep 5
    
    sudo apt-get update
    sudo apt-get upgrade -y
    
    log_info "Installing packages..."
    sudo apt-get install -y $(cat "$SNAPSHOT_DIR/installed-packages.txt" | grep -v deinstall | awk '{print $1}')
    
    log_info "Restoring APT sources..."
    sudo cp "$SNAPSHOT_DIR/apt-sources.list" /etc/apt/sources.list 2>/dev/null || true
    sudo cp -r "$SNAPSHOT_DIR/apt-sources.d"/* /etc/apt/sources.list.d/ 2>/dev/null || true
    sudo apt-get update
    
    log_info "Installing Kubernetes tools..."
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
    sudo apt-get update
    sudo apt-get install -y kubelet kubeadm kubectl
    
    log_info "Installing Helm..."
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    
    log_info "Restoring Helm repositories..."
    if [ -f "$SNAPSHOT_DIR/helm-repos.txt" ]; then
        while IFS= read -r line; do
            if [[ $line =~ ^[a-zA-Z] ]]; then
                name=$(echo $line | awk '{print $1}')
                url=$(echo $line | awk '{print $2}')
                helm repo add "$name" "$url" 2>/dev/null || true
            fi
        done < "$SNAPSHOT_DIR/helm-repos.txt"
        helm repo update
    fi
    
    log_info "Configuring containerd..."
    sudo mkdir -p /etc/containerd
    if [ -f "$SNAPSHOT_DIR/containerd-config.toml" ]; then
        sudo cp "$SNAPSHOT_DIR/containerd-config.toml" /etc/containerd/config.toml
    fi
    sudo systemctl restart containerd
    sudo systemctl enable containerd
    
    log_info "Configuring system settings..."
    if [ -f "$SNAPSHOT_DIR/k8s-modules.conf" ]; then
        sudo cp "$SNAPSHOT_DIR/k8s-modules.conf" /etc/modules-load.d/k8s.conf
        sudo modprobe br_netfilter
    fi
    
    if [ -f "$SNAPSHOT_DIR/k8s-sysctl.conf" ]; then
        sudo cp "$SNAPSHOT_DIR/k8s-sysctl.conf" /etc/sysctl.d/k8s.conf
        sudo sysctl --system
    fi
    
    log_info "Disabling swap..."
    sudo swapoff -a
    if [ -f "$SNAPSHOT_DIR/fstab" ]; then
        sudo cp "$SNAPSHOT_DIR/fstab" /etc/fstab
    fi
    
    log_info "Restoring shell configuration..."
    if [ -f "$SNAPSHOT_DIR/bashrc" ]; then
        cp "$SNAPSHOT_DIR/bashrc" ~/.bashrc
    fi
    if [ -f "$SNAPSHOT_DIR/bash_aliases" ]; then
        cp "$SNAPSHOT_DIR/bash_aliases" ~/.bash_aliases
    fi
    
    log_info "Restoring Git repositories..."
    if [ -d "$SNAPSHOT_DIR/git-repos/dynamo" ]; then
        cp -r "$SNAPSHOT_DIR/git-repos/dynamo" ~/dynamo
    fi
    
    log_info "Restoring firewall rules..."
    if [ -f "$SNAPSHOT_DIR/iptables-rules.txt" ]; then
        sudo iptables-restore < "$SNAPSHOT_DIR/iptables-rules.txt" 2>/dev/null || true
    fi
    
    echo ""
    log_info "Restoration complete!"
    echo ""
    echo "Next steps:"
    echo "1. Initialize Kubernetes cluster: sudo kubeadm init --pod-network-cidr=10.244.0.0/16"
    echo "2. Configure kubectl: mkdir -p \$HOME/.kube && sudo cp -i /etc/kubernetes/admin.conf \$HOME/.kube/config && sudo chown \$(id -u):\$(id -g) \$HOME/.kube/config"
    echo "3. Remove control-plane taint: kubectl taint nodes --all node-role.kubernetes.io/control-plane-"
    echo "4. Install Flannel CNI: kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml"
    echo "5. Run installation: bash gpu-operator-stack.sh install"
}

# ============================================================================
# STATUS FUNCTION
# ============================================================================

cmd_status() {
    log_section "GPU Operator Stack Status"
    
    echo "=== System Information ==="
    cat /etc/os-release | grep PRETTY_NAME
    echo "Hostname: $(hostname)"
    echo ""
    
    if command -v kubectl &>/dev/null; then
        echo "=== Kubernetes Cluster ==="
        if kubectl cluster-info &>/dev/null 2>&1; then
            kubectl cluster-info | head -1
            echo ""
            kubectl get nodes
            echo ""
            echo "=== Namespaces ==="
            kubectl get namespaces
            echo ""
            echo "=== GPU Operator ==="
            kubectl get pods -n $GPU_OPERATOR_NAMESPACE 2>/dev/null || echo "GPU Operator not installed"
            echo ""
            echo "=== Monitoring Stack ==="
            kubectl get pods -n $MONITORING_NAMESPACE 2>/dev/null || echo "Monitoring stack not installed"
        else
            echo "Kubernetes cluster not initialized"
        fi
    else
        echo "Kubernetes tools not installed"
    fi
    
    echo ""
    echo "=== Helm Repositories ==="
    helm repo list 2>/dev/null || echo "Helm not installed"
    
    echo ""
    echo "=== GPU Resources ==="
    if kubectl cluster-info &>/dev/null 2>&1; then
        kubectl get nodes -o json | jq -r '.items[0].status.capacity | to_entries[] | select(.key | contains("gpu"))' 2>/dev/null || echo "No GPU resources detected"
    else
        echo "Cluster not available"
    fi
}

# ============================================================================
# HEALTH CHECK FUNCTION (Dynamo Platform)
# ============================================================================

cmd_health() {
    log_section "Dynamo Platform Health Check"
    
    NAMESPACE="${1:-dynamo-system}"
    
    if ! kubectl get namespace $NAMESPACE &> /dev/null; then
        log_error "Namespace $NAMESPACE does not exist"
        exit 1
    fi
    
    log_info "Namespace exists: $NAMESPACE"
    echo ""
    
    echo "=== Pod Status ==="
    kubectl get pods -n $NAMESPACE -o wide
    echo ""
    
    echo "=== Component Health ==="
    
    check_component() {
        local name=$1
        local selector=$2
        local pods=$(kubectl get pods -n $NAMESPACE -l "$selector" --no-headers 2>/dev/null | wc -l | tr -d ' ')
        
        if [ "$pods" -eq 0 ]; then
            echo -e "  ${YELLOW}⚠️  $name: No pods found${NC}"
            return 1
        fi
        
        local ready=$(kubectl get pods -n $NAMESPACE -l "$selector" -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
        local running=$(kubectl get pods -n $NAMESPACE -l "$selector" -o jsonpath='{.items[*].status.phase}' 2>/dev/null)
        
        if [[ "$ready" == *"True"* ]] && [[ "$running" == *"Running"* ]]; then
            echo -e "  ${GREEN}✅ $name: Healthy ($pods pods)${NC}"
            return 0
        elif [[ "$running" == *"Running"* ]]; then
            echo -e "  ${YELLOW}⚠️  $name: Running but not ready ($pods pods)${NC}"
            return 1
        else
            echo -e "  ${RED}❌ $name: Not healthy ($pods pods)${NC}"
            kubectl get pods -n $NAMESPACE -l "$selector" --no-headers | grep -v "Running.*1/1"
            return 1
        fi
    }
    
    HEALTHY=0
    check_component "Dynamo Operator" "app.kubernetes.io/name=dynamo-operator" || ((HEALTHY++))
    check_component "etcd" "app.kubernetes.io/name=etcd" || ((HEALTHY++))
    check_component "NATS" "app.kubernetes.io/name=nats" || ((HEALTHY++))
    check_component "KAI Scheduler" "app=scheduler" || ((HEALTHY++))
    check_component "KAI Operator" "app=kai-operator" || ((HEALTHY++))
    check_component "Binder" "app=binder" || ((HEALTHY++))
    check_component "Admission Controller" "app=admission" || ((HEALTHY++))
    check_component "Grove Operator" "app.kubernetes.io/name=grove-operator" || ((HEALTHY++))
    
    echo ""
    echo "=== Storage Status ==="
    kubectl get pvc -n $NAMESPACE 2>/dev/null || echo "No PVCs found"
    
    echo ""
    echo "=== Services ==="
    kubectl get svc -n $NAMESPACE
    
    echo ""
    echo "=== Recent Events ==="
    kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp' | tail -10
    
    echo ""
    echo "=== CRDs Installed ==="
    kubectl get crds | grep -E 'dynamo|kai|grove' | wc -l | xargs echo "Total Dynamo-related CRDs:"
    
    echo ""
    if [ $HEALTHY -eq 0 ]; then
        log_info "All Components Healthy"
        exit 0
    else
        log_warn "$HEALTHY Component(s) Need Attention"
        echo ""
        echo "Run these commands to investigate:"
        echo "  kubectl describe pods -n $NAMESPACE"
        echo "  kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=dynamo-operator --tail=50"
        echo "  kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp'"
        exit 1
    fi
}

# ============================================================================
# TROUBLESHOOT HELM FUNCTION
# ============================================================================

cmd_troubleshoot_helm() {
    log_section "Troubleshooting Helm Disk Space Issues"
    
    echo "1. Checking disk space:"
    df -h /home
    echo ""
    
    echo "2. Checking inode usage:"
    df -i /home
    echo ""
    
    echo "3. Checking Helm cache:"
    if [ -d ~/.cache/helm ]; then
        du -sh ~/.cache/helm
        echo ""
        echo "4. Helm cache breakdown:"
        du -sh ~/.cache/helm/* 2>/dev/null | sort -h || echo "  Cache directory exists but is empty or inaccessible"
    else
        echo "  Helm cache directory does not exist"
    fi
    echo ""
    
    echo "5. Top 10 directories using space in home:"
    du -h --max-depth=1 ~ 2>/dev/null | sort -h | tail -10
    echo ""
    
    echo "=== Attempting Solution 1: Clean Helm Cache ==="
    rm -rf ~/.cache/helm 2>/dev/null || true
    mkdir -p ~/.cache/helm/repository
    echo "Helm cache cleaned. Attempting to add repo..."
    helm repo remove nvidia 2>/dev/null || true
    
    if helm repo add nvidia https://helm.ngc.nvidia.com/nvidia 2>&1; then
        log_info "Success!"
    else
        log_warn "Still failing, trying Solution 2..."
        echo ""
        echo "=== Attempting Solution 2: Use /tmp for Helm Cache ==="
        export HELM_CACHE_HOME=/tmp/helm-cache-$(whoami)
        mkdir -p $HELM_CACHE_HOME
        echo "Helm cache set to: $HELM_CACHE_HOME"
        if helm repo add nvidia https://helm.ngc.nvidia.com/nvidia 2>&1; then
            log_info "Success!"
        else
            log_warn "Still failing, try Solution 3..."
        fi
    fi
    
    echo ""
    echo "=== Fixing kubeconfig permissions ==="
    chmod 600 ~/.kube/config 2>/dev/null && log_info "Fixed kubeconfig permissions" || log_warn "Could not fix kubeconfig (file may not exist)"
    
    echo ""
    echo "=== Summary ==="
    echo "If repo add still fails, use Solution 3: Install directly from OCI:"
    echo "  helm install dynamo-platform oci://nvcr.io/nvidia/helm-charts/dynamo-platform \\"
    echo "    --version 0.6.0 --namespace dynamo-system --create-namespace"
}

# ============================================================================
# GITHUB PUSH FUNCTION
# ============================================================================

cmd_push() {
    log_section "GitHub Repository Setup and Push"
    
    REPO_NAME="dynamo"
    GITHUB_USER="jpbueno"
    GITHUB_TOKEN="${1:-${GITHUB_TOKEN}}"
    
    log_info "Creating GitHub repository: $GITHUB_USER/$REPO_NAME"
    
    if [ -z "$GITHUB_TOKEN" ]; then
        log_error "GitHub token not provided."
        echo ""
        echo "Please either:"
        echo "1. Create the repository manually at: https://github.com/new"
        echo "   Repository name: $REPO_NAME"
        echo "   Visibility: Public or Private (your choice)"
        echo "   Then run: git push -u origin main"
        echo ""
        echo "OR"
        echo ""
        echo "2. Get a GitHub token from: https://github.com/settings/tokens"
        echo "   Then run: $0 push <your_token>"
        exit 1
    fi
    
    # Create repository via GitHub API
    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
      -H "Authorization: token $GITHUB_TOKEN" \
      -H "Accept: application/vnd.github.v3+json" \
      https://api.github.com/user/repos \
      -d "{\"name\":\"$REPO_NAME\",\"description\":\"NVIDIA Dynamo Platform - Workshop Preparation Kit\",\"private\":false}")
    
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | sed '$d')
    
    if [ "$HTTP_CODE" = "201" ]; then
        log_info "Repository created successfully!"
        log_info "Pushing code to GitHub..."
        git push -u origin main
        log_info "Done! Repository available at: https://github.com/$GITHUB_USER/$REPO_NAME"
    elif [ "$HTTP_CODE" = "422" ]; then
        log_warn "Repository might already exist, attempting to push..."
        git push -u origin main || log_error "Push failed. Please check repository permissions."
    else
        log_error "Failed to create repository. HTTP Code: $HTTP_CODE"
        echo "Response: $BODY"
        exit 1
    fi
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    case "${1:-help}" in
        install)
            cmd_install
            ;;
        snapshot)
            cmd_snapshot
            ;;
        restore)
            cmd_restore "$2"
            ;;
        status)
            cmd_status
            ;;
        health)
            cmd_health "$2"
            ;;
        troubleshoot-helm)
            cmd_troubleshoot_helm
            ;;
        push)
            cmd_push "$2"
            ;;
        help|--help|-h)
            show_usage
            ;;
        *)
            log_error "Unknown command: $1"
            echo ""
            show_usage
            exit 1
            ;;
    esac
}

main "$@"

