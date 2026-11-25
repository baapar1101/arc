"""MCP tools for tax providers, AI skills, MCP grants, CRM processes, AI billing."""
from __future__ import annotations

from app.services.ai.ai_mcp_tool_util import (
    mcp_bid,
    mcp_commit,
    mcp_db,
    mcp_jsonable,
    mcp_run,
    mcp_schema,
    mcp_uid,
)

EMPTY = mcp_schema({})
PROVIDER_SELECT = mcp_schema(
    {
        "provider_code": {"type": "string", "enum": ["moadian_direct", "fanava", "motamed_asa"]},
        "consent": {"type": "boolean"},
        "economic_code": {"type": ["string", "null"], "maxLength": 64},
    },
    ["provider_code"],
)
INVOICE_ID = mcp_schema({"invoice_id": {"type": "integer", "minimum": 1}}, ["invoice_id"])
MOTAMED_PAY = mcp_schema(
    {
        "invoice_id": {"type": "integer", "minimum": 1},
        "payments": {"type": "array", "maxItems": 40, "items": {"type": "object"}},
    },
    ["invoice_id", "payments"],
)
FANAVA_LIST = mcp_schema({"page": {"type": "integer", "minimum": 0}, "size": {"type": "integer", "minimum": 1, "maximum": 50}})
FANAVA_ID = mcp_schema({"fanava_invoice_id": {"type": "integer", "minimum": 1}}, ["fanava_invoice_id"])
SKILL_LIST = mcp_schema(
    {
        "search": {"type": "string", "maxLength": 80},
        "source_type": {"type": "string", "maxLength": 40},
        "is_official": {"type": "boolean"},
        "skip": {"type": "integer", "minimum": 0},
        "take": {"type": "integer", "minimum": 1, "maximum": 100},
    }
)
PKG_ID = mcp_schema({"package_id": {"type": "integer", "minimum": 1}}, ["package_id"])
ANTHROPIC = mcp_schema({"anthropic_skill_id": {"type": "string", "minLength": 1, "maxLength": 80}}, ["anthropic_skill_id"])
NATIVE = mcp_schema(
    {
        "skill_slug": {"type": "string", "minLength": 2, "maxLength": 80},
        "title": {"type": "string", "minLength": 1, "maxLength": 160},
        "description": {"type": "string", "minLength": 1, "maxLength": 2000},
        "skill_body": {"type": "string", "minLength": 1, "maxLength": 200000},
        "allowed_tool_names": {"type": "array", "maxItems": 80, "items": {"type": "string"}},
        "tags": {"type": "array", "maxItems": 12, "items": {"type": "string"}},
    },
    ["skill_slug", "title", "description", "skill_body"],
)
GIT = mcp_schema({"git_url": {"type": "string", "minLength": 12, "maxLength": 500}, "title": {"type": ["string", "null"], "maxLength": 160}}, ["git_url"])
ENABLE = mcp_schema(
    {
        "enable_ids": {"type": "array", "maxItems": 50, "items": {"type": "integer", "minimum": 1}},
        "disable_ids": {"type": "array", "maxItems": 50, "items": {"type": "integer", "minimum": 1}},
    }
)
PUBLISH = mcp_schema(
    {
        "package_id": {"type": "integer", "minimum": 1},
        "short_description": {"type": ["string", "null"], "maxLength": 280},
        "long_description": {"type": ["string", "null"], "maxLength": 4000},
        "tags": {"type": "array", "maxItems": 12, "items": {"type": "string"}},
        "version_label": {"type": "string", "maxLength": 32},
        "changelog": {"type": ["string", "null"], "maxLength": 2000},
        "price_amount": {"type": ["number", "null"], "minimum": 0},
        "currency_id": {"type": ["integer", "null"], "minimum": 1},
    },
    ["package_id"],
)
CONN_ID = mcp_schema({"connection_id": {"type": "integer", "minimum": 1}}, ["connection_id"])
CONN_PATCH = mcp_schema(
    {
        "connection_id": {"type": "integer", "minimum": 1},
        "tool_permissions": {"type": ["object", "array", "null"]},
        "enable_writes": {"type": ["boolean", "null"]},
        "unrestricted_tools": {"type": ["boolean", "null"]},
    },
    ["connection_id"],
)
PROC_LIST = mcp_schema(
    {
        "process_type": {"type": "string", "enum": ["lead_funnel", "sales_pipeline", "activity_type", "lead_source"]},
        "is_active": {"type": "boolean"},
    }
)
PROC_ID = mcp_schema({"definition_id": {"type": "integer", "minimum": 1}}, ["definition_id"])
PROC_CREATE = mcp_schema(
    {
        "process_type": {"type": "string", "enum": ["lead_funnel", "sales_pipeline", "activity_type", "lead_source"]},
        "code": {"type": "string", "minLength": 1, "maxLength": 50},
        "name": {"type": "string", "minLength": 1, "maxLength": 255},
        "description": {"type": ["string", "null"], "maxLength": 2000},
        "is_default": {"type": "boolean"},
        "is_active": {"type": "boolean"},
        "stages": {
            "type": "array",
            "maxItems": 40,
            "items": {
                "type": "object",
                "additionalProperties": False,
                "required": ["stage_code", "name", "order_index"],
                "properties": {
                    "stage_code": {"type": "string", "maxLength": 50},
                    "name": {"type": "string", "maxLength": 255},
                    "order_index": {"type": "integer", "minimum": 0},
                    "color": {"type": ["string", "null"], "maxLength": 20},
                    "is_win": {"type": "boolean"},
                    "is_lost": {"type": "boolean"},
                    "allow_transition_to": {"type": ["array", "null"], "items": {"type": "string"}},
                },
            },
        },
    },
    ["process_type", "code", "name"],
)
PROC_UPDATE = mcp_schema(
    {
        "definition_id": {"type": "integer", "minimum": 1},
        "name": {"type": "string", "minLength": 1, "maxLength": 255},
        "description": {"type": ["string", "null"]},
        "is_default": {"type": "boolean"},
        "is_active": {"type": "boolean"},
    },
    ["definition_id"],
)
AI_INV_LIST = mcp_schema(
    {
        "invoice_type": {"type": "string", "enum": ["subscription", "usage", "renewal"]},
        "limit": {"type": "integer", "minimum": 1, "maximum": 100},
        "skip": {"type": "integer", "minimum": 0},
    }
)
AI_INV_ID = mcp_schema({"invoice_id": {"type": "integer", "minimum": 1}}, ["invoice_id"])


def _ctx(context):
    user = context.get("user_context")
    if user is None:
        raise ValueError("هویت کاربر موجود نیست")
    return user


def _moadian(context):
    from app.core.moadian_plugin_dependency import ensure_moadian_plugin_active

    mcp_run(ensure_moadian_plugin_active, mcp_db(context), mcp_bid(context))


def get_tax_provider_handler(args, context):
    from app.services.tax_provider_service import get_business_provider_state

    _moadian(context)
    return mcp_jsonable(mcp_run(get_business_provider_state, mcp_db(context), mcp_bid(context)))


def select_tax_provider_handler(args, context):
    from app.core.moadian_plugin_dependency import ensure_moadian_plugin_active
    from app.services.motamed_asa_provider_service import MOTAMED_ASA_PROVIDER
    from app.services.tax_provider_service import select_business_provider
    from app.services.tax_setting_service import get_tax_setting, serialize_tax_setting

    db = mcp_db(context)
    bid = mcp_bid(context)
    mcp_run(ensure_moadian_plugin_active, db, bid)
    code = str(args["provider_code"]).strip().lower()
    enrollment = {}
    if args.get("economic_code"):
        enrollment["economic_code"] = str(args["economic_code"])
    result = mcp_run(
        select_business_provider,
        db,
        business_id=bid,
        provider_code=code,
        consent=bool(args.get("consent")),
        consented_by_user_id=mcp_uid(context),
        enrollment=enrollment,
    )
    mcp_commit(context)
    setting = get_tax_setting(db, bid)
    data = serialize_tax_setting(setting, business_id=bid, db=db)
    if isinstance(result, dict) and result.get("motamed_asa_onboarding"):
        data["motamed_asa_onboarding"] = result["motamed_asa_onboarding"]
    return mcp_jsonable(data)


def sync_motamed_asa_account_handler(args, context):
    from app.services.motamed_asa_provider_service import sync_motamed_asa_account

    _moadian(context)
    return mcp_jsonable(mcp_run(sync_motamed_asa_account, mcp_db(context), mcp_bid(context)))


def get_motamed_asa_invoice_payments_handler(args, context):
    from adapters.db.models.document import Document
    from app.services.motamed_asa_tax_submission_service import motamed_asa_invoice_payments

    _moadian(context)
    db = mcp_db(context)
    bid = mcp_bid(context)
    document = (
        db.query(Document).filter(Document.id == int(args["invoice_id"]), Document.business_id == bid).first()
    )
    if document is None:
        raise ValueError("فاکتور پیدا نشد.")
    return mcp_jsonable(mcp_run(motamed_asa_invoice_payments, db, bid, document))


def register_motamed_asa_invoice_payments_handler(args, context):
    from adapters.db.models.document import Document
    from app.services.motamed_asa_tax_submission_service import register_motamed_asa_payments

    _moadian(context)
    db = mcp_db(context)
    bid = mcp_bid(context)
    document = (
        db.query(Document).filter(Document.id == int(args["invoice_id"]), Document.business_id == bid).first()
    )
    if document is None:
        raise ValueError("فاکتور پیدا نشد.")
    result = mcp_run(register_motamed_asa_payments, db, bid, document, args.get("payments"))
    mcp_commit(context)
    return mcp_jsonable(result)


def sync_fanava_account_handler(args, context):
    from app.services.tax_provider_service import sync_business_fanava_account

    _moadian(context)
    return mcp_jsonable(mcp_run(sync_business_fanava_account, mcp_db(context), mcp_bid(context)))


def _fanava(context, fn):
    from app.services.tax_provider_service import fanava_business_call

    _moadian(context)
    return mcp_jsonable(mcp_run(fanava_business_call, mcp_db(context), mcp_bid(context), fn))


def list_fanava_invoices_handler(args, context):
    page = int(args.get("page") or 0)
    size = int(args.get("size") or 50)
    return _fanava(
        context,
        lambda client, token, account: client.list_invoices(token, int(account.cartable_id), page=page, size=size),
    )


def get_fanava_invoice_handler(args, context):
    fid = int(args["fanava_invoice_id"])
    return _fanava(context, lambda client, token, account: client.get_invoice(token, int(account.cartable_id), fid))


def check_fanava_invoice_status_handler(args, context):
    fid = int(args["fanava_invoice_id"])
    history = _fanava(context, lambda client, token, account: client.check_status(token, int(account.cartable_id), fid))
    return {"history": history}


def inquiry_fanava_invoice_status_handler(args, context):
    fid = int(args["fanava_invoice_id"])
    history = _fanava(context, lambda client, token, account: client.check_status(token, int(account.cartable_id), fid))
    latest = history[-1] if isinstance(history, list) and history else {}
    if str((latest or {}).get("status") or "").upper() != "SUCCESS":
        raise ValueError("استعلام نهایی فقط پس از موفقیت پردازش صورتحساب در فن‌آوا امکان‌پذیر است.")
    return _fanava(context, lambda client, token, account: client.inquiry_status(token, int(account.cartable_id), fid))


def test_tax_connection_stored_handler(args, context):
    from app.core.settings import get_settings
    from app.integrations.moadian.client import MoadianClient
    from app.services.tax_setting_health_service import run_extended_connection_test
    from app.services.tax_setting_service import (
        get_tax_setting,
        merge_tax_setting_for_test,
        validate_tax_setting_complete,
    )

    _moadian(context)
    db = mcp_db(context)
    bid = mcp_bid(context)
    stored = get_tax_setting(db, bid)
    if stored is None:
        raise ValueError("تنظیمات سامانه مودیان یافت نشد.")
    tax_setting = merge_tax_setting_for_test(stored, None, business_id=bid)
    missing = validate_tax_setting_complete(tax_setting)
    if missing:
        raise ValueError("تنظیمات مالیاتی ناقص است: " + ", ".join(missing))
    client = MoadianClient(settings=get_settings(), tax_setting=tax_setting)
    server_info = mcp_run(client.get_server_information)
    token = mcp_run(client.login)
    result = mcp_run(
        run_extended_connection_test,
        db,
        tax_setting,
        token=token,
        server_info=server_info if isinstance(server_info, dict) else {},
    )
    result["api_version"] = client.api_version
    return mcp_jsonable(result)


def list_ai_skill_marketplace_handler(args, context):
    from app.services.ai.ai_skill_service import list_marketplace_packages, package_to_dict

    db = mcp_db(context)
    take = int(args.get("take") or 20)
    skip = int(args.get("skip") or 0)
    rows, total = list_marketplace_packages(
        db,
        skip=skip,
        take=take,
        search=args.get("search"),
        source_type=args.get("source_type"),
        is_official=args.get("is_official"),
    )
    return mcp_jsonable(
        {
            "items": [package_to_dict(p, business_id=mcp_bid(context), db=db) for p in rows],
            "total": total,
            "skip": skip,
            "take": take,
        }
    )


def get_ai_skill_package_handler(args, context):
    from app.services.ai.ai_skill_service import get_package_for_business, package_to_dict

    pkg = get_package_for_business(mcp_db(context), int(args["package_id"]), mcp_bid(context))
    if not pkg:
        raise ValueError("بسته مهارت یافت نشد.")
    return mcp_jsonable(package_to_dict(pkg, include_body=True, business_id=mcp_bid(context), db=mcp_db(context)))


def list_installed_ai_skills_handler(args, context):
    from app.services.ai.ai_skill_service import install_to_dict, list_installed

    rows = list_installed(mcp_db(context), mcp_bid(context), enabled_only=False)
    return mcp_jsonable({"items": [install_to_dict(r, db=mcp_db(context)) for r in rows]})


def list_owned_ai_skills_handler(args, context):
    from app.services.ai.ai_skill_service import list_owned_packages, package_to_dict

    rows, total = list_owned_packages(mcp_db(context), mcp_bid(context), skip=0, take=50)
    return mcp_jsonable({"items": [package_to_dict(p, business_id=mcp_bid(context), db=mcp_db(context)) for p in rows], "total": total})


def install_ai_skill_handler(args, context):
    from app.services.ai.ai_skill_service import install_package, install_to_dict

    inst = mcp_run(
        install_package,
        mcp_db(context),
        business_id=mcp_bid(context),
        user_id=mcp_uid(context),
        package_id=int(args["package_id"]),
    )
    mcp_commit(context)
    return mcp_jsonable(install_to_dict(inst, db=mcp_db(context)))


def install_anthropic_ai_skill_handler(args, context):
    from app.services.ai.ai_skill_service import install_anthropic_prebuilt, install_to_dict

    inst = mcp_run(
        install_anthropic_prebuilt,
        mcp_db(context),
        business_id=mcp_bid(context),
        user_id=mcp_uid(context),
        anthropic_skill_id=str(args["anthropic_skill_id"]),
    )
    mcp_commit(context)
    return mcp_jsonable(install_to_dict(inst, db=mcp_db(context)))


def create_native_ai_skill_handler(args, context):
    from app.services.ai.ai_skill_service import create_native_skill, package_to_dict

    pkg = mcp_run(
        create_native_skill,
        mcp_db(context),
        business_id=mcp_bid(context),
        user_id=mcp_uid(context),
        skill_slug=str(args["skill_slug"]),
        title=str(args["title"]),
        description=str(args["description"]),
        skill_body=str(args["skill_body"]),
        allowed_tool_names=args.get("allowed_tool_names"),
        tags=args.get("tags"),
    )
    mcp_commit(context)
    return mcp_jsonable(package_to_dict(pkg, include_body=True))


def import_ai_skill_from_git_handler(args, context):
    from app.services.ai.ai_skill_service import import_skill_from_git, package_to_dict

    pkg = mcp_run(
        import_skill_from_git,
        mcp_db(context),
        business_id=mcp_bid(context),
        user_id=mcp_uid(context),
        git_url=str(args["git_url"]),
        title=args.get("title"),
    )
    mcp_commit(context)
    return mcp_jsonable(package_to_dict(pkg, include_body=True))


def purchase_ai_skill_handler(args, context):
    from app.services.ai.ai_skill_service import purchase_skill_package

    result = mcp_run(
        purchase_skill_package,
        mcp_db(context),
        business_id=mcp_bid(context),
        user_id=mcp_uid(context),
        package_id=int(args["package_id"]),
    )
    mcp_commit(context)
    return mcp_jsonable(result)


def set_ai_skills_enabled_handler(args, context):
    from app.services.ai.ai_skill_service import install_to_dict, set_installs_enabled

    changed = mcp_run(
        set_installs_enabled,
        mcp_db(context),
        business_id=mcp_bid(context),
        enable_ids=args.get("enable_ids"),
        disable_ids=args.get("disable_ids"),
    )
    mcp_commit(context)
    return mcp_jsonable({"updated": [install_to_dict(c, db=mcp_db(context)) for c in changed]})


def publish_ai_skill_handler(args, context):
    from app.services.ai.ai_skill_service import package_to_dict, publish_to_marketplace

    pkg = mcp_run(
        publish_to_marketplace,
        mcp_db(context),
        package_id=int(args["package_id"]),
        business_id=mcp_bid(context),
        user_id=mcp_uid(context),
        short_description=args.get("short_description"),
        long_description=args.get("long_description"),
        tags=args.get("tags"),
        version_label=str(args.get("version_label") or "1.0.0"),
        changelog=args.get("changelog"),
        price_amount=args.get("price_amount"),
        currency_id=args.get("currency_id"),
    )
    mcp_commit(context)
    return mcp_jsonable(package_to_dict(pkg))


def get_ai_skill_publisher_revenue_handler(args, context):
    from app.services.ai.ai_skill_service import get_publisher_revenue

    return mcp_jsonable(get_publisher_revenue(mcp_db(context), mcp_bid(context), skip=0, take=20))


def list_anthropic_skill_catalog_handler(args, context):
    from app.services.ai.ai_skill_service import ANTHROPIC_PREBUILT_CATALOG

    return {"items": list(ANTHROPIC_PREBUILT_CATALOG)}


def list_mcp_connections_handler(args, context):
    from app.core.ai_mcp_plugin_dependency import get_ai_mcp_plugin_access, public_ai_mcp_plugin_access
    from app.services.ai.ai_mcp_connections import list_managed_connections

    db = mcp_db(context)
    bid = mcp_bid(context)
    items = list_managed_connections(db, _ctx(context), bid)
    for item in items:
        item.pop("token", None)
        item.pop("secret", None)
        item.pop("key_hash", None)
    return mcp_jsonable(
        {
            "items": items,
            "plugin": public_ai_mcp_plugin_access(get_ai_mcp_plugin_access(db, bid)),
            "viewer_is_owner": bool(getattr(_ctx(context), "is_business_owner", lambda *_: False)(bid)),
        }
    )


def get_mcp_connection_catalog_handler(args, context):
    from app.services.ai.ai_mcp_connections import connection_catalog_payload

    return mcp_jsonable(mcp_run(connection_catalog_payload, mcp_db(context), _ctx(context), int(args["connection_id"])))


def update_mcp_connection_handler(args, context):
    from app.services.ai.ai_mcp_connections import update_connection_permissions

    result = mcp_run(
        update_connection_permissions,
        mcp_db(context),
        _ctx(context),
        int(args["connection_id"]),
        tool_permissions_raw=args.get("tool_permissions"),
        enable_writes_raw=args.get("enable_writes"),
        unrestricted_tools_raw=args.get("unrestricted_tools"),
    )
    mcp_commit(context)
    return mcp_jsonable(result)


def revoke_mcp_connection_handler(args, context):
    from app.services.ai.ai_mcp_connections import revoke_connection

    result = mcp_run(revoke_connection, mcp_db(context), _ctx(context), int(args["connection_id"]))
    mcp_commit(context)
    return mcp_jsonable(result)


def revoke_all_mcp_connections_handler(args, context):
    from app.services.ai.ai_mcp_connections import revoke_all_connections

    result = mcp_run(revoke_all_connections, mcp_db(context), _ctx(context), mcp_bid(context))
    mcp_commit(context)
    return mcp_jsonable(result)


def list_crm_process_definitions_handler(args, context):
    from adapters.api.v1.crm import _process_to_dict
    from adapters.db.models.crm import CrmProcessDefinition
    from sqlalchemy.orm import selectinload

    q = (
        mcp_db(context)
        .query(CrmProcessDefinition)
        .options(selectinload(CrmProcessDefinition.stages))
        .filter(CrmProcessDefinition.business_id == mcp_bid(context))
    )
    if args.get("process_type"):
        q = q.filter(CrmProcessDefinition.process_type == args["process_type"])
    if args.get("is_active") is not None:
        q = q.filter(CrmProcessDefinition.is_active == bool(args["is_active"]))
    items = q.order_by(CrmProcessDefinition.process_type, CrmProcessDefinition.code).all()
    return mcp_jsonable({"items": [_process_to_dict(p) for p in items]})


def get_crm_process_definition_handler(args, context):
    from adapters.api.v1.crm import _process_to_dict
    from adapters.db.models.crm import CrmProcessDefinition
    from sqlalchemy import and_

    proc = (
        mcp_db(context)
        .query(CrmProcessDefinition)
        .filter(and_(CrmProcessDefinition.id == int(args["definition_id"]), CrmProcessDefinition.business_id == mcp_bid(context)))
        .first()
    )
    if not proc:
        raise ValueError("فرایند یافت نشد.")
    return mcp_jsonable(_process_to_dict(proc))


def create_crm_process_definition_handler(args, context):
    from adapters.api.v1.crm import _process_to_dict
    from adapters.api.v1.schema_models.crm import CrmProcessDefinitionCreate
    from adapters.db.models.crm import CrmProcessDefinition, CrmProcessStage
    from sqlalchemy import and_

    db = mcp_db(context)
    bid = mcp_bid(context)
    body = CrmProcessDefinitionCreate(
        process_type=args["process_type"],
        code=args["code"],
        name=args["name"],
        description=args.get("description"),
        is_default=bool(args.get("is_default")),
        is_active=args.get("is_active") is not False,
        stages=args.get("stages") or [],
    )
    existing = (
        db.query(CrmProcessDefinition)
        .filter(
            and_(
                CrmProcessDefinition.business_id == bid,
                CrmProcessDefinition.process_type == body.process_type,
                CrmProcessDefinition.code == body.code,
            )
        )
        .first()
    )
    if existing:
        raise ValueError(f"فرایند با کد {body.code} از قبل وجود دارد.")
    proc = CrmProcessDefinition(
        business_id=bid,
        process_type=body.process_type,
        code=body.code,
        name=body.name,
        description=body.description,
        is_default=body.is_default,
        is_active=body.is_active,
        created_by_user_id=mcp_uid(context),
    )
    db.add(proc)
    db.flush()
    for s in body.stages or []:
        db.add(
            CrmProcessStage(
                process_definition_id=proc.id,
                stage_code=s.stage_code,
                name=s.name,
                order_index=s.order_index,
                color=s.color,
                is_win=s.is_win,
                is_lost=s.is_lost,
                allow_transition_to=s.allow_transition_to,
            )
        )
    mcp_commit(context)
    db.refresh(proc)
    return mcp_jsonable(_process_to_dict(proc))


def update_crm_process_definition_handler(args, context):
    from adapters.api.v1.crm import _process_to_dict
    from adapters.db.models.crm import CrmProcessDefinition
    from sqlalchemy import and_

    db = mcp_db(context)
    proc = (
        db.query(CrmProcessDefinition)
        .filter(and_(CrmProcessDefinition.id == int(args["definition_id"]), CrmProcessDefinition.business_id == mcp_bid(context)))
        .first()
    )
    if not proc:
        raise ValueError("فرایند یافت نشد.")
    if "name" in args:
        proc.name = args["name"]
    if "description" in args:
        proc.description = args["description"]
    if "is_default" in args:
        proc.is_default = bool(args["is_default"])
    if "is_active" in args:
        proc.is_active = bool(args["is_active"])
    mcp_commit(context)
    db.refresh(proc)
    return mcp_jsonable(_process_to_dict(proc))


def delete_crm_process_definition_handler(args, context):
    from adapters.db.models.crm import CrmProcessDefinition, Deal, Lead
    from sqlalchemy import and_

    db = mcp_db(context)
    bid = mcp_bid(context)
    definition_id = int(args["definition_id"])
    proc = (
        db.query(CrmProcessDefinition)
        .filter(and_(CrmProcessDefinition.id == definition_id, CrmProcessDefinition.business_id == bid))
        .first()
    )
    if not proc:
        raise ValueError("فرایند یافت نشد.")
    if db.query(Lead).filter(Lead.process_definition_id == definition_id).first():
        raise ValueError("این فرایند روی سرنخ استفاده شده و قابل حذف نیست.")
    if db.query(Deal).filter(Deal.process_definition_id == definition_id).first():
        raise ValueError("این فرایند روی فرصت استفاده شده و قابل حذف نیست.")
    db.delete(proc)
    mcp_commit(context)
    return {"deleted": True, "definition_id": definition_id}


def cancel_ai_subscription_handler(args, context):
    from datetime import datetime

    from adapters.db.repositories.ai_subscription_repository import AISubscriptionRepository

    db = mcp_db(context)
    sub = AISubscriptionRepository(db).get_active_subscription(user_id=mcp_uid(context), business_id=mcp_bid(context))
    if not sub:
        return {"cancelled": False, "message": "اشتراک فعالی برای لغو یافت نشد"}
    now = datetime.utcnow()
    sub.is_active = False
    sub.period_end = now
    sub.expires_at = now
    sub.updated_at = now
    mcp_commit(context)
    return {"cancelled": True, "id": sub.id}


def list_ai_invoices_handler(args, context):
    from adapters.db.repositories.ai_invoice_repository import AIInvoiceRepository

    invoices = AIInvoiceRepository(mcp_db(context)).get_business_invoices(
        business_id=mcp_bid(context),
        invoice_type=args.get("invoice_type"),
        limit=int(args.get("limit") or 50),
        skip=int(args.get("skip") or 0),
    )
    return mcp_jsonable(
        {
            "items": [
                {
                    "id": inv.id,
                    "invoice_type": inv.invoice_type,
                    "amount": float(inv.amount),
                    "currency": inv.currency,
                    "status": inv.status,
                    "plan_id": inv.plan_id,
                    "created_at": inv.created_at.isoformat() if inv.created_at else None,
                    "paid_at": inv.paid_at.isoformat() if inv.paid_at else None,
                }
                for inv in invoices
            ]
        }
    )


def pay_ai_invoice_handler(args, context):
    from app.services.ai.ai_invoice_service import pay_ai_invoice_from_wallet

    result = mcp_run(
        pay_ai_invoice_from_wallet,
        mcp_db(context),
        invoice_id=int(args["invoice_id"]),
        business_id=mcp_bid(context),
        user_id=mcp_uid(context),
    )
    mcp_commit(context)
    return mcp_jsonable(result)


def register_mcp_ops3_functions(registry) -> None:
    from app.services.ai.function_registry import AIFunction, AIRole

    roles = {AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN}
    registry.register(AIFunction(name="get_tax_provider", description="وضعیت ارائه‌دهنده ارسال مالیات کسب‌وکار متصل بدون کلید و رمز.", parameters_schema=EMPTY, handler=get_tax_provider_handler, allowed_roles=roles, required_permissions=["moadian.manage_settings"], category="tax", is_readonly=True))
    registry.register(AIFunction(name="select_tax_provider", description="انتخاب ارائه‌دهنده ارسال مالیات (مودیان مستقیم، فن‌آوا، معتمد آسا). کلید و رمز پذیرفته نمی‌شود. نیازمند تأیید.", parameters_schema=PROVIDER_SELECT, handler=select_tax_provider_handler, allowed_roles=roles, required_permissions=["moadian.manage_settings"], category="tax", requires_approval=True, risk_level="high", is_readonly=False))
    registry.register(AIFunction(name="sync_motamed_asa_account", description="همگام‌سازی حساب معتمد آسا با تنظیمات ذخیره‌شده. نیازمند تأیید.", parameters_schema=EMPTY, handler=sync_motamed_asa_account_handler, allowed_roles=roles, required_permissions=["moadian.manage_settings"], category="tax", requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="get_motamed_asa_invoice_payments", description="پرداخت‌های ثبت‌شده فاکتور در معتمد آسا برای فاکتور کسب‌وکار متصل.", parameters_schema=INVOICE_ID, handler=get_motamed_asa_invoice_payments_handler, allowed_roles=roles, required_permissions=["moadian.operate"], category="tax", is_readonly=True))
    registry.register(AIFunction(name="register_motamed_asa_invoice_payments", description="ثبت پرداخت فاکتور در معتمد آسا. نیازمند تأیید.", parameters_schema=MOTAMED_PAY, handler=register_motamed_asa_invoice_payments_handler, allowed_roles=roles, required_permissions=["moadian.operate"], category="tax", requires_approval=True, risk_level="high", is_readonly=False))
    registry.register(AIFunction(name="sync_fanava_account", description="همگام‌سازی حساب فن‌آوا با تنظیمات ذخیره‌شده. نیازمند تأیید.", parameters_schema=EMPTY, handler=sync_fanava_account_handler, allowed_roles=roles, required_permissions=["moadian.manage_settings"], category="tax", requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="list_fanava_invoices", description="صورتحساب‌های کارتابل فن‌آوای کسب‌وکار متصل؛ حداکثر ۵۰ در صفحه.", parameters_schema=FANAVA_LIST, handler=list_fanava_invoices_handler, allowed_roles=roles, required_permissions=["moadian.operate"], category="tax", is_readonly=True))
    registry.register(AIFunction(name="get_fanava_invoice", description="جزئیات یک صورتحساب فن‌آوا متعلق به کارتابل کسب‌وکار متصل.", parameters_schema=FANAVA_ID, handler=get_fanava_invoice_handler, allowed_roles=roles, required_permissions=["moadian.operate"], category="tax", is_readonly=True))
    registry.register(AIFunction(name="check_fanava_invoice_status", description="تاریخچه وضعیت صورتحساب فن‌آوا را می‌خواند.", parameters_schema=FANAVA_ID, handler=check_fanava_invoice_status_handler, allowed_roles=roles, required_permissions=["moadian.operate"], category="tax", requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="inquiry_fanava_invoice_status", description="استعلام نهایی صورتحساب فن‌آوا پس از موفقیت پردازش. نیازمند تأیید.", parameters_schema=FANAVA_ID, handler=inquiry_fanava_invoice_status_handler, allowed_roles=roles, required_permissions=["moadian.operate"], category="tax", requires_approval=True, risk_level="high", is_readonly=False))
    registry.register(AIFunction(name="test_tax_connection_stored", description="تست اتصال سامانه مودیان فقط با تنظیمات ذخیره‌شده؛ کلید خصوصی از MCP پذیرفته نمی‌شود.", parameters_schema=EMPTY, handler=test_tax_connection_stored_handler, allowed_roles=roles, required_permissions=["moadian.manage_settings"], category="tax", requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="list_ai_skill_marketplace", description="مهارت‌های منتشرشده مارکت‌پلیس هوش مصنوعی برای نصب در کسب‌وکار متصل.", parameters_schema=SKILL_LIST, handler=list_ai_skill_marketplace_handler, allowed_roles=roles, required_permissions=["settings.join"], category="business", is_readonly=True))
    registry.register(AIFunction(name="get_ai_skill_package", description="جزئیات و بدنه یک بسته مهارت متعلق یا قابل نصب برای کسب‌وکار متصل.", parameters_schema=PKG_ID, handler=get_ai_skill_package_handler, allowed_roles=roles, required_permissions=["settings.join"], category="business", is_readonly=True))
    registry.register(AIFunction(name="list_installed_ai_skills", description="مهارت‌های نصب‌شده روی کسب‌وکار متصل.", parameters_schema=EMPTY, handler=list_installed_ai_skills_handler, allowed_roles=roles, required_permissions=["settings.join"], category="business", is_readonly=True))
    registry.register(AIFunction(name="list_owned_ai_skills", description="مهارت‌های مالکیت کسب‌وکار برای انتشار در مارکت‌پلیس.", parameters_schema=EMPTY, handler=list_owned_ai_skills_handler, allowed_roles=roles, required_permissions=["settings.join"], category="business", is_readonly=True))
    registry.register(AIFunction(name="list_anthropic_skill_catalog", description="کاتالوگ مهارت‌های ازپیش‌ساخته Anthropic قابل نصب.", parameters_schema=EMPTY, handler=list_anthropic_skill_catalog_handler, allowed_roles=roles, required_permissions=["settings.join"], category="business", is_readonly=True))
    registry.register(AIFunction(name="install_ai_skill", description="نصب بسته مهارت در کسب‌وکار متصل. نیازمند تأیید.", parameters_schema=PKG_ID, handler=install_ai_skill_handler, allowed_roles=roles, required_permissions=["settings.join"], category="business", requires_approval=True, risk_level="high", is_readonly=False))
    registry.register(AIFunction(name="install_anthropic_ai_skill", description="نصب مهارت ازپیش‌ساخته Anthropic در کسب‌وکار. نیازمند تأیید.", parameters_schema=ANTHROPIC, handler=install_anthropic_ai_skill_handler, allowed_roles=roles, required_permissions=["settings.join"], category="business", requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="create_native_ai_skill", description="ایجاد مهارت بومی حسابیکس با متن دستورالعمل. نیازمند تأیید.", parameters_schema=NATIVE, handler=create_native_ai_skill_handler, allowed_roles=roles, required_permissions=["settings.join"], category="business", requires_approval=True, risk_level="high", is_readonly=False))
    registry.register(AIFunction(name="import_ai_skill_from_git", description="ورود مهارت از مخزن عمومی GitHub. نیازمند تأیید.", parameters_schema=GIT, handler=import_ai_skill_from_git_handler, allowed_roles=roles, required_permissions=["settings.join"], category="business", requires_approval=True, risk_level="high", is_readonly=False))
    registry.register(AIFunction(name="purchase_ai_skill", description="خرید مهارت پولی از کیف‌پول کسب‌وکار قبل از نصب. نیازمند تأیید.", parameters_schema=PKG_ID, handler=purchase_ai_skill_handler, allowed_roles=roles, required_permissions=["settings.join"], category="business", requires_approval=True, risk_level="high", is_readonly=False))
    registry.register(AIFunction(name="set_ai_skills_enabled", description="فعال یا غیرفعال کردن مهارت‌های نصب‌شده. نیازمند تأیید.", parameters_schema=ENABLE, handler=set_ai_skills_enabled_handler, allowed_roles=roles, required_permissions=["settings.join"], category="business", requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="publish_ai_skill", description="ارسال مهارت مالک کسب‌وکار به بررسی مارکت‌پلیس. نیازمند تأیید.", parameters_schema=PUBLISH, handler=publish_ai_skill_handler, allowed_roles=roles, required_permissions=["settings.join"], category="business", requires_approval=True, risk_level="high", is_readonly=False))
    registry.register(AIFunction(name="get_ai_skill_publisher_revenue", description="گزارش درآمد ناشر مهارت‌های کسب‌وکار متصل.", parameters_schema=EMPTY, handler=get_ai_skill_publisher_revenue_handler, allowed_roles=roles, required_permissions=["settings.join"], category="business", is_readonly=True))
    registry.register(AIFunction(name="list_mcp_connections", description="اتصال‌های MCP کسب‌وکار متصل بدون توکن یا هش کلید.", parameters_schema=EMPTY, handler=list_mcp_connections_handler, allowed_roles=roles, required_permissions=["settings.join"], category="business", is_readonly=True))
    registry.register(AIFunction(name="get_mcp_connection_catalog", description="کاتالوگ ابزار قابل اعطا برای یک اتصال MCP متعلق به کسب‌وکار.", parameters_schema=CONN_ID, handler=get_mcp_connection_catalog_handler, allowed_roles=roles, required_permissions=["settings.join"], category="business", is_readonly=True))
    registry.register(AIFunction(name="update_mcp_connection", description="تغییر دسترسی ابزار یا نوشتن یک اتصال MCP. توکن جدید صادر نمی‌شود. نیازمند تأیید.", parameters_schema=CONN_PATCH, handler=update_mcp_connection_handler, allowed_roles=roles, required_permissions=["settings.join"], category="business", requires_approval=True, risk_level="high", is_readonly=False))
    registry.register(AIFunction(name="revoke_mcp_connection", description="لغو یک اتصال MCP کسب‌وکار متصل. نیازمند تأیید.", parameters_schema=CONN_ID, handler=revoke_mcp_connection_handler, allowed_roles=roles, required_permissions=["settings.join"], category="business", requires_approval=True, risk_level="high", is_readonly=False))
    registry.register(AIFunction(name="revoke_all_mcp_connections", description="لغو همه اتصال‌های MCP کسب‌وکار متصل. نیازمند تأیید.", parameters_schema=EMPTY, handler=revoke_all_mcp_connections_handler, allowed_roles=roles, required_permissions=["settings.join"], category="business", requires_approval=True, risk_level="high", is_readonly=False))
    registry.register(AIFunction(name="list_crm_process_definitions", description="فهرست فرایندهای CRM کسب‌وکار شامل فانل سرنخ و پایپلاین فروش.", parameters_schema=PROC_LIST, handler=list_crm_process_definitions_handler, allowed_roles=roles, required_permissions=["crm.view"], category="crm", is_readonly=True))
    registry.register(AIFunction(name="get_crm_process_definition", description="جزئیات و مراحل یک فرایند CRM متعلق به کسب‌وکار متصل.", parameters_schema=PROC_ID, handler=get_crm_process_definition_handler, allowed_roles=roles, required_permissions=["crm.view"], category="crm", is_readonly=True))
    registry.register(AIFunction(name="create_crm_process_definition", description="تعریف فرایند CRM جدید با مراحل. نیازمند تأیید.", parameters_schema=PROC_CREATE, handler=create_crm_process_definition_handler, allowed_roles=roles, required_permissions=["crm.write"], category="crm", requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="update_crm_process_definition", description="ویرایش نام، توضیح یا وضعیت فرایند CRM. نیازمند تأیید.", parameters_schema=PROC_UPDATE, handler=update_crm_process_definition_handler, allowed_roles=roles, required_permissions=["crm.write"], category="crm", requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="delete_crm_process_definition", description="حذف فرایند CRM بدون سرنخ یا فرصت وابسته. نیازمند تأیید.", parameters_schema=PROC_ID, handler=delete_crm_process_definition_handler, allowed_roles=roles, required_permissions=["crm.write"], category="crm", requires_approval=True, risk_level="high", is_readonly=False))
    registry.register(AIFunction(name="cancel_ai_subscription", description="لغو اشتراک فعال هوش مصنوعی همین کسب‌وکار و کاربر. نیازمند تأیید.", parameters_schema=EMPTY, handler=cancel_ai_subscription_handler, allowed_roles=roles, required_permissions=["settings.join"], category="business", requires_approval=True, risk_level="high", is_readonly=False))
    registry.register(AIFunction(name="list_ai_invoices", description="صورتحساب‌های هوش مصنوعی کسب‌وکار متصل.", parameters_schema=AI_INV_LIST, handler=list_ai_invoices_handler, allowed_roles=roles, required_permissions=["settings.join"], category="business", is_readonly=True))
    registry.register(AIFunction(name="pay_ai_invoice", description="پرداخت صورتحساب هوش مصنوعی از کیف‌پول کسب‌وکار. نیازمند تأیید.", parameters_schema=AI_INV_ID, handler=pay_ai_invoice_handler, allowed_roles=roles, required_permissions=["settings.join"], category="business", requires_approval=True, risk_level="high", is_readonly=False))
