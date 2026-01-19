# 故障排查指南

本文档包含常见问题和解决方案。

---

## 1. SSL 证书问题

### 问题: 证书申请失败

**症状:**
- 访问域名提示证书错误
- Traefik 日志显示 ACME challenge 失败

**排查步骤:**

1. 检查 Cloudflare API 凭证是否正确:
   ```bash
   cat .env | grep CF_API
   ```

2. 检查 DNS 记录是否正确:
   ```bash
   nslookup yourdomain.com
   ```

3. 检查 acme.json 权限:
   ```bash
   ls -l data/traefik/acme.json
   # 应该是 -rw------- (600)

   chmod 600 data/traefik/acme.json
   ```

4. 查看 Traefik 日志:
   ```bash
   docker logs traefik | grep -i acme
   ```

**解决方案:**

- 确保域名 DNS 已正确解析到服务器 IP
- 验证 Cloudflare API Key 有效
- 重启 Traefik:
  ```bash
  cd core
  docker-compose restart traefik
  ```

### 问题: 证书不自动续期

**症状:**
- 证书即将过期但没有自动续期

**解决方案:**

1. 检查 Traefik 日志是否有错误
2. 手动触发续期:
   ```bash
   # 删除旧证书
   rm data/traefik/acme.json
   touch data/traefik/acme.json
   chmod 600 data/traefik/acme.json

   # 重启 Traefik
   cd core && docker-compose restart traefik
   ```

---

## 2. 服务无法访问

### 问题: 域名无法访问

**排查步骤:**

1. 检查服务是否运行:
   ```bash
   ./scripts/health-check.sh
   ```

2. 检查防火墙:
   ```bash
   # UFW
   ufw status

   # Firewalld
   firewall-cmd --list-all
   ```

3. 检查 Traefik 路由:
   ```bash
   curl http://localhost:8080/api/http/routers
   ```

4. 检查 DNS 解析:
   ```bash
   nslookup yourdomain.com
   ping yourdomain.com
   ```

**解决方案:**

- 确保防火墙开放 80 和 443 端口
- 验证 DNS A 记录指向正确的 IP
- 检查服务的 Traefik 标签配置

### 问题: 网关返回 502 Bad Gateway  

**症状:**
- 页面显示 502 错误
- Traefik 无法连接到后端服务

**排查步骤:**

1. 检查后端服务是否运行:
   ```bash
   docker ps | grep service-name
   ```

2. 检查服务健康状态:
   ```bash
   docker inspect service-name | grep -A 20 Health
   ```

3. 检查网络连接:
   ```bash
   docker network inspect core_frontend
   ```

**解决方案:**

- 重启后端服务:
  ```bash
  docker restart service-name
  ```

- 检查服务日志:
  ```bash
  docker logs service-name
  ```

---

## 3. Keycloak 问题

### 问题: Keycloak 无法启动

**症状:**
- Keycloak 容器不断重启
- 登录页面无法访问

**排查步骤:**

1. 查看容器日志:
   ```bash
   docker logs keycloak
   ```

2. 检查 PostgreSQL 是否健康:
   ```bash
   docker exec postgres pg_isready
   ```

**常见错误和解决方案:**

**错误: "Database not ready"**
```bash
# PostgreSQL 未启动或不健康
cd core
docker-compose restart postgres
# 等待 30 秒
docker-compose restart keycloak
```

**错误: "Port already in use"**
```bash
# 端口冲突,检查是否有多个实例
docker ps | grep keycloak
# 停止旧实例
docker stop $(docker ps -q --filter "name=keycloak")
cd core && docker-compose up -d
```

### 问题: 无法登录 Keycloak Admin

**解决方案:**

1. 重置管理员密码:
   ```bash
   docker exec -it keycloak /opt/keycloak/bin/kc.sh export --realm master --dir /tmp
   # 或者重新创建容器,会重置密码
   ```

---

## 4. 数据库问题

### 问题: PostgreSQL 连接失败

**症状:**
- 服务无法连接到数据库
- 错误: "connection refused"

**排查步骤:**

1. 检查 PostgreSQL 状态:
   ```bash
   docker ps | grep postgres
   docker logs postgres
   ```

2. 测试连接:
   ```bash
   docker exec postgres pg_isready -U ${POSTGRES_USER}
   ```

**解决方案:**

```bash
# 重启 PostgreSQL
cd core
docker-compose restart postgres

# 如果仍然失败,检查数据卷
docker volume ls
docker volume inspect core_postgres_data
```

---

## 5. 监控和告警问题

### 问题: Prometheus 没有数据

**排查步骤:**

1. 检查 Prometheus targets:
   ```bash
   curl http://localhost:9090/api/v1/targets
   ```

2. 检查网络连接:
   ```bash
   docker network inspect core_monitoring
   ```

**解决方案:**

```bash
# 重启 Prometheus
cd monitoring
docker-compose restart prometheus
```

### 问题: 告警不发送

**排查步骤:**

1. 检查 AlertManager 配置:
   ```bash
   docker logs alertmanager
   ```

2. 测试 SMTP 连接:
   ```bash
   telnet smtp.qq.com 587
   ```

3. 检查 webhook 配置:
   ```bash
   # 测试钉钉 webhook
   curl -X POST "${DINGTALK_WEBHOOK}" \
     -H 'Content-Type: application/json' \
     -d '{"msgtype":"text","text":{"content":"测试消息"}}'
   ```

**解决方案:**

- 验证 SMTP 凭证
- 检查钉钉/企业微信 webhook URL
- 查看 AlertManager 日志排查错误

### 问题: 短信不发送

**排查步骤:**

1. 检查短信转发服务:
   ```bash
   docker logs sms-forwarder
   curl http://localhost:5000/health
   ```

2. 验证阿里云凭证:
   ```bash
   cat .env | grep ALIYUN
   ```

**解决方案:**

```bash
# 重启短信转发服务
cd monitoring
docker-compose restart sms-forwarder

# 查看详细日志
docker logs -f sms-forwarder
```

---

## 6. 性能问题

### 问题: 系统响应缓慢

**排查步骤:**

1. 检查资源使用:
   ```bash
   docker stats
   htop
   ```

2. 检查磁盘 I/O:
   ```bash
   iostat -x 1
   ```

3. 查看慢查询:
   ```bash
   docker exec postgres psql -U ${POSTGRES_USER} -c \
     "SELECT query, calls, total_time FROM pg_stat_statements ORDER BY total_time DESC LIMIT 10;"
   ```

**解决方案:**

- 增加服务器资源 (CPU/内存)
- 优化数据库查询
- 启用缓存
- 限制并发连接数

### 问题: 磁盘空间不足

**排查步骤:**

```bash
df -h
du -sh data/*
docker system df
```

**解决方案:**

```bash
# 清理 Docker 未使用资源
docker system prune -af --volumes

# 清理旧日志
find data/ -name "*.log" -mtime +7 -delete

# 清理旧备份
find data/backups/ -type d -mtime +7 -exec rm -rf {} \;
```

---

## 7. 容器问题

### 问题: 容器频繁重启

**排查步骤:**

1. 查看重启历史:
   ```bash
   docker ps -a | grep Restarting
   docker inspect container-name | grep -A 10 State
   ```

2. 查看退出代码:
   ```bash
   docker inspect container-name | grep ExitCode
   ```

**常见退出代码:**

- **137**: 内存不足,被 OOM Killer 杀死
- **1**: 应用错误
- **139**: 段错误

**解决方案:**

```bash
# OOM 问题 - 增加内存限制
# 编辑 docker-compose.yml,添加:
# resources:
#   limits:
#     memory: 2G

# 应用错误 - 查看日志
docker logs container-name
```

---

## 8. 数据恢复

### 场景: 需要从备份恢复

**PostgreSQL 恢复:**

```bash
# 停止服务
cd core && docker-compose stop postgres

# 恢复数据
gunzip < data/backups/YYYYMMDD_HHMMSS/postgres_all.sql.gz | \
  docker exec -i postgres psql -U ${POSTGRES_USER}

# 重启服务
docker-compose start postgres
```

**Redis 恢复:**

```bash
# 停止 Redis
cd core && docker-compose stop redis

# 恢复 RDB 文件
gunzip data/backups/YYYYMMDD_HHMMSS/redis_dump.rdb.gz
docker cp data/backups/YYYYMMDD_HHMMSS/redis_dump.rdb redis:/data/

# 重启 Redis
docker-compose start redis
```

**SSL 证书恢复:**

```bash
# 恢复 acme.json
cp data/backups/YYYYMMDD_HHMMSS/acme.json data/traefik/
chmod 600 data/traefik/acme.json

# 重启 Traefik
cd core && docker-compose restart traefik
```

---

## 9. 网络问题

### 问题: 容器之间无法通信

**排查步骤:**

```bash
# 检查网络
docker network ls
docker network inspect core_frontend

# 测试连接
docker exec container1 ping container2
```

**解决方案:**

```bash
# 重建网络
cd core
docker-compose down
docker-compose up -d
```

---

## 10. DNS Manager 问题

### 问题: DNS 记录未自动创建

**症状:**
- 新容器启动但 Cloudflare 没有对应的 A 记录
- 服务无法通过域名访问

**排查步骤:**

1. 检查 DNS Manager 状态:
   ```bash
   docker ps | grep dns-manager
   docker logs dns-manager
   ```

2. 检查容器标签:
   ```bash
   docker inspect container-name | jq '.[0].Config.Labels'
   ```

   确保包含: `traefik.http.routers.*.rule=Host(\`subdomain.yourdomain.com\`)`

3. 检查域名匹配:
   ```bash
   # 确保 .env 中配置正确
   cat .env | grep DOMAIN
   ```

4. 手动触发同步:
   ```bash
   ./scripts/sync-dns.sh
   # 或
   docker kill --signal=SIGUSR1 dns-manager
   ```

5. 查看 DNS Manager 日志:
   ```bash
   docker logs dns-manager | grep "subdomain"
   docker logs dns-manager | grep "ERROR"
   ```

**常见原因和解决方案:**

**原因 1: Traefik 标签配置错误**
```bash
# 错误示例: 域名不匹配
traefik.http.routers.myapp.rule=Host(`myapp.other.com`)  # 域名不是 ${DOMAIN}

# 正确示例:
traefik.http.routers.myapp.rule=Host(`myapp.${DOMAIN}`)
```

**原因 2: DNS Manager 未运行**
```bash
# 启动 DNS Manager
cd core
docker-compose -f docker-compose.single.yml up -d dns-manager
```

**原因 3: Cloudflare API 凭证错误**
```bash
# 检查 API Token
docker logs dns-manager | grep "Invalid request headers"

# 重新配置 .env 并重启
vi .env  # 更新 CF_DNS_API_TOKEN
cd core && docker-compose -f docker-compose.single.yml restart dns-manager
```

### 问题: Cloudflare API 错误

**常见错误信息:**

| 错误 | 原因 | 解决方案 |
|------|------|----------|
| `Invalid request headers` | API Token 无效 | 重新创建 Token 并更新 `.env` |
| `Zone not found` | 域名未添加到 Cloudflare | 确保域名已添加到你的账户 |
| `Insufficient permissions` | Token 权限不足 | 添加 Zone-DNS-Edit 和 Zone-Zone-Read 权限 |
| `Rate limit exceeded` | 请求过于频繁 | 等待 1 分钟（已内置指数退避） |

**查看 API 错误:**
```bash
docker logs dns-manager | grep "api_errors"
curl http://localhost:8000/health | jq '.stats.api_errors'
```

### 问题: DNS Manager 频繁重启

**排查步骤:**

1. 查看重启原因:
   ```bash
   docker events --filter 'container=dns-manager' --since 1h
   ```

2. 检查内存使用:
   ```bash
   docker stats dns-manager --no-stream
   ```

3. 检查健康检查:
   ```bash
   curl http://localhost:8000/health
   docker inspect dns-manager | grep -A 10 Healthcheck
   ```

4. 查看错误日志:
   ```bash
   docker logs dns-manager --tail 100 | grep -i error
   ```

**解决方案:**

```bash
# 重启服务
cd core
docker-compose -f docker-compose.single.yml restart dns-manager

# 如果持续失败，检查资源限制
docker-compose -f docker-compose.single.yml config | grep -A 5 dns-manager
```

### 问题: DNS 记录重复创建

**症状:**
- Cloudflare 中同一子域名有多条 A 记录

**解决方案:**

DNS Manager 在创建前会检查记录是否存在，通常不会重复创建。如果发现重复:

1. 登录 Cloudflare Dashboard 确认
2. 手动删除重复记录
3. 检查是否有多个 DNS Manager 实例:
   ```bash
   docker ps -a | grep dns-manager
   # 应该只有一个
   ```

### 问题: 监控告警不工作

**排查步骤:**

1. 检查 Prometheus 是否抓取 DNS Manager:
   ```bash
   curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.job=="dns-manager")'
   ```

2. 检查指标是否暴露:
   ```bash
   curl http://localhost:8000/metrics | grep dns_
   ```

3. 检查告警规则:
   ```bash
   docker exec prometheus promtool check rules /etc/prometheus/rules/dns.yml
   ```

**解决方案:**

```bash
# 重启 Prometheus 重新加载配置
cd monitoring
docker-compose restart prometheus

# 查看 Prometheus 日志
docker logs prometheus | grep dns-manager
```

### 问题: IPv4 检测失败

**症状:**
- DNS Manager 无法启动
- 日志显示 "Failed to detect IPv4 address"

**排查步骤:**

```bash
# 测试 IP 检测服务
curl https://api.ipify.org
curl https://ifconfig.me/ip
curl https://ip.sb

# 检查网络连接
ping -c 3 api.ipify.org
```

**解决方案:**

```bash
# 如果网络受限，可以在 .env 中手动指定 IP（需要修改代码）
# 或者配置代理

# 临时方案: 重启 DNS Manager 重试
cd core
docker-compose -f docker-compose.single.yml restart dns-manager
```

### DNS Manager 调试命令速查

```bash
# 查看服务状态
docker ps | grep dns-manager

# 查看实时日志
docker logs -f dns-manager

# 查看最近创建的记录
docker logs dns-manager | grep "Successfully created"

# 查看健康状态和统计
curl http://localhost:8000/health | jq

# 查看 Prometheus 指标
curl http://localhost:8000/metrics | grep dns_

# 手动触发同步
./scripts/sync-dns.sh

# 查看特定容器的处理日志
docker logs dns-manager | grep "container-name"

# 检查 API 错误
docker logs dns-manager | grep -i "cloudflare\|api error"

# 运行集成测试
./scripts/test-dns-integration.sh
```

---

## 11. 获取帮助

如果以上方案无法解决问题:

1. **查看日志**:
   ```bash
   docker-compose logs -f
   ```

2. **检查 GitHub Issues**:
   查看项目 GitHub Issues 是否有类似问题

3. **联系支持**:
   提供以下信息:
   - 错误日志
   - 系统信息: `uname -a && docker version`
   - 服务状态: `./scripts/health-check.sh`

---

**持续更新中...** 如果遇到新问题,请提交 Issue 或 PR 补充本文档。
