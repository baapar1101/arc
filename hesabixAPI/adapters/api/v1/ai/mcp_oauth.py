"""OAuth 2.1 authorization and discovery endpoints for the MCP resource server."""
from __future__ import annotations

import hashlib
import html
import json
import re
import secrets
from datetime import datetime, timedelta
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import HTMLResponse, JSONResponse
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
    if metadata.get("token_endpoint_auth_method", "none") != "none":
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
        "Content-Security-Policy": "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data:; connect-src 'self'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'",
        "Referrer-Policy": "no-referrer", "X-Content-Type-Options": "nosniff",
    })


def _authorization_html(request_id: str, client_name: str, write_requested: bool, offline_requested: bool) -> str:
    safe_id, safe_name = html.escape(request_id), html.escape(client_name)
    return f'''<!doctype html><html lang="fa" dir="rtl"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>اتصال حسابیکس</title>
<style>body{{font-family:system-ui,sans-serif;background:#f5f7fb;margin:0;color:#182230}}main{{max-width:520px;margin:6vh auto;background:white;padding:24px;border-radius:16px;box-shadow:0 8px 30px #18223018}}input,select,button{{box-sizing:border-box;width:100%;padding:11px;margin:6px 0;border:1px solid #ccd3df;border-radius:8px}}button{{background:#1455d9;color:white;border:0;cursor:pointer}}label{{display:block;margin-top:12px}}#status{{white-space:pre-wrap;color:#a22}}.row{{display:flex;gap:8px}}.row>*{{flex:1}}</style>
<main><h2>اتصال امن به حسابیکس</h2><p><b>{safe_name}</b> درخواست دسترسی به ابزارهای کسب‌وکار حسابیکس را دارد. پس از ورود، کسب‌وکار و سطح دسترسی را انتخاب کنید.</p>
<label>موبایل یا ایمیل<input id="identifier" autocomplete="username" maxlength="255"></label><div class="row"><select id="channel"><option value="sms">پیامک</option><option value="email">ایمیل</option></select><button id="reload" type="button">دریافت کپچا</button></div>
<img id="captcha" alt="کپچا" style="max-height:80px"><label>متن کپچا<input id="captchaCode" maxlength="10" autocomplete="off"></label><button id="send" type="button">ارسال کد ورود</button>
<section id="otpSection" hidden><label>کد یکبارمصرف<input id="otp" inputmode="numeric" autocomplete="one-time-code" maxlength="6"></label><button id="verify" type="button">تایید و ورود</button></section>
<section id="consent" hidden><label>کسب‌وکار<select id="business"></select></label><p>دسترسی پایه: مشاهده اطلاعات و گزارش‌های این کسب‌وکار.</p>{'<label><input type="checkbox" id="write" style="width:auto"> اجازه استفاده از ابزارهای تغییردهنده اطلاعات (فقط مالک کسب‌وکار)</label>' if write_requested else ''}{'<label><input type="checkbox" id="offline" style="width:auto"> اجازه تمدید اتصال تا ۳۰ روز بدون ورود مجدد</label>' if offline_requested else ''}<button id="approve" type="button">تایید اتصال</button><button id="deny" type="button">رد درخواست</button></section><p id="status" role="status"></p></main>
<script>
const api='{get_settings().api_v1_prefix}', rid='{safe_id}';let captchaId='',loginSession='',sessionKey='';const $=id=>document.getElementById(id),status=m=>$('status').textContent=m;
async function data(r){{let j=await r.json();if(!r.ok||j.success===false)throw Error(j.message||j.detail||'درخواست ناموفق بود');return j.data??j}}
async function loadCaptcha(){{try{{let j=await data(await fetch(api+'/auth/captcha',{{method:'POST'}}));captchaId=j.captcha_id;$('captcha').src='data:image/png;base64,'+j.image_base64}}catch(e){{status(e.message)}}}}
$('reload').onclick=loadCaptcha;loadCaptcha();
$('send').onclick=async()=>{{try{{let j=await data(await fetch(api+'/auth/login/send-otp',{{method:'POST',headers:{{'Content-Type':'application/json'}},body:JSON.stringify({{identifier:$('identifier').value,channel:$('channel').value,captcha_id:captchaId,captcha_code:$('captchaCode').value}})}}));loginSession=j.session_id;$('otpSection').hidden=false;status('کد ورود ارسال شد')}}catch(e){{status(e.message);loadCaptcha()}}}};
$('verify').onclick=async()=>{{try{{let j=await data(await fetch(api+'/auth/login/verify-otp?session_id='+encodeURIComponent(loginSession)+'&otp_code='+encodeURIComponent($('otp').value),{{method:'POST'}}));let b=await data(await fetch(api+'/ai/mcp/oauth/authorize/session',{{method:'POST',headers:{{'Content-Type':'application/json',Authorization:'ApiKey '+j.api_key}},body:JSON.stringify({{request_id:rid}})}}));sessionKey=b.consent_token;$('business').innerHTML='';for(const item of b.items){{let o=document.createElement('option');o.value=item.id;o.textContent=item.name;o.dataset.owner=item.owner?'1':'0';$('business').append(o)}}$('business').onchange=()=>{{let w=$('write');if(w){{w.disabled=$('business').selectedOptions[0].dataset.owner!=='1';if(w.disabled)w.checked=false}}}};$('business').onchange();$('consent').hidden=false;$('identifier').disabled=true;$('send').disabled=true;status('ورود موفق؛ سطح دسترسی را بررسی و تایید کنید')}}catch(e){{status(e.message)}}}};
async function decide(approved){{try{{let scopes=['ai:tools:read'];if($('write')?.checked===true)scopes.push('ai:tools:write');if($('offline')?.checked===true)scopes.push('offline_access');let r=await fetch(api+'/ai/mcp/oauth/authorize/consent',{{method:'POST',headers:{{'Content-Type':'application/json',Authorization:'Bearer '+sessionKey}},body:JSON.stringify({{request_id:rid,business_id:$('business')?Number($('business').value):null,approved,scopes}})}});let j=await data(r);location.assign(j.redirect_to)}}catch(e){{status(e.message)}}}}
$('approve').onclick=()=>decide(true);$('deny').onclick=()=>decide(false);
</script></html>'''


@oauth_router.post("/authorize/session")
@rate_limit(max_requests=20, window_seconds=600, error_message="درخواست‌های ورود OAuth بیش از حد مجاز است.")
def create_consent_session(payload: dict, db: Session = Depends(get_db), ctx: AuthContext = Depends(get_current_user)) -> dict:
    db = ctx.db
    if db is None or ctx.is_superadmin():
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
    if ctx.is_superadmin() or not ctx.can_access_business(business_id) or not ctx.is_user_active():
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
    if not user or not user.is_active or not probe or not probe.can_access_business(business_id) or probe.is_superadmin():
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
