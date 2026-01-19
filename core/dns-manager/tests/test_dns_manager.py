import pytest
from unittest.mock import MagicMock, patch
from dns_manager import DNSManager, create_health_app


@pytest.fixture
def mock_env(monkeypatch):
    monkeypatch.setenv("DOMAIN", "example.com")
    monkeypatch.setenv("CF_DNS_API_TOKEN", "test-token")
    monkeypatch.setenv("LOG_LEVEL", "INFO")


@patch('dns_manager.CloudflareClient')
@patch('dns_manager.detect_ipv4')
def test_dns_manager_init(mock_detect_ip, mock_cf_client, mock_env):
    mock_detect_ip.return_value = "203.0.113.42"
    mock_cf = MagicMock()
    mock_cf_client.return_value = mock_cf

    manager = DNSManager()

    assert manager.domain == "example.com"
    assert manager.server_ip == "203.0.113.42"
    assert manager.cf_client == mock_cf


@patch('dns_manager.CloudflareClient')
@patch('dns_manager.detect_ipv4')
def test_handle_container_start_new_record(mock_detect_ip, mock_cf_client, mock_env):
    mock_detect_ip.return_value = "203.0.113.42"
    mock_cf = MagicMock()
    mock_cf.check_dns_exists.return_value = False
    mock_cf.create_dns_record.return_value = True
    mock_cf_client.return_value = mock_cf

    manager = DNSManager()
    manager._handle_container_start("myapp", "myapp-container")

    mock_cf.check_dns_exists.assert_called_once_with("myapp")
    mock_cf.create_dns_record.assert_called_once_with("myapp", "203.0.113.42")


@patch('dns_manager.CloudflareClient')
@patch('dns_manager.detect_ipv4')
def test_handle_container_start_existing_record(mock_detect_ip, mock_cf_client, mock_env):
    mock_detect_ip.return_value = "203.0.113.42"
    mock_cf = MagicMock()
    mock_cf.check_dns_exists.return_value = True
    mock_cf_client.return_value = mock_cf

    manager = DNSManager()
    manager._handle_container_start("myapp", "myapp-container")

    mock_cf.check_dns_exists.assert_called_once_with("myapp")
    mock_cf.create_dns_record.assert_not_called()


def test_health_app():
    app = create_health_app()
    client = app.test_client()

    response = client.get('/health')
    assert response.status_code == 200

    data = response.get_json()
    assert data['status'] == 'healthy'
    assert 'uptime' in data
    assert 'stats' in data
