"""Business-scoped MCP tools for position-based office automation."""
from __future__ import annotations

from typing import Any, Dict, Optional

from app.core.responses import ApiError
from app.services.ai.function_registry import AIFunction, AIRole

_ROLES = {AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN}
_KIND = ["internal", "incoming", "outgoing"]
_URGENCY = ["normal", "urgent", "immediate"]
_REF_KIND = ["action", "info", "signature", "return"]
_FOLDER = ["inbox", "action", "cc", "drafts", "sent", "followup", "archive", "registry"]


def _schema(properties=None, required=()):
	return {"type": "object", "properties": properties or {}, "required": list(required), "additionalProperties": False}


def _optional_pid(args: Dict[str, Any]) -> Optional[int]:
	raw = args.get("as_position_id") or args.get("position_id")
	if raw in (None, ""):
		return None
	try:
		pid = int(raw)
	except (TypeError, ValueError):
		return None
	return pid if pid > 0 else None


def _pid(args: Dict[str, Any]) -> int:
	pid = _optional_pid(args)
	if not pid:
		raise ApiError("OA_POSITION_REQUIRED", "Active position is required (as_position_id).", http_status=400)
	return pid


def _register(registry, name, description, schema, handler, permission, *, write=False, high=False):
	registry.register(AIFunction(
		name=name,
		description=description,
		parameters_schema=schema,
		handler=handler,
		allowed_roles=_ROLES,
		required_permissions=[permission],
		category="office_automation",
		requires_approval=bool(write),
		risk_level="high" if high else ("medium" if write else "safe"),
		is_readonly=not write,
	))


def _svc():
	from app.services import office_automation_service as svc
	return svc


def _ctx(context):
	return context["db"], int(context["business_id"]), context["user_context"].get_user_id(), str(context.get("locale") or "fa")


def _cal(context) -> str:
	return str(context.get("calendar_type") or "jalali")


def register_mcp_office_automation_functions(registry) -> None:
	pos = {"as_position_id": {"type": "integer", "minimum": 1, "description": "سمت فعال کاربر برای این عملیات"}}
	letter_id = {**pos, "letter_id": {"type": "integer", "minimum": 1}}

	_register(registry, "get_oa_dashboard", "نمای کارتابل و سمت‌های کاربر در اتوماسیون اداری.",
		_schema({**pos}), lambda a, c: _svc().get_dashboard(*_ctx(c)[:3], _optional_pid(a), lang=_ctx(c)[3]), "office_automation.view")
	_register(registry, "get_oa_settings", "خواندن تنظیمات شماره‌گذاری و سربرگ اتوماسیون.",
		_schema(), lambda a, c: _svc().get_settings(c["db"], int(c["business_id"])), "office_automation.view")
	_register(registry, "update_oa_settings", "ویرایش تنظیمات اتوماسیون اداری. نیازمند تأیید.",
		_schema({"payload": {"type": "object"}}, ["payload"]),
		lambda a, c: _svc().update_settings(c["db"], int(c["business_id"]), a["payload"], c["user_context"].get_user_id()),
		"office_automation.admin", write=True)

	_register(registry, "list_oa_org_units", "فهرست واحدهای سازمانی اتوماسیون.",
		_schema({"include_inactive": {"type": "boolean"}}),
		lambda a, c: {"items": _svc().list_org_units(c["db"], int(c["business_id"]), include_inactive=bool(a.get("include_inactive", False)), lang=_ctx(c)[3])},
		"office_automation.view")
	_register(registry, "create_oa_org_unit", "ساخت واحد سازمانی. اگر code خالی باشد کد یکتا ساخته می‌شود. نیازمند تأیید.",
		_schema({"payload": {"type": "object", "properties": {"code": {"type": "string"}, "auto_generate_code": {"type": "boolean"}, "name_i18n": {"type": "object"}, "parent_id": {"type": ["integer", "null"]}, "sort_order": {"type": "integer"}}}}, ["payload"]),
		lambda a, c: _svc().create_org_unit(c["db"], int(c["business_id"]), a["payload"], c["user_context"].get_user_id(), lang=_ctx(c)[3]),
		"office_automation.admin", write=True)
	_register(registry, "update_oa_org_unit", "ویرایش واحد سازمانی. نیازمند تأیید.",
		_schema({"unit_id": {"type": "integer", "minimum": 1}, "payload": {"type": "object"}}, ["unit_id", "payload"]),
		lambda a, c: _svc().update_org_unit(c["db"], int(c["business_id"]), int(a["unit_id"]), a["payload"], c["user_context"].get_user_id(), lang=_ctx(c)[3]),
		"office_automation.admin", write=True)

	_register(registry, "list_oa_positions", "فهرست و جستجوی سمت‌های سازمانی.",
		_schema({"include_inactive": {"type": "boolean"}, "q": {"type": "string"}, "limit": {"type": "integer", "minimum": 1, "maximum": 200}}),
		lambda a, c: {"items": _svc().list_positions(c["db"], int(c["business_id"]), include_inactive=bool(a.get("include_inactive", False)), lang=_ctx(c)[3], q=a.get("q"), limit=a.get("limit"))},
		"office_automation.view")
	_register(registry, "create_oa_position", "ساخت سمت سازمانی. اگر code خالی باشد کد یکتا ساخته می‌شود. نیازمند تأیید.",
		_schema({"payload": {"type": "object", "properties": {"code": {"type": "string"}, "auto_generate_code": {"type": "boolean"}, "org_unit_id": {"type": "integer"}, "name_i18n": {"type": "object"}, "is_secretariat": {"type": "boolean"}, "can_view_subtree": {"type": "boolean"}}, "required": ["org_unit_id"]}}, ["payload"]),
		lambda a, c: _svc().create_position(c["db"], int(c["business_id"]), a["payload"], c["user_context"].get_user_id(), lang=_ctx(c)[3]),
		"office_automation.admin", write=True)
	_register(registry, "update_oa_position", "ویرایش سمت سازمانی. نیازمند تأیید.",
		_schema({"position_id": {"type": "integer", "minimum": 1}, "payload": {"type": "object"}}, ["position_id", "payload"]),
		lambda a, c: _svc().update_position(c["db"], int(c["business_id"]), int(a["position_id"]), a["payload"], c["user_context"].get_user_id(), lang=_ctx(c)[3]),
		"office_automation.admin", write=True)

	_register(registry, "list_my_oa_positions", "سمت‌های فعال کاربر جاری شامل تصدی و جانشینی.",
		_schema(), lambda a, c: {"items": _svc().list_my_positions(c["db"], int(c["business_id"]), c["user_context"].get_user_id(), lang=_ctx(c)[3])}, "office_automation.view")
	_register(registry, "list_oa_position_holders", "فهرست تصدی سمت‌ها.",
		_schema({"position_id": {"type": ["integer", "null"], "minimum": 1}, "user_id": {"type": ["integer", "null"], "minimum": 1}}),
		lambda a, c: {"items": _svc().list_position_holders(c["db"], int(c["business_id"]), position_id=a.get("position_id"), user_id=a.get("user_id"), lang=_ctx(c)[3])},
		"office_automation.admin")
	_register(registry, "assign_oa_position_holder", "واگذاری سمت به کاربر. یک کاربر می‌تواند چند سمت داشته باشد. نیازمند تأیید.",
		_schema({"payload": {"type": "object", "properties": {"position_id": {"type": "integer"}, "user_id": {"type": "integer"}, "is_primary": {"type": "boolean"}, "starts_at": {"type": "string"}, "ends_at": {"type": ["string", "null"]}}, "required": ["position_id", "user_id"]}}, ["payload"]),
		lambda a, c: _svc().assign_position_holder(c["db"], int(c["business_id"]), a["payload"], c["user_context"].get_user_id(), lang=_ctx(c)[3], calendar_type=_cal(c)),
		"office_automation.admin", write=True, high=True)
	_register(registry, "end_oa_position_holder", "پایان تصدی سمت. نیازمند تأیید.",
		_schema({"holder_id": {"type": "integer", "minimum": 1}}, ["holder_id"]),
		lambda a, c: _svc().end_position_holder(c["db"], int(c["business_id"]), int(a["holder_id"]), c["user_context"].get_user_id()),
		"office_automation.admin", write=True)

	_register(registry, "list_oa_delegations", "فهرست جانشینی سمت‌ها.",
		_schema({"position_id": {"type": ["integer", "null"], "minimum": 1}}),
		lambda a, c: {"items": _svc().list_delegations(c["db"], int(c["business_id"]), position_id=a.get("position_id"), lang=_ctx(c)[3])},
		"office_automation.admin")
	_register(registry, "create_oa_delegation", "تعیین جانشین موقت برای یک سمت. نیازمند تأیید.",
		_schema({"payload": {"type": "object", "properties": {"position_id": {"type": "integer"}, "delegate_user_id": {"type": "integer"}, "scope": {"type": "string", "enum": ["full", "view", "refer"]}, "starts_at": {"type": "string"}, "ends_at": {"type": ["string", "null"]}}, "required": ["position_id", "delegate_user_id"]}}, ["payload"]),
		lambda a, c: _svc().create_delegation(c["db"], int(c["business_id"]), a["payload"], c["user_context"].get_user_id(), lang=_ctx(c)[3], calendar_type=_cal(c)),
		"office_automation.admin", write=True)
	_register(registry, "end_oa_delegation", "پایان جانشینی. نیازمند تأیید.",
		_schema({"delegation_id": {"type": "integer", "minimum": 1}}, ["delegation_id"]),
		lambda a, c: _svc().end_delegation(c["db"], int(c["business_id"]), int(a["delegation_id"]), c["user_context"].get_user_id()),
		"office_automation.admin", write=True)

	_register(registry, "list_oa_cartable", "کارتابل سمت فعال: inbox/action/cc/drafts/sent/followup/archive/registry.",
		_schema({**pos, "folder": {"type": "string", "enum": _FOLDER}, "q": {"type": "string"}, "date_from": {"type": "string"}, "date_to": {"type": "string"}, "limit": {"type": "integer", "minimum": 1, "maximum": 200}, "skip": {"type": "integer", "minimum": 0}}, ["as_position_id"]),
		lambda a, c: _svc().list_cartable(
			c["db"], int(c["business_id"]), c["user_context"].get_user_id(), _pid(a),
			folder=str(a.get("folder") or "inbox"), q=a.get("q"), limit=int(a.get("limit") or 50), skip=int(a.get("skip") or 0),
			lang=_ctx(c)[3], calendar_type=_cal(c), date_from=a.get("date_from"), date_to=a.get("date_to"),
		),
		"office_automation.view")
	_register(registry, "get_oa_letter", "جزئیات نامه شامل پاراف، پیوست، ارجاع و سابقه.",
		_schema(letter_id, ["letter_id"]),
		lambda a, c: _svc().get_letter(c["db"], int(c["business_id"]), int(a["letter_id"]), c["user_context"].get_user_id(), _optional_pid(a), lang=_ctx(c)[3], is_admin=c["user_context"].has_business_permission("office_automation", "admin")),
		"office_automation.view")
	_register(registry, "get_oa_letter_print", "نسخه چاپی نامه شامل سربرگ، متن، پاراف، پیوست و سابقه ارجاع.",
		_schema(letter_id, ["letter_id"]),
		lambda a, c: _svc().get_letter_print(c["db"], int(c["business_id"]), int(a["letter_id"]), c["user_context"].get_user_id(), _optional_pid(a), lang=_ctx(c)[3], is_admin=c["user_context"].has_business_permission("office_automation", "admin")),
		"office_automation.view")

	draft_payload = {"type": "object", "properties": {
		"subject": {"type": "string"}, "body": {"type": "string"}, "body_format": {"type": "string", "enum": ["markdown", "html", "plain"]},
		"letter_kind": {"type": "string", "enum": _KIND},
		"letter_date": {"type": "string"}, "urgency": {"type": "string", "enum": _URGENCY},
		"confidentiality": {"type": "string", "enum": ["normal", "confidential"]},
		"sender_name": {"type": "string"}, "sender_org": {"type": "string"}, "receiver_name": {"type": "string"},
		"receiver_org": {"type": "string"}, "sender_position_id": {"type": ["integer", "null"]},
		"receiver_position_id": {"type": ["integer", "null"]}, "format_id": {"type": ["integer", "null"]},
		"template_id": {"type": ["integer", "null"]}, "locale": {"type": "string", "enum": ["fa", "en"]},
		"person_id": {"type": ["integer", "null"]}, "follow_up_at": {"type": ["string", "null"]},
	}}
	_register(registry, "create_oa_letter_draft", "ساخت پیش‌نویس نامه از سمت فعال. نیازمند تأیید.",
		_schema({**pos, "payload": draft_payload}, ["as_position_id", "payload"]),
		lambda a, c: _svc().create_letter_draft(c["db"], int(c["business_id"]), a["payload"], c["user_context"].get_user_id(), _pid(a), lang=_ctx(c)[3], calendar_type=_cal(c)),
		"office_automation.compose", write=True)
	_register(registry, "update_oa_letter_draft", "ویرایش پیش‌نویس نامه. نیازمند تأیید.",
		_schema({**letter_id, "payload": draft_payload}, ["as_position_id", "letter_id", "payload"]),
		lambda a, c: _svc().update_letter_draft(c["db"], int(c["business_id"]), int(a["letter_id"]), a["payload"], c["user_context"].get_user_id(), _pid(a), lang=_ctx(c)[3], calendar_type=_cal(c)),
		"office_automation.compose", write=True)
	_register(registry, "delete_oa_letter_draft", "حذف پیش‌نویس نامه. نیازمند تأیید.",
		_schema(letter_id, ["as_position_id", "letter_id"]),
		lambda a, c: _svc().delete_letter_draft(c["db"], int(c["business_id"]), int(a["letter_id"]), c["user_context"].get_user_id(), _pid(a)),
		"office_automation.compose", write=True, high=True)
	_register(registry, "register_oa_letter", "ثبت و شماره‌گذاری نامه؛ وارده/صادره فقط از سمت دبیرخانه. recipients برای ارجاع اول. نیازمند تأیید.",
		_schema({**letter_id, "payload": {"type": "object", "properties": {
			"letter_kind": {"type": "string", "enum": _KIND},
			"recipients": {"type": "array", "items": {"type": "object", "properties": {
				"to_position_id": {"type": "integer"}, "kind": {"type": "string", "enum": _REF_KIND},
				"priority": {"type": "string", "enum": _URGENCY}, "instruction": {"type": "string"}, "due_at": {"type": "string"},
			}}},
		}}}, ["as_position_id", "letter_id"]),
		lambda a, c: _svc().register_letter(c["db"], int(c["business_id"]), int(a["letter_id"]), a.get("payload") or {}, c["user_context"].get_user_id(), _pid(a), lang=_ctx(c)[3], calendar_type=_cal(c)),
		"office_automation.compose", write=True, high=True)
	_register(registry, "refer_oa_letter", "ارجاع نامه به یک یا چند سمت. نیازمند تأیید.",
		_schema({**letter_id, "payload": {"type": "object"}}, ["as_position_id", "letter_id", "payload"]),
		lambda a, c: _svc().refer_letter(c["db"], int(c["business_id"]), int(a["letter_id"]), a["payload"], c["user_context"].get_user_id(), _pid(a), lang=_ctx(c)[3], calendar_type=_cal(c)),
		"office_automation.refer", write=True)
	_register(registry, "complete_oa_referral", "اقدام و بستن ارجاع کارتابل. نیازمند تأیید.",
		_schema({**pos, "referral_id": {"type": "integer", "minimum": 1}, "note": {"type": "string"}}, ["as_position_id", "referral_id"]),
		lambda a, c: _svc().complete_referral(c["db"], int(c["business_id"]), int(a["referral_id"]), {"note": a.get("note")}, c["user_context"].get_user_id(), _pid(a), lang=_ctx(c)[3]),
		"office_automation.refer", write=True)
	_register(registry, "return_oa_referral", "عودت ارجاع به فرستنده. نیازمند تأیید.",
		_schema({**pos, "referral_id": {"type": "integer", "minimum": 1}, "note": {"type": "string"}}, ["as_position_id", "referral_id"]),
		lambda a, c: _svc().return_referral(c["db"], int(c["business_id"]), int(a["referral_id"]), {"note": a.get("note")}, c["user_context"].get_user_id(), _pid(a), lang=_ctx(c)[3]),
		"office_automation.refer", write=True)
	_register(registry, "add_oa_paraph", "ثبت پاراف روی نامه از سمت فعال. نیازمند تأیید.",
		_schema({**letter_id, "text": {"type": "string", "minLength": 1}, "referral_id": {"type": ["integer", "null"]}}, ["as_position_id", "letter_id", "text"]),
		lambda a, c: _svc().add_paraph(c["db"], int(c["business_id"]), int(a["letter_id"]), {"text": a["text"], "referral_id": a.get("referral_id")}, c["user_context"].get_user_id(), _pid(a), lang=_ctx(c)[3]),
		"office_automation.refer", write=True)
	_register(registry, "add_oa_letter_attachment", "پیوست فایل موجود (file_storage_id) به نامه. نیازمند تأیید.",
		_schema({**letter_id, "file_storage_id": {"type": "string"}, "title": {"type": "string"}}, ["as_position_id", "letter_id", "file_storage_id"]),
		lambda a, c: _svc().add_attachment(c["db"], int(c["business_id"]), int(a["letter_id"]), {"file_storage_id": a["file_storage_id"], "title": a.get("title")}, c["user_context"].get_user_id(), _pid(a)),
		"office_automation.compose", write=True)
	_register(registry, "remove_oa_letter_attachment", "حذف پیوست نامه. نیازمند تأیید.",
		_schema({**pos, "attachment_id": {"type": "integer", "minimum": 1}}, ["as_position_id", "attachment_id"]),
		lambda a, c: _svc().remove_attachment(c["db"], int(c["business_id"]), int(a["attachment_id"]), c["user_context"].get_user_id(), _pid(a)),
		"office_automation.compose", write=True)
	_register(registry, "archive_oa_letter", "بایگانی نامه. نیازمند تأیید.",
		_schema(letter_id, ["as_position_id", "letter_id"]),
		lambda a, c: _svc().archive_letter(c["db"], int(c["business_id"]), int(a["letter_id"]), c["user_context"].get_user_id(), _pid(a), lang=_ctx(c)[3]),
		"office_automation.archive", write=True)
	_register(registry, "set_oa_follow_up", "تعیین تاریخ پیگیری نامه. نیازمند تأیید.",
		_schema({**letter_id, "follow_up_at": {"type": ["string", "null"]}}, ["as_position_id", "letter_id"]),
		lambda a, c: _svc().set_follow_up(c["db"], int(c["business_id"]), int(a["letter_id"]), {"follow_up_at": a.get("follow_up_at")}, c["user_context"].get_user_id(), _pid(a), lang=_ctx(c)[3], calendar_type=_cal(c)),
		"office_automation.refer", write=True)
	_register(registry, "link_oa_letters", "پیوند نامه به نامه مرتبط/پاسخ/پیرو. نیازمند تأیید.",
		_schema({**letter_id, "related_letter_id": {"type": "integer", "minimum": 1}, "link_kind": {"type": "string", "enum": ["related", "reply", "followup"]}}, ["as_position_id", "letter_id", "related_letter_id"]),
		lambda a, c: _svc().link_letters(c["db"], int(c["business_id"]), int(a["letter_id"]), {"related_letter_id": a["related_letter_id"], "link_kind": a.get("link_kind") or "related"}, c["user_context"].get_user_id(), _pid(a)),
		"office_automation.refer", write=True)

	_register(registry, "search_oa_letters", "جستجوی نامه‌های ثبت‌شده بر اساس موضوع، شماره یا شناسه.",
		_schema({"q": {"type": "string"}, "limit": {"type": "integer", "minimum": 1, "maximum": 50}}),
		lambda a, c: {"items": _svc().search_letters(c["db"], int(c["business_id"]), c["user_context"].get_user_id(), q=a.get("q"), limit=int(a.get("limit") or 20), lang=_ctx(c)[3], is_admin=c["user_context"].has_business_permission("office_automation", "admin"))},
		"office_automation.view")
	_register(registry, "list_oa_letter_formats", "فهرست فرمت‌های کاغذ و سربرگ نامه.",
		_schema({"include_inactive": {"type": "boolean"}}),
		lambda a, c: {"items": _svc().list_letter_formats(c["db"], int(c["business_id"]), include_inactive=bool(a.get("include_inactive", False)))},
		"office_automation.view")
	_register(registry, "create_oa_letter_format", "ساخت فرمت کاغذ، حاشیه، سربرگ و پس‌زمینه نامه. نیازمند تأیید.",
		_schema({"payload": {"type": "object"}}, ["payload"]),
		lambda a, c: _svc().create_letter_format(c["db"], int(c["business_id"]), a["payload"], c["user_context"].get_user_id()),
		"office_automation.admin", write=True)
	_register(registry, "update_oa_letter_format", "ویرایش فرمت نامه. نیازمند تأیید.",
		_schema({"format_id": {"type": "integer", "minimum": 1}, "payload": {"type": "object"}}, ["format_id", "payload"]),
		lambda a, c: _svc().update_letter_format(c["db"], int(c["business_id"]), int(a["format_id"]), a["payload"], c["user_context"].get_user_id()),
		"office_automation.admin", write=True)
	_register(registry, "delete_oa_letter_format", "حذف فرمت نامه. نیازمند تأیید.",
		_schema({"format_id": {"type": "integer", "minimum": 1}}, ["format_id"]),
		lambda a, c: _svc().delete_letter_format(c["db"], int(c["business_id"]), int(a["format_id"]), c["user_context"].get_user_id()),
		"office_automation.admin", write=True, high=True)
	_register(registry, "list_oa_letter_templates", "فهرست قالب‌های آماده نامه.",
		_schema({"include_inactive": {"type": "boolean"}, "letter_kind": {"type": "string", "enum": _KIND}}),
		lambda a, c: {"items": _svc().list_letter_templates(c["db"], int(c["business_id"]), include_inactive=bool(a.get("include_inactive", False)), letter_kind=a.get("letter_kind"))},
		"office_automation.view")
	_register(registry, "create_oa_letter_template", "ساخت قالب نامه آماده. نیازمند تأیید.",
		_schema({"payload": {"type": "object"}}, ["payload"]),
		lambda a, c: _svc().create_letter_template(c["db"], int(c["business_id"]), a["payload"], c["user_context"].get_user_id()),
		"office_automation.admin", write=True)
	_register(registry, "update_oa_letter_template", "ویرایش قالب نامه. نیازمند تأیید.",
		_schema({"template_id": {"type": "integer", "minimum": 1}, "payload": {"type": "object"}}, ["template_id", "payload"]),
		lambda a, c: _svc().update_letter_template(c["db"], int(c["business_id"]), int(a["template_id"]), a["payload"], c["user_context"].get_user_id()),
		"office_automation.admin", write=True)
	_register(registry, "delete_oa_letter_template", "حذف قالب نامه. نیازمند تأیید.",
		_schema({"template_id": {"type": "integer", "minimum": 1}}, ["template_id"]),
		lambda a, c: _svc().delete_letter_template(c["db"], int(c["business_id"]), int(a["template_id"]), c["user_context"].get_user_id()),
		"office_automation.admin", write=True, high=True)
