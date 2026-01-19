#!/bin/bash

# 停止所有服务脚本

set -e

echo "========================================="
echo "      停止所有服务"
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

# 1. 停止业务服务
echo -e "${YELLOW}[1/3] 停止业务服务...${NC}"

# Jenkins
if [ -f "services/jenkins/docker-compose.optimized.yml" ]; then
    cd services/jenkins
    $DOCKER_COMPOSE --env-file ../../.env -f docker-compose.optimized.yml down
    cd ../..
    echo -e "${GREEN}✓ Jenkins 已停止${NC}"
fi

# 示例应用
if [ -f "services/example-app/docker-compose.yml" ]; then
    cd services/example-app
    $DOCKER_COMPOSE --env-file ../../.env -f docker-compose.yml down
    cd ../..
    echo -e "${GREEN}✓ 示例应用已停止${NC}"
fi

# 2. 停止监控服务
echo -e "${YELLOW}[2/3] 停止监控服务...${NC}"
cd monitoring
$DOCKER_COMPOSE --env-file ../.env -f docker-compose.single.yml down
cd ..
echo -e "${GREEN}✓ 监控服务已停止${NC}"

# 3. 停止核心服务
echo -e "${YELLOW}[3/3] 停止核心服务...${NC}"
cd core
$DOCKER_COMPOSE --env-file ../.env -f docker-compose.single.yml down
cd ..
echo -e "${GREEN}✓ 核心服务已停止${NC}"

echo ""
echo "========================================="
echo -e "${GREEN}所有服务已停止!${NC}"
echo "========================================="
