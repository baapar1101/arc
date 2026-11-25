"""MCP tools for the fixed-assets plugin: register, lifecycle, depreciation."""
from __future__ import annotations

from typing import Any, Dict

_ROLES_LAZY = None
_MAX_LIST = 200
_METHOD_ENUM = ["straight_line", "declining_balance"]
_METHOD_ALIASES = {
    "straight_line": "straight_line",
    "declining": "declining_balance",
    "declining_balance": "declining_balance",
}

CREATE_FIXED_ASSET_SCHEMA: Dict[str, Any] = {}
UPDATE_FIXED_ASSET_SETTINGS_SCHEMA: Dict[str, Any] = {}
CAPITALIZE_FIXED_ASSET_SCHEMA: Dict[str, Any] = {}
DISPOSE_FIXED_ASSET_SCHEMA: Dict[str, Any] = {}


def _schema(properties: Dict[str, Any], required: list[str] | None = None) -> Dict[str, Any]:
    return {
        "type": "object",
        "properties": properties,
        "required": list(required or []),
        "additionalProperties": False,
    }


def _raise_service(exc: BaseException) -> None:
    from app.core.responses import ApiError

    if isinstance(exc, ApiError):
        raise ValueError(exc.message) from exc
    raise exc


def _svc():
    from app.services import fixed_asset_service as svc

    return svc


def _run(fn, *args):
    try:
        return fn(*args)
    except Exception as exc:
        _raise_service(exc)


def _bid(context: Dict[str, Any]) -> int:
    return int(context["business_id"])


def _uid(context: Dict[str, Any]) -> int:
    return int(context["user_context"].get_user_id())


def _db(context: Dict[str, Any]):
    return context["db"]


def _normalize_method_fields(payload: Dict[str, Any]) -> Dict[str, Any]:
    out = dict(payload)
    for key in ("method", "default_method"):
        raw = out.get(key)
        if isinstance(raw, str) and raw in _METHOD_ALIASES:
            out[key] = _METHOD_ALIASES[raw]
    return out


_COUNTERPARTY = {
    "counterparty_type": {
        "type": "string",
        "enum": ["person", "bank", "cash_register", "petty_cash", "opening", "account"],
        "description": "طرف حساب سند از موجودیت‌های همین کسب‌وکار",
    },
    "person_id": {"type": ["integer", "null"], "minimum": 1},
    "bank_account_id": {"type": ["integer", "null"], "minimum": 1},
    "cash_register_id": {"type": ["integer", "null"], "minimum": 1},
    "petty_cash_id": {"type": ["integer", "null"], "minimum": 1},
    "account_id": {"type": ["integer", "null"], "minimum": 1},
}

CREATE_FIXED_ASSET_SCHEMA = _schema(
    {
        "class_id": {"type": "integer", "minimum": 1, "description": "شناسه طبقه از list_fixed_asset_classes"},
        "name": {"type": "string", "minLength": 1, "maxLength": 255},
        "code": {"type": ["string", "null"], "maxLength": 64, "description": "اگر خالی باشد خودکار است"},
        "description": {"type": ["string", "null"], "maxLength": 1000},
        "serial_number": {"type": ["string", "null"], "maxLength": 100},
        "acquisition_kind": {"type": "string", "enum": ["purchase", "opening"]},
        "acquisition_date": {"type": "string", "format": "date"},
        "commission_date": {"type": ["string", "null"], "format": "date"},
        "cost": {"type": "number", "exclusiveMinimum": 0},
        "salvage": {"type": ["number", "null"], "minimum": 0},
        "vat_amount": {"type": ["number", "null"], "minimum": 0},
        "opening_accum_depreciation": {"type": ["number", "null"], "minimum": 0},
        "method": {"type": "string", "enum": _METHOD_ENUM},
        "useful_life_months": {"type": ["integer", "null"], "minimum": 1, "maximum": 1200},
        "declining_annual_rate": {"type": ["number", "null"], "exclusiveMinimum": 0, "exclusiveMaximum": 1},
        "location_id": {"type": ["integer", "null"], "minimum": 1},
        "custodian_person_id": {"type": ["integer", "null"], "minimum": 1},
        "project_id": {"type": ["integer", "null"], "minimum": 1},
    },
    ["class_id", "name", "acquisition_date", "cost"],
)
UPDATE_FIXED_ASSET_SETTINGS_SCHEMA = _schema(
    {
        "enabled": {"type": "boolean"},
        "default_currency_id": {"type": ["integer", "null"], "minimum": 1},
        "vat_account_id": {"type": ["integer", "null"], "minimum": 1},
        "vat_output_account_id": {"type": ["integer", "null"], "minimum": 1},
        "opening_equity_account_id": {"type": ["integer", "null"], "minimum": 1},
        "disposal_gain_account_id": {"type": ["integer", "null"], "minimum": 1},
        "disposal_loss_account_id": {"type": ["integer", "null"], "minimum": 1},
        "repair_expense_account_id": {"type": ["integer", "null"], "minimum": 1},
        "accounting_convention": {"type": "string", "enum": ["from_ready_date", "next_month"]},
        "tax_idle_months": {"type": "integer", "minimum": 0, "maximum": 600},
        "tax_idle_factor": {"type": "number", "minimum": 0, "maximum": 1},
        "accounting_idle_factor": {"type": "number", "minimum": 0, "maximum": 1},
        "require_custodian": {"type": "boolean"},
        "plaque_prefix": {"type": "string", "minLength": 1, "maxLength": 16},
    }
)
CAPITALIZE_FIXED_ASSET_SCHEMA = _schema(
    {"asset_id": {"type": "integer", "minimum": 1}, **_COUNTERPARTY},
    ["asset_id", "counterparty_type"],
)
DISPOSE_FIXED_ASSET_SCHEMA = _schema(
    {
        "asset_id": {"type": "integer", "minimum": 1},
        "kind": {"type": "string", "enum": ["sale", "scrap"]},
        "disposal_date": {"type": ["string", "null"], "format": "date"},
        "proceeds": {"type": ["number", "null"], "minimum": 0},
        "vat_output": {"type": ["number", "null"], "minimum": 0},
        **_COUNTERPARTY,
    },
    ["asset_id"],
)


def _public_settings(data: Any) -> Any:
    if not isinstance(data, dict):
        return data
    out = dict(data)
    out.pop("extra_settings", None)
    out.pop("extra_info", None)
    return out


def get_fixed_asset_settings_handler(args, context):
    return _public_settings(_run(_svc().get_settings, _db(context), _bid(context)))


def update_fixed_asset_settings_handler(args, context):
    return _public_settings(
        _run(_svc().update_settings, _db(context), _bid(context), dict(args), _uid(context))
    )


def get_fixed_assets_dashboard_handler(args, context):
    return _run(_svc().get_dashboard, _db(context), _bid(context))


def list_fixed_asset_classes_handler(args, context):
    return {
        "items": _run(
            _svc().list_classes,
            _db(context),
            _bid(context),
            bool(args.get("include_inactive", False)),
        )
    }


def update_fixed_asset_class_handler(args, context):
    payload = _normalize_method_fields({k: v for k, v in args.items() if k != "class_id"})
    return _run(_svc().update_class, _db(context), _bid(context), int(args["class_id"]), payload, _uid(context))


def list_fixed_asset_locations_handler(args, context):
    return {
        "items": _run(
            _svc().list_locations,
            _db(context),
            _bid(context),
            bool(args.get("include_inactive", False)),
        )
    }


def create_fixed_asset_location_handler(args, context):
    return _run(_svc().create_location, _db(context), _bid(context), dict(args), _uid(context))


def update_fixed_asset_location_handler(args, context):
    payload = {k: v for k, v in args.items() if k != "location_id"}
    return _run(_svc().update_location, _db(context), _bid(context), int(args["location_id"]), payload, _uid(context))


def list_fixed_assets_handler(args, context):
    return _run(
        lambda: _svc().list_assets(
            _db(context),
            _bid(context),
            status=args.get("status"),
            class_id=args.get("class_id"),
            search=args.get("search"),
            invoice_id=args.get("invoice_id"),
            limit=int(args.get("limit", 100)),
            skip=int(args.get("skip", 0)),
        )
    )


def get_fixed_asset_handler(args, context):
    return _run(_svc().get_asset, _db(context), _bid(context), int(args["asset_id"]))


def create_fixed_asset_handler(args, context):
    return _run(
        _svc().create_asset,
        _db(context),
        _bid(context),
        _normalize_method_fields(dict(args)),
        _uid(context),
    )


def update_fixed_asset_handler(args, context):
    payload = _normalize_method_fields({k: v for k, v in args.items() if k != "asset_id"})
    return _run(_svc().update_asset, _db(context), _bid(context), int(args["asset_id"]), payload, _uid(context))


def delete_fixed_asset_handler(args, context):
    return _run(_svc().delete_asset, _db(context), _bid(context), int(args["asset_id"]))


def capitalize_fixed_asset_handler(args, context):
    payload = {k: v for k, v in args.items() if k != "asset_id"}
    return _run(_svc().capitalize_asset, _db(context), _bid(context), int(args["asset_id"]), payload, _uid(context))


def set_fixed_asset_idle_handler(args, context):
    payload = {k: v for k, v in args.items() if k != "asset_id"}
    return _run(_svc().set_asset_idle, _db(context), _bid(context), int(args["asset_id"]), payload, _uid(context))


def resume_fixed_asset_handler(args, context):
    return _run(_svc().resume_asset, _db(context), _bid(context), int(args["asset_id"]), _uid(context))


def dispose_fixed_asset_handler(args, context):
    payload = {k: v for k, v in args.items() if k != "asset_id"}
    return _run(_svc().dispose_asset, _db(context), _bid(context), int(args["asset_id"]), payload, _uid(context))


def post_fixed_asset_expenditure_handler(args, context):
    payload = {k: v for k, v in args.items() if k != "asset_id"}
    return _run(
        _svc().post_subsequent_expenditure,
        _db(context),
        _bid(context),
        int(args["asset_id"]),
        payload,
        _uid(context),
    )


def change_fixed_asset_estimate_handler(args, context):
    payload = _normalize_method_fields({k: v for k, v in args.items() if k != "asset_id"})
    return _run(_svc().change_asset_estimate, _db(context), _bid(context), int(args["asset_id"]), payload, _uid(context))


def list_fixed_asset_depreciation_runs_handler(args, context):
    return _run(
        lambda: _svc().list_depreciation_runs(
            _db(context),
            _bid(context),
            limit=int(args.get("limit", 50)),
            skip=int(args.get("skip", 0)),
        )
    )


def get_fixed_asset_depreciation_run_handler(args, context):
    return _run(_svc().get_depreciation_run, _db(context), _bid(context), int(args["run_id"]))


def create_fixed_asset_depreciation_run_handler(args, context):
    return _run(_svc().create_depreciation_run, _db(context), _bid(context), dict(args), _uid(context))


def post_fixed_asset_depreciation_run_handler(args, context):
    return _run(_svc().post_depreciation_run, _db(context), _bid(context), int(args["run_id"]), _uid(context))


def delete_fixed_asset_depreciation_run_handler(args, context):
    return _run(_svc().delete_depreciation_run, _db(context), _bid(context), int(args["run_id"]))


GET_FIXED_ASSET_REPORT_SCHEMA = _schema(
    {
        "kind": {
            "type": "string",
            "enum": [
                "register",
                "class_summary",
                "depreciation",
                "acquisitions",
                "disposals",
                "idle",
                "locations",
                "expenditures",
            ],
            "description": (
                "register=دفتر اموال، class_summary=گردش طبقات استاندارد ۱۱، "
                "depreciation=استهلاک ثبت‌شده دوره، acquisitions=تحصیل دوره، "
                "disposals=خروج/اسقاط، idle=راکد، locations=محل/تحویل‌گیرنده، "
                "expenditures=مخارج بعدی"
            ),
        },
        "from_date": {"type": "string", "format": "date"},
        "to_date": {"type": "string", "format": "date"},
        "class_id": {"type": "integer", "minimum": 1},
        "status": {"type": "string", "enum": ["draft", "capitalized", "idle", "disposed"]},
        "location_id": {"type": "integer", "minimum": 1},
        "limit": {"type": "integer", "minimum": 1, "maximum": _MAX_LIST},
    },
    ["kind"],
)


def get_fixed_asset_report_handler(args, context):
    from app.services.fixed_asset_reports import get_fixed_asset_report

    return _run(
        lambda: get_fixed_asset_report(
            _db(context),
            _bid(context),
            str(args["kind"]),
            from_date=args.get("from_date"),
            to_date=args.get("to_date"),
            class_id=args.get("class_id"),
            status=args.get("status"),
            location_id=args.get("location_id"),
            limit=int(args.get("limit", 200)),
        )
    )


_CLASS_UPDATE_SCHEMA = _schema({
    "class_id": {"type": "integer", "minimum": 1},
    "name": {"type": "string", "minLength": 1, "maxLength": 255},
    "cost_account_id": {"type": ["integer", "null"], "minimum": 1},
    "accum_dep_account_id": {"type": ["integer", "null"], "minimum": 1},
    "dep_expense_account_id": {"type": ["integer", "null"], "minimum": 1},
    "default_method": {"type": "string", "enum": _METHOD_ENUM},
    "default_useful_life_months": {"type": ["integer", "null"], "minimum": 1, "maximum": 1200},
    "default_declining_rate": {"type": ["number", "null"], "exclusiveMinimum": 0, "exclusiveMaximum": 1},
    "is_active": {"type": "boolean"},
    "depreciable": {"type": "boolean"},
}, ["class_id"])
_LOCATION_CREATE_SCHEMA = _schema({
    "code": {"type": "string", "minLength": 1, "maxLength": 64},
    "name": {"type": "string", "minLength": 1, "maxLength": 255},
    "parent_id": {"type": ["integer", "null"], "minimum": 1},
}, ["code", "name"])
_LOCATION_UPDATE_SCHEMA = _schema({
    "location_id": {"type": "integer", "minimum": 1},
    "code": {"type": "string", "minLength": 1, "maxLength": 64},
    "name": {"type": "string", "minLength": 1, "maxLength": 255},
    "parent_id": {"type": ["integer", "null"], "minimum": 1},
    "is_active": {"type": "boolean"},
}, ["location_id"])
LIST_FIXED_ASSETS_SCHEMA = _schema({
    "status": {"type": "string", "enum": ["draft", "capitalized", "idle", "disposed"]},
    "class_id": {"type": "integer", "minimum": 1},
    "invoice_id": {
        "type": "integer",
        "minimum": 1,
        "description": "فیلتر دارایی‌های ساخته‌شده از یک فاکتور خرید سرمایه‌ای",
    },
    "search": {"type": "string", "maxLength": 200},
    "limit": {"type": "integer", "minimum": 1, "maximum": _MAX_LIST},
    "skip": {"type": "integer", "minimum": 0},
})
_LIST_ASSETS_SCHEMA = LIST_FIXED_ASSETS_SCHEMA
_ASSET_ID_SCHEMA = _schema({"asset_id": {"type": "integer", "minimum": 1}}, ["asset_id"])
_UPDATE_ASSET_SCHEMA = _schema({
    "asset_id": {"type": "integer", "minimum": 1},
    "name": {"type": "string", "minLength": 1, "maxLength": 255},
    "description": {"type": ["string", "null"], "maxLength": 1000},
    "serial_number": {"type": ["string", "null"], "maxLength": 100},
    "location_id": {"type": ["integer", "null"], "minimum": 1},
    "custodian_person_id": {"type": ["integer", "null"], "minimum": 1},
    "project_id": {"type": ["integer", "null"], "minimum": 1},
    "cost": {"type": "number", "exclusiveMinimum": 0},
    "salvage": {"type": ["number", "null"], "minimum": 0},
    "method": {"type": "string", "enum": _METHOD_ENUM},
    "useful_life_months": {"type": ["integer", "null"], "minimum": 1, "maximum": 1200},
    "declining_annual_rate": {"type": ["number", "null"], "exclusiveMinimum": 0, "exclusiveMaximum": 1},
}, ["asset_id"])
_IDLE_SCHEMA = _schema({
    "asset_id": {"type": "integer", "minimum": 1},
    "idle_from": {"type": ["string", "null"], "format": "date"},
}, ["asset_id"])
_EXPENDITURE_SCHEMA = _schema({
    "asset_id": {"type": "integer", "minimum": 1},
    "kind": {"type": "string", "enum": ["routine", "major"]},
    "amount": {"type": "number", "exclusiveMinimum": 0},
    "vat_amount": {"type": ["number", "null"], "minimum": 0},
    "expenditure_date": {"type": ["string", "null"], "format": "date"},
    "description": {"type": ["string", "null"], "maxLength": 500},
    "remaining_useful_life_months": {"type": ["integer", "null"], "minimum": 1, "maximum": 1200},
    **_COUNTERPARTY,
}, ["asset_id", "kind", "amount", "counterparty_type"])
_ESTIMATE_SCHEMA = _schema({
    "asset_id": {"type": "integer", "minimum": 1},
    "effective_date": {"type": ["string", "null"], "format": "date"},
    "method": {"type": "string", "enum": _METHOD_ENUM},
    "salvage": {"type": ["number", "null"], "minimum": 0},
    "remaining_useful_life_months": {"type": ["integer", "null"], "minimum": 1, "maximum": 1200},
    "declining_annual_rate": {"type": ["number", "null"], "exclusiveMinimum": 0, "exclusiveMaximum": 1},
}, ["asset_id"])
_RUN_LIST_SCHEMA = _schema({
    "limit": {"type": "integer", "minimum": 1, "maximum": _MAX_LIST},
    "skip": {"type": "integer", "minimum": 0},
})
_RUN_ID_SCHEMA = _schema({"run_id": {"type": "integer", "minimum": 1}}, ["run_id"])
_CREATE_RUN_SCHEMA = _schema({
    "period_year": {"type": "integer", "minimum": 1900, "maximum": 2100},
    "period_month": {"type": "integer", "minimum": 1, "maximum": 12},
    "period_start": {"type": "string", "format": "date"},
    "convention": {"type": "string", "enum": ["from_ready_date", "next_month"]},
    "description": {"type": ["string", "null"], "maxLength": 500},
})


def register_mcp_fixed_assets_functions(registry) -> None:
    from app.services.ai.function_registry import AIFunction, AIRole

    roles = {AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN}
    empty = _schema({})
    include_inactive = _schema({"include_inactive": {"type": "boolean"}})

    registry.register(AIFunction(name="get_fixed_asset_settings", description="تنظیمات افزونه دارایی ثابت کسب‌وکار متصل. افزونه باید فعال باشد.", parameters_schema=empty, handler=get_fixed_asset_settings_handler, allowed_roles=roles, required_permissions=["fixed_assets.view"], category="accounting", is_readonly=True))
    registry.register(AIFunction(name="update_fixed_asset_settings", description="ویرایش قرارداد استهلاک، حساب‌ها و پیشوند پلاک دارایی ثابت. extra_info پذیرفته نمی‌شود. نیاز به تأیید.", parameters_schema=UPDATE_FIXED_ASSET_SETTINGS_SCHEMA, handler=update_fixed_asset_settings_handler, allowed_roles=roles, required_permissions=["fixed_assets.manage"], category="accounting", requires_approval=True, risk_level="high", is_readonly=False))
    registry.register(AIFunction(name="get_fixed_assets_dashboard", description="خلاصه تعداد و وضعیت دارایی‌های ثابت کسب‌وکار متصل.", parameters_schema=empty, handler=get_fixed_assets_dashboard_handler, allowed_roles=roles, required_permissions=["fixed_assets.view"], category="accounting", is_readonly=True))
    registry.register(AIFunction(name="list_fixed_asset_classes", description="فهرست طبقات دارایی ثابت (زمین، ساختمان، وسیله و …).", parameters_schema=include_inactive, handler=list_fixed_asset_classes_handler, allowed_roles=roles, required_permissions=["fixed_assets.view"], category="accounting", is_readonly=True))
    registry.register(AIFunction(name="update_fixed_asset_class", description="ویرایش نام، حساب‌ها و روش پیش‌فرض یک طبقه دارایی. نیاز به تأیید.", parameters_schema=_CLASS_UPDATE_SCHEMA, handler=update_fixed_asset_class_handler, allowed_roles=roles, required_permissions=["fixed_assets.manage"], category="accounting", requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="list_fixed_asset_locations", description="فهرست محل‌های استقرار دارایی.", parameters_schema=include_inactive, handler=list_fixed_asset_locations_handler, allowed_roles=roles, required_permissions=["fixed_assets.view"], category="accounting", is_readonly=True))
    registry.register(AIFunction(name="create_fixed_asset_location", description="ثبت محل استقرار دارایی. code و name الزامی است. نیاز به تأیید.", parameters_schema=_LOCATION_CREATE_SCHEMA, handler=create_fixed_asset_location_handler, allowed_roles=roles, required_permissions=["fixed_assets.manage"], category="accounting", requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="update_fixed_asset_location", description="ویرایش محل استقرار دارایی متعلق به کسب‌وکار متصل.", parameters_schema=_LOCATION_UPDATE_SCHEMA, handler=update_fixed_asset_location_handler, allowed_roles=roles, required_permissions=["fixed_assets.manage"], category="accounting", requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="list_fixed_assets", description="فهرست دارایی‌های ثابت کسب‌وکار متصل، حداکثر ۲۰۰ مورد در صفحه. فیلتر status/class_id/invoice_id/search.", parameters_schema=_LIST_ASSETS_SCHEMA, handler=list_fixed_assets_handler, allowed_roles=roles, required_permissions=["fixed_assets.view"], category="accounting", is_readonly=True))
    registry.register(AIFunction(name="get_fixed_asset", description="جزئیات یک دارایی ثابت متعلق به کسب‌وکار متصل.", parameters_schema=_ASSET_ID_SCHEMA, handler=get_fixed_asset_handler, allowed_roles=roles, required_permissions=["fixed_assets.view"], category="accounting", is_readonly=True))
    registry.register(AIFunction(name="create_fixed_asset", description="ثبت دارایی پیش‌نویس بدون فاکتور فروشنده (افتتاحیه یا تحصیل مستقل). برای خرید از فروشنده از create_invoice با سطر fixed_asset استفاده کن تا موجودی کالا بدهکار نشود. سرمایه‌گذاری مستقل با capitalize_fixed_asset. نیاز به تأیید.", parameters_schema=CREATE_FIXED_ASSET_SCHEMA, handler=create_fixed_asset_handler, allowed_roles=roles, required_permissions=["fixed_assets.operate"], category="accounting", requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="update_fixed_asset", description="ویرایش دارایی. پس از سرمایه‌گذاری فقط نام/محل/تحویل‌گیرنده و مشابه آن قابل تغییر است.", parameters_schema=_UPDATE_ASSET_SCHEMA, handler=update_fixed_asset_handler, allowed_roles=roles, required_permissions=["fixed_assets.operate"], category="accounting", requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="delete_fixed_asset", description="حذف دارایی پیش‌نویس سرمایه‌نشده. برگشت‌ناپذیر و نیازمند تأیید.", parameters_schema=_ASSET_ID_SCHEMA, handler=delete_fixed_asset_handler, allowed_roles=roles, required_permissions=["fixed_assets.operate"], category="accounting", requires_approval=True, risk_level="high", is_readonly=False))
    registry.register(AIFunction(name="capitalize_fixed_asset", description="سرمایه‌گذاری دارایی پیش‌نویس بدون فاکتور فروشنده و صدور سند تحصیل. دارایی ساخته‌شده از فاکتور خرید سرمایه‌ای را دوباره capitalize نکن. طرف حساب الزامی است. نیازمند تأیید.", parameters_schema=CAPITALIZE_FIXED_ASSET_SCHEMA, handler=capitalize_fixed_asset_handler, allowed_roles=roles, required_permissions=["fixed_assets.post"], category="accounting", requires_approval=True, risk_level="high", is_readonly=False))
    registry.register(AIFunction(name="set_fixed_asset_idle", description="قرار دادن دارایی سرمایه‌شده در رکود استهلاک.", parameters_schema=_IDLE_SCHEMA, handler=set_fixed_asset_idle_handler, allowed_roles=roles, required_permissions=["fixed_assets.operate"], category="accounting", requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="resume_fixed_asset", description="خروج دارایی از رکود و بازگشت به وضعیت سرمایه‌شده.", parameters_schema=_ASSET_ID_SCHEMA, handler=resume_fixed_asset_handler, allowed_roles=roles, required_permissions=["fixed_assets.operate"], category="accounting", requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="dispose_fixed_asset", description="خروج فروش یا اسقاط دارایی و صدور سند. نیازمند تأیید.", parameters_schema=DISPOSE_FIXED_ASSET_SCHEMA, handler=dispose_fixed_asset_handler, allowed_roles=roles, required_permissions=["fixed_assets.post"], category="accounting", requires_approval=True, risk_level="high", is_readonly=False))
    registry.register(AIFunction(name="post_fixed_asset_expenditure", description="ثبت مخارج بعدی routine یا major روی دارایی سرمایه‌شده. نیازمند تأیید.", parameters_schema=_EXPENDITURE_SCHEMA, handler=post_fixed_asset_expenditure_handler, allowed_roles=roles, required_permissions=["fixed_assets.post"], category="accounting", requires_approval=True, risk_level="high", is_readonly=False))
    registry.register(AIFunction(name="change_fixed_asset_estimate", description="تغییر برآورد عمر/نرخ/اسقاط دارایی سرمایه‌شده از تاریخ مؤثر.", parameters_schema=_ESTIMATE_SCHEMA, handler=change_fixed_asset_estimate_handler, allowed_roles=roles, required_permissions=["fixed_assets.manage"], category="accounting", requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="list_fixed_asset_depreciation_runs", description="فهرست اجرای استهلاک ماهانه.", parameters_schema=_RUN_LIST_SCHEMA, handler=list_fixed_asset_depreciation_runs_handler, allowed_roles=roles, required_permissions=["fixed_assets.view"], category="accounting", is_readonly=True))
    registry.register(AIFunction(name="get_fixed_asset_depreciation_run", description="جزئیات یک اجرای استهلاک شامل سطرها.", parameters_schema=_RUN_ID_SCHEMA, handler=get_fixed_asset_depreciation_run_handler, allowed_roles=roles, required_permissions=["fixed_assets.view"], category="accounting", is_readonly=True))
    registry.register(AIFunction(name="create_fixed_asset_depreciation_run", description="ایجاد پیش‌نویس استهلاک یک ماه میلادی. period_year+period_month یا period_start.", parameters_schema=_CREATE_RUN_SCHEMA, handler=create_fixed_asset_depreciation_run_handler, allowed_roles=roles, required_permissions=["fixed_assets.operate"], category="accounting", requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="post_fixed_asset_depreciation_run", description="ثبت قطعی اجرای استهلاک و صدور سند. نیازمند تأیید.", parameters_schema=_RUN_ID_SCHEMA, handler=post_fixed_asset_depreciation_run_handler, allowed_roles=roles, required_permissions=["fixed_assets.post"], category="accounting", requires_approval=True, risk_level="high", is_readonly=False))
    registry.register(AIFunction(name="delete_fixed_asset_depreciation_run", description="حذف پیش‌نویس اجرای استهلاک ثبت‌نشده. نیازمند تأیید.", parameters_schema=_RUN_ID_SCHEMA, handler=delete_fixed_asset_depreciation_run_handler, allowed_roles=roles, required_permissions=["fixed_assets.operate"], category="accounting", requires_approval=True, risk_level="high", is_readonly=False))
    registry.register(AIFunction(name="get_fixed_asset_report", description="گزارش اموال کسب‌وکار متصل: دفتر، گردش طبقات، استهلاک دوره، تحصیل، خروج، راکد، محل استقرار یا مخارج بعدی. برای گردش/استهلاک/تحصیل/خروج/مخارج from_date و to_date بفرست.", parameters_schema=GET_FIXED_ASSET_REPORT_SCHEMA, handler=get_fixed_asset_report_handler, allowed_roles=roles, required_permissions=["fixed_assets.view"], category="accounting", is_readonly=True))
