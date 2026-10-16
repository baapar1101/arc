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
ACCESS_TTL = timedelta(minutes=15)
REFRESH_TTL = timedelta(days=30)
AUTH_REQUEST_TTL = timedelta(minutes=10)
CODE_TTL = timedelta(minutes=2)
_VERIFIER_RE = re.compile(r"^[A-Za-z0-9._~-]{43,128}$")


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
        raw_request_id, client.client_name, WRITE_SCOPE in requested_scopes,
        "offline_access" in requested_scopes,
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


def _authorization_html(request_id: str, client_name: str, write_requested: bool, offline_requested: bool) -> str:
    safe_name = html.escape(client_name)
    api_json = json.dumps(get_settings().api_v1_prefix)
    request_json = json.dumps(request_id)
    write_option = (
        '<label class="permission permission--optional"><input type="checkbox" id="write">'
        '<span><strong>ابزارهای ویرایشی</strong><small>امکان ثبت یا تغییر اطلاعات کسب‌وکار (ویژهٔ مالک)</small></span></label>'
        if write_requested else ""
    )
    offline_option = (
        '<label class="permission permission--optional"><input type="checkbox" id="offline">'
        '<span><strong>تمدید اتصال</strong><small>تمدید اتصال تا ۳۰ روز، بدون ورود دوباره</small></span></label>'
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
    body {{ margin:0; min-height:100vh; min-height:100dvh; padding:clamp(16px,4vw,48px); display:grid; place-items:center; color:var(--ink); background:radial-gradient(ellipse at 50% 0%,#e3eff7 0,transparent 48%),var(--canvas); font-family:YekanBakh,Tahoma,sans-serif; font-size:15px; line-height:1.7; }}
    button,input,select {{ font:inherit; }}
    .shell {{ width:min(100%,520px); }}
    .card {{ overflow:hidden; background:var(--surface); border:1px solid rgba(15,76,129,.09); border-radius:24px; box-shadow:0 24px 72px rgba(21,52,76,.12),0 2px 8px rgba(21,52,76,.04); }}
    .card-head {{ padding:clamp(22px,6vw,36px) clamp(20px,6vw,40px) 24px; text-align:center; }}
    .brand-mark {{ width:56px; height:56px; margin:0 auto 15px; display:grid; place-items:center; color:#fff; background:linear-gradient(145deg,#17639d,var(--brand-strong)); border-radius:18px; box-shadow:0 8px 18px rgba(15,76,129,.22); }}
    .brand-mark svg {{ width:29px; height:29px; }}
    .eyebrow {{ margin:0 0 3px; color:var(--brand); font-size:12px; font-weight:600; }}
    h1 {{ margin:0; font-size:clamp(22px,5vw,27px); line-height:1.4; font-weight:700; letter-spacing:-.02em; }}
    .intro {{ margin:10px auto 0; max-width:390px; color:var(--muted); font-size:14px; line-height:1.9; }}
    .client {{ color:var(--ink); font-weight:600; }}
    .secure-note {{ margin-top:15px; display:inline-flex; align-items:center; gap:7px; color:#4e6b7e; font-size:12px; }}
    .secure-note svg {{ width:15px; height:15px; color:#31836a; }}
    .steps {{ display:flex; align-items:center; justify-content:center; gap:10px; margin-top:22px; color:#7890a1; font-size:12px; }}
    .step {{ display:flex; align-items:center; gap:7px; }}
    .step-number {{ width:22px; height:22px; display:grid; place-items:center; border:1px solid #d6e1e9; border-radius:50%; font-family:Roboto,YekanBakh,sans-serif; font-size:11px; }}
    .step.active {{ color:var(--brand); font-weight:600; }}
    .step.active .step-number {{ color:#fff; background:var(--brand); border-color:var(--brand); }}
    .step-line {{ width:28px; height:1px; background:#dce5eb; }}
    .card-body {{ padding:0 clamp(20px,6vw,40px) clamp(22px,6vw,36px); }}
    .section-label {{ margin:0 0 12px; color:#536b7c; font-size:13px; font-weight:600; }}
    .field {{ display:block; margin:0 0 15px; }}
    .field-label {{ display:block; margin-bottom:6px; color:#314b5d; font-size:13px; font-weight:600; }}
    .control {{ width:100%; min-height:48px; padding:10px 13px; color:var(--ink); background:#fff; border:1px solid #d8e2e9; border-radius:11px; outline:none; transition:border-color .16s,box-shadow .16s; }}
    .control:focus {{ border-color:#4c8ab4; box-shadow:0 0 0 3px rgba(15,76,129,.11); }}
    .control::placeholder {{ color:#99a8b4; }}
    .captcha-row {{ display:grid; grid-template-columns:minmax(0,1fr) 105px; gap:10px; align-items:end; }}
    .captcha-box {{ height:48px; display:flex; align-items:center; justify-content:center; overflow:hidden; background:#f7fafc; border:1px solid var(--line); border-radius:11px; }}
    .captcha-box img {{ max-width:100%; max-height:44px; object-fit:contain; }}
    .icon-button {{ width:38px; height:38px; flex:0 0 38px; display:grid; place-items:center; color:#547187; background:transparent; border:0; border-radius:9px; cursor:pointer; }}
    .captcha-tools {{ display:flex; align-items:center; gap:5px; }}
    .captcha-tools .captcha-box {{ flex:1; }}
    .icon-button:hover {{ color:var(--brand); background:#edf4f8; }}
    .icon-button svg {{ width:18px; height:18px; }}
    .channel-row {{ display:grid; grid-template-columns:145px minmax(0,1fr); gap:10px; align-items:center; }}
    .primary,.secondary {{ width:100%; min-height:48px; padding:10px 16px; border-radius:11px; font-weight:600; cursor:pointer; transition:background .16s,border-color .16s,transform .16s; }}
    .primary {{ color:#fff; background:var(--brand); border:1px solid var(--brand); box-shadow:0 5px 12px rgba(15,76,129,.14); }}
    .primary:hover:not(:disabled) {{ background:var(--brand-strong); border-color:var(--brand-strong); transform:translateY(-1px); }}
    .secondary {{ color:#496579; background:#fff; border:1px solid #d8e2e9; }}
    .secondary:hover:not(:disabled) {{ background:#f6f9fb; border-color:#bdcdd9; }}
    button:disabled {{ opacity:.58; cursor:wait; }}
    .status {{ min-height:24px; margin:13px 0 0; color:var(--muted); font-size:13px; }}
    .status[data-tone="error"] {{ color:var(--danger); }}
    .status[data-tone="success"] {{ color:var(--success); }}
    .divider {{ height:1px; margin:19px 0; background:var(--line); }}
    .permission-list {{ display:grid; gap:9px; margin:0 0 17px; }}
    .permission {{ display:flex; align-items:flex-start; gap:11px; padding:13px; background:#f7fafc; border:1px solid #e5edf2; border-radius:12px; cursor:pointer; }}
    .permission input {{ width:18px; height:18px; margin:3px 0 0; accent-color:var(--brand); flex:0 0 auto; }}
    .permission span {{ display:grid; gap:1px; }}
    .permission strong {{ color:#29465a; font-size:13px; font-weight:600; }}
    .permission small {{ color:var(--muted); font-size:12px; }}
    .permission--optional {{ background:#fff; }}
    .button-row {{ display:grid; grid-template-columns:1fr 1fr; gap:10px; margin-top:13px; }}
    .footnote {{ margin:17px 0 0; color:#8192a0; text-align:center; font-size:11px; }}
    @media(max-width:420px) {{ body {{ padding:12px; }} .card {{ border-radius:19px; }} .channel-row {{ grid-template-columns:118px minmax(0,1fr); gap:8px; }} .steps {{ gap:7px; }} .step-line {{ width:17px; }} .intro {{ font-size:13px; }} }}
    @media(prefers-reduced-motion:reduce) {{ *,*::before,*::after {{ scroll-behavior:auto !important; transition:none !important; }} }}
  </style>
</head>
<body>
  <main class="shell">
    <article class="card" aria-labelledby="page-title">
      <header class="card-head">
        <div class="brand-mark" aria-hidden="true"><svg viewBox="0 0 24 24" fill="none"><path d="M12 2.8 20 6v5.4c0 5.2-3.5 8.4-8 10.1-4.5-1.7-8-4.9-8-10.1V6l8-3.2Z" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/><path d="m8.7 12.1 2.2 2.2 4.6-4.7" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg></div>
        <p class="eyebrow">حسابیکس · اتصال به هوش مصنوعی</p>
        <h1 id="page-title">اتصال امن حساب کاربری</h1>
        <p class="intro"><span class="client">{safe_name}</span> می‌خواهد به ابزارهای حسابیکس شما متصل شود. ورود و انتخاب کسب‌وکار را فقط در صورتی ادامه دهید که این درخواست را خودتان آغاز کرده‌اید.</p>
        <span class="secure-note"><svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="M12 3 19 6v5c0 4.6-3 7.5-7 9-4-1.5-7-4.4-7-9V6l7-3Z" stroke="currentColor" stroke-width="1.8"/><path d="m9 11.5 2 2 4-4" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>ورود مستقیم و رمزنگاری‌شده در حسابیکس</span>
        <div class="steps" aria-label="مراحل اتصال"><span class="step active" id="stepLogin"><span class="step-number">۱</span> ورود</span><span class="step-line"></span><span class="step" id="stepConsent"><span class="step-number">۲</span> انتخاب دسترسی</span></div>
      </header>
      <div class="card-body">
        <section id="loginSection" aria-labelledby="login-heading">
          <h2 class="section-label" id="login-heading">با شماره موبایل یا ایمیل حسابیکس وارد شوید</h2>
          <label class="field"><span class="field-label">شماره موبایل یا ایمیل</span><input class="control" id="identifier" autocomplete="username" maxlength="255" placeholder="مثلاً ۰۹۱۲۱۲۳۴۵۶۷" required></label>
          <div class="captcha-row">
            <label class="field"><span class="field-label">کد امنیتی</span><input class="control" id="captchaCode" maxlength="10" autocomplete="off" placeholder="متن تصویر را وارد کنید" required></label>
            <div class="captcha-tools"><div class="captcha-box"><img id="captcha" alt="تصویر کد امنیتی"></div><button class="icon-button" id="reload" type="button" aria-label="دریافت کد امنیتی جدید" title="کد جدید"><svg viewBox="0 0 24 24" fill="none"><path d="M20 7v5h-5M4 17v-5h5" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/><path d="M6 9a7 7 0 0 1 12-2l2 2M4 15l2 2a7 7 0 0 0 12-2" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg></button></div>
          </div>
          <div class="channel-row"><label><span class="field-label">روش دریافت کد</span><select class="control" id="channel"><option value="sms">پیامک</option><option value="email">ایمیل</option></select></label><button class="primary" id="send" type="button">ارسال کد ورود</button></div>
          <p id="status" class="status" role="status" aria-live="polite"></p>
        </section>
        <section id="otpSection" hidden aria-labelledby="otp-heading">
          <div class="divider"></div><h2 class="section-label" id="otp-heading">کد ارسال‌شده را وارد کنید</h2>
          <label class="field"><span class="field-label">کد یک‌بارمصرف</span><input class="control" id="otp" inputmode="numeric" autocomplete="one-time-code" maxlength="6" placeholder="کد ۶ رقمی" dir="ltr" required></label>
          <button class="primary" id="verify" type="button">تایید و ادامه</button>
          <p class="status" id="otpStatus" role="status" aria-live="polite"></p>
        </section>
        <section id="consent" hidden aria-labelledby="consent-heading">
          <div class="divider"></div><h2 class="section-label" id="consent-heading">کسب‌وکار و دسترسی را انتخاب کنید</h2>
          <label class="field"><span class="field-label">کسب‌وکار</span><select class="control" id="business" required></select></label>
          <div class="permission-list"><label class="permission"><input type="checkbox" checked disabled><span><strong>مشاهدهٔ اطلاعات و گزارش‌ها</strong><small>دسترسی پایه برای استفاده از ابزارهای حسابیکس</small></span></label>{write_option}{offline_option}</div>
          <div class="button-row"><button class="primary" id="approve" type="button">تایید و اتصال</button><button class="secondary" id="deny" type="button">رد درخواست</button></div>
          <p class="status" id="consentStatus" role="status" aria-live="polite"></p>
        </section>
      </div>
    </article>
    <p class="footnote">با تایید شما، فقط کسب‌وکار و سطح دسترسی انتخاب‌شده متصل می‌شود.</p>
  </main>
<script>
const api={api_json},rid={request_json};let captchaId='',loginSession='',sessionKey='';
const $=id=>document.getElementById(id);
function status(id,message,tone=''){{const el=$(id);el.textContent=message;el.dataset.tone=tone}}
async function request(path,options={{}}){{
  let response;try{{response=await fetch(api+path,options)}}catch{{throw Error('ارتباط با سرور برقرار نشد؛ اتصال اینترنت را بررسی کنید.')}}
  let payload;try{{payload=await response.json()}}catch{{if(response.status===404)throw Error(`مسیر API «${{path}}» در سرور پیدا نشد (HTTP 404). سرور یا تنظیم Nginx نیاز به به‌روزرسانی دارد.`);throw Error(`پاسخ سرور معتبر نیست (HTTP ${{response.status}}). اگر خطا ادامه دارد، صفحه را دوباره باز کنید.`)}}
  const error=payload?.error&&typeof payload.error==='object'?payload.error:payload;
  if(!response.ok||payload?.success===false){{
    if(response.status===404&&error?.code==='SESSION_NOT_FOUND')throw Error('نشست ورود منقضی شده است. کد تازه دریافت کنید و دوباره وارد کنید.');
    if(response.status===404&&error?.code==='USER_NOT_FOUND')throw Error('برای این شماره یا ایمیل حساب فعالی پیدا نشد. شناسهٔ ورود حسابیکس را بررسی کنید.');
    if(response.status===404&&(!error?.code||error.code==='HTTP_ERROR'))throw Error(`مسیر API «${{path}}» در نسخهٔ فعلی سرور پیدا نشد (HTTP 404). صفحه را تازه کنید؛ اگر مشکل ماند، سرور باید به‌روزرسانی شود.`);
    throw Error(error?.message||payload?.detail||`درخواست ناموفق بود (HTTP ${{response.status}}).`)
  }}
  return payload?.data??payload;
}}
function asciiDigits(value){{return value.replace(/[۰-۹٠-٩]/g,d=>String('۰۱۲۳۴۵۶۷۸۹٠١٢٣٤٥٦٧٨٩'.indexOf(d)%10))}}
async function loadCaptcha(){{try{{const result=await request('/auth/captcha',{{method:'POST'}});captchaId=result.captcha_id;$('captcha').src='data:image/png;base64,'+result.image_base64}}catch(error){{status('status',error.message,'error')}}}}
function setBusy(button,busy,label){{button.disabled=busy;if(busy){{button.dataset.label=button.textContent;button.textContent=label}}else if(button.dataset.label){{button.textContent=button.dataset.label;delete button.dataset.label}}}}
$('reload').addEventListener('click',loadCaptcha);loadCaptcha();
$('send').addEventListener('click',async()=>{{const button=$('send');setBusy(button,true,'در حال ارسال…');status('status','');try{{if(!$('identifier').value.trim()||!$('captchaCode').value.trim())throw Error('شماره موبایل یا ایمیل و کد امنیتی را وارد کنید.');const result=await request('/auth/login/send-otp',{{method:'POST',headers:{{'Content-Type':'application/json'}},body:JSON.stringify({{identifier:$('identifier').value.trim(),channel:$('channel').value,captcha_id:captchaId,captcha_code:$('captchaCode').value.trim()}})}});loginSession=result.session_id;$('otpSection').hidden=false;$('otp').focus();status('otpStatus',result.message||'کد ورود ارسال شد. پیامک یا ایمیل خود را بررسی کنید.','success')}}catch(error){{status('status',error.message,'error');await loadCaptcha()}}finally{{setBusy(button,false)}}}});
 $('verify').addEventListener('click',async()=>{{const button=$('verify');setBusy(button,true,'در حال بررسی…');status('otpStatus','');try{{const otp=asciiDigits($('otp').value.trim());if(!otp)throw Error('کد یک‌بارمصرف را وارد کنید.');const login=await request('/auth/login/verify-otp?session_id='+encodeURIComponent(loginSession)+'&otp_code='+encodeURIComponent(otp),{{method:'POST'}});const consent=await request('/ai/mcp/oauth/authorize/session',{{method:'POST',headers:{{'Content-Type':'application/json',Authorization:'ApiKey '+login.api_key}},body:JSON.stringify({{request_id:rid}})}});sessionKey=consent.consent_token;$('business').replaceChildren();for(const item of consent.items){{const option=document.createElement('option');option.value=item.id;option.textContent=item.name;option.dataset.owner=item.owner?'1':'0';$('business').append(option)}}$('business').addEventListener('change',()=>{{const write=$('write');if(write){{write.disabled=$('business').selectedOptions[0]?.dataset.owner!=='1';if(write.disabled)write.checked=false}}}});$('business').dispatchEvent(new Event('change'));$('loginSection').hidden=true;$('otpSection').hidden=true;$('consent').hidden=false;$('stepLogin').classList.remove('active');$('stepConsent').classList.add('active');status('consentStatus','ورود موفق بود. کسب‌وکار و دسترسی‌های درخواستی را بررسی کنید.','success')}}catch(error){{status('otpStatus',error.message,'error')}}finally{{setBusy(button,false)}}}});
async function decide(approved){{const button=approved?$('approve'):$('deny');setBusy(button,true,approved?'در حال اتصال…':'در حال ثبت…');status('consentStatus','');try{{const scopes=['ai:tools:read'];if($('write')?.checked)scopes.push('ai:tools:write');if($('offline')?.checked)scopes.push('offline_access');const result=await request('/ai/mcp/oauth/authorize/consent',{{method:'POST',headers:{{'Content-Type':'application/json',Authorization:'Bearer '+sessionKey}},body:JSON.stringify({{request_id:rid,business_id:Number($('business').value),approved,scopes}})}});location.assign(result.redirect_to)}}catch(error){{status('consentStatus',error.message,'error');setBusy(button,false)}}}}
$('approve').addEventListener('click',()=>decide(true));$('deny').addEventListener('click',()=>decide(false));
</script>
</body>
</html>'''


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
    requested = set(row.scopes or [])
    raw_scopes = payload.get("scopes")
    if not isinstance(raw_scopes, list) or not all(isinstance(scope, str) for scope in raw_scopes):
        raise HTTPException(400, "Invalid consent scopes")
    scopes = set(raw_scopes)
    if not scopes or not scopes <= requested or READ_SCOPE not in scopes or not scopes <= AUTH_SCOPES:
        raise HTTPException(400, "Invalid consent scopes")
    if WRITE_SCOPE in scopes and not ctx.is_business_owner(business_id):
        raise HTTPException(403, "Only the business owner can grant write tools")
    raw_code = "mcp_code_" + secrets.token_urlsafe(40)
    db.add(McpOAuthAuthorizationCode(
        code_hash=_hash(raw_code), client_id=row.client_id, redirect_uri=row.redirect_uri,
        resource=row.resource, user_id=ctx.get_user_id(), business_id=business_id,
        scopes=sorted(scopes), code_challenge=row.code_challenge,
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
    access_token, access_hash = generate_api_key(prefix="mcp_live_")
    access_scopes = [scope for scope in scopes if scope != "offline_access"]
    access_row = ApiKey(
        user_id=user_id, key_hash=access_hash, key_type="mcp", business_id=business_id,
        mcp_resource=resource, oauth_client_id=client_id, oauth_grant_id=oauth_grant_id,
        name=f"OAuth: {client.client_name}"[:100],
        scopes=json.dumps(access_scopes), expires_at=datetime.utcnow() + ACCESS_TTL,
    )
    db.add(access_row)
    returned = {"access_token": access_token, "token_type": "Bearer", "expires_in": int(ACCESS_TTL.total_seconds()), "scope": " ".join(access_scopes)}
    if "refresh_token" in (client.grant_types or []) and "offline_access" in scopes:
        refresh_token, refresh_hash = generate_api_key(prefix="mcp_refresh_")
        refresh_row = McpOAuthRefreshToken(
            token_hash=refresh_hash, client_id=client_id, user_id=user_id, business_id=business_id,
            grant_id=oauth_grant_id, resource=resource, scopes=scopes, expires_at=datetime.utcnow() + REFRESH_TTL,
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
