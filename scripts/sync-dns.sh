#!/bin/bash

# DNS 手动同步脚本
# 触发 DNS Manager 重新扫描所有容器

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "========================================="
echo "       DNS 手动同步工具"
echo "========================================="
echo ""

# 检查 DNS Manager 是否运行
if ! docker ps | grep -q dns-manager; then
    echo -e "${RED}错误: dns-manager 容器未运行${NC}"
    echo ""
    echo "启动方法:"
    echo "  cd core && docker-compose -f docker-compose.single.yml up -d dns-manager"
    exit 1
fi

echo -e "${YELLOW}触发 DNS 全量同步...${NC}"

# 发送 SIGUSR1 信号触发同步
docker kill --signal=SIGUSR1 dns-manager

echo -e "${GREEN}✓ 同步请求已发送${NC}"
echo ""
echo "查看同步日志:"
echo "  docker logs -f dns-manager"
echo ""
echo "查看健康状态:"
echo "  curl http://localhost:8000/health | jq"
echo ""
