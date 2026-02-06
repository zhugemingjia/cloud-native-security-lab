## 一些踩过的坑 #####
镜像源一定要配置对。血泪教训，笔者在此由于国内拉取不到国外镜像+镜像源配置出问题，浪费了大量时间。期间做过很多尝试，比如将GitHub上的DVWA文件下载下来，使用Dockerfile打包为本地镜像，然后再建立本地仓库，以本地仓库提供镜像服务，虽然有效但是极其繁琐。（因祸得福，也算是将Dockerfile打制作镜像和建立本地镜像仓库算是小有理解）
这里提醒和给出一些小小的提示，帮助和笔者一样的小白少走一些弯路。
1.首先是K8S的配置：https://mp.weixin.qq.com/s/lVYCmnSkYDpsucbbaB4fmQ。这个是笔者之前找了很多资料，浪费了很多时间去安装K8S。这个文档个人觉得比较简洁而且有效，推荐给大家。
2.containerd的镜像源配置：在containerd V2.x以上的版本，使用独立的host.toml文件配置镜像源。首先，需要在 /etc/containerd/config.toml 中配置 config_path，指定 hosts.toml 配置文件的目录路径。
重要提示：对于 docker.io，server 字段必须使用 https://registry-1.docker.io，不能使用 https://docker.io。因为 docker.io 是命名空间，而 registry-1.docker.io 才是实际的 registry 地址。
containerd 会严格校验，docker.io 下没有 /v2/ API，这可能导致配置失败。
##如：
server = "https://registry-1.docker.io"
[host."https://xxx.xxx.run"]
  capabilities = ["pull", "resolve"]
  skip_verify = false
