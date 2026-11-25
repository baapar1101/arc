"""MCP tools for backups, members, tax catalogs, print/share settings, document codes, AI usage."""
from __future__ import annotations

from datetime import date, datetime

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
BACKUP_CREATE = mcp_schema({"upload_to_ftp": {"type": "boolean"}})
BACKUP_ID = mcp_schema({"backup_id": {"type": "string", "minLength": 8, "maxLength": 64}}, ["backup_id"])
USER_ID = mcp_schema({"user_id": {"type": "integer", "minimum": 1}}, ["user_id"])
PERMS = mcp_schema(
    {
        "user_id": {"type": "integer", "minimum": 1},
        "permissions": {"type": "object"},
        "apply_membership_expiry": {"type": "boolean"},
        "membership_expires_at": {"type": ["string", "null"]},
    },
    ["user_id", "permissions"],
)
TAX_SEARCH = mcp_schema(
    {
        "q": {"type": "string", "maxLength": 80},
        "skip": {"type": "integer", "minimum": 0},
        "take": {"type": "integer", "minimum": 1, "maximum": 200},
    }
)
TAX_CODE = mcp_schema({"code": {"type": "string", "minLength": 1, "maxLength": 64}}, ["code"])
JOB_ID = mcp_schema({"job_id": {"type": "string", "minLength": 4, "maxLength": 80}}, ["job_id"])
LOT_PREVIEW = mcp_schema(
    {
        "product_id": {"type": "integer", "minimum": 1},
        "manufacturing_date": {"type": ["string", "null"]},
        "expiry_date": {"type": ["string", "null"]},
    },
    ["product_id"],
)
RESERVE = mcp_schema(
    {
        "document_type": {
            "type": "string",
            "enum": [
                "invoice_sales",
                "invoice_sales_return",
                "invoice_purchase",
                "invoice_purchase_return",
                "invoice_direct_consumption",
                "invoice_production",
                "invoice_waste",
            ],
        },
        "document_date": {"type": "string", "format": "date"},
    },
    ["document_type", "document_date"],
)
RESERVATION_ID = mcp_schema({"reservation_id": {"type": "string", "minLength": 8, "maxLength": 64}}, ["reservation_id"])
PRINT_UPDATE = mcp_schema(
    {
        "default": {"type": "object"},
        "per_type": {"type": "object"},
    }
)
SHARE_UPDATE = mcp_schema(
    {
        "default_online_payment_enabled": {"type": "boolean"},
        "default_online_payment_gateway_id": {"type": ["integer", "null"], "minimum": 0},
    }
)
AI_USAGE = mcp_schema({"start_date": {"type": "string"}, "end_date": {"type": "string"}})
AI_SUBSCRIBE = mcp_schema(
    {"plan_id": {"type": "integer", "minimum": 1}, "period": {"type": "string", "enum": ["monthly", "yearly"]}},
    ["plan_id"],
)
AI_MODEL = mcp_schema({"model_code": {"type": "string", "minLength": 1, "maxLength": 80}}, ["model_code"])


def _member_row(user, role: str, permission_obj, business) -> dict:
    from adapters.api.v1.business_users import _member_status, _membership_fields

    return {
        "user_id": user.id,
        "user_name": f"{user.first_name or ''} {user.last_name or ''}".strip(),
        "user_email": user.email or "",
        "user_phone": user.mobile,
        "role": role,
        "status": _member_status(permission_obj, role),
        "permissions": {} if role == "owner" else (permission_obj.business_permissions if permission_obj else {}),
        **_membership_fields(permission_obj if role == "member" else None, role),
        "added_at": (permission_obj.created_at if permission_obj else business.created_at),
    }


def list_business_backups_handler(args, context):
    from adapters.db.models.file_storage import FileStorage

    db = mcp_db(context)
    bid = mcp_bid(context)
    items = []
    rows = (
        db.query(FileStorage)
        .filter(FileStorage.module_context == "business_backup", FileStorage.deleted_at.is_(None))
        .order_by(FileStorage.created_at.desc())
        .all()
    )
    for f in rows:
        dev = f.developer_data or {}
        try:
            same = int(dev.get("business_id")) == bid
        except (TypeError, ValueError):
            same = False
        if not same:
            continue
        items.append(
            {
                "id": str(f.id),
                "filename": f.original_name,
                "size": f.file_size,
                "created_at": f.created_at.isoformat() if f.created_at else None,
                "checksum": f.checksum,
                "ftp_uploaded": bool(dev.get("ftp_uploaded")),
            }
        )
    return {"items": items[:200], "total": min(len(items), 200)}


def create_business_backup_handler(args, context):
    from adapters.api.v1.business_backups import run_workflow_business_backup

    out = mcp_run(
        run_workflow_business_backup,
        mcp_db(context),
        mcp_bid(context),
        mcp_uid(context),
        bool(args.get("upload_to_ftp")),
    )
    if isinstance(out, dict):
        out.pop("zip_bytes", None)
    return mcp_jsonable(out)


def delete_business_backup_handler(args, context):
    from datetime import datetime as dt
    from uuid import UUID

    from adapters.db.models.file_storage import FileStorage

    db = mcp_db(context)
    bid = mcp_bid(context)
    backup_id = str(args["backup_id"])
    file = db.query(FileStorage).filter(FileStorage.id == str(UUID(backup_id))).first()
    if not file:
        raise ValueError("بکاپ یافت نشد.")
    dev = file.developer_data or {}
    try:
        same = int(dev.get("business_id")) == bid
    except (TypeError, ValueError):
        same = False
    if file.module_context != "business_backup" or not same:
        raise ValueError("بکاپ یافت نشد.")
    if file.deleted_at is None:
        file.deleted_at = dt.utcnow()
        mcp_commit(context)
    return {"deleted": True, "backup_id": backup_id}


def get_ftp_backup_settings_handler(args, context):
    from adapters.db.models.business_ftp_backup_setting import BusinessFtpBackupSetting
    from app.services.business_ftp_service import row_to_public_dict

    row = (
        mcp_db(context)
        .query(BusinessFtpBackupSetting)
        .filter(BusinessFtpBackupSetting.business_id == mcp_bid(context))
        .first()
    )
    return row_to_public_dict(row)


def delete_ftp_backup_settings_handler(args, context):
    from adapters.db.models.business_ftp_backup_setting import BusinessFtpBackupSetting

    db = mcp_db(context)
    row = db.query(BusinessFtpBackupSetting).filter(BusinessFtpBackupSetting.business_id == mcp_bid(context)).first()
    if row:
        db.delete(row)
        mcp_commit(context)
    return {"deleted": True}


def test_ftp_backup_saved_handler(args, context):
    from app.services.business_ftp_service import do_ftp_test

    return mcp_jsonable(mcp_run(do_ftp_test, mcp_bid(context), {"use_saved": True}))


def scan_ftp_backup_usage_handler(args, context):
    from app.services.business_ftp_service import do_ftp_usage_scan

    return mcp_jsonable(mcp_run(do_ftp_usage_scan, mcp_bid(context)))


def list_tax_units_handler(args, context):
    from adapters.db.models.tax_unit import TaxUnit

    rows = mcp_db(context).query(TaxUnit).order_by(TaxUnit.name).all()
    return {
        "items": [
            {"id": u.id, "name": u.name, "code": u.code, "description": u.description}
            for u in rows[:500]
        ]
    }


def list_tax_types_handler(args, context):
    from adapters.db.models.tax_type import TaxType

    rows = mcp_db(context).query(TaxType).order_by(TaxType.id).all()
    return {
        "items": [
            {"id": t.id, "title": t.title, "code": t.code, "description": t.description}
            for t in rows[:500]
        ]
    }


def search_tax_product_codes_handler(args, context):
    from app.services.tax_product_code_service import search_tax_product_codes

    take = int(args.get("take") or 20)
    skip = int(args.get("skip") or 0)
    return mcp_jsonable(mcp_run(search_tax_product_codes, mcp_db(context), args.get("q"), skip, take))


def get_tax_product_code_handler(args, context):
    from app.services.tax_product_code_service import get_tax_product_code

    item = mcp_run(get_tax_product_code, mcp_db(context), str(args["code"]))
    if not item:
        return {"code": args["code"], "found": False}
    return mcp_jsonable(item)


def get_business_user_handler(args, context):
    from adapters.db.models.business import Business
    from adapters.db.models.user import User
    from adapters.db.repositories.business_permission_repo import BusinessPermissionRepository

    db = mcp_db(context)
    bid = mcp_bid(context)
    user_id = int(args["user_id"])
    business = db.get(Business, bid)
    user = db.get(User, user_id)
    if not business or not user:
        raise ValueError("کاربر یا کسب‌وکار یافت نشد.")
    perm = BusinessPermissionRepository(db).get_by_user_and_business(user_id, bid)
    role = "owner" if business.owner_id == user_id else "member"
    if role == "member" and not perm:
        raise ValueError("این کاربر عضو کسب‌وکار نیست.")
    return mcp_jsonable({"user": _member_row(user, role, perm, business)})


def update_business_user_permissions_handler(args, context):
    from datetime import datetime as dt

    from adapters.api.v1.schemas import UpdatePermissionsRequest
    from adapters.db.models.business import Business
    from adapters.db.models.user import User
    from adapters.db.repositories.business_permission_repo import BusinessPermissionRepository

    db = mcp_db(context)
    bid = mcp_bid(context)
    user_id = int(args["user_id"])
    business = db.get(Business, bid)
    if not business or not db.get(User, user_id):
        raise ValueError("کاربر یا کسب‌وکار یافت نشد.")
    if business.owner_id == user_id and bool(args.get("apply_membership_expiry")):
        raise ValueError("عضویت مالک را نمی‌توان زمان‌دار کرد.")
    expires = args.get("membership_expires_at")
    if isinstance(expires, str) and expires:
        expires = dt.fromisoformat(expires.replace("Z", "+00:00"))
    body = UpdatePermissionsRequest(
        permissions=args.get("permissions") or {},
        apply_membership_expiry=bool(args.get("apply_membership_expiry")),
        membership_expires_at=expires,
    )
    repo = BusinessPermissionRepository(db)
    if body.apply_membership_expiry:
        repo.create_or_update(
            user_id=user_id,
            business_id=bid,
            permissions=body.permissions,
            membership_expires_at=body.membership_expires_at,
        )
    else:
        repo.create_or_update(user_id=user_id, business_id=bid, permissions=body.permissions)
    mcp_commit(context)
    return {"updated": True, "user_id": user_id}


def remove_business_user_handler(args, context):
    from adapters.db.models.business import Business
    from adapters.db.repositories.business_permission_repo import BusinessPermissionRepository

    db = mcp_db(context)
    bid = mcp_bid(context)
    user_id = int(args["user_id"])
    business = db.get(Business, bid)
    if not business:
        raise ValueError("کسب‌وکار یافت نشد.")
    if business.owner_id == user_id:
        raise ValueError("مالک کسب‌وکار را نمی‌توان حذف کرد.")
    ok = BusinessPermissionRepository(db).delete_by_user_and_business(user_id, bid)
    if not ok:
        raise ValueError("این کاربر عضو کسب‌وکار نیست.")
    mcp_commit(context)
    return {"removed": True, "user_id": user_id}


def _connected_users(context, chat_attr: str) -> dict:
    from adapters.db.models.business import Business
    from adapters.db.models.user import User
    from adapters.db.repositories.business_permission_repo import BusinessPermissionRepository
    from sqlalchemy import and_, select

    db = mcp_db(context)
    bid = mcp_bid(context)
    business = db.get(Business, bid)
    if not business:
        raise ValueError("کسب‌وکار یافت نشد.")
    perms = BusinessPermissionRepository(db).get_business_users(bid)
    user_ids = {business.owner_id}
    for perm in perms:
        if perm.user_id:
            user_ids.add(perm.user_id)
    col = getattr(User, chat_attr, None)
    if col is None:
        return {"users": [], "total": 0}
    users = db.execute(select(User).where(and_(User.id.in_(list(user_ids)), col.isnot(None)))).scalars().all()
    items = []
    for user in users:
        items.append(
            {
                "user_id": user.id,
                "name": f"{user.first_name or ''} {user.last_name or ''}".strip() or user.email,
                "role": "owner" if user.id == business.owner_id else "member",
                "connected": True,
            }
        )
    return {"users": items, "total": len(items)}


def list_telegram_connected_users_handler(args, context):
    return _connected_users(context, "telegram_chat_id")


def list_bale_connected_users_handler(args, context):
    return _connected_users(context, "bale_chat_id")


def get_background_job_handler(args, context):
    from app.services.job_manager import JobManager

    job_id = str(args["job_id"])
    status = JobManager.instance().get(job_id)
    if not status:
        raise ValueError("کار پس‌زمینه یافت نشد.")
    return {
        "id": status.id,
        "state": status.state,
        "progress": getattr(status, "progress", None),
        "message": getattr(status, "message", None),
        "error": getattr(status, "error", None),
        "result": mcp_jsonable(getattr(status, "result", None)),
    }


def preview_product_lot_dates_handler(args, context):
    from adapters.db.models.product import Product
    from app.services.inventory_lot_service import _as_date, compute_lot_dates

    db = mcp_db(context)
    product = (
        db.query(Product)
        .filter(Product.id == int(args["product_id"]), Product.business_id == mcp_bid(context))
        .first()
    )
    if product is None:
        raise ValueError("کالا یافت نشد.")
    dates = compute_lot_dates(
        product,
        manufacturing_date=_as_date(args.get("manufacturing_date")),
        expiry_date=_as_date(args.get("expiry_date")),
    )
    return {k: (v.isoformat() if v else None) for k, v in dates.items()}


def reserve_document_code_handler(args, context):
    from app.services.document_code_reservation_service import reserve_document_code

    raw = str(args["document_date"])[:10]
    result = mcp_run(
        reserve_document_code,
        mcp_db(context),
        business_id=mcp_bid(context),
        user_id=mcp_uid(context),
        document_type=str(args["document_type"]),
        document_date=date.fromisoformat(raw),
    )
    mcp_commit(context)
    return mcp_jsonable(result)


def cancel_document_code_reservation_handler(args, context):
    from app.services.document_code_reservation_service import cancel_document_code_reservation

    cancelled = mcp_run(
        cancel_document_code_reservation,
        mcp_db(context),
        business_id=mcp_bid(context),
        user_id=mcp_uid(context),
        reservation_id=str(args["reservation_id"]),
    )
    mcp_commit(context)
    return {"cancelled": bool(cancelled)}


def get_business_print_settings_handler(args, context):
    from app.services.business_service import get_business_print_settings

    return mcp_jsonable(mcp_run(get_business_print_settings, mcp_db(context), mcp_bid(context)))


def update_business_print_settings_handler(args, context):
    from app.services.business_service import update_business_print_settings

    payload = {k: args[k] for k in ("default", "per_type") if k in args}
    result = mcp_jsonable(mcp_run(update_business_print_settings, mcp_db(context), mcp_bid(context), payload))
    mcp_commit(context)
    return result


def get_invoice_share_payment_settings_handler(args, context):
    from app.services.business_service import get_business_invoice_share_settings

    return mcp_jsonable(mcp_run(get_business_invoice_share_settings, mcp_db(context), mcp_bid(context)))


def update_invoice_share_payment_settings_handler(args, context):
    from app.services.business_service import update_business_invoice_share_settings

    payload = {k: args[k] for k in ("default_online_payment_enabled", "default_online_payment_gateway_id") if k in args}
    result = mcp_jsonable(mcp_run(update_business_invoice_share_settings, mcp_db(context), mcp_bid(context), payload))
    mcp_commit(context)
    return result


def _serialize_ai_sub(subscription) -> dict | None:
    from app.services.ai.ai_model_service import serialize_plan_for_user
    from app.services.ai.ai_quota_helpers import effective_tokens_limit

    if not subscription:
        return None
    plan = subscription.plan
    return mcp_jsonable(
        {
            "id": subscription.id,
            "plan_id": subscription.plan_id,
            "preferred_model_code": getattr(subscription, "preferred_model_code", None),
            "plan": serialize_plan_for_user(plan) if plan else None,
            "subscription_type": subscription.subscription_type,
            "tokens_used": subscription.tokens_used,
            "tokens_limit": effective_tokens_limit(subscription.tokens_limit),
            "period_start": subscription.period_start.isoformat() if subscription.period_start else None,
            "period_end": subscription.period_end.isoformat() if subscription.period_end else None,
            "is_active": subscription.is_active,
            "auto_renew": getattr(subscription, "auto_renew", False),
        }
    )


def get_ai_subscription_handler(args, context):
    from adapters.db.repositories.ai_subscription_repository import AISubscriptionRepository

    sub = AISubscriptionRepository(mcp_db(context)).get_active_subscription(
        user_id=mcp_uid(context),
        business_id=mcp_bid(context),
    )
    return {"subscription": _serialize_ai_sub(sub)}


def list_ai_plans_handler(args, context):
    from adapters.db.repositories.ai_plan_repository import AIPlanRepository
    from adapters.db.repositories.ai_subscription_repository import AISubscriptionRepository
    from app.services.ai.ai_model_service import serialize_plan_for_user

    db = mcp_db(context)
    plans = [serialize_plan_for_user(p) for p in AIPlanRepository(db).get_active_plans()]
    sub = AISubscriptionRepository(db).get_active_subscription(user_id=mcp_uid(context), business_id=mcp_bid(context))
    return mcp_jsonable({"plans": plans, "current_plan_id": sub.plan_id if sub else None})


def subscribe_ai_plan_handler(args, context):
    from app.services.ai_plan_service import subscribe_to_plan

    result = mcp_run(
        subscribe_to_plan,
        mcp_db(context),
        mcp_uid(context),
        mcp_bid(context),
        int(args["plan_id"]),
        str(args.get("period") or "monthly"),
    )
    mcp_commit(context)
    return mcp_jsonable(result)


def set_ai_preferred_model_handler(args, context):
    from adapters.db.repositories.ai_subscription_repository import AISubscriptionRepository
    from app.services.ai.ai_model_service import validate_model_selection

    db = mcp_db(context)
    bid = mcp_bid(context)
    sub = AISubscriptionRepository(db).get_active_subscription(user_id=mcp_uid(context), business_id=bid)
    if not sub:
        raise ValueError("اشتراک فعالی وجود ندارد.")
    mcp_run(validate_model_selection, db, sub.plan, str(args["model_code"]).strip(), business_id=bid)
    sub.preferred_model_code = str(args["model_code"]).strip()
    mcp_commit(context)
    return {"preferred_model_code": sub.preferred_model_code}


def get_ai_usage_stats_handler(args, context):
    from adapters.db.repositories.ai_usage_log_repository import AIUsageLogRepository

    from datetime import timedelta

    end = datetime.utcnow()
    if args.get("end_date"):
        end = datetime.fromisoformat(str(args["end_date"]).replace("Z", "+00:00")).replace(tzinfo=None)
    if args.get("start_date"):
        start = datetime.fromisoformat(str(args["start_date"]).replace("Z", "+00:00")).replace(tzinfo=None)
    else:
        start = end - timedelta(days=30)
    repo = AIUsageLogRepository(mcp_db(context))
    bid = mcp_bid(context)
    return mcp_jsonable(
        {
            "total": repo.get_business_usage_stats(business_id=bid, start_date=start, end_date=end),
            "daily": repo.get_daily_usage_stats(business_id=bid, start_date=start, end_date=end),
            "by_model": repo.get_model_usage_stats(business_id=bid, start_date=start, end_date=end),
        }
    )


def register_mcp_ops2_functions(registry) -> None:
    from app.services.ai.function_registry import AIFunction, AIRole

    roles = {AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN}
    registry.register(AIFunction(name="list_business_backups", description="فهرست فایل‌های پشتیبان ذخیره‌شده کسب‌وکار متصل بدون محتوای باینری.", parameters_schema=EMPTY, handler=list_business_backups_handler, allowed_roles=roles, required_permissions=["settings.join"], category="business", is_readonly=True))
    registry.register(AIFunction(name="create_business_backup", description="ایجاد پشتیبان کامل کسب‌وکار و ذخیره در فضای فایل. محتوای ZIP برگردانده نمی‌شود. نیازمند تأیید.", parameters_schema=BACKUP_CREATE, handler=create_business_backup_handler, allowed_roles=roles, required_permissions=["settings.join"], category="business", requires_approval=True, risk_level="high", is_readonly=False))
    registry.register(AIFunction(name="delete_business_backup", description="حذف نرم یک فایل پشتیبان متعلق به کسب‌وکار متصل. نیازمند تأیید.", parameters_schema=BACKUP_ID, handler=delete_business_backup_handler, allowed_roles=roles, required_permissions=["settings.join"], category="business", requires_approval=True, risk_level="high", is_readonly=False))
    registry.register(AIFunction(name="get_ftp_backup_settings", description="تنظیمات FTP/SFTP پشتیبان بدون رمز عبور.", parameters_schema=EMPTY, handler=get_ftp_backup_settings_handler, allowed_roles=roles, required_permissions=["settings.manage_ftp"], category="business", is_readonly=True))
    registry.register(AIFunction(name="delete_ftp_backup_settings", description="حذف تنظیمات ذخیره‌شده FTP پشتیبان. نیازمند تأیید.", parameters_schema=EMPTY, handler=delete_ftp_backup_settings_handler, allowed_roles=roles, required_permissions=["settings.manage_ftp"], category="business", requires_approval=True, risk_level="high", is_readonly=False))
    registry.register(AIFunction(name="test_ftp_backup_saved", description="تست اتصال با تنظیمات FTP ذخیره‌شده؛ رمز از MCP پذیرفته نمی‌شود.", parameters_schema=EMPTY, handler=test_ftp_backup_saved_handler, allowed_roles=roles, required_permissions=["settings.manage_ftp"], category="business", requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="scan_ftp_backup_usage", description="اسکن فضای پوشه ریموت FTP ذخیره‌شده کسب‌وکار.", parameters_schema=EMPTY, handler=scan_ftp_backup_usage_handler, allowed_roles=roles, required_permissions=["settings.manage_ftp"], category="business", requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="list_tax_units", description="فهرست واحدهای اندازه‌گیری استاندارد مالیاتی سامانه مودیان.", parameters_schema=EMPTY, handler=list_tax_units_handler, allowed_roles=roles, required_permissions=["products.view"], category="tax", is_readonly=True))
    registry.register(AIFunction(name="list_tax_types", description="فهرست نوع‌های مالیات استاندارد مانند ارزش افزوده.", parameters_schema=EMPTY, handler=list_tax_types_handler, allowed_roles=roles, required_permissions=["products.view"], category="tax", is_readonly=True))
    registry.register(AIFunction(name="search_tax_product_codes", description="جستجوی کد کالا یا خدمت مالیاتی واردشده در سیستم. حداکثر ۲۰۰ مورد.", parameters_schema=TAX_SEARCH, handler=search_tax_product_codes_handler, allowed_roles=roles, required_permissions=["products.view"], category="tax", is_readonly=True))
    registry.register(AIFunction(name="get_tax_product_code", description="شرح یک کد مالیاتی؛ اگر در لیست سیستم نباشد found=false برمی‌گردد.", parameters_schema=TAX_CODE, handler=get_tax_product_code_handler, allowed_roles=roles, required_permissions=["products.view"], category="tax", is_readonly=True))
    registry.register(AIFunction(name="get_business_user", description="جزئیات و دسترسی‌های یک عضو کسب‌وکار متصل.", parameters_schema=USER_ID, handler=get_business_user_handler, allowed_roles=roles, required_permissions=["settings.users"], category="business", is_readonly=True))
    registry.register(AIFunction(name="update_business_user_permissions", description="جایگزینی دسترسی‌ها و اختیاری تاریخ انقضای عضویت. نیازمند تأیید.", parameters_schema=PERMS, handler=update_business_user_permissions_handler, allowed_roles=roles, required_permissions=["settings.users"], category="business", requires_approval=True, risk_level="high", is_readonly=False))
    registry.register(AIFunction(name="remove_business_user", description="حذف عضو غیرمالک از کسب‌وکار متصل. نیازمند تأیید.", parameters_schema=USER_ID, handler=remove_business_user_handler, allowed_roles=roles, required_permissions=["settings.users"], category="business", requires_approval=True, risk_level="high", is_readonly=False))
    registry.register(AIFunction(name="list_telegram_connected_users", description="اعضای کسب‌وکار که ربات تلگرام را وصل کرده‌اند؛ شناسه چت برگردانده نمی‌شود.", parameters_schema=EMPTY, handler=list_telegram_connected_users_handler, allowed_roles=roles, required_permissions=["settings.users"], category="business", is_readonly=True))
    registry.register(AIFunction(name="list_bale_connected_users", description="اعضای کسب‌وکار که ربات بله را وصل کرده‌اند؛ شناسه چت برگردانده نمی‌شود.", parameters_schema=EMPTY, handler=list_bale_connected_users_handler, allowed_roles=roles, required_permissions=["settings.users"], category="business", is_readonly=True))
    registry.register(AIFunction(name="get_background_job", description="وضعیت یک کار پس‌زمینه بکاپ، گزارش یا FTP با شناسه job_id.", parameters_schema=JOB_ID, handler=get_background_job_handler, allowed_roles=roles, required_permissions=["settings.join"], category="business", is_readonly=True))
    registry.register(AIFunction(name="preview_product_lot_dates", description="محاسبه تاریخ تولید یا انقضای لات بر اساس تنظیمات کالا بدون ثبت.", parameters_schema=LOT_PREVIEW, handler=preview_product_lot_dates_handler, allowed_roles=roles, required_permissions=["products.view"], category="products", is_readonly=True))
    registry.register(AIFunction(name="reserve_document_code", description="رزرو قطعی شماره سند فاکتور تا ۴ ساعت. شمارنده افزایش می‌یابد. نیازمند تأیید.", parameters_schema=RESERVE, handler=reserve_document_code_handler, allowed_roles=roles, required_permissions=["invoices.add"], category="invoices", requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="cancel_document_code_reservation", description="لغو رزرو شماره سند استفاده‌نشده. نیازمند تأیید.", parameters_schema=RESERVATION_ID, handler=cancel_document_code_reservation_handler, allowed_roles=roles, required_permissions=["invoices.add"], category="invoices", requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="get_business_print_settings", description="تنظیمات چاپ فاکتور پیش‌فرض و به‌تفکیک نوع سند.", parameters_schema=EMPTY, handler=get_business_print_settings_handler, allowed_roles=roles, required_permissions=["settings.print"], category="business", is_readonly=True))
    registry.register(AIFunction(name="update_business_print_settings", description="ذخیره تنظیمات چاپ فاکتور شامل لوگو، مهر، پاورقی و مقیاس. نیازمند تأیید.", parameters_schema=PRINT_UPDATE, handler=update_business_print_settings_handler, allowed_roles=roles, required_permissions=["settings.print"], category="business", requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="get_invoice_share_payment_settings", description="پیش‌فرض پرداخت آنلاین لینک عمومی فاکتور.", parameters_schema=EMPTY, handler=get_invoice_share_payment_settings_handler, allowed_roles=roles, required_permissions=["settings.join"], category="invoices", is_readonly=True))
    registry.register(AIFunction(name="update_invoice_share_payment_settings", description="ذخیره درگاه و فعال‌سازی پیش‌فرض پرداخت لینک فاکتور. نیازمند تأیید.", parameters_schema=SHARE_UPDATE, handler=update_invoice_share_payment_settings_handler, allowed_roles=roles, required_permissions=["settings.business"], category="invoices", requires_approval=True, risk_level="high", is_readonly=False))
    registry.register(AIFunction(name="get_ai_subscription", description="اشتراک فعال هوش مصنوعی همین کسب‌وکار و کاربر متصل.", parameters_schema=EMPTY, handler=get_ai_subscription_handler, allowed_roles=roles, required_permissions=["settings.join"], category="business", is_readonly=True))
    registry.register(AIFunction(name="list_ai_plans", description="پلن‌های فعال هوش مصنوعی و پلن فعلی کسب‌وکار.", parameters_schema=EMPTY, handler=list_ai_plans_handler, allowed_roles=roles, required_permissions=["settings.join"], category="business", is_readonly=True))
    registry.register(AIFunction(name="subscribe_ai_plan", description="خرید یا تغییر پلن هوش مصنوعی با کسر از کیف‌پول در صورت نیاز. نیازمند تأیید.", parameters_schema=AI_SUBSCRIBE, handler=subscribe_ai_plan_handler, allowed_roles=roles, required_permissions=["settings.join"], category="business", requires_approval=True, risk_level="high", is_readonly=False))
    registry.register(AIFunction(name="set_ai_preferred_model", description="تنظیم مدل ترجیحی اشتراک فعال هوش مصنوعی. نیازمند تأیید.", parameters_schema=AI_MODEL, handler=set_ai_preferred_model_handler, allowed_roles=roles, required_permissions=["settings.join"], category="business", requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="get_ai_usage_stats", description="آمار مصرف توکن هوش مصنوعی کسب‌وکار در بازه؛ پیش‌فرض ۳۰ روز.", parameters_schema=AI_USAGE, handler=get_ai_usage_stats_handler, allowed_roles=roles, required_permissions=["settings.join"], category="business", is_readonly=True))

