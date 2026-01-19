import pytest
from unittest.mock import MagicMock, patch
from docker_monitor import DockerMonitor, extract_domain_from_labels


def test_extract_domain_from_labels_simple():
    labels = {
        "traefik.enable": "true",
        "traefik.http.routers.myapp.rule": "Host(`myapp.example.com`)"
    }
    domain = extract_domain_from_labels(labels, "example.com")
    assert domain == "myapp"


def test_extract_domain_from_labels_escaped():
    labels = {
        "traefik.enable": "true",
        "traefik.http.routers.test.rule": "Host(\\`test.example.com\\`)"
    }
    domain = extract_domain_from_labels(labels, "example.com")
    assert domain == "test"


def test_extract_domain_from_labels_multiple_routers():
    labels = {
        "traefik.enable": "true",
        "traefik.http.routers.app1.rule": "Host(`app1.example.com`)",
        "traefik.http.routers.app2.rule": "Host(`app2.example.com`)"
    }
    # 应该返回第一个匹配的
    domain = extract_domain_from_labels(labels, "example.com")
    assert domain in ["app1", "app2"]


def test_extract_domain_from_labels_wrong_domain():
    labels = {
        "traefik.enable": "true",
        "traefik.http.routers.myapp.rule": "Host(`myapp.other.com`)"
    }
    domain = extract_domain_from_labels(labels, "example.com")
    assert domain is None


def test_extract_domain_from_labels_no_traefik():
    labels = {
        "com.example.app": "myapp"
    }
    domain = extract_domain_from_labels(labels, "example.com")
    assert domain is None


def test_extract_domain_from_labels_wildcard():
    labels = {
        "traefik.enable": "true",
        "traefik.http.routers.myapp.rule": "Host(`*.example.com`)"
    }
    # 应该过滤掉泛域名
    domain = extract_domain_from_labels(labels, "example.com")
    assert domain is None


@patch('docker.from_env')
def test_docker_monitor_init(mock_docker):
    mock_client = MagicMock()
    mock_docker.return_value = mock_client

    monitor = DockerMonitor("example.com", lambda x, y: None)
    assert monitor.domain == "example.com"
    assert monitor.client == mock_client


@patch('docker.from_env')
def test_scan_existing_containers(mock_docker):
    mock_client = MagicMock()
    mock_docker.return_value = mock_client

    # 模拟容器列表
    mock_container = MagicMock()
    mock_container.name = "test-app"
    mock_container.labels = {
        "traefik.enable": "true",
        "traefik.http.routers.test.rule": "Host(`test.example.com`)"
    }
    mock_client.containers.list.return_value = [mock_container]

    callback_called = []
    def callback(subdomain, container_name):
        callback_called.append((subdomain, container_name))

    monitor = DockerMonitor("example.com", callback)
    monitor.scan_existing_containers()

    assert len(callback_called) == 1
    assert callback_called[0] == ("test", "test-app")


@patch('docker.from_env')
def test_handle_container_start(mock_docker):
    mock_client = MagicMock()
    mock_docker.return_value = mock_client

    mock_container = MagicMock()
    mock_container.name = "new-app"
    mock_container.labels = {
        "traefik.enable": "true",
        "traefik.http.routers.new.rule": "Host(`new.example.com`)"
    }
    mock_client.containers.get.return_value = mock_container

    callback_called = []
    def callback(subdomain, container_name):
        callback_called.append((subdomain, container_name))

    monitor = DockerMonitor("example.com", callback)

    # 模拟容器启动事件
    event = {
        "status": "start",
        "id": "container123",
        "Actor": {
            "Attributes": {
                "traefik.enable": "true"
            }
        }
    }

    monitor._handle_event(event)

    assert len(callback_called) == 1
    assert callback_called[0] == ("new", "new-app")
