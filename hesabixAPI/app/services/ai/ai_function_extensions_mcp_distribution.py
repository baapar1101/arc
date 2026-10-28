"""Permission-bound MCP tools for the business distribution workflows."""
from __future__ import annotations

import importlib
from datetime import date
from typing import Any, Callable

from app.services.ai.function_registry import AIRole, AIFunction

_ROLES = {AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN}
_SCHEMA_MODULE = "adapters.api.v1.schema_models.distribution"


def _schema(properties=None, required=()):
    return {"type": "object", "properties": properties or {}, "required": list(required), "additionalProperties": False}


def _model_schema(name: str, extra=None, required_extra=(), exclude=(), overrides=None):
    cls = getattr(importlib.import_module(_SCHEMA_MODULE), name)
    raw = cls.model_json_schema()
    properties = dict(raw.get("properties") or {})
    for key in exclude:
        properties.pop(key, None)
    properties.update(overrides or {})
    properties.update(extra or {})
    result = {"type": "object", "properties": properties,
        "required": [x for x in dict.fromkeys([*(raw.get("required") or []), *required_extra]) if x in properties],
        "additionalProperties": False}
    if raw.get("$defs"):
        result["$defs"] = raw["$defs"]
    return result


def _payload(model: str, args: dict, exclude=()):
    cls = getattr(importlib.import_module(_SCHEMA_MODULE), model)
    data = {k: v for k, v in args.items() if k not in set(exclude) and k in cls.model_fields}
    return cls(**data).model_dump(exclude_none=True)


def _register(registry, name: str, description: str, schema: dict, handler: Callable,
              permissions, *, write=False, high=False):
    def tenant_bound(args, context):
        from app.core.distribution_plugin_dependency import check_distribution_plugin_active
        business_id = int(context["business_id"])
        if not check_distribution_plugin_active(context["db"], business_id):
            from app.core.responses import ApiError
            raise ApiError("DISTRIBUTION_PLUGIN_NOT_ACTIVE", "افزونه توزیع برای این کسب‌وکار فعال نیست", http_status=403)
        return handler(args, context)
    registry.register(AIFunction(name=name, description=description, parameters_schema=schema, handler=tenant_bound,
        allowed_roles=_ROLES, required_permissions=list(permissions) if isinstance(permissions, (list, tuple)) else [permissions],
        category="distribution", requires_approval=bool(write), risk_level="high" if high else ("medium" if write else "safe"), is_readonly=not write))


def register_mcp_distribution_functions(registry) -> None:
    from app.services import distribution_service as base
    from app.services import distribution_phase3_service as p3
    from app.services import distribution_phase4_service as p4
    from app.services import distribution_commercial_service as commerce
    from app.services import distribution_field_ops_service as field

    id_props = {"territory_id": {"type": "integer", "minimum": 1}, "route_id": {"type": "integer", "minimum": 1},
        "stop_id": {"type": "integer", "minimum": 1}, "assignment_id": {"type": "integer", "minimum": 1},
        "visit_id": {"type": "integer", "minimum": 1}, "request_id": {"type": "integer", "minimum": 1},
        "van_id": {"type": "integer", "minimum": 1}, "target_id": {"type": "integer", "minimum": 1},
        "settlement_id": {"type": "integer", "minimum": 1}, "order_id": {"type": "integer", "minimum": 1},
        "promo_id": {"type": "integer", "minimum": 1}, "trip_id": {"type": "integer", "minimum": 1},
        "stop_id": {"type": "integer", "minimum": 1}, "plan_id": {"type": "integer", "minimum": 1},
        "asset_id": {"type": "integer", "minimum": 1}, "assortment_id": {"type": "integer", "minimum": 1},
        "person_id": {"type": "integer", "minimum": 1}}

    def reg(name, desc, schema, handler, permission="distribution.view", *, write=False, high=False):
        _register(registry, name, desc, schema, handler, permission, write=write, high=high)
    def ctx_call(service, method, args_builder=lambda a,c: (), *, include_ctx=False):
        def call(a,c):
            fn = getattr(service, method)
            values = args_builder(a,c)
            if include_ctx:
                return fn(c["db"], int(c["business_id"]), c["user_context"], *values)
            return fn(c["db"], int(c["business_id"]), *values)
        return call
    def body_schema(model, extras=None, required=(), *, exclude=(), overrides=None):
        return _model_schema(model, extras, required, exclude, overrides)
    def payload_call(service, method, model, path_fields=(), *, actor=False, include_ctx=False, extra_builder=None):
        def call(a,c):
            bid=int(c["business_id"]); db=c["db"]
            payload=_payload(model,a,exclude=path_fields)
            values=[]
            for field_name in path_fields:
                values.append(int(a[field_name]))
            if actor:
                values.append(c["user_context"].get_user_id() or 0)
            if extra_builder:
                values.extend(extra_builder(a,c,payload))
            if include_ctx:
                return getattr(service,method)(db,bid,c["user_context"],*values,payload)
            return getattr(service,method)(db,bid,*values,payload)
        return call

    # Route, territory, visit scheduling and assignments.
    reg("get_distribution_summary", "خلاصه شاخص‌های افزونه توزیع برای کسب‌وکار متصل.", _schema(), ctx_call(base,"get_summary",include_ctx=True))
    reg("list_distribution_territories", "فهرست قلمروهای توزیع.", _schema(), ctx_call(base,"list_territories",include_ctx=True))
    reg("create_distribution_territory", "ایجاد قلمرو توزیع.", body_schema("TerritoryCreatePayload"), lambda a,c: base.create_territory(c["db"],int(c["business_id"]),_payload("TerritoryCreatePayload",a)), "distribution.manage", write=True)
    reg("update_distribution_territory", "ویرایش قلمرو توزیع.", body_schema("TerritoryUpdatePayload", {"territory_id":id_props["territory_id"]}, ["territory_id"]), lambda a,c: base.update_territory(c["db"],int(c["business_id"]),int(a["territory_id"]),_payload("TerritoryUpdatePayload",a)), "distribution.manage", write=True)
    reg("delete_distribution_territory", "حذف قلمرو توزیع؛ نیازمند تأیید.", _schema({"territory_id":id_props["territory_id"]},["territory_id"]), lambda a,c: base.delete_territory(c["db"],int(c["business_id"]),int(a["territory_id"])), "distribution.manage", write=True, high=True)
    reg("create_distribution_route", "ایجاد مسیر توزیع.", body_schema("RouteCreatePayload"), lambda a,c: base.create_route(c["db"],int(c["business_id"]),_payload("RouteCreatePayload",a)), "distribution.manage", write=True)
    reg("update_distribution_route", "ویرایش مسیر توزیع.", body_schema("RouteUpdatePayload", {"route_id":id_props["route_id"]}, ["route_id"]), lambda a,c: base.update_route(c["db"],int(c["business_id"]),int(a["route_id"]),_payload("RouteUpdatePayload",a)), "distribution.manage", write=True)
    reg("delete_distribution_route", "حذف مسیر توزیع؛ نیازمند تأیید.", _schema({"route_id":id_props["route_id"]},["route_id"]), lambda a,c: base.delete_route(c["db"],int(c["business_id"]),int(a["route_id"])), "distribution.manage", write=True, high=True)
    reg("list_distribution_route_stops", "فهرست توقف‌های مسیر توزیع.", _schema({"route_id":id_props["route_id"]},["route_id"]), lambda a,c: base.list_route_stops(c["db"],int(c["business_id"]),int(a["route_id"]),c["user_context"]))
    reg("upsert_distribution_route_stop", "افزودن یا ویرایش توقف مسیر؛ person باید متعلق به کسب‌وکار باشد.", body_schema("RouteStopPayload", {"route_id":id_props["route_id"]}, ["route_id","person_id"]), lambda a,c: base.upsert_route_stop(c["db"],int(c["business_id"]),int(a["route_id"]),_payload("RouteStopPayload",a)), "distribution.manage", write=True)
    reg("delete_distribution_route_stop", "حذف توقف از مسیر؛ نیازمند تأیید.", _schema({"route_id":id_props["route_id"],"stop_id":id_props["stop_id"]},["route_id","stop_id"]), lambda a,c: base.delete_route_stop(c["db"],int(c["business_id"]),int(a["route_id"]),int(a["stop_id"])), "distribution.manage", write=True)
    reg("list_distribution_assignments", "فهرست تخصیص مسیر به کاربران با فیلتر اختیاری مسیر.", _schema({"route_id":{"type":["integer","null"],"minimum":1}}), lambda a,c: base.list_assignments(c["db"],int(c["business_id"]),a.get("route_id"),c["user_context"]))
    reg("create_distribution_assignment", "تخصیص مسیر به کاربر در بازه زمانی.", body_schema("AssignmentCreatePayload"), lambda a,c: base.create_assignment(c["db"],int(c["business_id"]),_payload("AssignmentCreatePayload",a)), "distribution.manage", write=True)
    reg("delete_distribution_assignment", "حذف تخصیص مسیر.", _schema({"assignment_id":id_props["assignment_id"]},["assignment_id"]), lambda a,c: base.delete_assignment(c["db"],int(c["business_id"]),int(a["assignment_id"])), "distribution.manage", write=True)
    def daily_plan(a,c):
        ctx=c["user_context"]; uid=ctx.get_user_id()
        if uid is None: raise ValueError("Authenticated user id is required")
        if not (ctx.has_business_permission("distribution","operate") or ctx.has_business_permission("distribution","manage") or ctx.has_business_permission("distribution","reports_team")):
            from app.core.responses import ApiError
            raise ApiError("FORBIDDEN","distribution.operate, distribution.manage or distribution.reports_team required",http_status=403)
        target=a.get("target_user_id")
        if target is not None:
            if not (ctx.has_business_permission("distribution","manage") or ctx.has_business_permission("distribution","reports_team")):
                from app.core.responses import ApiError
                raise ApiError("FORBIDDEN","Only managers or team-report users can inspect another user's plan",http_status=403)
            uid=int(target)
        from app.core.business_calendar import business_today
        return base.get_daily_plan(c["db"],int(c["business_id"]),int(uid),date.fromisoformat(a["plan_date"]) if a.get("plan_date") else business_today(int(c["business_id"])))
    reg("get_distribution_daily_plan", "برنامه ویزیت روزانه؛ برای مشاهده برنامه کاربر دیگر permission گزارش تیم لازم است.", _schema({"plan_date":{"type":["string","null"],"format":"date"},"target_user_id":{"type":["integer","null"],"minimum":1}}), daily_plan, ["distribution.operate","distribution.manage","distribution.reports_team"])
    def list_visits(a,c):
        rows,total=base.list_visits(c["db"],int(c["business_id"]),c["user_context"],date.fromisoformat(a["from_date"]) if a.get("from_date") else None,date.fromisoformat(a["to_date"]) if a.get("to_date") else None,int(a.get("take",50)),int(a.get("skip",0)))
        return {"items":rows,"total":total,"take":int(a.get("take",50)),"skip":int(a.get("skip",0))}
    reg("list_distribution_visits", "فهرست بازدیدهای قابل مشاهده با فیلتر تاریخ و صفحه‌بندی.", _schema({"from_date":{"type":["string","null"],"format":"date"},"to_date":{"type":["string","null"],"format":"date"},"take":{"type":"integer","minimum":1,"maximum":200},"skip":{"type":"integer","minimum":0}}),list_visits)

    # Field operations, returns, configuration and read-only reports.
    reg("start_distribution_visit", "شروع بازدید میدانی برای مشتری و مسیر؛ موقعیت فقط در صورت ارائه ثبت می‌شود.", body_schema("VisitStartPayload",exclude=("supervisor_user_id","is_carried_over")), lambda a,c: base.start_visit(c["db"],int(c["business_id"]),c["user_context"].get_user_id(),_payload("VisitStartPayload",a,exclude=("supervisor_user_id","is_carried_over")),ctx=c["user_context"]), "distribution.operate", write=True)
    reg("complete_distribution_visit", "ثبت نتیجه و تکمیل بازدید؛ ممکن است سفارش، فاکتور یا گردش فروش خودرو ایجاد کند.", body_schema("VisitCompletePayload", {"visit_id":id_props["visit_id"]}, ["visit_id","outcome"], overrides={"pod_signature_png":{"type":["string","null"],"maxLength":250000}}), lambda a,c: base.complete_visit(c["db"],int(c["business_id"]),c["user_context"].get_user_id(),int(a["visit_id"]),_payload("VisitCompletePayload",a),allow_manage_override=c["user_context"].has_business_permission("distribution","manage")), "distribution.operate", write=True, high=True)
    reg("cancel_distribution_visit", "لغو بازدید؛ نیازمند تأیید.", _schema({"visit_id":id_props["visit_id"],"reason":{"type":["string","null"],"maxLength":1000}},["visit_id"]), lambda a,c: base.cancel_visit(c["db"],int(c["business_id"]),c["user_context"].get_user_id(),int(a["visit_id"]),a.get("reason"),allow_manage_override=c["user_context"].has_business_permission("distribution","manage")), "distribution.operate", write=True)
    reg("create_distribution_return_request", "ثبت درخواست مرجوعی کالا؛ به‌تنهایی تأیید یا سند انبار قطعی نمی‌سازد.", body_schema("ReturnRequestCreatePayload"), lambda a,c: base.create_return_request(c["db"],int(c["business_id"]),c["user_context"].get_user_id(),_payload("ReturnRequestCreatePayload",a),ctx=c["user_context"]), "distribution.operate", write=True)
    reg("list_distribution_return_requests", "فهرست درخواست‌های مرجوعی.", _schema({"status":{"type":["string","null"]}}), lambda a,c: base.list_return_requests(c["db"],int(c["business_id"]),c["user_context"],a.get("status")))
    reg("resolve_distribution_return_request", "تأیید یا رد مرجوعی؛ تأیید می‌تواند سند انبار ایجاد کند.", body_schema("ReturnResolvePayload", {"request_id":id_props["request_id"]}, ["request_id","status"]), lambda a,c: base.resolve_return_request(c["db"],int(c["business_id"]),c["user_context"].get_user_id(),int(a["request_id"]),_payload("ReturnResolvePayload",a)), "distribution.approve_returns", write=True, high=True)
    reg("get_distribution_settings", "خواندن تنظیمات عملیات توزیع.", _schema(), lambda a,c: base.settings_for_client(c["db"],int(c["business_id"]),c["user_context"]))
    reg("update_distribution_settings", "ویرایش تنظیمات توزیع، نقشه، رهگیری و فروش خودرو.", body_schema("DistributionSettingsPayload"), lambda a,c: base.update_distribution_settings(c["db"],int(c["business_id"]),_payload("DistributionSettingsPayload",a)), "distribution.manage", write=True, high=True)
    reg("get_distribution_dashboard", "گزارش داشبورد توزیع برای بازه زمانی و کاربر اختیاری.", _schema({"from_date":{"type":"string","format":"date"},"to_date":{"type":"string","format":"date"},"target_user_id":{"type":["integer","null"],"minimum":1}},["from_date","to_date"]), lambda a,c: base.get_distribution_reports_dashboard(c["db"],int(c["business_id"]),c["user_context"],date.fromisoformat(a["from_date"]),date.fromisoformat(a["to_date"]),a.get("target_user_id")))

    # Van inventory.
    reg("list_distribution_vans", "فهرست خودروهای فروش/توزیع.", _schema(), lambda a,c:p3.list_vans(c["db"],int(c["business_id"]),c["user_context"]))
    reg("create_distribution_van", "ثبت خودرو و تخصیص اختیاری کاربر.", body_schema("VanCreatePayload"), lambda a,c:p3.create_van(c["db"],int(c["business_id"]),_payload("VanCreatePayload",a)), "distribution.manage", write=True)
    reg("update_distribution_van", "ویرایش مشخصات خودرو.", body_schema("VanUpdatePayload", {"van_id":id_props["van_id"]}, ["van_id"]), lambda a,c:p3.update_van(c["db"],int(c["business_id"]),int(a["van_id"]),_payload("VanUpdatePayload",a)), "distribution.manage", write=True)
    reg("get_distribution_van_stock", "موجودی خودرو به تفکیک کالا و lot.", _schema({"van_id":id_props["van_id"]},["van_id"]), lambda a,c:p3.get_van_stock(c["db"],int(c["business_id"]),int(a["van_id"]),ctx=c["user_context"]))
    reg("load_distribution_van", "بارگیری کالا از انبار به خودرو؛ گردش موجودی ثبت می‌کند.", body_schema("VanLoadPayload", {"van_id":id_props["van_id"]}, ["van_id","lines"]), lambda a,c:p3.load_van(c["db"],int(c["business_id"]),c["user_context"].get_user_id(),int(a["van_id"]),_payload("VanLoadPayload",a)["lines"],a.get("source_warehouse_id"),ctx=c["user_context"]), "distribution.operate", write=True, high=True)
    reg("unload_distribution_van", "تخلیه کالا از خودرو به انبار؛ گردش موجودی ثبت می‌کند.", body_schema("VanUnloadPayload", {"van_id":id_props["van_id"]}, ["van_id","lines"]), lambda a,c:p3.unload_van(c["db"],int(c["business_id"]),c["user_context"].get_user_id(),int(a["van_id"]),_payload("VanUnloadPayload",a)["lines"],a.get("dest_warehouse_id"),ctx=c["user_context"]), "distribution.operate", write=True, high=True)
    def my_van_stock(a,c):
        van=p3.get_van_for_user(c["db"],int(c["business_id"]),c["user_context"].get_user_id())
        return {"van":None,"items":[]} if van is None else p3.get_van_stock(c["db"],int(c["business_id"]),int(van.id),ctx=c["user_context"])
    reg("get_my_distribution_van_stock", "موجودی خودروی تخصیص‌یافته به کاربر جاری.", _schema(), my_van_stock, "distribution.operate")

    # Sales targets, settlements, customer orders and promotions.
    reg("list_distribution_targets", "فهرست اهداف فروش.", _schema({"user_id":{"type":["integer","null"],"minimum":1},"period_type":{"type":["string","null"],"enum":["day","month",None]}}), lambda a,c:p4.list_sales_targets(c["db"],int(c["business_id"]),c["user_context"],user_id=a.get("user_id"),period_type=a.get("period_type")))
    reg("upsert_distribution_target", "ثبت یا ویرایش هدف فروش کاربر.", body_schema("SalesTargetPayload"), lambda a,c:p4.upsert_sales_target(c["db"],int(c["business_id"]),c["user_context"].get_user_id(),_payload("SalesTargetPayload",a)), "distribution.manage", write=True)
    reg("delete_distribution_target", "حذف هدف فروش.", _schema({"target_id":id_props["target_id"]},["target_id"]), lambda a,c:p4.delete_sales_target(c["db"],int(c["business_id"]),int(a["target_id"])), "distribution.manage", write=True)
    def preview_settlement(a,c):
        from app.core.business_calendar import business_today
        return p4.preview_settlement(c["db"],int(c["business_id"]),c["user_context"],int(a.get("target_user_id") or c["user_context"].get_user_id()),date.fromisoformat(a["settlement_date"]) if a.get("settlement_date") else business_today(int(c["business_id"])))
    reg("preview_distribution_settlement", "پیش‌نمایش تسویه و مغایرت بدون ثبت تسویه.", _schema({"settlement_date":{"type":["string","null"],"format":"date"},"target_user_id":{"type":["integer","null"],"minimum":1}}), preview_settlement, "distribution.operate")
    reg("list_distribution_settlements", "فهرست تسویه‌ها با فیلتر تاریخ/کاربر.", _schema({"from_date":{"type":["string","null"],"format":"date"},"to_date":{"type":["string","null"],"format":"date"},"user_id":{"type":["integer","null"],"minimum":1}}), lambda a,c:p4.list_settlements(c["db"],int(c["business_id"]),c["user_context"],from_date=date.fromisoformat(a["from_date"]) if a.get("from_date") else None,to_date=date.fromisoformat(a["to_date"]) if a.get("to_date") else None,user_id=a.get("user_id")))
    reg("upsert_distribution_settlement", "ثبت مبالغ وصولی و هزینه برای تسویه؛ تأیید حسابداری عملیات جداگانه است.", body_schema("SettlementUpsertPayload"), lambda a,c:p4.upsert_settlement(c["db"],int(c["business_id"]),c["user_context"].get_user_id(),c["user_context"],_payload("SettlementUpsertPayload",a)), "distribution.operate", write=True, high=True)
    reg("confirm_distribution_settlement", "تأیید تسویه؛ در صورت درخواست می‌تواند رسید مالی ایجاد کند.", body_schema("SettlementConfirmPayload", {"settlement_id":id_props["settlement_id"]}, ["settlement_id"]), lambda a,c:p4.confirm_settlement(c["db"],int(c["business_id"]),c["user_context"].get_user_id(),c["user_context"],int(a["settlement_id"]),_payload("SettlementConfirmPayload",a)), "distribution.settle", write=True, high=True)
    reg("list_distribution_orders", "فهرست سفارش‌های پیش‌فروش/میدانی.", _schema({"status":{"type":["string","null"]},"person_id":{"type":["integer","null"],"minimum":1},"from_date":{"type":["string","null"],"format":"date"},"to_date":{"type":["string","null"],"format":"date"}}), lambda a,c:commerce.list_visit_orders(c["db"],int(c["business_id"]),c["user_context"],status=a.get("status"),from_date=date.fromisoformat(a["from_date"]) if a.get("from_date") else None,to_date=date.fromisoformat(a["to_date"]) if a.get("to_date") else None,person_id=a.get("person_id")))
    reg("create_distribution_order", "ایجاد سفارش پیش‌فروش یا ویزیت با اقلام صریح؛ سفارش draft مگر confirm=true.", body_schema("VisitOrderCreatePayload"), lambda a,c:commerce.create_visit_order(c["db"],int(c["business_id"]),c["user_context"].get_user_id(),_payload("VisitOrderCreatePayload",a),ctx=c["user_context"]), "distribution.operate", write=True, high=True)
    reg("confirm_distribution_order", "تأیید سفارش موجود.", _schema({"order_id":id_props["order_id"]},["order_id"]), lambda a,c:commerce.confirm_visit_order(c["db"],int(c["business_id"]),c["user_context"].get_user_id(),int(a["order_id"]),ctx=c["user_context"]), "distribution.operate", write=True, high=True)
    reg("update_distribution_order_status", "تغییر وضعیت سفارش توزیع.", _schema({"order_id":id_props["order_id"],"status":{"type":"string","enum":["draft","confirmed","picking","loaded","out_for_delivery","delivered","cancelled"]}},["order_id","status"]), lambda a,c:commerce.update_order_status(c["db"],int(c["business_id"]),int(a["order_id"]),a["status"],actor_user_id=c["user_context"].get_user_id() or 0), "distribution.manage", write=True, high=True)
    def suggested_order(a,c):
        base.assert_person_visible_for_ctx(c["db"],int(c["business_id"]),c["user_context"],int(a["person_id"]))
        return commerce.suggested_order_for_person(c["db"],int(c["business_id"]),int(a["person_id"]))
    reg("get_suggested_distribution_order", "پیشنهاد سفارش برای مشتری با توجه به داده‌های کسب‌وکار.", _schema({"person_id":id_props["person_id"]},["person_id"]), suggested_order)
    reg("list_distribution_promotions", "فهرست کمپین‌های تخفیف توزیع.", _schema({"include_inactive":{"type":"boolean"}}), lambda a,c:commerce.list_promotions(c["db"],int(c["business_id"]),active_only=not bool(a.get("include_inactive",False))))
    reg("create_distribution_promotion", "ایجاد پروموشن؛ اثر آن ممکن است قیمت سفارش را تغییر دهد.", body_schema("PromotionUpsertPayload"), lambda a,c:commerce.upsert_promotion(c["db"],int(c["business_id"]),_payload("PromotionUpsertPayload",a)), "distribution.manage", write=True, high=True)
    reg("update_distribution_promotion", "ویرایش پروموشن.", body_schema("PromotionUpsertPayload", {"promo_id":id_props["promo_id"]}, ["promo_id"]), lambda a,c:commerce.upsert_promotion(c["db"],int(c["business_id"]),_payload("PromotionUpsertPayload",a),promo_id=int(a["promo_id"])), "distribution.manage", write=True, high=True)
    reg("delete_distribution_promotion", "حذف پروموشن.", _schema({"promo_id":id_props["promo_id"]},["promo_id"]), lambda a,c:commerce.delete_promotion(c["db"],int(c["business_id"]),int(a["promo_id"])), "distribution.manage", write=True, high=True)

    # Delivery, customer profile, assortments and supporting insights.
    reg("list_distribution_delivery_trips", "فهرست سفرهای تحویل.", _schema({"trip_date":{"type":["string","null"],"format":"date"}}), lambda a,c:commerce.list_delivery_trips(c["db"],int(c["business_id"]),c["user_context"],trip_date=date.fromisoformat(a["trip_date"]) if a.get("trip_date") else None))
    reg("create_distribution_delivery_trip", "ایجاد سفر تحویل از سفارش‌های مشخص.", body_schema("DeliveryTripCreatePayload"), lambda a,c:commerce.create_delivery_trip(c["db"],int(c["business_id"]),c["user_context"].get_user_id(),_payload("DeliveryTripCreatePayload",a),ctx=c["user_context"]), "distribution.operate", write=True, high=True)
    reg("start_distribution_delivery_trip", "شروع سفر تحویل؛ نیازمند تأیید.", _schema({"trip_id":id_props["trip_id"]},["trip_id"]), lambda a,c:commerce.start_delivery_trip(c["db"],int(c["business_id"]),int(a["trip_id"]),c["user_context"].get_user_id() or 0,allow_manage=c["user_context"].has_business_permission("distribution","manage")), "distribution.operate", write=True, high=True)
    reg("complete_distribution_delivery_stop", "ثبت تحویل/کسری/عدم تحویل به همراه مدرک تحویل.", body_schema("DeliveryStopCompletePayload", {"stop_id":id_props["stop_id"]}, ["stop_id"]), lambda a,c:commerce.complete_delivery_stop(c["db"],int(c["business_id"]),int(a["stop_id"]),c["user_context"].get_user_id() or 0,_payload("DeliveryStopCompletePayload",a),ctx=c["user_context"]), "distribution.operate", write=True, high=True)
    reg("list_distribution_load_plans", "فهرست برنامه‌های بارگیری.", _schema({"plan_date":{"type":["string","null"],"format":"date"}}), lambda a,c:commerce.list_load_plans(c["db"],int(c["business_id"]),plan_date=date.fromisoformat(a["plan_date"]) if a.get("plan_date") else None))
    reg("create_distribution_load_plan", "ساخت برنامه بارگیری از سفارش‌های انتخاب‌شده.", body_schema("LoadPlanCreatePayload"), lambda a,c:commerce.build_load_plan_from_orders(c["db"],int(c["business_id"]),c["user_context"].get_user_id() or 0,_payload("LoadPlanCreatePayload",a)), "distribution.manage", write=True)
    reg("confirm_distribution_load_plan", "تأیید برنامه بارگیری و ثبت مقدارهای واقعی.", body_schema("LoadPlanConfirmPayload", {"plan_id":id_props["plan_id"]}, ["plan_id"]), lambda a,c:commerce.confirm_load_plan(c["db"],int(c["business_id"]),int(a["plan_id"]),c["user_context"].get_user_id() or 0,_payload("LoadPlanConfirmPayload",a)), "distribution.manage", write=True, high=True)
    reg("get_distribution_visit_trail", "مسیر ثبت‌شده بازدید؛ اطلاعات مکانی فقط با دسترسی توزیع مجاز.", _schema({"visit_id":id_props["visit_id"]},["visit_id"]), lambda a,c:commerce.get_visit_trail(c["db"],int(c["business_id"]),int(a["visit_id"]),ctx=c["user_context"]))
    def credit_summary(a,c):
        base.assert_person_visible_for_ctx(c["db"],int(c["business_id"]),c["user_context"],int(a["person_id"]))
        return base.get_person_credit_summary(c["db"],int(c["business_id"]),int(a["person_id"]))
    reg("get_distribution_person_credit_summary", "خلاصه اعتبار مشتری برای عملیات توزیع.", _schema({"person_id":id_props["person_id"]},["person_id"]), credit_summary)
    reg("get_distribution_customer_360", "نمای تجمیعی مشتری در افزونه توزیع.", _schema({"person_id":id_props["person_id"]},["person_id"]), lambda a,c:field.customer_360(c["db"],int(c["business_id"]),int(a["person_id"]),user_id=c["user_context"].get_user_id(),ctx=c["user_context"]))
    reg("list_distribution_reason_codes", "فهرست کدهای علت ویزیت/مرجوعی.", _schema(), lambda a,c:field.reason_catalog())
    reg("get_distribution_product_by_barcode", "جستجوی کالا با بارکد در کسب‌وکار متصل.", _schema({"barcode":{"type":"string","minLength":1,"maxLength":128},"person_id":{"type":["integer","null"],"minimum":1}},["barcode"]), lambda a,c:field.lookup_product_by_barcode(c["db"],int(c["business_id"]),a["barcode"],person_id=a.get("person_id")))
    def open_invoices(a,c):
        base.assert_person_visible_for_ctx(c["db"],int(c["business_id"]),c["user_context"],int(a["person_id"]))
        return __import__("app.services.distribution_documents",fromlist=["list_person_open_invoices"]).list_person_open_invoices(c["db"],int(c["business_id"]),int(a["person_id"]),limit=int(a.get("limit",20)))
    reg("list_distribution_person_open_invoices", "فاکتورهای باز مشتری برای عملیات توزیع؛ حداکثر ۵۰ مورد.", _schema({"person_id":id_props["person_id"],"limit":{"type":"integer","minimum":1,"maximum":50}},["person_id"]), open_invoices)
    reg("upsert_distribution_customer_profile", "تنظیم کلاس، تناوب و قیمت‌گذاری مشتری.", body_schema("CustomerProfilePayload", {"person_id":id_props["person_id"]}, ["person_id"]), lambda a,c:field.upsert_customer_profile(c["db"],int(c["business_id"]),int(a["person_id"]),_payload("CustomerProfilePayload",a)), "distribution.manage", write=True)
    reg("list_distribution_customer_profiles", "فهرست پروفایل‌های مشتری توزیع.", _schema({"person_id":{"type":["integer","null"],"minimum":1}}), lambda a,c:field.list_customer_profiles(c["db"],int(c["business_id"]),person_id=a.get("person_id"),ctx=c["user_context"]))
    reg("list_distribution_assortments", "فهرست ترکیب کالاهای پیشنهادی برای انواع فروشگاه.", _schema(), lambda a,c:field.list_assortments(c["db"],int(c["business_id"])))
    reg("create_distribution_assortment", "ایجاد ترکیب کالا برای فروشگاه‌ها.", body_schema("AssortmentPayload"), lambda a,c:field.upsert_assortment(c["db"],int(c["business_id"]),_payload("AssortmentPayload",a)), "distribution.manage", write=True)
    reg("update_distribution_assortment", "ویرایش ترکیب کالا.", body_schema("AssortmentPayload", {"assortment_id":id_props["assortment_id"]}, ["assortment_id"]), lambda a,c:field.upsert_assortment(c["db"],int(c["business_id"]),_payload("AssortmentPayload",a),assortment_id=int(a["assortment_id"])), "distribution.manage", write=True)
    reg("delete_distribution_assortment", "حذف ترکیب کالا.", _schema({"assortment_id":id_props["assortment_id"]},["assortment_id"]), lambda a,c:field.delete_assortment(c["db"],int(c["business_id"]),int(a["assortment_id"])), "distribution.manage", write=True)
    reg("list_distribution_customer_assets", "فهرست تجهیزات ثبت‌شده نزد مشتریان.", _schema({"person_id":{"type":["integer","null"],"minimum":1}}), lambda a,c:commerce.list_customer_assets(c["db"],int(c["business_id"]),a.get("person_id"),ctx=c["user_context"]))
    reg("create_distribution_customer_asset", "ثبت تجهیز مشتری؛ نیازمند تأیید.", body_schema("CustomerAssetPayload"), lambda a,c:commerce.upsert_customer_asset(c["db"],int(c["business_id"]),_payload("CustomerAssetPayload",a)), "distribution.manage", write=True)
    reg("update_distribution_customer_asset", "ویرایش تجهیز ثبت‌شده نزد مشتری.", body_schema("CustomerAssetPayload", {"asset_id":id_props["asset_id"]}, ["asset_id"]), lambda a,c:commerce.upsert_customer_asset(c["db"],int(c["business_id"]),_payload("CustomerAssetPayload",a),asset_id=int(a["asset_id"])), "distribution.manage", write=True)
    reg("get_distribution_scorecard", "امتیاز عملکرد ویزیتور در بازه زمانی.", _schema({"from_date":{"type":"string","format":"date"},"to_date":{"type":"string","format":"date"},"target_user_id":{"type":["integer","null"],"minimum":1}},["from_date","to_date"]), lambda a,c:field.visitor_scorecard(c["db"],int(c["business_id"]),c["user_context"],date.fromisoformat(a["from_date"]),date.fromisoformat(a["to_date"]),a.get("target_user_id")))
    reg("list_distribution_commission_rules", "فهرست قواعد محاسبه کمیسیون.", _schema(), lambda a,c:commerce.list_commission_rules(c["db"],int(c["business_id"])), "distribution.manage")
    reg("create_distribution_commission_rule", "تعریف قاعده کمیسیون فروش.", body_schema("CommissionRulePayload"), lambda a,c:commerce.upsert_commission_rule(c["db"],int(c["business_id"]),_payload("CommissionRulePayload",a)), "distribution.manage", write=True, high=True)
    reg("list_distribution_commission_runs", "فهرست اجراهای محاسبه کمیسیون.", _schema(), lambda a,c:commerce.list_commission_runs(c["db"],int(c["business_id"])), "distribution.manage")
    reg("create_distribution_commission_run", "محاسبه کمیسیون برای کاربر و بازه مشخص.", body_schema("CommissionRunPayload"), lambda a,c:commerce.compute_commission_run(c["db"],int(c["business_id"]),c["user_context"].get_user_id() or 0,_payload("CommissionRunPayload",a)), "distribution.manage", write=True, high=True)
    reg("list_distribution_shelf_audits", "فهرست بازرسی قفسه مشتری/بازدید.", _schema({"person_id":{"type":["integer","null"],"minimum":1},"visit_id":{"type":["integer","null"],"minimum":1}}), lambda a,c:commerce.list_shelf_audits(c["db"],int(c["business_id"]),person_id=a.get("person_id"),visit_id=a.get("visit_id"),ctx=c["user_context"]))
    reg("create_distribution_shelf_audit", "ثبت نتیجه بازرسی قفسه، پاسخ‌ها و تصاویر.", body_schema("ShelfAuditPayload"), lambda a,c:commerce.create_shelf_audit(c["db"],int(c["business_id"]),c["user_context"].get_user_id() or 0,_payload("ShelfAuditPayload",a),ctx=c["user_context"]), "distribution.operate", write=True)

    reg("set_distribution_customer_location", "ثبت مختصات فروشگاه مشتری.", body_schema("PersonLocationPayload", {"person_id":id_props["person_id"]}, ["person_id","latitude","longitude"]), lambda a,c:p3.update_person_location(c["db"],int(c["business_id"]),int(a["person_id"]),float(a["latitude"]),float(a["longitude"])), "distribution.manage", write=True, high=True)
    reg("update_distribution_visit_location", "ثبت موقعیت لحظه‌ای ویزیت جاری کاربر؛ داده مکانی ذخیره/به اشتراک گذاشته می‌شود.", body_schema("VisitHeartbeatPayload", {"visit_id":id_props["visit_id"]}, ["visit_id","latitude","longitude"]), lambda a,c:base.heartbeat_visit(c["db"],int(c["business_id"]),c["user_context"].get_user_id(),int(a["visit_id"]),float(a["latitude"]),float(a["longitude"])), "distribution.operate", write=True)
    reg("report_distribution_live_location", "ارسال موقعیت فعلی کاربر برای اشتراک‌گذاری نقشه تیم.", _schema({"latitude":{"type":"number","minimum":-90,"maximum":90},"longitude":{"type":"number","minimum":-180,"maximum":180},"visit_id":{"type":["integer","null"],"minimum":1}},["latitude","longitude"]), lambda a,c:commerce.report_live_location(c["db"],int(c["business_id"]),c["user_context"].get_user_id(),float(a["latitude"]),float(a["longitude"]),visit_id=a.get("visit_id")), "distribution.operate", write=True)
    reg("set_distribution_location_consent", "ثبت یا لغو رضایت اشتراک موقعیت زندهٔ کاربر جاری.", _schema({"location_consent":{"type":"boolean"}},["location_consent"]), lambda a,c:base.upsert_user_preference(c["db"],int(c["business_id"]),c["user_context"].get_user_id() or 0,{"location_consent":bool(a["location_consent"])}), "distribution.view", write=True)
    def publish_plan(a,c):
        from app.core.business_calendar import business_today
        bid=int(c["business_id"])
        actor=c["user_context"].get_user_id() or 0
        day=date.fromisoformat(a["plan_date"]) if a.get("plan_date") else business_today(bid)
        if a.get("all_assigned"):
            return base.publish_daily_plans_for_date(c["db"],bid,actor,day,locked=bool(a.get("locked",True)),notes=a.get("notes"),ctx=c["user_context"])
        target=int(a["target_user_id"]) if a.get("target_user_id") else actor
        return base.publish_daily_plan(c["db"],bid,actor,target,day,locked=bool(a.get("locked",True)),notes=a.get("notes"),ctx=c["user_context"])
    reg("publish_distribution_daily_plan", "نشر رسمی برنامه روز برای یک ویزیتور یا همه تخصیص‌ها.", _schema({"plan_date":{"type":["string","null"],"format":"date"},"target_user_id":{"type":["integer","null"],"minimum":1},"all_assigned":{"type":"boolean"},"locked":{"type":"boolean"},"notes":{"type":["string","null"]}}), publish_plan, "distribution.manage", write=True)
    def optimize(a,c):
        from app.core.business_calendar import business_today
        day=date.fromisoformat(a["plan_date"]) if a.get("plan_date") else business_today(int(c["business_id"]))
        return p3.optimize_route_plan(c["db"],int(c["business_id"]),int(a["route_id"]),day,a.get("start_latitude"),a.get("start_longitude"))
    route_opt_schema=_schema({"route_id":id_props["route_id"],"plan_date":{"type":["string","null"],"format":"date"},"start_latitude":{"type":["number","null"],"minimum":-90,"maximum":90},"start_longitude":{"type":["number","null"],"minimum":-180,"maximum":180}},["route_id"])
    reg("preview_distribution_route_optimization", "پیش‌نمایش ترتیب بهینه توقف‌ها بدون تغییر مسیر ذخیره‌شده.",route_opt_schema,optimize)
    def persist_optimize(a,c):
        from app.core.business_calendar import business_today
        day=date.fromisoformat(a["plan_date"]) if a.get("plan_date") else business_today(int(c["business_id"]))
        return p3.apply_route_optimize(c["db"],int(c["business_id"]),int(a["route_id"]),day,a.get("start_latitude"),a.get("start_longitude"))
    reg("apply_distribution_route_optimization", "ذخیره ترتیب بهینه توقف‌های مسیر؛ نیازمند تأیید.",route_opt_schema,persist_optimize,"distribution.manage",write=True,high=True)
    reg("get_distribution_team_map", "نمایش موقعیت‌های زنده تیم؛ اطلاعات مکانی همکاران را برمی‌گرداند.",_schema({"plan_date":{"type":["string","null"],"format":"date"}}),lambda a,c:p3.get_team_map(c["db"],int(c["business_id"]),c["user_context"],date.fromisoformat(a["plan_date"]) if a.get("plan_date") else None))
    reg("get_distribution_offline_pack", "بسته داده آفلاین برای کاربر جاری؛ اطلاعات طبق مجوز و برنامه تخصیص‌شده محدود است.",_schema(),lambda a,c:field.build_offline_pack(c["db"],int(c["business_id"]),c["user_context"]),"distribution.operate")
    def user_day_trail(a,c):
        ctx=c["user_context"]
        if not base._can_see_team_distribution(ctx,int(c["business_id"])):
            from app.core.responses import ApiError
            raise ApiError("FORBIDDEN","Day trail requires manage or reports_team",http_status=403)
        base.assert_user_visible_for_ctx(c["db"],int(c["business_id"]),ctx,int(a["user_id"]))
        from app.core.business_calendar import business_today
        day=date.fromisoformat(a["day"]) if a.get("day") else business_today(int(c["business_id"]))
        return commerce.get_user_day_trail(c["db"],int(c["business_id"]),int(a["user_id"]),day)
    reg("get_distribution_user_day_trail","مسیر روزانه کاربر؛ فقط مدیر یا کاربر مجاز به گزارش تیم.",_schema({"user_id":{"type":"integer","minimum":1},"day":{"type":["string","null"],"format":"date"}},["user_id"]),user_day_trail,["distribution.manage","distribution.reports_team"])

    reg("run_distribution_setup_wizard", "راه‌اندازی افزونه توزیع، قلمرو، مسیر و تخصیص‌ها؛ ممکن است چند رکورد بسازد.", body_schema("SetupWizardPayload"), lambda a,c:field.run_setup_wizard(c["db"],int(c["business_id"]),c["user_context"].get_user_id() or 0,_payload("SetupWizardPayload",a)), "distribution.manage", write=True, high=True)
    reg("onboard_distribution_outlet", "ثبت مشتری جدید و افزودن آن به مسیر/پروفایل توزیع در صورت ارسال فیلدها.", body_schema("NewOutletPayload"), lambda a,c:field.onboard_new_outlet(c["db"],int(c["business_id"]),c["user_context"].get_user_id() or 0,_payload("NewOutletPayload",a)), "distribution.operate", write=True, high=True)

