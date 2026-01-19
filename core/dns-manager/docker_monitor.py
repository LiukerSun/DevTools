import re
import logging
import docker
from typing import Callable, Optional


logger = logging.getLogger("dns-manager")


def extract_domain_from_labels(labels: dict, base_domain: str) -> Optional[str]:
    """
    从 Traefik 标签中提取子域名

    Args:
        labels: 容器标签字典
        base_domain: 基础域名（如 example.com）

    Returns:
        子域名（不包含基础域名），如果未找到则返回 None
    """
    # 检查是否启用 Traefik
    if labels.get("traefik.enable") != "true":
        return None

    # 查找所有 Host 规则
    pattern = r'traefik\.http\.routers\..+\.rule'

    for key, value in labels.items():
        if re.match(pattern, key):
            # 提取 Host(`domain`) 或 Host(\`domain\`)
            host_match = re.search(r'Host\([`\\]+([^`\\]+)[`\\]+\)', value)
            if host_match:
                full_domain = host_match.group(1)

                # 检查是否是泛域名
                if full_domain.startswith('*'):
                    logger.debug(f"Skipping wildcard domain: {full_domain}")
                    continue

                # 检查是否匹配基础域名
                if full_domain.endswith(f".{base_domain}"):
                    subdomain = full_domain[:-len(base_domain)-1]
                    return subdomain
                elif full_domain == base_domain:
                    # 主域名，使用 @ 或空字符串
                    return "@"

    return None


class DockerMonitor:
    """Docker 容器事件监听器"""

    def __init__(self, domain: str, on_container_start: Callable[[str, str], None]):
        """
        初始化 Docker 监听器

        Args:
            domain: 基础域名
            on_container_start: 容器启动回调函数 (subdomain, container_name) -> None
        """
        self.domain = domain
        self.on_container_start = on_container_start
        self.client = docker.from_env()
        logger.info("Docker monitor initialized")

    def scan_existing_containers(self):
        """扫描所有现有容器"""
        logger.info("Scanning existing containers...")

        try:
            containers = self.client.containers.list()
            logger.info(f"Found {len(containers)} running containers")

            for container in containers:
                subdomain = extract_domain_from_labels(container.labels, self.domain)
                if subdomain:
                    logger.info(f"Found existing container: {container.name} -> {subdomain}.{self.domain}")
                    self.on_container_start(subdomain, container.name)
        except Exception as e:
            logger.error(f"Failed to scan containers: {e}")

    def listen(self):
        """
        监听 Docker 事件
        阻塞调用，持续运行
        """
        logger.info("Starting Docker event listener...")

        try:
            # 监听容器启动事件
            for event in self.client.events(decode=True, filters={'type': 'container', 'event': 'start'}):
                self._handle_event(event)
        except Exception as e:
            logger.error(f"Docker event listener error: {e}")
            raise

    def _handle_event(self, event: dict):
        """处理单个 Docker 事件"""
        try:
            # 检查是否启用 Traefik
            if event.get('Actor', {}).get('Attributes', {}).get('traefik.enable') != 'true':
                return

            container_id = event.get('Actor', {}).get('ID')
            if not container_id:
                logger.debug("Event missing container ID, skipping")
                return

            container = self.client.containers.get(container_id)

            subdomain = extract_domain_from_labels(container.labels, self.domain)
            if subdomain:
                logger.info(f"Container started: {container.name} -> {subdomain}.{self.domain}")
                self.on_container_start(subdomain, container.name)
        except Exception as e:
            logger.error(f"Failed to handle container event: {e}")
