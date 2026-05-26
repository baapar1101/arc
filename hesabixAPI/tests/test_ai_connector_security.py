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


def test_connector_url_rejects_templated_host():
    with pytest.raises(ApiError):
        _validate_connector_url("https://{{host}}/data")
