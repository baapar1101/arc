"""افزونه سرور MCP هوش مصنوعی: لایسنس کانال، هشدار مدل، چت داخلی باز."""

from __future__ import annotations

import asyncio
from datetime import datetime, timedelta
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

from adapters.db.seed_data.marketplace_plugins_seed import (
	AI_MCP_SERVER_PLUGIN_CODE,
	_DEFAULT_PLUGINS,
)
from app.core.ai_mcp_plugin_dependency import (
	ERROR_CODE,
	PLUGIN_CODE,
	STATUS_TOOL_NAME,
	check_ai_mcp_plugin_active,
	get_ai_mcp_plugin_access,
	mcp_oauth_catalog_envelope,
	require_ai_mcp_plugin_active,
)
from app.core.plugin_license import (
	PLUGIN_ACCESS_ACTIVE,
	PLUGIN_ACCESS_EXPIRED,
	PLUGIN_ACCESS_MISSING,
	PLUGIN_ACCESS_PLUGIN_DISABLED,
	get_plugin_access_reason,
)
from app.core.responses import ApiError
from app.services.ai.ai_mcp_service import handle_mcp_request


def _mock_db(*, plugin_active=True, business_active=True, expired=False, globally_enabled=False):
	db = MagicMock()
	plugin = MagicMock()
	plugin.id = 77
	plugin.is_active = plugin_active
	plugin.enabled_for_all_businesses = globally_enabled
	plugin.code = PLUGIN_CODE
	plugin.name = "سرور MCP هوش مصنوعی"

	license_row = None
	if business_active:
		license_row = MagicMock()
		license_row.status = "active"
		license_row.ends_at = datetime.utcnow() + timedelta(days=30)
		if expired:
			license_row.ends_at = datetime.utcnow() - timedelta(days=1)

	def query_side_effect(model):
		q = MagicMock()
		if model.__name__ == "MarketplacePlugin":
			q.filter.return_value.first.return_value = plugin
		elif model.__name__ == "BusinessPlugin":
			q.filter.return_value.first.return_value = license_row
		return q

	db.query.side_effect = query_side_effect
	return db


def _ctx():
	ctx = MagicMock()
	ctx.business_id = 1
	ctx.mcp_scopes = {"ai:tools:read"}
	ctx.mcp_tool_permissions = None
	ctx.get_user_id.return_value = 9
	ctx.mcp_connection_id = 3
	return ctx


def _run(body, access):
	with patch("app.services.ai.ai_mcp_service.get_ai_mcp_plugin_access", return_value=access):
		return asyncio.run(handle_mcp_request(MagicMock(), _ctx(), body, business_id=1))


INACTIVE = {
	"code": PLUGIN_CODE,
	"name": "سرور MCP هوش مصنوعی",
	"is_active": False,
	"reason": PLUGIN_ACCESS_EXPIRED,
	"message": "اشتراک افزونه «سرور MCP هوش مصنوعی» تمام شده است. دستیار به داده این کسب‌وکار دسترسی ندارد. از بازار افزونه‌های حسابیکس آن را تمدید کنید.",
	"marketplace_path": "/plugin-marketplace",
}
MISSING = {
	**INACTIVE,
	"reason": PLUGIN_ACCESS_MISSING,
	"message": "افزونه «سرور MCP هوش مصنوعی» برای این کسب‌وکار فعال نیست. دستیار به داده این کسب‌وکار دسترسی ندارد. از بازار افزونه‌ها دوره آزمایشی را شروع کنید یا افزونه را بخرید.",
}
ACTIVE = {
	"code": PLUGIN_CODE,
	"name": "سرور MCP هوش مصنوعی",
	"is_active": True,
	"reason": PLUGIN_ACCESS_ACTIVE,
	"message": "افزونه «سرور MCP هوش مصنوعی» برای این کسب‌وکار فعال است.",
	"marketplace_path": "/plugin-marketplace",
}


def test_seed_includes_ai_mcp_server_plugin():
	plugin = next(p for p in _DEFAULT_PLUGINS if p.code == AI_MCP_SERVER_PLUGIN_CODE)
	assert plugin.name == "سرور MCP هوش مصنوعی"
	assert plugin.category == "integration"
	assert plugin.trial_allowed is True
	assert plugin.trial_days == 14
	periods = {period: price for period, price in plugin.plans}
	assert periods["monthly"] == 300_000
	assert periods["yearly"] == 3_000_000
	assert periods["lifetime"] == 10_000_000
	assert "ChatGPT" in plugin.description
	assert "اگر افزونه فعال نباشد" in plugin.description
	assert "چت داخل حسابیکس" in plugin.description


def test_plugin_access_reason_missing_expired_active():
	assert get_plugin_access_reason(_mock_db(business_active=False), 1, PLUGIN_CODE) == PLUGIN_ACCESS_MISSING
	assert get_plugin_access_reason(_mock_db(expired=True), 1, PLUGIN_CODE) == PLUGIN_ACCESS_EXPIRED
	assert get_plugin_access_reason(_mock_db(), 1, PLUGIN_CODE) == PLUGIN_ACCESS_ACTIVE
	assert get_plugin_access_reason(_mock_db(plugin_active=False, business_active=False), 1, PLUGIN_CODE) == PLUGIN_ACCESS_PLUGIN_DISABLED
	assert get_plugin_access_reason(_mock_db(globally_enabled=True, business_active=False), 1, PLUGIN_CODE) == PLUGIN_ACCESS_ACTIVE


def test_require_blocks_new_connection_when_inactive():
	with pytest.raises(ApiError) as exc:
		require_ai_mcp_plugin_active(_mock_db(expired=True), 1)
	assert exc.value.code == ERROR_CODE
	assert exc.value.status_code == 403
	assert "تمام شده" in exc.value.message
	assert check_ai_mcp_plugin_active(_mock_db(), 1) is True


def test_mcp_initialize_warns_when_plugin_expired():
	result = _run({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2025-11-25"}}, INACTIVE)
	instructions = result["result"]["instructions"]
	assert "تمام شده" in instructions
	assert STATUS_TOOL_NAME in instructions


def test_mcp_tools_list_only_status_when_inactive():
	result = _run({"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}}, INACTIVE)
	names = [item["name"] for item in result["result"]["tools"]]
	assert names == [STATUS_TOOL_NAME]


def test_mcp_tools_call_data_tool_returns_user_warning():
	result = _run(
		{"jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": {"name": "search_invoices", "arguments": {}}},
		MISSING,
	)
	assert result["result"]["isError"] is True
	assert "فعال نیست" in result["result"]["content"][0]["text"]


def test_mcp_status_tool_always_callable():
	result = _run(
		{"jsonrpc": "2.0", "id": 4, "method": "tools/call", "params": {"name": STATUS_TOOL_NAME, "arguments": {}}},
		INACTIVE,
	)
	assert result["result"]["isError"] is False
	assert "ai_mcp_server" in result["result"]["content"][0]["text"]
	assert "expired" in result["result"]["content"][0]["text"]


def test_mcp_hides_agent_and_prompts_when_inactive():
	listed = _run({"jsonrpc": "2.0", "id": 5, "method": "tools/list", "params": {}}, INACTIVE)
	assert "ask_hesabix_agent" not in [item["name"] for item in listed["result"]["tools"]]
	prompts = _run({"jsonrpc": "2.0", "id": 6, "method": "prompts/list", "params": {}}, INACTIVE)
	assert prompts["result"]["prompts"] == []


def test_mcp_tools_list_keeps_domain_tools_when_licensed():
	registry = MagicMock()
	definition = {"function": {"name": "search_invoices", "description": "جستجوی فاکتور", "parameters": {"type": "object"}}}
	with patch("app.services.ai.ai_mcp_service._get_tools", return_value=(registry, [definition])):
		with patch("app.services.ai.ai_mcp_service._openai_tool_to_mcp", return_value={
			"name": "search_invoices",
			"description": "جستجوی فاکتور",
			"inputSchema": {"type": "object"},
			"annotations": {"readOnlyHint": True, "destructiveHint": False, "idempotentHint": True, "openWorldHint": False},
		}):
			result = _run({"jsonrpc": "2.0", "id": 7, "method": "tools/list", "params": {}}, ACTIVE)
	names = {item["name"] for item in result["result"]["tools"]}
	assert "search_invoices" in names
	assert STATUS_TOOL_NAME in names
	assert "ask_hesabix_agent" in names


def test_oauth_catalog_hides_tools_when_plugin_inactive():
	envelope = mcp_oauth_catalog_envelope(INACTIVE, [{"name": "search_invoices", "read_only": True}])
	assert envelope["tools"] == []
	assert envelope["plugin"]["is_active"] is False
	assert envelope["plugin"]["reason"] == PLUGIN_ACCESS_EXPIRED
	active = mcp_oauth_catalog_envelope(ACTIVE, [{"name": "search_invoices"}])
	assert active["tools"][0]["name"] == "search_invoices"


def test_manual_connection_endpoint_requires_plugin():
	mcp_api = (Path(__file__).resolve().parents[1] / "adapters" / "api" / "v1" / "ai" / "mcp.py").read_text(encoding="utf-8")
	assert "require_ai_mcp_plugin_active" in mcp_api
	oauth = (Path(__file__).resolve().parents[1] / "adapters" / "api" / "v1" / "ai" / "mcp_oauth.py").read_text(encoding="utf-8")
	assert "pluginBanner" in oauth
	assert "mcp_oauth_catalog_envelope" in oauth


def test_in_app_chat_is_not_gated_by_mcp_plugin():
	api_root = Path(__file__).resolve().parents[1]
	chat = (api_root / "adapters" / "api" / "v1" / "ai" / "chat.py").read_text(encoding="utf-8")
	assert "ai_mcp_plugin_dependency" not in chat
	assert "ai_mcp_server" not in chat
	telegram = (api_root / "app" / "services" / "telegram_ai_chat_service.py").read_text(encoding="utf-8")
	assert "ai_mcp_plugin_dependency" not in telegram


def test_plugin_error_codes_are_translated():
	from app.core.i18n import Translator

	fa = Translator("fa")
	en = Translator("en")
	assert "فعال نیست" in fa.t("AI_MCP_PLUGIN_NOT_ACTIVE")
	assert "تمام شده" in fa.t("AI_MCP_PLUGIN_EXPIRED")
	assert "not active" in en.t("AI_MCP_PLUGIN_NOT_ACTIVE").lower()
	assert "expired" in en.t("AI_MCP_PLUGIN_EXPIRED").lower()


def test_get_ai_mcp_plugin_access_messages():
	expired = get_ai_mcp_plugin_access(_mock_db(expired=True), 1)
	assert expired["is_active"] is False
	assert expired["reason"] == PLUGIN_ACCESS_EXPIRED
	assert "تمام شده" in expired["message"]
	missing = get_ai_mcp_plugin_access(_mock_db(business_active=False), 1)
	assert missing["reason"] == PLUGIN_ACCESS_MISSING
	assert "فعال نیست" in missing["message"]
