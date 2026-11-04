"""گیت لایسنس کانال MCP خارجی. چت داخل حسابیکس را قفل نمی‌کند."""

from __future__ import annotations

from typing import Any, Dict, List, Mapping, MutableSequence, Sequence

from sqlalchemy.orm import Session

from app.core.plugin_license import (
	PLUGIN_ACCESS_ACTIVE,
	PLUGIN_ACCESS_EXPIRED,
	PLUGIN_ACCESS_MISSING,
	PLUGIN_ACCESS_PLUGIN_DISABLED,
	PLUGIN_ACCESS_PLUGIN_NOT_FOUND,
	get_plugin_access_reason,
)
from app.core.responses import ApiError

PLUGIN_CODE = "ai_mcp_server"
PLUGIN_NAME_FA = "سرور MCP هوش مصنوعی"
STATUS_TOOL_NAME = "get_ai_mcp_plugin_status"
MARKETPLACE_PATH = "/plugin-marketplace"
ERROR_CODE = "AI_MCP_PLUGIN_NOT_ACTIVE"
ERROR_CODE_EXPIRED = "AI_MCP_PLUGIN_EXPIRED"

_STATUS_DESCRIPTION = (
	"وضعیت افزونه سرور MCP هوش مصنوعی برای همین کسب‌وکار. "
	"اگر افزونه فعال نباشد یا اشتراکش تمام شده باشد، همین ابزار را صدا بزن و متن را عیناً به کاربر بگو؛ "
	"داده حسابداری را حدس نزن."
)


def check_ai_mcp_plugin_active(db: Session, business_id: int) -> bool:
	return get_plugin_access_reason(db, business_id, PLUGIN_CODE) == PLUGIN_ACCESS_ACTIVE


def ai_mcp_plugin_user_message(reason: str) -> str:
	if reason == PLUGIN_ACCESS_EXPIRED:
		return (
			f"اشتراک افزونه «{PLUGIN_NAME_FA}» تمام شده است. "
			"دستیار به داده این کسب‌وکار دسترسی ندارد. از بازار افزونه‌های حسابیکس آن را تمدید کنید."
		)
	if reason in {PLUGIN_ACCESS_PLUGIN_DISABLED, PLUGIN_ACCESS_PLUGIN_NOT_FOUND}:
		return (
			f"افزونه «{PLUGIN_NAME_FA}» در حال حاضر در دسترس نیست. "
			"دستیار به داده این کسب‌وکار دسترسی ندارد."
		)
	return (
		f"افزونه «{PLUGIN_NAME_FA}» برای این کسب‌وکار فعال نیست. "
		"دستیار به داده این کسب‌وکار دسترسی ندارد. از بازار افزونه‌ها دوره آزمایشی را شروع کنید یا افزونه را بخرید."
	)


def get_ai_mcp_plugin_access(db: Session, business_id: int) -> Dict[str, Any]:
	reason = get_plugin_access_reason(db, int(business_id or 0), PLUGIN_CODE)
	is_active = reason == PLUGIN_ACCESS_ACTIVE
	return {
		"code": PLUGIN_CODE,
		"name": PLUGIN_NAME_FA,
		"is_active": is_active,
		"reason": reason,
		"message": (
			f"افزونه «{PLUGIN_NAME_FA}» برای این کسب‌وکار فعال است."
			if is_active
			else ai_mcp_plugin_user_message(reason)
		),
		"marketplace_path": MARKETPLACE_PATH,
	}


def public_ai_mcp_plugin_access(access: Mapping[str, Any]) -> Dict[str, Any]:
	return {
		"code": access.get("code") or PLUGIN_CODE,
		"name": access.get("name") or PLUGIN_NAME_FA,
		"is_active": bool(access.get("is_active")),
		"reason": str(access.get("reason") or PLUGIN_ACCESS_MISSING),
		"message": str(access.get("message") or ai_mcp_plugin_user_message(PLUGIN_ACCESS_MISSING)),
		"marketplace_path": str(access.get("marketplace_path") or MARKETPLACE_PATH),
	}


def mcp_plugin_inactive_instructions(access: Mapping[str, Any]) -> str:
	message = str(access.get("message") or ai_mcp_plugin_user_message(PLUGIN_ACCESS_MISSING))
	return (
		f"{message} "
		"این موضوع را در اولین پاسخ صریحاً به کاربر بگو. هیچ مانده، فاکتور، موجودی یا گزارش را حدس نزن. "
		f"فقط ابزار `{STATUS_TOOL_NAME}` در دسترس است."
	)


def mcp_status_tool_descriptor(access: Mapping[str, Any] | None = None) -> Dict[str, Any]:
	description = _STATUS_DESCRIPTION
	if access and not access.get("is_active"):
		description = (
			f"{access.get('message') or ai_mcp_plugin_user_message(PLUGIN_ACCESS_MISSING)} "
			"این متن را عیناً به کاربر بگو و داده حسابداری را حدس نزن."
		)
	return {
		"name": STATUS_TOOL_NAME,
		"description": description,
		"inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
		"annotations": {
			"readOnlyHint": True,
			"destructiveHint": False,
			"idempotentHint": True,
			"openWorldHint": False,
		},
	}


def mcp_status_catalog_item(access: Mapping[str, Any] | None = None) -> Dict[str, Any]:
	description = _STATUS_DESCRIPTION
	if access and not access.get("is_active"):
		description = str(access.get("message") or description)
	return {
		"name": STATUS_TOOL_NAME,
		"description": description,
		"input_schema": {"type": "object", "properties": {}, "additionalProperties": False},
		"category": "plugin",
		"capability": "mcp.plugin_status",
		"read_only": True,
		"required_permissions": [],
		"aliases": ["افزونه MCP", "وضعیت افزونه"],
		"keywords": ["mcp", "plugin", "license"],
	}


def mcp_oauth_catalog_envelope(access: Mapping[str, Any], tools: Sequence[Mapping[str, Any]]) -> Dict[str, Any]:
	payload = public_ai_mcp_plugin_access(access)
	return {
		"tools": list(tools) if payload["is_active"] else [],
		"plugin": payload,
	}


def apply_visible_catalog_plugin_gate(
	db: Session,
	business_id: int,
	catalog: Sequence[Mapping[str, Any]],
) -> List[Dict[str, Any]]:
	access = get_ai_mcp_plugin_access(db, business_id)
	status_item = mcp_status_catalog_item(access)
	if not access["is_active"]:
		return [status_item]
	out: List[Dict[str, Any]] = [dict(item) for item in catalog if item.get("name") != STATUS_TOOL_NAME]
	out.append(status_item)
	return sorted(out, key=lambda item: str(item.get("name") or ""))


def inject_mcp_status_tool(
	tools: MutableSequence[Dict[str, Any]],
	access: Mapping[str, Any] | None = None,
) -> List[Dict[str, Any]]:
	filtered = [item for item in tools if item.get("name") != STATUS_TOOL_NAME]
	filtered.append(mcp_status_tool_descriptor(access))
	filtered.sort(key=lambda item: str(item.get("name") or ""))
	return filtered


def restricted_mcp_tool_list(access: Mapping[str, Any] | None = None) -> List[Dict[str, Any]]:
	return [mcp_status_tool_descriptor(access)]


def require_ai_mcp_plugin_active(db: Session, business_id: int) -> Dict[str, Any]:
	access = get_ai_mcp_plugin_access(db, business_id)
	if access["is_active"]:
		return access
	expired = access["reason"] == PLUGIN_ACCESS_EXPIRED
	raise ApiError(
		ERROR_CODE_EXPIRED if expired else ERROR_CODE,
		access["message"],
		http_status=403,
		details={
			"plugin_code": PLUGIN_CODE,
			"reason": access["reason"],
			"required_action": "renew_plugin" if expired else "activate_plugin",
			"marketplace_url": MARKETPLACE_PATH,
		},
	)
