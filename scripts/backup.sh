#!/bin/bash

# 数据备份脚本
# 备份 PostgreSQL、Redis、SSL 证书等重要数据

set -e

echo "========================================="
echo "      数据备份脚本"
echo "========================================="
echo ""

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# 配置
BACKUP_ROOT="./data/backups"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="${BACKUP_ROOT}/${DATE}"
RETENTION_DAYS=7

# 加载环境变量
if [ -f ".env" ]; then
    source .env
else
    echo -e "${RED}.env 文件不存在!${NC}"
    exit 1
fi

# 创建备份目录
mkdir -p "${BACKUP_DIR}"

echo -e "${YELLOW}备份目录: ${BACKUP_DIR}${NC}"
echo ""

# 1. 备份 PostgreSQL
echo -e "${YELLOW}[1/5] 备份 PostgreSQL 数据库...${NC}"

if docker ps --format '{{.Names}}' | grep -q "^postgres$"; then
    docker exec -t postgres pg_dumpall -c -U ${POSTGRES_USER} | gzip > "${BACKUP_DIR}/postgres_all.sql.gz"
    echo -e "${GREEN}✓ PostgreSQL 备份完成${NC}"
    echo "  文件: $(du -h ${BACKUP_DIR}/postgres_all.sql.gz | cut -f1)"
else
    echo -e "${RED}✗ PostgreSQL 容器未运行,跳过备份${NC}"
fi

# 2. 备份 Redis
echo -e "${YELLOW}[2/5] 备份 Redis 数据...${NC}"

if docker ps --format '{{.Names}}' | grep -q "^redis$"; then
    # 触发 Redis 保存
    docker exec redis redis-cli BGSAVE

    # 等待保存完成
    sleep 5

    # 复制 RDB 文件
    docker cp redis:/data/dump.rdb "${BACKUP_DIR}/redis_dump.rdb"
    gzip "${BACKUP_DIR}/redis_dump.rdb"

    echo -e "${GREEN}✓ Redis 备份完成${NC}"
    echo "  文件: $(du -h ${BACKUP_DIR}/redis_dump.rdb.gz | cut -f1)"
else
    echo -e "${RED}✗ Redis 容器未运行,跳过备份${NC}"
fi

# 3. 备份 SSL 证书
echo -e "${YELLOW}[3/5] 备份 SSL 证书...${NC}"

if [ -f "./data/traefik/acme.json" ]; then
    cp ./data/traefik/acme.json "${BACKUP_DIR}/acme.json"
    chmod 600 "${BACKUP_DIR}/acme.json"
    echo -e "${GREEN}✓ SSL 证书备份完成${NC}"
else
    echo -e "${RED}✗ acme.json 不存在,跳过备份${NC}"
fi

# 4. 备份 Grafana 配置
echo -e "${YELLOW}[4/5] 备份 Grafana 配置...${NC}"

if [ -d "./data/grafana" ]; then
    tar -czf "${BACKUP_DIR}/grafana.tar.gz" -C ./data grafana
    echo -e "${GREEN}✓ Grafana 配置备份完成${NC}"
    echo "  文件: $(du -h ${BACKUP_DIR}/grafana.tar.gz | cut -f1)"
else
    echo -e "${RED}✗ Grafana 数据目录不存在,跳过备份${NC}"
fi

# 5. 备份配置文件
echo -e "${YELLOW}[5/5] 备份配置文件...${NC}"

tar -czf "${BACKUP_DIR}/configs.tar.gz" \
    --exclude='*.log' \
    --exclude='data' \
    core/ monitoring/ services/ scripts/ .env 2>/dev/null || true

echo -e "${GREEN}✓ 配置文件备份完成${NC}"
echo "  文件: $(du -h ${BACKUP_DIR}/configs.tar.gz | cut -f1)"

# 清理旧备份
echo ""
echo -e "${YELLOW}清理 ${RETENTION_DAYS} 天前的旧备份...${NC}"

find "${BACKUP_ROOT}" -maxdepth 1 -type d -mtime +${RETENTION_DAYS} -exec rm -rf {} \; 2>/dev/null || true

# 备份摘要
echo ""
echo "========================================="
echo -e "${GREEN}备份完成!${NC}"
echo "========================================="
echo ""
echo "备份位置: ${BACKUP_DIR}"
echo "备份文件:"
ls -lh "${BACKUP_DIR}"
echo ""
echo "总大小: $(du -sh ${BACKUP_DIR} | cut -f1)"
echo ""
echo "提示:"
echo "  - 建议定期将备份文件传输到远程服务器"
echo "  - 可以使用 rsync 或 scp 命令传输备份"
echo "  - 示例: rsync -avz ${BACKUP_DIR} user@remote:/backups/"
echo ""
