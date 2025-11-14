#!/bin/bash

# Troubleshooting script for Helm "no space left on device" error
# Run this on the remote server: ssh jbuenosantan@10.185.124.93

echo "=== Diagnosing Disk Space Issue ==="
echo ""

# Check disk space
echo "1. Checking disk space:"
df -h /home
echo ""

# Check inode usage
echo "2. Checking inode usage:"
df -i /home
echo ""

# Check Helm cache size
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

# Check what's using space in home directory
echo "5. Top 10 directories using space in home:"
du -h --max-depth=1 ~ 2>/dev/null | sort -h | tail -10
echo ""

# Try Solution 1: Aggressive Helm cache cleanup
echo "=== Attempting Solution 1: Clean Helm Cache ==="
rm -rf ~/.cache/helm 2>/dev/null || true
mkdir -p ~/.cache/helm/repository
echo "Helm cache cleaned. Attempting to add repo..."
helm repo remove nvidia 2>/dev/null || true

if helm repo add nvidia https://helm.ngc.nvidia.com/nvidia 2>&1; then
    echo "✅ Success!"
else
    echo "❌ Still failing, trying Solution 2..."
    echo ""
    echo "=== Attempting Solution 2: Use /tmp for Helm Cache ==="
    export HELM_CACHE_HOME=/tmp/helm-cache-$(whoami)
    mkdir -p $HELM_CACHE_HOME
    echo "Helm cache set to: $HELM_CACHE_HOME"
    if helm repo add nvidia https://helm.ngc.nvidia.com/nvidia 2>&1; then
        echo "✅ Success!"
    else
        echo "❌ Still failing, try Solution 3..."
    fi
fi

echo ""
echo "=== Fixing kubeconfig permissions ==="
chmod 600 ~/.kube/config 2>/dev/null && echo "✅ Fixed kubeconfig permissions" || echo "⚠️  Could not fix kubeconfig (file may not exist)"

echo ""
echo "=== Summary ==="
echo "If repo add still fails, use Solution 3: Install directly from OCI:"
echo "  helm install dynamo-platform oci://nvcr.io/nvidia/helm-charts/dynamo-platform \\"
echo "    --version 0.6.0 --namespace dynamo-system --create-namespace"
