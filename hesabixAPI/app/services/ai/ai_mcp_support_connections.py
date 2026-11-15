"""Manage platform support-desk MCP credentials. Not bound to a business."""
from __future__ import annotations

import json
import logging
from datetime import datetime, timedelta
from typing import Any, Dict, List

from sqlalchemy.orm import Session

from adapters.db.models.api_key import ApiKey
from adapters.db.models.user import User
from app.core.auth_dependency import AuthContext
from app.core.responses import ApiError
from app.core.security import generate_api_key
from app.services.ai.ai_mcp_connections import connection_status, parse_scope_list, user_display_name

logger = logging.getLogger(__name__)

SUPPORT_MCP_KEY_TYPE = "mcp_support"
SUPPORT_MCP_BEARER_PREFIX = "mcp_sup_"
SUPPORT_MCP_READ_SCOPE = "ai:tools:read"
SUPPORT_MCP_WRITE_SCOPE = "ai:tools:write"
SUPPORT_CONNECTION_LIMIT_PER_USER = 10
SUPPORT_CONNECTION_TTL_DAYS = 90


def _require_support_operator(ctx: AuthContext) -> None:
    if not (ctx.is_superadmin() or ctx.can_access_support_operator()):
        raise ApiError("FORBIDDEN", "فقط اپراتور پشتیبانی و مدیر سیستم به این بخش دسترسی دارند", http_status=403)


def _support_rows(db: Session) -> Any:
    return db.query(ApiKey).filter(ApiKey.key_type == SUPPORT_MCP_KEY_TYPE)


def serialize_support_connection(row: ApiKey, user: User | None, *, can_manage: bool, now: datetime | None = None) -> Dict[str, Any]:
    scopes = parse_scope_list(row.scopes)
    status = connection_status(row, membership_active=True, now=now)
    return {
        "id": row.id,
        "name": row.name,
        "user_id": row.user_id,
        "user_name": user_display_name(user),
        "user_email": user.email if user else None,
        "scopes": scopes,
        "created_at": row.created_at.isoformat() + "Z" if row.created_at else None,
        "expires_at": row.expires_at.isoformat() + "Z" if row.expires_at else None,
        "last_used_at": row.last_used_at.isoformat() + "Z" if row.last_used_at else None,
        "revoked": row.revoked_at is not None,
        "status": status,
        "can_manage": can_manage,
        "channel": "support",
    }


def list_support_connections(db: Session, ctx: AuthContext) -> List[Dict[str, Any]]:
    _require_support_operator(ctx)
    query = _support_rows(db)
    if not ctx.is_superadmin():
        query = query.filter(ApiKey.user_id == ctx.get_user_id())
    rows = query.order_by(ApiKey.created_at.desc()).all()
    user_ids = {row.user_id for row in rows}
    users = {
        user.id: user
        for user in db.query(User).filter(User.id.in_(user_ids)).all()
    } if user_ids else {}
    viewer_id = ctx.get_user_id()
    items = []
    for row in rows:
        can_manage = ctx.is_superadmin() or row.user_id == viewer_id
        items.append(serialize_support_connection(row, users.get(row.user_id), can_manage=can_manage))
    return items


def create_support_connection(
    db: Session,
    ctx: AuthContext,
    *,
    name: str,
    resource: str,
) -> Dict[str, Any]:
    _require_support_operator(ctx)
    active = (
        _support_rows(db)
        .filter(
            ApiKey.user_id == ctx.get_user_id(),
            ApiKey.revoked_at.is_(None),
            ApiKey.expires_at > datetime.utcnow(),
        )
        .count()
    )
    if active >= SUPPORT_CONNECTION_LIMIT_PER_USER:
        raise ApiError(
            "MCP_CONNECTION_LIMIT",
            f"حداکثر {SUPPORT_CONNECTION_LIMIT_PER_USER} اتصال فعال MCP پشتیبانی برای هر اپراتور مجاز است",
            http_status=409,
        )
    label = (name or "اتصال MCP پشتیبانی").strip()[:100] or "اتصال MCP پشتیبانی"
    scopes = [SUPPORT_MCP_READ_SCOPE, SUPPORT_MCP_WRITE_SCOPE]
    secret, key_hash = generate_api_key(prefix=SUPPORT_MCP_BEARER_PREFIX)
    row = ApiKey(
        user_id=ctx.get_user_id(),
        key_hash=key_hash,
        key_type=SUPPORT_MCP_KEY_TYPE,
        business_id=None,
        mcp_resource=resource,
        name=label,
        scopes=json.dumps(scopes),
        mcp_tool_permissions=None,
        expires_at=datetime.utcnow() + timedelta(days=SUPPORT_CONNECTION_TTL_DAYS),
    )
    db.add(row)
    db.commit()
    db.refresh(row)
    logger.info(
        "support MCP connection created connection_id=%s user_id=%s",
        row.id,
        row.user_id,
    )
    payload = serialize_support_connection(row, ctx.user, can_manage=True)
    payload["token"] = secret
    payload["token_once"] = True
    payload["authorization"] = "Bearer"
    payload["server_url"] = resource
    return payload


def revoke_support_connection(db: Session, ctx: AuthContext, connection_id: int) -> Dict[str, Any]:
    _require_support_operator(ctx)
    row = _support_rows(db).filter(ApiKey.id == connection_id).first()
    if not row:
        raise ApiError("NOT_FOUND", "اتصال MCP پشتیبانی یافت نشد", http_status=404)
    if not (ctx.is_superadmin() or row.user_id == ctx.get_user_id()):
        raise ApiError("FORBIDDEN", "لغو این اتصال مجاز نیست", http_status=403)
    if row.revoked_at is None:
        row.revoked_at = datetime.utcnow()
        db.add(row)
        db.commit()
        db.refresh(row)
    logger.info(
        "support MCP connection revoked connection_id=%s user_id=%s by=%s",
        row.id,
        row.user_id,
        ctx.get_user_id(),
    )
    user = db.get(User, row.user_id)
    return serialize_support_connection(row, user, can_manage=True)
