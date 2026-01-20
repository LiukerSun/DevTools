import pytest
from unittest.mock import patch, MagicMock
from utils import detect_ipv4, setup_logging, validate_ipv4


def test_validate_ipv4_valid():
    assert validate_ipv4("192.168.1.1") == True
    assert validate_ipv4("8.8.8.8") == True
    assert validate_ipv4("10.0.0.1") == True


def test_validate_ipv4_invalid():
    assert validate_ipv4("256.1.1.1") == False
    assert validate_ipv4("not.an.ip") == False
    assert validate_ipv4("") == False
    assert validate_ipv4(None) == False


@patch('requests.get')
def test_detect_ipv4_success(mock_get):
    mock_response = MagicMock()
    mock_response.text = "203.0.113.42"
    mock_response.raise_for_status = MagicMock()
    mock_get.return_value = mock_response

    ip = detect_ipv4()
    assert ip == "203.0.113.42"


@patch('requests.get')
def test_detect_ipv4_fallback(mock_get):
    # 第一个服务失败，第二个成功
    mock_get.side_effect = [
        Exception("Connection failed"),
        MagicMock(text="203.0.113.42", raise_for_status=MagicMock())
    ]

    ip = detect_ipv4()
    assert ip == "203.0.113.42"


@patch('requests.get')
def test_detect_ipv4_all_fail(mock_get):
    mock_get.side_effect = Exception("Network error")

    with pytest.raises(Exception, match="Failed to detect"):
        detect_ipv4()


def test_detect_ipv4_public_ip_env(monkeypatch):
    monkeypatch.setenv("PUBLIC_IP", "203.0.113.99")
    ip = detect_ipv4()
    assert ip == "203.0.113.99"


def test_detect_ipv4_public_ip_invalid(monkeypatch):
    monkeypatch.setenv("PUBLIC_IP", "2001:db8::1")
    with pytest.raises(ValueError, match="PUBLIC_IP is set"):
        detect_ipv4()


def test_setup_logging():
    logger = setup_logging("INFO")
    assert logger.level == 20  # INFO level
    assert logger.name == "dns-manager"
