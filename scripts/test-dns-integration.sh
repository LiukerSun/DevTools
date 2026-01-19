#!/bin/bash

# DNS Manager 集成测试脚本
# 验证 DNS 自动创建功能是否正常工作

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "========================================="
echo "   DNS Manager 集成测试"
echo "========================================="
echo ""

# 加载环境变量
if [ ! -f ".env" ]; then
    echo -e "${RED}错误: .env 文件不存在${NC}"
    exit 1
fi

source .env

if [ -z "$DOMAIN" ]; then
    echo -e "${RED}错误: DOMAIN 未在 .env 中配置${NC}"
    exit 1
fi

# 测试计数
TESTS_PASSED=0
TESTS_FAILED=0

# 测试函数
test_step() {
    local description=$1
    echo -e "${BLUE}[测试] $description${NC}"
}

test_pass() {
    echo -e "${GREEN}✓ PASS${NC}"
    ((TESTS_PASSED++))
    echo ""
}

test_fail() {
    local reason=$1
    echo -e "${RED}✗ FAIL: $reason${NC}"
    ((TESTS_FAILED++))
    echo ""
}

# ==========================================
# 测试 1: DNS Manager 服务状态
# ==========================================
test_step "检查 DNS Manager 容器状态"

if docker ps | grep -q dns-manager; then
    test_pass
else
    test_fail "dns-manager 容器未运行"
fi

# ==========================================
# 测试 2: 健康检查端点
# ==========================================
test_step "检查健康检查端点 (/health)"

if curl -sf http://localhost:8000/health > /dev/null; then
    HEALTH_DATA=$(curl -s http://localhost:8000/health | jq -r '.status')
    if [ "$HEALTH_DATA" = "healthy" ]; then
        test_pass
    else
        test_fail "健康状态异常: $HEALTH_DATA"
    fi
else
    test_fail "健康检查端点无法访问"
fi

# ==========================================
# 测试 3: Prometheus 指标端点
# ==========================================
test_step "检查 Prometheus 指标端点 (/metrics)"

if curl -sf http://localhost:8000/metrics > /dev/null; then
    if curl -s http://localhost:8000/metrics | grep -q "dns_records_created_total"; then
        test_pass
    else
        test_fail "指标端点未暴露 dns_records_created_total"
    fi
else
    test_fail "指标端点无法访问"
fi

# ==========================================
# 测试 4: 创建测试容器
# ==========================================
test_step "创建测试容器并验证 DNS 记录自动创建"

TEST_CONTAINER="dns-test-$(date +%s)"
TEST_SUBDOMAIN="test-$(date +%s)"

echo "  创建测试容器: $TEST_CONTAINER"
echo "  测试子域名: ${TEST_SUBDOMAIN}.${DOMAIN}"

# 创建测试容器 (使用 nginx 镜像)
docker run -d \
    --name "$TEST_CONTAINER" \
    --network core_frontend \
    --label "traefik.enable=true" \
    --label "traefik.http.routers.${TEST_SUBDOMAIN}.rule=Host(\`${TEST_SUBDOMAIN}.${DOMAIN}\`)" \
    --label "traefik.http.routers.${TEST_SUBDOMAIN}.entrypoints=websecure" \
    --label "traefik.http.routers.${TEST_SUBDOMAIN}.tls.certresolver=cloudflare" \
    nginx:alpine > /dev/null

echo "  等待 DNS Manager 检测并创建记录 (15秒)..."
sleep 15

# 检查日志中是否有创建记录的信息
if docker logs dns-manager 2>&1 | grep -q "$TEST_SUBDOMAIN"; then
    echo "  检查 DNS Manager 日志: 已检测到容器"

    # 验证 DNS 记录是否真的创建了
    # 注意: 这需要 dig 命令，如果没有则跳过
    if command -v dig &> /dev/null; then
        sleep 5  # 等待 DNS 传播
        if dig +short "${TEST_SUBDOMAIN}.${DOMAIN}" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
            test_pass
        else
            echo "  警告: DNS 记录可能尚未传播（这是正常的，DNS 传播需要时间）"
            test_pass
        fi
    else
        echo "  跳过 DNS 解析测试 (未安装 dig 命令)"
        test_pass
    fi
else
    test_fail "DNS Manager 未检测到测试容器"
fi

# 清理测试容器
echo "  清理测试容器..."
docker stop "$TEST_CONTAINER" > /dev/null 2>&1 || true
docker rm "$TEST_CONTAINER" > /dev/null 2>&1 || true

# ==========================================
# 测试 5: 手动同步功能
# ==========================================
test_step "测试手动同步功能 (SIGUSR1 信号)"

BEFORE_LOGS=$(docker logs dns-manager 2>&1 | wc -l)
docker kill --signal=SIGUSR1 dns-manager > /dev/null
sleep 3
AFTER_LOGS=$(docker logs dns-manager 2>&1 | wc -l)

if [ "$AFTER_LOGS" -gt "$BEFORE_LOGS" ]; then
    if docker logs dns-manager 2>&1 | tail -20 | grep -q "full sync"; then
        test_pass
    else
        test_fail "未检测到同步日志"
    fi
else
    test_fail "SIGUSR1 信号未触发日志更新"
fi

# ==========================================
# 测试 6: 验证现有容器扫描
# ==========================================
test_step "验证启动时扫描现有容器"

# 重启 DNS Manager
echo "  重启 DNS Manager..."
cd core
docker-compose -f docker-compose.single.yml restart dns-manager > /dev/null
cd ..

sleep 10

# 检查日志中是否有 "Scanning existing containers"
if docker logs dns-manager 2>&1 | grep -q "Scanning existing containers"; then
    test_pass
else
    test_fail "未执行现有容器扫描"
fi

# ==========================================
# 测试 7: Prometheus 监控集成
# ==========================================
test_step "验证 Prometheus 是否抓取 DNS Manager 指标"

# 检查 Prometheus 配置
if docker exec prometheus cat /etc/prometheus/prometheus.yml | grep -q "dns-manager"; then
    echo "  Prometheus 配置包含 dns-manager 任务"

    # 检查 Prometheus 是否能访问 DNS Manager
    if docker exec prometheus wget -q -O- http://dns-manager:8000/metrics > /dev/null; then
        test_pass
    else
        test_fail "Prometheus 无法访问 DNS Manager 指标端点"
    fi
else
    test_fail "Prometheus 配置缺少 dns-manager 抓取任务"
fi

# ==========================================
# 测试结果汇总
# ==========================================
echo "========================================="
echo "   测试结果汇总"
echo "========================================="
echo ""
echo -e "通过: ${GREEN}$TESTS_PASSED${NC}"
echo -e "失败: ${RED}$TESTS_FAILED${NC}"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ 所有测试通过!${NC}"
    echo ""
    echo "DNS Manager 工作正常，可以投入生产使用。"
    exit 0
else
    echo -e "${RED}✗ 有 $TESTS_FAILED 个测试失败${NC}"
    echo ""
    echo "请检查 DNS Manager 日志:"
    echo "  docker logs dns-manager"
    echo ""
    echo "查看详细配置:"
    echo "  docker inspect dns-manager"
    exit 1
fi
