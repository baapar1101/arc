"""MCP tools for CRM notes, tags, close reasons, and custom-field definitions."""
from __future__ import annotations

from datetime import date, datetime
from typing import Any, Dict

from app.services.ai.function_registry import AIRole, AIFunction


_ROLES = {AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN}


def _obj(properties: Dict[str, Any], required: list[str]) -> Dict[str, Any]:
    return {"type": "object", "properties": properties, "required": required, "additionalProperties": False}


def _register(registry, name, description, schema, handler, *, write=False, high=False):
    registry.register(AIFunction(
        name=name,
        description=description,
        parameters_schema=schema,
        handler=handler,
        allowed_roles=_ROLES,
        required_permissions=["crm.write" if write else "crm.view"],
        category="crm",
        requires_approval=bool(write),
        risk_level="high" if high else ("medium" if write else "safe"),
        is_readonly=not write,
    ))


def register_mcp_crm_meta_functions(registry) -> None:
    def lang(user_context):
        return getattr(user_context, "language", None) or "fa"

    # Process and stage management are tenant-scoped; deletes enforce the same in-use guards as REST.
    _register(registry, "list_crm_process_definitions", "فهرست فرایندها و مراحل CRM با فیلتر اختیاری.",
        _obj({"process_type": {"type": "string", "enum": ["lead_funnel", "sales_pipeline", "activity_type", "lead_source"]}, "is_active": {"type": "boolean"}}, []), lambda a, c: _process_list(a, c))
    _register(registry, "get_crm_process_definition", "دریافت جزئیات فرایند CRM و مراحل آن.", _obj({"definition_id": {"type": "integer", "minimum": 1}}, ["definition_id"]), lambda a, c: _process_get(a, c))
    _register(registry, "create_crm_process_definition", "ایجاد فرایند CRM همراه با مراحل اختیاری.",
        _obj({"process_type": {"type": "string", "enum": ["lead_funnel", "sales_pipeline", "activity_type", "lead_source"]}, "code": {"type": "string", "minLength": 1, "maxLength": 50}, "name": {"type": "string", "minLength": 1, "maxLength": 255}, "description": {"type": ["string", "null"]}, "is_default": {"type": "boolean"}, "is_active": {"type": "boolean"}, "stages": {"type": "array", "maxItems": 100, "items": {"type": "object", "properties": {"stage_code": {"type": "string", "minLength": 1, "maxLength": 50}, "name": {"type": "string", "minLength": 1, "maxLength": 255}, "order_index": {"type": "integer", "minimum": 0}, "color": {"type": ["string", "null"], "maxLength": 20}, "is_win": {"type": "boolean"}, "is_lost": {"type": "boolean"}, "allow_transition_to": {"type": ["array", "null"], "items": {"type": "string"}}}, "required": ["stage_code", "name"], "additionalProperties": False}}}, ["process_type", "code", "name"]), lambda a, c: _process_mutation("create", a, c), write=True)
    _register(registry, "update_crm_process_definition", "ویرایش مشخصات فرایند CRM.", _obj({"definition_id": {"type": "integer", "minimum": 1}, "name": {"type": "string", "minLength": 1, "maxLength": 255}, "description": {"type": ["string", "null"]}, "is_default": {"type": "boolean"}, "is_active": {"type": "boolean"}}, ["definition_id"]), lambda a, c: _process_mutation("update", a, c), write=True)
    _register(registry, "delete_crm_process_definition", "حذف فرایند CRM فقط در صورت استفاده‌نشدن در سرنخ یا فرصت.", _obj({"definition_id": {"type": "integer", "minimum": 1}}, ["definition_id"]), lambda a, c: _process_mutation("delete", a, c), write=True, high=True)
    _register(registry, "list_crm_process_stages", "فهرست مراحل یک فرایند CRM.", _obj({"definition_id": {"type": "integer", "minimum": 1}}, ["definition_id"]), lambda a, c: _stage_list(a, c))
    _register(registry, "create_crm_process_stage", "افزودن مرحله به فرایند CRM.", _stage_schema("create"), lambda a, c: _stage_mutation("create", a, c), write=True)
    _register(registry, "update_crm_process_stage", "ویرایش مرحله CRM.", _stage_schema("update"), lambda a, c: _stage_mutation("update", a, c), write=True)
    _register(registry, "delete_crm_process_stage", "حذف مرحله فقط در صورت استفاده‌نشدن در سرنخ یا فرصت.", _obj({"definition_id": {"type": "integer", "minimum": 1}, "stage_id": {"type": "integer", "minimum": 1}}, ["definition_id", "stage_id"]), lambda a, c: _stage_mutation("delete", a, c), write=True, high=True)
    _register(registry, "get_crm_lead_history", "دریافت تاریخچه تغییرات یک سرنخ (حداکثر ۲۰۰ رویداد).", _obj({"lead_id": {"type": "integer", "minimum": 1}, "limit": {"type": "integer", "minimum": 1, "maximum": 200}}, ["lead_id"]), lambda a, c: _history("lead", a, c))
    _register(registry, "get_crm_deal_history", "دریافت تاریخچه تغییرات یک فرصت (حداکثر ۲۰۰ رویداد).", _obj({"deal_id": {"type": "integer", "minimum": 1}, "limit": {"type": "integer", "minimum": 1, "maximum": 200}}, ["deal_id"]), lambda a, c: _history("deal", a, c))
    _register(registry, "get_crm_customer_360", "دریافت نمای ۳۶۰ درجه مشتری در حوزه CRM کسب‌وکار متصل.", _obj({"person_id": {"type": "integer", "minimum": 1}}, ["person_id"]), lambda a, c: _customer_360(a, c))
    _register(registry, "get_crm_my_work_queue", "دریافت صف کاری کاربر احراز‌شده: وظایف و پیگیری‌های سررسیدشده/۲۴ ساعت آینده.", _obj({}, []), lambda a, c: _work_queue(c))
    _register(registry, "get_crm_follow_ups", "فهرست پیگیری‌های امروز تا حداکثر ۳۰ روز آینده؛ داده‌های تخصیص‌نیافته و موارد تخصیص‌یافته به خود کاربر را نشان می‌دهد مگر اینکه مالک/مدیر باشد.", _obj({"days_ahead": {"type": "integer", "minimum": 0, "maximum": 30}}, []), lambda a, c: _follow_ups(a, c))
    _register(registry, "get_crm_pipeline_report", "تعداد و مبلغ فرصت‌ها به تفکیک مرحله؛ بازه تاریخ بر اساس زمان ایجاد فرصت است.", _obj({"process_definition_id": {"type": "integer", "minimum": 1}, "from_date": {"type": "string", "format": "date"}, "to_date": {"type": "string", "format": "date"}}, []), lambda a, c: _pipeline_report(a, c))
    _register(registry, "get_crm_lead_sources_report", "تعداد سرنخ‌ها به تفکیک منبع.", _obj({}, []), lambda a, c: _lead_sources_report(c))
    _register(registry, "get_crm_weighted_forecast", "مبلغ فرصت‌های باز و پیش‌بینی موزون بر اساس درصد احتمال موفقیت.", _obj({"process_definition_id": {"type": "integer", "minimum": 1}}, []), lambda a, c: _weighted_forecast(a, c))
    _register(registry, "get_crm_sales_trend", "روند روزانه یا ماهانه مبلغ/تعداد فرصت‌های بسته‌شده در بازه محدود.", _obj({"period": {"type": "string", "enum": ["day", "week", "month"]}, "months": {"type": "integer", "minimum": 1, "maximum": 24}}, []), lambda a, c: _sales_trend(a, c))
    _register(registry, "get_crm_employee_performance", "مقایسه عملکرد اعضا در CRM؛ اگر کاربر مجوز گزارش تیم نداشته باشد فقط آمار خودش برمی‌گردد.", _obj({}, []), lambda a, c: _employee_performance(c))
    _register(registry, "get_crm_lost_reasons_report", "تعداد و مبلغ فرصت‌ها به تفکیک دلیل باخت.", _obj({}, []), lambda a, c: _close_reason_report("lost", c))
    _register(registry, "get_crm_won_reasons_report", "تعداد و مبلغ فرصت‌ها به تفکیک دلیل برد.", _obj({}, []), lambda a, c: _close_reason_report("won", c))

    # Notes and their comments. The domain service owns visibility and ACL checks.
    _register(registry, "list_crm_note_types", "فهرست انواع فعال یادداشت CRM برای کسب‌وکار متصل.",
        _obj({}, []), lambda a, c: _list_note_types(c, lang(c["user_context"])))
    _register(registry, "create_crm_note_type", "ایجاد نوع یادداشت CRM برای کسب‌وکار متصل.",
        _obj({"code": {"type": "string", "minLength": 1, "maxLength": 50}, "title_i18n": {"type": "object", "additionalProperties": {"type": "string"}}, "scheduling_mode": {"type": "string", "enum": ["day_only", "meeting"]}, "allow_comments": {"type": "boolean"}, "sort_order": {"type": "integer", "minimum": 0}}, ["code", "title_i18n"]), lambda a, c: _note_type_mutation("create", a, c), write=True)
    _register(registry, "update_crm_note_type", "ویرایش نوع یادداشت CRM؛ نوع‌های سیستمی را حذف نکنید.",
        _obj({"type_id": {"type": "integer", "minimum": 1}, "title_i18n": {"type": "object", "additionalProperties": {"type": "string"}}, "scheduling_mode": {"type": "string", "enum": ["day_only", "meeting"]}, "allow_comments": {"type": "boolean"}, "is_active": {"type": "boolean"}, "sort_order": {"type": "integer", "minimum": 0}}, ["type_id"]), lambda a, c: _note_type_mutation("update", a, c), write=True)
    _register(registry, "delete_crm_note_type", "حذف نوع یادداشت غیرسیستمی CRM در صورت مجاز بودن توسط سرویس دامنه.",
        _obj({"type_id": {"type": "integer", "minimum": 1}}, ["type_id"]), lambda a, c: _note_type_mutation("delete", a, c), write=True, high=True)

    _register(registry, "list_crm_notes", "فهرست یادداشت‌های قابل‌مشاهده کاربر در یک بازه حداکثر ۳۶۶ روزه؛ تاریخ‌ها ISO (YYYY-MM-DD) هستند.",
        _obj({"from_date": {"type": "string", "format": "date"}, "to_date": {"type": "string", "format": "date"}}, ["from_date", "to_date"]),
        lambda a, c: _list_notes(a, c))

    _register(registry, "get_crm_note", "دریافت یادداشت CRM در صورت داشتن دسترسی مشاهده.",
        _obj({"note_id": {"type": "integer", "minimum": 1}}, ["note_id"]),
        lambda a, c: _get_note(a, c))

    _register(registry, "create_crm_note", "ایجاد یادداشت یا رویداد تقویمی CRM. برای نوع meeting مقدار starts_at الزامی است؛ برای day_only مقدار occurs_on الزامی است.",
        _obj({
            "note_type_id": {"type": "integer", "minimum": 1},
            "visibility": {"type": "string", "enum": ["private", "business_public", "shared"]},
            "title": {"type": ["string", "null"], "maxLength": 255}, "body": {"type": "string", "minLength": 1},
            "occurs_on": {"type": ["string", "null"], "format": "date"},
            "starts_at": {"type": ["string", "null"], "format": "date-time"}, "ends_at": {"type": ["string", "null"], "format": "date-time"},
            "lead_id": {"type": ["integer", "null"], "minimum": 1},
            "shared_user_ids": {"type": ["array", "null"], "maxItems": 100, "items": {"type": "integer", "minimum": 1}},
        }, ["note_type_id", "visibility", "body"]), lambda a, c: _create_note(a, c), write=True)

    _register(registry, "update_crm_note", "ویرایش یادداشت CRM؛ فقط فیلدهای ارسال‌شده تغییر می‌کنند. حذف پیوند سرنخ را با clear_lead=true انجام دهید.",
        _obj({
            "note_id": {"type": "integer", "minimum": 1}, "note_type_id": {"type": "integer", "minimum": 1},
            "visibility": {"type": "string", "enum": ["private", "business_public", "shared"]}, "title": {"type": ["string", "null"], "maxLength": 255},
            "body": {"type": "string", "minLength": 1}, "occurs_on": {"type": ["string", "null"], "format": "date"},
            "starts_at": {"type": ["string", "null"], "format": "date-time"}, "ends_at": {"type": ["string", "null"], "format": "date-time"},
            "lead_id": {"type": ["integer", "null"], "minimum": 1}, "clear_lead": {"type": "boolean"},
            "status": {"type": "string", "enum": ["active", "archived", "cancelled"]},
            "shared_user_ids": {"type": "array", "maxItems": 100, "items": {"type": "integer", "minimum": 1}},
        }, ["note_id"]), lambda a, c: _update_note(a, c), write=True)

    _register(registry, "delete_crm_note", "حذف نرم یادداشت CRM؛ دسترسی مالکیت/ACL توسط سرویس دامنه بررسی می‌شود.",
        _obj({"note_id": {"type": "integer", "minimum": 1}}, ["note_id"]), lambda a, c: _delete_note(a, c), write=True, high=True)

    _register(registry, "list_crm_note_comments", "فهرست نظرهای قابل‌مشاهده برای یادداشت عمومی CRM.",
        _obj({"note_id": {"type": "integer", "minimum": 1}}, ["note_id"]), lambda a, c: _note_comments(a, c))

    _register(registry, "add_crm_note_comment", "افزودن نظر به یادداشت عمومی در صورت مجاز بودن نظرها.",
        _obj({"note_id": {"type": "integer", "minimum": 1}, "body": {"type": "string", "minLength": 1, "maxLength": 10000}}, ["note_id", "body"]), lambda a, c: _add_note_comment(a, c), write=True)

    _register(registry, "delete_crm_note_comment", "حذف نظر خود کاربر؛ حذف نظر دیگران فقط برای مالک کسب‌وکار/مدیر سیستم.",
        _obj({"note_id": {"type": "integer", "minimum": 1}, "comment_id": {"type": "integer", "minimum": 1}}, ["note_id", "comment_id"]), lambda a, c: _delete_note_comment(a, c), write=True, high=True)
    _register(registry, "get_crm_note_audit", "دریافت حداکثر ۲۰۰ رویداد سابقهٔ یک یادداشت، در صورت داشتن دسترسی.",
        _obj({"note_id": {"type": "integer", "minimum": 1}}, ["note_id"]), lambda a, c: _note_audit(a, c))

    # CRM metadata that drives tagging, closure, and custom fields.
    _register(registry, "list_crm_tags", "فهرست برچسب‌های CRM کسب‌وکار متصل.", _obj({}, []), lambda a, c: _list_tags(c))
    _register(registry, "create_crm_tag", "ایجاد برچسب CRM.", _obj({"name": {"type": "string", "minLength": 1, "maxLength": 100}, "color": {"type": ["string", "null"], "maxLength": 32}, "sort_order": {"type": "integer", "minimum": 0}}, ["name"]), lambda a, c: _tag_mutation("create", a, c), write=True)
    _register(registry, "update_crm_tag", "ویرایش نام، رنگ، وضعیت فعال یا ترتیب یک برچسب CRM.", _obj({"tag_id": {"type": "integer", "minimum": 1}, "name": {"type": "string", "minLength": 1, "maxLength": 100}, "color": {"type": "string", "maxLength": 32}, "is_active": {"type": "boolean"}, "sort_order": {"type": "integer", "minimum": 0}}, ["tag_id"]), lambda a, c: _tag_mutation("update", a, c), write=True)
    _register(registry, "delete_crm_tag", "حذف برچسب CRM و رابطه‌های وابسته طبق قیدهای دامنه.", _obj({"tag_id": {"type": "integer", "minimum": 1}}, ["tag_id"]), lambda a, c: _tag_mutation("delete", a, c), write=True, high=True)
    _register(registry, "set_crm_lead_tags", "جایگزینی کامل برچسب‌های سرنخ؛ آرایه خالی همه برچسب‌ها را پاک می‌کند.", _obj({"lead_id": {"type": "integer", "minimum": 1}, "tag_ids": {"type": "array", "maxItems": 100, "uniqueItems": True, "items": {"type": "integer", "minimum": 1}}}, ["lead_id", "tag_ids"]), lambda a, c: _set_tags("lead", a, c), write=True)
    _register(registry, "set_crm_deal_tags", "جایگزینی کامل برچسب‌های فرصت فروش؛ آرایه خالی همه برچسب‌ها را پاک می‌کند.", _obj({"deal_id": {"type": "integer", "minimum": 1}, "tag_ids": {"type": "array", "maxItems": 100, "uniqueItems": True, "items": {"type": "integer", "minimum": 1}}}, ["deal_id", "tag_ids"]), lambda a, c: _set_tags("deal", a, c), write=True)

    _register(registry, "list_crm_close_reasons", "فهرست دلایل فعال/همه دلایل برد و باخت CRM.", _obj({"reason_type": {"type": "string", "enum": ["won", "lost"]}, "active_only": {"type": "boolean"}}, []), lambda a, c: _list_reasons(a, c))
    _register(registry, "create_crm_close_reason", "ایجاد دلیل برد یا باخت CRM.", _obj({"reason_type": {"type": "string", "enum": ["won", "lost"]}, "code": {"type": "string", "minLength": 1, "maxLength": 50}, "name": {"type": "string", "minLength": 1, "maxLength": 255}, "sort_order": {"type": "integer", "minimum": 0}}, ["reason_type", "code", "name"]), lambda a, c: _reason_mutation("create", a, c), write=True)
    _register(registry, "update_crm_close_reason", "ویرایش عنوان، وضعیت فعال یا ترتیب دلیل بستن CRM.", _obj({"reason_id": {"type": "integer", "minimum": 1}, "name": {"type": "string", "minLength": 1, "maxLength": 255}, "is_active": {"type": "boolean"}, "sort_order": {"type": "integer", "minimum": 0}}, ["reason_id"]), lambda a, c: _reason_mutation("update", a, c), write=True)
    _register(registry, "delete_crm_close_reason", "حذف دلیل بستن CRM.", _obj({"reason_id": {"type": "integer", "minimum": 1}}, ["reason_id"]), lambda a, c: _reason_mutation("delete", a, c), write=True, high=True)

    _register(registry, "list_crm_custom_fields", "فهرست تعریف فیلدهای سفارشی CRM.", _obj({"entity_type": {"type": "string", "enum": ["lead", "deal", "activity"]}, "active_only": {"type": "boolean"}}, []), lambda a, c: _list_fields(a, c))
    _register(registry, "create_crm_custom_field", "تعریف فیلد سفارشی برای سرنخ، فرصت فروش یا فعالیت. برای select گزینه‌ها لازم است.", _obj({"entity_type": {"type": "string", "enum": ["lead", "deal", "activity"]}, "field_key": {"type": "string", "minLength": 1, "maxLength": 100}, "label": {"type": "string", "minLength": 1, "maxLength": 255}, "field_type": {"type": "string", "enum": ["text", "number", "date", "select", "boolean"]}, "options": {"type": ["array", "null"], "maxItems": 100, "items": {}}, "is_required": {"type": "boolean"}, "sort_order": {"type": "integer", "minimum": 0}}, ["entity_type", "field_key", "label", "field_type"]), lambda a, c: _field_mutation("create", a, c), write=True)
    _register(registry, "update_crm_custom_field", "ویرایش برچسب، گزینه‌ها، اجباری‌بودن، ترتیب یا وضعیت فیلد سفارشی CRM.", _obj({"field_id": {"type": "integer", "minimum": 1}, "label": {"type": "string", "minLength": 1, "maxLength": 255}, "options": {"type": "array", "maxItems": 100, "items": {}}, "is_required": {"type": "boolean"}, "sort_order": {"type": "integer", "minimum": 0}, "is_active": {"type": "boolean"}}, ["field_id"]), lambda a, c: _field_mutation("update", a, c), write=True)
    _register(registry, "delete_crm_custom_field", "حذف تعریف فیلد سفارشی CRM.", _obj({"field_id": {"type": "integer", "minimum": 1}}, ["field_id"]), lambda a, c: _field_mutation("delete", a, c), write=True, high=True)


def _list_notes(args, context):
    db, bid, user = context["db"], int(context["business_id"]), context["user_context"]
    start, end = date.fromisoformat(args["from_date"]), date.fromisoformat(args["to_date"])
    if end < start or (end - start).days > 366:
        raise ValueError("بازه تاریخ باید معتبر و حداکثر ۳۶۶ روز باشد")
    from app.services import crm_calendar_note_service as svc
    return svc.list_notes(db, user, bid, start, end, getattr(user, "language", None) or "fa")


def _list_note_types(context, language):
    from app.services import crm_calendar_note_service as svc
    db, bid = context["db"], int(context["business_id"])
    items = svc.list_note_types(db, bid, language)
    db.commit()
    return items


def _get_note(args, context):
    from app.services import crm_calendar_note_service as svc
    db, bid, user = context["db"], int(context["business_id"]), context["user_context"]
    item = svc.get_note(db, user, bid, int(args["note_id"]), getattr(user, "language", None) or "fa")
    if item is None:
        raise ValueError("یادداشت پیدا نشد یا دسترسی مشاهده ندارید")
    return item


def _note_type_mutation(action, args, context):
    from app.services import crm_calendar_note_service as svc
    db, bid = context["db"], int(context["business_id"])
    language = getattr(context["user_context"], "language", None) or "fa"
    if action == "create":
        item = svc.create_note_type(db, bid, code=args["code"], title_i18n=args["title_i18n"],
            scheduling_mode=args.get("scheduling_mode", "day_only"), allow_comments=bool(args.get("allow_comments", True)),
            sort_order=int(args.get("sort_order", 0)), lang=language, translator=None)
    elif action == "update":
        values = {k: args.get(k) for k in ("title_i18n", "scheduling_mode", "allow_comments", "is_active", "sort_order")}
        item = svc.update_note_type(db, bid, int(args["type_id"]), **values, lang=language, translator=None)
    else:
        svc.delete_note_type(db, bid, int(args["type_id"]), None)
        item = {"type_id": int(args["type_id"]), "deleted": True}
    db.commit()
    return item


def _note_audit(args, context):
    from app.services import crm_calendar_note_service as svc
    return svc.list_audit(context["db"], context["user_context"], int(context["business_id"]), int(args["note_id"]))


def _create_note(args, context):
    from app.services import crm_calendar_note_service as svc
    db, bid, user = context["db"], int(context["business_id"]), context["user_context"]
    data = {
        "note_type_id": int(args["note_type_id"]),
        "visibility": args["visibility"],
        "title": args.get("title"),
        "body": args["body"],
        "occurs_on": args.get("occurs_on"),
        "starts_at": args.get("starts_at"),
        "ends_at": args.get("ends_at"),
        "lead_id": args.get("lead_id"),
        "shared_user_ids": args.get("shared_user_ids"),
    }
    data["occurs_on"] = date.fromisoformat(data["occurs_on"]) if data.get("occurs_on") else None
    for key in ("starts_at", "ends_at"):
        data[key] = datetime.fromisoformat(data[key].replace("Z", "+00:00")) if data.get(key) else None
    row = svc.create_note(db, user, bid, **data, translator=None)
    result = svc.get_note(db, user, bid, int(row.id), getattr(user, "language", None) or "fa")
    db.commit()
    return result


def _update_note(args, context):
    from app.services import crm_calendar_note_service as svc
    db, bid, user = context["db"], int(context["business_id"]), context["user_context"]
    data = dict(args)
    note_id = int(data.pop("note_id"))
    clear_lead = bool(data.pop("clear_lead", False))
    lead_field_set = clear_lead or "lead_id" in data
    if clear_lead:
        data["lead_id"] = None
    for key in ("occurs_on",):
        if data.get(key) is not None:
            data[key] = date.fromisoformat(data[key])
    for key in ("starts_at", "ends_at"):
        if data.get(key) is not None:
            data[key] = datetime.fromisoformat(data[key].replace("Z", "+00:00"))
    allowed = {"note_type_id", "visibility", "title", "body", "occurs_on", "starts_at", "ends_at", "lead_id", "status", "shared_user_ids"}
    values = {key: data.get(key) for key in allowed}
    values["lead_field_set"] = lead_field_set
    row = svc.update_note(db, user, bid, note_id, **values, translator=None)
    result = svc.get_note(db, user, bid, note_id, getattr(user, "language", None) or "fa")
    db.commit()
    return result or {"id": row.id, "updated": True}


def _delete_note(args, context):
    from app.services import crm_calendar_note_service as svc
    db, bid, user = context["db"], int(context["business_id"]), context["user_context"]
    note_id = int(args["note_id"])
    svc.soft_delete_note(db, user, bid, note_id, None)
    db.commit()
    return {"note_id": note_id, "deleted": True}


def _note_comments(args, context):
    from app.services import crm_calendar_note_service as svc
    db, bid, user = context["db"], int(context["business_id"]), context["user_context"]
    return svc.list_comments(db, user, bid, int(args["note_id"]), getattr(user, "language", None) or "fa")


def _add_note_comment(args, context):
    from app.services import crm_calendar_note_service as svc
    db, bid, user = context["db"], int(context["business_id"]), context["user_context"]
    item = svc.add_comment(db, user, bid, int(args["note_id"]), args["body"], None)
    db.commit()
    return item


def _delete_note_comment(args, context):
    from app.services import crm_calendar_note_service as svc
    db, bid, user = context["db"], int(context["business_id"]), context["user_context"]
    svc.delete_comment(db, user, bid, int(args["note_id"]), int(args["comment_id"]), None)
    db.commit()
    return {"comment_id": int(args["comment_id"]), "deleted": True}


def _list_tags(context):
    from app.services import crm_tag_service as svc
    db, bid = context["db"], int(context["business_id"])
    return svc.list_tags(db, bid, seed_defaults=False)


def _tag_mutation(action, args, context):
    from app.services import crm_tag_service as svc
    db, bid = context["db"], int(context["business_id"])
    values = {k: v for k, v in args.items() if k != "tag_id"}
    if action == "create":
        row = svc.create_tag(db, bid, **values)
        result = svc.tag_to_dict(row)
    elif action == "update":
        row = svc.update_tag(db, bid, int(args["tag_id"]), **values)
        result = svc.tag_to_dict(row)
    else:
        svc.delete_tag(db, bid, int(args["tag_id"]))
        result = {"tag_id": int(args["tag_id"]), "deleted": True}
    db.commit()
    return result


def _set_tags(entity, args, context):
    from app.services import crm_tag_service as svc
    db, bid = context["db"], int(context["business_id"])
    method = svc.set_lead_tags if entity == "lead" else svc.set_deal_tags
    key = "lead_id" if entity == "lead" else "deal_id"
    result = method(db, bid, int(args[key]), args["tag_ids"])
    db.commit()
    return result


def _list_reasons(args, context):
    from app.services import crm_close_reason_service as svc
    return svc.list_reasons(context["db"], int(context["business_id"]), reason_type=args.get("reason_type"), active_only=bool(args.get("active_only", False)), seed_defaults=False)


def _reason_mutation(action, args, context):
    from app.services import crm_close_reason_service as svc
    db, bid = context["db"], int(context["business_id"])
    values = {k: v for k, v in args.items() if k != "reason_id"}
    if action == "create":
        row = svc.create_reason(db, bid, **values)
        result = svc.reason_to_dict(row)
    elif action == "update":
        row = svc.update_reason(db, bid, int(args["reason_id"]), **values)
        result = svc.reason_to_dict(row)
    else:
        svc.delete_reason(db, bid, int(args["reason_id"]))
        result = {"reason_id": int(args["reason_id"]), "deleted": True}
    db.commit()
    return result


def _list_fields(args, context):
    from app.services import crm_custom_field_service as svc
    return svc.list_definitions(context["db"], int(context["business_id"]), entity_type=args.get("entity_type"), active_only=bool(args.get("active_only", False)))


def _field_mutation(action, args, context):
    from app.services import crm_custom_field_service as svc
    db, bid = context["db"], int(context["business_id"])
    values = {k: v for k, v in args.items() if k != "field_id"}
    if action == "create":
        row = svc.create_definition(db, bid, **values)
        result = svc.definition_to_dict(row)
    elif action == "update":
        row = svc.update_definition(db, bid, int(args["field_id"]), **values)
        result = svc.definition_to_dict(row)
    else:
        svc.delete_definition(db, bid, int(args["field_id"]))
        result = {"field_id": int(args["field_id"]), "deleted": True}
    db.commit()
    return result


def _stage_schema(action):
    props = {"definition_id": {"type": "integer", "minimum": 1}}
    if action == "update":
        props["stage_id"] = {"type": "integer", "minimum": 1}
    props.update({
        "stage_code": {"type": "string", "minLength": 1, "maxLength": 50},
        "name": {"type": "string", "minLength": 1, "maxLength": 255},
        "order_index": {"type": "integer", "minimum": 0},
        "color": {"type": ["string", "null"], "maxLength": 20},
        "is_win": {"type": "boolean"}, "is_lost": {"type": "boolean"},
        "allow_transition_to": {"type": ["array", "null"], "items": {"type": "string"}},
    })
    required = ["definition_id"] + (["stage_id"] if action == "update" else ["stage_code", "name"])
    return _obj(props, required)


def _process_item(proc, with_stages=True):
    result = {"id": proc.id, "business_id": proc.business_id, "process_type": proc.process_type,
        "code": proc.code, "name": proc.name, "description": proc.description,
        "is_default": proc.is_default, "is_active": proc.is_active,
        "created_by_user_id": proc.created_by_user_id,
        "created_at": proc.created_at.isoformat() if proc.created_at else None,
        "updated_at": proc.updated_at.isoformat() if proc.updated_at else None}
    if with_stages:
        result["stages"] = [_stage_item(s) for s in sorted(proc.stages, key=lambda x: x.order_index)]
    return result


def _stage_item(stage):
    return {"id": stage.id, "process_definition_id": stage.process_definition_id, "stage_code": stage.stage_code,
        "name": stage.name, "order_index": stage.order_index, "color": stage.color, "is_win": stage.is_win,
        "is_lost": stage.is_lost, "allow_transition_to": stage.allow_transition_to,
        "created_at": stage.created_at.isoformat() if stage.created_at else None,
        "updated_at": stage.updated_at.isoformat() if stage.updated_at else None}


def _process_list(args, context):
    from adapters.db.models.crm import CrmProcessDefinition
    db, bid = context["db"], int(context["business_id"])
    q = db.query(CrmProcessDefinition).filter(CrmProcessDefinition.business_id == bid)
    if args.get("process_type"):
        q = q.filter(CrmProcessDefinition.process_type == args["process_type"])
    if args.get("is_active") is not None:
        q = q.filter(CrmProcessDefinition.is_active.is_(bool(args["is_active"])))
    return [_process_item(p) for p in q.order_by(CrmProcessDefinition.process_type, CrmProcessDefinition.code).all()]


def _process_get(args, context):
    from adapters.db.models.crm import CrmProcessDefinition
    db, bid = context["db"], int(context["business_id"])
    proc = db.query(CrmProcessDefinition).filter(CrmProcessDefinition.id == int(args["definition_id"]), CrmProcessDefinition.business_id == bid).first()
    if not proc:
        raise ValueError("فرایند در کسب‌وکار متصل پیدا نشد")
    return _process_item(proc)


def _process_mutation(action, args, context):
    from adapters.db.models.crm import CrmProcessDefinition, CrmProcessStage, Lead, Deal
    db, bid = context["db"], int(context["business_id"])
    if action == "create":
        duplicate = db.query(CrmProcessDefinition.id).filter(CrmProcessDefinition.business_id == bid,
            CrmProcessDefinition.process_type == args["process_type"], CrmProcessDefinition.code == args["code"]).first()
        if duplicate:
            raise ValueError("کد فرایند برای این نوع قبلاً استفاده شده است")
        proc = CrmProcessDefinition(business_id=bid, process_type=args["process_type"], code=args["code"], name=args["name"],
            description=args.get("description"), is_default=bool(args.get("is_default", False)), is_active=bool(args.get("is_active", True)),
            created_by_user_id=context["user_context"].get_user_id())
        db.add(proc)
        db.flush()
        for stage in args.get("stages", []):
            db.add(CrmProcessStage(process_definition_id=proc.id, stage_code=stage["stage_code"], name=stage["name"],
                order_index=int(stage.get("order_index", 0)), color=stage.get("color"), is_win=bool(stage.get("is_win", False)),
                is_lost=bool(stage.get("is_lost", False)), allow_transition_to=stage.get("allow_transition_to")))
    else:
        proc = db.query(CrmProcessDefinition).filter(CrmProcessDefinition.id == int(args["definition_id"]), CrmProcessDefinition.business_id == bid).first()
        if not proc:
            raise ValueError("فرایند در کسب‌وکار متصل پیدا نشد")
        if action == "update":
            for key in ("name", "description", "is_default", "is_active"):
                if key in args:
                    setattr(proc, key, args[key])
        else:
            if db.query(Lead.id).filter(Lead.process_definition_id == proc.id).first() or db.query(Deal.id).filter(Deal.process_definition_id == proc.id).first():
                raise ValueError("این فرایند در سرنخ‌ها یا فرصت‌ها استفاده شده و قابل حذف نیست")
            db.delete(proc)
            db.commit()
            return {"definition_id": int(args["definition_id"]), "deleted": True}
    db.commit()
    db.refresh(proc)
    return _process_item(proc)


def _stage_list(args, context):
    from adapters.db.models.crm import CrmProcessDefinition, CrmProcessStage
    db, bid = context["db"], int(context["business_id"])
    definition_id = int(args["definition_id"])
    exists = db.query(CrmProcessDefinition.id).filter(CrmProcessDefinition.id == definition_id, CrmProcessDefinition.business_id == bid).first()
    if not exists:
        raise ValueError("فرایند در کسب‌وکار متصل پیدا نشد")
    return [_stage_item(s) for s in db.query(CrmProcessStage).filter(CrmProcessStage.process_definition_id == definition_id).order_by(CrmProcessStage.order_index).all()]


def _stage_mutation(action, args, context):
    from adapters.db.models.crm import CrmProcessDefinition, CrmProcessStage, Lead, Deal
    db, bid = context["db"], int(context["business_id"])
    definition_id = int(args["definition_id"])
    proc = db.query(CrmProcessDefinition).filter(CrmProcessDefinition.id == definition_id, CrmProcessDefinition.business_id == bid).first()
    if not proc:
        raise ValueError("فرایند در کسب‌وکار متصل پیدا نشد")
    if action == "create":
        if db.query(CrmProcessStage.id).filter(CrmProcessStage.process_definition_id == definition_id, CrmProcessStage.stage_code == args["stage_code"]).first():
            raise ValueError("کد مرحله در این فرایند تکراری است")
        stage = CrmProcessStage(process_definition_id=definition_id, stage_code=args["stage_code"], name=args["name"],
            order_index=int(args.get("order_index", 0)), color=args.get("color"), is_win=bool(args.get("is_win", False)),
            is_lost=bool(args.get("is_lost", False)), allow_transition_to=args.get("allow_transition_to"))
        db.add(stage)
    else:
        stage = db.query(CrmProcessStage).filter(CrmProcessStage.id == int(args["stage_id"]), CrmProcessStage.process_definition_id == definition_id).first()
        if not stage:
            raise ValueError("مرحله در فرایند انتخاب‌شده پیدا نشد")
        if action == "update":
            for key in ("stage_code", "name", "order_index", "color", "is_win", "is_lost", "allow_transition_to"):
                if key in args:
                    setattr(stage, key, args[key])
        else:
            if db.query(Lead.id).filter(Lead.stage_id == stage.id).first() or db.query(Deal.id).filter(Deal.stage_id == stage.id).first():
                raise ValueError("این مرحله در سرنخ‌ها یا فرصت‌ها استفاده شده و قابل حذف نیست")
            db.delete(stage)
            db.commit()
            return {"stage_id": int(args["stage_id"]), "deleted": True}
    db.commit()
    db.refresh(stage)
    return _stage_item(stage)


def _history(entity, args, context):
    from adapters.db.models.crm import CrmChangeHistory, Lead, Deal
    from sqlalchemy.orm import joinedload
    db, bid = context["db"], int(context["business_id"])
    entity_id = int(args["lead_id"] if entity == "lead" else args["deal_id"])
    model = Lead if entity == "lead" else Deal
    if not db.query(model.id).filter(model.id == entity_id, model.business_id == bid).first():
        raise ValueError(f"{entity_id} در کسب‌وکار متصل پیدا نشد")
    rows = db.query(CrmChangeHistory).options(joinedload(CrmChangeHistory.changed_by)).filter(
        CrmChangeHistory.business_id == bid, CrmChangeHistory.entity_type == entity, CrmChangeHistory.entity_id == entity_id
    ).order_by(CrmChangeHistory.changed_at.desc()).limit(int(args.get("limit", 50))).all()
    return [{"id": r.id, "field_name": r.field_name, "old_value": r.old_value, "new_value": r.new_value,
        "changed_at": r.changed_at.isoformat() if r.changed_at else None, "changed_by_user_id": r.changed_by_user_id,
        "changed_by_name": (f"{r.changed_by.first_name or ''} {r.changed_by.last_name or ''}".strip() if r.changed_by else str(r.changed_by_user_id))} for r in rows]


def _customer_360(args, context):
    from app.services import crm_customer_360_service
    return crm_customer_360_service.get_customer_360(context["db"], int(context["business_id"]), int(args["person_id"]))


def _work_queue(context):
    from datetime import datetime, timedelta
    from adapters.db.models.crm import CrmActivity, Lead, Deal
    from app.services.ai.ai_function_extensions_mcp_crm import _crm_lead_result, _crm_deal_result, _crm_activity_result
    from sqlalchemy.orm import selectinload
    db, bid, user = context["db"], int(context["business_id"]), context["user_context"]
    user_id = user.get_user_id()
    now = datetime.utcnow()
    horizon = now + timedelta(hours=24)
    tasks = db.query(CrmActivity).options(selectinload(CrmActivity.assigned_to), selectinload(CrmActivity.created_by)).filter(
        CrmActivity.business_id == bid, CrmActivity.is_task.is_(True), CrmActivity.status == "open", CrmActivity.assigned_to_user_id == user_id
    ).order_by(CrmActivity.due_at.asc().nullslast()).limit(100).all()
    leads = db.query(Lead).filter(Lead.business_id == bid, Lead.assigned_to_user_id == user_id, Lead.person_id.is_(None),
        Lead.next_follow_up_at.isnot(None), Lead.next_follow_up_at <= horizon).order_by(Lead.next_follow_up_at.asc()).limit(100).all()
    deals = db.query(Deal).filter(Deal.business_id == bid, Deal.assigned_to_user_id == user_id, Deal.closed_at.is_(None),
        Deal.next_follow_up_at.isnot(None), Deal.next_follow_up_at <= horizon).order_by(Deal.next_follow_up_at.asc()).limit(100).all()
    return {"tasks": [_crm_activity_result(t) for t in tasks], "overdue_tasks_count": sum(1 for t in tasks if t.due_at and t.due_at < now),
        "lead_follow_ups": [_crm_lead_result(db, bid, lead) for lead in leads], "deal_follow_ups": [_crm_deal_result(db, bid, deal) for deal in deals]}


def _follow_ups(args, context):
    from datetime import datetime, timedelta, timezone
    from zoneinfo import ZoneInfo
    from sqlalchemy import or_
    from adapters.db.models.crm import Lead, Deal
    from app.services.ai.ai_function_extensions_mcp_crm import _crm_lead_result, _crm_deal_result
    from sqlalchemy.orm import selectinload
    db, bid, user = context["db"], int(context["business_id"]), context["user_context"]
    days = int(args.get("days_ahead", 7))
    tz = ZoneInfo("Asia/Tehran")
    start = datetime.now(tz).replace(hour=0, minute=0, second=0, microsecond=0).astimezone(timezone.utc).replace(tzinfo=None)
    end = (datetime.now(tz).replace(hour=0, minute=0, second=0, microsecond=0) + timedelta(days=days)).astimezone(timezone.utc).replace(tzinfo=None)
    uid = user.get_user_id()
    restrict = bool(uid and not (user.is_superadmin() or user.is_business_owner(bid)))
    ql = db.query(Lead).options(selectinload(Lead.stage), selectinload(Lead.assigned_to), selectinload(Lead.person), selectinload(Lead.created_by)).filter(
        Lead.business_id == bid, Lead.person_id.is_(None), Lead.next_follow_up_at >= start, Lead.next_follow_up_at <= end)
    qd = db.query(Deal).options(selectinload(Deal.stage), selectinload(Deal.assigned_to), selectinload(Deal.person), selectinload(Deal.created_by)).filter(
        Deal.business_id == bid, Deal.closed_at.is_(None), Deal.next_follow_up_at >= start, Deal.next_follow_up_at <= end)
    if restrict:
        ql = ql.filter(or_(Lead.assigned_to_user_id.is_(None), Lead.assigned_to_user_id == uid))
        qd = qd.filter(or_(Deal.assigned_to_user_id.is_(None), Deal.assigned_to_user_id == uid))
    leads = ql.order_by(Lead.next_follow_up_at).limit(50).all()
    deals = qd.order_by(Deal.next_follow_up_at).limit(50).all()
    return {"leads": [_crm_lead_result(db, bid, x) for x in leads], "deals": [_crm_deal_result(db, bid, x) for x in deals]}


def _parse_report_dates(args):
    start = date.fromisoformat(args["from_date"]) if args.get("from_date") else None
    end = date.fromisoformat(args["to_date"]) if args.get("to_date") else None
    if start and end and end < start:
        raise ValueError("تاریخ پایان نباید قبل از تاریخ شروع باشد")
    if start and end and (end - start).days > 3660:
        raise ValueError("بازه گزارش حداکثر ۱۰ سال است")
    return start, end


def _pipeline_report(args, context):
    from sqlalchemy import and_, func
    from adapters.db.models.crm import Deal, CrmProcessStage, CrmProcessDefinition
    db, bid = context["db"], int(context["business_id"])
    start, end = _parse_report_dates(args)
    deal_filter = and_(Deal.stage_id == CrmProcessStage.id, Deal.business_id == bid)
    if start:
        deal_filter = and_(deal_filter, func.date(Deal.created_at) >= start)
    if end:
        deal_filter = and_(deal_filter, func.date(Deal.created_at) <= end)
    q = db.query(CrmProcessStage.id, CrmProcessStage.name, CrmProcessStage.order_index,
        func.count(Deal.id).label("deal_count"), func.coalesce(func.sum(Deal.amount), 0).label("total_amount"))
    q = q.outerjoin(Deal, deal_filter).join(CrmProcessDefinition, CrmProcessDefinition.id == CrmProcessStage.process_definition_id)
    q = q.filter(CrmProcessDefinition.business_id == bid, CrmProcessDefinition.process_type == "sales_pipeline")
    if args.get("process_definition_id"):
        q = q.filter(CrmProcessDefinition.id == int(args["process_definition_id"]))
    rows = q.group_by(CrmProcessStage.id, CrmProcessStage.name, CrmProcessStage.order_index).order_by(CrmProcessStage.order_index).all()
    return [{"stage_id": r.id, "stage_name": r.name, "order_index": r.order_index, "deal_count": r.deal_count,
        "total_amount": float(r.total_amount or 0)} for r in rows]


def _lead_sources_report(context):
    from sqlalchemy import func
    from adapters.db.models.crm import Lead
    rows = context["db"].query(Lead.source_code, func.count(Lead.id).label("count")).filter(
        Lead.business_id == int(context["business_id"]), Lead.source_code.isnot(None), Lead.source_code != "").group_by(Lead.source_code).all()
    return [{"source_code": r.source_code, "count": r.count} for r in rows]


def _weighted_forecast(args, context):
    from sqlalchemy import func
    from adapters.db.models.crm import Deal
    db, bid = context["db"], int(context["business_id"])
    q = db.query(func.coalesce(func.sum(Deal.amount * func.coalesce(Deal.probability_percent, 50) / 100), 0).label("weighted_total"),
        func.count(Deal.id).label("deal_count"), func.coalesce(func.sum(Deal.amount), 0).label("total_amount")).filter(
        Deal.business_id == bid, Deal.closed_at.is_(None))
    if args.get("process_definition_id"):
        q = q.filter(Deal.process_definition_id == int(args["process_definition_id"]))
    row = q.first()
    return {"weighted_total": float(row.weighted_total or 0), "total_amount": float(row.total_amount or 0), "deal_count": int(row.deal_count or 0)}


def _sales_trend(args, context):
    from datetime import datetime, timedelta
    from sqlalchemy import func
    from adapters.db.models.crm import Deal
    db, bid = context["db"], int(context["business_id"])
    period, months = args.get("period", "month"), int(args.get("months", 6))
    end = datetime.utcnow()
    start = end - timedelta(days=months * 31)
    rows = db.query(func.date(Deal.closed_at).label("period"), func.count(Deal.id).label("count"),
        func.coalesce(func.sum(Deal.amount), 0).label("amount")).filter(Deal.business_id == bid,
        Deal.closed_at.isnot(None), Deal.closed_at >= start, Deal.closed_at <= end).group_by(func.date(Deal.closed_at)).all()
    grouped = {}
    for row in rows:
        d = date.fromisoformat(str(row.period))
        if period == "month":
            key = d.strftime("%Y-%m")
        elif period == "week":
            iso = d.isocalendar()
            key = f"{iso.year}-W{iso.week:02d}"
        else:
            key = d.isoformat()
        bucket = grouped.setdefault(key, {"period": key, "count": 0, "amount": 0.0})
        bucket["count"] += int(row.count)
        bucket["amount"] += float(row.amount or 0)
    return [grouped[k] for k in sorted(grouped)]


def _employee_performance(context):
    from sqlalchemy import func, case
    from adapters.db.models.crm import Lead, Deal, CrmActivity
    from adapters.db.models.user import User
    db, bid, ctx = context["db"], int(context["business_id"]), context["user_context"]
    ids = set()
    for model, field in ((Lead, Lead.assigned_to_user_id), (Deal, Deal.assigned_to_user_id), (CrmActivity, CrmActivity.created_by_user_id)):
        ids.update(int(row[0]) for row in db.query(field).filter(model.business_id == bid, field.isnot(None)).distinct().all() if row[0])
    uid = ctx.get_user_id()
    team_allowed = bool(ctx.is_superadmin() or ctx.is_business_owner(bid) or ctx.has_business_permission("crm", "reports_team"))
    if not team_allowed:
        ids = {int(uid)} if uid else set()
    if not ids:
        return {"items": [], "restricted_to_self": not team_allowed}
    lead_rows = db.query(Lead.assigned_to_user_id, func.count(Lead.id), func.sum(case((Lead.person_id.isnot(None), 1), else_=0))).filter(
        Lead.business_id == bid, Lead.assigned_to_user_id.in_(ids)).group_by(Lead.assigned_to_user_id).all()
    deal_rows = db.query(Deal.assigned_to_user_id, func.count(Deal.id), func.sum(case((Deal.closed_at.isnot(None), 1), else_=0)), func.coalesce(func.sum(Deal.amount), 0)).filter(
        Deal.business_id == bid, Deal.assigned_to_user_id.in_(ids)).group_by(Deal.assigned_to_user_id).all()
    activity_rows = db.query(CrmActivity.created_by_user_id, func.count(CrmActivity.id)).filter(
        CrmActivity.business_id == bid, CrmActivity.created_by_user_id.in_(ids)).group_by(CrmActivity.created_by_user_id).all()
    lm = {int(r[0]): (int(r[1] or 0), int(r[2] or 0)) for r in lead_rows}
    dm = {int(r[0]): (int(r[1] or 0), int(r[2] or 0), float(r[3] or 0)) for r in deal_rows}
    am = {int(r[0]): int(r[1] or 0) for r in activity_rows}
    users = {int(u.id): u for u in db.query(User).filter(User.id.in_(ids)).all()}
    result = []
    for member_id in sorted(ids):
        member = users.get(member_id)
        if not member:
            continue
        lc, converted = lm.get(member_id, (0, 0))
        dc, closed, total = dm.get(member_id, (0, 0, 0.0))
        name = f"{member.first_name or ''} {member.last_name or ''}".strip() or str(member_id)
        result.append({"user_id": member_id, "user_name": name, "leads_count": lc, "converted_leads": converted,
            "conversion_rate": round(converted / lc * 100, 1) if lc else 0, "deals_count": dc,
            "closed_deals": closed, "total_amount": total, "activities_count": am.get(member_id, 0)})
    result.sort(key=lambda x: (-x["total_amount"], -x["deals_count"], x["user_id"]))
    return {"items": result, "restricted_to_self": not team_allowed}


def _close_reason_report(reason_type, context):
    from sqlalchemy import func
    from adapters.db.models.crm import Deal
    from app.services import crm_close_reason_service
    db, bid = context["db"], int(context["business_id"])
    column = Deal.won_reason_code if reason_type == "won" else Deal.lost_reason_code
    rows = db.query(column, func.count(Deal.id).label("count"), func.coalesce(func.sum(Deal.amount), 0).label("total_amount")).filter(
        Deal.business_id == bid, column.isnot(None), column != "").group_by(column).all()
    names = {r["code"]: r["name"] for r in crm_close_reason_service.list_reasons(db, bid, reason_type=reason_type)}
    db.commit()
    return [{"reason_code": r[0], "reason_name": names.get(r[0], r[0]), "count": int(r.count or 0),
        "total_amount": float(r.total_amount or 0)} for r in rows]
