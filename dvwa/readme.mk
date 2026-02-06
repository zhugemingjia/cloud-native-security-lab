# DVWA Kubernetes 部署

## 项目概述
使用 Kubernetes 部署 Damn Vulnerable Web Application (DVWA) 漏洞测试环境。

## 部署步骤

### 1. 应用配置文件
```bash
kubectl apply -f manifests/

### 端口转发
```bash
kubectl port-forward svc/dvwa-service 8080:80

###之后就能通过节点IP+映射端口访问到DVWA

###
用户名：admin
密码：password
