#!/bin/bash

# Let's Encrypt 证书环境切换脚本
# 用于在 Staging 和 Production 环境之间切换

set -e

# 颜色输出
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "========================================="
echo "  Let's Encrypt 证书环境切换工具"
echo "========================================="
echo ""

# 检查是否为 root 用户
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}请使用 root 用户或 sudo 运行此脚本${NC}"
    exit 1
fi

# 定位到脚本所在目录的上一级（项目根目录）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

TRAEFIK_CONFIG="core/traefik/traefik.yml"
ACME_JSON="data/traefik/acme.json"

# 检测 Docker Compose 命令
if docker compose version &> /dev/null; then
    DOCKER_COMPOSE="docker compose"
elif command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE="docker-compose"
else
    echo -e "${RED}Docker Compose 未安装${NC}"
    exit 1
fi

# 检查当前环境
echo -e "${BLUE}检查当前配置...${NC}"
if grep -q "acme-staging-v02.api.letsencrypt.org" "$TRAEFIK_CONFIG"; then
    CURRENT_ENV="staging"
    echo -e "当前环境: ${YELLOW}Staging (测试环境)${NC}"
elif grep -q "acme-v02.api.letsencrypt.org" "$TRAEFIK_CONFIG"; then
    CURRENT_ENV="production"
    echo -e "当前环境: ${GREEN}Production (生产环境)${NC}"
else
    echo -e "${RED}无法确定当前环境${NC}"
    exit 1
fi

echo ""
echo "选择操作:"
echo "  1) 切换到 Staging 环境 (无速率限制，用于测试)"
echo "  2) 切换到 Production 环境 (有速率限制，签发正式证书)"
echo "  3) 重新申请证书 (保持当前环境)"
echo "  4) 退出"
echo ""

read -p "请选择 [1-4]: " choice

case $choice in
    1)
        if [ "$CURRENT_ENV" = "staging" ]; then
            echo -e "${YELLOW}已经在 Staging 环境${NC}"
            read -p "是否重新申请证书? [y/N]: " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 0
            fi
        else
            echo -e "${YELLOW}切换到 Staging 环境...${NC}"
            sed -i 's|# caServer: https://acme-staging-v02.api.letsencrypt.org/directory|caServer: https://acme-staging-v02.api.letsencrypt.org/directory|g' "$TRAEFIK_CONFIG"
            sed -i 's|caServer: https://acme-v02.api.letsencrypt.org/directory|# caServer: https://acme-v02.api.letsencrypt.org/directory|g' "$TRAEFIK_CONFIG"
        fi
        ;;
    2)
        if [ "$CURRENT_ENV" = "production" ]; then
            echo -e "${YELLOW}已经在 Production 环境${NC}"
            read -p "是否重新申请证书? [y/N]: " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 0
            fi
        else
            echo -e "${YELLOW}切换到 Production 环境...${NC}"
            echo -e "${RED}警告: Production 环境有速率限制 (7天内最多5个证书)${NC}"
            echo ""
            read -p "确认切换到 Production 环境? [y/N]: " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                echo "已取消"
                exit 0
            fi
            sed -i 's|caServer: https://acme-staging-v02.api.letsencrypt.org/directory|# caServer: https://acme-staging-v02.api.letsencrypt.org/directory|g' "$TRAEFIK_CONFIG"
            sed -i 's|# caServer: https://acme-v02.api.letsencrypt.org/directory|caServer: https://acme-v02.api.letsencrypt.org/directory|g' "$TRAEFIK_CONFIG"
        fi
        ;;
    3)
        echo -e "${YELLOW}重新申请证书 (保持当前环境: $CURRENT_ENV)${NC}"
        ;;
    4)
        echo "已退出"
        exit 0
        ;;
    *)
        echo -e "${RED}无效选择${NC}"
        exit 1
        ;;
esac

echo ""
echo -e "${YELLOW}准备重新申请证书...${NC}"
echo ""

# 显示当前证书信息
if [ -f "$ACME_JSON" ] && [ -s "$ACME_JSON" ]; then
    echo -e "${BLUE}当前证书信息:${NC}"
    if command -v jq &> /dev/null; then
        cat "$ACME_JSON" | jq -r '.cloudflare.Certificates[0].domain // "无证书"'
    else
        echo "（安装 jq 以查看详细信息）"
    fi
    echo ""
fi

# 确认删除旧证书
echo -e "${RED}警告: 将删除现有证书并重新申请${NC}"
read -p "确认继续? [y/N]: " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "已取消"
    exit 0
fi

# 停止 Traefik
echo -e "${YELLOW}停止 Traefik 服务...${NC}"
cd core
$DOCKER_COMPOSE --env-file ../.env -f docker-compose.single.yml stop traefik
cd ..

# 备份旧证书
if [ -f "$ACME_JSON" ] && [ -s "$ACME_JSON" ]; then
    BACKUP_FILE="$ACME_JSON.backup.$(date +%Y%m%d_%H%M%S)"
    echo -e "${YELLOW}备份旧证书到: $BACKUP_FILE${NC}"
    cp "$ACME_JSON" "$BACKUP_FILE"
fi

# 删除旧证书
echo -e "${YELLOW}删除旧证书文件...${NC}"
rm -f "$ACME_JSON"
touch "$ACME_JSON"
chmod 600 "$ACME_JSON"

# 重启 Traefik
echo -e "${YELLOW}启动 Traefik 服务...${NC}"
cd core
$DOCKER_COMPOSE --env-file ../.env -f docker-compose.single.yml up -d traefik
cd ..

echo ""
echo -e "${GREEN}✓ 操作完成${NC}"
echo ""
echo "后续步骤:"
echo "  1. 查看证书申请日志:"
echo "     docker logs -f traefik"
echo ""
echo "  2. 等待 2-5 分钟后检查证书:"
echo "     cat $ACME_JSON | jq '.cloudflare.Certificates[0].domain'"
echo ""
echo "  3. 检查域名是否可访问:"
echo "     curl -I https://traefik.\${DOMAIN}"
echo ""

if [ "$CURRENT_ENV" = "staging" ]; then
    echo -e "${YELLOW}注意: 当前使用 Staging 证书，浏览器会显示不安全${NC}"
    echo "测试通过后，请运行此脚本切换到 Production 环境"
else
    echo -e "${GREEN}当前使用 Production 证书，浏览器会显示安全${NC}"
fi

echo ""
echo "========================================="
