#!/bin/bash

# 启动所有服务脚本

set -e

echo "========================================="
echo "      启动所有服务"
echo "========================================="

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 检测 Docker Compose 命令
if docker compose version &> /dev/null; then
    DOCKER_COMPOSE="docker compose"
elif command -v $DOCKER_COMPOSE &> /dev/null; then
    DOCKER_COMPOSE="$DOCKER_COMPOSE"
else
    echo -e "\033[0;31m错误: Docker Compose 未安装\033[0m"
    exit 1
fi

# 1. 启动核心服务
echo -e "${YELLOW}[1/3] 启动核心服务...${NC}"
cd core
$DOCKER_COMPOSE --env-file ../.env -f docker-compose.single.yml up -d
cd ..
echo -e "${GREEN}✓ 核心服务已启动${NC}"

# 等待核心服务健康
echo "等待核心服务健康检查..."
sleep 30

# 2. 启动监控服务
echo -e "${YELLOW}[2/3] 启动监控服务...${NC}"
cd monitoring
$DOCKER_COMPOSE --env-file ../.env -f docker-compose.single.yml up -d
cd ..
echo -e "${GREEN}✓ 监控服务已启动${NC}"

# 3. 启动业务服务
echo -e "${YELLOW}[3/3] 启动业务服务...${NC}"

# Jenkins
if [ -f "services/jenkins/docker-compose.optimized.yml" ]; then
    cd services/jenkins
    $DOCKER_COMPOSE --env-file ../../.env -f docker-compose.optimized.yml up -d
    cd ../..
    echo -e "${GREEN}✓ Jenkins 已启动${NC}"
fi

# 示例应用
if [ -f "services/example-app/docker-compose.yml" ]; then
    cd services/example-app
    $DOCKER_COMPOSE --env-file ../../.env -f docker-compose.yml up -d
    cd ../..
    echo -e "${GREEN}✓ 示例应用已启动${NC}"
fi

echo ""
echo "========================================="
echo -e "${GREEN}所有服务启动完成!${NC}"
echo "========================================="
echo ""
echo "运行 ./scripts/health-check.sh 检查服务状态"
