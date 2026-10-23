"""MCP lifecycle actions for checks. Every action is tenant-bound and accounting-gated."""
from __future__ import annotations

from typing import Any, Dict

from app.services.ai.function_registry import AIRole, AIFunction

_ROLES = {AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN}


def _schema(properties, required):
    return {"type": "object", "properties": properties, "required": required, "additionalProperties": False}


def register_mcp_check_action_functions(registry) -> None:
    common = {"document_date": {"type": "string", "format": "date"}, "description": {"type": "string", "maxLength": 500}}
    specs = [
        ("endorse_check", "واگذاری چک دریافتی به شخص دیگر؛ سند حسابداری ایجاد می‌شود.", {"target_person_id": {"type": "integer", "minimum": 1}, **common}, ["target_person_id"], "endorse"),
        ("clear_check", "وصول چک دریافتی به حساب بانکی؛ سند حسابداری ایجاد می‌شود.", {"bank_account_id": {"type": "integer", "minimum": 1}, **common}, ["bank_account_id"], "clear"),
        ("return_check", "عودت چک دریافتی از واگذارشونده یا به صادرکننده.", {"return_type": {"type": "string", "enum": ["from_endorsee", "to_drawer"]}, "target_person_id": {"type": "integer", "minimum": 1}, **common}, [], "return"),
        ("bounce_check", "ثبت برگشت چک و هزینه احتمالی.", {"bank_account_id": {"type": "integer", "minimum": 1}, "expense_account_id": {"type": "integer", "minimum": 1}, "expense_amount": {"type": "number", "exclusiveMinimum": 0}, **common}, [], "bounce"),
        ("pay_check", "پرداخت چک پرداختنی از حساب بانکی.", {"bank_account_id": {"type": "integer", "minimum": 1}, **common}, ["bank_account_id"], "pay"),
        ("deposit_check", "سپرده‌گذاری چک دریافتی برای وصول.", {"bank_account_id": {"type": "integer", "minimum": 1}, **common}, [], "deposit"),
    ]
    for name, description, props, required, action in specs:
        registry.register(AIFunction(name=name, description=description + " فقط برای چک متعلق به کسب‌وکار متصل و با دسترسی accounting.write. تأیید صریح لازم است.",
            parameters_schema=_schema({"check_id": {"type": "integer", "minimum": 1}, **props}, ["check_id", *required]),
            handler=lambda args, context, operation=action: _perform_action(operation, args, context),
            allowed_roles=_ROLES, required_permissions=["accounting.write"], category="checks",
            requires_approval=True, risk_level="high", is_readonly=False))

    registry.register(AIFunction(name="get_check_history", description="دریافت تاریخچه وضعیت و اسناد حسابداری مرتبط با چک کسب‌وکار متصل.",
        parameters_schema=_schema({"check_id": {"type": "integer", "minimum": 1}}, ["check_id"]),
        handler=_check_history, allowed_roles=_ROLES, required_permissions=["checks.view"], category="checks"))
    registry.register(AIFunction(name="calculate_checks_reconciliation", description="محاسبه راس چک‌ها بدون ذخیره‌سازی.",
        parameters_schema=_schema({"check_ids": {"type": "array", "minItems": 2, "maxItems": 100, "uniqueItems": True, "items": {"type": "integer", "minimum": 1}},
            "base_date": {"type": "string", "format": "date-time"}, "currency_id": {"type": ["integer", "null"], "minimum": 1}}, ["check_ids", "base_date"]),
        handler=_calculate_reconciliation, allowed_roles=_ROLES, required_permissions=["checks.view"], category="checks"))
    registry.register(AIFunction(name="create_checks_reconciliation", description="ایجاد جلسه راس‌گیری و ذخیره نتیجه برای حداقل دو چک.",
        parameters_schema=_schema({"name": {"type": "string", "minLength": 1, "maxLength": 255}, "check_ids": {"type": "array", "minItems": 2, "maxItems": 100, "uniqueItems": True, "items": {"type": "integer", "minimum": 1}},
            "base_date": {"type": "string", "format": "date-time"}, "description": {"type": ["string", "null"], "maxLength": 1000}}, ["name", "check_ids", "base_date"]),
        handler=_create_reconciliation, allowed_roles=_ROLES, required_permissions=["checks.write"], category="checks",
        requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="list_checks_reconciliations", description="فهرست جلسات راس‌گیری با صفحه‌بندی محدود.",
        parameters_schema=_schema({"search": {"type": "string", "maxLength": 200}, "take": {"type": "integer", "minimum": 1, "maximum": 100}, "skip": {"type": "integer", "minimum": 0}}, []),
        handler=_list_reconciliations, allowed_roles=_ROLES, required_permissions=["checks.view"], category="checks"))
    registry.register(AIFunction(name="get_checks_reconciliation", description="دریافت جزئیات جلسه راس‌گیری متعلق به کسب‌وکار متصل.",
        parameters_schema=_schema({"reconciliation_id": {"type": "integer", "minimum": 1}}, ["reconciliation_id"]),
        handler=_get_reconciliation, allowed_roles=_ROLES, required_permissions=["checks.view"], category="checks"))
    registry.register(AIFunction(name="delete_checks_reconciliation", description="حذف جلسه راس‌گیری متعلق به کسب‌وکار متصل.",
        parameters_schema=_schema({"reconciliation_id": {"type": "integer", "minimum": 1}}, ["reconciliation_id"]),
        handler=_delete_reconciliation, allowed_roles=_ROLES, required_permissions=["checks.write"], category="checks",
        requires_approval=True, risk_level="high", is_readonly=False))


def _perform_action(action: str, args: Dict[str, Any], context: Dict[str, Any]):
    from app.services import check_service
    db, business_id, ctx = context["db"], int(context["business_id"]), context["user_context"]
    check_id = int(args["check_id"])
    before = check_service.get_check_by_id(db, check_id)
    if not before or int(before.get("business_id") or 0) != business_id:
        raise ValueError("چک در کسب‌وکار متصل پیدا نشد")
    if not ctx.can_access_business(business_id):
        raise ValueError("به این کسب‌وکار دسترسی ندارید")
    if not ctx.has_any_permission("accounting", "write"):
        raise ValueError("برای گردش چک، دسترسی accounting.write لازم است")
    payload = {k: v for k, v in args.items() if k != "check_id"}
    handler = {
        "endorse": check_service.endorse_check,
        "clear": check_service.clear_check,
        "return": check_service.return_check,
        "bounce": check_service.bounce_check,
        "pay": check_service.pay_check,
        "deposit": check_service.deposit_check,
    }[action]
    return handler(db, check_id, ctx.get_user_id(), payload)


def _check_history(args, context):
    from app.services import check_service
    db, bid, ctx = context["db"], int(context["business_id"]), context["user_context"]
    check_id = int(args["check_id"])
    check = check_service.get_check_by_id(db, check_id)
    if not check or int(check.get("business_id") or 0) != bid or not ctx.can_access_business(bid):
        raise ValueError("چک در کسب‌وکار متصل پیدا نشد")
    return check_service.get_check_history_and_documents(db, check_id)


def _calculate_reconciliation(args, context):
    from app.services.check_reconciliation_service import calculate_checks_reconciliation
    return calculate_checks_reconciliation(context["db"], int(context["business_id"]), args["check_ids"], args["base_date"], args.get("currency_id"))


def _create_reconciliation(args, context):
    from app.services.check_reconciliation_service import create_reconciliation
    ctx, bid = context["user_context"], int(context["business_id"])
    if not ctx.can_access_business(bid):
        raise ValueError("به این کسب‌وکار دسترسی ندارید")
    return create_reconciliation(context["db"], bid, ctx.get_user_id(), args)


def _list_reconciliations(args, context):
    from app.services.check_reconciliation_service import list_reconciliations
    query = {"take": min(int(args.get("take", 20)), 100), "skip": int(args.get("skip", 0)), "sort_desc": True}
    if args.get("search"):
        query.update({"search": args["search"], "search_fields": ["name"]})
    return list_reconciliations(context["db"], int(context["business_id"]), query)


def _get_reconciliation(args, context):
    from app.services.check_reconciliation_service import get_reconciliation_by_id
    ctx, bid = context["user_context"], int(context["business_id"])
    item = get_reconciliation_by_id(context["db"], int(args["reconciliation_id"]))
    if not item or int(item.get("business_id") or 0) != bid or not ctx.can_access_business(bid):
        raise ValueError("جلسه راس‌گیری در کسب‌وکار متصل پیدا نشد")
    return item


def _delete_reconciliation(args, context):
    from app.services.check_reconciliation_service import delete_reconciliation, get_reconciliation_by_id
    ctx, bid = context["user_context"], int(context["business_id"])
    reconciliation_id = int(args["reconciliation_id"])
    item = get_reconciliation_by_id(context["db"], reconciliation_id)
    if not item or int(item.get("business_id") or 0) != bid or not ctx.can_access_business(bid):
        raise ValueError("جلسه راس‌گیری در کسب‌وکار متصل پیدا نشد")
    delete_reconciliation(context["db"], reconciliation_id)
    return {"reconciliation_id": reconciliation_id, "deleted": True}
