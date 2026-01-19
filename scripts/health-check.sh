#!/bin/bash

# 健康检查脚本 - 检查所有服务状态

echo "========================================="
echo "      服务健康检查"
echo "========================================="
echo ""

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 加载环境变量
if [ -f ".env" ]; then
    source .env
fi

# 检查容器状态
check_container() {
    local container=$1
    local name=$2

    if docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
        health=$(docker inspect --format='{{.State.Health.Status}}' ${container} 2>/dev/null || echo "no-healthcheck")

        if [ "$health" = "healthy" ]; then
            echo -e "${GREEN}✓${NC} ${name}: 运行中 (健康)"
        elif [ "$health" = "no-healthcheck" ]; then
            echo -e "${YELLOW}○${NC} ${name}: 运行中 (无健康检查)"
        else
            echo -e "${RED}✗${NC} ${name}: 运行中 (不健康: ${health})"
        fi
    else
        echo -e "${RED}✗${NC} ${name}: 未运行"
    fi
}

echo "核心服务:"
echo "----------"
check_container "traefik" "Traefik"
check_container "postgres" "PostgreSQL"
check_container "redis" "Redis"
check_container "keycloak" "Keycloak"

echo ""
echo "监控服务:"
echo "----------"
check_container "prometheus" "Prometheus"
check_container "grafana" "Grafana"
check_container "loki" "Loki"
check_container "promtail" "Promtail"
check_container "alertmanager" "AlertManager"
check_container "node-exporter" "Node Exporter"
check_container "cadvisor" "cAdvisor"
check_container "sms-forwarder" "SMS Forwarder"

echo ""
echo "业务服务:"
echo "----------"
check_container "jenkins" "Jenkins"
check_container "example-app" "示例应用"

echo ""
echo "========================================="
echo "网络连接检查:"
echo "========================================="

if [ -n "$DOMAIN" ]; then
    echo "测试域名解析和 HTTPS 连接..."
    echo ""

    # 测试 Traefik
    if curl -s -o /dev/null -w "%{http_code}" "https://traefik.${DOMAIN}" | grep -q "200\|401\|403"; then
        echo -e "${GREEN}✓${NC} Traefik Dashboard 可访问"
    else
        echo -e "${RED}✗${NC} Traefik Dashboard 无法访问"
    fi

    # 测试 Keycloak
    if curl -s -o /dev/null -w "%{http_code}" "https://auth.${DOMAIN}" | grep -q "200"; then
        echo -e "${GREEN}✓${NC} Keycloak 可访问"
    else
        echo -e "${RED}✗${NC} Keycloak 无法访问"
    fi

    # 测试 Grafana
    if curl -s -o /dev/null -w "%{http_code}" "https://grafana.${DOMAIN}" | grep -q "200\|302"; then
        echo -e "${GREEN}✓${NC} Grafana 可访问"
    else
        echo -e "${RED}✗${NC} Grafana 无法访问"
    fi
else
    echo -e "${YELLOW}⚠${NC} 未配置 DOMAIN 环境变量,跳过网络检查"
fi

echo ""
echo "========================================="
echo "资源使用情况:"
echo "========================================="
echo ""

docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" | head -15

echo ""
echo "检查完成!"
