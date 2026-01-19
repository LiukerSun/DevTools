# 新服务部署指南

本指南说明如何在网关中添加新的应用服务，并自动获得 HTTPS 和 DNS 配置。

## 方法 1：使用自动化脚本（推荐）

### 1. 运行脚本生成模板

```bash
cd ~/DevTools
./scripts/add-service.sh <服务名> <子域名>
```

**示例：**
```bash
# 添加一个博客服务
./scripts/add-service.sh myblog blog

# 添加一个 API 服务
./scripts/add-service.sh myapi api
```

### 2. 编辑生成的配置文件

```bash
vim services/<服务名>/docker-compose.yml
```

修改以下内容：
- `image`: 您的 Docker 镜像
- `ports`: 如果需要暴露端口
- `volumes`: 如果需要持久化数据
- `environment`: 环境变量

### 3. 启动服务

```bash
cd services/<服务名>
docker compose --env-file ../../.env -f docker-compose.yml up -d
```

### 4. 验证部署

```bash
# 查看 DNS 自动创建日志
docker logs dns-manager | grep <子域名>

# 查看 SSL 证书申请日志
docker logs traefik | grep <子域名>

# 查看服务日志
docker logs <服务名>
```

### 5. 访问服务

访问 `https://<子域名>.${DOMAIN}`（例如：https://blog.lzpage.help）

---

## 方法 2：手动创建

### 1. 创建服务目录

```bash
mkdir -p services/myapp
```

### 2. 创建 docker-compose.yml

```yaml
version: '3.9'

networks:
  frontend:
    external: true
    name: core_frontend

services:
  myapp:
    image: nginx:alpine  # 替换为您的镜像
    container_name: myapp
    restart: unless-stopped
    networks:
      - frontend

    # ==========================================
    # Traefik 配置（必需）
    # ==========================================
    labels:
      # 1. 启用 Traefik
      - "traefik.enable=true"

      # 2. 域名路由（DNS Manager 会自动创建 DNS 记录）
      - "traefik.http.routers.myapp.rule=Host(`myapp.${DOMAIN}`)"

      # 3. HTTPS 入口点
      - "traefik.http.routers.myapp.entrypoints=websecure"

      # 4. 自动 SSL 证书
      - "traefik.http.routers.myapp.tls.certresolver=cloudflare"

      # 5. 指定服务端口（如果不是 80）
      - "traefik.http.services.myapp.loadbalancer.server.port=8080"

      # 6. 可选：限流保护
      - "traefik.http.middlewares.myapp-ratelimit.ratelimit.average=100"
      - "traefik.http.middlewares.myapp-ratelimit.ratelimit.burst=50"
      - "traefik.http.routers.myapp.middlewares=myapp-ratelimit"

      # 7. 可选：Keycloak SSO 认证
      # - "traefik.http.routers.myapp.middlewares=myapp-ratelimit,keycloak-auth@docker"
```

### 3. 启动服务

```bash
cd services/myapp
docker compose --env-file ../../.env -f docker-compose.yml up -d
```

---

## 自动化功能说明

当您启动服务后，系统会自动完成以下操作：

### ✅ 自动 DNS 记录创建

**DNS Manager** 会：
1. 监听 Docker 容器启动事件
2. 检测到新容器的 Traefik 标签
3. 提取域名（如 `myapp.${DOMAIN}`）
4. 通过 Cloudflare API 创建 A 记录：`myapp.yourdomain.com -> 服务器 IP`
5. 记录约 10 秒后全球生效

**验证：**
```bash
# 查看 DNS Manager 日志
docker logs dns-manager | grep myapp

# 测试 DNS 解析
dig +short myapp.yourdomain.com
```

### ✅ 自动 SSL 证书申请

**Traefik** 会：
1. 检测到新路由的 `tls.certresolver=cloudflare` 标签
2. 通过 Cloudflare DNS-01 验证申请 Let's Encrypt 证书
3. 验证通过后自动下载并安装证书
4. 证书自动续期（90 天有效期，提前 30 天续期）

**验证：**
```bash
# 查看 Traefik 日志
docker logs traefik | grep certificate | grep myapp

# 浏览器访问检查证书
https://myapp.yourdomain.com
```

---

## 配置模板示例

### Nginx 静态网站

```yaml
services:
  mywebsite:
    image: nginx:alpine
    container_name: mywebsite
    restart: unless-stopped
    networks:
      - frontend
    volumes:
      - ./html:/usr/share/nginx/html:ro
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.mywebsite.rule=Host(`www.${DOMAIN}`)"
      - "traefik.http.routers.mywebsite.entrypoints=websecure"
      - "traefik.http.routers.mywebsite.tls.certresolver=cloudflare"
      - "traefik.http.services.mywebsite.loadbalancer.server.port=80"
```

### Node.js 应用

```yaml
services:
  nodeapp:
    image: node:18-alpine
    container_name: nodeapp
    restart: unless-stopped
    networks:
      - frontend
    working_dir: /app
    volumes:
      - ./app:/app
    command: npm start
    environment:
      - NODE_ENV=production
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.nodeapp.rule=Host(`api.${DOMAIN}`)"
      - "traefik.http.routers.nodeapp.entrypoints=websecure"
      - "traefik.http.routers.nodeapp.tls.certresolver=cloudflare"
      - "traefik.http.services.nodeapp.loadbalancer.server.port=3000"
```

### WordPress

```yaml
services:
  wordpress:
    image: wordpress:latest
    container_name: wordpress
    restart: unless-stopped
    networks:
      - frontend
      - backend
    environment:
      - WORDPRESS_DB_HOST=postgres:3306
      - WORDPRESS_DB_USER=${DB_USER}
      - WORDPRESS_DB_PASSWORD=${DB_PASSWORD}
      - WORDPRESS_DB_NAME=wordpress
    volumes:
      - wordpress_data:/var/www/html
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.wordpress.rule=Host(`blog.${DOMAIN}`)"
      - "traefik.http.routers.wordpress.entrypoints=websecure"
      - "traefik.http.routers.wordpress.tls.certresolver=cloudflare"
      - "traefik.http.services.wordpress.loadbalancer.server.port=80"

volumes:
  wordpress_data:
```

---

## 常见问题

### Q: DNS 记录没有自动创建？

**检查步骤：**
```bash
# 1. 确认 DNS Manager 正在运行
docker ps | grep dns-manager

# 2. 查看日志
docker logs dns-manager

# 3. 确认容器有正确的 Traefik 标签
docker inspect <服务名> | grep traefik.enable

# 4. 确认容器在 core_frontend 网络
docker inspect <服务名> | grep core_frontend
```

### Q: SSL 证书没有申请？

**检查步骤：**
```bash
# 1. 查看 Traefik 日志
docker logs traefik | grep -i error

# 2. 确认 DNS 记录已存在
dig +short <子域名>.yourdomain.com

# 3. 检查 acme.json 权限
ls -la data/traefik/acme.json
# 应该是 -rw------- (600)

# 4. 等待一段时间（证书申请可能需要 1-2 分钟）
```

### Q: 服务无法访问？

**检查步骤：**
```bash
# 1. 确认容器正在运行
docker ps | grep <服务名>

# 2. 查看容器日志
docker logs <服务名>

# 3. 测试容器内部连接
docker exec <服务名> curl -f http://localhost:<端口>

# 4. 检查 Traefik 路由
docker exec traefik wget -qO- http://localhost:8080/api/http/routers | grep <服务名>
```

---

## 重要提示

### ✅ 必需配置

1. **网络连接**：必须连接到 `core_frontend` 网络
2. **Traefik 标签**：必须包含以下标签：
   - `traefik.enable=true`
   - `traefik.http.routers.<name>.rule=Host(...)`
   - `traefik.http.routers.<name>.entrypoints=websecure`
   - `traefik.http.routers.<name>.tls.certresolver=cloudflare`

### ⚠️ 注意事项

1. **端口号**：如果服务不是运行在 80 端口，必须指定端口：
   ```yaml
   - "traefik.http.services.<name>.loadbalancer.server.port=8080"
   ```

2. **路由名称**：每个服务的路由名称必须唯一（如 `jenkins`、`myapp`）

3. **中间件组合**：如果需要多个中间件，用逗号分隔：
   ```yaml
   - "traefik.http.routers.<name>.middlewares=ratelimit,auth@docker"
   ```

4. **环境变量**：使用 `${DOMAIN}` 引用 .env 文件中的域名配置

---

## 管理命令速查

```bash
# 启动服务
cd services/<服务名>
docker compose --env-file ../../.env -f docker-compose.yml up -d

# 停止服务
docker compose --env-file ../../.env -f docker-compose.yml down

# 重启服务
docker compose --env-file ../../.env -f docker-compose.yml restart

# 查看日志
docker logs -f <服务名>

# 查看状态
docker ps | grep <服务名>

# 进入容器
docker exec -it <服务名> sh
```

---

## 总结

新服务部署只需 3 步：

1. **创建配置**：使用脚本或手动创建 docker-compose.yml
2. **启动服务**：`docker compose --env-file ../../.env up -d`
3. **等待就绪**：DNS（10秒） + SSL（1-2分钟）自动完成

就是这么简单！🚀
