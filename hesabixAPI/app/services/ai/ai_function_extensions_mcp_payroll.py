"""Business-scoped MCP tools for payroll workflows."""
from __future__ import annotations

from typing import Any, Dict

from app.services.ai.function_registry import AIRole, AIFunction

_ROLES = {AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN}


def _schema(properties=None, required=()):
    return {"type": "object", "properties": properties or {}, "required": list(required), "additionalProperties": False}


def _register(registry, name, description, schema, handler, permission, *, write=False, high=False):
    registry.register(AIFunction(
        name=name, description=description, parameters_schema=schema, handler=handler,
        allowed_roles=_ROLES, required_permissions=[permission], category="payroll",
        requires_approval=bool(write), risk_level="high" if high else ("medium" if write else "safe"),
        is_readonly=not write,
    ))


def _service(method: str, *, module="payroll_service", call="standard"):
    def handler(args: Dict[str, Any], context: Dict[str, Any]):
        from importlib import import_module
        svc = import_module(f"app.services.{module}")
        fn = getattr(svc, method)
        db, business_id = context["db"], int(context["business_id"])
        uid = context["user_context"].get_user_id()
        if call == "standard":
            return fn(db, business_id)
        if call == "payload":
            return fn(db, business_id, args["payload"], user_id=uid)
        if call == "id":
            return fn(db, business_id, int(args["id"]))
        if call == "id_user":
            return fn(db, business_id, int(args["id"]), user_id=uid)
        if call == "update_id_payload":
            return fn(db, business_id, int(args["id"]), args["payload"], user_id=uid)
        if call == "list_employees":
            rows, total = fn(db, business_id, include_inactive=bool(args.get("include_inactive", False)),
                department_id=args.get("department_id"), limit=int(args.get("limit", 100)), skip=int(args.get("skip", 0)))
            return {"items": rows, "total": total}
        if call == "list_periods":
            rows, total = fn(db, business_id, limit=int(args.get("limit", 24)), skip=int(args.get("skip", 0)))
            return {"items": rows, "total": total}
        if call == "list_runs":
            rows, total = fn(db, business_id, status=args.get("status"), period_id=args.get("period_id"),
                limit=int(args.get("limit", 50)), skip=int(args.get("skip", 0)))
            return {"items": rows, "total": total}
        if call == "run_id":
            return fn(db, business_id, int(args["run_id"]))
        if call == "run_id_user":
            return fn(db, business_id, int(args["run_id"]), user_id=uid)
        if call == "run_id_payload":
            return fn(db, business_id, int(args["run_id"]), args.get("payload", {}), user_id=uid)
        if call == "run_payment":
            return fn(db, business_id, int(args["run_id"]), uid, int(args["payment_account_id"]))
        if call == "summary":
            return fn(db, business_id, period_id=args.get("period_id"), run_id=args.get("run_id"))
        if call == "employee_summary":
            return fn(db, business_id, period_id=args.get("period_id"), run_id=args.get("run_id"),
                limit=int(args.get("limit", 100)), skip=int(args.get("skip", 0)))
        if call == "period_overview":
            return fn(db, business_id, year=args.get("year"))
        raise ValueError("Payroll tool handler configuration is invalid")
    return handler


def _delete_handler(method: str, id_key="id"):
    def handler(args, context):
        from app.services import payroll_service as svc
        result = getattr(svc, method)(context["db"], int(context["business_id"]), int(args[id_key]),
            user_id=context["user_context"].get_user_id())
        return result if result is not None else {"deleted": True, id_key: int(args[id_key])}
    return handler


def _action(method: str, *, reason=False):
    def handler(args, context):
        from app.services import payroll_service as svc
        kwargs = {"user_id": context["user_context"].get_user_id()}
        if reason:
            kwargs["reason"] = args.get("reason")
        return getattr(svc, method)(context["db"], int(context["business_id"]), int(args["run_id"]), **kwargs)
    return handler


def register_mcp_payroll_functions(registry) -> None:
    id_schema = _schema({"id": {"type": "integer", "minimum": 1}}, ["id"])
    run_schema = _schema({"run_id": {"type": "integer", "minimum": 1}}, ["run_id"])
    report_schema = _schema({"period_id": {"type": ["integer", "null"], "minimum": 1},
        "run_id": {"type": ["integer", "null"], "minimum": 1}})
    _register(registry, "get_payroll_dashboard", "نمای کلی ماژول حقوق و دستمزد در کسب‌وکار متصل.", _schema(), _service("get_dashboard_summary"), "payroll.view")
    _register(registry, "get_payroll_settings", "خواندن تنظیمات حقوق و دستمزد کسب‌وکار.", _schema(), _service("get_settings"), "payroll.view")
    settings_payload = {"type": "object", "properties": {"enabled": {"type": "boolean"}, "document_code_format": {"type": "string", "maxLength": 20}, "document_code_prefix": {"type": "string", "maxLength": 16}, "calculation_mode": {"type": "string", "enum": ["manual", "semi_auto", "formula"]}, "require_approval": {"type": "boolean"}, "auto_post_on_finalize": {"type": "boolean"}, "allow_negative_net": {"type": "boolean"}, "round_amounts_to": {"type": "integer", "minimum": 0}, "wages_payable_account_id": {"type": ["integer", "null"], "minimum": 1}, "payroll_expense_account_id": {"type": ["integer", "null"], "minimum": 1}, "tax_payable_account_id": {"type": ["integer", "null"], "minimum": 1}, "insurance_payable_account_id": {"type": ["integer", "null"], "minimum": 1}, "default_currency_id": {"type": ["integer", "null"], "minimum": 1}, "payslip_template_json": {"type": ["object", "null"]}, "extra_settings": {"type": ["object", "null"]}}, "additionalProperties": False}
    _register(registry, "update_payroll_settings", "ویرایش تنظیمات حقوق و دستمزد، از جمله تأیید اجباری و ثبت خودکار در حسابداری؛ این انتخاب‌ها بر گردش مالی بعدی اثر دارند و نیازمند تأیید هستند.", _schema({"payload": settings_payload}, ["payload"]), _service("update_settings", call="payload"), "payroll.manage", write=True, high=True)
    _register(registry, "list_payroll_item_categories", "فهرست دسته‌بندی آیتم‌های حقوق.", _schema({"include_inactive": {"type": "boolean"}}),
        lambda a,c: {"items": __import__("app.services.payroll_service", fromlist=["list_item_categories"]).list_item_categories(c["db"], int(c["business_id"]), bool(a.get("include_inactive", False)))}, "payroll.view")
    _register(registry, "list_payroll_items", "فهرست اجزای حقوق، محاسبات و وضعیت فعال.", _schema({"item_kind": {"type": "string", "enum": ["earning", "deduction", "employer_cost", "informational"]}, "include_inactive": {"type": "boolean"}}),
        lambda a,c: {"items": __import__("app.services.payroll_service", fromlist=["list_item_definitions"]).list_item_definitions(c["db"], int(c["business_id"]), item_kind=a.get("item_kind"), include_inactive=bool(a.get("include_inactive", False)))}, "payroll.view")
    _register(registry, "list_payroll_departments", "فهرست بخش‌های سازمانی حقوق.", _schema({"include_inactive": {"type": "boolean"}}),
        lambda a,c: {"items": __import__("app.services.payroll_service", fromlist=["list_departments"]).list_departments(c["db"], int(c["business_id"]), include_inactive=bool(a.get("include_inactive", False)))}, "payroll.view")
    _register(registry, "list_payroll_employees", "فهرست پروفایل‌های پرسنلی با فیلتر بخش و صفحه‌بندی (حداکثر ۵۰۰).", _schema({"include_inactive": {"type": "boolean"}, "department_id": {"type": ["integer", "null"], "minimum": 1}, "limit": {"type": "integer", "minimum": 1, "maximum": 500}, "skip": {"type": "integer", "minimum": 0}}), _service("list_employees", call="list_employees"), "payroll.view")
    _register(registry, "list_payroll_periods", "فهرست دوره‌های حقوق (حداکثر ۱۲۰).", _schema({"limit": {"type": "integer", "minimum": 1, "maximum": 120}, "skip": {"type": "integer", "minimum": 0}}), _service("list_periods", call="list_periods"), "payroll.view")
    _register(registry, "list_payroll_runs", "فهرست اجراهای حقوق با فیلتر دوره/وضعیت (حداکثر ۲۰۰).", _schema({"status": {"type": "string", "enum": ["draft", "pending_approval", "finalized", "posted", "cancelled"]}, "period_id": {"type": ["integer", "null"], "minimum": 1}, "limit": {"type": "integer", "minimum": 1, "maximum": 200}, "skip": {"type": "integer", "minimum": 0}}), _service("list_runs", call="list_runs"), "payroll.view")
    _register(registry, "get_payroll_run", "جزئیات اجرای حقوق، ردیف‌های پرسنل و پیوند سندهای حسابداری.", run_schema, _service("get_run", call="run_id"), "payroll.view")
    for tool, method, module, call in [
        ("get_payroll_department_summary", "get_run_department_summary", "payroll_service", "summary"),
        ("get_payroll_item_summary", "get_item_summary_report", "payroll_reports", "summary"),
        ("get_payroll_employee_summary", "get_employee_summary_report", "payroll_reports", "employee_summary"),
        ("get_payroll_statutory_summary", "get_statutory_summary_report", "payroll_reports", "summary"),
    ]:
        _register(registry, tool, "گزارش حقوق بر اساس دوره یا اجرای مشخص؛ داده فقط از کسب‌وکار متصل خوانده می‌شود.",
            _schema({**report_schema["properties"], **({"limit": {"type": "integer", "minimum": 1, "maximum": 500}, "skip": {"type": "integer", "minimum": 0}} if call == "employee_summary" else {})}),
            _service(method, module=module, call=call), "payroll.view")
    _register(registry, "get_payroll_period_overview", "گزارش نمای کلی دوره‌های حقوق برای یک سال شمسی.", _schema({"year": {"type": ["integer", "null"], "minimum": 1300, "maximum": 1500}}), _service("get_period_overview_report", module="payroll_reports", call="period_overview"), "payroll.view")

    payload = {"type": "object", "properties": {"code": {"type": "string", "maxLength": 64}, "name": {"type": "string", "maxLength": 200}, "description": {"type": ["string", "null"]}, "item_kind": {"type": "string", "enum": ["earning", "deduction", "employer_cost", "informational"]}, "sort_order": {"type": "integer"}, "is_active": {"type": "boolean"}}, "additionalProperties": False}
    _register(registry, "create_payroll_item_category", "ساخت دسته آیتم حقوق؛ نیازمند تأیید.", _schema({"payload": payload}, ["payload"]), _service("create_item_category", call="payload"), "payroll.manage", write=True)
    _register(registry, "update_payroll_item_category", "ویرایش دسته آیتم حقوق؛ شناسه را از فهرست بگیر. نیازمند تأیید.", _schema({"id": {"type": "integer", "minimum": 1}, "payload": payload}, ["id", "payload"]), _service("update_item_category", call="update_id_payload"), "payroll.manage", write=True)
    _register(registry, "delete_payroll_item_category", "حذف دسته غیرسیستمی بدون آیتم وابسته؛ نیازمند تأیید.", id_schema, _delete_handler("delete_item_category"), "payroll.manage", write=True, high=True)
    item_payload = {"type": "object", "properties": {"category_id": {"type": ["integer", "null"], "minimum": 1}, "code": {"type": "string", "maxLength": 64}, "name": {"type": "string", "maxLength": 200}, "item_kind": {"type": "string", "enum": ["earning", "deduction", "employer_cost", "informational"]}, "account_id": {"type": ["integer", "null"], "minimum": 1}, "counter_account_id": {"type": ["integer", "null"], "minimum": 1}, "calculation_type": {"type": "string", "enum": ["manual", "fixed", "percent_of_base", "percent_of_gross", "formula", "statutory"]}, "default_amount": {"type": ["number", "null"]}, "percent_value": {"type": ["number", "null"]}, "formula_expression": {"type": ["string", "null"], "maxLength": 4000}, "affects_gross": {"type": "boolean"}, "affects_taxable": {"type": "boolean"}, "affects_insurance": {"type": "boolean"}, "is_taxable": {"type": "boolean"}, "is_insurable": {"type": "boolean"}, "show_on_payslip": {"type": "boolean"}, "sort_order": {"type": "integer"}, "is_active": {"type": "boolean"}, "extra_config": {"type": ["object", "null"]}}, "additionalProperties": False}
    _register(registry, "create_payroll_item", "تعریف جزء حقوق با نوع محاسبه و نگاشت حساب؛ فرمول فقط با expression معتبر و مورد تأیید ثبت شود. نیازمند تأیید.", _schema({"payload": item_payload}, ["payload"]), _service("create_item_definition", call="payload"), "payroll.manage", write=True, high=True)
    _register(registry, "update_payroll_item", "ویرایش تعریف جزء حقوق؛ شناسه را از list_payroll_items بگیر. نیازمند تأیید.", _schema({"id": {"type": "integer", "minimum": 1}, "payload": item_payload}, ["id", "payload"]), _service("update_item_definition", call="update_id_payload"), "payroll.manage", write=True, high=True)
    _register(registry, "delete_payroll_item", "حذف تعریف جزء حقوق در صورت نداشتن سوابق وابسته؛ نیازمند تأیید.", id_schema, _delete_handler("delete_item_definition"), "payroll.manage", write=True, high=True)
    dept_payload = {"type": "object", "properties": {"code": {"type": "string", "maxLength": 64}, "name": {"type": "string", "maxLength": 200}, "parent_id": {"type": ["integer", "null"], "minimum": 1}, "sort_order": {"type": "integer"}, "is_active": {"type": "boolean"}}, "additionalProperties": False}
    _register(registry, "create_payroll_department", "ساخت بخش سازمانی حقوق.", _schema({"payload": dept_payload}, ["payload"]), _service("create_department", call="payload"), "payroll.manage", write=True)
    _register(registry, "update_payroll_department", "ویرایش بخش سازمانی حقوق.", _schema({"id": {"type": "integer", "minimum": 1}, "payload": dept_payload}, ["id", "payload"]), _service("update_department", call="update_id_payload"), "payroll.manage", write=True)
    employee_payload = {"type": "object", "properties": {"person_id": {"type": "integer", "minimum": 1}, "department_id": {"type": ["integer", "null"], "minimum": 1}, "employee_code": {"type": "string", "maxLength": 64}, "job_title": {"type": ["string", "null"], "maxLength": 200}, "employment_type": {"type": "string", "enum": ["full_time", "part_time", "contract", "daily", "seasonal"]}, "hire_date": {"type": ["string", "null"], "format": "date"}, "termination_date": {"type": ["string", "null"], "format": "date"}, "base_salary": {"type": ["number", "null"], "minimum": 0}, "insurance_number": {"type": ["string", "null"]}, "tax_id": {"type": ["string", "null"]}, "bank_account_info": {"type": ["object", "null"]}, "is_active": {"type": "boolean"}, "extra_info": {"type": ["object", "null"]}}, "additionalProperties": False}
    _register(registry, "create_payroll_employee", "ساخت پروفایل حقوق برای شخصی که از قبل به‌عنوان کارمند ثبت شده است؛ برای داده بانکی و شناسه‌های مالیاتی از اطلاعات واقعی و مجاز استفاده کن. نیازمند تأیید.", _schema({"payload": employee_payload}, ["payload"]), _service("create_employee", call="payload"), "payroll.manage", write=True, high=True)
    update_employee_payload = {**employee_payload, "properties": {k:v for k,v in employee_payload["properties"].items() if k != "person_id"}}
    _register(registry, "update_payroll_employee", "ویرایش پروفایل حقوق پرسنل. نیازمند تأیید.", _schema({"id": {"type": "integer", "minimum": 1}, "payload": update_employee_payload}, ["id", "payload"]), _service("update_employee", call="update_id_payload"), "payroll.manage", write=True, high=True)
    period_payload = {"type": "object", "properties": {"year": {"type": "integer", "minimum": 1300, "maximum": 1500}, "month": {"type": "integer", "minimum": 1, "maximum": 12}, "title": {"type": "string", "maxLength": 120}, "start_date": {"type": ["string", "null"], "format": "date"}, "end_date": {"type": ["string", "null"], "format": "date"}}, "required": ["year", "month"], "additionalProperties": False}
    _register(registry, "create_payroll_period", "ایجاد دورهٔ حقوق شمسی. نیازمند تأیید.", _schema({"payload": period_payload}, ["payload"]), _service("create_period", call="payload"), "payroll.operate", write=True)
    _register(registry, "close_payroll_period", "بستن دورهٔ حقوق؛ پس از بستن دیگر اجرای جدید برای آن دوره ساخته نمی‌شود. نیازمند تأیید.", _schema({"period_id": {"type": "integer", "minimum": 1}}, ["period_id"]), lambda a,c: __import__("app.services.payroll_service", fromlist=["close_period"]).close_period(c["db"], int(c["business_id"]), int(a["period_id"]), user_id=c["user_context"].get_user_id()), "payroll.operate", write=True, high=True)

    line_item = {"type": "object", "properties": {"item_definition_id": {"type": "integer", "minimum": 1}, "amount": {"type": "number"}}, "required": ["item_definition_id", "amount"], "additionalProperties": False}
    line = {"type": "object", "properties": {"employee_id": {"type": "integer", "minimum": 1}, "notes": {"type": ["string", "null"], "maxLength": 2000}, "items": {"type": "array", "maxItems": 100, "items": line_item}}, "required": ["employee_id"], "additionalProperties": False}
    run_payload = {"type": "object", "properties": {"period_id": {"type": ["integer", "null"], "minimum": 1}, "code": {"type": "string", "maxLength": 64}, "title": {"type": "string", "maxLength": 200}, "run_date": {"type": "string", "format": "date"}, "description": {"type": ["string", "null"], "maxLength": 2000}, "employee_ids": {"type": "array", "maxItems": 500, "uniqueItems": True, "items": {"type": "integer", "minimum": 1}}, "lines": {"type": "array", "minItems": 1, "maxItems": 500, "items": line}}, "additionalProperties": False}
    _register(registry, "create_payroll_run", "ساخت پیش‌نویس اجرای حقوق برای حداکثر ۵۰۰ کارمند. مبلغ هر آیتم فقط با شناسه تعریف‌شده تعیین می‌شود؛ این ابزار سند را قطعی یا پرداخت نمی‌کند. نیازمند تأیید.", _schema({"payload": run_payload}, ["payload"]), _service("create_run", call="payload"), "payroll.operate", write=True, high=True)
    update_run_payload = {"type": "object", "properties": {k:v for k,v in run_payload["properties"].items() if k not in ("employee_ids", "code")}, "additionalProperties": False}
    _register(registry, "update_payroll_run", "ویرایش پیش‌نویس حقوق؛ خطوطی که ارسال شوند جایگزین کامل خطوط قبلی می‌شوند. نیازمند تأیید.", _schema({"run_id": {"type": "integer", "minimum": 1}, "payload": update_run_payload}, ["run_id", "payload"]), _service("update_run", call="run_id_payload"), "payroll.operate", write=True, high=True)
    _register(registry, "delete_payroll_run", "حذف اجرای حقوق در وضعیت پیش‌نویس. نیازمند تأیید.", run_schema, _delete_handler("delete_run", "run_id"), "payroll.operate", write=True, high=True)
    for tool, method, perm, desc in [
        ("finalize_payroll_run", "finalize_run", "payroll.operate", "نهایی‌سازی پیش‌نویس؛ ممکن است طبق تنظیمات کسب‌وکار وارد تأیید یا ثبت خودکار شود."),
        ("cancel_payroll_run", "cancel_run", "payroll.operate", "لغو اجرای حقوق؛ نیازمند تأیید."),
        ("approve_payroll_run", "approve_run", "payroll.approve", "تأیید اجرای حقوق؛ ممکن است طبق تنظیمات کسب‌وکار سند حسابداری خودکار بسازد."),
    ]:
        _register(registry, tool, desc + " نیازمند تأیید.", run_schema, _action(method), perm, write=True, high=True)
    _register(registry, "reject_payroll_run", "رد اجرای حقوق در انتظار تأیید؛ وضعیت آن به پیش‌نویس برمی‌گردد. نیازمند تأیید.", _schema({"run_id": {"type": "integer", "minimum": 1}, "reason": {"type": "string", "maxLength": 2000}}, ["run_id"]), _action("reject_run", reason=True), "payroll.approve", write=True, high=True)
    _register(registry, "copy_payroll_run", "کپی اجرای حقوق به پیش‌نویس جدید؛ شناسه دوره مقصد اختیاری است. نیازمند تأیید.", _schema({"run_id": {"type": "integer", "minimum": 1}, "payload": {"type": "object", "properties": {"period_id": {"type": ["integer", "null"], "minimum": 1}, "title": {"type": "string", "maxLength": 200}, "run_date": {"type": "string", "format": "date"}}, "additionalProperties": False}} , ["run_id"]), _service("copy_run", call="run_id_payload"), "payroll.operate", write=True, high=True)
    _register(registry, "post_payroll_run_to_accounting", "ثبت سند حقوق قطعی‌شده در حسابداری؛ عملیات مالی پرخطر و نیازمند تأیید.", run_schema, _service("post_run_to_accounting", call="run_id_user"), "payroll.post", write=True, high=True)
    _register(registry, "post_payroll_run_payment", "ثبت پرداخت اجرای حقوق ثبت‌شده از حساب بانکی/صندوق مجاز؛ payment_account_id را از ابزار حساب‌های پرداخت بگیر. نیازمند تأیید.", _schema({"run_id": {"type": "integer", "minimum": 1}, "payment_account_id": {"type": "integer", "minimum": 1}}, ["run_id", "payment_account_id"]), _service("post_run_payment", call="run_payment"), "payroll.post", write=True, high=True)
