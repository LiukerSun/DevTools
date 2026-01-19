#!/usr/bin/env python3
import os
import time
import signal
import logging
from threading import Thread
from flask import Flask, jsonify
from prometheus_client import Counter, Gauge, generate_latest

from utils import detect_ipv4, setup_logging
from cloudflare_client import CloudflareClient
from docker_monitor import DockerMonitor


# Prometheus 指标
dns_records_created = Counter('dns_records_created_total', 'Total DNS records created')
dns_api_errors = Counter('dns_api_errors_total', 'Total DNS API errors')
dns_containers_monitored = Gauge('dns_containers_monitored', 'Number of containers monitored')

# 全局状态
stats = {
    'start_time': time.time(),
    'containers_monitored': 0,
    'records_created': 0,
    'api_errors': 0
}


def create_health_app():
    """创建健康检查 Flask 应用"""
    app = Flask(__name__)

    @app.route('/health')
    def health():
        return jsonify({
            'status': 'healthy',
            'uptime': int(time.time() - stats['start_time']),
            'stats': {
                'containers_monitored': stats['containers_monitored'],
                'dns_records_created': stats['records_created'],
                'api_errors': stats['api_errors']
            }
        })

    @app.route('/metrics')
    def metrics():
        return generate_latest()

    @app.route('/sync', methods=['POST'])
    def sync():
        # 手动触发同步的端点
        return jsonify({'message': 'Sync triggered'}), 200

    return app


class DNSManager:
    """DNS 自动管理主程序"""

    def __init__(self):
        # 加载配置
        self.domain = os.getenv('DOMAIN')
        cf_token = os.getenv('CF_DNS_API_TOKEN')
        cf_email = os.getenv('CF_API_EMAIL')
        cf_key = os.getenv('CF_API_KEY')
        log_level = os.getenv('LOG_LEVEL', 'INFO')

        # 设置日志
        self.logger = setup_logging(log_level)

        # 验证配置
        if not self.domain:
            raise ValueError("DOMAIN environment variable is required")

        # 检测服务器 IP
        self.logger.info("Detecting server IPv4 address...")
        self.server_ip = detect_ipv4()
        self.logger.info(f"Server IP: {self.server_ip}")

        # 初始化 Cloudflare 客户端
        self.cf_client = CloudflareClient(
            domain=self.domain,
            api_token=cf_token,
            api_email=cf_email,
            api_key=cf_key
        )

        # 初始化 Docker 监听器
        self.docker_monitor = DockerMonitor(
            domain=self.domain,
            on_container_start=self._handle_container_start
        )

        self.logger.info("DNS Manager initialized")

    def _handle_container_start(self, subdomain: str, container_name: str):
        """
        处理容器启动事件

        Args:
            subdomain: 子域名
            container_name: 容器名称
        """
        try:
            stats['containers_monitored'] += 1
            dns_containers_monitored.set(stats['containers_monitored'])

            # 检查 DNS 记录是否已存在
            if self.cf_client.check_dns_exists(subdomain):
                self.logger.info(f"DNS record already exists for {subdomain}.{self.domain}, skipping")
                return

            # 创建 DNS 记录
            self.logger.info(f"Creating DNS record: {subdomain}.{self.domain} -> {self.server_ip}")
            success = self.cf_client.create_dns_record(subdomain, self.server_ip)

            if success:
                stats['records_created'] += 1
                dns_records_created.inc()
                self.logger.info(f"Successfully created DNS record for {subdomain}.{self.domain}")
            else:
                stats['api_errors'] += 1
                dns_api_errors.inc()
                self.logger.error(f"Failed to create DNS record for {subdomain}.{self.domain}")
        except Exception as e:
            stats['api_errors'] += 1
            dns_api_errors.inc()
            self.logger.error(f"Error handling container {container_name}: {e}")

    def run(self):
        """启动 DNS Manager"""
        # 扫描现有容器
        self.logger.info("Scanning existing containers...")
        self.docker_monitor.scan_existing_containers()

        # 启动健康检查服务器（后台线程）
        health_app = create_health_app()
        health_thread = Thread(
            target=lambda: health_app.run(host='0.0.0.0', port=8000, debug=False),
            daemon=True
        )
        health_thread.start()
        self.logger.info("Health check server started on port 8000")

        # 注册信号处理器
        signal.signal(signal.SIGUSR1, self._handle_sync_signal)
        signal.signal(signal.SIGTERM, self._handle_term_signal)

        # 开始监听 Docker 事件（阻塞）
        self.logger.info("Starting event listener...")
        self.docker_monitor.listen()

    def _handle_sync_signal(self, signum, frame):
        """处理 SIGUSR1 信号：触发全量同步"""
        self.logger.info("Received SIGUSR1, triggering full sync...")
        self.docker_monitor.scan_existing_containers()

    def _handle_term_signal(self, signum, frame):
        """处理 SIGTERM 信号：优雅关闭"""
        self.logger.info("Received SIGTERM, shutting down...")
        exit(0)


if __name__ == '__main__':
    manager = DNSManager()
    manager.run()
