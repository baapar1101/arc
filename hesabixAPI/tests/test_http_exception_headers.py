from fastapi import HTTPException
from starlette.requests import Request

from app.core.error_handlers import _translate_http_exception


def test_http_exception_response_preserves_authentication_challenge():
    request = Request(
        {
            "type": "http",
            "asgi": {"version": "3.0"},
            "http_version": "1.1",
            "method": "POST",
            "scheme": "https",
            "path": "/api/v1/ai/mcp",
            "raw_path": b"/api/v1/ai/mcp",
            "query_string": b"",
            "headers": [],
            "client": ("127.0.0.1", 12345),
            "server": ("example.test", 443),
        }
    )
    challenge = 'Bearer resource_metadata="https://example.test/.well-known/oauth-protected-resource/api/v1/ai/mcp", scope="ai:tools:read"'
    exc = HTTPException(
        status_code=401,
        detail="A Hesabix MCP bearer credential is required.",
        headers={"WWW-Authenticate": challenge},
    )

    response = _translate_http_exception(request, exc)

    assert response.status_code == 401
    assert response.headers["www-authenticate"] == challenge
