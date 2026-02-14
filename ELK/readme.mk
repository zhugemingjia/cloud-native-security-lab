ELK Stack on Kubernetes (ECK) 安装手册
https://img.shields.io/badge/ECK-2.11.0-blue
https://img.shields.io/badge/Kubernetes-1.24%252B-brightgreen
https://img.shields.io/badge/License-MIT-yellow

使用 Elastic Cloud on Kubernetes (ECK) 在 Kubernetes 集群上部署 Elasticsearch、Kibana 和 Filebeat，搭建生产可用的日志监控系统。本指南包含详细步骤、避坑指南及生产环境建议。

📖 目录
架构概述

前置条件

快速开始

1. 安装 ECK Operator

2. 配置 NFS 持久化存储

3. 部署 Elasticsearch

4. 部署 Kibana 并配置 Ingress HTTPS

5. 部署 Filebeat 采集容器日志

验证与测试

常见问题与排查

配置速查表

卸载

贡献指南

许可证

架构概述
plain
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   Ingress/Nginx  │────▶│     Kibana      │────▶│ Elasticsearch   │
│  (HTTPS: 443)   │     │   (Port: 5601)  │     │   (Port: 9200)  │
└─────────────────┘     └─────────────────┘     └─────────────────┘
                                                        ▲
┌─────────────────┐                                     │
│    Filebeat     │─────────────────────────────────────┘
│ (DaemonSet采集) │
└─────────────────┘
        │
        ▼
┌─────────────────┐
│  NFS Storage    │◄── 持久化存储 Elasticsearch 数据
│ (192.168.100.100)│
└─────────────────┘
ECK Operator：管理 Elasticsearch、Kibana 等资源的生命周期。

Elasticsearch：日志存储与检索，数据持久化到 NFS。

Kibana：日志可视化，通过 Ingress HTTPS 对外暴露。

Filebeat：以 DaemonSet 方式运行在每个节点，采集容器日志。

NFS：提供共享存储，确保 ES 数据高可用（生产环境建议使用更可靠的存储如 Ceph、云盘等）。

前置条件
组件	版本/要求	说明
Kubernetes 集群	1.24+	建议使用生产级集群
ECK Operator	2.11.0	本手册基于该版本
NFS 服务器	任何支持 NFS 的系统	用于 ES 持久化，IP 需集群内可达
Ingress Controller	nginx-ingress	用于暴露 Kibana
存储类	支持 ReadWriteOnce 的动态存储	本示例使用 NFS Client Provisioner
⚠️ 注意：生产环境建议使用云服务商提供的块存储（如 AWS EBS、GCE PD）或专用存储系统，避免 NFS 单点故障和性能瓶颈。

快速开始
1. 安装 ECK Operator
bash
# 安装自定义资源定义 (CRD)
kubectl create -f https://download.elastic.co/downloads/eck/2.11.0/crds.yaml

# 安装 Operator
kubectl apply -f https://download.elastic.co/downloads/eck/2.11.0/operator.yaml

# 验证安装
kubectl get pods -n elastic-system
💡 提示：Operator 默认资源请求较高，若集群资源紧张，可下载 YAML 后调整 resources 字段再应用。

2. 配置 NFS 持久化存储
2.1 准备 NFS 服务器
在 NFS 服务器（假设 IP 192.168.100.100）上执行：

bash
mkdir -p /root/data/es-storage
chmod 777 /root/data/es-storage
echo "/root/data/es-storage *(rw,sync,no_root_squash)" >> /etc/exports
exportfs -r
2.2 部署 NFS Client Provisioner
文件：nfs-rbac.yaml（RBAC 权限）

yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: nfs-client-provisioner
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: nfs-client-provisioner-runner
rules:
  - apiGroups: [""]
    resources: ["nodes"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["persistentvolumes"]
    verbs: ["get", "list", "watch", "create", "delete"]
  - apiGroups: [""]
    resources: ["persistentvolumeclaims"]
    verbs: ["get", "list", "watch", "update"]
  - apiGroups: ["storage.k8s.io"]
    resources: ["storageclasses"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["events"]
    verbs: ["create", "update", "patch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: run-nfs-client-provisioner
subjects:
  - kind: ServiceAccount
    name: nfs-client-provisioner
    namespace: kube-system
roleRef:
  kind: ClusterRole
  name: nfs-client-provisioner-runner
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: leader-locking-nfs-client-provisioner
  namespace: kube-system
rules:
  - apiGroups: [""]
    resources: ["endpoints"]
    verbs: ["get", "list", "watch", "create", "update", "patch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: leader-locking-nfs-client-provisioner
  namespace: kube-system
subjects:
  - kind: ServiceAccount
    name: nfs-client-provisioner
    namespace: kube-system
roleRef:
  kind: Role
  name: leader-locking-nfs-client-provisioner
  apiGroup: rbac.authorization.k8s.io
文件：nfs-storageclass.yaml（设为默认 StorageClass）

yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nfs-client
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: k8s-sigs.io/nfs-subdir-external-provisioner
parameters:
  archiveOnDelete: "false"
reclaimPolicy: Retain
volumeBindingMode: Immediate
文件：nfs-deployment.yaml（Provisioner 部署）

yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nfs-client-provisioner
  namespace: kube-system
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: nfs-client-provisioner
  template:
    metadata:
      labels:
        app: nfs-client-provisioner
    spec:
      serviceAccountName: nfs-client-provisioner
      containers:
        - name: nfs-client-provisioner
          image: k8s.gcr.io/sig-storage/nfs-subdir-external-provisioner:v4.0.2
          volumeMounts:
            - name: nfs-client-root
              mountPath: /persistentvolumes
          env:
            - name: PROVISIONER_NAME
              value: k8s-sigs.io/nfs-subdir-external-provisioner
            - name: NFS_SERVER
              value: 192.168.100.100        # ⚠️ 替换为你的 NFS 服务器 IP
            - name: NFS_PATH
              value: /root/data/es-storage  # ⚠️ 替换为你的共享路径
      volumes:
        - name: nfs-client-root
          nfs:
            server: 192.168.100.100         # ⚠️ 替换
            path: /root/data/es-storage     # ⚠️ 替换
应用配置：

bash
kubectl apply -f nfs-rbac.yaml
kubectl apply -f nfs-storageclass.yaml
kubectl apply -f nfs-deployment.yaml

# 验证
kubectl get sc                 # 应看到 nfs-client 且标记为 default
kubectl get pods -n kube-system | grep nfs
3. 部署 Elasticsearch
创建命名空间 log，并部署 ES 实例。

文件：elasticsearch.yaml

yaml
apiVersion: elasticsearch.k8s.elastic.co/v1
kind: Elasticsearch
metadata:
  name: quickstart
  namespace: log
spec:
  version: 8.15.0
  nodeSets:
  - name: default
    count: 1
    config:
      node.store.allow_mmap: false   # 避免 mmap 检查，适合 NFS
    podTemplate:
      spec:
        containers:
        - name: elasticsearch
          resources:
            requests:
              memory: "1Gi"
              cpu: "500m"
            limits:
              memory: "1.5Gi"         # 根据节点资源调整
              cpu: "1"
          env:
          - name: ES_JAVA_OPTS
            value: "-Xms512m -Xmx512m"  # JVM 堆大小，不超过内存 limits 的 50%
    volumeClaimTemplates:
    - metadata:
        name: elasticsearch-data
      spec:
        accessModes:
        - ReadWriteOnce
        resources:
          requests:
            storage: 5Gi                # 根据需要调整
        storageClassName: nfs-client
部署：

bash
kubectl create namespace log
kubectl apply -f elasticsearch.yaml

# 等待就绪（约 2-3 分钟）
kubectl get elasticsearch -n log
kubectl get pods -n log -w
🔐 获取 elastic 用户密码（登录 Kibana 用）：

bash
kubectl get secret -n log quickstart-es-elastic-user -o go-template='{{.data.elastic | base64decode}}'
4. 部署 Kibana 并配置 Ingress HTTPS
4.1 部署 Kibana
文件：kibana.yaml

yaml
apiVersion: kibana.k8s.elastic.co/v1
kind: Kibana
metadata:
  name: quickstart
  namespace: log
spec:
  version: 8.15.0
  count: 1
  elasticsearchRef:
    name: quickstart
  http:
    service:
      spec:
        type: ClusterIP
        ports:
        - port: 5601
          targetPort: 5601
4.2 生成 TLS 证书（测试环境）
bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout kibana.key -out kibana.crt \
  -subj "/CN=kibana.lim.com" \
  -addext "subjectAltName=DNS:kibana.lim.com"

kubectl create secret tls kibana-tls \
  --cert=kibana.crt --key=kibana.key -n log
⚠️ 生产环境：建议使用正规 CA 签发的证书，或集成 cert-manager 自动管理。

4.3 配置 Ingress
文件：ingress.yaml

yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: kibana-ingress
  namespace: log
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"   # 关键：后端使用 HTTPS
    nginx.ingress.kubernetes.io/proxy-ssl-verify: "false"   # 忽略后端证书验证
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - kibana.lim.com
    secretName: kibana-tls
  rules:
  - host: kibana.lim.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: quickstart-kb-http     # ECK 自动生成的 Service 名
            port:
              number: 5601
部署：

bash
kubectl apply -f kibana.yaml
kubectl apply -f ingress.yaml

# 验证
kubectl get ingress -n log
kubectl get pods -n log
现在可通过 https://kibana.lim.com 访问 Kibana，使用 elastic 用户和之前获取的密码登录。

5. 部署 Filebeat 采集容器日志
文件：filebeat.yaml

yaml
apiVersion: beat.k8s.elastic.co/v1beta1
kind: Beat
metadata:
  name: quickstart
  namespace: log
spec:
  type: filebeat
  version: 8.15.0
  elasticsearchRef:
    name: quickstart
  config:
    filebeat.inputs:
    - type: container
      paths:
      - /var/log/containers/*.log
      processors:
      - add_kubernetes_metadata:
          in_cluster: true
  daemonSet:
    podTemplate:
      spec:
        automountServiceAccountToken: true
        securityContext:
          runAsUser: 0                     # 以 root 运行，确保读权限
        containers:
        - name: filebeat
          resources:
            requests:
              memory: "100Mi"
              cpu: "100m"
            limits:
              memory: "200Mi"
              cpu: "200m"
          volumeMounts:
          - name: varlogcontainers
            mountPath: /var/log/containers
          - name: varlogpods
            mountPath: /var/log/pods
          - name: varlibdockercontainers
            mountPath: /var/lib/docker/containers
          - name: data
            mountPath: /usr/share/filebeat/data
        volumes:
        - name: varlogcontainers
          hostPath:
            path: /var/log/containers
        - name: varlogpods
          hostPath:
            path: /var/log/pods
        - name: varlibdockercontainers
          hostPath:
            path: /var/lib/docker/containers
        - name: data
          emptyDir: {}                      # 临时存储，避免权限问题
🔍 注意：如果你的节点使用 containerd 运行时，/var/lib/docker/containers 可能不存在。请根据实际情况调整挂载路径。通常 containerd 的日志位于 /var/log/pods，可以只挂载前两个路径。

部署：

bash
kubectl apply -f filebeat.yaml

# 验证每个节点都有 Filebeat Pod
kubectl get pods -n log -o wide | grep filebeat
验证与测试
检查所有 Pod 状态

bash
kubectl get pods -n log
期望所有 Pod 均为 Running 状态。

查看 Elasticsearch 健康状态

bash
kubectl get elasticsearch -n log
输出中 HEALTH 应为 green 或 yellow。

在 Kibana 中查看日志

访问 https://kibana.lim.com

登录后进入 "Discover" 页面，创建索引模式（如 filebeat-*），即可看到容器日志。

手动生成测试日志

bash
kubectl run test-logger --image=busybox --restart=Never -- sh -c "echo 'Hello ELK' && sleep 5"
稍后在 Kibana 中搜索 "Hello ELK" 确认日志被采集。

常见问题与排查
❌ Filebeat 不断重启
原因：/usr/share/filebeat/data 目录无写入权限。

解决：使用 emptyDir 卷挂载到该目录（已在配置中提供）。

❌ Filebeat 无法采集日志
原因：容器运行时路径不匹配。

检查：

bash
# 登录节点，查看实际日志路径
ls /var/log/containers
ls /var/log/pods
ls /var/lib/docker/containers   # 仅 docker 运行时存在
解决：根据实际路径调整 hostPath 挂载。

❌ Kibana Ingress 访问空白/无法加载
原因：Ingress 后端协议未配置为 HTTPS，或未跳过证书验证。

解决：添加注解：

yaml
nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
nginx.ingress.kubernetes.io/proxy-ssl-verify: "false"
❌ ImagePullBackOff
可能原因：集群节点镜像仓库源不一致，导致某些节点找不到镜像。

临时解决：登录问题节点手动拉取镜像：

bash
docker pull k8s.gcr.io/sig-storage/nfs-subdir-external-provisioner:v4.0.2
# 或 crictl pull ...
长期方案：统一所有节点的容器运行时配置，或使用私有镜像仓库（如 Harbor）缓存镜像。

❌ Elasticsearch 启动失败（mmap 相关）
原因：NFS 不支持 mmap。

解决：在 ES 配置中设置 node.store.allow_mmap: false。

❌ Elasticsearch 内存不足
原因：未设置 ES_JAVA_OPTS 限制堆内存。

解决：添加环境变量 -Xms512m -Xmx512m，并确保 limits 内存足够。

配置速查表
问题/需求	配置项/命令	位置
ES 堆内存限制	ES_JAVA_OPTS: "-Xms512m -Xmx512m"	elasticsearch.yaml
ES 存储类	storageClassName: nfs-client	elasticsearch.yaml
Kibana Ingress 后端协议	nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"	ingress.yaml
Kibana 服务名	quickstart-kb-http (ECK 自动生成)	ingress.yaml
Filebeat 以 root 运行	securityContext.runAsUser: 0	filebeat.yaml
Filebeat 临时存储	emptyDir: {} 挂载到 /usr/share/filebeat/data	filebeat.yaml
获取 elastic 密码	kubectl get secret -n log quickstart-es-elastic-user -o go-template='{{.data.elastic | base64decode}}'	命令行
卸载
bash
# 删除 Filebeat
kubectl delete -f filebeat.yaml

# 删除 Kibana 和 Ingress
kubectl delete -f ingress.yaml
kubectl delete -f kibana.yaml

# 删除 Elasticsearch
kubectl delete -f elasticsearch.yaml

# 删除 NFS Provisioner
kubectl delete -f nfs-deployment.yaml
kubectl delete -f nfs-storageclass.yaml
kubectl delete -f nfs-rbac.yaml

# 删除命名空间（可选）
kubectl delete namespace log

# 卸载 ECK Operator
kubectl delete -f https://download.elastic.co/downloads/eck/2.11.0/operator.yaml
kubectl delete -f https://download.elastic.co/downloads/eck/2.11.0/crds.yaml
⚠️ 删除 PVC 前请确认数据已备份，PVC 删除后 NFS 上的数据可能丢失。

贡献指南
欢迎提交 Issue 和 PR 改进本指南。在贡献前请确保：

更新内容与当前 ECK 版本兼容。

添加或修改部分需附上说明。

保持 Markdown 格式清晰。

许可证
MIT © 2025
