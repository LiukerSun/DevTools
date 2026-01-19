#!/bin/bash

# 修复 Let's Encrypt Email 配置问题

set -e

# 颜色输出
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "========================================="
echo "  Let's Encrypt Email 配置修复工具"
echo "========================================="
echo ""

# 检查是否为 root 用户
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}请使用 root 用户或 sudo 运行此脚本${NC}"
    exit 1
fi

# 定位到项目根目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

echo -e "${BLUE}步骤 1: 检查 .env 文件中的 EMAIL 配置${NC}"
if [ -f ".env" ]; then
    EMAIL_VALUE=$(grep '^EMAIL=' .env | cut -d'=' -f2)
    if [ -z "$EMAIL_VALUE" ]; then
        echo -e "${RED}✗ EMAIL 未在 .env 文件中设置${NC}"
        echo ""
        read -p "请输入您的邮箱地址（用于 Let's Encrypt 通知）: " NEW_EMAIL

        # 验证邮箱格式
        if [[ ! "$NEW_EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            echo -e "${RED}邮箱格式无效${NC}"
            exit 1
        fi

        # 检查 .env 文件中是否已有 EMAIL 行
        if grep -q '^EMAIL=' .env; then
            sed -i "s|^EMAIL=.*|EMAIL=$NEW_EMAIL|g" .env
        else
            echo "EMAIL=$NEW_EMAIL" >> .env
        fi
        echo -e "${GREEN}✓ EMAIL 已添加到 .env 文件${NC}"
    else
        echo -e "${GREEN}✓ EMAIL 已设置: $EMAIL_VALUE${NC}"

        # 验证邮箱格式
        if [[ ! "$EMAIL_VALUE" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            echo -e "${RED}✗ 邮箱格式无效: $EMAIL_VALUE${NC}"
            read -p "请输入正确的邮箱地址: " NEW_EMAIL

            if [[ ! "$NEW_EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
                echo -e "${RED}邮箱格式无效${NC}"
                exit 1
            fi

            sed -i "s|^EMAIL=.*|EMAIL=$NEW_EMAIL|g" .env
            echo -e "${GREEN}✓ EMAIL 已更新${NC}"
        fi
    fi
else
    echo -e "${RED}✗ .env 文件不存在${NC}"
    exit 1
fi

# 重新加载环境变量
source .env

echo ""
echo -e "${BLUE}步骤 2: 检查 traefik.yml 配置${NC}"
TRAEFIK_CONFIG="core/traefik/traefik.yml"

if [ -f "$TRAEFIK_CONFIG" ]; then
    # 检查是否包含未替换的变量
    if grep -q '\${EMAIL}' "$TRAEFIK_CONFIG"; then
        echo -e "${YELLOW}⚠ traefik.yml 包含未替换的变量${NC}"
        echo "正在从模板重新生成配置..."

        TRAEFIK_TEMPLATE="core/traefik/traefik.yml.template"
        if [ -f "$TRAEFIK_TEMPLATE" ]; then
            cp "$TRAEFIK_TEMPLATE" "$TRAEFIK_CONFIG"
            sed -i "s|\${EMAIL}|$EMAIL|g" "$TRAEFIK_CONFIG"
            sed -i "s|\${DOMAIN}|$DOMAIN|g" "$TRAEFIK_CONFIG"
            echo -e "${GREEN}✓ traefik.yml 已重新生成${NC}"
        else
            echo -e "${RED}✗ 找不到模板文件${NC}"
            exit 1
        fi
    else
        # 检查当前的 email 值
        CURRENT_EMAIL=$(grep 'email:' "$TRAEFIK_CONFIG" | head -1 | awk '{print $2}')
        echo -e "${GREEN}✓ traefik.yml 中的 email: $CURRENT_EMAIL${NC}"

        # 如果不匹配，更新它
        if [ "$CURRENT_EMAIL" != "$EMAIL" ]; then
            echo -e "${YELLOW}⚠ traefik.yml 中的 email 与 .env 不一致${NC}"
            echo "正在更新..."
            sed -i "s|email:.*|email: $EMAIL|g" "$TRAEFIK_CONFIG"
            echo -e "${GREEN}✓ email 已更新${NC}"
        fi
    fi
else
    echo -e "${RED}✗ traefik.yml 不存在${NC}"
    exit 1
fi

echo ""
echo -e "${BLUE}步骤 3: 验证配置${NC}"
echo "当前配置:"
echo "  EMAIL: $EMAIL"
echo "  DOMAIN: $DOMAIN"
echo ""

read -p "确认配置正确？继续重启 Traefik？[Y/n]: " -n 1 -r
echo
if [[ $REPLY =~ ^[Nn]$ ]]; then
    echo "已取消"
    exit 0
fi

echo ""
echo -e "${BLUE}步骤 4: 重启 Traefik${NC}"

# 检测 Docker Compose 命令
if docker compose version &> /dev/null; then
    DOCKER_COMPOSE="docker compose"
elif command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE="docker-compose"
else
    echo -e "${RED}Docker Compose 未安装${NC}"
    exit 1
fi

# 删除旧证书（因为之前用错误的 email 可能已经创建了账户）
ACME_JSON="data/traefik/acme.json"
if [ -f "$ACME_JSON" ] && [ -s "$ACME_JSON" ]; then
    BACKUP_FILE="$ACME_JSON.backup.$(date +%Y%m%d_%H%M%S)"
    echo -e "${YELLOW}备份旧证书到: $BACKUP_FILE${NC}"
    cp "$ACME_JSON" "$BACKUP_FILE"
fi

echo "删除旧证书文件..."
rm -f "$ACME_JSON"
touch "$ACME_JSON"
chmod 600 "$ACME_JSON"

# 重启 Traefik
echo "重启 Traefik 服务..."
cd core
$DOCKER_COMPOSE --env-file ../.env -f docker-compose.single.yml restart traefik
cd ..

echo ""
echo -e "${GREEN}✓ 配置已修复，Traefik 已重启${NC}"
echo ""
echo "后续步骤:"
echo "  1. 查看证书申请日志:"
echo "     docker logs -f traefik | grep -i certificate"
echo ""
echo "  2. 等待 2-5 分钟后检查证书:"
echo "     cat $ACME_JSON | jq '.cloudflare.Certificates[0].domain'"
echo ""
echo "  3. 检查是否还有错误:"
echo "     docker logs traefik 2>&1 | grep -i error | tail -20"
echo ""
echo "========================================="
