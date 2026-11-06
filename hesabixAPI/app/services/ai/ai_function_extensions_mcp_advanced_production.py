"""ابزارهای MCP افزونه تولید پیشرفته. بدون لایسنس افزونه اجرا نمی‌شوند."""
from __future__ import annotations

from typing import Any, Dict

from app.services.ai.function_registry import AIFunction, AIRole

_ROLES = {AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN}
_REPORTS = [
	"orders",
	"progress",
	"overdue",
	"schedule",
	"plan_achievement",
	"open_orders",
	"cycle_time",
	"order_costing",
	"material_requirements",
	"material_shortage",
	"material_variance",
	"scrap",
	"scrap_by_product",
	"scrap_rate",
	"finished_goods",
	"finished_by_product",
	"unplanned_production",
	"oee",
	"downtime",
	"inspections",
	"maintenance",
	"reliability",
	"product_profit",
	"cost_share",
	"qc_pass_rate",
	"production_daily",
	"line_output",
	"shift_output",
	"wip_age",
	"work_center_output",
	"capacity_usage",
	"qc_rejects",
	"period_cost",
	"operator_output",
	"setup_time",
	"lot_trace",
	"yield_rate",
	"unused_capacity",
	"break_even",
	"monthly_comparison",
	"material_flow",
	"production_by_lot",
	"conversion_efficiency",
	"low_yield",
	"line_maintenance_cost",
	"material_price_variance",
	"product_cost",
	"wip_balance",
	"operation_variance",
	"scrap_by_reason",
	"recyclable_scrap",
	"nonrecyclable_scrap",
	"qc_causes",
	"machine_output",
	"downtime_cost",
	"held_orders",
	"material_consumption",
	"capacity_required",
	"wip_count",
	"rework",
	"line_returns",
	"wip_by_center",
	"material_scrap",
	"idle_materials",
	"stage_transfers",
	"wage_variance",
]


def _schema(properties=None, required=()):
	return {
		"type": "object",
		"properties": properties or {},
		"required": list(required),
		"additionalProperties": False,
	}


def _guard(handler):
	def wrapped(args: Dict[str, Any], context: Dict[str, Any]):
		from app.core.advanced_production_plugin_dependency import check_advanced_production_plugin_active
		from app.core.responses import ApiError

		db = context["db"]
		business_id = int(context["business_id"])
		if not check_advanced_production_plugin_active(db, business_id):
			raise ApiError(
				"ADVANCED_PRODUCTION_PLUGIN_NOT_ACTIVE",
				"ADVANCED_PRODUCTION_PLUGIN_NOT_ACTIVE",
				http_status=403,
				details={"plugin_code": "advanced_production"},
			)
		return handler(args, context)

	return wrapped


def register_mcp_advanced_production_functions(registry) -> None:
	from app.services import advanced_production_service as svc

	def settings(args, context):
		data = svc.get_settings(context["db"], int(context["business_id"]))
		context["db"].commit()
		return data

	def update(args, context):
		data = svc.update_settings(context["db"], int(context["business_id"]), args.get("payload") or {})
		context["db"].commit()
		return data

	def dashboard(args, context):
		data = svc.get_dashboard(context["db"], int(context["business_id"]))
		context["db"].commit()
		return data

	def report(args, context):
		data = svc.run_named_report(
			context["db"],
			int(context["business_id"]),
			str(args["report_key"]),
			args,
		)
		context["db"].commit()
		return data

	registry.register(AIFunction(
		name="get_advanced_production_settings",
		description="تنظیمات افزونه تولید پیشرفته کسب‌وکار متصل. روش بها فقط گزارش افزونه را عوض می‌کند و دفتر کل را بازنویسی نمی‌کند. افزونه باید فعال باشد.",
		parameters_schema=_schema(),
		handler=_guard(settings),
		allowed_roles=_ROLES,
		required_permissions=["advanced_production.view"],
		category="advanced_production",
		is_readonly=True,
	))
	registry.register(AIFunction(
		name="update_advanced_production_settings",
		description="ویرایش روش بهای گزارش تولید پیشرفته و پیوند حساب‌های اختیاری. اسناد تولید ثبت‌شده را عوض نمی‌کند. نیازمند تأیید. افزونه باید فعال باشد.",
		parameters_schema=_schema({
			"payload": {
				"type": "object",
				"additionalProperties": False,
				"properties": {
					"costing_method": {"type": "string", "enum": ["actual", "standard", "weighted_average"]},
					"overhead_mode": {"type": "string", "enum": ["bom_operations"]},
					"wip_account_id": {"type": ["integer", "null"], "minimum": 1},
					"finished_goods_account_id": {"type": ["integer", "null"], "minimum": 1},
					"scrap_expense_account_id": {"type": ["integer", "null"], "minimum": 1},
					"cost_variance_account_id": {"type": ["integer", "null"], "minimum": 1},
				},
			},
		}, ["payload"]),
		handler=_guard(update),
		allowed_roles=_ROLES,
		required_permissions=["advanced_production.manage"],
		category="advanced_production",
		requires_approval=True,
		risk_level="medium",
		is_readonly=False,
	))
	registry.register(AIFunction(
		name="get_advanced_production_dashboard",
		description="داشبورد تولید پیشرفته کسب‌وکار متصل: سفارش باز، سررسیدگذشته و خروجی امروز. تاریخ‌ها با تقویم کسب‌وکار است. افزونه باید فعال باشد.",
		parameters_schema=_schema(),
		handler=_guard(dashboard),
		allowed_roles=_ROLES,
		required_permissions=["advanced_production.view"],
		category="advanced_production",
		is_readonly=True,
	))
	registry.register(AIFunction(
		name="get_advanced_production_report",
		description="یک گزارش نام‌دار تولید پیشرفته. تاریخ‌ها ISO (YYYY-MM-DD) هستند. واریانس مثبت یعنی نامساعد نسبت به استاندارد. افزونه باید فعال باشد.",
		parameters_schema=_schema({
			"report_key": {"type": "string", "enum": _REPORTS},
			"date_from": {"type": ["string", "null"]},
			"date_to": {"type": ["string", "null"]},
			"product_id": {"type": ["integer", "null"], "minimum": 1},
			"status": {"type": ["string", "null"]},
			"search": {"type": ["string", "null"]},
			"production_order_id": {"type": ["integer", "null"], "minimum": 1},
			"lot_code": {"type": ["string", "null"]},
			"fixed_cost": {"type": ["number", "null"], "exclusiveMinimum": 0},
			"calendar_type": {"type": "string", "enum": ["jalali", "gregorian"]},
			"days_without_movement": {"type": "integer", "minimum": 1, "maximum": 3650},
			"fiscal_year_id": {"type": ["integer", "null"], "minimum": 1},
			"warehouse_id": {"type": ["integer", "null"], "minimum": 1},
			"currency_id": {"type": ["integer", "null"], "minimum": 1},
			"skip": {"type": "integer", "minimum": 0},
			"take": {"type": "integer", "minimum": 1, "maximum": 200},
		}, ["report_key"]),
		handler=_guard(report),
		allowed_roles=_ROLES,
		required_permissions=["advanced_production.view"],
		category="advanced_production",
		is_readonly=True,
	))
	kinds = ["work_centers", "lines", "machines", "shifts", "downtime", "outputs", "inspections", "maintenance", "scrap_reasons", "scrap_events", "order_holds", "order_lines", "wip_counts", "reworks", "line_returns", "stage_transfers", "labor"]

	def list_master(args, context):
		from app.services.advanced_production_master import list_master as read
		return read(context["db"], int(context["business_id"]), str(args["kind"]))

	def create_master(args, context):
		from app.services.advanced_production_master import create_master as write
		data = write(context["db"], int(context["business_id"]), str(args["kind"]), args.get("payload") or {})
		context["db"].commit()
		return data

	registry.register(AIFunction(
		name="list_advanced_production_master",
		description="فهرست داده پایه تولید پیشرفته: مرکز کار، خط، ماشین، شیفت، توقف، خروجی یا بازرسی کیفیت. افزونه باید فعال باشد.",
		parameters_schema=_schema({"kind": {"type": "string", "enum": kinds}}, ["kind"]),
		handler=_guard(list_master),
		allowed_roles=_ROLES,
		required_permissions=["advanced_production.view"],
		category="advanced_production",
		is_readonly=True,
	))
	registry.register(AIFunction(
		name="create_advanced_production_master",
		description="ثبت یک رکورد داده پایه تولید پیشرفته. تاریخ ISO و ساعت شیفت HH:MM است. نیازمند تأیید. افزونه باید فعال باشد.",
		parameters_schema=_schema({
			"kind": {"type": "string", "enum": kinds},
			"payload": {"type": "object"},
		}, ["kind", "payload"]),
		handler=_guard(create_master),
		allowed_roles=_ROLES,
		required_permissions=["advanced_production.operate"],
		category="advanced_production",
		requires_approval=True,
		risk_level="medium",
		is_readonly=False,
	))
