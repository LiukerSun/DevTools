# 网关 - 部署指南

本文档提供完整的分步部署指南,帮助你在云服务器上从零开始部署整个网关系统。

---

## 前置准备

### 1. 云服务器要求

- **操作系统**: Ubuntu 20.04+ / CentOS 8+ / Debian 11+
- **配置推荐**: 4 核 CPU, 8GB 内存, 100GB SSD
- **网络**: 公网 IP,开放 80 和 443 端口
- **权限**: Root 或具有 sudo 权限的用户

### 2. 域名和 Cloudflare

- 已注册域名
- 域名 DNS 托管在 Cloudflare
- 获取 Cloudflare API Token 或 Global API Key

### 3. 可选服务

- 阿里云短信账号 (用于短信告警)
- 钉钉或企业微信群机器人 (用于消息通知)
- SMTP 邮箱账号 (用于邮件告警)

---

## 第一步:准备 Cloudflare API 凭证

### 1.1 登录 Cloudflare

访问 [Cloudflare Dashboard](https://dash.cloudflare.com/)

### 1.2 获取 API 凭证

**方式 A: API Token (推荐)**

1. 进入 "My Profile" → "API Tokens"
2. 点击 "Create Token"
3. 选择 "Edit zone DNS" 模板
4. 配置权限:
   - Zone - DNS - Edit
   - Zone - Zone - Read
5. 选择你的域名
6. 创建并保存 Token

**方式 B: Global API Key**

1. 进入 "My Profile" → "API Keys"
2. 查看 "Global API Key"
3. 点击 "View" 并保存

### 1.3 配置域名 A 记录

在 Cloudflare DNS 中添加 A 记录,指向你的云服务器公网 IP:

```
类型: A
名称: @ (或你的主域名)
内容: 你的服务器公网 IP
代理状态: 仅 DNS (关闭橙色云朵)
```

---

## 第二步:连接到云服务器

### 2.1 SSH 连接

```bash
ssh root@你的服务器IP
```

### 2.2 更新系统

```bash
# Ubuntu/Debian
apt update && apt upgrade -y

# CentOS/RHEL
yum update -y
```

### 2.3 安装基础工具

```bash
# Ubuntu/Debian
apt install -y git curl wget vim

# CentOS/RHEL
yum install -y git curl wget vim
```

---

## 第三步:下载项目

### 3.1 克隆项目到服务器

如果你已经有 Git 仓库:

```bash
git clone git@github.com:LiukerSun/DevTools.git
cd DevTools
```

### 3.2 验证文件完整性

```bash
ls -la
# 应该看到: core/ monitoring/ services/ scripts/ docs/ 等目录
```

---

## 第四步:配置环境变量

### 4.1 复制环境变量模板

```bash
cp .env.example .env
```

### 4.2 编辑 .env 文件

```bash
vim .env
```

### 4.3 填写必要配置

```bash
# ===== 基础配置 =====
DOMAIN=yourdomain.com                    # 替换为你的域名
EMAIL=admin@yourdomain.com               # 用于 Let's Encrypt 通知

# ===== Cloudflare =====
CF_API_EMAIL=your-email@example.com      # Cloudflare 账号邮箱
CF_API_KEY=your-api-key-here             # Cloudflare Global API Key 或 Token

# ===== PostgreSQL =====
POSTGRES_USER=keycloak
POSTGRES_PASSWORD=生成一个强密码          # 使用 openssl rand -base64 32 生成
POSTGRES_DB=keycloak

# ===== Keycloak =====
KEYCLOAK_ADMIN=admin
KEYCLOAK_ADMIN_PASSWORD=生成一个强密码    # 使用 openssl rand -base64 32 生成

# ===== Grafana =====
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=生成一个强密码

# ===== SMTP 邮件配置 =====
SMTP_HOST=smtp.qq.com                    # QQ 邮箱示例,根据实际修改
SMTP_PORT=587
SMTP_USER=your-email@qq.com
SMTP_PASSWORD=your-smtp-authorization-code  # QQ 邮箱需要使用授权码
ALERT_EMAIL=receiver@example.com         # 接收告警的邮箱

# ===== 钉钉 Webhook (可选) =====
DINGTALK_WEBHOOK=https://oapi.dingtalk.com/robot/send?access_token=xxx

# ===== 企业微信 Webhook (可选) =====
WECHAT_WEBHOOK=https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=xxx

# ===== 阿里云短信 (可选) =====
ALIYUN_ACCESS_KEY=your-access-key
ALIYUN_ACCESS_SECRET=your-access-secret
ALIYUN_SMS_SIGN=your-sms-signature       # 短信签名
ALIYUN_SMS_TEMPLATE=SMS_123456789        # 短信模板 ID
ALERT_PHONE=13800138000                  # 接收告警的手机号
```

### 4.4 保存并退出

按 `ESC` 然后输入 `:wq` 保存退出。

---

## 第五步:一键部署

### 5.1 运行部署脚本

```bash
chmod +x scripts/deploy.sh
./scripts/deploy.sh
```

### 5.2 脚本将自动执行以下操作

1. 检查并安装 Docker 和 Docker Compose
2. 验证环境变量配置
3. 创建数据目录
4. 配置防火墙规则
5. 启动核心服务 (Traefik, PostgreSQL, Keycloak, Redis)
6. 等待服务健康检查
7. 启动监控服务 (Prometheus, Grafana, Loki, AlertManager)

### 5.3 预计耗时

- 首次部署: 5-10 分钟 (取决于网络速度)
- 镜像下载: 约 2-3 GB

---

## 第六步:验证部署

### 6.1 检查服务状态

```bash
./scripts/health-check.sh
```

应该看到所有服务显示为 "运行中 (健康)"。

### 6.2 访问服务

在浏览器中访问以下地址:

- **Traefik Dashboard**: https://traefik.yourdomain.com
- **Keycloak**: https://auth.yourdomain.com
- **Grafana**: https://grafana.yourdomain.com
- **Prometheus**: https://prometheus.yourdomain.com

### 6.3 验证 SSL 证书

- 浏览器地址栏应显示 🔒 锁图标
- 点击查看证书,应该是 Let's Encrypt 签发的有效证书

---

## 第七步:配置 Keycloak

### 7.1 登录 Keycloak Admin

1. 访问 https://auth.yourdomain.com
2. 点击 "Administration Console"
3. 使用 .env 中配置的 KEYCLOAK_ADMIN 和 KEYCLOAK_ADMIN_PASSWORD 登录

### 7.2 创建 Realm

1. 点击左上角的 "master" 下拉菜单
2. 点击 "Create Realm"
3. 名称: gateway (或自定义)
4. 启用 "Enabled"
5. 点击 "Create"

### 7.3 创建用户

1. 在左侧菜单选择 "Users"
2. 点击 "Add user"
3. 填写用户名和邮箱
4. 点击 "Create"
5. 切换到 "Credentials" 标签
6. 设置密码,取消勾选 "Temporary"
7. 点击 "Set password"

### 7.4 配置客户端 (可选)

如果需要为特定服务配置 OAuth2/OIDC 客户端,参考 Keycloak 文档。

---

## 第八步:配置 Grafana

### 8.1 登录 Grafana

1. 访问 https://grafana.yourdomain.com
2. 使用 .env 中配置的 GRAFANA_ADMIN_USER 和 GRAFANA_ADMIN_PASSWORD 登录

### 8.2 验证数据源

1. 左侧菜单: Configuration → Data Sources
2. 应该看到 Prometheus 和 Loki 已自动配置
3. 点击 "Test" 验证连接

### 8.3 导入仪表板

1. 左侧菜单: Dashboards → Import
2. 推荐导入以下官方仪表板:
   - **Traefik**: Dashboard ID 17346
   - **Node Exporter**: Dashboard ID 1860
   - **Docker**: Dashboard ID 15798
   - **PostgreSQL**: Dashboard ID 9628

---

## 第九步:测试告警

### 9.1 触发测试告警

```bash
# 模拟高 CPU 使用率
stress --cpu 8 --timeout 300s

# 或者停止一个服务触发告警
docker stop keycloak
```

### 9.2 检查告警通知

- 查看 AlertManager: https://alerts.yourdomain.com
- 检查邮箱是否收到告警邮件
- 检查钉钉/企业微信群是否收到消息
- 检查手机是否收到短信 (Critical 级别)

### 9.3 恢复服务

```bash
docker start keycloak
```

---

## 第十步:部署业务服务

### 10.1 部署 Jenkins

```bash
cd services/jenkins
docker-compose up -d
cd ../..
```

访问 https://jenkins.yourdomain.com 验证。

### 10.2 部署示例应用

```bash
cd services/example-app
docker-compose up -d
cd ../..
```

访问 https://example.yourdomain.com 验证。

### 10.3 添加自定义服务

参考 `services/example-app/docker-compose.yml` 模板,创建你自己的服务。

---

## 日常管理

### 启动所有服务

```bash
./scripts/start-all.sh
```

### 停止所有服务

```bash
./scripts/stop-all.sh
```

### 健康检查

```bash
./scripts/health-check.sh
```

### 数据备份

```bash
./scripts/backup.sh
```

建议设置 cron 定时任务:

```bash
# 每天凌晨 2 点备份
crontab -e
0 2 * * * /opt/DevTools/scripts/backup.sh >> /var/log/gateway-backup.log 2>&1
```

### 查看日志

```bash
# 查看所有服务日志
cd core && docker-compose logs -f

# 查看特定服务日志
docker logs -f traefik
docker logs -f keycloak
```

---

## 常见问题

详见 `docs/troubleshooting.md`

---

## 下一步

1. 配置更多监控仪表板
2. 定制告警规则
3. 部署更多业务服务
4. 定期备份并测试恢复流程
5. 查看性能优化建议

---

**部署完成!** 🎉
