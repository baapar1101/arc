from __future__ import annotations

import logging
import secrets
import time
from datetime import datetime
from typing import Any, Dict, Optional, Tuple

from fastapi import APIRouter, Body, Depends, HTTPException, Request
from fastapi.responses import JSONResponse, Response
from sqlalchemy.orm import Session

from adapters.api.v1.ai.mcp_oauth import _base_url
from adapters.db.models.user import User
from adapters.db.repositories.api_key_repo import ApiKeyRepository
from adapters.db.session import get_db
from app.core.auth_dependency import AuthContext, get_current_user
from app.core.permissions import require_app_permission
from app.core.responses import ApiError, success_response
from app.core.security import hash_api_key
from app.services.ai.ai_mcp_support_connections import (
    SUPPORT_MCP_BEARER_PREFIX,
    SUPPORT_MCP_KEY_TYPE,
    SUPPORT_MCP_READ_SCOPE,
    create_support_connection,
    list_support_connections,
    revoke_support_connection,
)
from app.services.ai.ai_mcp_support_service import SERVER_NAME, handle_support_mcp_request

router = APIRouter(prefix="/ai/mcp/support", tags=["هوش مصنوعی-MCP پشتیبانی"])
logger = logging.getLogger(__name__)
_LEGACY_VERSIONS = {"2025-11-25", "2025-06-18", "2025-03-26"}
_MODERN_VERSIONS = {"2026-07-28"}


def _support_resource(request: Request) -> str:
    return _base_url(request) + request.url_for("mcp_support_jsonrpc_endpoint").path


def _scopes(row) -> set[str]:
    import json

    try:
        value = json.loads(row.scopes or "[]")
        return {str(scope) for scope in value} if isinstance(value, list) else set()
    except (TypeError, ValueError):
        return set()


def get_mcp_support_context(request: Request, db: Session = Depends(get_db)) -> AuthContext:
    """Authenticate a support-desk MCP bearer. Not bound to a business."""
    diagnostic_id = getattr(request.state, "diagnostic_request_id", None)
    authorization = request.headers.get("authorization", "")
    scheme, _, token = authorization.partition(" ")
    resource_metadata = _base_url(request) + "/.well-known/oauth-protected-resource" + request.url.path
    if scheme.lower() != "bearer" or not token.startswith(SUPPORT_MCP_BEARER_PREFIX):
        logger.warning("support_mcp_auth_rejected diagnostic_id=%s reason=missing_or_invalid_scheme", diagnostic_id)
        raise HTTPException(
            status_code=401,
            detail="A Hesabix support MCP bearer credential is required.",
            headers={"WWW-Authenticate": f'Bearer resource_metadata="{resource_metadata}", scope="{SUPPORT_MCP_READ_SCOPE}"'},
        )
    row = ApiKeyRepository(db).get_by_hash(hash_api_key(token))
    if (
        not row
        or row.key_type != SUPPORT_MCP_KEY_TYPE
        or row.revoked_at is not None
        or (row.expires_at and row.expires_at <= datetime.utcnow())
        or row.business_id is not None
    ):
        logger.warning("support_mcp_auth_rejected diagnostic_id=%s reason=invalid_expired_or_bound_credential", diagnostic_id)
        raise HTTPException(
            status_code=401,
            detail="The Hesabix support MCP bearer credential is invalid or expired.",
            headers={"WWW-Authenticate": f'Bearer error="invalid_token", resource_metadata="{resource_metadata}"'},
        )
    if row.mcp_resource and row.mcp_resource != _support_resource(request):
        logger.warning(
            "support_mcp_auth_rejected diagnostic_id=%s connection_id=%s reason=wrong_resource",
            diagnostic_id,
            row.id,
        )
        raise HTTPException(
            status_code=401,
            detail="The bearer credential was issued for another MCP resource.",
            headers={"WWW-Authenticate": f'Bearer error="invalid_token", error_description="wrong audience", resource_metadata="{resource_metadata}"'},
        )
    user = db.get(User, row.user_id)
    if not user or not user.is_active:
        logger.warning("support_mcp_auth_rejected diagnostic_id=%s connection_id=%s reason=inactive_user", diagnostic_id, row.id)
        raise HTTPException(
            status_code=401,
            detail="The Hesabix support MCP bearer credential is invalid or expired.",
            headers={"WWW-Authenticate": f'Bearer error="invalid_token", resource_metadata="{resource_metadata}"'},
        )
    ctx = AuthContext(
        user=user,
        api_key_id=row.id,
        language="fa",
        calendar_type="jalali" if request.headers.get("X-Calendar-Type", "jalali").lower() != "gregorian" else "gregorian",
        timezone=request.headers.get("X-Timezone"),
        business_id=None,
        db=db,
    )
    if not (ctx.is_superadmin() or ctx.can_access_support_operator()):
        logger.warning(
            "support_mcp_auth_rejected diagnostic_id=%s connection_id=%s reason=not_support_operator",
            diagnostic_id,
            row.id,
        )
        raise HTTPException(
            status_code=403,
            detail="Support operator permission is no longer active.",
            headers={"WWW-Authenticate": f'Bearer error="invalid_token", resource_metadata="{resource_metadata}"'},
        )
    ctx.mcp_scopes = _scopes(row) or {SUPPORT_MCP_READ_SCOPE, "ai:tools:write"}
    ctx.mcp_tool_permissions = None
    ctx.mcp_connection_id = row.id
    ctx.mcp_channel = "support"
    origin = request.headers.get("origin")
    if origin:
        from app.core.settings import get_settings

        allowed_origins = set(get_settings().mcp_allowed_origins)
        if origin not in allowed_origins:
            logger.warning(
                "support_mcp_auth_rejected diagnostic_id=%s connection_id=%s reason=origin_not_allowed",
                diagnostic_id,
                row.id,
            )
            raise HTTPException(status_code=403, detail="Origin is not allowed for MCP")
    if row.last_used_at is None or (datetime.utcnow() - row.last_used_at).total_seconds() >= 60:
        row.last_used_at = datetime.utcnow()
        db.add(row)
        db.commit()
    return ctx


def _validate_mcp_http(request: Request, body: Dict[str, Any]) -> Tuple[Optional[Response], Optional[str]]:
    content_type = request.headers.get("content-type", "").split(";", 1)[0].strip().lower()
    if content_type != "application/json":
        return JSONResponse({"error": "Content-Type must be application/json"}, status_code=415), None
    accept = request.headers.get("accept", "")
    accepted = {part.split(";", 1)[0].strip().lower() for part in accept.split(",")}
    if not ({"application/json", "*/*"} & accepted) or not ({"text/event-stream", "*/*"} & accepted):
        return JSONResponse({"error": "Accept must include application/json and text/event-stream"}, status_code=406), None
    if body.get("jsonrpc") != "2.0" or not isinstance(body.get("method"), str):
        return JSONResponse(
            {"jsonrpc": "2.0", "id": body.get("id"), "error": {"code": -32600, "message": "Invalid Request"}},
            status_code=400,
        ), None
    protocol_version = request.headers.get("mcp-protocol-version")
    params = body.get("params") or {}
    params_meta = params.get("_meta") if isinstance(params, dict) else None
    modern_version = params_meta.get("io.modelcontextprotocol/protocolVersion") if isinstance(params_meta, dict) else None
    if modern_version in _MODERN_VERSIONS:
        if protocol_version != modern_version:
            return JSONResponse(
                {"jsonrpc": "2.0", "id": body.get("id"), "error": {"code": -32020, "message": "Header mismatch: MCP-Protocol-Version"}},
                status_code=400,
            ), None
        if not isinstance(params_meta.get("io.modelcontextprotocol/clientCapabilities"), dict):
            return JSONResponse(
                {"jsonrpc": "2.0", "id": body.get("id"), "error": {"code": -32600, "message": "Missing modern client capabilities"}},
                status_code=400,
            ), None
        if request.headers.get("mcp-method") != body.get("method"):
            return JSONResponse(
                {"jsonrpc": "2.0", "id": body.get("id"), "error": {"code": -32020, "message": "Header mismatch: Mcp-Method"}},
                status_code=400,
            ), None
        header_name = request.headers.get("mcp-name")
        name_value = params.get("name") or params.get("uri") if isinstance(params, dict) else None
        name_required = body.get("method") in {"tools/call", "resources/read", "prompts/get"}
        if name_required and header_name != name_value:
            return JSONResponse(
                {"jsonrpc": "2.0", "id": body.get("id"), "error": {"code": -32020, "message": "Header mismatch: Mcp-Name"}},
                status_code=400,
            ), None
        protocol_version = modern_version
    elif body.get("method") != "initialize" and protocol_version not in _LEGACY_VERSIONS:
        return JSONResponse(
            {"jsonrpc": "2.0", "id": body.get("id"), "error": {"code": -32600, "message": "Missing or unsupported MCP-Protocol-Version"}},
            status_code=400,
        ), None
    if protocol_version and protocol_version not in _LEGACY_VERSIONS | _MODERN_VERSIONS:
        return JSONResponse(
            {
                "jsonrpc": "2.0",
                "id": body.get("id"),
                "error": {
                    "code": -32022,
                    "message": "Unsupported protocol version",
                    "data": {"supported": sorted(_LEGACY_VERSIONS | _MODERN_VERSIONS), "requested": protocol_version},
                },
            },
            status_code=400,
        ), None
    return None, protocol_version


@router.post(
    "/connections",
    summary="ایجاد دسترسی MCP میز پشتیبانی",
    description="توکن یک‌بارمصرف است و فقط برای اپراتور پشتیبانی یا مدیر سیستم صادر می‌شود.",
)
@require_app_permission("support_operator")
def create_support_mcp_connection(
    request: Request,
    body: Dict[str, Any] = Body(default_factory=dict),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    payload = create_support_connection(
        db,
        ctx,
        name=str((body or {}).get("name") or "اتصال MCP پشتیبانی"),
        resource=_support_resource(request),
    )
    return success_response(payload, request)


@router.get("/connections", summary="فهرست اتصال‌های MCP میز پشتیبانی")
@require_app_permission("support_operator")
def list_support_mcp_connections(
    request: Request,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    return success_response(
        {
            "items": list_support_connections(db, ctx),
            "server_url": _support_resource(request),
            "authorization": "Bearer",
            "channel": "support",
        },
        request,
    )


@router.delete("/connections/{connection_id}", summary="لغو اتصال MCP میز پشتیبانی")
@require_app_permission("support_operator")
def delete_support_mcp_connection(
    connection_id: int,
    request: Request,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    return success_response(revoke_support_connection(db, ctx, connection_id), request)


@router.post(
    "",
    summary="MCP پشتیبانی Streamable HTTP",
    description="نقطه ورود پروتکل MCP میز پشتیبانی است؛ به کسب‌وکار متصل نیست.",
)
async def mcp_support_jsonrpc_endpoint(
    request: Request,
    body: Dict[str, Any] = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_mcp_support_context),
) -> Response:
    diagnostic_id = getattr(request.state, "diagnostic_request_id", None) or secrets.token_hex(8)
    method = body.get("method")
    params = body.get("params") or {}
    tool_name = params.get("name") if isinstance(params, dict) else None
    started_at = time.perf_counter()
    logger.info(
        "support_mcp_request_received diagnostic_id=%s method=%s tool=%s protocol=%s",
        diagnostic_id,
        method,
        tool_name if isinstance(tool_name, str) else "",
        request.headers.get("mcp-protocol-version", ""),
    )
    error_response, protocol_version = _validate_mcp_http(request, body)
    if error_response is not None:
        return error_response
    response = await handle_support_mcp_request(db, ctx, body, diagnostic_id=diagnostic_id)
    if str(body.get("method") or "").startswith("notifications/") or body.get("method") in {
        "notifications/initialized",
        "notifications/cancelled",
    }:
        return Response(status_code=202)
    negotiated = protocol_version or "2025-11-25"
    if body.get("method") == "initialize" and isinstance(response, dict):
        result = response.get("result") or {}
        negotiated = result.get("protocolVersion", negotiated) if isinstance(result, dict) else negotiated
    if negotiated in _MODERN_VERSIONS and isinstance(response, dict):
        response["_meta"] = {"io.modelcontextprotocol/serverInfo": {"name": SERVER_NAME, "version": "1.0.0"}}
        result = response.get("result")
        if isinstance(result, dict) and body.get("method") != "server/discover":
            result.setdefault("resultType", "complete")
    rpc_error = response.get("error") if isinstance(response, dict) else None
    tool_result = response.get("result") if isinstance(response, dict) else None
    tool_is_error = tool_result.get("isError") if isinstance(tool_result, dict) else None
    logger.info(
        "support_mcp_request_completed diagnostic_id=%s method=%s tool=%s rpc_error_code=%s tool_is_error=%s duration_ms=%.2f",
        diagnostic_id,
        method,
        tool_name if isinstance(tool_name, str) else "",
        rpc_error.get("code") if isinstance(rpc_error, dict) else "",
        tool_is_error,
        (time.perf_counter() - started_at) * 1000,
    )
    return JSONResponse(
        response,
        headers={"MCP-Protocol-Version": negotiated, "X-Hesabix-Diagnostic-ID": diagnostic_id},
    )
