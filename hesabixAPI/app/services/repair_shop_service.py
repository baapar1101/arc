"""
سرویس اصلی افزونه مدیریت تعمیرگاه
"""
from __future__ import annotations

import secrets
import logging
from datetime import datetime, date
from typing import Any, Dict, List, Optional
from decimal import Decimal

from sqlalchemy.orm import Session
from sqlalchemy import and_, or_, func

from adapters.db.models.repair_shop import (
    RepairShopSettings,
    RepairTechnician,
    RepairOrder,
    RepairOrderPart,
    RepairOrderStatus,
    RepairOrderAttachment,
    RepairInvoice,
)
from adapters.db.models.business import Business
from adapters.db.models.person import Person
from adapters.db.models.product import Product
from adapters.db.models.fiscal_year import FiscalYear
from adapters.db.models.currency import Currency
from adapters.db.repositories.repair_shop_repository import (
    RepairShopSettingsRepository,
    RepairTechnicianRepository,
    RepairOrderRepository,
    RepairOrderPartRepository,
    RepairOrderStatusRepository,
    RepairOrderAttachmentRepository,
    RepairInvoiceRepository,
)
from app.core.responses import ApiError
from app.core.repair_shop_plugin_dependency import check_repair_shop_plugin_active

logger = logging.getLogger(__name__)

# الفبای برای تولید کدهای رندوم
BASE62_ALPHABET = "23456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"

# وضعیت‌های مجاز
VALID_STATUSES = [
    "received",
    "assigned",
    "in_progress",
    "waiting_parts",
    "testing",
    "completed_fixed",
    "completed_unfixable",
    "ready_for_pickup",
    "delivered",
    "cancelled"
]


# ========== Helper Functions ==========

def _generate_random_code(length: int = 8) -> str:
    """تولید کد رندوم"""
    return "".join(secrets.choice(BASE62_ALPHABET) for _ in range(length))


def _check_plugin_active(db: Session, business_id: int) -> None:
    """بررسی فعال بودن افزونه"""
    if not check_repair_shop_plugin_active(db, business_id):
        raise ApiError(
            "PLUGIN_NOT_ACTIVE",
            "افزونه مدیریت تعمیرگاه فعال نیست",
            http_status=403
        )


def _get_current_fiscal_year(db: Session, business_id: int) -> FiscalYear:
    """دریافت سال مالی جاری"""
    today = date.today()
    
    fiscal_year = db.query(FiscalYear).filter(
        and_(
            FiscalYear.business_id == business_id,
            FiscalYear.start_date <= today,
            FiscalYear.end_date >= today
        )
    ).first()
    
    if not fiscal_year:
        raise ApiError(
            "NO_ACTIVE_FISCAL_YEAR",
            "سال مالی فعالی یافت نشد",
            http_status=400
        )
    
    return fiscal_year


# ========== تنظیمات تعمیرگاه ==========

def get_repair_shop_settings(db: Session, business_id: int) -> Dict[str, Any]:
    """دریافت تنظیمات تعمیرگاه"""
    _check_plugin_active(db, business_id)
    
    repo = RepairShopSettingsRepository(db)
    settings = repo.get_by_business(business_id)
    
    if not settings:
        # ایجاد تنظیمات پیش‌فرض
        settings = repo.create_or_update(business_id, {})
    
    return {
        "id": settings.id,
        "business_id": settings.business_id,
        "receipt_code_format": settings.receipt_code_format,
        "receipt_code_prefix": settings.receipt_code_prefix,
        "auto_send_sms_on_receive": settings.auto_send_sms_on_receive,
        "auto_send_sms_on_status_change": settings.auto_send_sms_on_status_change,
        "auto_send_email_on_receive": settings.auto_send_email_on_receive,
        "auto_send_email_on_status_change": settings.auto_send_email_on_status_change,
        "sms_templates": settings.sms_templates or {},
        "email_templates": settings.email_templates or {},
        "default_service_product_id": settings.default_service_product_id,
        "default_warehouse_id": settings.default_warehouse_id,
        "extra_settings": settings.extra_settings or {},
    }


def update_repair_shop_settings(
    db: Session,
    business_id: int,
    settings_data: Dict[str, Any]
) -> Dict[str, Any]:
    """به‌روزرسانی تنظیمات تعمیرگاه"""
    _check_plugin_active(db, business_id)
    
    repo = RepairShopSettingsRepository(db)
    settings = repo.create_or_update(business_id, settings_data)
    
    db.commit()
    
    return get_repair_shop_settings(db, business_id)


# ========== تعمیرکاران ==========

def list_technicians(
    db: Session,
    business_id: int,
    only_active: bool = True,
    offset: int = 0,
    limit: int = 100
) -> Dict[str, Any]:
    """لیست تعمیرکاران"""
    _check_plugin_active(db, business_id)
    
    repo = RepairTechnicianRepository(db)
    technicians = repo.list_by_business(business_id, only_active, offset, limit)
    
    items = []
    for tech in technicians:
        # دریافت اطلاعات Person
        person = db.query(Person).filter(Person.id == tech.person_id).first()
        
        items.append({
            "id": tech.id,
            "business_id": tech.business_id,
            "person_id": tech.person_id,
            "person_name": person.name if person else "",
            "code": tech.code,
            "commission_type": tech.commission_type,
            "commission_value": float(tech.commission_value),
            "is_active": tech.is_active,
            "extra_info": tech.extra_info or {},
        })
    
    return {
        "items": items,
        "total": len(items),
    }


def get_technician(
    db: Session,
    business_id: int,
    technician_id: int
) -> Dict[str, Any]:
    """دریافت اطلاعات یک تعمیرکار"""
    _check_plugin_active(db, business_id)
    
    repo = RepairTechnicianRepository(db)
    tech = repo.get_by_id(technician_id, business_id)
    
    if not tech:
        raise ApiError("TECHNICIAN_NOT_FOUND", "تعمیرکار یافت نشد", http_status=404)
    
    # دریافت اطلاعات Person
    person = db.query(Person).filter(Person.id == tech.person_id).first()
    
    return {
        "id": tech.id,
        "business_id": tech.business_id,
        "person_id": tech.person_id,
        "person_name": person.name if person else "",
        "code": tech.code,
        "commission_type": tech.commission_type,
        "commission_value": float(tech.commission_value),
        "is_active": tech.is_active,
        "extra_info": tech.extra_info or {},
    }


def create_technician(
    db: Session,
    business_id: int,
    data: Dict[str, Any],
    user_id: int
) -> Dict[str, Any]:
    """ایجاد تعمیرکار جدید"""
    _check_plugin_active(db, business_id)
    
    # بررسی Person
    person_id = data.get("person_id")
    if not person_id:
        raise ApiError("PERSON_ID_REQUIRED", "شناسه Person الزامی است", http_status=400)
    
    person = db.query(Person).filter(
        and_(
            Person.id == person_id,
            Person.business_id == business_id
        )
    ).first()
    
    if not person:
        raise ApiError("PERSON_NOT_FOUND", "Person یافت نشد", http_status=404)
    
    # تولید کد (اگر ارسال نشده باشد)
    code = data.get("code")
    if not code:
        # تولید کد اتوماتیک
        repo = RepairTechnicianRepository(db)
        counter = 1
        while True:
            code = f"TECH-{counter:04d}"
            existing = repo.get_by_code(code, business_id)
            if not existing:
                break
            counter += 1
    
    # بررسی تکراری بودن کد
    repo = RepairTechnicianRepository(db)
    existing = repo.get_by_code(code, business_id)
    if existing:
        raise ApiError("CODE_ALREADY_EXISTS", "کد تعمیرکار تکراری است", http_status=409)
    
    # ایجاد
    tech_data = {
        "business_id": business_id,
        "person_id": person_id,
        "code": code,
        "commission_type": data.get("commission_type", "percentage"),
        "commission_value": Decimal(str(data.get("commission_value", 0))),
        "is_active": data.get("is_active", True),
        "extra_info": data.get("extra_info"),
    }
    
    tech = repo.create(tech_data)
    db.commit()
    
    return get_technician(db, business_id, tech.id)


def update_technician(
    db: Session,
    business_id: int,
    technician_id: int,
    data: Dict[str, Any],
    user_id: int
) -> Dict[str, Any]:
    """به‌روزرسانی تعمیرکار"""
    _check_plugin_active(db, business_id)
    
    repo = RepairTechnicianRepository(db)
    tech = repo.get_by_id(technician_id, business_id)
    
    if not tech:
        raise ApiError("TECHNICIAN_NOT_FOUND", "تعمیرکار یافت نشد", http_status=404)
    
    # بررسی تکراری بودن کد (اگر تغییر کرده باشد)
    if "code" in data and data["code"] != tech.code:
        existing = repo.get_by_code(data["code"], business_id)
        if existing:
            raise ApiError("CODE_ALREADY_EXISTS", "کد تعمیرکار تکراری است", http_status=409)
    
    # به‌روزرسانی
    update_data = {}
    if "code" in data:
        update_data["code"] = data["code"]
    if "commission_type" in data:
        update_data["commission_type"] = data["commission_type"]
    if "commission_value" in data:
        update_data["commission_value"] = Decimal(str(data["commission_value"]))
    if "is_active" in data:
        update_data["is_active"] = data["is_active"]
    if "extra_info" in data:
        update_data["extra_info"] = data["extra_info"]
    
    tech = repo.update(tech, update_data)
    db.commit()
    
    return get_technician(db, business_id, technician_id)


def delete_technician(
    db: Session,
    business_id: int,
    technician_id: int,
    user_id: int
) -> Dict[str, Any]:
    """حذف تعمیرکار"""
    _check_plugin_active(db, business_id)
    
    repo = RepairTechnicianRepository(db)
    tech = repo.get_by_id(technician_id, business_id)
    
    if not tech:
        raise ApiError("TECHNICIAN_NOT_FOUND", "تعمیرکار یافت نشد", http_status=404)
    
    # بررسی اینکه آیا تعمیرکار سفارش فعالی دارد
    active_orders = db.query(RepairOrder).filter(
        and_(
            RepairOrder.assigned_technician_id == technician_id,
            RepairOrder.status.in_([
                "received", "assigned", "in_progress", "waiting_parts", "testing"
            ])
        )
    ).count()
    
    if active_orders > 0:
        raise ApiError(
            "TECHNICIAN_HAS_ACTIVE_ORDERS",
            f"این تعمیرکار {active_orders} سفارش فعال دارد. ابتدا سفارشات را تکمیل کنید.",
            http_status=409
        )
    
    # غیرفعال کردن به جای حذف (Soft Delete)
    tech.is_active = False
    db.commit()
    
    return {"message": "تعمیرکار با موفقیت غیرفعال شد"}


# ========== سفارشات تعمیر ==========

def _generate_repair_code(
    db: Session,
    business_id: int,
    format_type: str,
    prefix: str
) -> str:
    """تولید کد یکتا برای سفارش تعمیر"""
    repo = RepairOrderRepository(db)
    
    if format_type == "random":
        # تولید کد رندوم
        while True:
            code = f"{prefix}-{_generate_random_code(8)}"
            existing = repo.get_by_code(code, business_id)
            if not existing:
                return code
    
    elif format_type == "sequential":
        # تولید کد ترتیبی
        year = datetime.utcnow().year
        next_num = repo.get_next_sequential_number(business_id, prefix, year)
        return f"{prefix}-{year}-{next_num:04d}"
    
    else:
        # پیش‌فرض: sequential
        year = datetime.utcnow().year
        next_num = repo.get_next_sequential_number(business_id, prefix, year)
        return f"{prefix}-{year}-{next_num:04d}"


def list_repair_orders(
    db: Session,
    business_id: int,
    filters: Optional[Dict[str, Any]] = None,
    offset: int = 0,
    limit: int = 50
) -> Dict[str, Any]:
    """لیست سفارشات تعمیر"""
    from sqlalchemy.orm import selectinload, joinedload
    
    _check_plugin_active(db, business_id)
    
    repo = RepairOrderRepository(db)
    orders, total = repo.list_by_business(business_id, filters, offset, limit)
    
    # دریافت ارز پیش‌فرض کسب‌وکار برای همه سفارشات
    business = db.query(Business).filter(Business.id == business_id).first()
    default_currency_symbol = "تومان"
    if business and business.default_currency_id:
        currency = db.query(Currency).filter(Currency.id == business.default_currency_id).first()
        if currency:
            default_currency_symbol = currency.symbol
    
    # Eager load relationships برای جلوگیری از N+1 queries
    # دریافت IDs برای batch loading
    customer_ids = {order.customer_person_id for order in orders}
    technician_ids = {order.assigned_technician_id for order in orders if order.assigned_technician_id}
    currency_ids = {order.currency_id for order in orders}
    
    # Load همه customers به صورت batch
    customers_map = {}
    if customer_ids:
        customers = db.query(Person).filter(Person.id.in_(customer_ids)).all()
        customers_map = {c.id: c for c in customers}
    
    # Load همه technicians و persons مرتبط
    technicians_map = {}
    tech_persons_map = {}
    if technician_ids:
        technicians = db.query(RepairTechnician).filter(
            RepairTechnician.id.in_(technician_ids)
        ).all()
        technicians_map = {t.id: t for t in technicians}
        
        tech_person_ids = {t.person_id for t in technicians}
        if tech_person_ids:
            tech_persons = db.query(Person).filter(Person.id.in_(tech_person_ids)).all()
            tech_persons_map = {p.id: p for p in tech_persons}
    
    # Load همه currencies
    currencies_map = {}
    if currency_ids:
        currencies = db.query(Currency).filter(Currency.id.in_(currency_ids)).all()
        currencies_map = {c.id: c for c in currencies}
    
    items = []
    for order in orders:
        # دریافت اطلاعات مشتری از cache
        customer = customers_map.get(order.customer_person_id)
        
        # دریافت اطلاعات تعمیرکار از cache
        technician_name = None
        if order.assigned_technician_id:
            technician = technicians_map.get(order.assigned_technician_id)
            if technician:
                tech_person = tech_persons_map.get(technician.person_id)
                technician_name = tech_person.name if tech_person else ""
        
        # دریافت ارز این سفارش از cache
        currency = currencies_map.get(order.currency_id)
        currency_symbol = currency.symbol if currency else default_currency_symbol
        
        items.append({
            "id": order.id,
            "code": order.code,
            "customer_person_id": order.customer_person_id,
            "customer_name": customer.name if customer else "",
            "customer_phone": customer.mobile if customer else None,
            "product_name": order.product_name,
            "product_serial": order.product_serial,
            "status": order.status,
            "problem_description": order.problem_description,
            "assigned_technician_id": order.assigned_technician_id,
            "technician_name": technician_name,
            "final_cost": float(order.final_cost),
            "currency_id": order.currency_id,
            "currency_symbol": currency_symbol,
            "received_at": order.received_at.isoformat(),
            "estimated_delivery_at": order.estimated_delivery_at.isoformat() if order.estimated_delivery_at else None,
            "completed_at": order.completed_at.isoformat() if order.completed_at else None,
        })
    
    return {
        "items": items,
        "total": total,
        "offset": offset,
        "limit": limit,
    }


def get_repair_order(
    db: Session,
    business_id: int,
    order_id: int
) -> Dict[str, Any]:
    """دریافت اطلاعات کامل یک سفارش تعمیر"""
    _check_plugin_active(db, business_id)
    
    repo = RepairOrderRepository(db)
    order = repo.get_by_id(order_id, business_id)
    
    if not order:
        raise ApiError("REPAIR_ORDER_NOT_FOUND", "سفارش تعمیر یافت نشد", http_status=404)
    
    # دریافت اطلاعات مشتری
    customer = db.query(Person).filter(Person.id == order.customer_person_id).first()
    
    # دریافت اطلاعات تعمیرکار
    technician_name = None
    if order.assigned_technician_id:
        technician = db.query(RepairTechnician).filter(
            RepairTechnician.id == order.assigned_technician_id
        ).first()
        if technician:
            tech_person = db.query(Person).filter(Person.id == technician.person_id).first()
            technician_name = tech_person.name if tech_person else ""
    
    # دریافت اطلاعات ارز
    currency = db.query(Currency).filter(Currency.id == order.currency_id).first()
    currency_symbol = currency.symbol if currency else "تومان"
    currency_code = currency.code if currency else "IRR"
    
    # دریافت قطعات
    parts_repo = RepairOrderPartRepository(db)
    parts = parts_repo.list_by_order(order_id)
    
    parts_list = []
    for part in parts:
        product = db.query(Product).filter(Product.id == part.product_id).first()
        parts_list.append({
            "id": part.id,
            "product_id": part.product_id,
            "product_name": product.name if product else "",
            "quantity": float(part.quantity),
            "unit_price": float(part.unit_price),
            "total_price": float(part.total_price),
            "warehouse_id": part.warehouse_id,
            "description": part.description,
        })
    
    # دریافت تاریخچه وضعیت‌ها
    status_repo = RepairOrderStatusRepository(db)
    statuses = status_repo.list_by_order(order_id)
    
    status_history = []
    for status in statuses:
        status_history.append({
            "id": status.id,
            "status": status.status,
            "notes": status.notes,
            "created_at": status.created_at.isoformat(),
            "sms_sent": status.sms_sent,
            "email_sent": status.email_sent,
        })
    
    return {
        "id": order.id,
        "code": order.code,
        "business_id": order.business_id,
        "customer_person_id": order.customer_person_id,
        "customer_name": customer.name if customer else "",
        "customer_phone": customer.mobile if customer else None,
        "customer_email": customer.email if customer else None,
        "product_id": order.product_id,
        "product_name": order.product_name,
        "product_serial": order.product_serial,
        "warranty_code_id": order.warranty_code_id,
        "status": order.status,
        "problem_description": order.problem_description,
        "customer_notes": order.customer_notes,
        "technician_notes": order.technician_notes,
        "assigned_technician_id": order.assigned_technician_id,
        "technician_name": technician_name,
        "estimated_cost": float(order.estimated_cost) if order.estimated_cost else None,
        "final_cost": float(order.final_cost),
        "parts_cost": float(order.parts_cost),
        "labor_cost": float(order.labor_cost),
        "technician_commission": float(order.technician_commission),
        "currency_id": order.currency_id,
        "currency_symbol": currency_symbol,
        "currency_code": currency_code,
        "received_at": order.received_at.isoformat(),
        "estimated_delivery_at": order.estimated_delivery_at.isoformat() if order.estimated_delivery_at else None,
        "completed_at": order.completed_at.isoformat() if order.completed_at else None,
        "delivered_at": order.delivered_at.isoformat() if order.delivered_at else None,
        "extra_info": order.extra_info or {},
        "parts": parts_list,
        "status_history": status_history,
    }


def create_repair_order(
    db: Session,
    business_id: int,
    data: Dict[str, Any],
    user_id: int
) -> Dict[str, Any]:
    """ایجاد سفارش تعمیر جدید"""
    _check_plugin_active(db, business_id)
    
    # دریافت تنظیمات
    settings_repo = RepairShopSettingsRepository(db)
    settings = settings_repo.get_by_business(business_id)
    if not settings:
        settings = settings_repo.create_or_update(business_id, {})
    
    # بررسی مشتری
    customer_person_id = data.get("customer_person_id")
    if not customer_person_id:
        raise ApiError("CUSTOMER_REQUIRED", "مشتری الزامی است", http_status=400)
    
    customer = db.query(Person).filter(
        and_(
            Person.id == customer_person_id,
            Person.business_id == business_id
        )
    ).first()
    
    if not customer:
        raise ApiError("CUSTOMER_NOT_FOUND", "مشتری یافت نشد", http_status=404)
    
    # بررسی کالا (اختیاری)
    product_id = data.get("product_id")
    product_name = data.get("product_name")
    
    if product_id:
        product = db.query(Product).filter(
            and_(
                Product.id == product_id,
                Product.business_id == business_id
            )
        ).first()
        
        if not product:
            raise ApiError("PRODUCT_NOT_FOUND", "کالا یافت نشد", http_status=404)
        
        if not product_name:
            product_name = product.name
    
    if not product_name:
        raise ApiError("PRODUCT_NAME_REQUIRED", "نام کالا الزامی است", http_status=400)
    
    # دریافت سال مالی و ارز
    fiscal_year = _get_current_fiscal_year(db, business_id)
    
    currency_id = data.get("currency_id")
    if not currency_id:
        # استفاده از ارز پیش‌فرض کسب‌وکار
        business = db.query(Business).filter(Business.id == business_id).first()
        if not business:
            raise ApiError("BUSINESS_NOT_FOUND", "کسب‌وکار یافت نشد", http_status=404)
        
        if not business.default_currency_id:
            raise ApiError(
                "NO_DEFAULT_CURRENCY",
                "ارز پیش‌فرض برای این کسب‌وکار تنظیم نشده است",
                http_status=400
            )
        
        currency_id = business.default_currency_id
    
    # تولید کد
    code = _generate_repair_code(
        db,
        business_id,
        settings.receipt_code_format,
        settings.receipt_code_prefix
    )
    
    # ایجاد سفارش
    order_data = {
        "business_id": business_id,
        "code": code,
        "customer_person_id": customer_person_id,
        "product_id": product_id,
        "product_name": product_name,
        "product_serial": data.get("product_serial"),
        "warranty_code_id": data.get("warranty_code_id"),
        "status": "received",
        "problem_description": data.get("problem_description", ""),
        "customer_notes": data.get("customer_notes"),
        "estimated_cost": Decimal(str(data["estimated_cost"])) if data.get("estimated_cost") else None,
        "fiscal_year_id": fiscal_year.id,
        "currency_id": currency_id,
        "created_by_user_id": user_id,
        "received_at": datetime.utcnow(),
        "estimated_delivery_at": data.get("estimated_delivery_at"),
    }
    
    repo = RepairOrderRepository(db)
    order = repo.create(order_data)
    
    # ثبت وضعیت اولیه
    status_repo = RepairOrderStatusRepository(db)
    status_repo.create({
        "repair_order_id": order.id,
        "status": "received",
        "notes": "دریافت کالا",
        "created_by_user_id": user_id,
    })
    
    db.commit()
    
    # ارسال پیامک/ایمیل (اگر فعال باشد)
    if settings.auto_send_sms_on_receive or settings.auto_send_email_on_receive:
        from app.services.repair_shop_notification import send_repair_notification
        try:
            send_repair_notification(
                db=db,
                business_id=business_id,
                repair_order=order,
                event_type="repair_shop.received",
                triggered_by_user_id=user_id
            )
        except Exception as e:
            logger.error(f"خطا در ارسال نوتیفیکیشن دریافت سفارش: {e}")
            # ادامه می‌دهیم حتی اگر نوتیفیکیشن ارسال نشد
    
    return get_repair_order(db, business_id, order.id)


def update_repair_order(
    db: Session,
    business_id: int,
    order_id: int,
    data: Dict[str, Any],
    user_id: int
) -> Dict[str, Any]:
    """به‌روزرسانی سفارش تعمیر"""
    _check_plugin_active(db, business_id)
    
    repo = RepairOrderRepository(db)
    order = repo.get_by_id(order_id, business_id)
    
    if not order:
        raise ApiError("REPAIR_ORDER_NOT_FOUND", "سفارش تعمیر یافت نشد", http_status=404)
    
    # فقط سفارشات در وضعیت‌های خاص قابل ویرایش هستند
    if order.status in ["delivered", "cancelled"]:
        raise ApiError(
            "ORDER_NOT_EDITABLE",
            f"سفارش در وضعیت {order.status} قابل ویرایش نیست",
            http_status=400
        )
    
    # به‌روزرسانی فیلدهای مجاز
    update_data = {}
    
    if "product_serial" in data:
        update_data["product_serial"] = data["product_serial"]
    if "problem_description" in data:
        update_data["problem_description"] = data["problem_description"]
    if "customer_notes" in data:
        update_data["customer_notes"] = data["customer_notes"]
    if "technician_notes" in data:
        update_data["technician_notes"] = data["technician_notes"]
    if "estimated_cost" in data:
        update_data["estimated_cost"] = Decimal(str(data["estimated_cost"])) if data["estimated_cost"] else None
    if "estimated_delivery_at" in data:
        update_data["estimated_delivery_at"] = data["estimated_delivery_at"]
    
    if update_data:
        update_data["updated_at"] = datetime.utcnow()
        order = repo.update(order, update_data)
        db.commit()
    
    return get_repair_order(db, business_id, order_id)


def delete_repair_order(
    db: Session,
    business_id: int,
    order_id: int,
    user_id: int,
    reason: Optional[str] = None
) -> Dict[str, Any]:
    """حذف (لغو) سفارش تعمیر"""
    _check_plugin_active(db, business_id)
    
    repo = RepairOrderRepository(db)
    order = repo.get_by_id(order_id, business_id)
    
    if not order:
        raise ApiError("REPAIR_ORDER_NOT_FOUND", "سفارش تعمیر یافت نشد", http_status=404)
    
    # بررسی وضعیت - فقط سفارشات خاص قابل لغو هستند
    if order.status in ["delivered"]:
        raise ApiError(
            "ORDER_NOT_DELETABLE",
            "سفارش تحویل داده شده قابل لغو نیست",
            http_status=400
        )
    
    if order.status == "cancelled":
        raise ApiError(
            "ORDER_ALREADY_CANCELLED",
            "این سفارش قبلاً لغو شده است",
            http_status=400
        )
    
    # بررسی فاکتور - اگر فاکتور صادر شده، نمی‌توان لغو کرد
    invoice_repo = RepairInvoiceRepository(db)
    existing_invoice = invoice_repo.get_by_order(order_id)
    
    if existing_invoice:
        raise ApiError(
            "ORDER_HAS_INVOICE",
            "این سفارش دارای فاکتور است و قابل لغو نیست. ابتدا فاکتور را حذف کنید.",
            http_status=409
        )
    
    # Soft delete: تغییر وضعیت به cancelled
    order.status = "cancelled"
    order.updated_at = datetime.utcnow()
    
    # ثبت در تاریخچه
    status_repo = RepairOrderStatusRepository(db)
    status_repo.create({
        "repair_order_id": order.id,
        "status": "cancelled",
        "notes": reason or "لغو سفارش توسط کاربر",
        "created_by_user_id": user_id,
    })
    
    db.commit()
    
    return {
        "message": "سفارش تعمیر با موفقیت لغو شد",
        "order_id": order.id,
        "code": order.code
    }

