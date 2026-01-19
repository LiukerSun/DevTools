# Docker 自动安装指南

本项目提供了自动化的 Docker 安装脚本，支持主流 Linux 发行版，让你无需手动配置即可开始部署。

---

## 自动安装（推荐）

部署脚本会自动检测并安装 Docker：

```bash
# 部署时自动安装
sudo ./scripts/deploy-single.sh
```

**首次运行时：**
1. 脚本检测到 Docker 未安装
2. 询问是否自动安装
3. 自动根据系统类型选择安装方式
4. 完成后继续部署流程

---

## 手动安装 Docker

如果你想单独安装 Docker（不运行部署）：

```bash
sudo bash scripts/install-docker.sh
```

### 安装内容

脚本会自动安装：
- ✓ **Docker Engine** - 核心容器引擎
- ✓ **Docker Compose Plugin** - 容器编排工具（v2）
- ✓ **Docker Buildx Plugin** - 多平台构建工具
- ✓ **Containerd** - 容器运行时

### 自动配置

安装完成后会自动配置：

1. **日志轮转**
   - 单个日志文件最大 100MB
   - 最多保留 3 个日志文件
   - 防止日志占满磁盘

2. **镜像加速**
   - 中国科技大学镜像源
   - 腾讯云镜像源
   - 加速国内拉取速度

3. **存储驱动**
   - 使用 `overlay2` 存储驱动
   - 更高的性能和稳定性

4. **用户权限**
   - 自动将当前用户加入 `docker` 组
   - 无需 `sudo` 即可使用 Docker

---

## 支持的操作系统

| 操作系统 | 版本 | 安装方式 |
|---------|------|---------|
| Ubuntu | 18.04, 20.04, 22.04, 24.04 | 官方仓库 |
| Debian | 10, 11, 12 | 官方仓库 |
| CentOS | 7, 8 | 官方仓库 |
| Rocky Linux | 8, 9 | 官方仓库 |
| Fedora | 35+ | 官方仓库 |
| 其他 Linux | - | Docker 通用脚本 |

---

## 安装过程详解

### 1. 系统检测

```bash
检测到操作系统: ubuntu 22.04
```

脚本会自动检测操作系统类型和版本，选择最佳安装方式。

### 2. 检查现有安装

```bash
✓ Docker 已安装 (版本: 24.0.5)
✓ Docker Compose 已安装 (版本: v2.20.2)
```

如果已安装，会显示当前版本并询问是否重新安装。

### 3. 安装 Docker

根据不同系统执行相应安装命令：

**Ubuntu/Debian:**
```bash
# 添加 Docker 官方 GPG 密钥
# 添加 Docker 仓库
# 安装 Docker 和插件
apt-get install docker-ce docker-ce-cli containerd.io docker-compose-plugin
```

**CentOS/Rocky Linux:**
```bash
# 添加 Docker 仓库
# 安装 Docker 和插件
yum install docker-ce docker-ce-cli containerd.io docker-compose-plugin
```

### 4. 配置 Docker

创建 `/etc/docker/daemon.json`：

```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "registry-mirrors": [
    "https://docker.mirrors.ustc.edu.cn",
    "https://mirror.ccs.tencentyun.com"
  ]
}
```

### 5. 启动服务

```bash
systemctl enable docker
systemctl start docker
```

### 6. 验证安装

```bash
# 显示版本信息
docker --version
docker compose version

# 运行测试容器
docker run hello-world
```

---

## 安装后操作

### 非 root 用户使用 Docker

脚本会自动将当前用户加入 `docker` 组，但需要重新登录才能生效：

**方法 1: 重新登录**
```bash
exit
ssh user@server
```

**方法 2: 切换组（临时）**
```bash
newgrp docker
```

**方法 3: 继续使用 sudo（不推荐）**
```bash
sudo docker ps
```

### 验证 Docker 正常工作

```bash
# 查看 Docker 版本
docker --version

# 查看 Docker Compose 版本
docker compose version

# 运行测试容器
docker run --rm hello-world

# 查看 Docker 系统信息
docker info
```

### 查看配置

```bash
# 查看 Docker 守护进程配置
cat /etc/docker/daemon.json

# 查看 Docker 服务状态
systemctl status docker

# 查看 Docker 日志
journalctl -u docker -f
```

---

## 常见问题

### Q: 安装过程中提示权限不足？

A: 必须使用 `sudo` 或 root 用户运行安装脚本：
```bash
sudo bash scripts/install-docker.sh
```

### Q: 安装后仍然需要 sudo 才能使用 docker？

A: 需要注销并重新登录，或运行 `newgrp docker`。

### Q: 如何验证 docker 组权限生效？

A: 运行以下命令（不使用 sudo）：
```bash
docker ps
```
如果不报错则说明权限正常。

### Q: 支持离线安装吗？

A: 当前脚本需要联网下载。如需离线安装，请参考 Docker 官方离线安装文档。

### Q: 能否自定义镜像源？

A: 可以。安装后编辑 `/etc/docker/daemon.json`，修改 `registry-mirrors` 部分。

### Q: 如何卸载 Docker？

**Ubuntu/Debian:**
```bash
sudo apt-get purge docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo rm -rf /var/lib/docker
sudo rm -rf /var/lib/containerd
```

**CentOS/Rocky Linux:**
```bash
sudo yum remove docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo rm -rf /var/lib/docker
sudo rm -rf /var/lib/containerd
```

### Q: 安装失败怎么办？

1. 检查系统是否支持（见支持的操作系统列表）
2. 检查网络连接
3. 查看详细错误信息
4. 尝试手动安装：
   ```bash
   curl -fsSL https://get.docker.com | sudo bash
   ```

---

## 自定义镜像源

如果默认的国内镜像源不可用，可以修改配置：

### 1. 编辑配置文件

```bash
sudo vim /etc/docker/daemon.json
```

### 2. 修改镜像源

```json
{
  "registry-mirrors": [
    "https://docker.mirrors.ustc.edu.cn",
    "https://mirror.ccs.tencentyun.com",
    "https://dockerhub.azk8s.cn",
    "https://reg-mirror.qiniu.com"
  ]
}
```

### 3. 重启 Docker

```bash
sudo systemctl restart docker
```

### 4. 验证配置

```bash
docker info | grep -A 5 "Registry Mirrors"
```

---

## Docker Compose 使用

安装完成后，可以使用两种方式调用 Docker Compose：

### 新版本（推荐）
```bash
docker compose up -d
docker compose down
docker compose logs -f
```

### 旧版本（兼容）
```bash
docker-compose up -d
docker-compose down
docker-compose logs -f
```

本项目同时支持两种方式。

---

## 高级配置

### 配置 Docker 守护进程监听网络

**警告:** 仅在安全网络中使用！

编辑 `/etc/docker/daemon.json`:
```json
{
  "hosts": ["unix:///var/run/docker.sock", "tcp://0.0.0.0:2375"]
}
```

### 配置存储驱动

大多数系统默认使用 `overlay2`，如需更改：

```json
{
  "storage-driver": "devicemapper"
}
```

### 配置日志驱动

使用其他日志驱动（如 syslog）：

```json
{
  "log-driver": "syslog",
  "log-opts": {
    "syslog-address": "tcp://192.168.0.42:514"
  }
}
```

---

## 参考资源

- [Docker 官方文档](https://docs.docker.com/)
- [Docker Compose 文档](https://docs.docker.com/compose/)
- [Docker Hub](https://hub.docker.com/)
- [Docker 中文社区](https://www.docker.org.cn/)

---

## 下一步

安装完成后，返回部署指南：
- [快速开始](../QUICK_START.md)
- [部署指南](deployment-guide.md)
