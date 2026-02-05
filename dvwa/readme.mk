# DVWA Kubernetes 部署项目

[![Kubernetes](https://img.shields.io/badge/Kubernetes-1.20+-326CE5?style=flat&logo=kubernetes)](https://kubernetes.io/)
[![DVWA](https://img.shields.io/badge/DVWA-v1.9-red?style=flat)](https://github.com/digininja/DVWA)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

> **⚠️ 安全警告**：DVWA (Damn Vulnerable Web Application) 是一个故意设计存在安全漏洞的 Web 应用，**仅用于安全学习和渗透测试训练**。请勿在生产环境或公网服务器上部署！

## 📋 项目概述

本项目提供 DVWA 在 Kubernetes 集群中的完整部署方案，包含：

- **Deployment 配置**：使用官方 `vulnerables/web-dvwa` 镜像
- **Service 配置**：集群内部服务暴露
- **端口转发指南**：通过 `kubectl port-forward` 本地安全访问
- **健康检查**：内置存活性和就绪性探针

## 🏗️ 架构说明

```
┌─────────────────┐
│     Browser     │
│  localhost:8080 │
└────────┬────────┘
         │ kubectl port-forward
         ▼
┌─────────────────┐     ┌─────────────────┐
│   Service       │────▶│   Pod (DVWA)    │
│   ClusterIP     │     │  Apache + PHP   │
│   port: 80      │     │  + MySQL        │
└─────────────────┘     └─────────────────┘
```

## 🚀 快速开始

### 前置要求

- Kubernetes 集群 (v1.20+) 或本地环境（Minikube/Kind/Docker Desktop）
- kubectl 命令行工具
- 至少 512MB 可用内存

### 1. 克隆项目

```bash
git clone <your-repo-url>
cd dvwa-k8s-deploy
```

### 2. 部署到 Kubernetes

```bash
# 创建命名空间
kubectl create namespace dvwa

# 部署 DVWA 应用
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml

# 验证部署状态
kubectl get all -n dvwa
```

### 3. 本地访问应用

```bash
# 方式一：端口转发到 Service（推荐）
kubectl port-forward -n dvwa svc/dvwa-service 8080:80

# 方式二：端口转发到具体 Pod（需先获取 Pod 名称）
kubectl get pods -n dvwa
kubectl port-forward -n dvwa pod/<pod-name> 8080:80
```

保持终端运行，浏览器访问：
- **地址**：http://localhost:8080
- **默认账号**：`admin` / `password`

## 📁 文件结构

```
.
├── README.md           # 本文件
├── deployment.yaml     # Pod 部署配置
├── service.yaml        # Service 暴露配置
├── cleanup.sh          # 清理脚本（可选）
└── LICENSE             # 许可证文件
```

## 🔧 配置详情

### Deployment 配置 (`deployment.yaml`)

| 配置项 | 说明 | 默认值 |
|--------|------|--------|
| 镜像 | DVWA 官方漏洞镜像 | `vulnerables/web-dvwa:latest` |
| 副本数 | Pod 实例数量 | `1` |
| 内存限制 | 容器内存上限 | `512Mi` |
| CPU限制 | 容器CPU上限 | `500m` |
| 健康检查 | HTTP 探测端口 | `80` (login.php) |
| 数据库密码 | 内部 MySQL 密码 | `dvwa` |

### Service 配置 (`service.yaml`)

| 配置项 | 说明 | 值 |
|--------|------|-----|
| 类型 | 服务暴露类型 | `ClusterIP`（集群内部） |
| 端口 | 服务端口 | `80` |
| 目标端口 | 容器端口 | `80` |
| 选择器 | 关联 Pod 标签 | `app: dvwa` |

## 🎯 首次使用指南

### 1. 初始化数据库

访问 http://localhost:8080/setup.php，点击 **"Create / Reset Database"** 按钮。

### 2. 登录应用

初始化完成后会自动跳转到登录页面：
- **用户名**：`admin`
- **密码**：`password`

### 3. 调整安全级别

登录后点击左侧 **"DVWA Security"**，根据学习需求调整难度：
- **Low**：无安全防护，适合初学者
- **Medium**：基础防护，适合练习绕过
- **High**：完整防护，适合高级测试
- **Impossible**：安全代码示例

## 🛠️ 常用命令

```bash
# 查看 Pod 状态
kubectl get pods -n dvwa -o wide

# 查看日志
kubectl logs -n dvwa -f deployment/dvwa

# 进入容器调试
kubectl exec -it -n dvwa deployment/dvwa -- /bin/bash

# 删除部署
kubectl delete namespace dvwa

# 强制重启
kubectl rollout restart deployment/dvwa -n dvwa
```

## 🔒 安全建议

1. **本地环境限制**：仅通过 `localhost` 或 `127.0.0.1` 访问，不暴露到公网
2. **命名空间隔离**：使用独立命名空间 `dvwa`，避免影响其他应用
3. **资源限制**：设置了内存和 CPU 限制，防止资源耗尽攻击影响主机
4. **及时清理**：学习完成后立即执行清理命令删除部署

## 🌐 其他访问方式（可选）

### NodePort 模式（集群内访问）

如需从集群其他节点访问，修改 `service.yaml`：

```yaml
spec:
  type: NodePort
  ports:
  - port: 80
    targetPort: 80
    nodePort: 30080  # 范围 30000-32767
```

访问地址：`http://<NodeIP>:30080`

### Ingress 模式（生产环境不推荐）

如需使用 Ingress，请确保添加 IP 白名单和网络策略限制。

## ❓ 常见问题

**Q: Pod 启动后立即崩溃？**
A: 检查资源限制是否过低，或执行 `kubectl logs -n dvwa deployment/dvwa` 查看错误。

**Q: 数据库初始化失败？**
A: 确保 Pod 完全启动（状态为 `Running`）后再访问 setup.php 页面。

**Q: 端口转发断开后无法访问？**
A: `kubectl port-forward` 需要保持终端运行，断开即停止转发，重新执行命令即可。

**Q: 如何修改默认密码？**
A: 在环境变量中添加 `MYSQL_PASS`，或进入容器修改 `/var/www/html/config/config.inc.php`。

## 📚 学习资源

- [DVWA 官方仓库](https://github.com/digininja/DVWA)
- [DVWA 漏洞教程](https://github.com/digininja/DVWA/wiki)
- [Kubernetes 官方文档](https://kubernetes.io/docs/home/)

## 🤝 贡献指南

欢迎提交 Issue 和 PR！请确保：
1. 描述清楚问题或改进建议
2. 遵循现有代码风格
3. 更新相关文档

## 📄 许可证

本项目采用 [MIT License](LICENSE) 开源。

---

<div align="center">

**⚠️ 仅用于教育目的，请勿用于非法活动 ⚠️**

</div>
