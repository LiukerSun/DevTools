#!/bin/bash

# 诊断脚本 - 检查部署状态和常见问题

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}"
cat << "EOF"
╔════════════════════════════════════════════════════╗
║                                                    ║
║                       诊断工具                      ║
║                                                    ║
╚════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"
echo ""

# 加载环境变量
if [ -f ".env" ]; then
    source .env
else
    echo -e "${RED}错误: .env 文件不存在${NC}"
    exit 1
fi

echo -e "${BLUE}═══ 1. 检查容器状态 ═══${NC}"
echo ""
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo ""

echo -e "${BLUE}═══ 2. 检查容器健康状态 ═══${NC}"
echo ""
for container in traefik postgres redis keycloak; do
    if docker ps --filter "name=$container" --format "{{.Names}}" | grep -q "$container"; then
        health=$(docker inspect --format='{{.State.Health.Status}}' $container 2>/dev/null || echo "no healthcheck")
        if [ "$health" = "healthy" ]; then
            echo -e "${GREEN}✓${NC} $container: $health"
        elif [ "$health" = "no healthcheck" ]; then
            echo -e "${YELLOW}⚠${NC} $container: no healthcheck configured"
        else
            echo -e "${RED}✗${NC} $container: $health"
        fi
    else
        echo -e "${RED}✗${NC} $container: not running"
    fi
done
echo ""

echo -e "${BLUE}═══ 3. 检查 Traefik 路由 ═══${NC}"
echo ""
if docker ps --filter "name=traefik" --format "{{.Names}}" | grep -q "traefik"; then
    echo "Traefik 发现的路由:"
    docker exec traefik traefik healthcheck --ping 2>/dev/null && echo -e "${GREEN}✓ Traefik ping 正常${NC}" || echo -e "${RED}✗ Traefik ping 失败${NC}"
    echo ""
    echo "查询 Traefik API 获取路由信息..."
    echo "(请访问 http://服务器IP:8080/api/http/routers 查看详细路由)"
    echo ""
else
    echo -e "${RED}✗ Traefik 容器未运行${NC}"
fi

echo -e "${BLUE}═══ 4. 检查 Docker 网络 ═══${NC}"
echo ""
for network in core_frontend core_backend core_monitoring; do
    if docker network ls | grep -q "$network"; then
        echo -e "${GREEN}✓${NC} $network 存在"
        containers=$(docker network inspect $network -f '{{range .Containers}}{{.Name}} {{end}}' 2>/dev/null)
        if [ ! -z "$containers" ]; then
            echo "   连接的容器: $containers"
        else
            echo -e "   ${YELLOW}⚠ 没有容器连接到此网络${NC}"
        fi
    else
        echo -e "${RED}✗${NC} $network 不存在"
    fi
done
echo ""

echo -e "${BLUE}═══ 5. 检查 DNS 解析 ═══${NC}"
echo ""
echo "你的域名: ${DOMAIN}"
echo "需要添加以下 DNS 记录到 Cloudflare:"
echo ""

# 获取服务器公网 IP
if command -v curl &> /dev/null; then
    PUBLIC_IP=$(curl -4 -s ifconfig.me 2>/dev/null || curl -4 -s icanhazip.com 2>/dev/null || echo "无法获取")
    echo -e "${CYAN}服务器公网 IP:${NC} $PUBLIC_IP"
else
    PUBLIC_IP="无法获取"
    echo -e "${YELLOW}⚠ 无法获取公网 IP,请手动检查${NC}"
fi
echo ""

echo -e "${YELLOW}必需的 DNS 记录:${NC}"
echo "  记录类型: A"
echo "  名称: traefik"
echo "  内容: $PUBLIC_IP"
echo "  代理状态: 仅DNS (关闭橙色云朵)"
echo ""
echo "  记录类型: A"
echo "  名称: auth"
echo "  内容: $PUBLIC_IP"
echo "  代理状态: 仅DNS (关闭橙色云朵)"
echo ""
echo "  记录类型: A"
echo "  名称: grafana"
echo "  内容: $PUBLIC_IP"
echo "  代理状态: 仅DNS (关闭橙色云朵)"
echo ""
echo "  记录类型: A"
echo "  名称: prometheus"
echo "  内容: $PUBLIC_IP"
echo "  代理状态: 仅DNS (关闭橙色云朵)"
echo ""

echo -e "${BLUE}═══ 6. 测试 DNS 解析 ═══${NC}"
echo ""
for subdomain in traefik auth grafana prometheus; do
    if command -v dig &> /dev/null; then
        resolved_ip=$(dig +short ${subdomain}.${DOMAIN} @1.1.1.1 2>/dev/null | head -n1)
    elif command -v nslookup &> /dev/null; then
        resolved_ip=$(nslookup ${subdomain}.${DOMAIN} 1.1.1.1 2>/dev/null | grep -A1 "Name:" | tail -n1 | awk '{print $2}')
    else
        resolved_ip="无法测试"
    fi

    if [ "$resolved_ip" = "$PUBLIC_IP" ]; then
        echo -e "${GREEN}✓${NC} ${subdomain}.${DOMAIN} → $resolved_ip"
    elif [ "$resolved_ip" = "无法测试" ]; then
        echo -e "${YELLOW}⚠${NC} ${subdomain}.${DOMAIN} → 无法测试 (安装 dig 或 nslookup)"
    elif [ -z "$resolved_ip" ]; then
        echo -e "${RED}✗${NC} ${subdomain}.${DOMAIN} → 未解析 (请添加 DNS 记录)"
    else
        echo -e "${YELLOW}⚠${NC} ${subdomain}.${DOMAIN} → $resolved_ip (不匹配服务器IP: $PUBLIC_IP)"
    fi
done
echo ""

echo -e "${BLUE}═══ 7. 检查 Traefik 配置 ═══${NC}"
echo ""
if docker ps --filter "name=traefik" --format "{{.Names}}" | grep -q "traefik"; then
    echo "Traefik 环境变量:"
    docker exec traefik env | grep -E "CF_API_EMAIL|CF_API_KEY" | sed 's/CF_API_KEY=.*/CF_API_KEY=***已设置***/'
    echo ""

    echo "检查 acme.json 文件:"
    if docker exec traefik ls -lh /acme.json 2>/dev/null; then
        size=$(docker exec traefik stat -c%s /acme.json 2>/dev/null || echo "0")
        if [ "$size" -gt 100 ]; then
            echo -e "${GREEN}✓ acme.json 已包含证书数据 ($size bytes)${NC}"
        else
            echo -e "${YELLOW}⚠ acme.json 很小 ($size bytes) - 可能还没有获取证书${NC}"
        fi
    else
        echo -e "${RED}✗ acme.json 不存在${NC}"
    fi
    echo ""
fi

echo -e "${BLUE}═══ 8. 检查容器日志错误 ═══${NC}"
echo ""
echo "Traefik 最近的错误日志:"
docker logs traefik --tail 20 2>&1 | grep -i "error\|fail\|warn" | tail -5 || echo "无错误"
echo ""

echo -e "${BLUE}═══ 9. 端口监听检查 ═══${NC}"
echo ""
if command -v netstat &> /dev/null; then
    echo "检查端口 80 和 443:"
    netstat -tlnp | grep -E ":80 |:443 " || echo "端口未监听"
elif command -v ss &> /dev/null; then
    echo "检查端口 80 和 443:"
    ss -tlnp | grep -E ":80 |:443 " || echo "端口未监听"
else
    echo -e "${YELLOW}⚠ netstat/ss 命令不可用,无法检查端口${NC}"
fi
echo ""

echo -e "${BLUE}═══ 诊断建议 ═══${NC}"
echo ""

# 检查是否是 DNS 问题
dns_issue=false
for subdomain in traefik auth grafana prometheus; do
    if command -v dig &> /dev/null; then
        resolved_ip=$(dig +short ${subdomain}.${DOMAIN} @1.1.1.1 2>/dev/null | head -n1)
    elif command -v nslookup &> /dev/null; then
        resolved_ip=$(nslookup ${subdomain}.${DOMAIN} 1.1.1.1 2>/dev/null | grep -A1 "Name:" | tail -n1 | awk '{print $2}')
    fi

    if [ -z "$resolved_ip" ] || [ "$resolved_ip" != "$PUBLIC_IP" ]; then
        dns_issue=true
        break
    fi
done

if [ "$dns_issue" = true ]; then
    echo -e "${YELLOW}⚠ DNS 配置问题:${NC}"
    echo "  1. 登录 Cloudflare Dashboard"
    echo "  2. 进入你的域名 ${DOMAIN}"
    echo "  3. 点击 'DNS' 标签"
    echo "  4. 添加上述列出的 A 记录"
    echo "  5. 确保 '代理状态' 显示为灰色云朵 (仅DNS)"
    echo ""
fi

if ! docker ps --filter "name=traefik" --format "{{.Names}}" | grep -q "traefik"; then
    echo -e "${RED}✗ Traefik 未运行:${NC}"
    echo "  运行: docker logs traefik"
    echo "  查看启动失败原因"
    echo ""
fi

# 检查 Keycloak 是否健康
if docker ps --filter "name=keycloak" --format "{{.Names}}" | grep -q "keycloak"; then
    health=$(docker inspect --format='{{.State.Health.Status}}' keycloak 2>/dev/null || echo "unknown")
    if [ "$health" != "healthy" ]; then
        echo -e "${YELLOW}⚠ Keycloak 未健康:${NC}"
        echo "  Keycloak 可能还在启动中 (首次启动需要 1-2 分钟)"
        echo "  运行: docker logs keycloak -f"
        echo "  等待看到 'Keycloak ... started'"
        echo ""
    fi
fi

echo -e "${CYAN}═══ 快速修复命令 ═══${NC}"
echo ""
echo "1. 查看 Traefik 详细日志:"
echo "   docker logs traefik -f"
echo ""
echo "2. 重启 Traefik (如果配置有问题):"
echo "   docker restart traefik"
echo ""
echo "3. 查看所有容器日志:"
echo "   cd core && docker compose --env-file ../.env -f docker-compose.single.yml logs -f"
echo ""
echo "4. 完全重新部署:"
echo "   cd core && docker compose --env-file ../.env -f docker-compose.single.yml down"
echo "   cd .. && sudo ./scripts/deploy-single.sh"
echo ""

echo -e "${BLUE}═══ 额外诊断 ═══${NC}"
echo ""
echo "访问以下地址获取更多信息:"
echo "  - Traefik API: http://$PUBLIC_IP:8080/api/rawdata"
echo "  - Traefik Dashboard: https://traefik.${DOMAIN} (如果 DNS 已配置)"
echo ""
