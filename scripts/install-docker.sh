#!/bin/bash

# Docker 和 Docker Compose 自动安装脚本
# 支持: Ubuntu, Debian, CentOS, Rocky Linux, Fedora

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}"
cat << "EOF"
╔════════════════════════════════════════════════════╗
║                                                    ║
║         Docker 自动安装脚本                         ║
║                                                    ║
╚════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"
echo ""

# 检查是否为 root 用户
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}请使用 root 用户或 sudo 运行此脚本${NC}"
    exit 1
fi

# 检测操作系统
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
    else
        echo -e "${RED}无法检测操作系统类型${NC}"
        exit 1
    fi

    echo -e "${YELLOW}检测到操作系统: ${OS} ${VER}${NC}"
}

# 检查 Docker 是否已安装
check_docker() {
    if command -v docker &> /dev/null; then
        DOCKER_VERSION=$(docker --version | awk '{print $3}' | sed 's/,//')
        echo -e "${GREEN}✓ Docker 已安装 (版本: ${DOCKER_VERSION})${NC}"
        return 0
    else
        echo -e "${YELLOW}Docker 未安装,准备安装...${NC}"
        return 1
    fi
}

# 检查 Docker Compose 是否已安装
check_docker_compose() {
    if docker compose version &> /dev/null; then
        COMPOSE_VERSION=$(docker compose version | awk '{print $4}')
        echo -e "${GREEN}✓ Docker Compose 已安装 (版本: ${COMPOSE_VERSION})${NC}"
        return 0
    elif command -v docker-compose &> /dev/null; then
        COMPOSE_VERSION=$(docker-compose --version | awk '{print $4}' | sed 's/,//')
        echo -e "${GREEN}✓ Docker Compose (standalone) 已安装 (版本: ${COMPOSE_VERSION})${NC}"
        return 0
    else
        echo -e "${YELLOW}Docker Compose 未安装,准备安装...${NC}"
        return 1
    fi
}

# 为 Ubuntu/Debian 安装 Docker
install_docker_ubuntu() {
    echo -e "${YELLOW}为 Ubuntu/Debian 安装 Docker...${NC}"

    # 更新包索引
    apt-get update

    # 安装依赖
    apt-get install -y \
        ca-certificates \
        curl \
        gnupg \
        lsb-release

    # 添加 Docker 官方 GPG 密钥
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/${OS}/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    # 添加 Docker 仓库
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${OS} \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    # 安装 Docker
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    echo -e "${GREEN}✓ Docker 安装完成${NC}"
}

# 为 CentOS/RHEL/Rocky Linux 安装 Docker
install_docker_centos() {
    echo -e "${YELLOW}为 CentOS/RHEL/Rocky Linux 安装 Docker...${NC}"

    # 安装依赖
    yum install -y yum-utils

    # 添加 Docker 仓库
    yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

    # 安装 Docker
    yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    echo -e "${GREEN}✓ Docker 安装完成${NC}"
}

# 为 Fedora 安装 Docker
install_docker_fedora() {
    echo -e "${YELLOW}为 Fedora 安装 Docker...${NC}"

    # 安装依赖
    dnf -y install dnf-plugins-core

    # 添加 Docker 仓库
    dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo

    # 安装 Docker
    dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    echo -e "${GREEN}✓ Docker 安装完成${NC}"
}

# 配置 Docker 守护进程
configure_docker() {
    echo -e "${YELLOW}配置 Docker 守护进程...${NC}"

    mkdir -p /etc/docker

    # 创建 daemon.json 配置文件
    cat > /etc/docker/daemon.json <<EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "registry-mirrors": [
    "https://docker.mirrors.ustc.edu.cn",
    "https://mirror.ccs.tencentyun.com"
  ]
}
EOF

    echo -e "${GREEN}✓ Docker 配置完成${NC}"
}

# 启动 Docker 服务
start_docker() {
    echo -e "${YELLOW}启动 Docker 服务...${NC}"

    systemctl enable docker
    systemctl start docker

    # 验证 Docker 运行状态
    if systemctl is-active --quiet docker; then
        echo -e "${GREEN}✓ Docker 服务已启动${NC}"
    else
        echo -e "${RED}✗ Docker 服务启动失败${NC}"
        exit 1
    fi
}

# 添加当前用户到 docker 组
add_user_to_docker_group() {
    # 获取实际运行脚本的用户（即使通过 sudo）
    if [ -n "$SUDO_USER" ]; then
        ACTUAL_USER=$SUDO_USER
    else
        ACTUAL_USER=$(whoami)
    fi

    if [ "$ACTUAL_USER" != "root" ]; then
        echo -e "${YELLOW}将用户 ${ACTUAL_USER} 添加到 docker 组...${NC}"
        usermod -aG docker $ACTUAL_USER
        echo -e "${GREEN}✓ 用户已添加到 docker 组${NC}"
        echo -e "${YELLOW}注意: 需要注销并重新登录才能使用 docker 命令 (无需 sudo)${NC}"
    fi
}

# 验证安装
verify_installation() {
    echo -e "${YELLOW}验证 Docker 安装...${NC}"
    echo ""

    # 显示 Docker 版本
    docker --version

    # 显示 Docker Compose 版本
    if docker compose version &> /dev/null; then
        docker compose version
    elif command -v docker-compose &> /dev/null; then
        docker-compose --version
    fi

    # 运行测试容器
    echo ""
    echo -e "${YELLOW}运行测试容器...${NC}"
    if docker run --rm hello-world &> /dev/null; then
        echo -e "${GREEN}✓ Docker 运行正常${NC}"
    else
        echo -e "${RED}✗ Docker 测试失败${NC}"
        exit 1
    fi
}

# 主安装流程
main() {
    echo -e "${BLUE}═══ 开始安装 Docker ═══${NC}"
    echo ""

    # 检测操作系统
    detect_os
    echo ""

    # 检查 Docker
    if check_docker; then
        DOCKER_INSTALLED=true
    else
        DOCKER_INSTALLED=false
    fi

    # 检查 Docker Compose
    if check_docker_compose; then
        COMPOSE_INSTALLED=true
    else
        COMPOSE_INSTALLED=false
    fi

    echo ""

    # 如果都已安装,询问是否重新安装
    if [ "$DOCKER_INSTALLED" = true ] && [ "$COMPOSE_INSTALLED" = true ]; then
        read -p "Docker 和 Docker Compose 已安装,是否重新安装? [y/N]: " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${GREEN}跳过安装${NC}"
            exit 0
        fi
    fi

    # 根据操作系统选择安装方法
    if [ "$DOCKER_INSTALLED" = false ]; then
        case $OS in
            ubuntu|debian)
                install_docker_ubuntu
                ;;
            centos|rhel|rocky)
                install_docker_centos
                ;;
            fedora)
                install_docker_fedora
                ;;
            *)
                echo -e "${RED}不支持的操作系统: ${OS}${NC}"
                echo -e "${YELLOW}尝试使用通用安装脚本...${NC}"
                curl -fsSL https://get.docker.com | bash
                ;;
        esac

        # 配置 Docker
        configure_docker

        # 启动 Docker
        start_docker
    fi

    # 添加用户到 docker 组
    add_user_to_docker_group

    echo ""
    echo -e "${BLUE}═══ 验证安装 ═══${NC}"
    echo ""

    # 验证安装
    verify_installation

    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                                                    ║${NC}"
    echo -e "${GREEN}║           Docker 安装完成!                          ║${NC}"
    echo -e "${GREEN}║                                                    ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════╝${NC}"
    echo ""

    echo -e "${YELLOW}已安装组件:${NC}"
    echo "  ✓ Docker Engine"
    echo "  ✓ Docker Compose Plugin"
    echo "  ✓ Docker Buildx Plugin"
    echo ""

    echo -e "${YELLOW}配置优化:${NC}"
    echo "  ✓ 日志轮转 (最多 3 个文件,每个 100MB)"
    echo "  ✓ 存储驱动 (overlay2)"
    echo "  ✓ 镜像加速 (国内镜像源)"
    echo ""

    if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
        echo -e "${YELLOW}下一步:${NC}"
        echo "  1. 注销并重新登录,使 docker 组权限生效"
        echo "  2. 或者运行: newgrp docker"
        echo "  3. 然后可以无需 sudo 使用 docker 命令"
        echo ""
    fi

    echo -e "${YELLOW}验证命令:${NC}"
    echo "  docker --version"
    echo "  docker compose version"
    echo "  docker run hello-world"
    echo ""
}

# 执行主流程
main
