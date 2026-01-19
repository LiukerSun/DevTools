# 服务自动 SSL 证书和 DNS 配置指南

本指南详细说明如何配置新服务，使其自动获得 SSL 证书和 DNS 记录。

## 工作原理

### 系统架构

```
新服务启动
    ↓
Docker 容器事件
    ↓
┌─────────────────┐         ┌──────────────────┐
│  DNS Manager    │         │     Traefik      │
│  监听事件       │         │   反向代理       │
└─────────────────┘         └──────────────────┘
    ↓                              ↓
提取 Traefik 标签              检测 TLS 配置
    ↓                              ↓
┌─────────────────┐         ┌──────────────────┐
│  Cloudflare API │         │ Let's Encrypt    │
│  创建 A 记录    │         │  申请证书        │
└─────────────────┘         └──────────────────┘
    ↓                              ↓
jenkins.domain.com        HTTPS 证书自动续期
-> 服务器 IP
```

### 关键组件

1. **DNS Manager**
   - 监听 Docker 容器启动事件
   - 从 `traefik.http.routers.*.rule` 标签提取域名
   - 调用 Cloudflare API 创建 A 记录

2. **Traefik**
   - 反向代理和负载均衡
   - 通过 Cloudflare DNS-01 验证申请 SSL 证书
   - 自动续期证书（Let's Encrypt 有效期 90 天）

3. **Cloudflare**
   - DNS 托管
   - 提供 API 用于自动化管理
   - DNS-01 验证支持内网服务器申请证书

## 必需的 Docker 标签

### 最小配置（自动 SSL + DNS）

```yaml
labels:
  # 1. 启用 Traefik（必需）
  - "traefik.enable=true"

  # 2. 域名规则（必需）- DNS Manager 从这里提取子域名
  - "traefik.http.routers.myapp.rule=Host(`myapp.${DOMAIN}`)"

  # 3. HTTPS 入口点（必需）
  - "traefik.http.routers.myapp.entrypoints=websecure"

  # 4. SSL 证书解析器（必需）- 自动申请证书
  - "traefik.http.routers.myapp.tls.certresolver=cloudflare"

  # 5. 服务端口（如果应用不是监听 80 端口，必须指定）
  - "traefik.http.services.myapp.loadbalancer.server.port=8080"
```

### 推荐配置（含安全增强）

```yaml
labels:
  # 基础配置
  - "traefik.enable=true"
  - "traefik.http.routers.myapp.rule=Host(`myapp.${DOMAIN}`)"
  - "traefik.http.routers.myapp.entrypoints=websecure"
  - "traefik.http.routers.myapp.tls.certresolver=cloudflare"
  - "traefik.http.services.myapp.loadbalancer.server.port=8080"

  # HTTP 到 HTTPS 重定向（推荐）
  - "traefik.http.routers.myapp-http.rule=Host(`myapp.${DOMAIN}`)"
  - "traefik.http.routers.myapp-http.entrypoints=web"
  - "traefik.http.routers.myapp-http.middlewares=https-redirect@docker"

  # 限流保护（推荐）
  - "traefik.http.middlewares.myapp-ratelimit.ratelimit.average=100"
  - "traefik.http.middlewares.myapp-ratelimit.ratelimit.burst=50"
  - "traefik.http.routers.myapp.middlewares=myapp-ratelimit"

  # 统一身份认证（可选）
  # - "traefik.http.routers.myapp.middlewares=keycloak-auth@docker"
```

## 完整示例

### Jenkins 服务

`services/jenkins/docker-compose.yml`:

```yaml
version: '3.9'

networks:
  frontend:
    external: true
    name: core_frontend

volumes:
  jenkins_home:

services:
  jenkins:
    image: jenkins/jenkins:lts
    container_name: jenkins
    restart: unless-stopped
    networks:
      - frontend
    volumes:
      - jenkins_home:/var/jenkins_home

    labels:
      # 启用 Traefik
      - "traefik.enable=true"

      # 域名配置（DNS Manager 会自动创建 jenkins.yourdomain.com）
      - "traefik.http.routers.jenkins.rule=Host(`jenkins.${DOMAIN}`)"
      - "traefik.http.routers.jenkins.entrypoints=websecure"

      # 自动 SSL 证书
      - "traefik.http.routers.jenkins.tls.certresolver=cloudflare"

      # 服务端口
      - "traefik.http.services.jenkins.loadbalancer.server.port=8080"

      # HTTP 重定向
      - "traefik.http.routers.jenkins-http.rule=Host(`jenkins.${DOMAIN}`)"
      - "traefik.http.routers.jenkins-http.entrypoints=web"
      - "traefik.http.routers.jenkins-http.middlewares=https-redirect@docker"
```

### 自定义 Web 应用

`services/myapp/docker-compose.yml`:

```yaml
version: '3.9'

networks:
  frontend:
    external: true
    name: core_frontend

services:
  myapp:
    image: myapp:latest
    container_name: myapp
    restart: unless-stopped
    networks:
      - frontend
    environment:
      - APP_ENV=production

    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.myapp.rule=Host(`myapp.${DOMAIN}`)"
      - "traefik.http.routers.myapp.entrypoints=websecure"
      - "traefik.http.routers.myapp.tls.certresolver=cloudflare"
      - "traefik.http.services.myapp.loadbalancer.server.port=3000"
```

## 部署步骤

### 1. 准备环境变量

确保 `.env` 文件配置完整：

```bash
# 基础域名
DOMAIN=yourdomain.com

# Cloudflare API（DNS Manager 和 Traefik 都需要）
CF_DNS_API_TOKEN=your-cloudflare-api-token

# 或使用 Global API Key
# CF_API_EMAIL=your-email@example.com
# CF_API_KEY=your-global-api-key
```

### 2. 启动服务

```bash
cd services/jenkins
docker-compose up -d
```

### 3. 验证 DNS 自动创建

```bash
# 方式 1: 查看 DNS Manager 日志
docker logs dns-manager | grep jenkins

# 预期输出:
# Creating DNS record: jenkins.yourdomain.com -> 1.2.3.4
# DNS record created successfully

# 方式 2: 查看 Cloudflare
# 登录 Cloudflare Dashboard → DNS Records
# 应该看到新创建的 A 记录: jenkins.yourdomain.com
```

### 4. 验证 SSL 证书申请

```bash
# 方式 1: 查看 Traefik 日志
docker logs traefik | grep jenkins

# 预期输出:
# time="..." level=info msg="Obtaining certificate for jenkins.yourdomain.com"
# time="..." level=info msg="Certificate obtained successfully"

# 方式 2: 访问 Traefik Dashboard
# https://traefik.yourdomain.com
# → HTTP → Routers → jenkins → TLS 应该显示 ✓

# 方式 3: 使用 openssl 检查证书
echo | openssl s_client -servername jenkins.yourdomain.com -connect yourdomain.com:443 2>/dev/null | openssl x509 -noout -dates

# 预期输出:
# notBefore=Jan 19 00:00:00 2025 GMT
# notAfter=Apr 19 00:00:00 2025 GMT
```

### 5. 测试访问

```bash
# 访问服务
curl -I https://jenkins.yourdomain.com

# 预期输出:
# HTTP/2 200
# ...
# strict-transport-security: max-age=31536000
```

## 常见配置场景

### 场景 1: 不同端口的服务

```yaml
# 应用运行在 3000 端口
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.myapp.rule=Host(`myapp.${DOMAIN}`)"
  - "traefik.http.routers.myapp.entrypoints=websecure"
  - "traefik.http.routers.myapp.tls.certresolver=cloudflare"
  - "traefik.http.services.myapp.loadbalancer.server.port=3000"  # 重要！
```

### 场景 2: 路径前缀路由

```yaml
# 访问 yourdomain.com/api
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.api.rule=Host(`${DOMAIN}`) && PathPrefix(`/api`)"
  - "traefik.http.routers.api.entrypoints=websecure"
  - "traefik.http.routers.api.tls.certresolver=cloudflare"

  # 去除路径前缀
  - "traefik.http.middlewares.api-stripprefix.stripprefix.prefixes=/api"
  - "traefik.http.routers.api.middlewares=api-stripprefix"
```

### 场景 3: 多域名服务

```yaml
# 同时支持 app.domain.com 和 www.domain.com
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.myapp.rule=Host(`app.${DOMAIN}`) || Host(`www.${DOMAIN}`)"
  - "traefik.http.routers.myapp.entrypoints=websecure"
  - "traefik.http.routers.myapp.tls.certresolver=cloudflare"

  # DNS Manager 只会自动创建 app.domain.com
  # www.domain.com 需要手动在 Cloudflare 创建 CNAME
```

### 场景 4: WebSocket 支持

```yaml
# 支持 WebSocket 连接
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.websocket.rule=Host(`ws.${DOMAIN}`)"
  - "traefik.http.routers.websocket.entrypoints=websecure"
  - "traefik.http.routers.websocket.tls.certresolver=cloudflare"

  # WebSocket 特定配置
  - "traefik.http.services.websocket.loadbalancer.server.port=8080"
  - "traefik.http.services.websocket.loadbalancer.sticky=true"
```

### 场景 5: 仅内网访问（跳过 DNS 自动创建）

```yaml
# 使用 IP 地址访问，不创建 DNS 记录
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.internal.rule=Host(`internal.local`)"
  - "traefik.http.routers.internal.entrypoints=web"  # 仅 HTTP
  # 不使用 tls.certresolver，DNS Manager 不会处理
```

## 高级配置

### 自定义中间件链

```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.myapp.rule=Host(`myapp.${DOMAIN}`)"
  - "traefik.http.routers.myapp.entrypoints=websecure"
  - "traefik.http.routers.myapp.tls.certresolver=cloudflare"

  # 定义多个中间件
  - "traefik.http.middlewares.myapp-ratelimit.ratelimit.average=100"
  - "traefik.http.middlewares.myapp-compress.compress=true"
  - "traefik.http.middlewares.myapp-headers.headers.customresponseheaders.X-Custom-Header=value"

  # 应用中间件链（注意顺序）
  - "traefik.http.routers.myapp.middlewares=myapp-ratelimit,myapp-compress,myapp-headers"
```

### 健康检查和负载均衡

```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.myapp.rule=Host(`myapp.${DOMAIN}`)"
  - "traefik.http.routers.myapp.entrypoints=websecure"
  - "traefik.http.routers.myapp.tls.certresolver=cloudflare"

  # 健康检查
  - "traefik.http.services.myapp.loadbalancer.healthcheck.path=/health"
  - "traefik.http.services.myapp.loadbalancer.healthcheck.interval=10s"
  - "traefik.http.services.myapp.loadbalancer.healthcheck.timeout=3s"

  # 粘性会话
  - "traefik.http.services.myapp.loadbalancer.sticky.cookie=true"
  - "traefik.http.services.myapp.loadbalancer.sticky.cookie.name=myapp_session"
```

## 故障排查

### DNS 记录未自动创建

**症状**: 容器启动后，Cloudflare 没有对应的 DNS 记录

**排查步骤**:

1. 检查 DNS Manager 是否运行
   ```bash
   docker ps | grep dns-manager
   ```

2. 查看 DNS Manager 日志
   ```bash
   docker logs dns-manager | grep -A 5 jenkins
   ```

3. 验证容器标签
   ```bash
   docker inspect jenkins | jq '.[0].Config.Labels' | grep traefik
   ```

4. 确认域名格式
   ```bash
   # 域名必须是 *.${DOMAIN} 格式
   # 正确: jenkins.yourdomain.com
   # 错误: jenkins.otherdomain.com
   ```

5. 手动触发同步
   ```bash
   ./scripts/sync-dns.sh
   ```

### SSL 证书申请失败

**症状**: 访问时显示证书错误或使用自签名证书

**排查步骤**:

1. 查看 Traefik 日志
   ```bash
   docker logs traefik | grep -i error | grep -i certificate
   ```

2. 常见错误和解决方案:

   | 错误信息 | 原因 | 解决方案 |
   |---------|------|---------|
   | `DNS problem` | DNS 记录不存在 | 等待 DNS 传播或手动创建记录 |
   | `Invalid credentials` | Cloudflare API 无效 | 检查 `.env` 中的 CF_DNS_API_TOKEN |
   | `Rate limit exceeded` | 请求过于频繁 | 等待 1 小时后重试 |
   | `CAA record forbids` | CAA 记录阻止 | 删除或修改 Cloudflare CAA 记录 |

3. 检查 acme.json 权限
   ```bash
   ls -la data/traefik/acme.json
   # 应该是: -rw------- (600)

   # 如果权限不对，修复:
   chmod 600 data/traefik/acme.json
   docker restart traefik
   ```

4. 手动触发证书申请
   ```bash
   # 删除 acme.json 强制重新申请
   docker stop traefik
   rm data/traefik/acme.json
   touch data/traefik/acme.json
   chmod 600 data/traefik/acme.json
   docker start traefik

   # 查看日志
   docker logs -f traefik | grep certificate
   ```

### 服务无法访问

**症状**: DNS 和证书都正常，但无法访问服务

**排查步骤**:

1. 检查容器是否运行
   ```bash
   docker ps | grep jenkins
   ```

2. 检查网络连接
   ```bash
   # 容器必须连接到 core_frontend 网络
   docker inspect jenkins | jq '.[0].NetworkSettings.Networks'
   ```

3. 测试容器健康检查
   ```bash
   docker exec jenkins curl -f http://localhost:8080/login
   ```

4. 查看 Traefik 路由状态
   ```bash
   # 访问 Traefik Dashboard
   https://traefik.yourdomain.com
   # → HTTP → Routers → 查找 jenkins
   ```

5. 检查防火墙
   ```bash
   # 确保 80 和 443 端口开放
   sudo ufw status | grep -E "(80|443)"
   ```

## 最佳实践

### 1. 命名规范

- **容器名**: 使用小写字母和连字符，如 `my-app`
- **路由器名**: 与容器名一致，如 `traefik.http.routers.my-app.rule`
- **子域名**: 简洁明了，如 `app.domain.com`

### 2. 安全增强

```yaml
labels:
  # 强制 HTTPS
  - "traefik.http.routers.myapp-http.middlewares=https-redirect@docker"

  # HSTS 头（已在 Traefik 全局配置）
  - "traefik.http.middlewares.myapp-security.headers.stsSeconds=31536000"
  - "traefik.http.middlewares.myapp-security.headers.stsIncludeSubdomains=true"

  # 限流
  - "traefik.http.middlewares.myapp-ratelimit.ratelimit.average=100"
```

### 3. 监控和日志

```yaml
# 启用访问日志
labels:
  - "traefik.http.routers.myapp.accesslog=true"

# 在 docker-compose.yml 中添加日志配置
logging:
  driver: "json-file"
  options:
    max-size: "10m"
    max-file: "3"
```

### 4. 资源限制

```yaml
deploy:
  resources:
    limits:
      cpus: '1.0'
      memory: 1G
    reservations:
      cpus: '0.5'
      memory: 512M
```

## 快速参考

### 必需的环境变量

```bash
DOMAIN=yourdomain.com
CF_DNS_API_TOKEN=your-token
```

### 必需的 Traefik 标签

```yaml
- "traefik.enable=true"
- "traefik.http.routers.NAME.rule=Host(`NAME.${DOMAIN}`)"
- "traefik.http.routers.NAME.entrypoints=websecure"
- "traefik.http.routers.NAME.tls.certresolver=cloudflare"
- "traefik.http.services.NAME.loadbalancer.server.port=PORT"
```

### 验证命令

```bash
# DNS 记录
dig +short jenkins.yourdomain.com

# SSL 证书
curl -vI https://jenkins.yourdomain.com 2>&1 | grep "subject:"

# 服务状态
docker logs dns-manager | tail -20
docker logs traefik | tail -20
```

## 相关文档

- [DNS Manager 详细指南](dns-manager-guide.md)
- [Traefik 官方文档](https://doc.traefik.io/traefik/)
- [Cloudflare API 文档](https://developers.cloudflare.com/api/)
- [Let's Encrypt 文档](https://letsencrypt.org/docs/)
