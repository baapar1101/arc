"""MCP tools for wallet top-up, members, HScript CRUD, report templates, FX auto-sync, tax identity, marketplace, workflows."""
from __future__ import annotations

from app.services.ai.ai_mcp_tool_util import mcp_bid, mcp_commit, mcp_db, mcp_jsonable, mcp_run, mcp_schema, mcp_uid

EMPTY = mcp_schema({})
TOPUP = mcp_schema(
    {
        "amount": {"type": "number", "exclusiveMinimum": 0},
        "gateway_id": {"type": "integer", "minimum": 1},
    },
    ["amount", "gateway_id"],
)
INVITE = mcp_schema(
    {
        "email_or_phone": {"type": "string", "minLength": 5, "maxLength": 120},
        "membership_expires_at": {"type": ["string", "null"]},
    },
    ["email_or_phone"],
)
HS_LIST = mcp_schema({"status": {"type": "string", "enum": ["draft", "published", "archived"]}})
HS_CREATE = mcp_schema(
    {
        "title": {"type": "string", "minLength": 1, "maxLength": 160},
        "source_code": {"type": "string", "minLength": 1, "maxLength": 200000},
        "slug": {"type": ["string", "null"], "maxLength": 80},
        "description": {"type": ["string", "null"], "maxLength": 2000},
        "default_params": {"type": "object"},
    },
    ["title", "source_code"],
)
HS_UPDATE = mcp_schema(
    {
        "report_id": {"type": "integer", "minimum": 1},
        "title": {"type": "string", "minLength": 1, "maxLength": 160},
        "source_code": {"type": "string", "minLength": 1, "maxLength": 200000},
        "description": {"type": ["string", "null"], "maxLength": 2000},
        "default_params": {"type": "object"},
        "changelog": {"type": ["string", "null"], "maxLength": 500},
    },
    ["report_id"],
)
HS_ID = mcp_schema({"report_id": {"type": "integer", "minimum": 1}}, ["report_id"])
TPL_CREATE = mcp_schema(
    {
        "name": {"type": "string", "minLength": 1, "maxLength": 160},
        "module_key": {"type": "string", "minLength": 1, "maxLength": 64},
        "content_html": {"type": "string", "minLength": 1, "maxLength": 1000000},
        "subtype": {"type": ["string", "null"], "maxLength": 64},
        "description": {"type": ["string", "null"], "maxLength": 512},
        "engine": {"type": "string", "enum": ["jinja2", "builder", "template_v2"]},
        "paper_size": {"type": ["string", "null"], "maxLength": 32},
        "orientation": {"type": ["string", "null"], "enum": ["portrait", "landscape"]},
        "content_css": {"type": ["string", "null"]},
        "header_html": {"type": ["string", "null"]},
        "footer_html": {"type": ["string", "null"]},
    },
    ["name", "module_key", "content_html"],
)
TPL_UPDATE = mcp_schema(
    {
        "template_id": {"type": "integer", "minimum": 1},
        "name": {"type": "string", "minLength": 1, "maxLength": 160},
        "module_key": {"type": "string", "minLength": 1, "maxLength": 64},
        "content_html": {"type": "string", "minLength": 1},
        "subtype": {"type": ["string", "null"]},
        "description": {"type": ["string", "null"]},
        "engine": {"type": "string", "enum": ["jinja2", "builder", "template_v2"]},
        "status": {"type": "string", "enum": ["draft", "in_review", "approved", "published", "deprecated"]},
        "paper_size": {"type": ["string", "null"]},
        "orientation": {"type": ["string", "null"], "enum": ["portrait", "landscape"]},
        "content_css": {"type": ["string", "null"]},
        "header_html": {"type": ["string", "null"]},
        "footer_html": {"type": ["string", "null"]},
    },
    ["template_id"],
)
TPL_ID = mcp_schema({"template_id": {"type": "integer", "minimum": 1}}, ["template_id"])
FX_UPDATE = mcp_schema(
    {
        "enabled": {"type": "boolean"},
        "schedule_mode": {"type": "string", "enum": ["interval", "daily_times"]},
        "interval_hours": {"type": "integer", "enum": [1, 2, 3, 6, 12, 24]},
        "daily_times": {"type": "array", "maxItems": 12, "items": {"type": "string"}},
        "timezone": {"type": "string", "maxLength": 64},
        "skip_if_unchanged": {"type": "boolean"},
        "min_change_percent": {"type": "number", "minimum": 0},
        "block_if_stale": {"type": "boolean"},
        "stale_after_hours": {"type": "integer", "minimum": 1},
        "rules": {
            "type": "array",
            "maxItems": 40,
            "items": {
                "type": "object",
                "additionalProperties": False,
                "required": ["currency_id"],
                "properties": {
                    "currency_id": {"type": "integer", "minimum": 1},
                    "enabled": {"type": "boolean"},
                    "offset_type": {"type": "string"},
                    "offset_direction": {"type": "string"},
                    "offset_value": {"type": "number"},
                },
            },
        },
    }
)
TAX_UPDATE = mcp_schema(
    {
        "tax_memory_id": {"type": "string", "minLength": 3, "maxLength": 128},
        "economic_code": {"type": "string", "minLength": 3, "maxLength": 64},
        "sandbox_mode": {"type": "boolean"},
    }
)
PURCHASE = mcp_schema(
    {
        "plugin_id": {"type": "integer", "minimum": 1},
        "plan_id": {"type": "integer", "minimum": 1},
        "quantity": {"type": "integer", "minimum": 1, "maximum": 12},
    },
    ["plugin_id", "plan_id"],
)
PLUGIN_ID = mcp_schema({"plugin_id": {"type": "integer", "minimum": 1}}, ["plugin_id"])
WF_LIST = mcp_schema(
    {
        "search": {"type": "string", "maxLength": 80},
        "tag": {"type": "string", "maxLength": 40},
        "take": {"type": "integer", "minimum": 1, "maximum": 50},
        "skip": {"type": "integer", "minimum": 0},
    }
)
WF_INSTALL = mcp_schema(
    {"package_id": {"type": "integer", "minimum": 1}, "name": {"type": ["string", "null"], "maxLength": 255}},
    ["package_id"],
)
WF_PUBLISH = mcp_schema(
    {
        "workflow_id": {"type": "integer", "minimum": 1},
        "title": {"type": "string", "minLength": 1, "maxLength": 160},
        "short_description": {"type": ["string", "null"], "maxLength": 280},
        "long_description": {"type": ["string", "null"], "maxLength": 4000},
        "version_label": {"type": "string", "maxLength": 32},
        "changelog": {"type": ["string", "null"], "maxLength": 2000},
        "tags": {"type": "array", "maxItems": 12, "items": {"type": "string", "maxLength": 32}},
    },
    ["workflow_id", "title"],
)
WF_PKG = mcp_schema({"package_id": {"type": "integer", "minimum": 1}}, ["package_id"])


def _tpl_summary(t) -> dict:
    return {
        "id": t.id,
        "name": t.name,
        "module_key": t.module_key,
        "subtype": t.subtype,
        "status": t.status,
        "is_default": bool(t.is_default),
        "version": t.version,
    }


def create_wallet_top_up_handler(args, context):
    from app.services.wallet_service import create_top_up_request

    return mcp_jsonable(
        mcp_run(
            create_top_up_request,
            mcp_db(context),
            mcp_bid(context),
            mcp_uid(context),
            {"amount": args["amount"], "gateway_id": args["gateway_id"], "source": "mcp"},
        )
    )


def invite_business_user_handler(args, context):
    from adapters.api.v1.schemas import AddUserRequest
    from adapters.db.models.business import Business
    from adapters.db.models.user import User
    from adapters.db.repositories.business_permission_repo import BusinessPermissionRepository
    from sqlalchemy import func

    db = mcp_db(context)
    bid = mcp_bid(context)
    body = AddUserRequest(email_or_phone=str(args["email_or_phone"]), membership_expires_at=args.get("membership_expires_at"))
    business = db.get(Business, bid)
    if not business:
        raise ValueError("کسب‌وکار یافت نشد.")
    identifier = body.email_or_phone.strip()
    if "@" in identifier:
        user = db.query(User).filter(func.lower(User.email) == identifier.lower()).first()
    else:
        user = db.query(User).filter(User.mobile == identifier).first()
    if not user:
        raise ValueError("کاربری با این ایمیل یا موبایل ثبت نشده است؛ ابتدا باید در حسابیکس ثبت‌نام کند.")
    if user.id == business.owner_id:
        raise ValueError("این کاربر مالک کسب‌وکار است.")
    repo = BusinessPermissionRepository(db)
    if repo.get_by_user_and_business(user.id, bid):
        raise ValueError("این کاربر از قبل عضو کسب‌وکار است.")
    permission_obj = repo.create_or_update(
        user_id=user.id,
        business_id=bid,
        permissions={"join": True},
        membership_expires_at=body.membership_expires_at,
    )
    mcp_commit(context)
    return {
        "user_id": user.id,
        "permission_id": permission_obj.id,
        "role": "member",
        "email": user.email,
        "mobile": user.mobile,
    }


def list_hscript_reports_handler(args, context):
    from app.services.hscript_report_service import list_reports

    return mcp_jsonable(mcp_run(list_reports, mcp_db(context), mcp_bid(context), status=args.get("status")))


def get_hscript_report_handler(args, context):
    from app.services.hscript_report_service import get_report

    return mcp_jsonable(mcp_run(get_report, mcp_db(context), mcp_bid(context), int(args["report_id"])))


def create_hscript_report_handler(args, context):
    from app.services.hscript_report_service import create_report

    return mcp_jsonable(
        mcp_run(
            create_report,
            mcp_db(context),
            mcp_bid(context),
            user_id=mcp_uid(context),
            title=args["title"],
            source_code=args["source_code"],
            slug=args.get("slug"),
            description=args.get("description"),
            default_params=args.get("default_params"),
        )
    )


def update_hscript_report_handler(args, context):
    from app.services.hscript_report_service import update_report

    keys = {k: args[k] for k in ("title", "description", "source_code", "default_params", "changelog") if k in args}
    return mcp_jsonable(
        mcp_run(update_report, mcp_db(context), mcp_bid(context), int(args["report_id"]), user_id=mcp_uid(context), **keys)
    )


def publish_hscript_report_handler(args, context):
    from app.services.hscript_report_service import publish_report

    return mcp_jsonable(
        mcp_run(publish_report, mcp_db(context), mcp_bid(context), int(args["report_id"]), user_id=mcp_uid(context))
    )


def delete_hscript_report_handler(args, context):
    from app.services.hscript_report_service import delete_report

    return mcp_jsonable(
        mcp_run(delete_report, mcp_db(context), mcp_bid(context), int(args["report_id"]), user_id=mcp_uid(context))
    )


def create_report_template_handler(args, context):
    from app.services.report_template_service import ReportTemplateService

    payload = dict(args)
    payload["business_id"] = mcp_bid(context)
    entity = mcp_run(ReportTemplateService.create_template, mcp_db(context), payload, mcp_uid(context))
    return _tpl_summary(entity)


def update_report_template_handler(args, context):
    from app.services.report_template_service import ReportTemplateService

    payload = {k: v for k, v in args.items() if k != "template_id"}
    entity = mcp_run(
        ReportTemplateService.update_template,
        mcp_db(context),
        int(args["template_id"]),
        payload,
        mcp_bid(context),
    )
    return _tpl_summary(entity)


def delete_report_template_handler(args, context):
    from app.services.report_template_service import ReportTemplateService

    mcp_run(ReportTemplateService.delete_template, mcp_db(context), int(args["template_id"]), mcp_bid(context))
    return {"deleted": True, "template_id": int(args["template_id"])}


def get_fx_auto_sync_settings_handler(args, context):
    from app.services.business_fx_auto_sync_service import get_settings_payload

    return mcp_jsonable(mcp_run(get_settings_payload, mcp_db(context), mcp_bid(context)))


def update_fx_auto_sync_settings_handler(args, context):
    from app.services.business_fx_auto_sync_service import upsert_settings

    data = mcp_jsonable(mcp_run(upsert_settings, mcp_db(context), mcp_bid(context), mcp_uid(context), dict(args)))
    mcp_commit(context)
    return data


def preview_fx_auto_sync_handler(args, context):
    from app.services.business_fx_auto_sync_service import preview_auto_sync

    return mcp_jsonable(mcp_run(preview_auto_sync, mcp_db(context), mcp_bid(context)))


def run_fx_auto_sync_handler(args, context):
    from app.services.business_fx_auto_sync_service import run_auto_sync_for_business

    return mcp_jsonable(
        mcp_run(
            run_auto_sync_for_business,
            mcp_db(context),
            mcp_bid(context),
            triggered_by="mcp",
            actor_user_id=mcp_uid(context),
        )
    )


def update_tax_identity_settings_handler(args, context):
    from app.services.encryption_service import decrypt_private_key
    from app.services.tax_setting_service import get_tax_setting, serialize_tax_setting, upsert_tax_setting

    db = mcp_db(context)
    bid = mcp_bid(context)
    current = get_tax_setting(db, bid)
    if not current or not current.private_key:
        raise ValueError("کلید خصوصی مالیاتی در پنل تنظیم نشده است؛ از MCP کلید ارسال نمی‌شود.")
    private_key = current.private_key
    try:
        private_key = decrypt_private_key(private_key)
    except Exception:
        pass
    payload = {
        "tax_memory_id": args.get("tax_memory_id") or current.tax_memory_id,
        "economic_code": args.get("economic_code") or current.economic_code,
        "private_key": private_key,
        "sandbox_mode": args.get("sandbox_mode", current.sandbox_mode),
    }
    setting = mcp_run(upsert_tax_setting, db, business_id=bid, user_id=mcp_uid(context), payload=payload)
    mcp_commit(context)
    data = serialize_tax_setting(setting, bid, db=db)
    data.pop("private_key", None)
    data.pop("certificate", None)
    data.pop("public_key", None)
    data.pop("certificate_request", None)
    return mcp_jsonable(data)


def purchase_marketplace_plugin_handler(args, context):
    from app.services.marketplace_service import purchase_plugin

    return mcp_jsonable(
        mcp_run(
            purchase_plugin,
            mcp_db(context),
            business_id=mcp_bid(context),
            user_id=mcp_uid(context),
            payload={"plugin_id": args["plugin_id"], "plan_id": args["plan_id"], "quantity": args.get("quantity") or 1},
        )
    )


def start_marketplace_plugin_trial_handler(args, context):
    from app.services.marketplace_service import start_trial_plugin

    return mcp_jsonable(
        mcp_run(
            start_trial_plugin,
            mcp_db(context),
            business_id=mcp_bid(context),
            plugin_id=int(args["plugin_id"]),
            user_id=mcp_uid(context),
        )
    )


def list_workflow_marketplace_packages_handler(args, context):
    from app.services.workflow.workflow_marketplace_service import list_published_packages

    rows, total = mcp_run(
        list_published_packages,
        mcp_db(context),
        skip=int(args.get("skip") or 0),
        take=int(args.get("take") or 20),
        search=args.get("search"),
        tag=args.get("tag"),
    )
    items = []
    for p in rows:
        items.append(
            {
                "id": p.id,
                "title": p.title,
                "short_description": p.short_description,
                "version_label": p.version_label,
                "status": getattr(p.status, "value", p.status),
                "tags": p.tags or [],
                "install_count": p.install_count,
            }
        )
    return mcp_jsonable({"total": total, "items": items})


def install_workflow_marketplace_package_handler(args, context):
    from app.services.workflow.workflow_marketplace_service import install_package_to_business

    wf, _inst = mcp_run(
        install_package_to_business,
        mcp_db(context),
        package_id=int(args["package_id"]),
        target_business_id=mcp_bid(context),
        user_id=mcp_uid(context),
        new_name=args.get("name"),
    )
    mcp_commit(context)
    return {"workflow_id": wf.id, "name": wf.name, "status": getattr(wf.status, "value", wf.status)}


def publish_workflow_to_marketplace_handler(args, context):
    from app.services.workflow.workflow_marketplace_service import publish_package

    pkg = mcp_run(
        publish_package,
        mcp_db(context),
        business_id=mcp_bid(context),
        user_id=mcp_uid(context),
        workflow_id=int(args["workflow_id"]),
        title=str(args["title"]),
        short_description=args.get("short_description"),
        long_description=args.get("long_description"),
        tags=args.get("tags"),
        version_label=str(args.get("version_label") or "1.0.0"),
        changelog=args.get("changelog"),
    )
    mcp_commit(context)
    return {"package_id": pkg.id, "title": pkg.title, "status": getattr(pkg.status, "value", pkg.status)}


def unpublish_workflow_marketplace_package_handler(args, context):
    from app.services.workflow.workflow_marketplace_service import unpublish_package

    pkg = mcp_run(
        unpublish_package,
        mcp_db(context),
        package_id=int(args["package_id"]),
        business_id=mcp_bid(context),
        user_id=mcp_uid(context),
    )
    mcp_commit(context)
    return {"package_id": pkg.id, "status": getattr(pkg.status, "value", pkg.status)}


def register_mcp_remaining_ops_functions(registry) -> None:
    from app.services.ai.function_registry import AIFunction, AIRole

    roles = {AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN}
    registry.register(AIFunction(
        name="create_wallet_top_up",
        description="ایجاد درخواست افزایش اعتبار کیف‌پول و لینک درگاه. مبلغ از حساب بانکی کاربر کسر می‌شود. نیازمند تأیید.",
        parameters_schema=TOPUP,
        handler=create_wallet_top_up_handler,
        allowed_roles=roles,
        required_permissions=["wallet.write"],
        category="financial",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="invite_business_user",
        description="افزودن کاربر ثبت‌شده حسابیکس به کسب‌وکار با دسترسی join. نیازمند تأیید.",
        parameters_schema=INVITE,
        handler=invite_business_user_handler,
        allowed_roles=roles,
        required_permissions=["settings.users"],
        category="business",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="list_hscript_reports",
        description="گزارش‌های HScript ذخیره‌شده کسب‌وکار متصل بدون سورس کامل در لیست.",
        parameters_schema=HS_LIST,
        handler=list_hscript_reports_handler,
        allowed_roles=roles,
        required_permissions=["hscript.view"],
        category="hscript",
        is_readonly=True,
    ))
    registry.register(AIFunction(
        name="get_hscript_report",
        description="جزئیات و سورس یک گزارش HScript متعلق به کسب‌وکار متصل.",
        parameters_schema=HS_ID,
        handler=get_hscript_report_handler,
        allowed_roles=roles,
        required_permissions=["hscript.view"],
        category="hscript",
        is_readonly=True,
    ))
    registry.register(AIFunction(
        name="create_hscript_report",
        description="ذخیره گزارش HScript جدید. اسکریپت باید از نظر نحوی معتبر باشد. نیازمند تأیید.",
        parameters_schema=HS_CREATE,
        handler=create_hscript_report_handler,
        allowed_roles=roles,
        required_permissions=["hscript.write"],
        category="hscript",
        requires_approval=True,
        risk_level="medium",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="update_hscript_report",
        description="ویرایش عنوان یا سورس گزارش HScript. نیازمند تأیید.",
        parameters_schema=HS_UPDATE,
        handler=update_hscript_report_handler,
        allowed_roles=roles,
        required_permissions=["hscript.write"],
        category="hscript",
        requires_approval=True,
        risk_level="medium",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="publish_hscript_report",
        description="انتشار گزارش HScript برای اجرا. نیازمند تأیید.",
        parameters_schema=HS_ID,
        handler=publish_hscript_report_handler,
        allowed_roles=roles,
        required_permissions=["hscript.publish"],
        category="hscript",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="delete_hscript_report",
        description="حذف نرم گزارش HScript. نیازمند تأیید.",
        parameters_schema=HS_ID,
        handler=delete_hscript_report_handler,
        allowed_roles=roles,
        required_permissions=["hscript.write"],
        category="hscript",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="create_report_template",
        description="ایجاد قالب چاپ/گزارش HTML کسب‌وکار. نیازمند تأیید.",
        parameters_schema=TPL_CREATE,
        handler=create_report_template_handler,
        allowed_roles=roles,
        required_permissions=["report_templates.write"],
        category="report_templates",
        requires_approval=True,
        risk_level="medium",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="update_report_template",
        description="ویرایش قالب چاپ/گزارش کسب‌وکار متصل. نیازمند تأیید.",
        parameters_schema=TPL_UPDATE,
        handler=update_report_template_handler,
        allowed_roles=roles,
        required_permissions=["report_templates.write"],
        category="report_templates",
        requires_approval=True,
        risk_level="medium",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="delete_report_template",
        description="حذف قالب چاپ/گزارش کسب‌وکار متصل. نیازمند تأیید.",
        parameters_schema=TPL_ID,
        handler=delete_report_template_handler,
        allowed_roles=roles,
        required_permissions=["report_templates.write"],
        category="report_templates",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="get_fx_auto_sync_settings",
        description="تنظیمات زمان‌بندی خودکار نرخ تسعیر کسب‌وکار چندارزی.",
        parameters_schema=EMPTY,
        handler=get_fx_auto_sync_settings_handler,
        allowed_roles=roles,
        required_permissions=["currency_revaluation.view"],
        category="accounting",
        is_readonly=True,
    ))
    registry.register(AIFunction(
        name="update_fx_auto_sync_settings",
        description="ذخیره زمان‌بندی و آفست نرخ تسعیر خودکار. نیازمند تأیید.",
        parameters_schema=FX_UPDATE,
        handler=update_fx_auto_sync_settings_handler,
        allowed_roles=roles,
        required_permissions=["currency_revaluation.add"],
        category="accounting",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="preview_fx_auto_sync",
        description="پیش‌نمایش نرخ مرجع و نرخ نهایی پس از آفست، بدون ثبت.",
        parameters_schema=EMPTY,
        handler=preview_fx_auto_sync_handler,
        allowed_roles=roles,
        required_permissions=["currency_revaluation.view"],
        category="accounting",
        is_readonly=True,
    ))
    registry.register(AIFunction(
        name="run_fx_auto_sync",
        description="اجرای فوری همگام‌سازی نرخ تسعیر از منبع مرکزی. نیازمند تأیید.",
        parameters_schema=EMPTY,
        handler=run_fx_auto_sync_handler,
        allowed_roles=roles,
        required_permissions=["currency_revaluation.add"],
        category="accounting",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="update_tax_identity_settings",
        description="به‌روزرسانی شناسه حافظه، کد اقتصادی و sandbox مالیات. کلید خصوصی از MCP پذیرفته یا برگردانده نمی‌شود.",
        parameters_schema=TAX_UPDATE,
        handler=update_tax_identity_settings_handler,
        allowed_roles=roles,
        required_permissions=["moadian.manage_settings"],
        category="tax",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="purchase_marketplace_plugin",
        description="خرید افزونه از بازار با کسر از کیف‌پول کسب‌وکار. نیازمند تأیید.",
        parameters_schema=PURCHASE,
        handler=purchase_marketplace_plugin_handler,
        allowed_roles=roles,
        required_permissions=["marketplace.write"],
        category="marketplace",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="start_marketplace_plugin_trial",
        description="شروع دوره آزمایشی افزونه برای کسب‌وکار (یک‌بار). نیازمند تأیید.",
        parameters_schema=PLUGIN_ID,
        handler=start_marketplace_plugin_trial_handler,
        allowed_roles=roles,
        required_permissions=["marketplace.write"],
        category="marketplace",
        requires_approval=True,
        risk_level="medium",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="list_workflow_marketplace_packages",
        description="بسته‌های منتشرشده مخزن ورک‌فلو برای نصب در کسب‌وکار متصل.",
        parameters_schema=WF_LIST,
        handler=list_workflow_marketplace_packages_handler,
        allowed_roles=roles,
        required_permissions=["workflows.view"],
        category="workflow",
        is_readonly=True,
    ))
    registry.register(AIFunction(
        name="install_workflow_marketplace_package",
        description="نصب ورک‌فلو از مخزن به‌صورت پیش‌نویس در کسب‌وکار متصل. نیازمند تأیید.",
        parameters_schema=WF_INSTALL,
        handler=install_workflow_marketplace_package_handler,
        allowed_roles=roles,
        required_permissions=["workflows.add"],
        category="workflow",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="publish_workflow_to_marketplace",
        description="انتشار ورک‌فلو کسب‌وکار در مخزن. نیازمند تأیید.",
        parameters_schema=WF_PUBLISH,
        handler=publish_workflow_to_marketplace_handler,
        allowed_roles=roles,
        required_permissions=["workflows.edit"],
        category="workflow",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="unpublish_workflow_marketplace_package",
        description="خروج بسته ورک‌فلو مالک کسب‌وکار از انتشار عمومی. نیازمند تأیید.",
        parameters_schema=WF_PKG,
        handler=unpublish_workflow_marketplace_package_handler,
        allowed_roles=roles,
        required_permissions=["workflows.edit"],
        category="workflow",
        requires_approval=True,
        risk_level="medium",
        is_readonly=False,
    ))
