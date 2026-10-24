"""OAuth 2.1 authorization and discovery endpoints for the MCP resource server."""
from __future__ import annotations

import hashlib
import html
import json
import re
import secrets
from datetime import datetime, timedelta
from pathlib import Path
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import FileResponse, HTMLResponse, JSONResponse
from sqlalchemy.orm import Session

from adapters.db.models.ai_mcp_oauth import (
    McpOAuthAuthorizationCode,
    McpOAuthAuthorizationRequest,
    McpOAuthClient,
    McpOAuthRefreshToken,
)
from adapters.db.models.api_key import ApiKey
from adapters.db.models.business import Business
from adapters.db.models.business_permission import BusinessPermission
from adapters.db.models.user import User
from adapters.db.session import get_db
from app.core.auth_dependency import AuthContext, get_current_user
from app.core.business_membership import membership_is_active
from app.core.security import generate_api_key, hash_api_key
from app.core.settings import get_settings
from app.core.cache import get_cache
from app.core.rate_limiter import rate_limit

oauth_router = APIRouter(prefix="/ai/mcp/oauth", tags=["هوش مصنوعی-MCP OAuth"])
metadata_router = APIRouter(tags=["MCP OAuth Discovery"])
SCOPES = {"ai:tools:read", "ai:tools:write"}
AUTH_SCOPES = SCOPES | {"offline_access"}
READ_SCOPE = "ai:tools:read"
WRITE_SCOPE = "ai:tools:write"
AUTH_REQUEST_TTL = timedelta(minutes=10)
CODE_TTL = timedelta(minutes=2)
_VERIFIER_RE = re.compile(r"^[A-Za-z0-9._~-]{43,128}$")


def _session_ttl(db: Session) -> timedelta:
    from app.services.system_settings_service import get_mcp_oauth_session_days

    return timedelta(days=get_mcp_oauth_session_days(db))


def _is_production() -> bool:
    return get_settings().environment.strip().lower() in {"production", "prod"}


def _base_url(request: Request) -> str:
    configured = get_settings().mcp_public_base_url.strip().rstrip("/")
    if configured:
        parsed = urlsplit(configured)
        try:
            valid_authority = bool(parsed.hostname) and parsed.port != 0 and not parsed.username and not parsed.password
        except ValueError:
            valid_authority = False
        if (parsed.scheme not in {"https", "http"} or not parsed.netloc or not valid_authority
                or parsed.path or parsed.query or parsed.fragment):
            raise HTTPException(503, "MCP_PUBLIC_BASE_URL is invalid")
        if _is_production() and parsed.scheme != "https":
            raise HTTPException(503, "MCP_PUBLIC_BASE_URL must use HTTPS in production")
        return configured
    if _is_production():
        raise HTTPException(503, "MCP OAuth requires MCP_PUBLIC_BASE_URL in production")
    return str(request.base_url).rstrip("/")


def _resource(request: Request) -> str:
    return _base_url(request) + request.url_for("mcp_jsonrpc_endpoint").path


def _issuer(request: Request) -> str:
    return _base_url(request)


def _oauth_url(request: Request, suffix: str) -> str:
    return _base_url(request) + get_settings().api_v1_prefix + "/ai/mcp/oauth/" + suffix


async def _resolve_client(db: Session, client_id: str) -> McpOAuthClient | None:
    row = db.query(McpOAuthClient).filter(McpOAuthClient.client_id == client_id).first()
    if row:
        return row
    if len(client_id) > 512:
        return None
    try:
        parsed = urlsplit(client_id)
        host = (parsed.hostname or "").lower()
        if (parsed.scheme != "https" or not host or parsed.username or parsed.password or
                parsed.port not in (None, 443) or parsed.query or parsed.fragment):
            return None
    except ValueError:
        return None
    allowed_hosts = {item.lower().lstrip(".") for item in get_settings().mcp_cimd_allowed_hosts}
    if host not in allowed_hosts:
        return None
    try:
        import httpx
        async with httpx.AsyncClient(timeout=httpx.Timeout(3.0, connect=2.0), follow_redirects=False) as client:
            async with client.stream("GET", client_id, headers={"Accept": "application/json"}) as response:
                if response.status_code != 200 or int(response.headers.get("content-length", "0") or 0) > 65536:
                    return None
                body = bytearray()
                async for chunk in response.aiter_bytes():
                    body.extend(chunk)
                    if len(body) > 65536:
                        return None
        metadata = json.loads(body.decode("utf-8"))
    except Exception:
        return None
    if not isinstance(metadata, dict) or metadata.get("client_id") != client_id:
        return None
    redirect_uris = metadata.get("redirect_uris")
    if not isinstance(redirect_uris, list) or not 1 <= len(redirect_uris) <= 10:
        return None
    if any(not isinstance(uri, str) or len(uri) > 2048 or not _trusted_redirect_uri(uri) for uri in redirect_uris):
        return None
    methods = metadata.get("token_endpoint_auth_methods_supported")
    if methods is not None and (not isinstance(methods, list) or "none" not in methods):
        return None
    # The singular CIMD field is the client's preferred/default method. ChatGPT
    # advertises `private_key_jwt` there while also explicitly supporting `none`.
    # This server only implements public-client (`none`) authentication, so use
    # the supported-methods list as the capability check when it is present.
    # Older/simple metadata documents may omit that list; in that case the
    # singular method is the only available declaration and must be `none`.
    auth_method = metadata.get("token_endpoint_auth_method")
    if methods is None and auth_method not in (None, "none"):
        return None
    if methods is not None and auth_method is not None and (
            not isinstance(auth_method, str) or auth_method not in methods):
        return None
    grants = metadata.get("grant_types", ["authorization_code"])
    if (not isinstance(grants, list) or not all(isinstance(grant, str) for grant in grants)
            or "authorization_code" not in grants
            or len(grants) != len(set(grants)) or not set(grants) <= {"authorization_code", "refresh_token"}):
        return None
    name = str(metadata.get("client_name") or "MCP client").strip()[:200]
    row = McpOAuthClient(
        client_id=client_id, client_name=name or "MCP client", redirect_uris=redirect_uris,
        grant_types=grants,
    )
    db.add(row)
    try:
        db.commit()
        db.refresh(row)
        return row
    except Exception:
        db.rollback()
        return db.query(McpOAuthClient).filter(McpOAuthClient.client_id == client_id).first()


def _hash(value: str) -> str:
    return hash_api_key(value)


def _valid_redirect_uri(uri: str) -> bool:
    try:
        if any(ord(char) < 0x21 or char == "\\" for char in uri):
            return False
        p = urlsplit(uri)
        _ = p.port
        if not p.scheme or p.fragment or "*" in uri or p.username or p.password:
            return False
        if {key for key, _value in parse_qsl(p.query, keep_blank_values=True)} & {"code", "state", "iss", "error"}:
            return False
        if p.scheme == "https":
            return bool(p.netloc)
        if p.scheme == "http":
            return p.hostname in {"localhost", "127.0.0.1", "::1"}
        # Native application redirect schemes are allowed; exact URI matching is always enforced.
        return bool(re.fullmatch(r"[A-Za-z][A-Za-z0-9+.-]{1,31}", p.scheme)) and not p.netloc
    except (TypeError, ValueError):
        return False


def _trusted_redirect_uri(uri: str) -> bool:
    if not _valid_redirect_uri(uri):
        return False
    parsed = urlsplit(uri)
    if parsed.scheme != "https":
        return (
            not _is_production()
            and parsed.scheme == "http"
            and parsed.hostname in {"localhost", "127.0.0.1", "::1"}
        )
    host = (parsed.hostname or "").lower()
    allowed = {item.lower().strip(".") for item in get_settings().mcp_oauth_trusted_redirect_hosts}
    return host in allowed or any(host.endswith("." + domain) for domain in allowed)


def _has_explicit_business_access(db: Session, user_id: int, business_id: int) -> bool:
    """Check tenant membership without the global superadmin access shortcut."""
    business = db.get(Business, business_id)
    if not business or business.deleted_at is not None:
        return False
    if business.owner_id == user_id:
        return True
    permission = db.query(BusinessPermission).filter(
        BusinessPermission.user_id == user_id,
        BusinessPermission.business_id == business_id,
    ).first()
    if not permission:
        return False
    permissions = AuthContext._normalize_permissions_value(permission.business_permissions or {})
    return permissions.get("join") is True and membership_is_active(permission)


def _consent_tool_catalog(db: Session, ctx: AuthContext, business_id: int) -> list[dict]:
    """Return only tools the signed-in member can already use in this business."""
    from app.services.ai.ai_mcp_service import _get_tools, _mcp_readonly, _openai_tool_to_mcp

    registry, definitions = _get_tools(db, ctx, business_id)
    catalog = []
    for definition in definitions:
        tool = _openai_tool_to_mcp(definition, registry)
        func = registry.get_function(tool["name"])
        readonly = _mcp_readonly(tool["name"], registry)
        catalog.append({
            "name": tool["name"],
            "description": tool["description"],
            "category": getattr(func, "category", None) or "other",
            "read_only": readonly,
        })
    return sorted(catalog, key=lambda item: (item["category"], item["name"]))


def _append_query(uri: str, values: dict[str, str]) -> str:
    p = urlsplit(uri)
    query = parse_qsl(p.query, keep_blank_values=True)
    query.extend(values.items())
    return urlunsplit((p.scheme, p.netloc, p.path, urlencode(query), ""))


def _json_error(error: str, description: str, status: int = 400) -> JSONResponse:
    return JSONResponse({"error": error, "error_description": description}, status_code=status,
                        headers={"Cache-Control": "no-store", "Pragma": "no-cache"})


@metadata_router.get("/.well-known/oauth-authorization-server")
def authorization_server_metadata(request: Request) -> dict:
    issuer = _issuer(request)
    return {
        "issuer": issuer,
        "authorization_endpoint": _oauth_url(request, "authorize"),
        "token_endpoint": _oauth_url(request, "token"),
        "registration_endpoint": _oauth_url(request, "register"),
        "revocation_endpoint": _oauth_url(request, "revoke"),
        "response_types_supported": ["code"],
        "response_modes_supported": ["query"],
        "grant_types_supported": ["authorization_code", "refresh_token"],
        "token_endpoint_auth_methods_supported": ["none"],
        "code_challenge_methods_supported": ["S256"],
        "scopes_supported": sorted(AUTH_SCOPES),
        "authorization_response_iss_parameter_supported": True,
        "client_id_metadata_document_supported": True,
    }


@metadata_router.get("/.well-known/oauth-protected-resource")
@metadata_router.get("/.well-known/oauth-protected-resource/{resource_path:path}")
def protected_resource_metadata(request: Request, resource_path: str | None = None) -> dict:
    resource = _resource(request)
    if resource_path and "/" + resource_path.rstrip("/") != urlsplit(resource).path:
        raise HTTPException(404, "Protected resource not found")
    return {
        "resource": resource,
        "authorization_servers": [_issuer(request)],
        "scopes_supported": sorted(SCOPES),
        "bearer_methods_supported": ["header"],
    }


@oauth_router.post("/register")
@rate_limit(max_requests=30, window_seconds=3600, error_message="ثبت کلاینت OAuth بیش از حد مجاز است.")
async def register_client(request: Request, db: Session = Depends(get_db)) -> JSONResponse:
    try:
        payload = await request.json()
    except Exception:
        return _json_error("invalid_client_metadata", "JSON body required")
    if not isinstance(payload, dict):
        return _json_error("invalid_client_metadata", "Client metadata must be an object")
    redirect_uris = payload.get("redirect_uris")
    if not isinstance(redirect_uris, list) or not 1 <= len(redirect_uris) <= 10:
        return _json_error("invalid_redirect_uri", "Between 1 and 10 redirect_uris are required")
    if any(not isinstance(uri, str) or len(uri) > 2048 or not _trusted_redirect_uri(uri) for uri in redirect_uris):
        return _json_error("invalid_redirect_uri", "A redirect URI is invalid or its host is not trusted")
    if len(set(redirect_uris)) != len(redirect_uris):
        return _json_error("invalid_redirect_uri", "Duplicate redirect URIs are not allowed")
    if payload.get("token_endpoint_auth_method", "none") != "none":
        return _json_error("invalid_client_metadata", "Only public clients using PKCE are supported")
    grants = payload.get("grant_types", ["authorization_code", "refresh_token"])
    if (not isinstance(grants, list) or not all(isinstance(grant, str) for grant in grants)
            or "authorization_code" not in grants
            or len(grants) != len(set(grants)) or not set(grants) <= {"authorization_code", "refresh_token"}):
        return _json_error("invalid_client_metadata", "Unsupported grant_types")
    if payload.get("response_types", ["code"]) != ["code"]:
        return _json_error("invalid_client_metadata", "Only the code response type is supported")
    name = str(payload.get("client_name") or "MCP client").strip()[:200]
    client_id = "mcp_client_" + secrets.token_urlsafe(32)
    row = McpOAuthClient(client_id=client_id, client_name=name or "MCP client", redirect_uris=redirect_uris, grant_types=grants)
    db.add(row)
    db.commit()
    return JSONResponse({
        "client_id": client_id,
        "client_id_issued_at": int(datetime.utcnow().timestamp()),
        "client_name": row.client_name,
        "redirect_uris": redirect_uris,
        "grant_types": grants,
        "response_types": ["code"],
        "token_endpoint_auth_method": "none",
    }, status_code=201, headers={"Cache-Control": "no-store"})


@oauth_router.get("/authorize", response_class=HTMLResponse)
@rate_limit(max_requests=30, window_seconds=600, error_message="درخواست‌های OAuth بیش از حد مجاز است.")
async def authorize(
    request: Request,
    response_type: str,
    client_id: str,
    redirect_uri: str,
    code_challenge: str,
    code_challenge_method: str,
    resource: str,
    state: str = "",
    scope: str = READ_SCOPE,
    db: Session = Depends(get_db),
) -> HTMLResponse:
    client = await _resolve_client(db, client_id)
    if response_type != "code" or not client or redirect_uri not in (client.redirect_uris or []):
        raise HTTPException(400, "Invalid OAuth authorization request")
    requested_scopes = scope.split()
    if (len(state) > 512 or code_challenge_method != "S256" or
            not _VERIFIER_RE.fullmatch(code_challenge) or not requested_scopes or
            READ_SCOPE not in requested_scopes or not set(requested_scopes) <= AUTH_SCOPES or
            len(requested_scopes) != len(set(requested_scopes)) or resource != _resource(request)):
        raise HTTPException(400, "Invalid OAuth authorization request")
    if "offline_access" in requested_scopes and "refresh_token" not in (client.grant_types or []):
        raise HTTPException(400, "This client is not registered for refresh tokens")
    raw_request_id = secrets.token_urlsafe(32)
    db.add(McpOAuthAuthorizationRequest(
        request_hash=_hash(raw_request_id), client_id=client_id, redirect_uri=redirect_uri,
        resource=resource, state=state, code_challenge=code_challenge,
        scopes=requested_scopes, expires_at=datetime.utcnow() + AUTH_REQUEST_TTL,
    ))
    db.commit()
    html_body = _authorization_html(
        raw_request_id, client.client_name, "offline_access" in requested_scopes,
    )
    return HTMLResponse(html_body, headers={
        "Cache-Control": "no-store", "Pragma": "no-cache",
        "Content-Security-Policy": "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; font-src 'self'; img-src data:; connect-src 'self'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'",
        "Referrer-Policy": "no-referrer", "X-Content-Type-Options": "nosniff",
    })


@oauth_router.get("/assets/fonts/{font_name}", include_in_schema=False)
def oauth_font(font_name: str) -> FileResponse:
    """Serve only the bundled UI fonts used by the standalone OAuth page."""
    allowed_fonts = {
        "YekanBakhFaNum-Regular.woff2",
        "YekanBakhFaNum-SemiBold.woff2",
        "YekanBakhFaNum-Bold.woff2",
        "roboto.woff2",
    }
    if font_name not in allowed_fonts:
        raise HTTPException(404, "Font not found")
    repository_root = Path(__file__).resolve().parents[5]
    font_path = repository_root / "hesabixUI" / "hesabix_ui" / "web" / "fonts" / font_name
    if not font_path.is_file():
        raise HTTPException(404, "Font not found")
    return FileResponse(
        font_path,
        media_type="font/woff2",
        headers={"Cache-Control": "public, max-age=31536000, immutable"},
    )


def _authorization_html(request_id: str, client_name: str, offline_requested: bool) -> str:
    safe_name = html.escape(client_name)
    api_json = json.dumps(get_settings().api_v1_prefix)
    request_json = json.dumps(request_id)
    offline_option = (
        '<label class="permission permission--optional"><input type="checkbox" id="offline">'
        '<span><strong>تداوم اتصال بدون ورود دوباره</strong><small>تمدید اتصال در بازهٔ زمانی تعیین‌شده در تنظیمات حسابیکس</small></span></label>'
        if offline_requested else ""
    )
    return f'''<!doctype html>
<html lang="fa" dir="rtl">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
  <meta name="color-scheme" content="light">
  <title>اتصال امن | حسابیکس</title>
  <style>
    @font-face {{ font-family: YekanBakh; src: url("{get_settings().api_v1_prefix}/ai/mcp/oauth/assets/fonts/YekanBakhFaNum-Regular.woff2") format("woff2"); font-weight: 400; font-display: swap; }}
    @font-face {{ font-family: YekanBakh; src: url("{get_settings().api_v1_prefix}/ai/mcp/oauth/assets/fonts/YekanBakhFaNum-SemiBold.woff2") format("woff2"); font-weight: 600; font-display: swap; }}
    @font-face {{ font-family: YekanBakh; src: url("{get_settings().api_v1_prefix}/ai/mcp/oauth/assets/fonts/YekanBakhFaNum-Bold.woff2") format("woff2"); font-weight: 700; font-display: swap; }}
    @font-face {{ font-family: Roboto; src: url("{get_settings().api_v1_prefix}/ai/mcp/oauth/assets/fonts/roboto.woff2") format("woff2"); font-weight: 400; font-display: swap; }}
    :root {{ color-scheme: light; --brand:#0f4c81; --brand-strong:#0a3d69; --ink:#172b3b; --muted:#657789; --line:#e4ebf1; --surface:#fff; --canvas:#f3f7fa; --danger:#a83232; --success:#176b4d; }}
    * {{ box-sizing:border-box; }}
    [hidden] {{ display:none !important; }}
    body {{ margin:0; min-height:100vh; min-height:100dvh; padding:clamp(16px,4vw,48px); display:grid; place-items:center; color:var(--ink); background:radial-gradient(ellipse at 8% 12%,rgba(116,181,213,.2),transparent 32%),radial-gradient(ellipse at 94% 84%,rgba(63,144,129,.13),transparent 31%),#f2f6f9; font-family:YekanBakh,Tahoma,sans-serif; font-size:15px; line-height:1.7; }}
    button,input,select {{ font:inherit; }}
    .shell {{ width:min(100%,560px); }}
    .card {{ overflow:hidden; background:var(--surface); border:1px solid rgba(18,63,94,.08); border-radius:26px; box-shadow:0 28px 80px rgba(21,52,76,.14),0 3px 12px rgba(21,52,76,.04); }}
    .card-head {{ padding:clamp(22px,6vw,34px) clamp(22px,6vw,42px) 20px; }}
    .brand-row {{ display:flex; align-items:center; gap:12px; }}
    .brand-mark {{ width:48px; height:48px; flex:0 0 48px; display:grid; place-items:center; color:#fff; background:linear-gradient(145deg,#2181ae,#0a426f); border-radius:16px; box-shadow:0 8px 18px rgba(15,76,129,.22); }}
    .brand-mark svg {{ width:26px; height:26px; }}
    .brand-copy {{ min-width:0; }}
    .eyebrow {{ margin:0; color:#526d80; font-size:12px; font-weight:600; }}
    h1 {{ margin:2px 0 0; font-size:clamp(21px,5vw,26px); line-height:1.4; font-weight:700; letter-spacing:-.02em; }}
    .intro {{ margin:16px 0 0; color:var(--muted); font-size:13px; line-height:1.9; }}
    .client {{ color:var(--ink); font-weight:700; }}
    .trust-row {{ display:flex; align-items:center; gap:8px; margin-top:12px; color:#39705f; font-size:12px; }}
    .trust-row svg {{ width:17px; height:17px; flex:0 0 auto; }}
    .steps {{ display:grid; grid-template-columns:1fr 1fr; gap:10px; margin-top:23px; padding:5px; background:#f1f5f8; border:1px solid #e9eef2; border-radius:13px; color:#778b99; font-size:12px; }}
    .step {{ display:flex; justify-content:center; align-items:center; gap:8px; min-height:36px; border-radius:9px; transition:background .18s,color .18s,box-shadow .18s; }}
    .step-number {{ width:21px; height:21px; display:grid; place-items:center; border:1px solid #d4dfe6; border-radius:50%; font-family:Roboto,YekanBakh,sans-serif; font-size:11px; }}
    .step.active {{ color:var(--brand); background:#fff; font-weight:700; box-shadow:0 2px 6px rgba(34,62,79,.08); }}
    .step.active .step-number {{ color:#fff; background:var(--brand); border-color:var(--brand); }}
    .card-body {{ padding:4px clamp(22px,6vw,42px) clamp(24px,6vw,38px); }}
    .section-heading {{ margin:0 0 5px; color:#213e52; font-size:17px; font-weight:700; }}
    .section-hint {{ margin:0 0 19px; color:var(--muted); font-size:12px; line-height:1.8; }}
    .field {{ display:block; margin:0 0 17px; }}
    .field-label {{ display:block; margin-bottom:7px; color:#314b5d; font-size:13px; font-weight:600; }}
    .control {{ width:100%; min-height:50px; padding:11px 14px; color:var(--ink); background:#fff; border:1px solid #d8e2e9; border-radius:12px; outline:none; transition:border-color .16s,box-shadow .16s,background .16s; }}
    .control:focus {{ border-color:#4c8ab4; box-shadow:0 0 0 4px rgba(15,76,129,.1); }}
    .control::placeholder {{ color:#99a8b4; }}
    .channel-label {{ margin-bottom:8px; color:#314b5d; font-size:13px; font-weight:600; }}
    .channel-switch {{ display:grid; grid-template-columns:1fr 1fr; gap:8px; margin-bottom:17px; padding:4px; background:#f3f6f8; border:1px solid #e8edf1; border-radius:12px; }}
    .channel-option {{ display:flex; align-items:center; justify-content:center; gap:8px; min-height:41px; color:#667b89; background:transparent; border:1px solid transparent; border-radius:9px; cursor:pointer; font-size:13px; transition:all .16s; }}
    .channel-option svg {{ width:17px; height:17px; }}
    .channel-option[aria-pressed="true"] {{ color:var(--brand); background:#fff; border-color:#e3ebf0; box-shadow:0 2px 5px rgba(31,63,82,.07); font-weight:700; }}
    .auth-mode {{ margin-bottom:17px; }}
    .captcha-field {{ margin-top:2px; }}
    .captcha-layout {{ display:grid; grid-template-columns:minmax(0,1fr) 164px; gap:10px; align-items:end; }}
    .captcha-image {{ height:54px; display:flex; align-items:center; justify-content:center; overflow:hidden; background:linear-gradient(135deg,#f5f9fb,#edf4f7); border:1px solid #dfe8ee; border-radius:12px; }}
    .captcha-image img {{ max-width:100%; max-height:52px; object-fit:contain; }}
    .captcha-image span {{ color:#7b8d99; font-size:11px; }}
    .captcha-refresh {{ width:42px; height:42px; flex:0 0 42px; display:grid; place-items:center; color:#4d6b7f; background:#fff; border:1px solid #dfe8ee; border-radius:11px; cursor:pointer; transition:all .16s; }}
    .captcha-refresh:hover:not(:disabled) {{ color:var(--brand); background:#f4f9fc; border-color:#b9d0df; }}
    .captcha-refresh svg {{ width:19px; height:19px; }}
    .captcha-tools {{ display:flex; align-items:center; gap:7px; }}
    .captcha-tools .captcha-image {{ flex:1; }}
    .primary,.secondary {{ width:100%; min-height:50px; padding:11px 16px; border-radius:12px; font-weight:700; cursor:pointer; transition:background .16s,border-color .16s,transform .16s,box-shadow .16s; }}
    .primary {{ color:#fff; background:linear-gradient(110deg,#14588b,#0d4777); border:1px solid #0f4c81; box-shadow:0 6px 14px rgba(15,76,129,.17); }}
    .primary:hover:not(:disabled) {{ background:linear-gradient(110deg,#0f4b79,#093a64); border-color:#0a3d69; transform:translateY(-1px); box-shadow:0 8px 17px rgba(15,76,129,.2); }}
    .secondary {{ color:#496579; background:#fff; border:1px solid #d8e2e9; }}
    .secondary:hover:not(:disabled) {{ background:#f6f9fb; border-color:#bdcdd9; }}
    button:focus-visible {{ outline:3px solid rgba(15,76,129,.28); outline-offset:2px; }}
    button:disabled {{ opacity:.58; cursor:wait; transform:none; }}
    .status {{ display:flex; align-items:flex-start; gap:8px; margin:13px 0 0; padding:0; color:var(--muted); font-size:12px; line-height:1.8; }}
    .status:not(:empty) {{ padding:10px 12px; background:#f3f7f9; border:1px solid #e7eef2; border-radius:11px; }}
    .status[data-tone="error"] {{ color:var(--danger); background:#fff5f4; border-color:#f4d7d4; }}
    .status[data-tone="success"] {{ color:var(--success); background:#f1faf5; border-color:#d8eee2; }}
    .divider {{ height:1px; margin:18px 0; background:var(--line); }}
    .otp-input {{ min-height:62px; text-align:center; direction:ltr; font-family:Roboto,YekanBakh,sans-serif; font-size:26px; font-weight:700; letter-spacing:.42em; padding-left:calc(14px + .42em); }}
    .otp-summary {{ display:flex; align-items:center; gap:9px; margin:14px 0 18px; padding:11px 13px; color:#506b7c; background:#f4f8fa; border:1px solid #e5edf2; border-radius:11px; font-size:12px; }}
    .otp-summary svg {{ width:17px; height:17px; color:#39705f; flex:0 0 auto; }}
    .text-button {{ display:inline-flex; align-items:center; justify-content:center; gap:6px; min-height:40px; padding:6px 8px; color:var(--brand); background:transparent; border:0; border-radius:8px; cursor:pointer; font-size:12px; font-weight:600; }}
    .text-button:hover {{ background:#f0f6fa; }}
    .permission-list {{ display:grid; gap:9px; margin:17px 0 19px; }}
    .permission {{ display:flex; align-items:flex-start; gap:11px; padding:14px; background:#f4f8fa; border:1px solid #e2ebf0; border-radius:13px; cursor:pointer; transition:border-color .16s,background .16s; }}
    .permission:has(input:checked) {{ background:#f0f7fb; border-color:#c9dce8; }}
    .permission input {{ width:18px; height:18px; margin:3px 0 0; accent-color:var(--brand); flex:0 0 auto; }}
    .permission span {{ display:grid; gap:2px; }}
    .permission strong {{ color:#29465a; font-size:13px; font-weight:700; }}
    .permission small {{ color:var(--muted); font-size:12px; line-height:1.7; }}
    .permission--optional {{ background:#fff; }}
    .business-label {{ margin-bottom:7px; }}
    .button-row {{ display:grid; grid-template-columns:1fr 1fr; gap:10px; margin-top:17px; }}
    .footnote {{ display:flex; justify-content:center; align-items:center; gap:6px; margin:16px 0 0; color:#778b99; text-align:center; font-size:11px; }}
    .footnote svg {{ width:14px; height:14px; color:#438069; }}
    @media(max-width:460px) {{ body {{ padding:12px; }} .card {{ border-radius:21px; }} .card-head {{ padding:22px 20px 17px; }} .card-body {{ padding:4px 20px 25px; }} .captcha-layout {{ grid-template-columns:minmax(0,1fr) 142px; gap:8px; }} .steps {{ gap:6px; }} .intro {{ font-size:12px; }} .otp-input {{ font-size:23px; }} }}
    @media(max-width:360px) {{ .captcha-layout {{ grid-template-columns:minmax(0,1fr) 126px; }} .brand-mark {{ width:43px; height:43px; flex-basis:43px; }} .button-row {{ grid-template-columns:1fr; }} }}
    @media(prefers-reduced-motion:reduce) {{ *,*::before,*::after {{ scroll-behavior:auto !important; transition:none !important; }} }}
  </style>
</head>
<body>
  <main class="shell">
    <article class="card" aria-labelledby="page-title">
      <header class="card-head">
        <div class="brand-row"><div class="brand-mark" aria-hidden="true"><svg viewBox="0 0 24 24" fill="none"><path d="M12 2.8 20 6v5.4c0 5.2-3.5 8.4-8 10.1-4.5-1.7-8-4.9-8-10.1V6l8-3.2Z" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/><path d="m8.7 12.1 2.2 2.2 4.6-4.7" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg></div><div class="brand-copy"><p class="eyebrow">حسابیکس · اتصال به هوش مصنوعی</p><h1 id="page-title">اتصال امن حساب کاربری</h1></div></div>
        <p class="intro"><span class="client">{safe_name}</span> درخواست اتصال به ابزارهای حسابیکس را دارد. فقط اگر این درخواست را خودتان آغاز کرده‌اید، ادامه دهید.</p>
        <div class="trust-row"><svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="M12 3 19 6v5c0 4.6-3 7.5-7 9-4-1.5-7-4.4-7-9V6l7-3Z" stroke="currentColor" stroke-width="1.8"/><path d="m9 11.5 2 2 4-4" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg><span>ورود شما مستقیماً در حسابیکس انجام می‌شود</span></div>
        <div class="steps" aria-label="مراحل اتصال"><span class="step active" id="stepLogin"><span class="step-number">۱</span><span>تایید هویت</span></span><span class="step" id="stepConsent"><span class="step-number">۲</span><span>انتخاب دسترسی</span></span></div>
      </header>
      <div class="card-body">
        <section id="loginSection" aria-labelledby="login-heading">
          <h2 class="section-heading" id="login-heading">ورود به حسابیکس</h2>
          <p class="section-hint">با کد یک‌بارمصرف یا رمز عبور حسابیکس وارد شوید.</p>
          <div class="channel-switch auth-mode" role="group" aria-label="روش ورود">
            <button class="channel-option" type="button" data-mode="otp" aria-pressed="true"><span>کد یک‌بارمصرف</span></button>
            <button class="channel-option" type="button" data-mode="password" aria-pressed="false"><span>رمز عبور</span></button>
          </div>
          <div id="otpMethod">
          <div class="channel-label">ارسال کد از طریق</div>
          <div class="channel-switch" role="group" aria-label="روش دریافت کد">
            <button class="channel-option" type="button" data-channel="sms" aria-pressed="true"><svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><rect x="5" y="2.8" width="14" height="18.4" rx="3" stroke="currentColor" stroke-width="1.7"/><path d="M9 6h6M10 18h4" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/></svg><span>پیامک</span></button>
            <button class="channel-option" type="button" data-channel="email" aria-pressed="false"><svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><rect x="3" y="5" width="18" height="14" rx="3" stroke="currentColor" stroke-width="1.7"/><path d="m4.5 7 7.5 5.5L19.5 7" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/></svg><span>ایمیل</span></button>
          </div>
          </div>
          <label class="field"><span class="field-label" id="identifierLabel">شماره موبایل</span><input class="control" id="identifier" type="tel" inputmode="tel" autocomplete="tel" maxlength="255" placeholder="مثلاً ۰۹۱۲۱۲۳۴۵۶۷" required></label>
          <div id="passwordField" hidden><label class="field"><span class="field-label" for="password">رمز عبور</span><input class="control" id="password" type="password" autocomplete="current-password" maxlength="128" placeholder="رمز عبور حسابیکس" required></label></div>
          <div class="field captcha-field">
            <label class="field-label" for="captchaCode">کد امنیتی تصویر</label>
            <div class="captcha-layout">
              <input class="control" id="captchaCode" maxlength="10" autocomplete="off" autocapitalize="characters" placeholder="متن تصویر را وارد کنید" required>
              <div class="captcha-tools"><div class="captcha-image"><span id="captchaPlaceholder">در حال دریافت تصویر…</span><img id="captcha" alt="کد امنیتی جدید"></div><button class="captcha-refresh" id="reload" type="button" aria-label="دریافت تصویر جدید" title="تصویر جدید"><svg viewBox="0 0 24 24" fill="none"><path d="M20 7v5h-5M4 17v-5h5" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/><path d="M6 9a7 7 0 0 1 12-2l2 2M4 15l2 2a7 7 0 0 0 12-2" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg></button></div>
            </div>
          </div>
          <button class="primary" id="send" type="button">ارسال کد تایید</button>
          <button class="primary" id="passwordLogin" type="button" hidden>ورود و ادامه</button>
          <p id="status" class="status" role="status" aria-live="polite"></p>
        </section>
        <section id="otpSection" hidden aria-labelledby="otp-heading">
          <div class="divider"></div><h2 class="section-heading" id="otp-heading">کد تایید را وارد کنید</h2>
          <p class="section-hint">کد یک‌بارمصرف را در پیامک یا ایمیل خود پیدا کنید.</p>
          <div class="otp-summary"><svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="M4 7.5A2.5 2.5 0 0 1 6.5 5h11A2.5 2.5 0 0 1 20 7.5v9a2.5 2.5 0 0 1-2.5 2.5h-11A2.5 2.5 0 0 1 4 16.5v-9Z" stroke="currentColor" stroke-width="1.7"/><path d="m5 7 7 5.5L19 7" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/></svg><span id="deliverySummary">کد برای شما ارسال شد.</span></div>
          <label class="field"><span class="field-label" for="otp">کد یک‌بارمصرف</span><input class="control otp-input" id="otp" inputmode="numeric" autocomplete="one-time-code" maxlength="6" placeholder="ــــــ" dir="ltr" aria-describedby="otpHint" required></label>
          <p class="section-hint" id="otpHint">کد را بدون فاصله وارد کنید.</p>
          <button class="primary" id="verify" type="button">تایید و ادامه</button>
          <p class="status" id="otpStatus" role="status" aria-live="polite"></p>
          <div class="divider"></div><button class="text-button" id="changeLogin" type="button"><span aria-hidden="true">←</span> اصلاح شماره یا روش دریافت کد</button>
        </section>
        <section id="consent" hidden aria-labelledby="consent-heading">
          <div class="divider"></div><h2 class="section-heading" id="consent-heading">اتصال را بررسی و تایید کنید</h2>
          <p class="section-hint">کسب‌وکار و سطح دسترسی را انتخاب کنید. فقط موارد انتخاب‌شده در اختیار این اتصال قرار می‌گیرد.</p>
          <label class="field"><span class="field-label business-label" for="business">کسب‌وکار موردنظر</span><select class="control" id="business" required><option value="" selected disabled>یک کسب‌وکار را انتخاب کنید</option></select></label>
          <div id="toolPermissionSection" hidden><h3 class="section-heading">انتخاب ابزارها</h3><p class="section-hint">فقط ابزارهای مجاز برای حساب شما نمایش داده می‌شوند. ابزارهای تغییردهنده نیز مطابق سطح دسترسی شما قابل انتخاب‌اند.</p><button class="text-button" id="grantAll" type="button">فعال‌سازی همهٔ دسترسی‌های مجاز</button><div id="toolPermissions" class="permission-list"></div></div>
          <div class="permission-list">{offline_option}</div>
          <div class="button-row"><button class="primary" id="approve" type="button">تایید و اتصال</button><button class="secondary" id="deny" type="button">رد درخواست</button></div>
          <p class="status" id="consentStatus" role="status" aria-live="polite"></p>
        </section>
      </div>
    </article>
    <p class="footnote"><svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="M12 3 19 6v5c0 4.6-3 7.5-7 9-4-1.5-7-4.4-7-9V6l7-3Z" stroke="currentColor" stroke-width="1.7"/><path d="m9 11.5 2 2 4-4" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/></svg>می‌توانید دسترسی این اتصال را بعداً از تنظیمات حسابیکس لغو کنید.</p>
  </main>
<script>
const api={api_json},rid={request_json};let captchaId='',loginSession='',sessionKey='',selectedChannel='sms',loginMode='otp';
const $=id=>document.getElementById(id);
function status(id,message,tone=''){{const el=$(id);el.textContent=message;el.dataset.tone=tone}}
async function request(path,options={{}}){{
  let response;try{{response=await fetch(api+path,options)}}catch{{throw Error('ارتباط با سرور برقرار نشد؛ اتصال اینترنت را بررسی کنید.')}}
  let payload;try{{payload=await response.json()}}catch{{if(response.status===404)throw Error(`مسیر API «${{path}}» در سرور پیدا نشد (HTTP 404). سرور یا تنظیم Nginx نیاز به به‌روزرسانی دارد.`);throw Error(`پاسخ سرور معتبر نیست (HTTP ${{response.status}}). اگر خطا ادامه دارد، صفحه را دوباره باز کنید.`)}}
  const error=payload?.error&&typeof payload.error==='object'?payload.error:payload;
  if(!response.ok||payload?.success===false){{
    const friendlyErrors={{INVALID_CAPTCHA:'کد امنیتی درست نیست. تصویر تازه بگیرید و دوباره وارد کنید.',INVALID_CREDENTIALS:'ایمیل یا شماره موبایل و رمز عبور را بررسی کنید.',INVALID_IDENTIFIER:'ایمیل یا شماره موبایل معتبر وارد کنید.',INVALID_OTP_FORMAT:'کد تایید باید ۶ رقم باشد.',OTP_NOT_FOUND:'کد تایید منقضی شده است. دوباره کد بگیرید.',SESSION_NOT_FOUND:'نشست ورود منقضی شده است. دوباره کد بگیرید.',INVALID_OTP:'کد واردشده صحیح نیست. آن را بررسی و دوباره وارد کنید.',OTP_ATTEMPTS_EXCEEDED:'تعداد تلاش مجاز تمام شده است. دوباره کد ورود بگیرید.',RATE_LIMIT_EXCEEDED:'درخواست‌های زیادی ثبت شده است. کمی صبر کنید و دوباره تلاش کنید.',CHANNEL_NOT_SUPPORTED:'روش دریافت انتخاب‌شده در دسترس نیست.',USER_NOT_FOUND:'برای این شماره یا ایمیل حساب فعالی پیدا نشد. اطلاعات ورود را بررسی کنید.'}};
    if(friendlyErrors[error?.code])throw Error(friendlyErrors[error.code]);
    if(response.status===404&&(!error?.code||error.code==='HTTP_ERROR'))throw Error(`مسیر API «${{path}}» در نسخهٔ فعلی سرور پیدا نشد (HTTP 404). صفحه را تازه کنید؛ اگر مشکل ماند، سرور باید به‌روزرسانی شود.`);
    throw Error(error?.message||payload?.detail||`درخواست ناموفق بود (HTTP ${{response.status}}).`)
  }}
  return payload?.data??payload;
}}
function asciiDigits(value){{return value.replace(/[۰-۹٠-٩]/g,d=>String('۰۱۲۳۴۵۶۷۸۹٠١٢٣٤٥٦٧٨٩'.indexOf(d)%10))}}
function setChannel(channel){{selectedChannel=channel;status('status','','');document.querySelectorAll('.channel-option[data-channel]').forEach(button=>button.setAttribute('aria-pressed',String(button.dataset.channel===channel)));const email=channel==='email';$('identifierLabel').textContent=email?'آدرس ایمیل':'شماره موبایل';$('identifier').type=email?'email':'tel';$('identifier').inputMode=email?'email':'tel';$('identifier').autocomplete=email?'email':'tel';$('identifier').placeholder=email?'مثلاً name@example.com':'مثلاً ۰۹۱۲۱۲۳۴۵۶۷';$('identifier').focus()}}
function setMode(mode){{loginMode=mode;status('status','','');const password=mode==='password';$('otpMethod').hidden=password;$('passwordField').hidden=!password;$('send').hidden=password;$('passwordLogin').hidden=!password;document.querySelectorAll('[data-mode]').forEach(button=>button.setAttribute('aria-pressed',String(button.dataset.mode===mode)));$('identifierLabel').textContent=password?'ایمیل یا شماره موبایل':(selectedChannel==='email'?'آدرس ایمیل':'شماره موبایل');$('identifier').type=password?'text':(selectedChannel==='email'?'email':'tel');$('identifier').inputMode=password?'text':(selectedChannel==='email'?'email':'tel');$('identifier').autocomplete=password?'username':(selectedChannel==='email'?'email':'tel');$('identifier').placeholder=password?'ایمیل یا شماره موبایل حسابیکس':(selectedChannel==='email'?'مثلاً name@example.com':'مثلاً ۰۹۱۲۱۲۳۴۵۶۷');if(password)$('password').focus();else $('identifier').focus()}}
function maskDestination(value,channel){{const clean=value.trim();if(channel==='email'){{const parts=clean.split('@');return parts.length===2?(parts[0].slice(0,1)+'•••@'+parts[1]):clean}}const digits=asciiDigits(clean).replace(/\\D/g,'');return digits.length>4?('•••••'+digits.slice(-4)):clean}}
async function loadCaptcha(){{const button=$('reload');button.disabled=true;$('captchaPlaceholder').hidden=false;$('captchaPlaceholder').textContent='در حال دریافت تصویر…';try{{const result=await request('/auth/captcha',{{method:'POST'}});captchaId=result.captcha_id;$('captcha').src='data:image/png;base64,'+result.image_base64;$('captchaPlaceholder').hidden=true}}catch(error){{captchaId='';$('captchaPlaceholder').textContent='تصویر دریافت نشد';status('status',error.message,'error')}}finally{{button.disabled=false}}}}
function setBusy(button,busy,label){{button.disabled=busy;if(busy){{button.dataset.label=button.textContent;button.textContent=label}}else if(button.dataset.label){{button.textContent=button.dataset.label;delete button.dataset.label}}}}
$('reload').addEventListener('click',loadCaptcha);document.querySelectorAll('.channel-option[data-channel]').forEach(button=>button.addEventListener('click',()=>setChannel(button.dataset.channel)));document.querySelectorAll('.channel-option[data-mode]').forEach(button=>button.addEventListener('click',()=>setMode(button.dataset.mode)));loadCaptcha();
$('send').addEventListener('click',async()=>{{const button=$('send');let requestStarted=false;setBusy(button,true,'در حال ارسال کد…');status('status','');try{{if(!$('identifier').value.trim())throw Error(selectedChannel==='email'?'آدرس ایمیل را وارد کنید.':'شماره موبایل را وارد کنید.');if(selectedChannel==='email'&&!$('identifier').checkValidity())throw Error('فرمت آدرس ایمیل را بررسی کنید.');if(!$('captchaCode').value.trim())throw Error('متن تصویر امنیتی را وارد کنید.');if(!captchaId)throw Error('تصویر امنیتی هنوز آماده نیست. چند لحظه دیگر دوباره تلاش کنید.');requestStarted=true;const result=await request('/auth/login/send-otp',{{method:'POST',headers:{{'Content-Type':'application/json'}},body:JSON.stringify({{identifier:$('identifier').value.trim(),channel:selectedChannel,captcha_id:captchaId,captcha_code:$('captchaCode').value.trim()}})}});loginSession=result.session_id;$('deliverySummary').textContent='کد تایید به '+maskDestination($('identifier').value,selectedChannel)+' ارسال شد.';$('otp').value='';$('loginSection').hidden=true;$('otpSection').hidden=false;$('stepLogin').classList.remove('active');$('stepConsent').classList.remove('active');$('otp').focus();status('otpStatus','کد ارسال شد. کد را وارد کنید.','success')}}catch(error){{status('status',error.message,'error');if(requestStarted)await loadCaptcha()}}finally{{setBusy(button,false)}}}});
$('otp').addEventListener('input',()=>{{const value=asciiDigits($('otp').value).replace(/\\D/g,'').slice(0,6);if($('otp').value!==value)$('otp').value=value}});
$('changeLogin').addEventListener('click',()=>{{status('otpStatus','','');$('otpSection').hidden=true;$('loginSection').hidden=false;$('stepLogin').classList.add('active');$('stepConsent').classList.remove('active');$('captchaCode').value='';loadCaptcha();$('identifier').focus()}});
async function continueToConsent(login){{const consent=await request('/ai/mcp/oauth/authorize/session',{{method:'POST',headers:{{'Content-Type':'application/json',Authorization:'ApiKey '+login.api_key}},body:JSON.stringify({{request_id:rid}})}});sessionKey=consent.consent_token;$('business').replaceChildren();const placeholder=document.createElement('option');placeholder.value='';placeholder.textContent='یک کسب‌وکار را انتخاب کنید';placeholder.disabled=true;placeholder.selected=true;$('business').append(placeholder);for(const item of consent.items){{const option=document.createElement('option');option.value=item.id;option.textContent=item.name;option.dataset.owner=item.owner?'1':'0';$('business').append(option)}}$('business').addEventListener('change',()=>{{const write=$('write');if(write){{write.disabled=$('business').selectedOptions[0]?.dataset.owner!=='1';if(write.disabled)write.checked=false}}}});$('business').dispatchEvent(new Event('change'));$('loginSection').hidden=true;$('otpSection').hidden=true;$('consent').hidden=false;$('stepLogin').classList.remove('active');$('stepConsent').classList.add('active');status('consentStatus','ورود موفق بود. دسترسی‌های درخواستی را بررسی کنید.','success')}}
$('verify').addEventListener('click',async()=>{{const button=$('verify');setBusy(button,true,'در حال بررسی کد…');status('otpStatus','');try{{const otp=asciiDigits($('otp').value.trim());if(otp.length!==6)throw Error('کد تایید باید ۶ رقم باشد.');const login=await request('/auth/login/verify-otp?session_id='+encodeURIComponent(loginSession)+'&otp_code='+encodeURIComponent(otp),{{method:'POST'}});await continueToConsent(login)}}catch(error){{status('otpStatus',error.message,'error')}}finally{{setBusy(button,false)}}}});
async function passwordLogin(){{const button=$('passwordLogin');let attempted=false;setBusy(button,true,'در حال ورود…');status('status','');try{{const identifier=$('identifier').value.trim(),password=$('password').value;if(!identifier)throw Error('ایمیل یا شماره موبایل را وارد کنید.');if(!password)throw Error('رمز عبور را وارد کنید.');if(!$('captchaCode').value.trim())throw Error('متن تصویر امنیتی را وارد کنید.');if(!captchaId)throw Error('تصویر امنیتی هنوز آماده نیست. چند لحظه دیگر دوباره تلاش کنید.');attempted=true;const login=await request('/auth/login',{{method:'POST',headers:{{'Content-Type':'application/json'}},body:JSON.stringify({{identifier,password,captcha_id:captchaId,captcha_code:$('captchaCode').value.trim()}})}});await continueToConsent(login)}}catch(error){{status('status',error.message,'error');if(attempted)await loadCaptcha()}}finally{{setBusy(button,false)}}}}
$('passwordLogin').addEventListener('click',passwordLogin);
async function decide(approved){{const button=approved?$('approve'):$('deny');setBusy(button,true,approved?'در حال اتصال…':'در حال ثبت…');status('consentStatus','');try{{const selected=[...document.querySelectorAll('[data-tool-name]:checked')].map(el=>el.dataset.toolName);const hasWrite=selected.some(name=>consentCatalog.some(tool=>tool.name===name&&!tool.read_only));const scopes=['ai:tools:read'];if(hasWrite)scopes.push('ai:tools:write');if($('offline')?.checked)scopes.push('offline_access');const result=await request('/ai/mcp/oauth/authorize/consent',{{method:'POST',headers:{{'Content-Type':'application/json',Authorization:'Bearer '+sessionKey}},body:JSON.stringify({{request_id:rid,business_id:Number($('business').value),approved,scopes,tool_permissions:selected}})}});location.assign(result.redirect_to)}}catch(error){{status('consentStatus',error.message,'error');setBusy(button,false)}}}}
let consentCatalog=[];
const categoryLabels={{invoices:'فاکتورها',products:'کالاها',inventory:'انبار',people:'اشخاص',financial:'مالی',crm:'CRM',reports:'گزارش‌ها',workflow:'گردش‌کار',export:'خروجی‌ها',integration:'یکپارچه‌سازی',other:'سایر'}};
async function loadConsentCatalog(){{
  const host=$('toolPermissions');host.replaceChildren();$('toolPermissionSection').hidden=true;
  if(!$('business').value)return;
  try{{
    const result=await request('/ai/mcp/oauth/authorize/catalog',{{method:'POST',headers:{{'Content-Type':'application/json',Authorization:'Bearer '+sessionKey}},body:JSON.stringify({{request_id:rid,business_id:Number($('business').value)}})}});
    consentCatalog=result.tools||[];const groups=new Map();
    for(const tool of consentCatalog){{const category=tool.category||'other';if(!groups.has(category))groups.set(category,[]);groups.get(category).push(tool)}}
    for(const [category,tools] of groups){{
      const heading=document.createElement('h4');heading.textContent=categoryLabels[category]||category;host.append(heading);
      for(const tool of tools){{
        const label=document.createElement('label');label.className='permission';const input=document.createElement('input');input.type='checkbox';input.dataset.toolName=tool.name;
        const isWrite=!tool.read_only;const writeAllowed=__WRITE_ALLOWED__;input.checked=false;input.disabled=isWrite&&!writeAllowed;
        const content=document.createElement('span');const title=document.createElement('strong');title.textContent=tool.name+(isWrite?' · تغییردهنده':' · فقط‌خواندنی');const description=document.createElement('small');description.textContent=tool.description||'';content.append(title,description);label.append(input,content);host.append(label)
      }}
    }}
    $('toolPermissionSection').hidden=false
  }}catch(error){{status('consentStatus',error.message,'error')}}
}}
$('business').addEventListener('change',loadConsentCatalog);
$('grantAll').addEventListener('click',()=>{{document.querySelectorAll('#toolPermissions input[type="checkbox"]:not(:disabled)').forEach(input=>input.checked=true)}});
$('approve').addEventListener('click',()=>{{if(!$('business').value){{status('consentStatus','ابتدا کسب‌وکار موردنظر را انتخاب کنید.','error');return}}decide(true)}});$('deny').addEventListener('click',()=>decide(false));
$('identifier').addEventListener('keydown',event=>{{if(event.key==='Enter'){{event.preventDefault();(loginMode==='password'?$('passwordLogin'):$('send')).click()}}}});$('captchaCode').addEventListener('keydown',event=>{{if(event.key==='Enter'){{event.preventDefault();(loginMode==='password'?$('passwordLogin'):$('send')).click()}}}});$('password').addEventListener('keydown',event=>{{if(event.key==='Enter'){{event.preventDefault();passwordLogin()}}}});$('otp').addEventListener('keydown',event=>{{if(event.key==='Enter'){{event.preventDefault();$('verify').click()}}}});
</script>
</body>
</html>'''.replace("__WRITE_ALLOWED__", "true")


@oauth_router.post("/authorize/session")
@rate_limit(max_requests=20, window_seconds=600, error_message="درخواست‌های ورود OAuth بیش از حد مجاز است.")
def create_consent_session(payload: dict, db: Session = Depends(get_db), ctx: AuthContext = Depends(get_current_user)) -> dict:
    db = ctx.db
    if db is None:
        raise HTTPException(403, "A business user account is required")
    raw_request_id = payload.get("request_id")
    authorization = db.query(McpOAuthAuthorizationRequest).filter(
        McpOAuthAuthorizationRequest.request_hash == _hash(str(raw_request_id or "")),
        McpOAuthAuthorizationRequest.expires_at > datetime.utcnow(),
    ).with_for_update().first()
    if not authorization or not ctx.is_user_active():
        raise HTTPException(400, "Authorization request expired or invalid")
    if authorization.user_id is not None:
        raise HTTPException(400, "This authorization request was already authenticated")
    businesses = db.query(Business).filter(Business.deleted_at.is_(None)).all()
    result = []
    for business in businesses:
        if business.owner_id == ctx.get_user_id():
            result.append({"id": business.id, "name": business.name, "owner": True})
            continue
        permission = db.query(BusinessPermission).filter(
            BusinessPermission.user_id == ctx.get_user_id(),
            BusinessPermission.business_id == business.id,
        ).first()
        raw = AuthContext._normalize_permissions_value(permission.business_permissions or {}) if permission else {}
        if permission and raw.get("join") is True and membership_is_active(permission):
            result.append({"id": business.id, "name": business.name, "owner": False})
    result.sort(key=lambda item: item["name"].casefold())
    if not result:
        raise HTTPException(403, "No active business is available to this account")
    consent_token = "mcp_consent_" + secrets.token_urlsafe(32)
    authorization.user_id = ctx.get_user_id()
    authorization.consent_token_hash = _hash(consent_token)
    authorization.consent_expires_at = min(authorization.expires_at, datetime.utcnow() + timedelta(minutes=5))
    login_key = db.query(ApiKey).filter(ApiKey.id == ctx.api_key_id, ApiKey.key_type == "session").first()
    if not login_key:
        raise HTTPException(401, "Short-lived login session required")
    login_key.revoked_at = datetime.utcnow()
    get_cache().delete(f"api_key:{login_key.key_hash}")
    db.add(authorization)
    db.add(login_key)
    db.commit()
    return {"consent_token": consent_token, "expires_in": 300, "items": result}


@oauth_router.post("/authorize/catalog")
@rate_limit(max_requests=60, window_seconds=600, error_message="درخواست‌های فهرست ابزار بیش از حد مجاز است.")
def consent_catalog(payload: dict, request: Request, db: Session = Depends(get_db)) -> dict:
    auth_header = request.headers.get("authorization", "")
    scheme, _, raw_token = auth_header.partition(" ")
    raw_request_id = payload.get("request_id")
    row = db.query(McpOAuthAuthorizationRequest).filter(
        McpOAuthAuthorizationRequest.request_hash == _hash(str(raw_request_id or "")),
        McpOAuthAuthorizationRequest.expires_at > datetime.utcnow(),
        McpOAuthAuthorizationRequest.user_id.is_not(None),
        McpOAuthAuthorizationRequest.consent_expires_at > datetime.utcnow(),
    ).first()
    if (scheme.lower() != "bearer" or not raw_token.startswith("mcp_consent_") or not row
            or not row.consent_token_hash
            or not secrets.compare_digest(row.consent_token_hash, _hash(raw_token))):
        raise HTTPException(401, "A valid one-time OAuth consent token is required")
    user = db.get(User, row.user_id)
    if not user or not user.is_active:
        raise HTTPException(401, "The authenticated user is no longer active")
    try:
        business_id = int(payload.get("business_id"))
    except (TypeError, ValueError):
        raise HTTPException(400, "A business must be selected")
    ctx = AuthContext(user=user, api_key_id=0, business_id=business_id, db=db)
    if not _has_explicit_business_access(db, user.id, business_id):
        raise HTTPException(403, "Business access is no longer active")
    catalog = _consent_tool_catalog(db, ctx, business_id)
    return {"tools": catalog}


@oauth_router.post("/authorize/consent")
@rate_limit(max_requests=30, window_seconds=600, error_message="تاییدهای OAuth بیش از حد مجاز است.")
def consent(payload: dict, request: Request, db: Session = Depends(get_db)) -> dict:
    auth_header = request.headers.get("authorization", "")
    scheme, _, raw_consent_token = auth_header.partition(" ")
    if scheme.lower() != "bearer" or not raw_consent_token.startswith("mcp_consent_"):
        raise HTTPException(401, "A one-time OAuth consent token is required")
    raw_request_id = payload.get("request_id")
    row = db.query(McpOAuthAuthorizationRequest).filter(
        McpOAuthAuthorizationRequest.request_hash == _hash(str(raw_request_id or "")),
        McpOAuthAuthorizationRequest.expires_at > datetime.utcnow(),
        McpOAuthAuthorizationRequest.user_id.is_not(None),
        McpOAuthAuthorizationRequest.consent_expires_at > datetime.utcnow(),
    ).with_for_update().first()
    if not row or not row.consent_token_hash or not secrets.compare_digest(row.consent_token_hash, _hash(raw_consent_token)):
        raise HTTPException(400, "Authorization request expired or already used")
    user = db.get(User, row.user_id)
    if not user or not user.is_active:
        raise HTTPException(401, "The authenticated user is no longer active")
    client = db.query(McpOAuthClient).filter(McpOAuthClient.client_id == row.client_id).first()
    if not client or row.redirect_uri not in (client.redirect_uris or []):
        raise HTTPException(400, "OAuth client registration is invalid")
    approved = payload.get("approved") is True
    redirect = row.redirect_uri
    if not approved:
        response_params = {"error": "access_denied", "iss": _issuer(request)}
        if row.state:
            response_params["state"] = row.state
        target = _append_query(redirect, response_params)
        db.delete(row)
        db.commit()
        return {"redirect_to": target}
    try:
        business_id = int(payload.get("business_id"))
    except (TypeError, ValueError):
        raise HTTPException(400, "A business must be selected")
    ctx = AuthContext(user=user, api_key_id=0, business_id=business_id, db=db)
    if (not ctx.is_user_active() or
            not _has_explicit_business_access(db, ctx.get_user_id(), business_id)):
        raise HTTPException(403, "Business access is no longer active")
    raw_tool_permissions = payload.get("tool_permissions")
    if (not isinstance(raw_tool_permissions, list)
            or not all(isinstance(name, str) for name in raw_tool_permissions)
            or len(raw_tool_permissions) != len(set(raw_tool_permissions))):
        raise HTTPException(400, "Invalid tool permissions")
    tool_catalog = _consent_tool_catalog(db, ctx, business_id)
    available_tools = {tool["name"]: tool for tool in tool_catalog}
    selected_tools = set(raw_tool_permissions)
    if not selected_tools <= set(available_tools):
        raise HTTPException(400, "A selected tool is unavailable for this business member")
    selected_write = any(not available_tools[name]["read_only"] for name in selected_tools)
    requested = set(row.scopes or [])
    raw_scopes = payload.get("scopes")
    if not isinstance(raw_scopes, list) or not all(isinstance(scope, str) for scope in raw_scopes):
        raise HTTPException(400, "Invalid consent scopes")
    scopes = set(raw_scopes)
    # The consent UI is the authority for optional write access. Allow it to
    # grant the server-advertised write scope even when the client requested
    # only the required read scope; all selected tools are still user-filtered.
    if (not scopes or not scopes <= (requested | {WRITE_SCOPE})
            or READ_SCOPE not in scopes or not scopes <= AUTH_SCOPES):
        raise HTTPException(400, "Invalid consent scopes")
    if (selected_write != (WRITE_SCOPE in scopes)):
        raise HTTPException(400, "Write scope must match the selected tools")
    raw_code = "mcp_code_" + secrets.token_urlsafe(40)
    db.add(McpOAuthAuthorizationCode(
        code_hash=_hash(raw_code), client_id=row.client_id, redirect_uri=row.redirect_uri,
        resource=row.resource, user_id=ctx.get_user_id(), business_id=business_id,
        scopes=sorted(scopes), tool_permissions=sorted(selected_tools), code_challenge=row.code_challenge,
        expires_at=datetime.utcnow() + CODE_TTL,
    ))
    response_params = {"code": raw_code, "iss": _issuer(request)}
    if row.state:
        response_params["state"] = row.state
    target = _append_query(redirect, response_params)
    db.delete(row)
    db.commit()
    return {"redirect_to": target}


@oauth_router.post("/token")
@rate_limit(max_requests=60, window_seconds=60, error_message="درخواست توکن بیش از حد مجاز است.")
async def token(request: Request, db: Session = Depends(get_db)) -> JSONResponse:
    try:
        form = await request.form()
    except Exception:
        return _json_error("invalid_request", "Form-encoded request body required")
    grant_type = str(form.get("grant_type", ""))
    client_id = str(form.get("client_id", ""))
    oauth_grant_id = secrets.token_urlsafe(32)
    code_row = None
    refresh_row = None
    client = db.query(McpOAuthClient).filter(McpOAuthClient.client_id == client_id).first()
    if not client:
        return _json_error("invalid_client", "Unknown client")
    if grant_type == "authorization_code":
        if "authorization_code" not in (client.grant_types or []):
            return _json_error("unauthorized_client", "Client is not permitted to use this grant type")
        code = str(form.get("code", ""))
        redirect_uri = str(form.get("redirect_uri", ""))
        verifier = str(form.get("code_verifier", ""))
        resource = str(form.get("resource", ""))
        if not _VERIFIER_RE.fullmatch(verifier):
            return _json_error("invalid_grant", "Invalid PKCE verifier")
        code_row = db.query(McpOAuthAuthorizationCode).filter(
            McpOAuthAuthorizationCode.code_hash == _hash(code),
            McpOAuthAuthorizationCode.client_id == client_id,
            McpOAuthAuthorizationCode.expires_at > datetime.utcnow(),
            McpOAuthAuthorizationCode.consumed_at.is_(None),
        ).with_for_update().first()
        if not code_row or code_row.redirect_uri != redirect_uri or code_row.resource != resource:
            return _json_error("invalid_grant", "Authorization code, redirect URI, or resource is invalid")
        challenge = __import__("base64").urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).rstrip(b"=").decode()
        if not secrets.compare_digest(challenge, code_row.code_challenge):
            return _json_error("invalid_grant", "PKCE verification failed")
        code_row.consumed_at = datetime.utcnow()
        user_id, business_id, scopes = code_row.user_id, code_row.business_id, list(code_row.scopes or [])
        tool_permissions = list(code_row.tool_permissions or [])
        resource = code_row.resource
        db.add(code_row)
        db.flush()
    elif grant_type == "refresh_token":
        if "refresh_token" not in (client.grant_types or []):
            return _json_error("unauthorized_client", "Client is not permitted to use this grant type")
        refresh = str(form.get("refresh_token", ""))
        resource = str(form.get("resource", ""))
        refresh_row = db.query(McpOAuthRefreshToken).filter(
            McpOAuthRefreshToken.token_hash == _hash(refresh),
            McpOAuthRefreshToken.client_id == client_id,
        ).with_for_update().first()
        if refresh_row and refresh_row.revoked_at is not None:
            # A consumed refresh token was replayed: revoke this client's grant family.
            now = datetime.utcnow()
            db.query(McpOAuthRefreshToken).filter(
                McpOAuthRefreshToken.grant_id == refresh_row.grant_id,
                McpOAuthRefreshToken.revoked_at.is_(None),
            ).update({McpOAuthRefreshToken.revoked_at: now}, synchronize_session=False)
            db.query(ApiKey).filter(
                ApiKey.key_type == "mcp", ApiKey.oauth_client_id == client_id,
                ApiKey.oauth_grant_id == refresh_row.grant_id,
                ApiKey.revoked_at.is_(None),
            ).update({ApiKey.revoked_at: now}, synchronize_session=False)
            db.commit()
            return _json_error("invalid_grant", "Refresh token reuse detected; grant revoked")
        if not refresh_row or refresh_row.expires_at <= datetime.utcnow() or refresh_row.resource != resource:
            return _json_error("invalid_grant", "Refresh token is invalid, expired, or already used")
        requested_scope = str(form.get("scope", "")).split()
        stored_scopes = set(refresh_row.scopes or [])
        access_scopes_requested = set(requested_scope)
        if requested_scope and (
            not access_scopes_requested <= (stored_scopes - {"offline_access"})
            or READ_SCOPE not in access_scopes_requested
        ):
            return _json_error("invalid_scope", "Refresh scope cannot exceed the authorized scope")
        if requested_scope:
            refresh_row.scopes = sorted(
                access_scopes_requested | ({"offline_access"} if "offline_access" in stored_scopes else set())
            )
        refresh_row.revoked_at = datetime.utcnow()
        user_id, business_id, scopes = refresh_row.user_id, refresh_row.business_id, list(refresh_row.scopes or [])
        tool_permissions = list(refresh_row.tool_permissions or [])
        oauth_grant_id = refresh_row.grant_id
        db.add(refresh_row)
    else:
        return _json_error("unsupported_grant_type", "Only authorization_code and refresh_token are supported")
    user = db.get(User, user_id)
    probe = AuthContext(user=user, api_key_id=0, business_id=business_id, db=db) if user else None
    if (not user or not user.is_active or not probe or
            not _has_explicit_business_access(db, user_id, business_id)):
        now = datetime.utcnow()
        if grant_type == "refresh_token" and refresh_row is not None:
            db.query(McpOAuthRefreshToken).filter(
                McpOAuthRefreshToken.grant_id == refresh_row.grant_id,
                McpOAuthRefreshToken.revoked_at.is_(None),
            ).update({McpOAuthRefreshToken.revoked_at: now}, synchronize_session=False)
            db.query(ApiKey).filter(
                ApiKey.key_type == "mcp",
                ApiKey.oauth_client_id == client_id,
                ApiKey.oauth_grant_id == refresh_row.grant_id,
                ApiKey.revoked_at.is_(None),
            ).update({ApiKey.revoked_at: now}, synchronize_session=False)
        # Keep the authorization code consumed even when the user or business
        # access changed between consent and token exchange.
        db.commit()
        return _json_error("invalid_grant", "User or business access is no longer active")
    session_ttl = _session_ttl(db)
    access_token, access_hash = generate_api_key(prefix="mcp_live_")
    access_scopes = [scope for scope in scopes if scope != "offline_access"]
    access_row = ApiKey(
        user_id=user_id, key_hash=access_hash, key_type="mcp", business_id=business_id,
        mcp_resource=resource, oauth_client_id=client_id, oauth_grant_id=oauth_grant_id,
        name=f"OAuth: {client.client_name}"[:100],
        scopes=json.dumps(access_scopes), mcp_tool_permissions=tool_permissions,
        expires_at=datetime.utcnow() + session_ttl,
    )
    db.add(access_row)
    returned = {"access_token": access_token, "token_type": "Bearer", "expires_in": int(session_ttl.total_seconds()), "scope": " ".join(access_scopes)}
    if "refresh_token" in (client.grant_types or []) and "offline_access" in scopes:
        refresh_token, refresh_hash = generate_api_key(prefix="mcp_refresh_")
        refresh_row = McpOAuthRefreshToken(
            token_hash=refresh_hash, client_id=client_id, user_id=user_id, business_id=business_id,
            grant_id=oauth_grant_id, resource=resource, scopes=scopes,
            tool_permissions=tool_permissions, expires_at=datetime.utcnow() + session_ttl,
        )
        db.add(refresh_row)
        db.flush()
        if grant_type == "refresh_token":
            previous = db.query(McpOAuthRefreshToken).filter(
                McpOAuthRefreshToken.token_hash == _hash(str(form.get("refresh_token", ""))),
                McpOAuthRefreshToken.client_id == client_id,
            ).first()
            if previous:
                previous.replaced_by_id = refresh_row.id
                db.add(previous)
        returned["refresh_token"] = refresh_token
    db.commit()
    return JSONResponse(returned, headers={"Cache-Control": "no-store", "Pragma": "no-cache"})


@oauth_router.post("/revoke")
@rate_limit(max_requests=60, window_seconds=60, error_message="درخواست‌های لغو OAuth بیش از حد مجاز است.")
async def revoke(request: Request, db: Session = Depends(get_db)) -> JSONResponse:
    try:
        form = await request.form()
    except Exception:
        return _json_error("invalid_request", "Form-encoded request body required")
    client_id, raw_token = str(form.get("client_id", "")), str(form.get("token", ""))
    if not db.query(McpOAuthClient).filter(McpOAuthClient.client_id == client_id).first():
        return _json_error("invalid_client", "Unknown client")
    token_hash = _hash(raw_token)
    refresh = db.query(McpOAuthRefreshToken).filter(
        McpOAuthRefreshToken.token_hash == token_hash, McpOAuthRefreshToken.client_id == client_id,
    ).first()
    if refresh and refresh.revoked_at is None:
        refresh.revoked_at = datetime.utcnow()
        db.add(refresh)
        now = datetime.utcnow()
        db.query(McpOAuthRefreshToken).filter(
            McpOAuthRefreshToken.grant_id == refresh.grant_id,
            McpOAuthRefreshToken.revoked_at.is_(None),
        ).update({McpOAuthRefreshToken.revoked_at: now}, synchronize_session=False)
        db.query(ApiKey).filter(
            ApiKey.key_type == "mcp", ApiKey.oauth_grant_id == refresh.grant_id,
            ApiKey.revoked_at.is_(None),
        ).update({ApiKey.revoked_at: now}, synchronize_session=False)
    access = db.query(ApiKey).filter(
        ApiKey.key_hash == token_hash,
        ApiKey.key_type == "mcp",
        ApiKey.oauth_client_id == client_id,
    ).first()
    if access and access.revoked_at is None:
        now = datetime.utcnow()
        if access.oauth_grant_id:
            db.query(McpOAuthRefreshToken).filter(
                McpOAuthRefreshToken.grant_id == access.oauth_grant_id,
                McpOAuthRefreshToken.client_id == client_id,
                McpOAuthRefreshToken.revoked_at.is_(None),
            ).update({McpOAuthRefreshToken.revoked_at: now}, synchronize_session=False)
            db.query(ApiKey).filter(
                ApiKey.oauth_grant_id == access.oauth_grant_id,
                ApiKey.oauth_client_id == client_id,
                ApiKey.key_type == "mcp",
                ApiKey.revoked_at.is_(None),
            ).update({ApiKey.revoked_at: now}, synchronize_session=False)
        else:
            access.revoked_at = now
            db.add(access)
    db.commit()
    return JSONResponse({}, headers={"Cache-Control": "no-store"})
