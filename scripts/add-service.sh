#!/bin/bash

# 添加新服务助手脚本
# 自动生成 docker-compose.yml 模板

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# 参数检查
SERVICE_NAME=$1
SUBDOMAIN=$2

if [ -z "$SERVICE_NAME" ] || [ -z "$SUBDOMAIN" ]; then
    echo "========================================="
    echo "       添加新服务助手"
    echo "========================================="
    echo ""
    echo "用法: ./add-service.sh <service-name> <subdomain>"
    echo ""
    echo "示例:"
    echo "  ./add-service.sh myapp myapp"
    echo "  ./add-service.sh blog blog"
    echo ""
    exit 1
fi

# 加载域名配置
if [ ! -f ".env" ]; then
    echo -e "${RED}错误: .env 文件不存在${NC}"
    exit 1
fi

source .env

if [ -z "$DOMAIN" ]; then
    echo -e "${RED}错误: DOMAIN 未在 .env 中配置${NC}"
    exit 1
fi

echo "========================================="
echo "       添加新服务: $SERVICE_NAME"
echo "========================================="
echo ""
echo "子域名: ${SUBDOMAIN}.${DOMAIN}"
echo "服务目录: services/${SERVICE_NAME}"
echo ""

# 检查目录是否已存在
if [ -d "services/${SERVICE_NAME}" ]; then
    echo -e "${YELLOW}警告: 服务目录已存在${NC}"
    read -p "是否覆盖? [y/N]: " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "操作已取消"
        exit 0
    fi
fi

# 创建服务目录
mkdir -p "services/${SERVICE_NAME}"

# 生成 docker-compose.yml 模板
cat > "services/${SERVICE_NAME}/docker-compose.yml" <<EOF
version: '3.9'

networks:
  frontend:
    external: true
    name: core_frontend

services:
  ${SERVICE_NAME}:
    image: ${SERVICE_NAME}:latest
    container_name: ${SERVICE_NAME}
    restart: unless-stopped
    networks:
      - frontend
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.${SERVICE_NAME}.rule=Host(\\\`${SUBDOMAIN}.\${DOMAIN}\\\`)"
      - "traefik.http.routers.${SERVICE_NAME}.entrypoints=websecure"
      - "traefik.http.routers.${SERVICE_NAME}.tls.certresolver=cloudflare"
      # 可选: 启用 SSO 认证
      # - "traefik.http.routers.${SERVICE_NAME}.middlewares=keycloak-auth@docker"
EOF

echo -e "${GREEN}✓ 服务模板已创建${NC}"
echo ""
echo "文件位置: services/${SERVICE_NAME}/docker-compose.yml"
echo ""
echo "下一步:"
echo "  1. 编辑 docker-compose.yml，配置实际的镜像和端口"
echo "     vim services/${SERVICE_NAME}/docker-compose.yml"
echo ""
echo "  2. 启动服务"
echo "     cd services/${SERVICE_NAME}"
echo "     docker compose --env-file ../../.env -f docker-compose.yml up -d"
echo ""
echo "  3. DNS 记录将自动创建（约 10 秒后生效）"
echo "     查看日志: docker logs dns-manager | grep ${SUBDOMAIN}"
echo ""
echo "  4. SSL 证书自动申请（约 1-2 分钟）"
echo "     查看日志: docker logs traefik | grep ${SUBDOMAIN}"
echo ""
echo "  5. 访问服务"
echo "     https://${SUBDOMAIN}.${DOMAIN}"
echo ""
echo "停止服务:"
echo "  cd services/${SERVICE_NAME}"
echo "  docker compose --env-file ../../.env -f docker-compose.yml down"
echo ""
