"""MCP tools for business file storage metadata, shares, and plans. Binary upload/download stays in the app UI."""
from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy import and_

from app.services.ai.ai_mcp_tool_util import mcp_bid, mcp_commit, mcp_db, mcp_jsonable, mcp_run, mcp_schema, mcp_uid

LIST_FILES_SCHEMA = mcp_schema(
    {
        "module_context": {"type": "string", "maxLength": 80},
        "context_id": {"type": "string", "maxLength": 80},
        "page": {"type": "integer", "minimum": 1},
        "limit": {"type": "integer", "minimum": 1, "maximum": 100},
    }
)
FILE_ID = mcp_schema({"file_id": {"type": "string", "minLength": 8, "maxLength": 64}}, ["file_id"])
RENAME_SCHEMA = mcp_schema(
    {
        "file_id": {"type": "string", "minLength": 8, "maxLength": 64},
        "new_name": {"type": "string", "minLength": 1, "maxLength": 255},
    },
    ["file_id", "new_name"],
)
SHARE_CREATE = mcp_schema(
    {
        "file_id": {"type": "string", "minLength": 8, "maxLength": 64},
        "expires_in_days": {"type": ["integer", "null"], "minimum": 1, "maximum": 365},
    },
    ["file_id"],
)
SHARES_BIZ = mcp_schema(
    {
        "page": {"type": "integer", "minimum": 1},
        "limit": {"type": "integer", "minimum": 1, "maximum": 100},
        "only_active": {"type": "boolean"},
    }
)
SHARE_ID = mcp_schema({"share_id": {"type": "integer", "minimum": 1}}, ["share_id"])
SUBSCRIBE = mcp_schema(
    {"plan_id": {"type": "integer", "minimum": 1}, "auto_renew": {"type": "boolean"}},
    ["plan_id"],
)
SUB_ID = mcp_schema({"subscription_id": {"type": "integer", "minimum": 1}}, ["subscription_id"])
INVOICE_ID = mcp_schema({"invoice_id": {"type": "integer", "minimum": 1}}, ["invoice_id"])
EMPTY = mcp_schema({})


def _file_row(db, business_id: int, file_id: str):
    from adapters.db.models.file_storage import FileStorage

    row = (
        db.query(FileStorage)
        .filter(
            and_(
                FileStorage.id == file_id,
                FileStorage.business_id == business_id,
                FileStorage.deleted_at.is_(None),
            )
        )
        .first()
    )
    if not row:
        raise ValueError("فایل در کسب‌وکار متصل یافت نشد.")
    return row


def _file_dict(row) -> dict:
    return {
        "id": str(row.id) if row.id else None,
        "original_name": row.original_name or "",
        "file_size": row.file_size or 0,
        "mime_type": row.mime_type or "application/octet-stream",
        "module_context": row.module_context or "",
        "context_id": str(row.context_id) if row.context_id else None,
        "created_at": row.created_at.isoformat() if row.created_at else None,
    }


def _oa_file_admin(context, business_id: int) -> bool:
    ctx = context.get("user_context")
    if ctx is None:
        return False
    try:
        return bool(ctx.has_business_permission("office_automation", "admin") or ctx.is_business_owner(business_id))
    except Exception:
        return False


def _hide_oa_file(context, file_id: str) -> None:
    from app.services.oa_document_service import require_oa_file_visible

    bid = mcp_bid(context)
    require_oa_file_visible(
        mcp_db(context), bid, mcp_uid(context), str(file_id), is_admin=_oa_file_admin(context, bid),
    )


def list_storage_files_handler(args, context):
    from adapters.db.models.file_storage import FileStorage
    from app.services.oa_document_service import restrict_file_query

    db = mcp_db(context)
    bid = mcp_bid(context)
    page = int(args.get("page") or 1)
    limit = int(args.get("limit") or 50)
    filters = [FileStorage.business_id == bid, FileStorage.deleted_at.is_(None)]
    if args.get("module_context"):
        filters.append(FileStorage.module_context == args["module_context"])
    if args.get("context_id"):
        filters.append(FileStorage.context_id == args["context_id"])
    q = restrict_file_query(
        db.query(FileStorage).filter(and_(*filters)),
        db,
        bid,
        mcp_uid(context),
        _oa_file_admin(context, bid),
    )
    total = q.count()
    rows = q.order_by(FileStorage.created_at.desc()).offset((page - 1) * limit).limit(limit).all()
    return {
        "items": [_file_dict(row) for row in rows],
        "pagination": {
            "page": page,
            "limit": limit,
            "total": total,
            "total_pages": (total + limit - 1) // limit if limit else 1,
        },
    }


def get_storage_file_handler(args, context):
    _hide_oa_file(context, str(args["file_id"]))
    return _file_dict(_file_row(mcp_db(context), mcp_bid(context), str(args["file_id"])))


def rename_storage_file_handler(args, context):
    _hide_oa_file(context, str(args["file_id"]))
    row = _file_row(mcp_db(context), mcp_bid(context), str(args["file_id"]))
    row.original_name = str(args["new_name"]).strip()
    mcp_commit(context)
    return {"id": str(row.id), "original_name": row.original_name}


def delete_storage_file_handler(args, context):
    _hide_oa_file(context, str(args["file_id"]))
    row = _file_row(mcp_db(context), mcp_bid(context), str(args["file_id"]))
    row.deleted_at = datetime.now(timezone.utc)
    mcp_commit(context)
    return {"deleted": True, "file_id": str(row.id)}


def create_storage_file_share_handler(args, context):
    from app.services.file_storage_share_service import create_share

    data = mcp_jsonable(
        mcp_run(
            create_share,
            mcp_db(context),
            mcp_bid(context),
            str(args["file_id"]),
            mcp_uid(context),
            password=None,
            expires_in_days=args.get("expires_in_days", 30),
            is_admin=_oa_file_admin(context, mcp_bid(context)),
        )
    )
    if isinstance(data, dict):
        data = dict(data)
        data.pop("token", None)
        data["token_returned"] = False
    return data


def list_storage_file_shares_handler(args, context):
    from app.services.file_storage_share_service import list_shares_for_file

    _hide_oa_file(context, str(args["file_id"]))
    return {"items": mcp_jsonable(mcp_run(list_shares_for_file, mcp_db(context), mcp_bid(context), str(args["file_id"])))}


def list_storage_shares_handler(args, context):
    from app.services.file_storage_share_service import list_shares_for_business

    page = int(args.get("page") or 1)
    limit = int(args.get("limit") or 50)
    return mcp_jsonable(
        mcp_run(
            list_shares_for_business,
            mcp_db(context),
            mcp_bid(context),
            page=page,
            limit=limit,
            only_active=bool(args.get("only_active")),
            user_id=mcp_uid(context),
            is_admin=_oa_file_admin(context, mcp_bid(context)),
        )
    )


def revoke_storage_file_share_handler(args, context):
    from app.services.file_storage_share_service import revoke_share

    mcp_run(revoke_share, mcp_db(context), mcp_bid(context), int(args["share_id"]))
    return {"revoked": True, "share_id": int(args["share_id"])}


def get_storage_usage_handler(args, context):
    from app.services.storage_subscription_service import get_storage_usage_info

    return mcp_jsonable(mcp_run(get_storage_usage_info, mcp_db(context), mcp_bid(context)))


def list_storage_plans_handler(args, context):
    from app.services.storage_plan_service import list_storage_plans

    return mcp_jsonable(mcp_run(list_storage_plans, mcp_db(context), only_active=True))


def list_storage_subscriptions_handler(args, context):
    from app.services.storage_subscription_service import get_active_subscriptions

    return mcp_jsonable(mcp_run(get_active_subscriptions, mcp_db(context), mcp_bid(context)))


def subscribe_storage_plan_handler(args, context):
    from app.services.storage_subscription_service import subscribe_to_plan

    return mcp_jsonable(
        mcp_run(
            subscribe_to_plan,
            mcp_db(context),
            mcp_bid(context),
            int(args["plan_id"]),
            bool(args.get("auto_renew", False)),
        )
    )


def cancel_storage_subscription_handler(args, context):
    from app.services.storage_subscription_service import cancel_subscription

    return mcp_jsonable(mcp_run(cancel_subscription, mcp_db(context), mcp_bid(context), int(args["subscription_id"])))


def list_storage_invoices_handler(args, context):
    from app.services.storage_invoice_service import list_storage_invoices

    return mcp_jsonable(mcp_run(list_storage_invoices, mcp_db(context), mcp_bid(context)))


def pay_storage_invoice_handler(args, context):
    from app.services.storage_invoice_service import pay_storage_invoice_from_wallet

    return mcp_jsonable(
        mcp_run(pay_storage_invoice_from_wallet, mcp_db(context), mcp_bid(context), int(args["invoice_id"]), mcp_uid(context))
    )


def register_mcp_storage_functions(registry) -> None:
    from app.services.ai.function_registry import AIFunction, AIRole

    roles = {AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN}
    registry.register(AIFunction(
        name="list_storage_files",
        description="فهرست متادیتای فایل‌های کسب‌وکار متصل. محتوای باینری از MCP برنمی‌گردد؛ آپلود از رابط کاربری است.",
        parameters_schema=LIST_FILES_SCHEMA,
        handler=list_storage_files_handler,
        allowed_roles=roles,
        required_permissions=["storage.view"],
        category="business",
        is_readonly=True,
    ))
    registry.register(AIFunction(
        name="get_storage_file",
        description="متادیتای یک فایل متعلق به کسب‌وکار متصل.",
        parameters_schema=FILE_ID,
        handler=get_storage_file_handler,
        allowed_roles=roles,
        required_permissions=["storage.view"],
        category="business",
        is_readonly=True,
    ))
    registry.register(AIFunction(
        name="rename_storage_file",
        description="تغییر نام نمایشی فایل کسب‌وکار متصل. نیازمند تأیید.",
        parameters_schema=RENAME_SCHEMA,
        handler=rename_storage_file_handler,
        allowed_roles=roles,
        required_permissions=["storage.write"],
        category="business",
        requires_approval=True,
        risk_level="medium",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="delete_storage_file",
        description="حذف نرم فایل کسب‌وکار متصل. نیازمند تأیید.",
        parameters_schema=FILE_ID,
        handler=delete_storage_file_handler,
        allowed_roles=roles,
        required_permissions=["storage.write"],
        category="business",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="create_storage_file_share",
        description="ایجاد لینک اشتراک فایل. توکن خام برنمی‌گردد؛ public_url برمی‌گردد. نیازمند تأیید.",
        parameters_schema=SHARE_CREATE,
        handler=create_storage_file_share_handler,
        allowed_roles=roles,
        required_permissions=["storage.write"],
        category="business",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="list_storage_file_shares",
        description="لینک‌های اشتراک یک فایل کسب‌وکار متصل.",
        parameters_schema=FILE_ID,
        handler=list_storage_file_shares_handler,
        allowed_roles=roles,
        required_permissions=["storage.view"],
        category="business",
        is_readonly=True,
    ))
    registry.register(AIFunction(
        name="list_storage_shares",
        description="همه لینک‌های اشتراک فایل کسب‌وکار متصل.",
        parameters_schema=SHARES_BIZ,
        handler=list_storage_shares_handler,
        allowed_roles=roles,
        required_permissions=["storage.view"],
        category="business",
        is_readonly=True,
    ))
    registry.register(AIFunction(
        name="revoke_storage_file_share",
        description="باطل کردن یک لینک اشتراک فایل. نیازمند تأیید.",
        parameters_schema=SHARE_ID,
        handler=revoke_storage_file_share_handler,
        allowed_roles=roles,
        required_permissions=["storage.write"],
        category="business",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="get_storage_usage",
        description="مصرف و سقف فضای ذخیره‌سازی کسب‌وکار متصل.",
        parameters_schema=EMPTY,
        handler=get_storage_usage_handler,
        allowed_roles=roles,
        required_permissions=["storage.view"],
        category="business",
        is_readonly=True,
    ))
    registry.register(AIFunction(
        name="list_storage_plans",
        description="پلن‌های فعال فضای ذخیره‌سازی قابل اشتراک.",
        parameters_schema=EMPTY,
        handler=list_storage_plans_handler,
        allowed_roles=roles,
        required_permissions=["storage.view"],
        category="business",
        is_readonly=True,
    ))
    registry.register(AIFunction(
        name="list_storage_subscriptions",
        description="اشتراک‌های فعال فضای ذخیره‌سازی کسب‌وکار متصل.",
        parameters_schema=EMPTY,
        handler=list_storage_subscriptions_handler,
        allowed_roles=roles,
        required_permissions=["storage.view"],
        category="business",
        is_readonly=True,
    ))
    registry.register(AIFunction(
        name="subscribe_storage_plan",
        description="اشتراک کسب‌وکار به پلن فضای ذخیره‌سازی. ممکن است از کیف‌پول کسر شود. نیازمند تأیید.",
        parameters_schema=SUBSCRIBE,
        handler=subscribe_storage_plan_handler,
        allowed_roles=roles,
        required_permissions=["storage.write"],
        category="business",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="cancel_storage_subscription",
        description="لغو اشتراک فضای ذخیره‌سازی. نیازمند تأیید.",
        parameters_schema=SUB_ID,
        handler=cancel_storage_subscription_handler,
        allowed_roles=roles,
        required_permissions=["storage.write"],
        category="business",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="list_storage_invoices",
        description="صورتحساب‌های فضای ذخیره‌سازی کسب‌وکار متصل.",
        parameters_schema=EMPTY,
        handler=list_storage_invoices_handler,
        allowed_roles=roles,
        required_permissions=["storage.view"],
        category="business",
        is_readonly=True,
    ))
    registry.register(AIFunction(
        name="pay_storage_invoice",
        description="پرداخت صورتحساب فضای ذخیره‌سازی از کیف‌پول کسب‌وکار. نیازمند تأیید.",
        parameters_schema=INVOICE_ID,
        handler=pay_storage_invoice_handler,
        allowed_roles=roles,
        required_permissions=["storage.write"],
        category="business",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
