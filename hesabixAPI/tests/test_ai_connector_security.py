import pytest

from app.core.responses import ApiError
from app.services.ai.ai_connector_service import _validate_connector_url


def test_connector_url_allows_public_https(monkeypatch):
    monkeypatch.setattr(
        "app.services.ai.ai_connector_service.socket.getaddrinfo",
        lambda *args, **kwargs: [(None, None, None, "", ("93.184.216.34", 443))],
    )

    assert _validate_connector_url("https://example.com/api?q={{term}}") == (
        "https://example.com/api?q={{term}}"
    )


def test_connector_url_blocks_localhost():
    with pytest.raises(ApiError):
        _validate_connector_url("http://localhost:8000/internal")


def test_connector_url_blocks_private_resolved_ip(monkeypatch):
    monkeypatch.setattr(
        "app.services.ai.ai_connector_service.socket.getaddrinfo",
        lambda *args, **kwargs: [(None, None, None, "", ("10.0.0.5", 443))],
    )

    with pytest.raises(ApiError):
        _validate_connector_url("https://api.example.com/data")


def test_connector_url_blocks_ipv6_link_local(monkeypatch):
    monkeypatch.setattr(
        "app.services.ai.ai_connector_service.socket.getaddrinfo",
        lambda *args, **kwargs: [(None, None, None, "", ("fe80::1", 443))],
    )
    with pytest.raises(ApiError):
        _validate_connector_url("https://api.example.com/data")


def test_connector_url_blocks_ipv4_mapped_private(monkeypatch):
    monkeypatch.setattr(
        "app.services.ai.ai_connector_service.socket.getaddrinfo",
        lambda *args, **kwargs: [(None, None, None, "", ("::ffff:10.1.2.3", 443))],
    )
    with pytest.raises(ApiError):
        _validate_connector_url("https://api.example.com/data")


def test_connector_url_blocks_metadata_ip():
    with pytest.raises(ApiError):
        _validate_connector_url("http://169.254.169.254/latest/meta-data")


def test_connector_url_rejects_templated_host():
    with pytest.raises(ApiError):
        _validate_connector_url("https://{{host}}/data")
