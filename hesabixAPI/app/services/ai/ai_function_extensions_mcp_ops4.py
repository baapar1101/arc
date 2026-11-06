"""MCP tools for Woo opening inventory, Basalam extras, HScript ops, wallet, person share, table prefs."""
from __future__ import annotations

from app.services.ai.ai_mcp_tool_util import (
    mcp_await,
    mcp_bid,
    mcp_commit,
    mcp_db,
    mcp_jsonable,
    mcp_run,
    mcp_schema,
    mcp_uid,
)

EMPTY = mcp_schema({})
PAYLOAD = mcp_schema({"payload": {"type": "object"}})
PERSON_ID = mcp_schema({"person_id": {"type": "integer", "minimum": 1}}, ["person_id"])
PERSON_SHARE = mcp_schema(
    {
        "person_id": {"type": "integer", "minimum": 1},
        "expires_in_hours": {"type": ["integer", "null"], "minimum": 1, "maximum": 720},
        "max_view_count": {"type": ["integer", "null"], "minimum": 1, "maximum": 1000},
        "replace_existing": {"type": "boolean"},
        "include_ledger": {"type": "boolean"},
        "include_invoices": {"type": "boolean"},
        "include_invoice_lines": {"type": "boolean"},
        "documents_limit": {"type": "integer", "minimum": 10, "maximum": 200},
    },
    ["person_id"],
)
TABLE_ID = mcp_schema({"table_id": {"type": "string", "minLength": 1, "maxLength": 255}}, ["table_id"])
TABLE_SAVE = mcp_schema(
    {
        "table_id": {"type": "string", "minLength": 1, "maxLength": 255},
        "settings": {"type": "object"},
    },
    ["table_id", "settings"],
)
WALLET_SETTINGS = mcp_schema(
    {
        "mode": {"type": "string", "enum": ["manual", "auto"]},
        "frequency": {"type": ["string", "null"], "enum": ["daily", "weekly"]},
        "threshold_amount": {"type": ["number", "null"], "minimum": 0},
        "min_reserve": {"type": ["number", "null"], "minimum": 0},
        "default_bank_account_id": {"type": ["integer", "null"], "minimum": 1},
    }
)
PAYOUT_LIST = mcp_schema(
    {"skip": {"type": "integer", "minimum": 0}, "limit": {"type": "integer", "minimum": 1, "maximum": 100}}
)
PAYOUT_CREATE = mcp_schema(
    {
        "amount": {"type": "number", "exclusiveMinimum": 0},
        "bank_account_id": {"type": "integer", "minimum": 1},
        "description": {"type": "string", "maxLength": 400},
        "schedule_type": {"type": "string", "maxLength": 40},
    },
    ["amount", "bank_account_id"],
)
PAYOUT_ID = mcp_schema({"payout_id": {"type": "integer", "minimum": 1}}, ["payout_id"])
HS_ID = mcp_schema({"report_id": {"type": "integer", "minimum": 1}}, ["report_id"])
HS_PARAM = mcp_schema(
    {
        "source_code": {"type": ["string", "null"], "maxLength": 200000},
        "default_params": {"type": "object"},
        "params": {"type": "object"},
    }
)
HS_VER = mcp_schema(
    {"report_id": {"type": "integer", "minimum": 1}, "version_id": {"type": "integer", "minimum": 1}},
    ["report_id", "version_id"],
)
HS_RESTORE = mcp_schema(
    {
        "report_id": {"type": "integer", "minimum": 1},
        "version_id": {"type": "integer", "minimum": 1},
        "changelog": {"type": ["string", "null"], "maxLength": 500},
    },
    ["report_id", "version_id"],
)
HS_RUNS = mcp_schema(
    {"report_id": {"type": "integer", "minimum": 1}, "limit": {"type": "integer", "minimum": 1, "maximum": 100}},
    ["report_id"],
)
HS_RUN = mcp_schema(
    {
        "report_id": {"type": "integer", "minimum": 1},
        "params": {"type": "object"},
        "preview": {"type": "boolean"},
        "persist": {"type": "boolean"},
    },
    ["report_id"],
)
HS_SCHED_LIST = mcp_schema({"report_id": {"type": "integer", "minimum": 1}})
HS_SCHED_CREATE = mcp_schema(
    {
        "report_id": {"type": "integer", "minimum": 1},
        "title": {"type": ["string", "null"], "maxLength": 255},
        "enabled": {"type": "boolean"},
        "schedule_mode": {"type": "string", "enum": ["simple", "cron"]},
        "simple_repeat": {"type": "string", "maxLength": 32},
        "simple_time": {"type": "string", "maxLength": 8},
        "simple_weekday": {"type": "integer", "minimum": 0, "maximum": 6},
        "simple_interval": {"type": "integer", "minimum": 1, "maximum": 23},
        "cron_expression": {"type": ["string", "null"], "maxLength": 120},
        "timezone": {"type": "string", "maxLength": 64},
        "output_format": {"type": "string", "enum": ["pdf", "excel", "json"]},
        "channels": {"type": "array", "maxItems": 8, "items": {"type": "string"}},
        "recipient_user_ids": {"type": "array", "maxItems": 40, "items": {"type": "integer", "minimum": 1}},
        "params": {"type": "object"},
    },
    ["report_id"],
)
HS_SCHED_UPDATE = mcp_schema(
    {
        "schedule_id": {"type": "integer", "minimum": 1},
        "title": {"type": ["string", "null"], "maxLength": 255},
        "enabled": {"type": "boolean"},
        "schedule_mode": {"type": "string", "enum": ["simple", "cron"]},
        "simple_repeat": {"type": "string", "maxLength": 32},
        "simple_time": {"type": "string", "maxLength": 8},
        "simple_weekday": {"type": "integer", "minimum": 0, "maximum": 6},
        "simple_interval": {"type": "integer", "minimum": 1, "maximum": 23},
        "cron_expression": {"type": ["string", "null"], "maxLength": 120},
        "timezone": {"type": "string", "maxLength": 64},
        "output_format": {"type": "string", "enum": ["pdf", "excel", "json"]},
        "channels": {"type": "array", "maxItems": 8, "items": {"type": "string"}},
        "recipient_user_ids": {"type": "array", "maxItems": 40, "items": {"type": "integer", "minimum": 1}},
        "params": {"type": "object"},
    },
    ["schedule_id"],
)
HS_SCHED_ID = mcp_schema({"schedule_id": {"type": "integer", "minimum": 1}}, ["schedule_id"])
BASALAM_DLQ = mcp_schema(
    {
        "all": {"type": "boolean"},
        "dlq_ids": {"type": "array", "maxItems": 200, "items": {"type": "integer", "minimum": 1}},
    }
)
BASALAM_PAY = mcp_schema({"verify_remote": {"type": "boolean"}})
BASALAM_CHAT = mcp_schema(
    {
        "conversation_id": {"type": "integer", "minimum": 1},
        "body": {"type": "string", "minLength": 1, "maxLength": 4000},
        "chat_id": {"type": ["string", "integer", "null"]},
    },
    ["conversation_id", "body"],
)


def _woo(context) -> None:
    from app.core.woocommerce_plugin_dependency import check_woocommerce_plugin_active

    if not check_woocommerce_plugin_active(mcp_db(context), mcp_bid(context)):
        raise ValueError("افزونه ووکامرس برای این کسب‌وکار فعال نیست")


def _basalam(context) -> None:
    from app.core.basalam_plugin_dependency import check_basalam_plugin_active

    if not check_basalam_plugin_active(mcp_db(context), mcp_bid(context)):
        raise ValueError("افزونه باسلام برای این کسب‌وکار فعال نیست")


def _person(context, person_id: int):
    from adapters.db.models.person import Person

    row = (
        mcp_db(context)
        .query(Person)
        .filter(Person.id == int(person_id), Person.business_id == mcp_bid(context))
        .first()
    )
    if row is None:
        raise ValueError("شخص در این کسب‌وکار یافت نشد")
    return row


def _payout(context, payout_id: int):
    from adapters.db.models.wallet import WalletPayout

    row = mcp_db(context).query(WalletPayout).filter(WalletPayout.id == int(payout_id)).first()
    if row is None:
        raise ValueError("درخواست تسویه یافت نشد")
    if int(row.business_id) != mcp_bid(context):
        raise ValueError("این درخواست تسویه متعلق به کسب‌وکار متصل نیست")
    return row


def _sched_body(args) -> dict:
    keys = (
        "title",
        "enabled",
        "schedule_mode",
        "simple_repeat",
        "simple_time",
        "simple_weekday",
        "simple_interval",
        "cron_expression",
        "timezone",
        "output_format",
        "channels",
        "recipient_user_ids",
        "params",
    )
    return {k: args[k] for k in keys if k in args}


def get_woocommerce_opening_inventory_status_handler(args, context):
    from app.services.woocommerce_integration_service import control_opening_inventory_status

    _woo(context)
    return mcp_jsonable(mcp_run(control_opening_inventory_status, mcp_db(context), mcp_bid(context)))


def get_woocommerce_opening_inventory_accounts_handler(args, context):
    from app.services.woocommerce_integration_service import control_opening_inventory_accounts

    _woo(context)
    return mcp_jsonable(mcp_run(control_opening_inventory_accounts, mcp_db(context), mcp_bid(context)))


def preview_woocommerce_opening_inventory_handler(args, context):
    from app.services.woocommerce_integration_service import post_control_opening_inventory_preview

    _woo(context)
    return mcp_jsonable(
        mcp_run(post_control_opening_inventory_preview, mcp_db(context), mcp_bid(context), args.get("payload") or {})
    )


def prepare_woocommerce_opening_inventory_handler(args, context):
    from app.services.woocommerce_integration_service import post_control_opening_inventory_prepare

    _woo(context)
    return mcp_jsonable(
        mcp_run(post_control_opening_inventory_prepare, mcp_db(context), mcp_bid(context), args.get("payload") or {})
    )


def batch_woocommerce_opening_inventory_handler(args, context):
    from app.services.woocommerce_integration_service import post_control_opening_inventory_batch

    _woo(context)
    return mcp_jsonable(
        mcp_run(post_control_opening_inventory_batch, mcp_db(context), mcp_bid(context), args.get("payload") or {})
    )


def finalize_woocommerce_opening_inventory_handler(args, context):
    from app.services.woocommerce_integration_service import post_control_opening_inventory_finalize

    _woo(context)
    return mcp_jsonable(
        mcp_run(post_control_opening_inventory_finalize, mcp_db(context), mcp_bid(context), args.get("payload") or {})
    )


def cancel_woocommerce_opening_inventory_handler(args, context):
    from app.services.woocommerce_integration_service import post_control_opening_inventory_cancel

    _woo(context)
    return mcp_jsonable(
        mcp_run(post_control_opening_inventory_cancel, mcp_db(context), mcp_bid(context), args.get("payload") or {})
    )


def get_basalam_currency_readiness_handler(args, context):
    from app.services.basalam_integration_service import get_basalam_currency_readiness

    _basalam(context)
    return mcp_jsonable(mcp_run(get_basalam_currency_readiness, mcp_db(context), mcp_bid(context)))


def retry_basalam_product_publish_handler(args, context):
    from app.services.basalam_integration_service import retry_failed_product_publishes

    _basalam(context)
    return mcp_jsonable(
        mcp_run(
            retry_failed_product_publishes,
            mcp_db(context),
            mcp_bid(context),
            args.get("payload") or {},
            user_id=mcp_uid(context),
        )
    )


def clear_basalam_product_conflicts_handler(args, context):
    from app.services.basalam_integration_service import clear_product_conflicts

    _basalam(context)
    return mcp_jsonable(mcp_run(clear_product_conflicts, mcp_db(context), mcp_bid(context)))


def sync_basalam_unverified_payments_handler(args, context):
    from app.services.basalam_integration_service import sync_unverified_payments

    _basalam(context)
    verify = args.get("verify_remote")
    return mcp_jsonable(
        mcp_run(
            sync_unverified_payments,
            db=mcp_db(context),
            business_id=mcp_bid(context),
            user_id=mcp_uid(context),
            verify_remote=bool(verify) if verify is not None else None,
        )
    )


def clear_basalam_dead_letter_handler(args, context):
    from app.services.basalam_integration_service import clear_sync_dead_letter

    _basalam(context)
    if args.get("all") is True:
        return mcp_jsonable(mcp_run(clear_sync_dead_letter, mcp_db(context), mcp_bid(context), mode="all"))
    ids = args.get("dlq_ids")
    if isinstance(ids, list) and ids:
        return mcp_jsonable(
            mcp_run(clear_sync_dead_letter, mcp_db(context), mcp_bid(context), mode="ids", dlq_ids=ids)
        )
    raise ValueError('باید all=true یا dlq_ids غیرخالی ارسال شود')


def sync_basalam_inbound_chats_handler(args, context):
    from app.services.basalam_integration_service import sync_inbound_chat_messages

    _basalam(context)
    return mcp_jsonable(
        mcp_run(
            sync_inbound_chat_messages,
            db=mcp_db(context),
            business_id=mcp_bid(context),
            payload=args.get("payload") or {},
            user_id=mcp_uid(context),
        )
    )


def reply_basalam_chat_handler(args, context):
    from app.services.basalam_integration_service import send_chat_reply_to_basalam

    _basalam(context)
    result = mcp_await(
        send_chat_reply_to_basalam(
            db=mcp_db(context),
            business_id=mcp_bid(context),
            conversation_id=int(args["conversation_id"]),
            body=str(args["body"]),
            user_id=mcp_uid(context),
            basalam_chat_id=args.get("chat_id"),
        )
    )
    return mcp_jsonable(result)


def get_person_share_link_handler(args, context):
    from app.services.person_share_link_service import get_active_share_link_for_person, serialize_share_link

    person = _person(context, args["person_id"])
    link = get_active_share_link_for_person(mcp_db(context), person.business_id, person.id)
    return {"link": mcp_jsonable(serialize_share_link(link, db=mcp_db(context)))}


def create_person_share_link_handler(args, context):
    from app.services.person_share_link_service import create_share_link, serialize_share_link

    person = _person(context, args["person_id"])
    options = {
        "include_ledger": args.get("include_ledger", True),
        "include_invoices": args.get("include_invoices", True),
        "include_invoice_lines": args.get("include_invoice_lines", True),
        "documents_limit": int(args.get("documents_limit") or 50),
    }
    link = mcp_run(
        create_share_link,
        mcp_db(context),
        business_id=person.business_id,
        person_id=person.id,
        user_id=mcp_uid(context),
        expires_in_hours=args.get("expires_in_hours"),
        max_view_count=args.get("max_view_count"),
        options=options,
        replace_existing=bool(args.get("replace_existing", True)),
    )
    return mcp_jsonable(serialize_share_link(link, db=mcp_db(context)))


def revoke_person_share_link_handler(args, context):
    from app.services.person_share_link_service import revoke_share_link

    person = _person(context, args["person_id"])
    revoked = mcp_run(
        revoke_share_link,
        mcp_db(context),
        business_id=person.business_id,
        person_id=person.id,
        user_id=mcp_uid(context),
    )
    return {"revoked": bool(revoked)}


def get_data_table_column_settings_handler(args, context):
    from app.services.data_table_user_settings_service import get_column_settings, validate_table_id

    table_id = mcp_run(validate_table_id, str(args["table_id"]))
    settings = get_column_settings(
        mcp_db(context), business_id=mcp_bid(context), user_id=mcp_uid(context), table_id=table_id
    )
    return mcp_jsonable({"settings": settings})


def save_data_table_column_settings_handler(args, context):
    from app.services.data_table_user_settings_service import save_column_settings, validate_table_id

    table_id = mcp_run(validate_table_id, str(args["table_id"]))
    settings = args.get("settings")
    if not isinstance(settings, dict):
        raise ValueError("settings باید شیء باشد")
    data = mcp_run(
        save_column_settings,
        mcp_db(context),
        business_id=mcp_bid(context),
        user_id=mcp_uid(context),
        table_id=table_id,
        settings=settings,
    )
    return mcp_jsonable(data)


def delete_data_table_column_settings_handler(args, context):
    from app.services.data_table_user_settings_service import delete_column_settings, validate_table_id

    table_id = mcp_run(validate_table_id, str(args["table_id"]))
    deleted = mcp_run(
        delete_column_settings,
        mcp_db(context),
        business_id=mcp_bid(context),
        user_id=mcp_uid(context),
        table_id=table_id,
    )
    return {"deleted": bool(deleted)}


def get_wallet_settings_handler(args, context):
    from app.services.wallet_service import get_business_wallet_settings

    return mcp_jsonable(mcp_run(get_business_wallet_settings, mcp_db(context), mcp_bid(context)))


def update_wallet_settings_handler(args, context):
    from app.services.wallet_service import update_business_wallet_settings

    data = mcp_run(update_business_wallet_settings, mcp_db(context), mcp_bid(context), args)
    mcp_commit(context)
    return mcp_jsonable(data)


def list_wallet_payouts_handler(args, context):
    from app.services.wallet_service import list_wallet_payouts_admin

    return mcp_jsonable(
        mcp_run(
            list_wallet_payouts_admin,
            mcp_db(context),
            business_id=mcp_bid(context),
            skip=int(args.get("skip") or 0),
            limit=int(args.get("limit") or 50),
        )
    )


def create_wallet_payout_handler(args, context):
    from app.services.wallet_service import create_payout_request

    data = mcp_run(create_payout_request, mcp_db(context), mcp_bid(context), mcp_uid(context), args)
    mcp_commit(context)
    return mcp_jsonable(data)


def approve_wallet_payout_handler(args, context):
    from app.services.wallet_service import approve_payout_request

    _payout(context, args["payout_id"])
    data = mcp_run(approve_payout_request, mcp_db(context), int(args["payout_id"]), mcp_uid(context))
    mcp_commit(context)
    return mcp_jsonable(data)


def cancel_wallet_payout_handler(args, context):
    from app.services.wallet_service import cancel_payout_request

    _payout(context, args["payout_id"])
    data = mcp_run(cancel_payout_request, mcp_db(context), int(args["payout_id"]), mcp_uid(context))
    mcp_commit(context)
    return mcp_jsonable(data)


def run_wallet_auto_settle_handler(args, context):
    from app.services.wallet_service import run_auto_settlement

    data = mcp_run(run_auto_settlement, mcp_db(context), mcp_bid(context), mcp_uid(context))
    mcp_commit(context)
    return mcp_jsonable(data)


def get_hscript_plan_handler(args, context):
    from app.services import hscript_report_service as svc

    return mcp_jsonable(mcp_run(svc.get_plan_status, mcp_db(context), mcp_bid(context)))


def get_hscript_catalog_handler(args, context):
    from app.services import hscript_report_service as svc

    return mcp_jsonable(mcp_run(svc.get_catalog))


def list_hscript_recipes_handler(args, context):
    from app.services import hscript_report_service as svc

    return mcp_jsonable(mcp_run(svc.list_recipes))


def infer_hscript_param_schema_handler(args, context):
    from app.services import hscript_report_service as svc

    return mcp_jsonable(
        mcp_run(
            svc.infer_report_param_schema,
            source_code=args.get("source_code"),
            default_params=args.get("default_params"),
            params=args.get("params"),
        )
    )


def archive_hscript_report_handler(args, context):
    from app.services import hscript_report_service as svc

    return mcp_jsonable(
        mcp_run(svc.archive_report, mcp_db(context), mcp_bid(context), int(args["report_id"]), user_id=mcp_uid(context))
    )


def list_hscript_report_versions_handler(args, context):
    from app.services import hscript_report_service as svc

    return mcp_jsonable(mcp_run(svc.list_versions, mcp_db(context), mcp_bid(context), int(args["report_id"])))


def get_hscript_report_version_handler(args, context):
    from app.services import hscript_report_service as svc

    return mcp_jsonable(
        mcp_run(svc.get_version, mcp_db(context), mcp_bid(context), int(args["report_id"]), int(args["version_id"]))
    )


def restore_hscript_report_version_handler(args, context):
    from app.services import hscript_report_service as svc

    return mcp_jsonable(
        mcp_run(
            svc.restore_version,
            mcp_db(context),
            mcp_bid(context),
            int(args["report_id"]),
            int(args["version_id"]),
            user_id=mcp_uid(context),
            changelog=args.get("changelog"),
        )
    )


def list_hscript_report_runs_handler(args, context):
    from app.services import hscript_report_service as svc

    return mcp_jsonable(
        mcp_run(
            svc.list_runs,
            mcp_db(context),
            mcp_bid(context),
            int(args["report_id"]),
            limit=int(args.get("limit") or 30),
        )
    )


def run_hscript_report_handler(args, context):
    from app.services import hscript_report_service as svc

    preview = bool(args.get("preview"))
    persist = False if preview else bool(args.get("persist", True))
    result = mcp_run(
        svc.run_report,
        mcp_db(context),
        mcp_bid(context),
        user_id=mcp_uid(context),
        report_id=int(args["report_id"]),
        params=args.get("params") if isinstance(args.get("params"), dict) else {},
        fiscal_year_id=getattr(context.get("user_context"), "fiscal_year_id", None),
        preview=preview,
        persist=persist,
    )
    spec = result.get("spec") if isinstance(result, dict) else None
    if isinstance(spec, dict):
        blocks = spec.get("blocks") or []
        if isinstance(blocks, list) and len(blocks) > 40:
            result = {**result, "spec": {**spec, "blocks": blocks[:40], "_truncated": True}}
    return mcp_jsonable(result)


def list_hscript_schedules_handler(args, context):
    from app.services import hscript_schedule_service as sched_svc

    return mcp_jsonable(
        mcp_run(sched_svc.list_schedules, mcp_db(context), mcp_bid(context), report_id=args.get("report_id"))
    )


def create_hscript_schedule_handler(args, context):
    from app.services import hscript_schedule_service as sched_svc

    return mcp_jsonable(
        mcp_run(
            sched_svc.create_schedule,
            mcp_db(context),
            mcp_bid(context),
            user_id=mcp_uid(context),
            report_id=int(args["report_id"]),
            data=_sched_body(args),
        )
    )


def update_hscript_schedule_handler(args, context):
    from app.services import hscript_schedule_service as sched_svc

    return mcp_jsonable(
        mcp_run(
            sched_svc.update_schedule,
            mcp_db(context),
            mcp_bid(context),
            int(args["schedule_id"]),
            user_id=mcp_uid(context),
            data=_sched_body(args),
        )
    )


def delete_hscript_schedule_handler(args, context):
    from app.services import hscript_schedule_service as sched_svc

    return mcp_jsonable(mcp_run(sched_svc.delete_schedule, mcp_db(context), mcp_bid(context), int(args["schedule_id"])))


def run_hscript_schedule_now_handler(args, context):
    from app.services import hscript_schedule_service as sched_svc

    row = mcp_run(sched_svc._get_schedule, mcp_db(context), mcp_bid(context), int(args["schedule_id"]))
    return mcp_jsonable(mcp_run(sched_svc.run_schedule_now, mcp_db(context), row, triggered_by="manual"))


def register_mcp_ops4_functions(registry) -> None:
    from app.services.ai.function_registry import AIFunction, AIRole

    roles = {AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN}
    registry.register(AIFunction(name="get_woocommerce_opening_inventory_status", description="وضعیت پل موجودی اول دوره ووکامرس برای کسب‌وکار متصل. افزونه باید فعال باشد.", parameters_schema=EMPTY, handler=get_woocommerce_opening_inventory_status_handler, allowed_roles=roles, required_permissions=["woocommerce.view"], category="integration", is_readonly=True))
    registry.register(AIFunction(name="get_woocommerce_opening_inventory_accounts", description="حساب‌های قابل استفاده در موجودی اول دوره ووکامرس کسب‌وکار متصل.", parameters_schema=EMPTY, handler=get_woocommerce_opening_inventory_accounts_handler, allowed_roles=roles, required_permissions=["woocommerce.view"], category="integration", is_readonly=True))
    registry.register(AIFunction(name="preview_woocommerce_opening_inventory", description="پیش‌نمایش سند موجودی اول دوره از پل ووکامرس بدون ثبت نهایی.", parameters_schema=PAYLOAD, handler=preview_woocommerce_opening_inventory_handler, allowed_roles=roles, required_permissions=["woocommerce.manage"], category="integration", requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="prepare_woocommerce_opening_inventory", description="آماده‌سازی دسته‌های موجودی اول دوره ووکامرس. نیازمند تأیید.", parameters_schema=PAYLOAD, handler=prepare_woocommerce_opening_inventory_handler, allowed_roles=roles, required_permissions=["woocommerce.manage"], category="integration", requires_approval=True, risk_level="high", is_readonly=False))
    registry.register(AIFunction(name="batch_woocommerce_opening_inventory", description="ارسال یک دسته از موجودی اول دوره به ووکامرس. نیازمند تأیید.", parameters_schema=PAYLOAD, handler=batch_woocommerce_opening_inventory_handler, allowed_roles=roles, required_permissions=["woocommerce.manage"], category="integration", requires_approval=True, risk_level="high", is_readonly=False))
    registry.register(AIFunction(name="finalize_woocommerce_opening_inventory", description="نهایی‌سازی موجودی اول دوره ووکامرس و ثبت در حسابیکس. نیازمند تأیید.", parameters_schema=PAYLOAD, handler=finalize_woocommerce_opening_inventory_handler, allowed_roles=roles, required_permissions=["woocommerce.manage"], category="integration", requires_approval=True, risk_level="high", is_readonly=False))
    registry.register(AIFunction(name="cancel_woocommerce_opening_inventory", description="لغو فرآیند موجودی اول دوره ووکامرس. نیازمند تأیید.", parameters_schema=PAYLOAD, handler=cancel_woocommerce_opening_inventory_handler, allowed_roles=roles, required_permissions=["woocommerce.manage"], category="integration", requires_approval=True, risk_level="high", is_readonly=False))
    registry.register(AIFunction(name="get_basalam_currency_readiness", description="آمادگی ارز و واحد پولی باسلام در برابر ارز پایه کسب‌وکار متصل.", parameters_schema=EMPTY, handler=get_basalam_currency_readiness_handler, allowed_roles=roles, required_permissions=["basalam.view"], category="integration", is_readonly=True))
    registry.register(AIFunction(name="retry_basalam_product_publish", description="تلاش مجدد انتشار کالاهای ناموفق باسلام. نیازمند تأیید.", parameters_schema=PAYLOAD, handler=retry_basalam_product_publish_handler, allowed_roles=roles, required_permissions=["basalam.sync"], category="integration", requires_approval=True, risk_level="high", is_readonly=False))
    registry.register(AIFunction(name="clear_basalam_product_conflicts", description="پاک کردن همه تعارض‌های کالای باسلام کسب‌وکار. نیازمند تأیید.", parameters_schema=EMPTY, handler=clear_basalam_product_conflicts_handler, allowed_roles=roles, required_permissions=["basalam.sync"], category="integration", requires_approval=True, risk_level="high", is_readonly=False))
    registry.register(AIFunction(name="sync_basalam_unverified_payments", description="همگام پرداخت‌های تأییدنشده باسلام. نیازمند تأیید.", parameters_schema=BASALAM_PAY, handler=sync_basalam_unverified_payments_handler, allowed_roles=roles, required_permissions=["basalam.sync"], category="integration", requires_approval=True, risk_level="high", is_readonly=False))
    registry.register(AIFunction(name="clear_basalam_dead_letter", description="پاک کردن صف مرده همگام باسلام با all یا dlq_ids. نیازمند تأیید.", parameters_schema=BASALAM_DLQ, handler=clear_basalam_dead_letter_handler, allowed_roles=roles, required_permissions=["basalam.manage"], category="integration", requires_approval=True, risk_level="high", is_readonly=False))
    registry.register(AIFunction(name="sync_basalam_inbound_chats", description="دریافت پیام‌های ورودی چت باسلام به کسب‌وکار متصل. نیازمند تأیید.", parameters_schema=PAYLOAD, handler=sync_basalam_inbound_chats_handler, allowed_roles=roles, required_permissions=["basalam.sync"], category="integration", requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="reply_basalam_chat", description="ارسال پاسخ به گفتگوی باسلام. نیازمند تأیید.", parameters_schema=BASALAM_CHAT, handler=reply_basalam_chat_handler, allowed_roles=roles, required_permissions=["basalam.manage"], category="integration", requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="get_person_share_link", description="وضعیت لینک عمومی کارت حساب شخص متعلق به کسب‌وکار متصل.", parameters_schema=PERSON_ID, handler=get_person_share_link_handler, allowed_roles=roles, required_permissions=["people.view"], category="persons", is_readonly=True))
    registry.register(AIFunction(name="create_person_share_link", description="ایجاد یا جایگزینی لینک عمومی کارت حساب شخص. URL عمومی می‌سازد. نیازمند تأیید.", parameters_schema=PERSON_SHARE, handler=create_person_share_link_handler, allowed_roles=roles, required_permissions=["people.write"], category="persons", requires_approval=True, risk_level="high", is_readonly=False))
    registry.register(AIFunction(name="revoke_person_share_link", description="لغو لینک عمومی فعال کارت حساب شخص. نیازمند تأیید.", parameters_schema=PERSON_ID, handler=revoke_person_share_link_handler, allowed_roles=roles, required_permissions=["people.write"], category="persons", requires_approval=True, risk_level="high", is_readonly=False))
    registry.register(AIFunction(name="get_data_table_column_settings", description="تنظیمات ستون جدول ذخیره‌شده برای همین کاربر و کسب‌وکار.", parameters_schema=TABLE_ID, handler=get_data_table_column_settings_handler, allowed_roles=roles, required_permissions=["settings.view"], category="business", is_readonly=True))
    registry.register(AIFunction(name="save_data_table_column_settings", description="ذخیره ترتیب و نمایش ستون‌های یک جدول برای همین کاربر. نیازمند تأیید.", parameters_schema=TABLE_SAVE, handler=save_data_table_column_settings_handler, allowed_roles=roles, required_permissions=["settings.view"], category="business", requires_approval=True, risk_level="low", is_readonly=False))
    registry.register(AIFunction(name="delete_data_table_column_settings", description="حذف تنظیم ستون جدول و بازگشت به پیش‌فرض. نیازمند تأیید.", parameters_schema=TABLE_ID, handler=delete_data_table_column_settings_handler, allowed_roles=roles, required_permissions=["settings.view"], category="business", requires_approval=True, risk_level="low", is_readonly=False))
    registry.register(AIFunction(name="get_wallet_settings", description="تنظیمات تسویه خودکار کیف‌پول کسب‌وکار متصل.", parameters_schema=EMPTY, handler=get_wallet_settings_handler, allowed_roles=roles, required_permissions=["wallet.view"], category="financial", is_readonly=True))
    registry.register(AIFunction(name="update_wallet_settings", description="ویرایش حالت دستی/خودکار، آستانه و حساب بانکی پیش‌فرض تسویه. نیازمند تأیید.", parameters_schema=WALLET_SETTINGS, handler=update_wallet_settings_handler, allowed_roles=roles, required_permissions=["wallet.write"], category="financial", requires_approval=True, risk_level="high", is_readonly=False))
    registry.register(AIFunction(name="list_wallet_payouts", description="درخواست‌های تسویه کیف‌پول همین کسب‌وکار.", parameters_schema=PAYOUT_LIST, handler=list_wallet_payouts_handler, allowed_roles=roles, required_permissions=["wallet.view"], category="financial", is_readonly=True))
    registry.register(AIFunction(name="create_wallet_payout", description="ایجاد درخواست تسویه به حساب بانکی کسب‌وکار و قفل مبلغ. نیازمند تأیید.", parameters_schema=PAYOUT_CREATE, handler=create_wallet_payout_handler, allowed_roles=roles, required_permissions=["wallet.write"], category="financial", requires_approval=True, risk_level="high", is_readonly=False))
    registry.register(AIFunction(name="approve_wallet_payout", description="تأیید درخواست تسویه متعلق به کسب‌وکار متصل. نیازمند تأیید.", parameters_schema=PAYOUT_ID, handler=approve_wallet_payout_handler, allowed_roles=roles, required_permissions=["wallet.write"], category="financial", requires_approval=True, risk_level="high", is_readonly=False))
    registry.register(AIFunction(name="cancel_wallet_payout", description="لغو درخواست تسویه و بازگشت مبلغ به مانده قابل برداشت. نیازمند تأیید.", parameters_schema=PAYOUT_ID, handler=cancel_wallet_payout_handler, allowed_roles=roles, required_permissions=["wallet.write"], category="financial", requires_approval=True, risk_level="high", is_readonly=False))
    registry.register(AIFunction(name="run_wallet_auto_settle", description="اجرای فوری تسویه خودکار طبق تنظیمات ذخیره‌شده. نیازمند تأیید.", parameters_schema=EMPTY, handler=run_wallet_auto_settle_handler, allowed_roles=roles, required_permissions=["wallet.write"], category="financial", requires_approval=True, risk_level="high", is_readonly=False))
    registry.register(AIFunction(name="get_hscript_plan", description="وضعیت پلن، سقف گزارش و زمان‌بندی HScript کسب‌وکار متصل.", parameters_schema=EMPTY, handler=get_hscript_plan_handler, allowed_roles=roles, required_permissions=["hscript.view"], category="hscript", is_readonly=True))
    registry.register(AIFunction(name="get_hscript_catalog", description="کاتالوگ ماژول‌ها، متدها و دستورپخت‌های زبان HScript.", parameters_schema=EMPTY, handler=get_hscript_catalog_handler, allowed_roles=roles, required_permissions=["hscript.view"], category="hscript", is_readonly=True))
    registry.register(AIFunction(name="list_hscript_recipes", description="فهرست دستورپخت‌های آماده گزارش HScript.", parameters_schema=EMPTY, handler=list_hscript_recipes_handler, allowed_roles=roles, required_permissions=["hscript.view"], category="hscript", is_readonly=True))
    registry.register(AIFunction(name="infer_hscript_param_schema", description="استنتاج schema فرم پارامتر از سورس HScript بدون اجرا.", parameters_schema=HS_PARAM, handler=infer_hscript_param_schema_handler, allowed_roles=roles, required_permissions=["hscript.view"], category="hscript", is_readonly=True))
    registry.register(AIFunction(name="archive_hscript_report", description="بایگانی گزارش HScript منتشرشده. نیازمند تأیید.", parameters_schema=HS_ID, handler=archive_hscript_report_handler, allowed_roles=roles, required_permissions=["hscript.publish"], category="hscript", requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="list_hscript_report_versions", description="نسخه‌های ذخیره‌شده یک گزارش HScript کسب‌وکار متصل.", parameters_schema=HS_ID, handler=list_hscript_report_versions_handler, allowed_roles=roles, required_permissions=["hscript.view"], category="hscript", is_readonly=True))
    registry.register(AIFunction(name="get_hscript_report_version", description="سورس کامل یک نسخه گزارش HScript متعلق به کسب‌وکار متصل.", parameters_schema=HS_VER, handler=get_hscript_report_version_handler, allowed_roles=roles, required_permissions=["hscript.view"], category="hscript", is_readonly=True))
    registry.register(AIFunction(name="restore_hscript_report_version", description="بازگردانی سورس گزارش به یک نسخه قبلی. نیازمند تأیید.", parameters_schema=HS_RESTORE, handler=restore_hscript_report_version_handler, allowed_roles=roles, required_permissions=["hscript.write"], category="hscript", requires_approval=True, risk_level="high", is_readonly=False))
    registry.register(AIFunction(name="list_hscript_report_runs", description="سابقه اجرای یک گزارش HScript کسب‌وکار متصل.", parameters_schema=HS_RUNS, handler=list_hscript_report_runs_handler, allowed_roles=roles, required_permissions=["hscript.view"], category="hscript", is_readonly=True))
    registry.register(AIFunction(name="run_hscript_report", description="اجرای همگام گزارش ذخیره‌شده HScript روی داده واقعی کسب‌وکار. نیازمند تأیید.", parameters_schema=HS_RUN, handler=run_hscript_report_handler, allowed_roles=roles, required_permissions=["hscript.view"], category="hscript", requires_approval=True, risk_level="high", is_readonly=False))
    registry.register(AIFunction(name="list_hscript_schedules", description="زمان‌بندی‌های اجرای گزارش HScript کسب‌وکار متصل.", parameters_schema=HS_SCHED_LIST, handler=list_hscript_schedules_handler, allowed_roles=roles, required_permissions=["hscript.schedule"], category="hscript", is_readonly=True))
    registry.register(AIFunction(name="create_hscript_schedule", description="ایجاد زمان‌بندی برای گزارش منتشرشده HScript. نیازمند تأیید.", parameters_schema=HS_SCHED_CREATE, handler=create_hscript_schedule_handler, allowed_roles=roles, required_permissions=["hscript.schedule"], category="hscript", requires_approval=True, risk_level="high", is_readonly=False))
    registry.register(AIFunction(name="update_hscript_schedule", description="ویرایش زمان‌بندی HScript کسب‌وکار متصل. نیازمند تأیید.", parameters_schema=HS_SCHED_UPDATE, handler=update_hscript_schedule_handler, allowed_roles=roles, required_permissions=["hscript.schedule"], category="hscript", requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="delete_hscript_schedule", description="حذف زمان‌بندی HScript کسب‌وکار متصل. نیازمند تأیید.", parameters_schema=HS_SCHED_ID, handler=delete_hscript_schedule_handler, allowed_roles=roles, required_permissions=["hscript.schedule"], category="hscript", requires_approval=True, risk_level="high", is_readonly=False))
    registry.register(AIFunction(name="run_hscript_schedule_now", description="اجرای فوری یک زمان‌بندی HScript. نیازمند تأیید.", parameters_schema=HS_SCHED_ID, handler=run_hscript_schedule_now_handler, allowed_roles=roles, required_permissions=["hscript.schedule"], category="hscript", requires_approval=True, risk_level="high", is_readonly=False))
