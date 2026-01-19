#!/bin/bash

# 单机优化版 - 一键部署脚本
# 适用于: 单台云服务器,资源有限的环境
# 优化: 移除冗余实例,降低内存和 CPU 占用

set -e

echo "========================================="
echo "  网关 - 单机优化版部署脚本"
echo "========================================="
echo ""
echo "此版本特点:"
echo "  ✓ 单实例部署,降低资源占用"
echo "  ✓ 资源限制,防止 OOM"
echo "  ✓ 保留核心功能,简化运维"
echo "  ✓ 适合 4核8G 或更低配置"
echo ""

# 颜色输出
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# 检查是否为 root 用户
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}请使用 root 用户或 sudo 运行此脚本${NC}"
    exit 1
fi

# 步骤 1: 检查和安装 Docker
echo -e "${YELLOW}[1/8] 检查 Docker 环境...${NC}"

# 检查 Docker
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Docker 未安装${NC}"
    echo ""
    read -p "是否自动安装 Docker? [Y/n]: " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        echo -e "${RED}需要 Docker 才能继续部署${NC}"
        exit 1
    fi

    # 调用 Docker 安装脚本
    echo -e "${YELLOW}开始安装 Docker...${NC}"
    bash scripts/install-docker.sh

    if [ $? -ne 0 ]; then
        echo -e "${RED}Docker 安装失败${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}✓ Docker 已安装${NC}"
    docker --version
fi

# 检查 Docker Compose 并设置命令变量
if docker compose version &> /dev/null; then
    echo -e "${GREEN}✓ Docker Compose 已安装${NC}"
    docker compose version
    DOCKER_COMPOSE="docker compose"
elif command -v docker-compose &> /dev/null; then
    echo -e "${GREEN}✓ Docker Compose 已安装${NC}"
    docker-compose --version
    DOCKER_COMPOSE="docker-compose"
else
    echo -e "${RED}Docker Compose 未安装${NC}"
    echo "请运行: bash scripts/install-docker.sh"
    exit 1
fi

# 步骤 2: 检查 .env 文件
echo -e "${YELLOW}[2/8] 检查环境变量配置...${NC}"

if [ ! -f ".env" ]; then
    echo -e "${RED}.env 文件不存在!${NC}"
    echo "请从 .env.example 复制并填写配置:"
    echo "  cp .env.example .env"
    echo "  vi .env"
    exit 1
else
    echo -e "${GREEN}✓ .env 文件存在${NC}"
fi

# 加载环境变量
source .env

# 验证必要的环境变量
if [ -z "$DOMAIN" ]; then
    echo -e "${RED}环境变量配置不完整!${NC}"
    echo "DOMAIN 未设置"
    exit 1
fi

# 检查 Cloudflare 认证配置 (支持两种方式)
if [ -n "$CF_DNS_API_TOKEN" ]; then
    echo -e "${GREEN}✓ 使用 Cloudflare API Token 认证${NC}"
elif [ -n "$CF_API_EMAIL" ] && [ -n "$CF_API_KEY" ]; then
    echo -e "${YELLOW}⚠ 使用 Cloudflare Global API Key 认证 (推荐改用 API Token)${NC}"
else
    echo -e "${RED}Cloudflare 认证配置不完整!${NC}"
    echo "请在 .env 文件中配置以下任一方式:"
    echo ""
    echo "方式 1 (推荐): API Token"
    echo "  CF_DNS_API_TOKEN=your-api-token"
    echo ""
    echo "方式 2: Global API Key"
    echo "  CF_API_EMAIL=your-email@example.com"
    echo "  CF_API_KEY=your-global-api-key"
    exit 1
fi

echo -e "${GREEN}✓ 环境变量配置完整${NC}"

# 步骤 3: 创建必要的目录
echo -e "${YELLOW}[3/8] 创建数据目录...${NC}"

mkdir -p data/traefik
mkdir -p data/postgres
mkdir -p data/redis
mkdir -p data/prometheus
mkdir -p data/grafana
mkdir -p data/loki
mkdir -p data/backups

# 创建 acme.json 并设置权限
touch data/traefik/acme.json
chmod 600 data/traefik/acme.json

echo -e "${GREEN}✓ 数据目录创建完成${NC}"

# 步骤 4: 配置防火墙
echo -e "${YELLOW}[4/8] 配置防火墙...${NC}"

if command -v ufw &> /dev/null; then
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw allow 22/tcp
    echo -e "${GREEN}✓ UFW 防火墙规则已添加${NC}"
elif command -v firewall-cmd &> /dev/null; then
    firewall-cmd --permanent --add-service=http
    firewall-cmd --permanent --add-service=https
    firewall-cmd --reload
    echo -e "${GREEN}✓ Firewalld 防火墙规则已添加${NC}"
else
    echo -e "${YELLOW}⚠ 未检测到防火墙,请手动开放 80 和 443 端口${NC}"
fi

# ==========================================
# 插入步骤: 自动生成 Traefik 配置
# ==========================================
echo -e "${YELLOW}[4.5/8] 从模板生成 Traefik 配置...${NC}"

TRAEFIK_TEMPLATE="core/traefik/traefik.yml.template"
TRAEFIK_CONFIG="core/traefik/traefik.yml"

if [ -f "$TRAEFIK_TEMPLATE" ]; then
    # 复制模板到实际配置文件
    cp "$TRAEFIK_TEMPLATE" "$TRAEFIK_CONFIG"
    
    echo "正在替换变量..."
    # 使用 sed 替换占位符
    # 使用 | 作为分隔符，防止内容中包含 / 导致报错
    sed -i "s|\${EMAIL}|$EMAIL|g" "$TRAEFIK_CONFIG"
    sed -i "s|\${DOMAIN}|$DOMAIN|g" "$TRAEFIK_CONFIG"
    
    echo -e "${GREEN}✓ Traefik 配置文件已生成: $TRAEFIK_CONFIG${NC}"
else
    echo -e "${RED}错误: 找不到模板文件 $TRAEFIK_TEMPLATE${NC}"
    echo "请先创建模板文件，或者手动配置 traefik.yml"
    # 这里可以选择 exit 1 终止，或者继续尝试使用现有的 traefik.yml
    exit 1
fi

# ==========================================
# 步骤 5: 启动核心服务 (单机版)
echo -e "${YELLOW}[5/8] 启动核心服务 (单实例模式)...${NC}"

cd core
$DOCKER_COMPOSE --env-file ../.env -f docker-compose.single.yml up -d
cd ..

echo -e "${GREEN}✓ 核心服务已启动${NC}"

# 步骤 6: 等待服务健康
echo -e "${YELLOW}[6/8] 等待服务健康检查...${NC}"

echo "等待 PostgreSQL 启动..."
sleep 30

echo "检查服务状态..."
cd core
$DOCKER_COMPOSE --env-file ../.env -f docker-compose.single.yml ps
cd ..

# ==========================================
# 插入的新步骤: 自动配置 AlertManager
# ==========================================
echo -e "${YELLOW}[6.5/8] 自动配置 AlertManager...${NC}"

AM_CONFIG="monitoring/alertmanager/alertmanager.yml"
AM_TEMPLATE="monitoring/alertmanager/alertmanager.yml.template"

# 1. 检查是否存在模板文件，如果不存在，则将当前的 yml (假定含有占位符) 另存为模板
if [ ! -f "$AM_TEMPLATE" ]; then
    if grep -q "\${SMTP_HOST}" "$AM_CONFIG"; then
        echo "首次运行，创建配置模板备份..."
        cp "$AM_CONFIG" "$AM_TEMPLATE"
    else
        echo -e "${RED}错误: 找不到带占位符的配置文件，也找不到模板。无法自动配置。${NC}"
        # 这里不退出，防止打断流程，但提示用户检查
    fi
fi

# 2. 从模板恢复配置文件 (确保每次都使用含有占位符的新鲜文件)
if [ -f "$AM_TEMPLATE" ]; then
    cp "$AM_TEMPLATE" "$AM_CONFIG"
    
    echo "正在替换环境变量..."
    # 使用 sed 批量替换占位符
    # 使用 | 作为分隔符，防止 URL 中的 / 导致 sed 报错
    sed -i "s|\${SMTP_HOST}|${SMTP_HOST}|g" "$AM_CONFIG"
    sed -i "s|\${SMTP_PORT}|${SMTP_PORT}|g" "$AM_CONFIG"
    sed -i "s|\${SMTP_USER}|${SMTP_USER}|g" "$AM_CONFIG"
    # 注意: 密码中可能包含特殊字符，sed 可能会报错，这里假设密码相对简单
    sed -i "s|\${SMTP_PASSWORD}|${SMTP_PASSWORD}|g" "$AM_CONFIG"
    sed -i "s|\${ALERT_EMAIL}|${ALERT_EMAIL}|g" "$AM_CONFIG"
    
    # 替换 Webhook (如果未设置，可能会替换为空，AlertManager可能会报错，建议在 .env 留空值)
    sed -i "s|\${DINGTALK_WEBHOOK}|${DINGTALK_WEBHOOK}|g" "$AM_CONFIG"
    sed -i "s|\${WECHAT_WEBHOOK}|${WECHAT_WEBHOOK}|g" "$AM_CONFIG"
    
    echo -e "${GREEN}✓ AlertManager 配置已更新${NC}"
fi
# ==========================================

# 步骤 7: 启动监控服务 (单机版)
echo -e "${YELLOW}[7/8] 启动监控服务 (轻量级)...${NC}"

cd monitoring
$DOCKER_COMPOSE --env-file ../.env -f docker-compose.single.yml up -d
cd ..

echo -e "${GREEN}✓ 监控服务已启动${NC}"

# 步骤 7.5: 启动 DNS Manager
echo -e "${YELLOW}[7.5/8.5] 启动 DNS 管理服务...${NC}"

cd core
$DOCKER_COMPOSE --env-file ../.env -f docker-compose.single.yml up -d dns-manager
cd ..

echo "等待 DNS Manager 初始化并同步 DNS 记录..."
sleep 10

# 检查 DNS Manager 状态
if docker ps | grep -q dns-manager; then
    echo -e "${GREEN}✓ DNS Manager 已启动${NC}"
    echo "  查看 DNS 同步日志: docker logs dns-manager"
    echo "  健康检查: curl http://localhost:8000/health"
else
    echo -e "${RED}✗ DNS Manager 启动失败${NC}"
    echo "  查看错误日志: docker logs dns-manager"
fi

echo ""

# 步骤 8: 显示资源使用情况
echo -e "${YELLOW}[8.5/8.5] 检查资源使用...${NC}"
echo ""

docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" | head -20

echo ""
echo "========================================="
echo -e "${GREEN}     单机版部署成功!${NC}"
echo "========================================="
echo ""
echo "访问地址:"
echo "  - Traefik Dashboard: https://traefik.${DOMAIN}"
echo "  - Keycloak:          https://auth.${DOMAIN}"
echo "  - Grafana:           https://grafana.${DOMAIN}"
echo "  - Prometheus:        https://prometheus.${DOMAIN}"
echo ""
echo "默认凭据:"
echo "  - Traefik Dashboard: admin / admin"
echo "  - Keycloak Admin:    ${KEYCLOAK_ADMIN} / ${KEYCLOAK_ADMIN_PASSWORD}"
echo "  - Grafana Admin:     ${GRAFANA_ADMIN_USER:-admin} / ${GRAFANA_ADMIN_PASSWORD:-admin}"
echo ""
echo "资源优化:"
echo "  ✓ Traefik: 单实例 (512MB 内存限制)"
echo "  ✓ Keycloak: 单实例 (2GB 内存限制)"
echo "  ✓ PostgreSQL: 单实例 (1GB 内存限制)"
echo "  ✓ Redis: 256MB 内存限制"
echo "  ✓ Prometheus: 15天数据保留 (1GB 内存限制)"
echo ""
echo "下一步:"
echo "  1. 访问 Keycloak 创建用户"
echo "  2. 配置 Grafana 仪表板"
echo "  3. 测试告警通知"
echo "  4. 部署业务服务"
echo ""
echo "管理命令:"
echo "  - 查看资源使用: docker stats"
echo "  - 查看日志: cd core && $DOCKER_COMPOSE --env-file ../.env -f docker-compose.single.yml logs -f"
echo "  - 备份数据: ./scripts/backup.sh"
echo ""
echo "========================================="
