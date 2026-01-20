import os
import re
import logging
import requests
from typing import Optional


def validate_ipv4(ip: Optional[str]) -> bool:
    """验证 IPv4 地址格式"""
    if not ip:
        return False

    pattern = r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$'
    match = re.match(pattern, ip)

    if not match:
        return False

    # 检查每个数字是否在 0-255 范围内
    for group in match.groups():
        if int(group) > 255:
            return False

    return True


def detect_ipv4() -> str:
    """
    自动检测服务器公网 IPv4 地址
    尝试多个服务以提高可靠性
    """
    public_ip = os.getenv("PUBLIC_IP")
    if public_ip:
        if validate_ipv4(public_ip):
            return public_ip
        raise ValueError("PUBLIC_IP is set but not a valid IPv4 address")

    ip_services = [
        'https://api.ipify.org',
        'https://ifconfig.me/ip',
        'https://ip.sb'
    ]

    for service in ip_services:
        try:
            response = requests.get(service, timeout=10)
            response.raise_for_status()
            ip = response.text.strip()

            if validate_ipv4(ip):
                return ip
        except Exception as e:
            logging.warning(f"Failed to get IP from {service}: {e}")
            continue

    raise Exception("Failed to detect IPv4 address from all services")


def setup_logging(level: str = "INFO") -> logging.Logger:
    """
    配置日志系统
    输出 JSON 格式日志便于 Loki 采集
    """
    logger = logging.getLogger("dns-manager")
    logger.setLevel(getattr(logging, level.upper()))

    # 控制台处理器
    handler = logging.StreamHandler()
    handler.setLevel(getattr(logging, level.upper()))

    # JSON 格式
    formatter = logging.Formatter(
        '{"timestamp":"%(asctime)s","level":"%(levelname)s","message":"%(message)s"}',
        datefmt='%Y-%m-%dT%H:%M:%SZ'
    )
    handler.setFormatter(formatter)

    logger.addHandler(handler)
    return logger
