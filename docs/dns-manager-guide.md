# DNS Manager 使用指南

## 概述

DNS Manager 是一个自动化 DNS 记录管理服务，当你添加新的 Docker 服务时，它会自动在 Cloudflare 上创建对应的 A 记录，让你无需手动配置 DNS。

## 工作原理

1. **监听容器事件** - DNS Manager 实时监听 Docker 容器启动事件
2. **提取域名信息** - 从 Traefik 标签中提取子域名 (`traefik.http.routers.*.rule`)
3. **检查记录存在性** - 调用 Cloudflare API 检查 DNS A 记录是否已存在
4. **自动创建记录** - 如果不存在，自动创建指向服务器 IPv4 地址的 A 记录
5. **跳过已有记录** - 如果记录已存在，跳过创建避免冲突

## 功能特性

- ✅ **自动检测服务器 IPv4** - 通过多个公网服务自动检测服务器公网 IP
- ✅ **容器启动时自动创建** - 新容器启动时立即创建 DNS 记录
- ✅ **部署时全量同步** - 部署时扫描所有现有容器并同步 DNS
- ✅ **手动触发同步** - 支持通过信号或 API 手动触发全量同步
- ✅ **指数退避重试** - API 失败时自动重试，避免速率限制
- ✅ **健康检查** - 提供 HTTP 端点检查服务状态和统计信息
- ✅ **Prometheus 指标** - 暴露指标供 Prometheus 采集和告警

## 配置要求

### 环境变量

DNS Manager 需要以下环境变量（已在 `core/docker-compose.single.yml` 中配置）:

```bash
# 必需配置
DOMAIN=yourdomain.com               # 基础域名
CF_DNS_API_TOKEN=your-token         # Cloudflare API Token (推荐)

# 或使用 Global API Key (不推荐)
CF_API_EMAIL=your-email@example.com
CF_API_KEY=your-global-api-key

# 可选配置
DNS_LOG_LEVEL=INFO                  # 日志级别 (DEBUG, INFO, WARNING, ERROR)
```

### Cloudflare API Token 权限

如果使用 API Token（推荐），需要以下权限:

1. 登录 Cloudflare Dashboard
2. 进入 "My Profile" → "API Tokens" → "Create Token"
3. 选择 "Edit zone DNS" 模板
4. 设置权限:
   - **Zone - DNS - Edit**
   - **Zone - Zone - Read**
5. 设置区域资源:
   - **Include - Specific zone - yourdomain.com**
6. 创建并复制 Token 到 `.env` 文件

## 使用方法

### 添加新服务

使用辅助脚本快速创建服务配置:

```bash
# 语法: ./scripts/add-service.sh <service-name> <subdomain>
./scripts/add-service.sh myapp myapp
```

脚本会自动生成 `services/myapp/docker-compose.yml`:

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
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.myapp.rule=Host(`myapp.${DOMAIN}`)"
      - "traefik.http.routers.myapp.entrypoints=websecure"
      - "traefik.http.routers.myapp.tls.certresolver=cloudflare"
```

**关键**: `traefik.http.routers.*.rule` 标签中的域名必须以 `.${DOMAIN}` 结尾

### 启动服务

```bash
cd services/myapp
docker-compose up -d
```

DNS Manager 会自动:
1. 检测到容器启动事件
2. 提取子域名 `myapp`
3. 在 Cloudflare 创建 A 记录: `myapp.yourdomain.com -> 服务器IP`

### 手动触发同步

如果需要手动同步所有容器的 DNS 记录:

```bash
# 方式 1: 使用同步脚本 (推荐)
./scripts/sync-dns.sh

# 方式 2: 发送 SIGUSR1 信号
docker kill --signal=SIGUSR1 dns-manager

# 方式 3: 调用 HTTP API
curl -X POST http://localhost:8000/sync
```

### 查看状态

```bash
# 健康检查
curl http://localhost:8000/health | jq

# 输出示例:
{
  "status": "healthy",
  "uptime": 3600,
  "stats": {
    "containers_monitored": 5,
    "dns_records_created": 3,
    "api_errors": 0
  }
}

# 查看日志
docker logs dns-manager

# 实时日志
docker logs -f dns-manager | grep "Creating DNS"
```

## 监控和告警

DNS Manager 暴露 Prometheus 指标到 `/metrics` 端点:

### 关键指标

| 指标名 | 类型 | 说明 |
|--------|------|------|
| `dns_records_created_total` | Counter | 累计创建的 DNS 记录数 |
| `dns_api_errors_total` | Counter | 累计 API 错误数 |
| `dns_containers_monitored` | Gauge | 当前监控的容器数量 |
| `up{job="dns-manager"}` | Gauge | 服务健康状态 (1=正常, 0=宕机) |

### 告警规则

已配置的告警 (在 `monitoring/prometheus/rules/dns.yml`):

- **DNSManagerDown** - 服务宕机超过 5 分钟
- **DNSAPIErrorsHigh** - API 错误率超过 0.1/s (10 分钟)
- **NoRecordsCreated** - 2 小时内有容器但未创建记录
- **DNSManagerMemoryHigh** - 内存使用率超过 80% (15 分钟)
- **DNSManagerRestarting** - 频繁重启 (5 分钟)

在 Grafana 中查看:

```bash
# 访问 Grafana
https://grafana.yourdomain.com

# 导入 DNS Manager 仪表板 (如果提供)
# Dashboard ID: TBD
```

## 故障排查

### DNS 记录未自动创建

1. **检查服务状态**
   ```bash
   docker ps | grep dns-manager
   docker logs dns-manager
   ```

2. **检查 Traefik 标签**
   ```bash
   docker inspect myapp | jq '.[0].Config.Labels'
   ```

   确保包含: `traefik.http.routers.*.rule=Host(\`myapp.yourdomain.com\`)`

3. **检查域名匹配**

   DNS Manager 只处理以 `.${DOMAIN}` 结尾的域名，确保:
   - `.env` 中 `DOMAIN=yourdomain.com`
   - 容器标签中域名为 `*.yourdomain.com`

4. **手动触发同步**
   ```bash
   ./scripts/sync-dns.sh
   docker logs dns-manager | grep "myapp"
   ```

### Cloudflare API 错误

常见错误和解决方案:

| 错误信息 | 原因 | 解决方案 |
|----------|------|----------|
| `Invalid request headers` | API Token 无效 | 重新创建 Token 并更新 `.env` |
| `Zone not found` | 域名未添加到 Cloudflare | 确保域名已添加到你的 Cloudflare 账户 |
| `Insufficient permissions` | Token 权限不足 | 添加 Zone-DNS-Edit 和 Zone-Zone-Read 权限 |
| `Rate limit exceeded` | 请求过于频繁 | 等待 1 分钟后重试（已内置指数退避） |

查看 API 错误日志:

```bash
docker logs dns-manager | grep "ERROR"
```

### 服务频繁重启

1. **查看重启原因**
   ```bash
   docker events --filter 'container=dns-manager' --since 1h
   ```

2. **检查内存使用**
   ```bash
   docker stats dns-manager --no-stream
   ```

3. **查看健康检查失败**
   ```bash
   curl http://localhost:8000/health
   ```

### DNS 记录重复创建

DNS Manager 在创建前会检查记录是否存在，不会重复创建。如果发现重复:

1. **检查 Cloudflare**

   登录 Cloudflare Dashboard 确认是否真的重复

2. **查看日志**
   ```bash
   docker logs dns-manager | grep "already exists"
   ```

3. **手动清理重复记录**

   登录 Cloudflare Dashboard 手动删除重复的 A 记录

## 限制和注意事项

1. **仅支持 A 记录** - 当前版本只创建 IPv4 A 记录，不支持 AAAA (IPv6) 或其他类型
2. **不自动删除** - 容器停止或删除时，DNS 记录不会自动删除（避免误删）
3. **泛域名过滤** - 自动跳过泛域名规则（`*.yourdomain.com`）
4. **跳过已有记录** - 如果 DNS 记录已存在，不会更新 IP 地址
5. **需要 Docker socket** - 必须挂载 `/var/run/docker.sock` 才能监听容器事件

## 高级用法

### 自定义日志级别

```bash
# 在 .env 中设置
DNS_LOG_LEVEL=DEBUG

# 重启服务
cd core
docker-compose -f docker-compose.single.yml restart dns-manager
```

### 查看 Prometheus 指标

```bash
curl http://localhost:8000/metrics

# 过滤 DNS 相关指标
curl -s http://localhost:8000/metrics | grep dns_
```

### 集成测试

```bash
# 运行单元测试
cd core/dns-manager
python -m pytest tests/ -v

# 运行集成测试（需要运行中的服务）
./scripts/test-dns-integration.sh
```

## 性能优化

DNS Manager 已针对单机部署优化:

- **资源限制**: 128MB 内存, 0.1 CPU
- **轻量级镜像**: 基于 `python:3.11-alpine`
- **高效监听**: 仅监听 `start` 事件, 过滤 `traefik.enable=true`
- **最小依赖**: 仅 5 个 Python 包
- **非阻塞健康检查**: Flask 运行在后台线程

实测性能:
- **内存占用**: 约 40-60MB
- **CPU 占用**: 空闲 <0.1%, 创建记录时约 1-2%
- **启动时间**: 约 3-5 秒

## 安全建议

1. **使用 API Token** - 避免使用 Global API Key，权限过大
2. **只读 Docker socket** - 已配置 `:ro`，DNS Manager 无法操作容器
3. **资源限制** - 已配置内存和 CPU 限制，防止资源耗尽
4. **日志脱敏** - 生产环境避免使用 `DEBUG` 级别，可能泄露敏感信息
5. **网络隔离** - DNS Manager 只需访问 frontend 网络，无需访问 backend

## 更新和维护

### 更新 DNS Manager

```bash
cd core
docker-compose -f docker-compose.single.yml pull dns-manager
docker-compose -f docker-compose.single.yml up -d dns-manager
```

### 备份配置

DNS Manager 无状态，配置全部来自环境变量:

```bash
# 备份 .env 文件
cp .env .env.backup.$(date +%Y%m%d)
```

### 卸载 DNS Manager

```bash
cd core
docker-compose -f docker-compose.single.yml stop dns-manager
docker-compose -f docker-compose.single.yml rm -f dns-manager
```

**注意**: 卸载后已创建的 DNS 记录不会被删除，需要手动清理 Cloudflare

## 常见问题 (FAQ)

**Q: DNS Manager 会自动删除停止的容器对应的 DNS 记录吗？**

A: 不会。为了安全起见，DNS Manager 只创建记录，不删除记录。如需删除，请手动登录 Cloudflare 操作。

**Q: 可以同时管理多个域名吗？**

A: 当前版本只支持单个域名（环境变量 `DOMAIN`）。如需管理多个域名，请部署多个 DNS Manager 实例。

**Q: 支持 IPv6 吗？**

A: 当前版本只支持 IPv4 A 记录。IPv6 (AAAA 记录) 支持计划在未来版本中添加。

**Q: DNS 记录创建需要多长时间？**

A: 通常 2-5 秒完成 Cloudflare API 调用。DNS 传播时间取决于 TTL 设置，一般 1-5 分钟。

**Q: 可以自定义 TTL 吗？**

A: 当前版本使用 Cloudflare 默认 TTL (Auto)。自定义 TTL 功能计划在未来版本中添加。

**Q: 如何处理 API 速率限制？**

A: DNS Manager 已内置指数退避重试机制。Cloudflare 免费账户限制为 1200 请求/5分钟，正常使用不会触发。

## 相关文档

- [部署指南](deployment-guide.md)
- [Cloudflare API 文档](https://developers.cloudflare.com/api/)
- [Traefik 标签参考](https://doc.traefik.io/traefik/routing/providers/docker/)
- [Prometheus 指标格式](https://prometheus.io/docs/concepts/metric_types/)

## 支持和反馈

如果遇到问题或有改进建议:

1. 查看日志: `docker logs dns-manager`
2. 检查 GitHub Issues
3. 提交新的 Issue 并附上日志和配置信息（脱敏处理）
