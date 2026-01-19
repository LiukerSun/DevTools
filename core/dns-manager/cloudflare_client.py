import logging
from typing import Optional
from CloudFlare import CloudFlare
from tenacity import retry, stop_after_attempt, wait_exponential


logger = logging.getLogger("dns-manager")


class CloudflareClient:
    """Cloudflare DNS 管理客户端"""

    def __init__(
        self,
        domain: str,
        api_token: Optional[str] = None,
        api_email: Optional[str] = None,
        api_key: Optional[str] = None
    ):
        self.domain = domain
        self.zone_id = None

        # 验证凭证
        if api_token:
            self.cf = CloudFlare(token=api_token)
        elif api_email and api_key:
            self.cf = CloudFlare(email=api_email, key=api_key)
        else:
            raise ValueError("Cloudflare credentials required: api_token or (api_email + api_key)")

        logger.info(f"Initialized Cloudflare client for domain: {domain}")

    def _get_zone_id(self) -> str:
        """获取域名的 Zone ID"""
        if self.zone_id:
            return self.zone_id

        try:
            zones = self.cf.zones.get(params={'name': self.domain})
            if not zones:
                raise Exception(f"Zone not found for domain: {self.domain}")

            self.zone_id = zones[0]['id']
            logger.info(f"Found zone ID: {self.zone_id}")
            return self.zone_id
        except Exception as e:
            logger.error(f"Failed to get zone ID: {e}")
            raise

    def check_dns_exists(self, subdomain: str) -> bool:
        """
        检查 DNS A 记录是否已存在

        Args:
            subdomain: 子域名（不包含主域名）

        Returns:
            True 如果记录存在，否则 False
        """
        zone_id = self._get_zone_id()
        full_domain = f"{subdomain}.{self.domain}"

        try:
            records = self.cf.zones.dns_records.get(
                zone_id,
                params={'type': 'A', 'name': full_domain}
            )
            exists = len(records) > 0
            logger.info(f"DNS record for {full_domain}: {'exists' if exists else 'not found'}")
            return exists
        except Exception as e:
            logger.error(f"Failed to check DNS record: {e}")
            return False

    @retry(
        stop=stop_after_attempt(5),
        wait=wait_exponential(multiplier=1, min=1, max=16),
        reraise=True
    )
    def create_dns_record(
        self,
        subdomain: str,
        ip: str,
        ttl: int = 300,
        proxied: bool = False
    ) -> bool:
        """
        创建 DNS A 记录（带重试）

        Args:
            subdomain: 子域名
            ip: IPv4 地址
            ttl: TTL 值（秒）
            proxied: 是否启用 Cloudflare 代理

        Returns:
            True 如果创建成功
        """
        zone_id = self._get_zone_id()
        full_domain = f"{subdomain}.{self.domain}"

        data = {
            'type': 'A',
            'name': full_domain,
            'content': ip,
            'ttl': ttl,
            'proxied': proxied
        }

        try:
            result = self.cf.zones.dns_records.post(zone_id, data=data)
            logger.info(f"Created DNS record: {full_domain} -> {ip} (ID: {result['id']})")
            return True
        except Exception as e:
            logger.error(f"Failed to create DNS record for {full_domain}: {e}")
            raise

    def list_dns_records(self) -> list:
        """列出所有 A 记录（用于调试）"""
        zone_id = self._get_zone_id()

        try:
            records = self.cf.zones.dns_records.get(
                zone_id,
                params={'type': 'A'}
            )
            return records
        except Exception as e:
            logger.error(f"Failed to list DNS records: {e}")
            return []
