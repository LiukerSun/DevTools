# Let's Encrypt 证书管理指南

## 概述

本项目使用 Traefik 自动申请和管理 Let's Encrypt SSL 证书。支持通配符证书，并可在 Staging 和 Production 环境之间切换。

## 速率限制

Let's Encrypt 有以下速率限制：

- **生产环境 (Production)**：
  - 同一组域名每 7 天最多 **5 个证书**
  - 超过限制需等待 7 天后才能再次申请

- **测试环境 (Staging)**：
  - 速率限制更宽松，适合测试
  - 证书不被浏览器信任（显示不安全）

## 环境说明

### Staging 环境（测试）

- **CA 服务器**: `https://acme-staging-v02.api.letsencrypt.org/directory`
- **优点**: 无严格速率限制，适合反复测试
- **缺点**: 浏览器会显示证书不安全警告
- **用途**: 测试证书申请流程、调试配置

### Production 环境（生产）

- **CA 服务器**: `https://acme-v02.api.letsencrypt.org/directory`
- **优点**: 浏览器信任的正式证书
- **缺点**: 有严格速率限制
- **用途**: 生产环境使用

## 快速开始

### 首次部署（使用 Staging 测试）

```bash
# 1. 部署系统（会自动使用 Staging 环境）
sudo bash scripts/deploy-single.sh

# 2. 查看证书申请日志
docker logs -f traefik | grep -i certificate

# 3. 确认证书申请成功（等待 2-5 分钟）
cat data/traefik/acme.json | jq '.cloudflare.Certificates[0].domain'

# 4. 测试通过后，切换到 Production
sudo bash scripts/switch-letsencrypt.sh
# 选择选项 2 (切换到 Production 环境)
```

### 切换证书环境

```bash
# 运行切换脚本
sudo bash scripts/switch-letsencrypt.sh
```

脚本提供以下选项：

1. **切换到 Staging 环境** - 用于测试，无速率限制
2. **切换到 Production 环境** - 用于生产，签发正式证书
3. **重新申请证书** - 保持当前环境，重新申请
4. **退出**

## 遇到速率限制错误

### 错误信息

```
error: 429 :: urn:ietf:params:acme:error:rateLimited ::
too many certificates (5) already issued for this exact set of identifiers in the last 168h0m0s
```

### 解决方案

**方案一：切换到 Staging 环境（推荐）**

```bash
# 1. 运行切换脚本
sudo bash scripts/switch-letsencrypt.sh

# 2. 选择选项 1（切换到 Staging）
# 3. 等待证书申请成功
# 4. 测试配置无误后，等待速率限制解除再切换到 Production
```

**方案二：等待速率限制解除**

- 查看错误日志中的 `retry after` 时间
- 等待 7 天速率限制窗口过期
- 时间到期后重新申请

**方案三：使用已有证书**

如果备份了旧证书：

```bash
# 恢复备份的证书
cp data/traefik/acme.json.backup.YYYYMMDD_HHMMSS data/traefik/acme.json
chmod 600 data/traefik/acme.json

# 重启 Traefik
cd core
docker compose --env-file ../.env -f docker-compose.single.yml restart traefik
```

## 通配符证书配置

### 当前配置

在 `core/traefik/traefik.yml` 中配置了通配符证书：

```yaml
entryPoints:
  websecure:
    address: ":443"
    http:
      tls:
        certResolver: cloudflare
        domains:
          - main: "*.${DOMAIN}"
            sans:
              - "${DOMAIN}"
```

这会申请一个通配符证书 `*.lzpage.help`，覆盖所有子域名。

### 验证通配符证书

```bash
# 查看证书域名
cat data/traefik/acme.json | jq '.cloudflare.Certificates[0].domain'

# 应该显示:
# {
#   "main": "*.lzpage.help",
#   "sans": ["lzpage.help"]
# }
```

## 常见问题

### Q1: 为什么还是每个域名单独申请证书？

**可能原因**：
- 服务配置中指定了 `tls.certresolver`
- Traefik 优先使用服务级别的证书配置

**解决方法**：
通配符证书会自动匹配所有子域名，无需在每个服务中单独配置。

### Q2: Staging 证书能用于生产吗？

**不能**。Staging 证书：
- 不被浏览器信任
- 会显示 "不安全" 警告
- 仅用于测试配置

### Q3: 如何查看证书有效期？

```bash
# 使用 openssl 查看
echo | openssl s_client -servername traefik.lzpage.help -connect localhost:443 2>/dev/null | openssl x509 -noout -dates

# 使用 curl 查看
curl -vI https://traefik.lzpage.help 2>&1 | grep -i "expire"
```

### Q4: 证书会自动续期吗？

**会**。Traefik 会在证书到期前 30 天自动续期，无需手动操作。

### Q5: 切换环境需要停机吗？

**需要短暂停机**。切换脚本会：
1. 停止 Traefik（约 10 秒）
2. 删除旧证书
3. 重启 Traefik
4. 自动申请新证书（2-5 分钟）

在此期间 HTTPS 服务不可用。

## 手动操作

### 手动切换到 Staging

```bash
# 编辑配置文件
vim core/traefik/traefik.yml

# 修改为:
caServer: https://acme-staging-v02.api.letsencrypt.org/directory
# caServer: https://acme-v02.api.letsencrypt.org/directory

# 重启
cd core
docker compose --env-file ../.env -f docker-compose.single.yml restart traefik
```

### 手动切换到 Production

```bash
# 编辑配置文件
vim core/traefik/traefik.yml

# 修改为:
# caServer: https://acme-staging-v02.api.letsencrypt.org/directory
caServer: https://acme-v02.api.letsencrypt.org/directory

# 删除旧证书
rm data/traefik/acme.json
touch data/traefik/acme.json
chmod 600 data/traefik/acme.json

# 重启
cd core
docker compose --env-file ../.env -f docker-compose.single.yml restart traefik
```

## 监控证书状态

### 实时日志

```bash
# 查看 Traefik 日志
docker logs -f traefik

# 过滤证书相关日志
docker logs traefik 2>&1 | grep -i certificate
```

### 证书文件检查

```bash
# 查看 acme.json 内容
cat data/traefik/acme.json | jq '.'

# 查看证书域名
cat data/traefik/acme.json | jq '.cloudflare.Certificates[0].domain'

# 查看证书到期时间
cat data/traefik/acme.json | jq '.cloudflare.Certificates[0].certificate' | base64 -d | openssl x509 -noout -dates
```

## 最佳实践

1. **首次部署先用 Staging**
   - 验证配置正确
   - 避免浪费 Production 配额

2. **Production 环境谨慎操作**
   - 确认配置无误后再切换
   - 避免频繁删除重建证书

3. **定期备份证书**
   - 使用 `scripts/backup.sh` 备份
   - 保留多个版本的证书备份

4. **监控证书到期**
   - Prometheus 规则已配置证书到期告警
   - 证书在 30 天内到期会触发告警

## 相关文件

- **配置文件**: `core/traefik/traefik.yml`
- **配置模板**: `core/traefik/traefik.yml.template`
- **证书存储**: `data/traefik/acme.json`
- **切换脚本**: `scripts/switch-letsencrypt.sh`
- **部署脚本**: `scripts/deploy-single.sh`

## 参考链接

- [Let's Encrypt 速率限制文档](https://letsencrypt.org/docs/rate-limits/)
- [Traefik Let's Encrypt 文档](https://doc.traefik.io/traefik/https/acme/)
- [Cloudflare DNS Challenge](https://doc.traefik.io/traefik/https/acme/#providers)
