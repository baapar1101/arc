"""Manage tenant-bound MCP connections from the Hesabix UI."""
from __future__ import annotations

import json
import logging
from datetime import datetime
from typing import Any, Iterable
from urllib.parse import urlparse

from sqlalchemy.orm import Session

from adapters.db.models.ai_mcp_oauth import McpOAuthClient, McpOAuthRefreshToken
from adapters.db.models.api_key import ApiKey
from adapters.db.models.user import User
from app.core.ai_mcp_plugin_dependency import STATUS_TOOL_NAME
from app.core.auth_dependency import AuthContext
from app.core.responses import ApiError
from app.services.ai.ai_mcp_discovery import AGENT_TOOL_NAME, WRITE_SCOPE

logger = logging.getLogger(__name__)
READ_SCOPE = "ai:tools:read"
_HIDDEN_MANAGED_TOOLS = {AGENT_TOOL_NAME, STATUS_TOOL_NAME}


def mcp_client_kind(oauth_client_id: str | None, *, oauth: bool) -> str:
    if not oauth:
        return "manual"
    host = (urlparse(oauth_client_id or "").hostname or oauth_client_id or "").lower()
    if "chatgpt.com" in host or "openai.com" in host:
        return "chatgpt"
    if "claude.ai" in host or "anthropic.com" in host:
        return "claude"
    return "oauth"


def connection_status(row: ApiKey, *, membership_active: bool, now: datetime | None = None) -> str:
    moment = now or datetime.utcnow()
    if row.revoked_at is not None:
        return "revoked"
    if not membership_active:
        return "membership_inactive"
    if row.expires_at is not None and row.expires_at <= moment:
        return "expired"
    return "active"


def user_display_name(user: User | None) -> str:
    if user is None:
        return ""
    name = " ".join(part for part in (user.first_name, user.last_name) if part).strip()
    return name or (user.email or user.mobile or "")


def parse_scope_list(value: Any) -> list[str]:
    if isinstance(value, str):
        try:
            value = json.loads(value or "[]")
        except (TypeError, ValueError):
            return []
    if not isinstance(value, list):
        return []
    return [str(item) for item in value if str(item).strip()]


def scopes_include_write(scopes: Iterable[str]) -> bool:
    return WRITE_SCOPE in {str(item) for item in scopes}


def can_manage_connection(ctx: AuthContext, row: ApiKey) -> bool:
    if not row.business_id:
        return False
    return bool(ctx.is_business_owner(row.business_id) or row.user_id == ctx.get_user_id())


def _load_connection(db: Session, connection_id: int) -> ApiKey | None:
    return db.query(ApiKey).filter(ApiKey.id == connection_id, ApiKey.key_type == "mcp").first()


def require_managed_connection(db: Session, ctx: AuthContext, connection_id: int) -> ApiKey:
    from adapters.api.v1.ai.mcp_oauth import _has_explicit_business_access

    row = _load_connection(db, connection_id)
    if (
        not row
        or not row.business_id
        or not ctx.db
        or not _has_explicit_business_access(ctx.db, ctx.get_user_id(), row.business_id)
    ):
        raise ApiError("MCP_CONNECTION_NOT_FOUND", "اتصال پیدا نشد", http_status=404)
    if not can_manage_connection(ctx, row):
        raise ApiError("FORBIDDEN", "مدیریت این اتصال مجاز نیست", http_status=403)
    return row


def representative_rows(rows: list[ApiKey], *, now: datetime | None = None) -> list[ApiKey]:
    moment = now or datetime.utcnow()
    chosen: dict[str, ApiKey] = {}
    ordered: list[ApiKey] = []

    def rank(row: ApiKey) -> tuple[int, int, float]:
        last_used = row.last_used_at or row.created_at or moment
        return (
            1 if row.revoked_at is not None else 0,
            1 if row.expires_at is not None and row.expires_at <= moment else 0,
            -last_used.timestamp(),
        )

    for row in rows:
        grant_id = row.oauth_grant_id
        if not grant_id:
            ordered.append(row)
            continue
        current = chosen.get(grant_id)
        if current is None or rank(row) < rank(current):
            chosen[grant_id] = row
    ordered.extend(chosen.values())
    ordered.sort(key=lambda row: row.created_at or moment, reverse=True)
    return ordered


def serialize_connection(
    row: ApiKey,
    *,
    user: User | None,
    client: McpOAuthClient | None,
    membership_active: bool,
    can_manage: bool,
    now: datetime | None = None,
) -> dict[str, Any]:
    scopes = parse_scope_list(row.scopes)
    tools = list(row.mcp_tool_permissions) if row.mcp_tool_permissions is not None else None
    oauth = bool(row.oauth_grant_id)
    kind = mcp_client_kind(row.oauth_client_id, oauth=oauth)
    client_name = (client.client_name if client and client.client_name else "") or {
        "chatgpt": "ChatGPT",
        "claude": "Claude",
        "oauth": "OAuth",
        "manual": "اتصال دستی",
    }.get(kind, kind)
    return {
        "id": row.id,
        "name": row.name,
        "business_id": row.business_id,
        "user_id": row.user_id,
        "user_name": user_display_name(user),
        "user_email": (user.email if user else None),
        "oauth": oauth,
        "oauth_grant_id": row.oauth_grant_id,
        "oauth_client_id": row.oauth_client_id,
        "client_kind": kind,
        "client_name": client_name,
        "scopes": sorted(scopes),
        "write_enabled": scopes_include_write(scopes),
        "tool_permissions": tools,
        "tool_count": len(tools) if tools is not None else None,
        "unrestricted_tools": tools is None,
        "created_at": row.created_at.isoformat() + "Z" if row.created_at else None,
        "expires_at": row.expires_at.isoformat() + "Z" if row.expires_at else None,
        "last_used_at": row.last_used_at.isoformat() + "Z" if row.last_used_at else None,
        "revoked": row.revoked_at is not None,
        "membership_active": membership_active,
        "status": connection_status(row, membership_active=membership_active, now=now),
        "can_manage": can_manage,
    }


def list_managed_connections(db: Session, ctx: AuthContext, business_id: int) -> list[dict[str, Any]]:
    from adapters.api.v1.ai.mcp_oauth import _has_explicit_business_access

    query = db.query(ApiKey).filter(ApiKey.key_type == "mcp", ApiKey.business_id == business_id)
    if not ctx.is_business_owner(business_id):
        query = query.filter(ApiKey.user_id == ctx.get_user_id())
    rows = representative_rows(query.order_by(ApiKey.created_at.desc()).all())
    user_ids = {int(row.user_id) for row in rows if row.user_id}
    client_ids = {str(row.oauth_client_id) for row in rows if row.oauth_client_id}
    users = {
        user.id: user
        for user in (db.query(User).filter(User.id.in_(user_ids)).all() if user_ids else [])
    }
    clients = {
        client.client_id: client
        for client in (
            db.query(McpOAuthClient).filter(McpOAuthClient.client_id.in_(client_ids)).all()
            if client_ids
            else []
        )
    }
    items = []
    for row in rows:
        membership_active = bool(
            row.user_id and _has_explicit_business_access(db, int(row.user_id), business_id)
        )
        items.append(
            serialize_connection(
                row,
                user=users.get(int(row.user_id)) if row.user_id else None,
                client=clients.get(str(row.oauth_client_id)) if row.oauth_client_id else None,
                membership_active=membership_active,
                can_manage=can_manage_connection(ctx, row),
            )
        )
    return items


def grantable_tool_catalog(db: Session, user: User, business_id: int) -> list[dict[str, Any]]:
    from adapters.api.v1.ai.mcp_oauth import _consent_tool_catalog

    ctx = AuthContext(user=user, api_key_id=0, business_id=business_id, db=db)
    catalog = [
        item
        for item in _consent_tool_catalog(db, ctx, business_id)
        if item.get("name") not in _HIDDEN_MANAGED_TOOLS
    ]
    return catalog


def parse_tool_permissions(raw: Any) -> list[str]:
    if not isinstance(raw, list) or not all(isinstance(name, str) for name in raw):
        raise ApiError(
            "MCP_INVALID_TOOL_PERMISSIONS",
            "فهرست ابزارها باید آرایه‌ای از نام‌های یکتا باشد",
            http_status=400,
        )
    cleaned = [name.strip() for name in raw if name.strip()]
    if len(cleaned) != len(set(cleaned)):
        raise ApiError(
            "MCP_INVALID_TOOL_PERMISSIONS",
            "فهرست ابزارها نباید نام تکراری داشته باشد",
            http_status=400,
        )
    if any(name in _HIDDEN_MANAGED_TOOLS for name in cleaned):
        raise ApiError(
            "MCP_TOOL_NOT_PERMITTED",
            "این ابزار از داخل حسابیکس قابل اعطا نیست",
            http_status=400,
        )
    return cleaned


def resolve_write_enabled(
    selected: list[str],
    catalog_by_name: dict[str, dict[str, Any]],
    enable_writes: Any,
) -> bool:
    has_write_tools = any(not bool(catalog_by_name[name]["read_only"]) for name in selected)
    if enable_writes is None:
        return has_write_tools
    if enable_writes is not True and enable_writes is not False:
        raise ApiError("MCP_INVALID_TOOL_PERMISSIONS", "مقدار نوشتن نامعتبر است", http_status=400)
    if enable_writes is False and has_write_tools:
        raise ApiError(
            "MCP_WRITE_TOOLS_REQUIRE_WRITE_SCOPE",
            "برای اتصال فقط‌خواندنی ابزارهای نوشتنی را بردارید",
            http_status=400,
        )
    return bool(enable_writes and has_write_tools)


def access_scope_payload(enable_writes: bool) -> str:
    scopes = [READ_SCOPE]
    if enable_writes:
        scopes.append(WRITE_SCOPE)
    return json.dumps(scopes)


def refresh_scope_payload(existing: Any, enable_writes: bool) -> list[str]:
    kept = [
        scope
        for scope in parse_scope_list(existing)
        if scope not in {READ_SCOPE, WRITE_SCOPE}
    ]
    scopes = [READ_SCOPE]
    if enable_writes:
        scopes.append(WRITE_SCOPE)
    for scope in kept:
        if scope not in scopes:
            scopes.append(scope)
    return scopes


def clone_stored_tool_permissions(raw: Any) -> list[str] | None:
    """None means unrestricted. An empty list is an explicit deny-all grant."""
    if raw is None:
        return None
    if isinstance(raw, list):
        return [str(item) for item in raw]
    return []


def keep_unrestricted_grant(originally_unrestricted: bool, unrestricted_flag: Any) -> bool:
    return originally_unrestricted and unrestricted_flag is True


def apply_permissions_to_grant(
    db: Session,
    row: ApiKey,
    *,
    tool_permissions: list[str] | None,
    enable_writes: bool,
) -> None:
    now = datetime.utcnow()
    scope_json = access_scope_payload(enable_writes)
    tool_count = "unrestricted" if tool_permissions is None else str(len(tool_permissions))
    if row.oauth_grant_id:
        keys = (
            db.query(ApiKey)
            .filter(
                ApiKey.key_type == "mcp",
                ApiKey.oauth_grant_id == row.oauth_grant_id,
                ApiKey.revoked_at.is_(None),
            )
            .all()
        )
        for key in keys:
            key.mcp_tool_permissions = tool_permissions
            key.scopes = scope_json
            db.add(key)
        tokens = (
            db.query(McpOAuthRefreshToken)
            .filter(
                McpOAuthRefreshToken.grant_id == row.oauth_grant_id,
                McpOAuthRefreshToken.revoked_at.is_(None),
            )
            .all()
        )
        for token in tokens:
            token.tool_permissions = tool_permissions
            token.scopes = refresh_scope_payload(token.scopes, enable_writes)
            db.add(token)
        logger.info(
            "MCP grant permissions updated grant_id=%s keys=%s refresh_tokens=%s write=%s tools=%s",
            row.oauth_grant_id,
            len(keys),
            len(tokens),
            enable_writes,
            tool_count,
        )
        return
    row.mcp_tool_permissions = tool_permissions
    row.scopes = scope_json
    db.add(row)
    logger.info(
        "MCP manual connection permissions updated connection_id=%s write=%s tools=%s at=%s",
        row.id,
        enable_writes,
        tool_count,
        now.isoformat(),
    )


def update_connection_permissions(
    db: Session,
    ctx: AuthContext,
    connection_id: int,
    *,
    tool_permissions_raw: Any,
    enable_writes_raw: Any,
    unrestricted_tools_raw: Any = False,
) -> dict[str, Any]:
    from adapters.api.v1.ai.mcp_oauth import _has_explicit_business_access

    row = require_managed_connection(db, ctx, connection_id)
    if row.revoked_at is not None:
        raise ApiError("MCP_CONNECTION_REVOKED", "این اتصال قبلاً قطع شده است", http_status=409)
    if row.expires_at is not None and row.expires_at <= datetime.utcnow():
        raise ApiError("MCP_CONNECTION_EXPIRED", "این اتصال منقضی شده است", http_status=409)
    user = db.get(User, row.user_id)
    if not user or not user.is_active:
        raise ApiError("MCP_MEMBERSHIP_INACTIVE", "صاحب این اتصال دیگر فعال نیست", http_status=409)
    if not row.business_id or not _has_explicit_business_access(db, user.id, row.business_id):
        raise ApiError(
            "MCP_MEMBERSHIP_INACTIVE",
            "صاحب این اتصال دیگر عضو کسب‌وکار نیست",
            http_status=409,
        )

    catalog = grantable_tool_catalog(db, user, int(row.business_id))
    catalog_by_name = {str(item["name"]): item for item in catalog}
    originally_unrestricted = row.mcp_tool_permissions is None
    if keep_unrestricted_grant(originally_unrestricted, unrestricted_tools_raw):
        if enable_writes_raw is None:
            enable_writes = scopes_include_write(parse_scope_list(row.scopes))
        elif enable_writes_raw is True or enable_writes_raw is False:
            enable_writes = bool(enable_writes_raw)
        else:
            raise ApiError("MCP_INVALID_TOOL_PERMISSIONS", "مقدار نوشتن نامعتبر است", http_status=400)
        selected = None
    else:
        selected = parse_tool_permissions(tool_permissions_raw)
        unknown = [name for name in selected if name not in catalog_by_name]
        if unknown:
            raise ApiError(
                "MCP_TOOL_NOT_PERMITTED",
                "یکی از ابزارها برای این کاربر مجاز نیست",
                http_status=400,
                details={"tools": unknown[:20]},
            )
        enable_writes = resolve_write_enabled(selected, catalog_by_name, enable_writes_raw)
    apply_permissions_to_grant(
        db,
        row,
        tool_permissions=selected,
        enable_writes=enable_writes,
    )
    db.commit()
    db.refresh(row)
    return serialize_connection(
        row,
        user=user,
        client=db.query(McpOAuthClient).filter(McpOAuthClient.client_id == row.oauth_client_id).first()
        if row.oauth_client_id
        else None,
        membership_active=True,
        can_manage=True,
    )


def connection_catalog_payload(db: Session, ctx: AuthContext, connection_id: int) -> dict[str, Any]:
    from adapters.api.v1.ai.mcp_oauth import _has_explicit_business_access

    row = require_managed_connection(db, ctx, connection_id)
    user = db.get(User, row.user_id)
    membership_active = bool(
        user
        and user.is_active
        and row.business_id
        and _has_explicit_business_access(db, user.id, row.business_id)
    )
    catalog = grantable_tool_catalog(db, user, int(row.business_id)) if user and row.business_id else []
    selected = list(row.mcp_tool_permissions) if row.mcp_tool_permissions is not None else [
        item["name"] for item in catalog
    ]
    return {
        "connection_id": row.id,
        "status": connection_status(row, membership_active=membership_active),
        "write_enabled": scopes_include_write(parse_scope_list(row.scopes)),
        "unrestricted_tools": row.mcp_tool_permissions is None,
        "selected": selected,
        "tools": catalog,
        "membership_active": membership_active,
    }


def revoke_connection(db: Session, ctx: AuthContext, connection_id: int) -> dict[str, Any]:
    row = require_managed_connection(db, ctx, connection_id)
    now = datetime.utcnow()
    if row.revoked_at is None:
        row.revoked_at = now
        db.add(row)
    if row.oauth_grant_id:
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
        row.id,
        ctx.get_user_id(),
        row.business_id,
    )
    return {"revoked": True, "id": row.id, "oauth": bool(row.oauth_grant_id)}


def revoke_all_connections(db: Session, ctx: AuthContext, business_id: int) -> dict[str, Any]:
    if not ctx.is_business_owner(business_id):
        raise ApiError(
            "MCP_REVOKE_ALL_OWNER_ONLY",
            "قطع همه اتصال‌ها فقط برای مالک کسب‌وکار مجاز است",
            http_status=403,
        )
    now = datetime.utcnow()
    rows = (
        db.query(ApiKey)
        .filter(
            ApiKey.key_type == "mcp",
            ApiKey.business_id == business_id,
            ApiKey.revoked_at.is_(None),
        )
        .all()
    )
    grant_ids = {row.oauth_grant_id for row in rows if row.oauth_grant_id}
    for row in rows:
        row.revoked_at = now
        db.add(row)
    if grant_ids:
        db.query(McpOAuthRefreshToken).filter(
            McpOAuthRefreshToken.grant_id.in_(grant_ids),
            McpOAuthRefreshToken.revoked_at.is_(None),
        ).update({McpOAuthRefreshToken.revoked_at: now}, synchronize_session=False)
    db.commit()
    logger.info(
        "MCP connections revoked for business_id=%s actor_user_id=%s count=%s",
        business_id,
        ctx.get_user_id(),
        len(rows),
    )
    return {"revoked": True, "count": len(rows)}
