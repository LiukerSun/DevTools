#!/bin/bash

# DevTools 完全卸载脚本
# 此脚本会彻底清理所有相关文件和 Docker 资源，不留任何痕迹
# 使用方法: 在项目根目录运行 ./uninstall.sh

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 获取脚本所在目录作为项目根目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_NAME="$(basename "$SCRIPT_DIR")"

echo "========================================="
echo "      DevTools 完全卸载"
echo "========================================="
echo ""
echo "项目目录: $SCRIPT_DIR"
echo ""
echo -e "${RED}警告: 此操作将删除所有数据，无法恢复!${NC}"
echo ""
echo "将要执行的操作:"
echo "  1. 停止所有 Docker 容器"
echo "  2. 删除所有项目相关的 Docker 容器"
echo "  3. 删除所有项目相关的 Docker 镜像"
echo "  4. 删除所有项目相关的 Docker 卷"
echo "  5. 删除所有项目相关的 Docker 网络"
echo "  6. (可选) 删除数据目录"
echo "  7. (可选) 删除整个项目目录"
echo ""
read -p "确认要继续吗？输入 'YES' 继续: " confirm

if [ "$confirm" != "YES" ]; then
    echo -e "${YELLOW}已取消卸载${NC}"
    exit 0
fi

echo ""
echo "========================================="
echo "开始卸载..."
echo "========================================="

# 切换到项目根目录
cd "$SCRIPT_DIR"

# 1. 停止所有服务
echo -e "${YELLOW}[1/7] 停止所有服务...${NC}"

# 检测 Docker Compose 命令
if docker compose version &> /dev/null; then
    DOCKER_COMPOSE="docker compose"
elif command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE="docker-compose"
else
    echo -e "${YELLOW}Docker Compose 未找到，跳过容器停止步骤${NC}"
    DOCKER_COMPOSE=""
fi

if [ -n "$DOCKER_COMPOSE" ]; then
    # 停止业务服务
    for service_dir in services/*/; do
        if [ -f "${service_dir}docker-compose.yml" ]; then
            echo "停止服务: $(basename "$service_dir")"
            cd "$service_dir"
            $DOCKER_COMPOSE down -v 2>/dev/null || true
            cd "$SCRIPT_DIR"
        fi
    done

    # 停止监控服务 (单机版和标准版)
    if [ -d "monitoring" ]; then
        echo "停止监控服务..."
        cd monitoring
        if [ -f "docker-compose.single.yml" ]; then
            $DOCKER_COMPOSE -f docker-compose.single.yml down -v 2>/dev/null || true
        fi
        if [ -f "docker-compose.yml" ]; then
            $DOCKER_COMPOSE down -v 2>/dev/null || true
        fi
        cd "$SCRIPT_DIR"
    fi

    # 停止核心服务 (单机版和标准版)
    if [ -d "core" ]; then
        echo "停止核心服务..."
        cd core
        if [ -f "docker-compose.single.yml" ]; then
            $DOCKER_COMPOSE -f docker-compose.single.yml down -v 2>/dev/null || true
        fi
        if [ -f "docker-compose.yml" ]; then
            $DOCKER_COMPOSE down -v 2>/dev/null || true
        fi
        cd "$SCRIPT_DIR"
    fi

    echo -e "${GREEN}✓ 所有服务已停止${NC}"
else
    echo -e "${YELLOW}⚠ 跳过服务停止步骤${NC}"
fi

# 2. 删除所有项目相关的容器（包括已停止的）
echo -e "${YELLOW}[2/7] 删除所有项目相关的容器...${NC}"
if command -v docker &> /dev/null; then
    # 查找并删除所有相关容器
    containers=$(docker ps -a --filter "name=core" --filter "name=monitoring" --filter "name=traefik" --filter "name=keycloak" --filter "name=postgres" --filter "name=redis" --filter "name=prometheus" --filter "name=grafana" --filter "name=loki" --filter "name=alertmanager" --filter "name=jenkins" --filter "name=promtail" --filter "name=dns-manager" -q 2>/dev/null | sort -u || true)

    if [ -n "$containers" ]; then
        docker rm -f $containers 2>/dev/null || true
        echo -e "${GREEN}✓ 已删除 $(echo $containers | wc -w | tr -d ' ') 个容器${NC}"
    else
        echo -e "${GREEN}✓ 没有找到相关容器${NC}"
    fi
else
    echo -e "${YELLOW}⚠ Docker 未安装，跳过${NC}"
fi

# 3. 删除所有项目相关的镜像
echo -e "${YELLOW}[3/7] 删除所有项目相关的镜像...${NC}"
if command -v docker &> /dev/null; then
    # 删除项目构建的镜像
    images=$(docker images | grep -E "(traefik|keycloak|postgres|redis|prometheus|grafana|loki|alertmanager|promtail|jenkins|dns-manager)" | awk '{print $3}' | sort -u 2>/dev/null || true)

    if [ -n "$images" ]; then
        docker rmi -f $images 2>/dev/null || true
        echo -e "${GREEN}✓ 已删除 $(echo $images | wc -w | tr -d ' ') 个镜像${NC}"
    else
        echo -e "${GREEN}✓ 没有找到相关镜像${NC}"
    fi

    echo "清理未使用的镜像..."
    docker image prune -f 2>/dev/null || true
else
    echo -e "${YELLOW}⚠ Docker 未安装，跳过${NC}"
fi

# 4. 删除所有项目相关的卷
echo -e "${YELLOW}[4/7] 删除所有项目相关的 Docker 卷...${NC}"
if command -v docker &> /dev/null; then
    volumes=$(docker volume ls --filter "name=core" --filter "name=monitoring" --filter "name=devtools" -q 2>/dev/null || true)

    if [ -n "$volumes" ]; then
        docker volume rm -f $volumes 2>/dev/null || true
        echo -e "${GREEN}✓ 已删除 $(echo $volumes | wc -w | tr -d ' ') 个卷${NC}"
    else
        echo -e "${GREEN}✓ 没有找到相关卷${NC}"
    fi

    echo "清理未使用的卷..."
    docker volume prune -f 2>/dev/null || true
else
    echo -e "${YELLOW}⚠ Docker 未安装，跳过${NC}"
fi

# 5. 删除所有项目相关的网络
echo -e "${YELLOW}[5/7] 删除所有项目相关的 Docker 网络...${NC}"
if command -v docker &> /dev/null; then
    networks=$(docker network ls --filter "name=core" --filter "name=monitoring" --filter "name=devtools" -q 2>/dev/null || true)

    if [ -n "$networks" ]; then
        docker network rm $networks 2>/dev/null || true
        echo -e "${GREEN}✓ 已删除 $(echo $networks | wc -w | tr -d ' ') 个网络${NC}"
    else
        echo -e "${GREEN}✓ 没有找到相关网络${NC}"
    fi

    echo "清理未使用的网络..."
    docker network prune -f 2>/dev/null || true
else
    echo -e "${YELLOW}⚠ Docker 未安装，跳过${NC}"
fi

# 6. 删除数据目录
echo ""
echo -e "${YELLOW}[6/7] 删除数据目录...${NC}"
echo "数据目录包含:"
echo "  - data/traefik (SSL 证书)"
echo "  - data/postgres (数据库)"
echo "  - data/redis (缓存)"
echo "  - data/prometheus (监控数据)"
echo "  - data/grafana (仪表板)"
echo "  - data/loki (日志)"
echo "  - data/backups (备份)"
echo ""
read -p "是否删除数据目录? [y/N]: " delete_data

if [[ "$delete_data" =~ ^[Yy]$ ]]; then
    if [ -d "data" ]; then
        rm -rf data/
        echo -e "${GREEN}✓ 数据目录已删除${NC}"
    else
        echo -e "${YELLOW}✓ 数据目录不存在${NC}"
    fi
else
    echo -e "${YELLOW}⊙ 保留数据目录${NC}"
fi

# 7. 删除整个项目目录
echo ""
echo -e "${YELLOW}[7/7] 删除项目目录...${NC}"
echo -e "${RED}警告: 这将删除整个项目目录: $SCRIPT_DIR${NC}"
echo ""
read -p "是否删除整个项目目录? 输入 'DELETE' 确认: " final_confirm

if [ "$final_confirm" = "DELETE" ]; then
    PARENT_DIR="$(dirname "$SCRIPT_DIR")"
    cd "$PARENT_DIR"
    rm -rf "$SCRIPT_DIR"
    echo -e "${GREEN}✓ 项目目录已删除${NC}"
    echo ""
    echo "========================================="
    echo -e "${GREEN}DevTools 已完全卸载!${NC}"
    echo "========================================="
else
    echo -e "${YELLOW}⊙ 保留项目目录${NC}"
    echo ""
    echo "========================================="
    echo -e "${GREEN}Docker 资源已清理!${NC}"
    echo "========================================="
fi

echo ""
echo "已清理的内容:"
echo "  ✓ 所有 Docker 容器"
echo "  ✓ 所有 Docker 镜像"
echo "  ✓ 所有 Docker 卷"
echo "  ✓ 所有 Docker 网络"
if [[ "$delete_data" =~ ^[Yy]$ ]]; then
    echo "  ✓ 数据目录"
fi
if [ "$final_confirm" = "DELETE" ]; then
    echo "  ✓ 项目目录及所有文件"
fi
echo ""
echo -e "${GREEN}系统已清理完成，可以重新安装${NC}"
