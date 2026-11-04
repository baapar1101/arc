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


def _register(registry, name, description, schema, handler, permission, *, write=False):
	registry.register(AIFunction(
		name=name,
		description=description,
		parameters_schema=schema,
		handler=_guard(handler),
		allowed_roles=_ROLES,
		required_permissions=[permission],
		category="advanced_production",
		requires_approval=bool(write),
		risk_level="medium" if write else "safe",
		is_readonly=not write,
	))


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

	_register(
		registry,
		"get_advanced_production_settings",
		"Read advanced production plugin settings. Valuation method affects plugin reports only and does not repost the general ledger. Plugin must be active.",
		_schema(),
		settings,
		"advanced_production.view",
	)
	_register(
		registry,
		"update_advanced_production_settings",
		"Update advanced production report valuation method and optional account links. Does not change posted production invoices. Requires confirmation.",
		_schema({
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
		update,
		"advanced_production.manage",
		write=True,
	)
	_register(
		registry,
		"get_advanced_production_dashboard",
		"Advanced production dashboard for the connected business: open, overdue and today's output. Dates follow the business calendar. Plugin must be active.",
		_schema(),
		dashboard,
		"advanced_production.view",
	)
	_register(
		registry,
		"get_advanced_production_report",
		"One advanced production report. Dates are ISO YYYY-MM-DD. Positive variance means unfavorable versus standard. Plugin must be active.",
		_schema({
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
		report,
		"advanced_production.view",
	)
	kinds = ["work_centers", "lines", "machines", "shifts", "downtime", "outputs", "inspections", "maintenance", "scrap_reasons", "scrap_events", "order_holds", "order_lines", "wip_counts", "reworks", "line_returns", "stage_transfers", "labor"]

	def list_master(args, context):
		from app.services.advanced_production_master import list_master as read
		return read(context["db"], int(context["business_id"]), str(args["kind"]))

	def create_master(args, context):
		from app.services.advanced_production_master import create_master as write
		data = write(context["db"], int(context["business_id"]), str(args["kind"]), args.get("payload") or {})
		context["db"].commit()
		return data

	_register(
		registry,
		"list_advanced_production_master",
		"List advanced production master data: work centers, lines, machines, shifts, downtime, output logs, or QC inspections. Plugin must be active.",
		_schema({"kind": {"type": "string", "enum": kinds}}, ["kind"]),
		list_master,
		"advanced_production.view",
	)
	_register(
		registry,
		"create_advanced_production_master",
		"Create one advanced production master record. Dates are ISO dates. Shift times are HH:MM. Requires confirmation. Plugin must be active.",
		_schema({
			"kind": {"type": "string", "enum": kinds},
			"payload": {"type": "object"},
		}, ["kind", "payload"]),
		create_master,
		"advanced_production.operate",
		write=True,
	)
