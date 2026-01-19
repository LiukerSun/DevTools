import pytest
from unittest.mock import MagicMock, patch
from cloudflare_client import CloudflareClient


@pytest.fixture
def mock_cf_token():
    return "test-api-token"


@pytest.fixture
def mock_domain():
    return "example.com"


@pytest.fixture
def client(mock_cf_token, mock_domain):
    return CloudflareClient(
        api_token=mock_cf_token,
        domain=mock_domain
    )


def test_init_with_token(mock_cf_token, mock_domain):
    client = CloudflareClient(api_token=mock_cf_token, domain=mock_domain)
    assert client.domain == mock_domain
    assert client.zone_id is None


def test_init_with_email_key(mock_domain):
    client = CloudflareClient(
        api_email="test@example.com",
        api_key="test-key",
        domain=mock_domain
    )
    assert client.domain == mock_domain


def test_init_missing_credentials(mock_domain):
    with pytest.raises(ValueError, match="Cloudflare credentials required"):
        CloudflareClient(domain=mock_domain)


@patch('cloudflare_client.CloudFlare')
def test_get_zone_id_success(mock_cf_class, client):
    mock_cf = MagicMock()
    mock_cf_class.return_value = mock_cf
    mock_cf.zones.get.return_value = [
        {"id": "zone123", "name": "example.com"}
    ]

    zone_id = client._get_zone_id()
    assert zone_id == "zone123"


@patch('cloudflare_client.CloudFlare')
def test_get_zone_id_not_found(mock_cf_class, client):
    mock_cf = MagicMock()
    mock_cf_class.return_value = mock_cf
    mock_cf.zones.get.return_value = []

    with pytest.raises(Exception, match="Zone not found"):
        client._get_zone_id()


@patch('cloudflare_client.CloudFlare')
def test_check_dns_exists_true(mock_cf_class, client):
    mock_cf = MagicMock()
    mock_cf_class.return_value = mock_cf
    client.zone_id = "zone123"
    mock_cf.zones.dns_records.get.return_value = [
        {"type": "A", "name": "test.example.com"}
    ]

    exists = client.check_dns_exists("test")
    assert exists == True


@patch('cloudflare_client.CloudFlare')
def test_check_dns_exists_false(mock_cf_class, client):
    mock_cf = MagicMock()
    mock_cf_class.return_value = mock_cf
    client.zone_id = "zone123"
    mock_cf.zones.dns_records.get.return_value = []

    exists = client.check_dns_exists("test")
    assert exists == False


@patch('cloudflare_client.CloudFlare')
def test_create_dns_record_success(mock_cf_class, client):
    mock_cf = MagicMock()
    mock_cf_class.return_value = mock_cf
    client.zone_id = "zone123"
    mock_cf.zones.dns_records.post.return_value = {"id": "record123"}

    result = client.create_dns_record("test", "192.168.1.1")
    assert result == True


@patch('cloudflare_client.CloudFlare')
def test_create_dns_record_with_retry(mock_cf_class, client):
    mock_cf = MagicMock()
    mock_cf_class.return_value = mock_cf
    client.zone_id = "zone123"

    # 第一次失败，第二次成功
    mock_cf.zones.dns_records.post.side_effect = [
        Exception("Rate limit"),
        {"id": "record123"}
    ]

    result = client.create_dns_record("test", "192.168.1.1")
    assert result == True
