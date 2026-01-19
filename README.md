# 网关 (Gateway)

> 基于 Docker + Traefik + Cloudflare DNS 验证的网关系统

这是一个基于 Docker + Traefik + Cloudflare DNS 验证的生产级网关解决方案,集成了反向代理、SSL 自动化、统一认证、完整监控和多渠道告警,让你可以轻松管理多个服务而无需担心端口冲突和证书问题。

---

## 核心特性

- 🔐 **自动 SSL 证书管理** - Cloudflare DNS 验证,Let's Encrypt 证书自动申请和续期
- 🌐 **自动 DNS 记录管理** - 新服务启动时自动创建 A 记录,无需手动配置 Cloudflare
- 🔑 **统一身份认证** - Keycloak 企业级 SSO,支持 OAuth2/OIDC 和双因素认证
- 📊 **完整可观测性** - Prometheus + Grafana + Loki + AlertManager 全栈监控
- 📧 **多渠道告警** - 邮件、短信、钉钉、企业微信,根据严重程度智能通知
- 🔌 **即插即用** - 新服务通过 Docker 标签自动注册,无需手动配置
- 🛡️ **安全加固** - 网络隔离、限流保护、自动化备份
- ⚡ **资源优化** - 单机部署,资源占用低,运维简单

---

## 快速开始

### 前置要求

- 云服务器 (最低配置: 2核4G, 推荐配置: 4核8G)
- 域名并托管在 Cloudflare
- Docker 和 Docker Compose (部署时自动安装)

### 5 分钟快速部署

```bash
# 1. 克隆或上传项目到服务器
git clone https://github.com/LiukerSun/DevTools.git
cd DevTools

# 2. 配置环境变量
cp .env.example .env
vim .env  # 填写域名、Cloudflare API、数据库密码等

# 3. 一键部署
# 脚本会自动检测并安装 Docker (如未安装)
chmod +x scripts/deploy-single.sh
sudo ./scripts/deploy-single.sh

# 4. 访问服务
# Traefik:    https://traefik.yourdomain.com  (admin/admin)
# Keycloak:   https://auth.yourdomain.com
# Grafana:    https://grafana.yourdomain.com
```

**注意:**
- 首次部署会自动检测并安装 Docker
- 支持 Ubuntu, Debian, CentOS, Rocky Linux, Fedora
- 如需手动安装: `sudo bash scripts/install-docker.sh`

**详细部署说明:** 查看 [docs/deployment-guide.md](docs/deployment-guide.md)

---

## 架构概览

```
                      互联网
                        |
              [云服务器 - 公网 IP]
                        |
                   [Traefik]
                  (反向代理)
                        |
      +---------+-------+-------+---------+
      |         |       |       |         |
 [Keycloak] [Jenkins] [Blog] [Grafana] [其他]
   (SSO)                      (监控)
      |
 [PostgreSQL]   [Redis]
   (数据库)     (缓存)
      |
 [Prometheus] [Loki] [AlertManager]
  (指标采集)  (日志)   (告警)
```

---

## 项目结构

```
gateway/
├── core/                 # 核心服务 (Traefik, Keycloak, PostgreSQL, Redis)
├── monitoring/           # 监控栈 (Prometheus, Grafana, Loki, AlertManager)
├── services/             # 业务服务 (Jenkins, 博客, 应用等)
├── scripts/              # 运维脚本 (部署, 备份, 健康检查)
├── docs/                 # 文档
└── data/                 # 数据持久化
```

---

## 添加新服务

只需 3 步,新服务即可自动获得 HTTPS、SSO 认证和监控:

```yaml
# services/myapp/docker-compose.yml
version: '3.9'

networks:
  frontend:
    external: true
    name: core_frontend

services:
  myapp:
    image: myapp:latest
    networks:
      - frontend
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.myapp.rule=Host(`myapp.${DOMAIN}`)"
      - "traefik.http.routers.myapp.entrypoints=websecure"
      - "traefik.http.routers.myapp.tls.certresolver=cloudflare"
      - "traefik.http.routers.myapp.middlewares=keycloak-auth@docker"  # 可选:SSO 保护
```

```bash
cd services/myapp
docker-compose up -d
```

访问 `https://myapp.yourdomain.com` - 完成!

---

## 管理命令

```bash
# 启动所有服务
./scripts/start-all.sh

# 停止所有服务
./scripts/stop-all.sh

# 健康检查
./scripts/health-check.sh

# 数据备份
./scripts/backup.sh

# 查看日志
cd core && docker-compose logs -f
```

---

## 监控和告警

### 告警分级

| 级别 | 触发条件 | 通知渠道 |
|------|----------|----------|
| **Critical** | 核心服务宕机、磁盘 < 10% | 短信 + 邮件 + 钉钉/企业微信 |
| **Warning** | CPU > 80%、非核心服务故障 | 邮件 + 钉钉/企业微信 |
| **Info** | 服务重启成功、备份完成 | 仅钉钉/企业微信 |

### 预置仪表板

- **系统概览** - 所有服务健康状态、资源使用
- **Traefik** - 流量、错误率、响应时间、SSL 证书状态
- **Keycloak** - 登录趋势、活跃用户、会话数
- **PostgreSQL** - 查询性能、连接池、复制延迟
- **容器监控** - 每个容器的 CPU、内存、网络 I/O

---

## 技术栈

| 组件 | 技术 | 版本 |
|------|------|------|
| 反向代理 | Traefik | 3.0+ |
| 身份认证 | Keycloak | 24.0+ |
| 数据库 | PostgreSQL | 16+ |
| 缓存 | Redis | 7.2+ |
| 监控 | Prometheus | 2.50+ |
| 可视化 | Grafana | 10.0+ |
| 日志 | Loki + Promtail | 3.0+ |
| 告警 | AlertManager | 0.27+ |

---

## 文档

- [部署指南](docs/deployment-guide.md) - 完整的分步部署教程
- [故障排查](docs/troubleshooting.md) - 常见问题和解决方案
- [Docker安装说明](docs/docker-installation.md) - Docker自动安装指南

---

## 常见问题

### Q: 支持哪些云服务商?

A: 所有提供公网 IP 的云服务器都支持,包括阿里云、腾讯云、AWS、GCP、Azure 等。

### Q: 必须使用 Cloudflare 吗?

A: 是的,当前版本使用 Cloudflare DNS-01 验证。如需其他 DNS 提供商,可修改 Traefik 配置。

### Q: 支持多域名吗?

A: 支持。在 .env 中配置主域名,其他域名通过 Traefik 标签单独指定。

### Q: 如何迁移到新服务器?

A: 1) 运行 `./scripts/backup.sh` 备份数据 2) 在新服务器部署 3) 恢复备份数据。

### Q: 可以只部署部分组件吗?

A: 可以。核心服务必须部署,监控和业务服务可选。

更多问题: [docs/troubleshooting.md](docs/troubleshooting.md)

---

## 路线图

- [x] 核心网关功能
- [x] 完整监控和告警
- [ ] Kubernetes 支持
- [ ] Web 管理界面
- [ ] 自动扩缩容
- [ ] 多区域部署

---

## 贡献

欢迎提交 Issue 和 Pull Request!

---

## 许可证

MIT License

---

## 支持

- 问题反馈: [GitHub Issues](https://github.com/LiukerSun/DevTools/issues)
- 文档: [docs/](docs/)
- 邮件: liukersun@gmail.com

---

**开始构建你的网关吧!** 🚀
