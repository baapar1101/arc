"""MCP tools for Woo control extras, Fanava extras, DigiPay settlements, leave business."""
from __future__ import annotations

from app.services.ai.ai_mcp_tool_util import mcp_bid, mcp_commit, mcp_db, mcp_jsonable, mcp_run, mcp_schema, mcp_uid

EMPTY = mcp_schema({})
PAGE_SEARCH = mcp_schema(
    {
        "page": {"type": "integer", "minimum": 1},
        "per_page": {"type": "integer", "minimum": 1, "maximum": 50},
        "search": {"type": "string", "maxLength": 80},
    }
)
REPORT_RANGE = mcp_schema({"after": {"type": "string", "maxLength": 40}, "before": {"type": "string", "maxLength": 40}})
LOGS = mcp_schema(
    {
        "page": {"type": "integer", "minimum": 1},
        "per_page": {"type": "integer", "minimum": 1, "maximum": 100},
        "action": {"type": "string", "maxLength": 80},
    }
)
FORCE = mcp_schema({"force": {"type": "boolean"}})
PAYLOAD = mcp_schema({"payload": {"type": "object"}})
FANAVA_ID = mcp_schema({"fanava_invoice_id": {"type": "integer", "minimum": 1}}, ["fanava_invoice_id"])
FANAVA_FIELDS = mcp_schema(
    {"code": {"type": "string", "minLength": 1, "maxLength": 40}, "subject": {"type": "string", "minLength": 1, "maxLength": 40}},
    ["code", "subject"],
)
SETTLE_LIST = mcp_schema(
    {"limit": {"type": "integer", "minimum": 1, "maximum": 200}, "offset": {"type": "integer", "minimum": 0}}
)
ATTACH = mcp_schema(
    {
        "purchase_id": {"type": "integer", "minimum": 1},
        "invoice_id": {"type": "integer", "minimum": 1},
        "receipt_document_id": {"type": ["integer", "null"], "minimum": 1},
    },
    ["purchase_id", "invoice_id"],
)
_SECRET_KEYS = ("bridge_token", "token", "secret", "password", "api_key", "consumer_key", "consumer_secret")


def _woo(context) -> None:
    from app.core.woocommerce_plugin_dependency import check_woocommerce_plugin_active

    if not check_woocommerce_plugin_active(mcp_db(context), mcp_bid(context)):
        raise ValueError("افزونه ووکامرس برای این کسب‌وکار فعال نیست")


def _mask(data):
    if isinstance(data, dict):
        out = {}
        for key, value in data.items():
            if any(s in str(key).lower() for s in _SECRET_KEYS) and value:
                out[key] = "***"
            else:
                out[key] = _mask(value)
        return out
    if isinstance(data, list):
        return [_mask(v) for v in data]
    return data


def _moadian(context) -> None:
    from app.core.moadian_plugin_dependency import ensure_moadian_plugin_active

    mcp_run(ensure_moadian_plugin_active, mcp_db(context), mcp_bid(context))


def _fanava(context, fn):
    from app.services.tax_provider_service import fanava_business_call

    _moadian(context)
    return mcp_jsonable(mcp_run(fanava_business_call, mcp_db(context), mcp_bid(context), fn))


def list_woocommerce_customers_handler(args, context):
    from app.services.woocommerce_integration_service import list_customers

    _woo(context)
    return mcp_jsonable(
        _mask(
            mcp_run(
                list_customers,
                mcp_db(context),
                mcp_bid(context),
                page=int(args.get("page") or 1),
                per_page=int(args.get("per_page") or 20),
                search=args.get("search"),
            )
        )
    )


def get_woocommerce_sales_summary_handler(args, context):
    from app.services.woocommerce_integration_service import reports_summary

    _woo(context)
    return mcp_jsonable(
        mcp_run(reports_summary, mcp_db(context), mcp_bid(context), after=args.get("after"), before=args.get("before"))
    )


def list_woocommerce_control_logs_handler(args, context):
    from app.services.woocommerce_integration_service import control_logs

    _woo(context)
    return mcp_jsonable(
        mcp_run(
            control_logs,
            mcp_db(context),
            mcp_bid(context),
            page=int(args.get("page") or 1),
            per_page=int(args.get("per_page") or 20),
            action=args.get("action"),
        )
    )


def get_woocommerce_connection_status_handler(args, context):
    from app.services.woocommerce_integration_service import control_connection

    _woo(context)
    return mcp_jsonable(_mask(mcp_run(control_connection, mcp_db(context), mcp_bid(context))))


def get_woocommerce_plugin_info_handler(args, context):
    from app.services.woocommerce_integration_service import control_plugin

    _woo(context)
    return mcp_jsonable(_mask(mcp_run(control_plugin, mcp_db(context), mcp_bid(context))))


def get_woocommerce_queue_snapshot_handler(args, context):
    from app.services.woocommerce_integration_service import control_queue_snapshot

    _woo(context)
    return mcp_jsonable(mcp_run(control_queue_snapshot, mcp_db(context), mcp_bid(context)))


def process_woocommerce_queue_once_handler(args, context):
    from app.services.woocommerce_integration_service import post_control_queue_process_once

    _woo(context)
    return mcp_jsonable(mcp_run(post_control_queue_process_once, mcp_db(context), mcp_bid(context)))


def check_woocommerce_plugin_update_handler(args, context):
    from app.services.woocommerce_integration_service import post_control_plugin_update_check

    _woo(context)
    return mcp_jsonable(
        mcp_run(post_control_plugin_update_check, mcp_db(context), mcp_bid(context), force=bool(args.get("force")))
    )


def run_woocommerce_stock_pull_handler(args, context):
    from app.services.woocommerce_integration_service import post_control_stock_pull_run

    _woo(context)
    return mcp_jsonable(
        mcp_run(post_control_stock_pull_run, mcp_db(context), mcp_bid(context), args.get("payload") or {})
    )


def get_woocommerce_stock_status_handler(args, context):
    from app.services.woocommerce_integration_service import control_stock_status

    _woo(context)
    return mcp_jsonable(mcp_run(control_stock_status, mcp_db(context), mcp_bid(context)))


def delete_fanava_invoice_handler(args, context):
    fid = int(args["fanava_invoice_id"])
    history = _fanava(context, lambda client, token, account: client.check_status(token, int(account.cartable_id), fid))
    latest = history[-1] if isinstance(history, list) and history else {}
    if str((latest or {}).get("status") or "").upper() != "SAVE":
        raise ValueError("فقط صورتحساب ذخیره‌شده و ارسال‌نشده از فن‌آوا قابل حذف است.")
    result = _fanava(context, lambda client, token, account: client.delete_invoice(token, int(account.cartable_id), fid))
    return {"deleted": True, "result": result}


def get_fanava_invoice_fields_handler(args, context):
    code = str(args["code"])
    subject = str(args["subject"])
    return _fanava(context, lambda client, token, account: client.invoice_fields_format(token, code, subject))


def list_digipay_settlements_handler(args, context):
    from app.services.digipay_service import list_settlements

    return mcp_jsonable(
        mcp_run(
            list_settlements,
            mcp_db(context),
            mcp_bid(context),
            locale="fa",
            calendar_type="jalali",
            limit=int(args.get("limit") or 50),
            offset=int(args.get("offset") or 0),
        )
    )


def attach_digipay_purchase_invoice_handler(args, context):
    from app.services.digipay_service import attach_purchase_to_invoice

    data = mcp_run(
        attach_purchase_to_invoice,
        mcp_db(context),
        mcp_bid(context),
        int(args["purchase_id"]),
        int(args["invoice_id"]),
        int(args["receipt_document_id"]) if args.get("receipt_document_id") else None,
        locale="fa",
    )
    return mcp_jsonable(data)


def leave_connected_business_handler(args, context):
    from adapters.db.models.business import Business
    from adapters.db.repositories.business_permission_repo import BusinessPermissionRepository

    db = mcp_db(context)
    bid = mcp_bid(context)
    uid = mcp_uid(context)
    business = db.get(Business, bid)
    if business is None:
        raise ValueError("کسب‌وکار یافت نشد")
    if int(business.owner_id or 0) == uid:
        raise ValueError("مالک نمی‌تواند از کسب‌وکار خارج شود")
    repo = BusinessPermissionRepository(db)
    permission_obj = repo.get_by_user_and_business(uid, bid)
    if not permission_obj:
        raise ValueError("شما عضو این کسب‌وکار نیستید")
    success = repo.delete_by_user_and_business(uid, bid)
    if not success:
        raise ValueError("خروج از کسب‌وکار ناموفق بود")
    mcp_commit(context)
    return {"left": True, "business_id": bid}


def register_mcp_ops6_functions(registry) -> None:
    from app.services.ai.function_registry import AIFunction, AIRole

    roles = {AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN}
    registry.register(AIFunction(name="list_woocommerce_customers", description="مشتریان فروشگاه ووکامرس متصل از پل وردپرس.", parameters_schema=PAGE_SEARCH, handler=list_woocommerce_customers_handler, allowed_roles=roles, required_permissions=["woocommerce.view"], category="integration", is_readonly=True))
    registry.register(AIFunction(name="get_woocommerce_sales_summary", description="خلاصه فروش ووکامرس در بازه after/before.", parameters_schema=REPORT_RANGE, handler=get_woocommerce_sales_summary_handler, allowed_roles=roles, required_permissions=["woocommerce.view"], category="integration", is_readonly=True))
    registry.register(AIFunction(name="list_woocommerce_control_logs", description="لاگ عملیات پل کنترل ووکامرس کسب‌وکار متصل.", parameters_schema=LOGS, handler=list_woocommerce_control_logs_handler, allowed_roles=roles, required_permissions=["woocommerce.view"], category="integration", is_readonly=True))
    registry.register(AIFunction(name="get_woocommerce_connection_status", description="وضعیت اتصال پل ووکامرس بدون توکن.", parameters_schema=EMPTY, handler=get_woocommerce_connection_status_handler, allowed_roles=roles, required_permissions=["woocommerce.view"], category="integration", is_readonly=True))
    registry.register(AIFunction(name="get_woocommerce_plugin_info", description="نسخه و وضعیت افزونه وردپرس ووکامرس متصل.", parameters_schema=EMPTY, handler=get_woocommerce_plugin_info_handler, allowed_roles=roles, required_permissions=["woocommerce.view"], category="integration", is_readonly=True))
    registry.register(AIFunction(name="get_woocommerce_queue_snapshot", description="نمای صف همگام‌سازی ووکامرس کسب‌وکار متصل.", parameters_schema=EMPTY, handler=get_woocommerce_queue_snapshot_handler, allowed_roles=roles, required_permissions=["woocommerce.view"], category="integration", is_readonly=True))
    registry.register(AIFunction(name="process_woocommerce_queue_once", description="پردازش یک دور صف همگام ووکامرس. نیازمند تأیید.", parameters_schema=EMPTY, handler=process_woocommerce_queue_once_handler, allowed_roles=roles, required_permissions=["woocommerce.manage"], category="integration", requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="check_woocommerce_plugin_update", description="بررسی به‌روزرسانی افزونه وردپرس ووکامرس. نیازمند تأیید.", parameters_schema=FORCE, handler=check_woocommerce_plugin_update_handler, allowed_roles=roles, required_permissions=["woocommerce.manage"], category="integration", requires_approval=True, risk_level="low", is_readonly=False))
    registry.register(AIFunction(name="run_woocommerce_stock_pull", description="کشیدن موجودی از ووکامرس به حسابیکس. نیازمند تأیید.", parameters_schema=PAYLOAD, handler=run_woocommerce_stock_pull_handler, allowed_roles=roles, required_permissions=["woocommerce.manage"], category="integration", requires_approval=True, risk_level="high", is_readonly=False))
    registry.register(AIFunction(name="get_woocommerce_stock_status", description="وضعیت همگام موجودی بین حسابیکس و ووکامرس.", parameters_schema=EMPTY, handler=get_woocommerce_stock_status_handler, allowed_roles=roles, required_permissions=["woocommerce.view"], category="integration", is_readonly=True))
    registry.register(AIFunction(name="delete_fanava_invoice", description="حذف صورتحساب ذخیره‌شده و ارسال‌نشده فن‌آوا. نیازمند تأیید.", parameters_schema=FANAVA_ID, handler=delete_fanava_invoice_handler, allowed_roles=roles, required_permissions=["moadian.manage_settings"], category="tax", requires_approval=True, risk_level="high", is_readonly=False))
    registry.register(AIFunction(name="get_fanava_invoice_fields", description="قالب فیلدهای صورتحساب فن‌آوا برای کد و موضوع داده‌شده.", parameters_schema=FANAVA_FIELDS, handler=get_fanava_invoice_fields_handler, allowed_roles=roles, required_permissions=["moadian.operate"], category="tax", is_readonly=True))
    registry.register(AIFunction(name="list_digipay_settlements", description="تسویه‌های ثبت‌شده دیجی‌پی همین کسب‌وکار.", parameters_schema=SETTLE_LIST, handler=list_digipay_settlements_handler, allowed_roles=roles, required_permissions=["digipay.view"], category="integration", is_readonly=True))
    registry.register(AIFunction(name="attach_digipay_purchase_invoice", description="اتصال خرید دیجی‌پی به فاکتور همین کسب‌وکار. نیازمند تأیید.", parameters_schema=ATTACH, handler=attach_digipay_purchase_invoice_handler, allowed_roles=roles, required_permissions=["digipay.operate"], category="integration", requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="leave_connected_business", description="خروج کاربر جاری از کسب‌وکار متصل؛ مالک نمی‌تواند خارج شود. نیازمند تأیید.", parameters_schema=EMPTY, handler=leave_connected_business_handler, allowed_roles=roles, required_permissions=["settings.join"], category="business", requires_approval=True, risk_level="high", is_readonly=False))
