# Jenkins 服务配置说明

## ⚠️ 安全须知

**重要：首次启动 Jenkins 必须完成初始化设置，否则任何人都可以访问！**

## 快速开始

### 1. 启动 Jenkins

```bash
cd services/jenkins
docker compose --env-file ../../.env -f docker-compose.yml up -d
```

### 2. 获取初始管理员密码

**方法 1：从容器日志获取**
```bash
docker logs jenkins 2>&1 | grep -A 5 "Please use the following password"
```

**方法 2：直接读取密码文件**
```bash
docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```

示例输出：
```
a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6
```

### 3. 完成初始化向导

1. 访问 `https://jenkins.${DOMAIN}` (例如：https://jenkins.lzpage.help)
2. 输入上一步获取的初始管理员密码
3. 选择"安装推荐的插件"或"选择插件安装"
4. 创建管理员用户（**强烈推荐！**）
   - 用户名：建议使用复杂的用户名（避免使用 admin）
   - 密码：至少 12 位，包含大小写字母、数字和特殊字符
   - 全名：您的名字
   - 电子邮件：您的邮箱
5. 完成配置

### 4. 验证安全设置

访问 Jenkins → Manage Jenkins → Configure Global Security，确认：
- ✅ 启用安全
- ✅ 需要登录才能访问
- ✅ 授权策略：基于矩阵的授权策略

## 自动化功能

### ✅ 自动 DNS 记录创建

当 Jenkins 容器启动时，**DNS Manager** 会自动：
1. 检测到容器启动事件
2. 从标签中提取域名 `jenkins.${DOMAIN}`
3. 在 Cloudflare 创建 A 记录：`jenkins.yourdomain.com -> 服务器 IP`

**验证 DNS 创建**：
```bash
# 方式 1: 查看 DNS Manager 日志
docker logs dns-manager | grep jenkins

# 方式 2: 测试 DNS 解析
dig +short jenkins.yourdomain.com

# 方式 3: 登录 Cloudflare Dashboard 查看 DNS 记录
```

### ✅ 自动 SSL 证书申请

**Traefik** 会自动通过 Cloudflare DNS-01 验证申请 Let's Encrypt 证书：
1. 检测到 `tls.certresolver=cloudflare` 标签
2. 通过 Cloudflare API 创建 TXT 记录用于验证
3. Let's Encrypt 验证通过后颁发证书
4. 证书自动续期（有效期 90 天，提前 30 天自动续期）

**验证证书申请**：
```bash
# 方式 1: 查看 Traefik 日志
docker logs traefik | grep -i certificate | grep jenkins

# 方式 2: 访问 Traefik Dashboard
# https://traefik.yourdomain.com
# → HTTP → Routers → jenkins → 查看 TLS 状态

# 方式 3: 使用 OpenSSL 检查证书
echo | openssl s_client -servername jenkins.yourdomain.com \
  -connect yourdomain.com:443 2>/dev/null | \
  openssl x509 -noout -dates -subject

# 方式 4: 浏览器访问
# https://jenkins.yourdomain.com
# 点击地址栏锁图标查看证书详情
```

## 关键配置解析

### docker-compose.yml

```yaml
labels:
  # 1. 启用 Traefik（DNS Manager 检查此标签）
  - "traefik.enable=true"

  # 2. 域名规则（DNS Manager 从这里提取 jenkins 子域名）
  - "traefik.http.routers.jenkins.rule=Host(`jenkins.${DOMAIN}`)"
  # ↑ 自动创建: jenkins.yourdomain.com -> 服务器 IP

  # 3. HTTPS 入口点
  - "traefik.http.routers.jenkins.entrypoints=websecure"

  # 4. SSL 证书自动申请（Cloudflare DNS-01 验证）
  - "traefik.http.routers.jenkins.tls.certresolver=cloudflare"
  # ↑ 自动申请和续期 Let's Encrypt 证书

  # 5. 指定服务端口（Jenkins 运行在 8080）
  - "traefik.http.services.jenkins.loadbalancer.server.port=8080"

  # 6. Keycloak SSO 认证（可选）
  # - "traefik.http.routers.jenkins.middlewares=keycloak-auth@docker"
```

## 工作流程

```
1. 启动 Jenkins 容器
   ↓
2. DNS Manager 监听到容器启动事件
   ↓
3. 提取域名: jenkins.yourdomain.com
   ↓
4. Cloudflare API 创建 A 记录
   ↓
5. Traefik 检测到新路由
   ↓
6. Traefik 通过 Cloudflare DNS-01 验证申请证书
   ↓
7. Let's Encrypt 颁发证书
   ↓
8. 完成! https://jenkins.yourdomain.com 可访问
```

## 重置 Jenkins（如果已启动但未设置密码）

如果您之前启动了 Jenkins 但没有设置管理员账号，需要重置：

```bash
# 停止并删除容器
cd services/jenkins
docker compose --env-file ../../.env -f docker-compose.yml down

# 删除 Jenkins 数据卷（⚠️ 会删除所有 Jenkins 数据）
docker volume rm jenkins_jenkins_home

# 重新启动
docker compose --env-file ../../.env -f docker-compose.yml up -d

# 获取新的初始密码
docker logs jenkins 2>&1 | grep -A 5 "Please use the following password"
```

## 故障排查

### DNS 记录未创建

```bash
# 1. 检查 DNS Manager 状态
docker ps | grep dns-manager

# 2. 查看日志
docker logs dns-manager | grep jenkins

# 3. 手动触发同步
./scripts/sync-dns.sh

# 4. 验证容器标签
docker inspect jenkins | jq '.[0].Config.Labels' | grep traefik
```

### SSL 证书未申请

```bash
# 1. 查看 Traefik 日志
docker logs traefik | grep -i error | grep certificate

# 2. 检查 acme.json 权限
ls -la ../../data/traefik/acme.json
# 应该是: -rw------- (600)

# 3. 手动触发证书申请
docker stop traefik
rm ../../data/traefik/acme.json
touch ../../data/traefik/acme.json
chmod 600 ../../data/traefik/acme.json
docker start traefik

# 4. 查看申请日志
docker logs -f traefik | grep jenkins
```

### 服务无法访问

```bash
# 1. 检查容器状态
docker ps | grep jenkins

# 2. 查看容器日志
docker logs jenkins

# 3. 测试容器健康
docker exec jenkins curl -f http://localhost:8080/login

# 4. 检查网络
docker inspect jenkins | jq '.[0].NetworkSettings.Networks'
# 应该包含: core_frontend
```

## 相关文档

- [服务自动 SSL 和 DNS 完整指南](../../docs/service-auto-ssl-dns-guide.md)
- [DNS Manager 使用指南](../../docs/dns-manager-guide.md)
- [部署指南](../../docs/deployment-guide.md)

## 总结

您的 Jenkins 配置**已经支持**自动 DNS 和自动 SSL 证书！

- ✅ 无需修改 docker-compose.yml
- ✅ 启动后自动创建 DNS 记录
- ✅ 自动申请和续期 SSL 证书
- ✅ 支持 HTTPS 访问

只需运行 `docker-compose up -d` 即可！
