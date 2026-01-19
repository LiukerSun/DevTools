#!/bin/bash

# PostgreSQL 数据库备份脚本
# 使用方法: ./backup.sh

set -e

# 配置
BACKUP_DIR="../data/backups/postgres"
CONTAINER_NAME="postgres"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/postgres_backup_${DATE}.sql.gz"
RETENTION_DAYS=7

# 创建备份目录
mkdir -p "${BACKUP_DIR}"

echo "开始备份 PostgreSQL 数据库..."
echo "备份文件: ${BACKUP_FILE}"

# 执行备份
docker exec -t ${CONTAINER_NAME} pg_dumpall -c -U ${POSTGRES_USER} | gzip > "${BACKUP_FILE}"

if [ $? -eq 0 ]; then
    echo "备份成功完成!"
    echo "文件大小: $(du -h ${BACKUP_FILE} | cut -f1)"

    # 删除超过保留天数的旧备份
    echo "清理 ${RETENTION_DAYS} 天前的旧备份..."
    find "${BACKUP_DIR}" -name "postgres_backup_*.sql.gz" -type f -mtime +${RETENTION_DAYS} -delete

    echo "备份任务完成!"
else
    echo "备份失败!"
    exit 1
fi
