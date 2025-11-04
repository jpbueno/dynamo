# NVIDIA Dynamo Platform - Workshop Preparation Kit

Welcome! This repository contains everything you need to prepare for the **NVIDIA Dynamo Platform Workshop** on **Friday, November 7, 2025**.

## 📦 What's Included

This preparation kit contains:

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

### Recommended Preparation Steps

1. **Week Before Workshop** (This Week)
   - [ ] Read through `DYNAMO_WORKSHOP_GUIDE.md` (30 minutes)
   - [ ] Set up your Kubernetes cluster
   - [ ] Verify you have all required access and permissions
   - [ ] Install the Dynamo Platform following the guide

2. **3-4 Days Before Workshop**
   - [ ] Run the health check: `./check-dynamo-health.sh`
   - [ ] Practice troubleshooting any issues
   - [ ] Test deploying sample workloads
   - [ ] Familiarize yourself with the quick reference

3. **Day Before Workshop**
   - [ ] Verify all components are still healthy
   - [ ] Review the architecture overview
   - [ ] Bookmark the quick reference
   - [ ] Prepare questions for your instructor

4. **Workshop Day**
   - [ ] Run final health check
   - [ ] Have the quick reference open
   - [ ] Keep the health check script running
   - [ ] Be ready to learn! 🎓

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

**When to Use:** During initial setup and when you need detailed explanations

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

The workshop will likely cover:

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

### Before the Workshop
- Review the troubleshooting section in the workshop guide
- Check NVIDIA Developer Forums
- Reach out to your workshop instructor

### During the Workshop
- Ask your instructor
- Collaborate with other participants
- Use the quick reference guide

### After the Workshop
- NVIDIA Developer Forums
- Internal NVIDIA Slack: #dynamo-platform
- GitHub Issues for specific components

## ✅ Final Checklist

Before the workshop, make sure:

- [ ] I've read the complete workshop guide
- [ ] I can access my Kubernetes cluster
- [ ] kubectl and helm are installed and working
- [ ] I've successfully installed the Dynamo Platform
- [ ] All components show as healthy
- [ ] I've tested deploying a sample workload
- [ ] I'm familiar with the quick reference commands
- [ ] I've practiced troubleshooting common issues
- [ ] I know where to find help during the workshop
- [ ] I'm excited and ready to learn! 🚀

## 📅 Important Dates

- **Today:** October 30, 2025 (Wednesday) - Start preparation
- **Workshop:** November 7, 2025 (Friday) - Be ready!
- **Suggested Preparation Time:** 2-3 hours over the next week

## 🎉 You're All Set!

You now have everything you need to successfully prepare for the workshop. Follow the guides, practice the commands, and don't hesitate to experiment with the platform.

**Pro Tip:** The best way to learn is by doing. Don't just read the guides—actually install the platform, break things, fix them, and understand how everything works together.

Good luck with your preparation! See you at the workshop! 🚀

---

**Last Updated:** October 30, 2025  
**Workshop Date:** Friday, November 7, 2025  
**Platform Version:** NVIDIA Dynamo v0.6.0

---

## 🙋 Questions?

If you have questions during preparation:
1. Check the troubleshooting section in `DYNAMO_WORKSHOP_GUIDE.md`
2. Review the quick reference in `QUICK_REFERENCE.md`
3. Run `./check-dynamo-health.sh` to diagnose issues
4. Reach out to your workshop instructor

Happy learning! 📚

