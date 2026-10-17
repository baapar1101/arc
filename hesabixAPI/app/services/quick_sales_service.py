from __future__ import annotations

import json
import logging
import re
from typing import Any, Dict, List

from sqlalchemy import and_, func, or_
from sqlalchemy.orm import Session

from adapters.api.v1.schema_models.person import PersonCreateRequest
from adapters.db.models.bank_account import BankAccount
from adapters.db.models.business import Business
from adapters.db.models.cash_register import CashRegister
from adapters.db.models.person import Person, PersonType
from adapters.db.models.quick_sales_payment_button import QuickSalesPaymentButton
from adapters.db.models.quick_sales_settings import QuickSalesSetting
from app.core.responses import ApiError
from app.services.person_group_service import assert_assignable_person_group
from app.services.person_service import create_person

logger = logging.getLogger(__name__)

DEFAULT_SHARE_CHANNELS: List[str] = ["sms", "native"]
VALID_SHARE_CHANNEL_CODES = frozenset({"sms", "email", "native"})
DEFAULT_SHARE_EXPIRY_HOURS = 168
MIN_SHARE_EXPIRY_HOURS = 1
MAX_SHARE_EXPIRY_HOURS = 720

PAYMENT_BUTTON_TARGETS = frozenset({"cash_register", "bank", "person"})
PAYMENT_BUTTON_SCOPES = frozenset({"business", "user"})
PAYMENT_BUTTON_RESERVED_SHORTCUTS = frozenset(
    {"ENTER", "ESCAPE", "DELETE", "BACKSPACE", "F5", "+", "-"}
)
MAX_PAYMENT_BUTTONS_PER_SCOPE = 30


def _normalize_payment_button_shortcut(value: Any) -> str | None:
    shortcut = str(value or "").strip().upper().replace(" ", "")
    if not shortcut:
        return None
    if len(shortcut) > 32:
        raise ApiError("PAYMENT_BUTTON_SHORTCUT_INVALID", "میانبر بیش از حد طولانی است", http_status=400)
    if shortcut in PAYMENT_BUTTON_RESERVED_SHORTCUTS:
        raise ApiError(
            "PAYMENT_BUTTON_SHORTCUT_RESERVED",
            "این کلید در فروش سریع یا مرورگر رزرو شده است",
            http_status=400,
        )
    if not re.fullmatch(
        r"(?:F(?:[1-9]|1[0-2])|(?:(?:CTRL|ALT|SHIFT)\+)+(?:[A-Z0-9]|F(?:[1-9]|1[0-2])))",
        shortcut,
    ):
        raise ApiError(
            "PAYMENT_BUTTON_SHORTCUT_INVALID",
            "میانبر باید یکی از کلیدهای F یا ترکیبی مانند Alt+1 باشد",
            http_status=400,
        )
    return shortcut


def _payment_button_target(
    db: Session,
    business_id: int,
    target_type: str,
    target_id: Any,
) -> tuple[Any, str]:
    try:
        parsed_id = int(target_id)
    except (TypeError, ValueError) as exc:
        raise ApiError("PAYMENT_BUTTON_TARGET_REQUIRED", "مقصد پرداخت الزامی است", http_status=400) from exc

    if target_type == "cash_register":
        target = (
            db.query(CashRegister)
            .filter(
                CashRegister.id == parsed_id,
                CashRegister.business_id == int(business_id),
                CashRegister.is_active == True,  # noqa: E712
            )
            .first()
        )
        name = getattr(target, "name", None)
    elif target_type == "bank":
        target = (
            db.query(BankAccount)
            .filter(
                BankAccount.id == parsed_id,
                BankAccount.business_id == int(business_id),
                BankAccount.is_active == True,  # noqa: E712
            )
            .first()
        )
        name = getattr(target, "name", None)
    elif target_type == "person":
        target = (
            db.query(Person)
            .filter(Person.id == parsed_id, Person.business_id == int(business_id))
            .first()
        )
        name = getattr(target, "alias_name", None)
    else:
        raise ApiError("PAYMENT_BUTTON_TARGET_TYPE_INVALID", "نوع مقصد پرداخت نامعتبر است", http_status=400)

    if not target:
        raise ApiError("PAYMENT_BUTTON_TARGET_NOT_FOUND", "مقصد پرداخت یافت نشد یا غیرفعال است", http_status=404)
    return target, str(name or "مقصد پرداخت")


def _payment_button_target_id(row: QuickSalesPaymentButton) -> int:
    if row.target_type == "cash_register":
        return int(row.cash_register_id)
    if row.target_type == "bank":
        return int(row.bank_account_id)
    return int(row.person_id)


def _payment_button_to_dict(db: Session, row: QuickSalesPaymentButton) -> Dict[str, Any]:
    _, target_name = _payment_button_target(
        db, row.business_id, row.target_type, _payment_button_target_id(row)
    )
    # برای شخص، خود نام شخص روی دکمه نمایش داده می‌شود تا عنوان مبهمی مثل «کارت شخصی» نسازیم.
    label = target_name if row.target_type == "person" else (row.label or target_name)
    return {
        "id": int(row.id),
        "business_id": int(row.business_id),
        "scope": row.scope,
        "owner_user_id": int(row.owner_user_id) if row.owner_user_id else None,
        "target_type": row.target_type,
        "target_id": _payment_button_target_id(row),
        "target_name": target_name,
        "label": label,
        "shortcut": row.shortcut,
        "position": int(row.position),
        "is_active": bool(row.is_active),
        "is_system": False,
    }


def _assert_payment_button_shortcut_available(
    db: Session,
    *,
    business_id: int,
    scope: str,
    owner_user_id: int | None,
    shortcut: str | None,
    exclude_id: int | None = None,
) -> None:
    if not shortcut:
        return
    query = db.query(QuickSalesPaymentButton).filter(
        QuickSalesPaymentButton.business_id == int(business_id),
        QuickSalesPaymentButton.is_active == True,  # noqa: E712
        func.upper(QuickSalesPaymentButton.shortcut) == shortcut,
    )
    if exclude_id is not None:
        query = query.filter(QuickSalesPaymentButton.id != int(exclude_id))
    if scope == "business":
        query = query.filter(
            or_(
                QuickSalesPaymentButton.scope == "business",
                QuickSalesPaymentButton.scope == "user",
            )
        )
    else:
        query = query.filter(
            or_(
                QuickSalesPaymentButton.scope == "business",
                and_(
                    QuickSalesPaymentButton.scope == "user",
                    QuickSalesPaymentButton.owner_user_id == int(owner_user_id),
                ),
            )
        )
    if query.first():
        raise ApiError(
            "PAYMENT_BUTTON_SHORTCUT_CONFLICT",
            "این میانبر قبلاً برای یک دکمه پرداخت استفاده شده است",
            http_status=409,
        )


def list_quick_sales_payment_buttons(
    db: Session, business_id: int, user_id: int
) -> List[Dict[str, Any]]:
    rows = (
        db.query(QuickSalesPaymentButton)
        .filter(
            QuickSalesPaymentButton.business_id == int(business_id),
            QuickSalesPaymentButton.is_active == True,  # noqa: E712
            or_(
                QuickSalesPaymentButton.scope == "business",
                and_(
                    QuickSalesPaymentButton.scope == "user",
                    QuickSalesPaymentButton.owner_user_id == int(user_id),
                ),
            ),
        )
        .order_by(QuickSalesPaymentButton.position.asc(), QuickSalesPaymentButton.id.asc())
        .all()
    )
    result = [_payment_button_to_dict(db, row) for row in rows]
    if result:
        return result

    settings = (
        db.query(QuickSalesSetting)
        .filter(QuickSalesSetting.business_id == int(business_id))
        .first()
    )
    register_id = getattr(settings, "default_cash_register_id", None)
    if not register_id:
        return []
    try:
        _, name = _payment_button_target(db, business_id, "cash_register", register_id)
    except ApiError:
        return []
    return [{
        "id": f"system-cash-{int(register_id)}",
        "business_id": int(business_id),
        "scope": "system",
        "owner_user_id": None,
        "target_type": "cash_register",
        "target_id": int(register_id),
        "target_name": name,
        "label": name,
        "shortcut": None,
        "position": 0,
        "is_active": True,
        "is_system": True,
    }]


def create_quick_sales_payment_button(
    db: Session,
    *,
    business_id: int,
    user_id: int,
    payload: Dict[str, Any],
    can_manage_business: bool,
) -> Dict[str, Any]:
    scope = str(payload.get("scope") or "user").strip().lower()
    if scope not in PAYMENT_BUTTON_SCOPES:
        raise ApiError("PAYMENT_BUTTON_SCOPE_INVALID", "دامنه دکمه نامعتبر است", http_status=400)
    if scope == "business" and not can_manage_business:
        raise ApiError("FORBIDDEN", "مجوز تعریف دکمه مشترک را ندارید", http_status=403)
    target_type = str(payload.get("target_type") or "").strip().lower()
    if target_type not in PAYMENT_BUTTON_TARGETS:
        raise ApiError("PAYMENT_BUTTON_TARGET_TYPE_INVALID", "نوع مقصد پرداخت نامعتبر است", http_status=400)
    target, target_name = _payment_button_target(
        db, business_id, target_type, payload.get("target_id")
    )
    owner_user_id = int(user_id) if scope == "user" else None
    count = (
        db.query(func.count(QuickSalesPaymentButton.id))
        .filter(
            QuickSalesPaymentButton.business_id == int(business_id),
            QuickSalesPaymentButton.scope == scope,
            QuickSalesPaymentButton.owner_user_id == owner_user_id,
            QuickSalesPaymentButton.is_active == True,  # noqa: E712
        )
        .scalar()
        or 0
    )
    if int(count) >= MAX_PAYMENT_BUTTONS_PER_SCOPE:
        raise ApiError("PAYMENT_BUTTON_LIMIT", "حداکثر تعداد دکمه‌های پرداخت ثبت شده است", http_status=400)
    shortcut = _normalize_payment_button_shortcut(payload.get("shortcut"))
    _assert_payment_button_shortcut_available(
        db,
        business_id=business_id,
        scope=scope,
        owner_user_id=owner_user_id,
        shortcut=shortcut,
    )
    max_position = (
        db.query(func.max(QuickSalesPaymentButton.position))
        .filter(
            QuickSalesPaymentButton.business_id == int(business_id),
            QuickSalesPaymentButton.scope == scope,
            QuickSalesPaymentButton.owner_user_id == owner_user_id,
        )
        .scalar()
    )
    label = str(payload.get("label") or "").strip() or target_name
    if target_type == "person":
        label = target_name
    row = QuickSalesPaymentButton(
        business_id=int(business_id),
        scope=scope,
        owner_user_id=owner_user_id,
        target_type=target_type,
        cash_register_id=int(target.id) if target_type == "cash_register" else None,
        bank_account_id=int(target.id) if target_type == "bank" else None,
        person_id=int(target.id) if target_type == "person" else None,
        label=label[:120],
        shortcut=shortcut,
        position=(int(max_position) + 1) if max_position is not None else 0,
        is_active=True,
        created_by_user_id=int(user_id),
    )
    db.add(row)
    db.commit()
    db.refresh(row)
    return _payment_button_to_dict(db, row)


def update_quick_sales_payment_button(
    db: Session,
    *,
    business_id: int,
    button_id: int,
    user_id: int,
    payload: Dict[str, Any],
    can_manage_business: bool,
) -> Dict[str, Any]:
    row = (
        db.query(QuickSalesPaymentButton)
        .filter(
            QuickSalesPaymentButton.id == int(button_id),
            QuickSalesPaymentButton.business_id == int(business_id),
            QuickSalesPaymentButton.is_active == True,  # noqa: E712
        )
        .first()
    )
    if not row:
        raise ApiError("PAYMENT_BUTTON_NOT_FOUND", "دکمه پرداخت یافت نشد", http_status=404)
    if row.scope == "business" and not can_manage_business:
        raise ApiError("FORBIDDEN", "مجوز ویرایش دکمه مشترک را ندارید", http_status=403)
    if row.scope == "user" and int(row.owner_user_id or 0) != int(user_id):
        raise ApiError("FORBIDDEN", "این دکمه متعلق به کاربر دیگری است", http_status=403)

    target_type = str(payload.get("target_type") or row.target_type).strip().lower()
    target_id = payload.get("target_id", _payment_button_target_id(row))
    target, target_name = _payment_button_target(db, business_id, target_type, target_id)
    shortcut = _normalize_payment_button_shortcut(payload.get("shortcut", row.shortcut))
    _assert_payment_button_shortcut_available(
        db,
        business_id=business_id,
        scope=row.scope,
        owner_user_id=row.owner_user_id,
        shortcut=shortcut,
        exclude_id=row.id,
    )
    row.target_type = target_type
    row.cash_register_id = int(target.id) if target_type == "cash_register" else None
    row.bank_account_id = int(target.id) if target_type == "bank" else None
    row.person_id = int(target.id) if target_type == "person" else None
    row.label = (
        target_name
        if target_type == "person"
        else (str(payload.get("label") or row.label or target_name).strip() or target_name)[:120]
    )
    row.shortcut = shortcut
    if "position" in payload:
        row.position = max(0, int(payload.get("position") or 0))
    db.commit()
    db.refresh(row)
    return _payment_button_to_dict(db, row)


def delete_quick_sales_payment_button(
    db: Session,
    *,
    business_id: int,
    button_id: int,
    user_id: int,
    can_manage_business: bool,
) -> None:
    row = (
        db.query(QuickSalesPaymentButton)
        .filter(
            QuickSalesPaymentButton.id == int(button_id),
            QuickSalesPaymentButton.business_id == int(business_id),
            QuickSalesPaymentButton.is_active == True,  # noqa: E712
        )
        .first()
    )
    if not row:
        raise ApiError("PAYMENT_BUTTON_NOT_FOUND", "دکمه پرداخت یافت نشد", http_status=404)
    if row.scope == "business" and not can_manage_business:
        raise ApiError("FORBIDDEN", "مجوز حذف دکمه مشترک را ندارید", http_status=403)
    if row.scope == "user" and int(row.owner_user_id or 0) != int(user_id):
        raise ApiError("FORBIDDEN", "این دکمه متعلق به کاربر دیگری است", http_status=403)
    row.is_active = False
    db.commit()


def reorder_quick_sales_payment_buttons(
    db: Session,
    *,
    business_id: int,
    user_id: int,
    button_ids: List[Any],
    can_manage_business: bool,
) -> List[Dict[str, Any]]:
    """ترتیب مؤثر دکمه‌های مشترک و شخصی کاربر را ذخیره می‌کند."""
    try:
        ordered_ids = [int(value) for value in button_ids]
    except (TypeError, ValueError) as exc:
        raise ApiError(
            "PAYMENT_BUTTON_ORDER_INVALID",
            "ترتیب دکمه‌های پرداخت نامعتبر است",
            http_status=400,
        ) from exc
    if len(ordered_ids) != len(set(ordered_ids)):
        raise ApiError(
            "PAYMENT_BUTTON_ORDER_INVALID",
            "شناسه تکراری در ترتیب دکمه‌ها وجود دارد",
            http_status=400,
        )
    rows = (
        db.query(QuickSalesPaymentButton)
        .filter(
            QuickSalesPaymentButton.business_id == int(business_id),
            QuickSalesPaymentButton.id.in_(ordered_ids),
            QuickSalesPaymentButton.is_active == True,  # noqa: E712
        )
        .all()
    )
    by_id = {int(row.id): row for row in rows}
    if set(by_id) != set(ordered_ids):
        raise ApiError(
            "PAYMENT_BUTTON_NOT_FOUND",
            "یکی از دکمه‌های پرداخت یافت نشد",
            http_status=404,
        )
    for row in rows:
        if row.scope == "business" and not can_manage_business:
            raise ApiError(
                "FORBIDDEN",
                "مجوز تغییر ترتیب دکمه‌های مشترک را ندارید",
                http_status=403,
            )
        if row.scope == "user" and int(row.owner_user_id or 0) != int(user_id):
            raise ApiError("FORBIDDEN", "این دکمه متعلق به کاربر دیگری است", http_status=403)
    for position, button_id in enumerate(ordered_ids):
        by_id[button_id].position = position
    db.commit()
    return list_quick_sales_payment_buttons(db, business_id, user_id)


def normalize_default_share_channels(value: Any) -> List[str]:
    """نرمال‌سازی لیست کانال‌های اشتراک‌گذاری."""
    if value is None:
        return list(DEFAULT_SHARE_CHANNELS)
    parsed = value
    if isinstance(value, str):
        try:
            parsed = json.loads(value)
        except json.JSONDecodeError:
            return list(DEFAULT_SHARE_CHANNELS)
    if not isinstance(parsed, list):
        return list(DEFAULT_SHARE_CHANNELS)
    channels = [str(c).strip().lower() for c in parsed if str(c).strip()]
    filtered = [c for c in channels if c in VALID_SHARE_CHANNEL_CODES]
    return filtered or list(DEFAULT_SHARE_CHANNELS)


def normalize_share_expiry_hours(value: Any) -> int:
    try:
        hours = int(value)
    except (TypeError, ValueError):
        return DEFAULT_SHARE_EXPIRY_HOURS
    return max(MIN_SHARE_EXPIRY_HOURS, min(MAX_SHARE_EXPIRY_HOURS, hours))


def _share_settings_from_obj(obj: QuickSalesSetting | None) -> Dict[str, Any]:
    if obj is None:
        return {
            "default_share_online_payment": True,
            "default_share_gateway_id": None,
            "default_share_channels": list(DEFAULT_SHARE_CHANNELS),
            "default_share_expiry_hours": DEFAULT_SHARE_EXPIRY_HOURS,
        }
    return {
        "default_share_online_payment": bool(getattr(obj, "default_share_online_payment", True)),
        "default_share_gateway_id": (
            int(obj.default_share_gateway_id) if obj.default_share_gateway_id else None
        ),
        "default_share_channels": normalize_default_share_channels(obj.default_share_channels),
        "default_share_expiry_hours": normalize_share_expiry_hours(
            getattr(obj, "default_share_expiry_hours", DEFAULT_SHARE_EXPIRY_HOURS)
        ),
    }


def _validate_share_gateway_id(db: Session, business_id: int, gateway_id: int) -> None:
    from adapters.db.models.payment_gateway import BusinessPaymentGateway, PaymentGateway

    gw = (
        db.query(PaymentGateway)
        .filter(PaymentGateway.id == int(gateway_id), PaymentGateway.is_active == True)  # noqa: E712
        .first()
    )
    if not gw:
        raise ApiError("GATEWAY_NOT_FOUND", "درگاه پرداخت یافت نشد یا غیرفعال است", http_status=404)
    links = (
        db.query(BusinessPaymentGateway)
        .filter(
            BusinessPaymentGateway.business_id == int(business_id),
            BusinessPaymentGateway.is_active == True,  # noqa: E712
        )
        .all()
    )
    if links:
        allowed = {int(lg.gateway_id) for lg in links}
        if int(gateway_id) not in allowed:
            raise ApiError(
                "GATEWAY_NOT_LINKED",
                "این درگاه برای این کسب‌وکار فعال نیست",
                http_status=400,
            )


def get_quick_sales_settings(db: Session, business_id: int) -> Dict[str, Any]:
    """دریافت تنظیمات فروش سریع یک کسب‌وکار"""
    obj = (
        db.query(QuickSalesSetting)
        .filter(QuickSalesSetting.business_id == int(business_id))
        .first()
    )
    
    # دریافت کسب‌وکار برای دسترسی به ارز پیش‌فرض
    business = db.query(Business).filter(Business.id == int(business_id)).first()
    business_default_currency_id = business.default_currency_id if business else None
    
    if not obj:
        # بازگشت مقادیر پیش‌فرض
        return {
            "business_id": int(business_id),
            "default_anonymous_customer_id": None,
            "auto_create_anonymous_customer": True,
            "anonymous_customer_name": "مشتری ناشناس",
            "quick_customer_group_id": None,
            "default_warehouse_id": None,
            "default_cash_register_id": None,
            "default_currency_id": business_default_currency_id,
            "default_price_list_id": None,
            "auto_print": False,
            "print_template_id": None,
            "print_paper_size": "80mm",
            "enable_warehouse_document": True,
            "warehouse_document_type": "posted",
            "auto_post_warehouse": True,
            "show_inventory": True,
            "enable_stock_shortage_override": False,
            "auto_create_payment_document": True,
            "show_purchase_price": False,
            **_share_settings_from_obj(None),
        }
    
    # اگر ارز پیش‌فرض در تنظیمات تنظیم نشده باشد، از ارز پیش‌فرض کسب‌وکار استفاده می‌کنیم
    currency_id = int(obj.default_currency_id) if obj.default_currency_id else business_default_currency_id
    
    return {
        "business_id": int(business_id),
        "default_anonymous_customer_id": int(obj.default_anonymous_customer_id) if obj.default_anonymous_customer_id else None,
        "auto_create_anonymous_customer": bool(obj.auto_create_anonymous_customer),
        "anonymous_customer_name": obj.anonymous_customer_name if obj.anonymous_customer_name else "مشتری ناشناس",
        "quick_customer_group_id": int(obj.quick_customer_group_id) if obj.quick_customer_group_id else None,
        "default_warehouse_id": int(obj.default_warehouse_id) if obj.default_warehouse_id else None,
        "default_cash_register_id": int(obj.default_cash_register_id) if obj.default_cash_register_id else None,
        "default_currency_id": currency_id,
        "default_price_list_id": int(obj.default_price_list_id) if obj.default_price_list_id else None,
        "auto_print": bool(obj.auto_print),
        "print_template_id": int(obj.print_template_id) if obj.print_template_id else None,
        "print_paper_size": (getattr(obj, "print_paper_size", None) or "80mm"),
        "enable_warehouse_document": bool(getattr(obj, 'enable_warehouse_document', True)),
        "warehouse_document_type": str(getattr(obj, 'warehouse_document_type', 'posted')),
        "auto_post_warehouse": bool(obj.auto_post_warehouse),
        "show_inventory": bool(obj.show_inventory),
        "enable_stock_shortage_override": bool(
            getattr(obj, "enable_stock_shortage_override", False)
        ),
        "auto_create_payment_document": bool(obj.auto_create_payment_document),
        "show_purchase_price": bool(obj.show_purchase_price),
        **_share_settings_from_obj(obj),
    }


def update_quick_sales_settings(db: Session, business_id: int, payload: Dict[str, Any], user_id: int | None = None) -> Dict[str, Any]:
    """به‌روزرسانی تنظیمات فروش سریع یک کسب‌وکار"""
    obj = (
        db.query(QuickSalesSetting)
        .filter(QuickSalesSetting.business_id == int(business_id))
        .first()
    )
    
    if not obj:
        obj = QuickSalesSetting(business_id=int(business_id))
        db.add(obj)
    
    # به‌روزرسانی فیلدها
    if "default_anonymous_customer_id" in payload:
        customer_id = payload.get("default_anonymous_customer_id")
        if customer_id is not None:
            # بررسی وجود شخص
            person = db.query(Person).filter(
                and_(
                    Person.id == int(customer_id),
                    Person.business_id == int(business_id),
                    Person.person_types.like(f'%{PersonType.CUSTOMER.value}%'),
                )
            ).first()
            if not person:
                raise ApiError("PERSON_NOT_FOUND", "مشتری یافت نشد", http_status=404)
        obj.default_anonymous_customer_id = int(customer_id) if customer_id is not None else None
    
    if "auto_create_anonymous_customer" in payload:
        obj.auto_create_anonymous_customer = bool(payload.get("auto_create_anonymous_customer"))
    
    if "anonymous_customer_name" in payload:
        name_data = payload.get("anonymous_customer_name")
        if name_data is not None:
            obj.anonymous_customer_name = str(name_data).strip()
        else:
            obj.anonymous_customer_name = None

    if "quick_customer_group_id" in payload:
        group_id = payload.get("quick_customer_group_id")
        if group_id is not None:
            assert_assignable_person_group(db, int(business_id), int(group_id))
        obj.quick_customer_group_id = int(group_id) if group_id is not None else None
    
    if "default_warehouse_id" in payload:
        warehouse_id = payload.get("default_warehouse_id")
        if warehouse_id is not None:
            from adapters.db.models.warehouse import Warehouse
            warehouse = db.query(Warehouse).filter(
                and_(
                    Warehouse.id == int(warehouse_id),
                    Warehouse.business_id == int(business_id),
                )
            ).first()
            if not warehouse:
                raise ApiError("WAREHOUSE_NOT_FOUND", "انبار یافت نشد", http_status=404)
        obj.default_warehouse_id = int(warehouse_id) if warehouse_id is not None else None
    
    if "default_cash_register_id" in payload:
        cash_register_id = payload.get("default_cash_register_id")
        if cash_register_id is not None:
            from adapters.db.models.cash_register import CashRegister
            cash_register = db.query(CashRegister).filter(
                and_(
                    CashRegister.id == int(cash_register_id),
                    CashRegister.business_id == int(business_id),
                )
            ).first()
            if not cash_register:
                raise ApiError("CASH_REGISTER_NOT_FOUND", "صندوق یافت نشد", http_status=404)
        obj.default_cash_register_id = int(cash_register_id) if cash_register_id is not None else None
    
    if "default_currency_id" in payload:
        currency_id = payload.get("default_currency_id")
        if currency_id is not None:
            from adapters.db.models.currency import Currency
            currency = db.query(Currency).filter(Currency.id == int(currency_id)).first()
            if not currency:
                raise ApiError("CURRENCY_NOT_FOUND", "ارز یافت نشد", http_status=404)
        obj.default_currency_id = int(currency_id) if currency_id is not None else None
    
    if "default_price_list_id" in payload:
        price_list_id = payload.get("default_price_list_id")
        if price_list_id is not None:
            from adapters.db.models.price_list import PriceList
            price_list = db.query(PriceList).filter(
                and_(
                    PriceList.id == int(price_list_id),
                    PriceList.business_id == int(business_id),
                )
            ).first()
            if not price_list:
                raise ApiError("PRICE_LIST_NOT_FOUND", "لیست قیمت یافت نشد", http_status=404)
        obj.default_price_list_id = int(price_list_id) if price_list_id is not None else None
    
    if "auto_print" in payload:
        obj.auto_print = bool(payload.get("auto_print"))
    
    if "print_template_id" in payload:
        template_id = payload.get("print_template_id")
        obj.print_template_id = int(template_id) if template_id is not None else None

    if "print_paper_size" in payload:
        from app.services.pdf.page_size import is_receipt_paper

        raw = payload.get("print_paper_size")
        size = str(raw).strip() if raw not in (None, "") else None
        if size and size not in ("A4", "A5", "A6") and not is_receipt_paper(size):
            raise ApiError("INVALID_PAPER_SIZE", "سایز کاغذ چاپ نامعتبر است", http_status=400)
        obj.print_paper_size = size
    
    if "enable_warehouse_document" in payload:
        obj.enable_warehouse_document = bool(payload.get("enable_warehouse_document"))
    
    if "warehouse_document_type" in payload:
        doc_type = payload.get("warehouse_document_type")
        if doc_type not in ("draft", "posted"):
            raise ApiError("INVALID_WAREHOUSE_DOCUMENT_TYPE", "نوع سند حواله باید draft یا posted باشد", http_status=400)
        obj.warehouse_document_type = str(doc_type)
    
    if "auto_post_warehouse" in payload:
        obj.auto_post_warehouse = bool(payload.get("auto_post_warehouse"))
    
    if "show_inventory" in payload:
        obj.show_inventory = bool(payload.get("show_inventory"))

    if "enable_stock_shortage_override" in payload:
        obj.enable_stock_shortage_override = bool(
            payload.get("enable_stock_shortage_override")
        )
    
    if "auto_create_payment_document" in payload:
        obj.auto_create_payment_document = bool(payload.get("auto_create_payment_document"))
    
    if "show_purchase_price" in payload:
        obj.show_purchase_price = bool(payload.get("show_purchase_price"))

    if "default_share_online_payment" in payload:
        obj.default_share_online_payment = bool(payload.get("default_share_online_payment"))

    if "default_share_gateway_id" in payload:
        gateway_id = payload.get("default_share_gateway_id")
        if gateway_id is not None:
            _validate_share_gateway_id(db, business_id, int(gateway_id))
        obj.default_share_gateway_id = int(gateway_id) if gateway_id is not None else None

    if "default_share_channels" in payload:
        obj.default_share_channels = normalize_default_share_channels(payload.get("default_share_channels"))

    if "default_share_expiry_hours" in payload:
        obj.default_share_expiry_hours = normalize_share_expiry_hours(payload.get("default_share_expiry_hours"))
    
    db.flush()
    db.commit()
    return get_quick_sales_settings(db, business_id)


def get_or_create_anonymous_customer(
    db: Session, 
    business_id: int, 
    settings: Dict[str, Any] | None = None
) -> Person:
    """دریافت یا ایجاد مشتری ناشناس"""
    if settings is None:
        settings = get_quick_sales_settings(db, business_id)
    
    # بررسی مشتری پیش‌فرض
    customer_id = settings.get("default_anonymous_customer_id")
    if customer_id:
        customer = db.query(Person).filter(
            and_(
                Person.id == int(customer_id),
                Person.business_id == int(business_id),
                Person.person_types.like(f'%{PersonType.CUSTOMER.value}%'),
            )
        ).first()
        if customer:
            return customer
    
    # جستجوی مشتری ناشناس موجود
    customer_name = settings.get("anonymous_customer_name", "مشتری ناشناس")
    name_fa = str(customer_name) if customer_name else "مشتری ناشناس"
    
    # جستجوی مشتری با نام و نوع مشتری
    # اولویت با مشتری‌هایی که کد دارند (کد None نباشد)
    customer = db.query(Person).filter(
        and_(
            Person.business_id == int(business_id),
            Person.alias_name == name_fa,
            Person.person_types.like(f'%{PersonType.CUSTOMER.value}%'),
            Person.code.isnot(None),  # اولویت با مشتری‌هایی که کد دارند
        )
    ).first()
    
    # اگر مشتری با کد پیدا نشد، مشتری بدون کد را جستجو کن
    if not customer:
        customer = db.query(Person).filter(
            and_(
                Person.business_id == int(business_id),
                Person.alias_name == name_fa,
                Person.person_types.like(f'%{PersonType.CUSTOMER.value}%'),
            )
        ).first()
    
    if customer:
        # به‌روزرسانی تنظیمات (مستقیماً بدون بررسی مجدد)
        obj = (
            db.query(QuickSalesSetting)
            .filter(QuickSalesSetting.business_id == int(business_id))
            .first()
        )
        if not obj:
            obj = QuickSalesSetting(business_id=int(business_id))
            db.add(obj)
        obj.default_anonymous_customer_id = customer.id
        db.flush()
        db.commit()
        return customer
    
    # ایجاد جدید با استفاده از create_person برای تولید صحیح کد
    if settings.get("auto_create_anonymous_customer", True):
        # استفاده از create_person برای تولید صحیح کد
        person_data = PersonCreateRequest(
            alias_name=name_fa,
            person_types=[PersonType.CUSTOMER],
            code=None,  # None = تولید خودکار کد
        )
        
        result = create_person(db, int(business_id), person_data)
        logger.debug(f"create_person result: {result}")
        customer_id = result.get("data", {}).get("id")
        
        if not customer_id:
            logger.error(f"Failed to get customer_id from create_person result: {result}")
            raise ApiError(
                "FAILED_TO_CREATE_ANONYMOUS_CUSTOMER",
                "خطا در ایجاد مشتری ناشناس",
                http_status=500
            )
        
        # دریافت مشتری ایجاد شده
        customer = db.query(Person).filter(
            and_(
                Person.id == int(customer_id),
                Person.business_id == int(business_id),
            )
        ).first()
        
        if not customer:
            raise ApiError(
                "ANONYMOUS_CUSTOMER_NOT_FOUND",
                "مشتری ناشناس ایجاد شد اما یافت نشد",
                http_status=500
            )
        
        # به‌روزرسانی تنظیمات (مستقیماً بدون بررسی مجدد)
        obj = (
            db.query(QuickSalesSetting)
            .filter(QuickSalesSetting.business_id == int(business_id))
            .first()
        )
        if not obj:
            obj = QuickSalesSetting(business_id=int(business_id))
            db.add(obj)
        obj.default_anonymous_customer_id = customer.id
        db.flush()
        db.commit()
        return customer
    
    raise ApiError(
        "ANONYMOUS_CUSTOMER_NOT_SET", 
        "مشتری ناشناس تعریف نشده است. لطفاً در تنظیمات فروش سریع یک مشتری پیش‌فرض انتخاب کنید.",
        http_status=400
    )
