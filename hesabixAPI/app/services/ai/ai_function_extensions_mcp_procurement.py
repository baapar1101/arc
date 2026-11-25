"""ابزارهای MCP تدارکات. لایسنس افزونه جدا از لایسنس کانال MCP بررسی می‌شود."""
from __future__ import annotations

from typing import Any, Dict

from app.core.procurement_plugin_dependency import check_procurement_plugin_active
from app.core.responses import ApiError
from app.services.ai.function_registry import AIFunction, AIRole

_ROLES = {AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN}


def _schema(properties=None, required=()):
	return {"type": "object", "properties": properties or {}, "required": list(required), "additionalProperties": False}


def _ctx(context: Dict[str, Any]):
	db = context["db"]
	business_id = int(context["business_id"])
	if not check_procurement_plugin_active(db, business_id):
		raise ApiError(
			"PROCUREMENT_PLUGIN_NOT_ACTIVE",
			"افزونه تدارکات برای این کسب‌وکار فعال نیست. داده خرید را حدس نزن.",
			http_status=403,
		)
	return db, business_id, context["user_context"].get_user_id()


def _register(registry, name, description, schema, handler, permission, *, write=False, high=False):
	registry.register(
		AIFunction(
			name=name,
			description=description,
			parameters_schema=schema,
			handler=handler,
			allowed_roles=_ROLES,
			required_permissions=[permission],
			category="procurement",
			requires_approval=bool(write),
			risk_level="high" if high else ("medium" if write else "safe"),
			is_readonly=not write,
		)
	)


def register_mcp_procurement_functions(registry) -> None:
	from app.services import procurement_service as svc

	_register(
		registry,
		"get_procurement_dashboard",
		"داشبورد تدارکات همین کسب‌وکار: درخواست معوق، سفارش باز، مغایرت فاکتور، قرارداد رو به انقضا و هشدار بودجه.",
		_schema(),
		lambda a, c: svc.dashboard(*_ctx(c)),
		"procurement.view",
	)
	_register(
		registry,
		"list_procurement_orders",
		"فهرست سفارش‌های خرید. وضعیت را فقط از همین خروجی بگو.",
		_schema({"status": {"type": "string"}, "limit": {"type": "integer", "minimum": 1, "maximum": 100}}),
		lambda a, c: svc.list_orders(_ctx(c)[0], _ctx(c)[1], a.get("status"), int(a.get("limit") or 50), 0),
		"procurement.view",
	)
	_register(
		registry,
		"get_procurement_order",
		"جزئیات یک سفارش خرید با اقلام، رسید، فاکتور و تأییدها.",
		_schema({"order_id": {"type": "integer", "minimum": 1}}, ["order_id"]),
		lambda a, c: svc.get_order(_ctx(c)[0], _ctx(c)[1], int(a["order_id"])),
		"procurement.view",
	)
	_register(
		registry,
		"create_procurement_requisition",
		"ثبت درخواست خرید. اگر موجودی نیاز را بپوشاند، بدون acknowledge_duplicate ثبت نمی‌شود. نیازمند تأیید.",
		_schema({"payload": {"type": "object"}}, ["payload"]),
		lambda a, c: svc.create_requisition(*_ctx(c)[:2], a["payload"], _ctx(c)[2]),
		"procurement.operate",
		write=True,
	)
	_register(
		registry,
		"decide_procurement_approval",
		"تأیید، رد یا برگشت درخواست، سفارش یا حرکت بودجه. رد و برگشت دلیل می‌خواهند. نیازمند تأیید.",
		_schema(
			{
				"entity_type": {"type": "string", "enum": ["requisition", "order", "budget_movement"]},
				"entity_id": {"type": "integer", "minimum": 1},
				"action": {"type": "string", "enum": ["approve", "reject", "return"]},
				"note": {"type": "string"},
			},
			["entity_type", "entity_id", "action"],
		),
		lambda a, c: svc.decide(_ctx(c)[0], _ctx(c)[1], a["entity_type"], int(a["entity_id"]), a["action"], a.get("note"), _ctx(c)[2]),
		"procurement.approve",
		write=True,
		high=True,
	)
	_register(
		registry,
		"create_procurement_order",
		"ایجاد پیش‌نویس سفارش خرید برای شخص تأمین‌کننده. سند حسابداری نمی‌سازد. نیازمند تأیید.",
		_schema({"payload": {"type": "object"}}, ["payload"]),
		lambda a, c: svc.create_order(*_ctx(c)[:2], a["payload"], _ctx(c)[2]),
		"procurement.operate",
		write=True,
	)
	_register(
		registry,
		"receive_procurement_order",
		"ثبت رسید جزئی روی سفارش تأییدشده و در صورت کالا، حواله ورود انبار. نیازمند تأیید.",
		_schema({"order_id": {"type": "integer", "minimum": 1}, "payload": {"type": "object"}}, ["order_id", "payload"]),
		lambda a, c: svc.receive_order(_ctx(c)[0], _ctx(c)[1], int(a["order_id"]), a["payload"], _ctx(c)[2]),
		"procurement.operate",
		write=True,
		high=True,
	)
	_register(
		registry,
		"compare_procurement_bids",
		"مقایسه وزنی پیشنهادهای یک استعلام. برنده را فقط با جایزهٔ صریح و دلیل انتخاب کن، نه با کمترین قیمت.",
		_schema({"event_id": {"type": "integer", "minimum": 1}}, ["event_id"]),
		lambda a, c: svc.compare_sourcing(_ctx(c)[0], _ctx(c)[1], int(a["event_id"])),
		"procurement.view",
	)
	_register(
		registry,
		"award_procurement_event",
		"انتخاب برنده استعلام یا مناقصه و ساخت پیش‌نویس سفارش. دلیل انتخاب اجباری است. نیازمند تأیید.",
		_schema({"event_id": {"type": "integer", "minimum": 1}, "payload": {"type": "object"}}, ["event_id", "payload"]),
		lambda a, c: svc.award_sourcing(_ctx(c)[0], _ctx(c)[1], int(a["event_id"]), a["payload"], _ctx(c)[2]),
		"procurement.approve",
		write=True,
		high=True,
	)
