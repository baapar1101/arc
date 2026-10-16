from __future__ import annotations

import json
import logging
from datetime import datetime, timedelta
from typing import Any, Dict

from fastapi import APIRouter, Body, Depends, HTTPException, Request
from fastapi.responses import JSONResponse, Response
from sqlalchemy.orm import Session

from adapters.db.models.api_key import ApiKey
from adapters.db.models.ai_mcp_oauth import McpOAuthRefreshToken
from adapters.db.models.user import User
from adapters.db.repositories.api_key_repo import ApiKeyRepository
from adapters.db.session import get_db
from app.core.auth_dependency import AuthContext, get_current_user
from app.core.responses import ApiError
from app.core.security import generate_api_key, hash_api_key
from app.core.cache import get_cache
from app.services.ai.ai_mcp_service import handle_mcp_request
from adapters.api.v1.ai.mcp_oauth import _base_url, _resource

router = APIRouter(prefix="/ai/mcp", tags=["هوش مصنوعی-MCP"])
logger = logging.getLogger(__name__)
MCP_BEARER_PREFIX = "mcp_live_"
MCP_READ_SCOPE = "ai:tools:read"
MCP_WRITE_SCOPE = "ai:tools:write"


def _scopes(row: ApiKey) -> set[str]:
    try:
        value = json.loads(row.scopes or "[]")
        return {str(scope) for scope in value} if isinstance(value, list) else set()
    except (TypeError, ValueError):
        return set()


def _require_business_access(ctx: AuthContext, business_id: int) -> None:
    if ctx.is_superadmin():
        raise ApiError("FORBIDDEN", "اتصال MCP کسب‌وکار باید با کاربر عادی همان کسب‌وکار ساخته شود", http_status=403)
    if not ctx.can_access_business(business_id):
        raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار مجاز نیست", http_status=403)


@router.post("/connections", summary="ایجاد دسترسی MCP برای یک کسب‌وکار")
def create_mcp_connection(
    request: Request,
    body: Dict[str, Any] = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    """Mint a one-time, tenant-bound MCP bearer credential. Write scope is explicit opt-in."""
    try:
        business_id = int(body.get("business_id"))
    except (TypeError, ValueError):
        raise ApiError("BUSINESS_ID_REQUIRED", "شناسه کسب‌وکار الزامی است", http_status=400)
    _require_business_access(ctx, business_id)
    enable_writes = body.get("enable_writes") is True
    if enable_writes and not ctx.is_business_owner(business_id):
        raise ApiError("FORBIDDEN", "فعال‌سازی ابزارهای نوشتنی فقط برای مالک کسب‌وکار مجاز است", http_status=403)

    name = str(body.get("name") or "اتصال MCP").strip()[:100]
    scopes = [MCP_READ_SCOPE] + ([MCP_WRITE_SCOPE] if enable_writes else [])
    active_connections = (
        db.query(ApiKey)
        .filter(
            ApiKey.key_type == "mcp",
            ApiKey.business_id == business_id,
            ApiKey.revoked_at.is_(None),
            ApiKey.expires_at > datetime.utcnow(),
        )
        .count()
    )
    if active_connections >= 20:
        raise ApiError("MCP_CONNECTION_LIMIT", "حداکثر ۲۰ اتصال فعال MCP برای این کسب‌وکار مجاز است", http_status=409)
    secret, key_hash = generate_api_key(prefix=MCP_BEARER_PREFIX)
    row = ApiKey(
        user_id=ctx.get_user_id(),
        key_hash=key_hash,
        key_type="mcp",
        business_id=business_id,
        name=name or "اتصال MCP",
        scopes=json.dumps(scopes),
        expires_at=datetime.utcnow() + timedelta(days=90),
    )
    db.add(row)
    db.commit()
    db.refresh(row)
    logger.info(
        "MCP connection created connection_id=%s user_id=%s business_id=%s scopes=%s",
        row.id, row.user_id, row.business_id, ",".join(scopes),
    )
    return {
        "id": row.id,
        "name": row.name,
        "business_id": row.business_id,
        "scopes": scopes,
        "token": secret,
        "token_once": True,
        "expires_at": row.expires_at.isoformat() + "Z",
        "server_url": _base_url(request) + request.url_for("mcp_jsonrpc_endpoint").path,
        "authorization": "Bearer",
    }


@router.get("/connections", summary="فهرست اتصال‌های MCP")
def list_mcp_connections(
    business_id: int,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    _require_business_access(ctx, business_id)
    query = db.query(ApiKey).filter(ApiKey.key_type == "mcp", ApiKey.business_id == business_id)
    if not ctx.is_business_owner(business_id):
        query = query.filter(ApiKey.user_id == ctx.get_user_id())
    rows = query.order_by(ApiKey.created_at.desc()).all()
    items = []
    seen_oauth_grants: set[str] = set()
    for row in rows:
        if row.oauth_grant_id:
            if row.oauth_grant_id in seen_oauth_grants:
                continue
            seen_oauth_grants.add(row.oauth_grant_id)
        items.append({
                "id": row.id,
                "name": row.name,
                "business_id": row.business_id,
                "scopes": sorted(_scopes(row)),
                "created_at": row.created_at.isoformat() + "Z",
                "expires_at": row.expires_at.isoformat() + "Z" if row.expires_at else None,
                "last_used_at": row.last_used_at.isoformat() + "Z" if row.last_used_at else None,
                "revoked": row.revoked_at is not None,
                "oauth": bool(row.oauth_grant_id),
            })
    return {"items": items}


@router.delete("/connections/{connection_id}", summary="لغو اتصال MCP")
def revoke_mcp_connection(
    connection_id: int,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    row = db.query(ApiKey).filter(ApiKey.id == connection_id, ApiKey.key_type == "mcp").first()
    if not row or not row.business_id or not ctx.can_access_business(row.business_id):
        raise ApiError("NOT_FOUND", "اتصال پیدا نشد", http_status=404)
    if not ctx.is_business_owner(row.business_id) and row.user_id != ctx.get_user_id():
        raise ApiError("FORBIDDEN", "لغو این اتصال مجاز نیست", http_status=403)
    row.revoked_at = datetime.utcnow()
    db.add(row)
    if row.oauth_grant_id:
        now = datetime.utcnow()
        db.query(ApiKey).filter(
            ApiKey.oauth_grant_id == row.oauth_grant_id,
            ApiKey.key_type == "mcp",
            ApiKey.revoked_at.is_(None),
        ).update({ApiKey.revoked_at: now}, synchronize_session=False)
        db.query(McpOAuthRefreshToken).filter(
            McpOAuthRefreshToken.grant_id == row.oauth_grant_id,
            McpOAuthRefreshToken.revoked_at.is_(None),
        ).update({McpOAuthRefreshToken.revoked_at: now}, synchronize_session=False)
    db.commit()
    logger.info(
        "MCP connection revoked connection_id=%s actor_user_id=%s business_id=%s",
        row.id, ctx.get_user_id(), row.business_id,
    )
    return {"revoked": True, "id": row.id}


def get_mcp_context(request: Request, db: Session = Depends(get_db)) -> AuthContext:
    """Authenticate a dedicated MCP bearer and pin its principal to one business."""
    authorization = request.headers.get("authorization", "")
    scheme, _, token = authorization.partition(" ")
    resource_metadata = _base_url(request) + "/.well-known/oauth-protected-resource" + request.url.path
    if scheme.lower() != "bearer" or not token.startswith(MCP_BEARER_PREFIX):
        raise HTTPException(
            status_code=401,
            detail="A Hesabix MCP bearer credential is required.",
            headers={"WWW-Authenticate": f'Bearer resource_metadata="{resource_metadata}", scope="{MCP_READ_SCOPE}"'},
        )
    row = ApiKeyRepository(db).get_by_hash(hash_api_key(token))
    if (
        not row
        or row.key_type != "mcp"
        or row.revoked_at is not None
        or (row.expires_at and row.expires_at <= datetime.utcnow())
        or not row.business_id
    ):
        raise HTTPException(
            status_code=401,
            detail="The Hesabix MCP bearer credential is invalid or expired.",
            headers={"WWW-Authenticate": f'Bearer error="invalid_token", resource_metadata="{resource_metadata}"'},
        )
    scopes = _scopes(row)
    if row.mcp_resource and row.mcp_resource != _resource(request):
        raise HTTPException(
            status_code=401,
            detail="The bearer credential was issued for another MCP resource.",
            headers={"WWW-Authenticate": f'Bearer error="invalid_token", error_description="wrong audience", resource_metadata="{resource_metadata}"'},
        )
    if MCP_READ_SCOPE not in scopes:
        raise ApiError("FORBIDDEN", "مجوز خواندن ابزارهای MCP وجود ندارد", http_status=403)
    user = db.get(User, row.user_id)
    if not user or not user.is_active:
        raise HTTPException(
            status_code=401,
            detail="The Hesabix MCP bearer credential is invalid or expired.",
            headers={"WWW-Authenticate": f'Bearer error="invalid_token", resource_metadata="{resource_metadata}"'},
        )
    ctx = AuthContext(
        user=user,
        api_key_id=row.id,
        language="fa",
        calendar_type="jalali" if request.headers.get("X-Calendar-Type", "jalali").lower() != "gregorian" else "gregorian",
        timezone=request.headers.get("X-Timezone"),
        business_id=row.business_id,
        db=db,
    )
    if not ctx.can_access_business(row.business_id):
        raise HTTPException(
            status_code=403,
            detail="Business membership is no longer active.",
            headers={"WWW-Authenticate": f'Bearer error="invalid_token", resource_metadata="{resource_metadata}"'},
        )
    if ctx.is_superadmin():
        raise ApiError("FORBIDDEN", "حساب مدیریتی سامانه برای اتصال MCP کسب‌وکار مجاز نیست", http_status=403)
    ctx.mcp_scopes = scopes
    ctx.mcp_connection_id = row.id
    origin = request.headers.get("origin")
    if origin:
        from app.core.settings import get_settings
        allowed_origins = set(get_settings().mcp_allowed_origins)
        if origin not in allowed_origins:
            raise HTTPException(status_code=403, detail="Origin is not allowed for MCP")
    if row.last_used_at is None or (datetime.utcnow() - row.last_used_at).total_seconds() >= 60:
        row.last_used_at = datetime.utcnow()
        db.add(row)
        db.commit()
    return ctx


@router.post("", summary="MCP Streamable HTTP endpoint")
async def mcp_jsonrpc_endpoint(
    request: Request,
    body: Dict[str, Any] = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_mcp_context),
) -> Response:
    content_type = request.headers.get("content-type", "").split(";", 1)[0].strip().lower()
    if content_type != "application/json":
        return JSONResponse({"error": "Content-Type must be application/json"}, status_code=415)
    accept = request.headers.get("accept", "")
    accepted = {part.split(";", 1)[0].strip().lower() for part in accept.split(",")}
    if not ({"application/json", "*/*"} & accepted) or not ({"text/event-stream", "*/*"} & accepted):
        return JSONResponse({"error": "Accept must include application/json and text/event-stream"}, status_code=406)
    if body.get("jsonrpc") != "2.0" or not isinstance(body.get("method"), str):
        return JSONResponse(
            {"jsonrpc": "2.0", "id": body.get("id"), "error": {"code": -32600, "message": "Invalid Request"}},
            status_code=400,
        )
    # Business identity comes only from the credential. Never trust query/body tenant selectors.
    protocol_version = request.headers.get("mcp-protocol-version")
    modern_versions = {"2026-07-28"}
    legacy_versions = {"2025-11-25", "2025-03-26"}
    params = body.get("params") or {}
    params_meta = params.get("_meta") if isinstance(params, dict) else None
    modern_version = params_meta.get("io.modelcontextprotocol/protocolVersion") if isinstance(params_meta, dict) else None
    if modern_version in modern_versions:
        if protocol_version != modern_version:
            return JSONResponse(
                {"jsonrpc": "2.0", "id": body.get("id"), "error": {"code": -32020, "message": "Header mismatch: MCP-Protocol-Version"}},
                status_code=400,
            )
        if not isinstance(params_meta.get("io.modelcontextprotocol/clientCapabilities"), dict):
            return JSONResponse(
                {"jsonrpc": "2.0", "id": body.get("id"), "error": {"code": -32600, "message": "Missing modern client capabilities"}},
                status_code=400,
            )
        mirrored_method = request.headers.get("mcp-method")
        if mirrored_method != body.get("method"):
            return JSONResponse(
                {"jsonrpc": "2.0", "id": body.get("id"), "error": {"code": -32020, "message": "Header mismatch: Mcp-Method"}},
                status_code=400,
            )
        header_name = request.headers.get("mcp-name")
        name_value = params.get("name") or params.get("uri") if isinstance(params, dict) else None
        name_required = body.get("method") in {"tools/call", "resources/read", "prompts/get"}
        if name_required and header_name != name_value:
            return JSONResponse(
                {"jsonrpc": "2.0", "id": body.get("id"), "error": {"code": -32020, "message": "Header mismatch: Mcp-Name"}},
                status_code=400,
            )
        protocol_version = modern_version
    elif body.get("method") != "initialize" and protocol_version not in legacy_versions:
        return JSONResponse(
            {"jsonrpc": "2.0", "id": body.get("id"), "error": {"code": -32600, "message": "Missing or unsupported MCP-Protocol-Version"}},
            status_code=400,
        )
    if protocol_version and protocol_version not in legacy_versions | modern_versions:
        return JSONResponse(
            {"jsonrpc": "2.0", "id": body.get("id"), "error": {"code": -32022, "message": "Unsupported protocol version", "data": {"supported": sorted(legacy_versions | modern_versions), "requested": protocol_version}}},
            status_code=400,
        )
    response = await handle_mcp_request(db, ctx, body, business_id=ctx.business_id)
    if body["method"].startswith("notifications/") or body["method"] in {"notifications/initialized", "notifications/cancelled"}:
        return Response(status_code=202)
    negotiated = protocol_version or "2025-11-25"
    if body.get("method") == "initialize" and isinstance(response, dict):
        result = response.get("result") or {}
        negotiated = result.get("protocolVersion", negotiated) if isinstance(result, dict) else negotiated
    if negotiated in modern_versions and isinstance(response, dict):
        response["_meta"] = {"io.modelcontextprotocol/serverInfo": {"name": "hesabix-ai", "version": "1.2.0"}}
        result = response.get("result")
        if isinstance(result, dict) and body.get("method") != "server/discover":
            result.setdefault("resultType", "complete")
    return JSONResponse(response, headers={"MCP-Protocol-Version": negotiated})
