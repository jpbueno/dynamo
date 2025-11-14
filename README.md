# NVIDIA Dynamo Platform - Workshop

> A hands-on workshop for deploying, managing, and operating the NVIDIA Dynamo Platform—a comprehensive AI/ML orchestration solution for Kubernetes clusters.

## 📖 Description

This workshop provides a complete, hands-on learning experience for the **NVIDIA Dynamo Platform v0.6.0**, an enterprise-grade AI/ML orchestration platform designed to simplify the deployment and management of distributed inference workloads at scale.

### What You'll Learn

- **Platform Architecture**: Understand the core components and how they work together
- **Deployment**: Master Helm-based installation and configuration
- **Workload Management**: Deploy and manage AI inference workloads effectively
- **Advanced Scheduling**: Leverage the KAI scheduler for optimized AI/ML workload placement
- **Multi-Node Inference**: Use the Grove operator for distributed inference scenarios
- **Operations**: Monitor, troubleshoot, and maintain a production-ready deployment

### Who Should Attend

- DevOps engineers working with Kubernetes and AI/ML workloads
- Platform engineers building AI infrastructure
- Data scientists and ML engineers deploying inference workloads
- Anyone interested in modern AI/ML orchestration platforms

### Workshop Outcomes

By the end of this workshop, you will:
- ✅ Have a fully functional Dynamo Platform deployment
- ✅ Understand the platform's architecture and components
- ✅ Be able to deploy and manage AI inference workloads
- ✅ Know how to troubleshoot common issues
- ✅ Have hands-on experience with production-ready AI infrastructure

## 📦 What's Included

This workshop contains:

1. **DYNAMO_WORKSHOP_GUIDE.md** - Comprehensive step-by-step installation and configuration guide
2. **QUICK_REFERENCE.md** - Quick reference card with essential commands
3. **check-dynamo-health.sh** - Automated health check script
4. **README.md** - This file

## 🚀 Getting Started

### Quick Setup (5 minutes)

```bash
# 1. Clone or navigate to this directory
cd /Users/jbuenosantan/Library/CloudStorage/OneDrive-NVIDIACorporation/NVIDIA/Inference/dynamo

# 2. Verify prerequisites
kubectl cluster-info
helm version

# 3. Start with the workshop guide
open DYNAMO_WORKSHOP_GUIDE.md  # or use your preferred markdown viewer
```

### Workshop Structure

1. **Prerequisites Check** (10 minutes)
   - [ ] Verify Kubernetes cluster access
   - [ ] Check kubectl and Helm installation
   - [ ] Ensure you have required permissions
   - [ ] Review system requirements

2. **Platform Installation** (30 minutes)
   - [ ] Follow the installation guide in `DYNAMO_WORKSHOP_GUIDE.md`
   - [ ] Install the Dynamo Platform using Helm
   - [ ] Verify all components are running
   - [ ] Run health check: `./check-dynamo-health.sh`

3. **Hands-On Exercises** (60 minutes)
   - [ ] Deploy sample workloads
   - [ ] Explore component interactions
   - [ ] Practice troubleshooting scenarios
   - [ ] Test advanced features

4. **Workshop Wrap-up** (20 minutes)
   - [ ] Review key concepts
   - [ ] Q&A session
   - [ ] Access additional resources
   - [ ] Next steps and practice recommendations

## 📚 Document Overview

### DYNAMO_WORKSHOP_GUIDE.md

**Purpose:** Complete installation and configuration guide  
**Read Time:** 45-60 minutes  
**Best For:** First-time installation and understanding the platform

**Key Sections:**
- Prerequisites and setup requirements
- Step-by-step installation with Helm
- Component verification procedures
- Troubleshooting common issues
- Testing the deployment
- Architecture overview
- Workshop exercises

**When to Use:** During the workshop installation phase and when you need detailed explanations

### QUICK_REFERENCE.md

**Purpose:** Fast command lookup and troubleshooting  
**Read Time:** 10-15 minutes  
**Best For:** Quick lookups during the workshop

**Key Sections:**
- Essential status commands
- Component-specific commands
- Troubleshooting patterns
- Testing commands
- Maintenance operations

**When to Use:** During the workshop when you need to quickly find a command

### check-dynamo-health.sh

**Purpose:** Automated health monitoring  
**Runtime:** 5-10 seconds  
**Best For:** Quick validation of platform health

**Features:**
- Checks all components automatically
- Color-coded status output
- Shows pod status and events
- Validates storage and services
- Returns exit code for automation

**Usage:**
```bash
# Basic usage (checks dynamo-system namespace)
./check-dynamo-health.sh

# Check a different namespace
./check-dynamo-health.sh my-dynamo-namespace

# Use in scripts
if ./check-dynamo-health.sh; then
    echo "Platform is healthy!"
else
    echo "Issues detected, check output above"
fi
```

## 🎯 Quick Start Commands

If you're short on time, here are the absolute essentials:

```bash
# 1. Create namespace
kubectl create namespace dynamo-system

# 2. Add NVIDIA Helm repo
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update

# 3. Install Dynamo Platform
helm install dynamo-platform nvidia/dynamo-platform \
  --namespace dynamo-system \
  --version 0.6.0 \
  --wait

# 4. Check health
./check-dynamo-health.sh

# 5. Monitor status
kubectl get pods -n dynamo-system -w
```

## 🔍 What is the Dynamo Platform?

The **NVIDIA Dynamo Platform** is a comprehensive AI/ML orchestration solution that provides:

- **Workload Management** - Deploy and manage AI inference workloads at scale
- **Advanced Scheduling** - KAI scheduler optimized for AI/ML workloads
- **Multi-Node Orchestration** - Grove operator for distributed inference
- **High-Performance Messaging** - NATS for event-driven architectures
- **State Management** - etcd for distributed configuration

### Platform Components

```
┌─────────────────────────────────────────┐
│     NVIDIA Dynamo Platform v0.6.0       │
├─────────────────────────────────────────┤
│ • Dynamo Operator (Core Controller)     │
│ • etcd (Distributed State Store)        │
│ • NATS + JetStream (Messaging)         │
│ • KAI Scheduler (AI Workload Scheduler) │
│ • Grove Operator (Multi-Node Inference) │
└─────────────────────────────────────────┘
```

## ⚠️ Known Issues from Your Manager's Deployment

Based on the deployment analysis, be aware of:

1. **Dynamo Operator Restart Loop**
   - Symptom: Controller pod may experience restarts
   - Impact: Temporary disruption to workload management
   - Resolution: Follow troubleshooting guide in workshop guide

2. **Resource Requirements**
   - Ensure adequate cluster resources (4+ CPU cores, 8GB+ RAM)
   - Verify storage class supports dynamic provisioning

3. **Production Recommendations**
   - Current setup uses 1 replica for etcd and NATS
   - For production, scale to 3 replicas for high availability

## 🎓 Workshop Topics

This workshop covers:

1. **Platform Overview** (15 min)
   - Architecture and components
   - Use cases and benefits

2. **Hands-On Deployment** (30 min)
   - Installing the platform
   - Verifying components
   - Basic troubleshooting

3. **Workload Management** (45 min)
   - Creating and deploying workloads
   - Monitoring and scaling
   - Advanced scheduling with KAI

4. **Multi-Node Inference** (30 min)
   - Grove operator usage
   - Distributed workloads
   - MPI integration

5. **Troubleshooting & Best Practices** (30 min)
   - Common issues and solutions
   - Production considerations
   - Q&A

## 📊 System Requirements

### Minimum Requirements
- Kubernetes 1.25+
- 4 CPU cores available
- 8GB RAM available
- 15GB storage
- kubectl and Helm 3.10+

### Recommended Requirements
- Kubernetes 1.27+
- 8 CPU cores available
- 16GB RAM available
- 30GB storage
- Multi-node cluster for HA

### Required Access
- Cluster admin or equivalent
- Access to container registries:
  - nvcr.io (NVIDIA)
  - docker.io (Docker Hub)
  - ghcr.io (GitHub)

## 🔧 Troubleshooting Quick Wins

### Helm Repository Error?
```bash
# "No space left on device" error - Try these in order:

# Option 1: Aggressive cleanup
rm -rf ~/.cache/helm && mkdir -p ~/.cache/helm/repository
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia && helm repo update

# Option 2: Use /tmp instead
export HELM_CACHE_HOME=/tmp/helm-cache-$(whoami)
mkdir -p $HELM_CACHE_HOME
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia && helm repo update

# Option 3: Skip repo, install directly from OCI
helm install dynamo-platform oci://nvcr.io/nvidia/helm-charts/dynamo-platform \
  --version 0.6.0 --namespace dynamo-system --create-namespace

# Fix kubeconfig permissions warning
chmod 600 ~/.kube/config
```

### Pod Not Starting?
```bash
kubectl describe pod <pod-name> -n dynamo-system
kubectl logs <pod-name> -n dynamo-system
```

### Components Not Healthy?
```bash
./check-dynamo-health.sh
kubectl get events -n dynamo-system --sort-by='.lastTimestamp'
```

### Need to Restart?
```bash
kubectl rollout restart deployment -n dynamo-system
```

### Want to Start Fresh?
```bash
helm uninstall dynamo-platform -n dynamo-system
kubectl delete namespace dynamo-system
# Then reinstall following the guide
```

## 📖 Additional Learning Resources

- [NVIDIA Dynamo Documentation](https://docs.nvidia.com/dynamo/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Helm Documentation](https://helm.sh/docs/)
- [KAI Scheduler](https://github.com/NVIDIA/KAI)
- [Grove Operator](https://github.com/NVIDIA/grove)

## 🆘 Getting Help

### During the Workshop
- Ask your instructor
- Collaborate with other participants
- Use the quick reference guide
- Review the troubleshooting section in the workshop guide

### After the Workshop
- NVIDIA Developer Forums
- Internal NVIDIA Slack: #dynamo-platform
- GitHub Issues for specific components
- Reference the quick reference guide for common commands

## ✅ Workshop Checklist

During the workshop, you will:

- [ ] Access your Kubernetes cluster
- [ ] Verify kubectl and helm are installed and working
- [ ] Install the Dynamo Platform using Helm
- [ ] Verify all components are healthy
- [ ] Deploy sample workloads
- [ ] Use the quick reference commands
- [ ] Practice troubleshooting common issues
- [ ] Learn about advanced features and best practices
- [ ] Complete hands-on exercises

## 📅 Workshop Information

- **Workshop Date:** November 7, 2025 (Friday)
- **Duration:** ~2 hours
- **Format:** Hands-on guided workshop

## 🎉 Welcome to the Workshop!

You now have everything you need to successfully complete this workshop. Follow the guides, execute the commands, and don't hesitate to experiment with the platform.

**Pro Tip:** The best way to learn is by doing. Don't just read the guides—actually install the platform, experiment with workloads, troubleshoot issues, and understand how everything works together.

Let's get started! 🚀

---

**Last Updated:** November 7, 2025  
**Workshop Date:** Friday, November 7, 2025  
**Platform Version:** NVIDIA Dynamo v0.6.0

---

## 🙋 Questions?

If you have questions during the workshop:
1. Ask your instructor or workshop facilitator
2. Check the troubleshooting section in `DYNAMO_WORKSHOP_GUIDE.md`
3. Review the quick reference in `QUICK_REFERENCE.md`
4. Run `./check-dynamo-health.sh` to diagnose issues
5. Collaborate with other participants

Happy learning! 📚

