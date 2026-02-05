# README.md

# Cloud Native Security Lab - DVWA靶场环境

## 🎯 项目概述

这是一个基于Kubernetes和Docker的网络安全学习环境，将传统安全靶场与云原生技术结合。本项目旨在帮助学习者在真实的云原生环境中实践网络安全攻防技术。

## 📦 当前部署内容

- **DVWA (Damn Vulnerable Web Application)** - 一个经典的Web安全漏洞靶场
- **MySQL 5.7** - 数据库服务
- **Kubernetes** - 容器编排平台
- **Containerd** - 容器运行时

## 🚀 快速开始

### 前提条件
- Kubernetes集群（已使用kubeadm部署）
- kubectl命令行工具
- Docker运行时

### 部署步骤

1. **克隆仓库**
   ```bash
   git clone https://github.com/zhugemingjia/cloud-native-security-lab.git
   cd cloud-native-security-lab
