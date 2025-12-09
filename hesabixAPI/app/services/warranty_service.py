from __future__ import annotations

import secrets
import logging
from datetime import datetime, timedelta
from typing import Any, Dict, List, Optional
from sqlalchemy.orm import Session
from sqlalchemy import and_, or_

from adapters.db.models.warranty import (
    WarrantySetting,
    WarrantyCode,
    WarrantyActivation,
    WarrantyTracking,
    WarrantyTrackingLink,
)
from adapters.db.models.business import Business
from adapters.db.models.product import Product
from adapters.db.models.product_instance import ProductInstance
from adapters.db.models.person import Person
from adapters.db.models.marketplace import BusinessPlugin, MarketplacePlugin
from adapters.db.repositories.warranty_repository import (
    WarrantySettingRepository,
    WarrantyCodeRepository,
    WarrantyActivationRepository,
    WarrantyTrackingRepository,
    WarrantyTrackingLinkRepository,
)
from app.core.responses import ApiError
from app.core.cache import get_cache

logger = logging.getLogger(__name__)

# الفبای برای تولید کدهای رندوم (بدون کاراکترهای مشابه)
BASE62_ALPHABET = "23456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"


# ========== Helper Functions ==========

def _generate_random_code(length: int = 12) -> str:
    """تولید کد رندوم"""
    return "".join(secrets.choice(BASE62_ALPHABET) for _ in range(length))


def _generate_random_serial(length: int = 12) -> str:
    """تولید سریال رندوم"""
    return _generate_random_code(length)


def _generate_sequential_code(
    db: Session,
    business_id: int,
    prefix: str = "WR",
    year: Optional[int] = None
) -> str:
    """تولید کد ترتیبی"""
    if year is None:
        year = datetime.utcnow().year
    
    base = f"{prefix}-{year}"
    like_pattern = f"{base}-%"
    
    last = (
        db.query(WarrantyCode)
        .filter(
            and_(
                WarrantyCode.business_id == business_id,
                WarrantyCode.code.like(like_pattern)
            )
        )
        .order_by(WarrantyCode.id.desc())
        .first()
    )
    
    next_num = 1
    if last and last.code.startswith(base + "-"):
        try:
            next_num = int(last.code.split("-")[-1]) + 1
        except Exception:
            next_num = 1
    
    return f"{base}-{next_num:06d}"


def _check_warranty_plugin_active(db: Session, business_id: int) -> bool:
    """بررسی فعال بودن پلاگین گارانتی برای کسب و کار"""
    plugin = db.query(MarketplacePlugin).filter(
        MarketplacePlugin.code == 'product_warranty',
        MarketplacePlugin.is_active == True  # noqa: E712
    ).first()
    
    if not plugin:
        return False
    
    license = db.query(BusinessPlugin).filter(
        BusinessPlugin.business_id == business_id,
        BusinessPlugin.plugin_id == plugin.id,
        BusinessPlugin.status == 'active'
    ).first()
    
    if not license:
        return False
    
    # بررسی انقضا
    if license.ends_at and license.ends_at < datetime.utcnow():
        return False
    
    return True


def _get_or_create_warranty_settings(
    db: Session,
    business_id: int
) -> WarrantySetting:
    """دریافت یا ایجاد تنظیمات گارانتی پیش‌فرض"""
    repo = WarrantySettingRepository(db)
    settings = repo.get_by_business(business_id)
    
    if not settings:
        # ایجاد تنظیمات پیش‌فرض
        settings = repo.create_or_update(business_id, {
            "code_format": "random",
            "code_prefix": "WR",
            "serial_format": "random",
            "serial_length": 12,
            "require_serial_verification": False,
            "require_product_instance_match": False,
            "auto_link_to_person": True,
            "enable_tracking_link": True,
        })
        db.commit()
    
    return settings


def _find_person_by_phone(db: Session, business_id: int, phone: str) -> Optional[Person]:
    """جستجوی Person بر اساس شماره تماس"""
    # نرمال‌سازی شماره تماس (حذف فاصله و کاراکترهای خاص)
    normalized_phone = phone.replace(" ", "").replace("-", "").replace("_", "")
    
    # جستجو در mobile و phone
    person = db.query(Person).filter(
        and_(
            Person.business_id == business_id,
            or_(
                Person.mobile == phone,
                Person.mobile == normalized_phone,
                Person.phone == phone,
                Person.phone == normalized_phone,
            )
        )
    ).first()
    
    return person


def _generate_tracking_link_code(db: Session) -> str:
    """تولید کد یکتا برای لینک رهگیری"""
    repo = WarrantyTrackingLinkRepository(db)
    
    for _ in range(10):
        code = _generate_random_code(16)
        if not repo.check_link_code_exists(code):
            return code
    
    # fallback: استفاده از timestamp
    return f"{int(datetime.utcnow().timestamp())}{secrets.randbelow(9999):04d}"


# ========== Settings Management ==========

def get_warranty_settings(
    db: Session,
    business_id: int
) -> Dict[str, Any]:
    """دریافت تنظیمات گارانتی"""
    if not _check_warranty_plugin_active(db, business_id):
        raise ApiError(
            "PLUGIN_NOT_ACTIVE",
            "پلاگین گارانتی برای این کسب و کار فعال نیست",
            http_status=403
        )
    
    settings = _get_or_create_warranty_settings(db, business_id)
    
    return {
        "id": settings.id,
        "business_id": settings.business_id,
        "code_format": settings.code_format,
        "code_prefix": settings.code_prefix,
        "serial_format": settings.serial_format,
        "serial_length": settings.serial_length,
        "require_serial_verification": settings.require_serial_verification,
        "require_product_instance_match": settings.require_product_instance_match,
        "max_activation_attempts": settings.max_activation_attempts,
        "activation_lockout_duration_minutes": settings.activation_lockout_duration_minutes,
        "require_customer_registration": settings.require_customer_registration,
        "auto_link_to_person": settings.auto_link_to_person,
        "enable_tracking_link": settings.enable_tracking_link,
        "tracking_link_expires_days": settings.tracking_link_expires_days,
        "enable_sms_notification": settings.enable_sms_notification,
        "enable_email_notification": settings.enable_email_notification,
        "security_features": settings.security_features,
        "created_at": settings.created_at,
        "updated_at": settings.updated_at,
    }


def update_warranty_settings(
    db: Session,
    business_id: int,
    settings_data: Dict[str, Any]
) -> Dict[str, Any]:
    """به‌روزرسانی تنظیمات گارانتی"""
    if not _check_warranty_plugin_active(db, business_id):
        raise ApiError(
            "PLUGIN_NOT_ACTIVE",
            "پلاگین گارانتی برای این کسب و کار فعال نیست",
            http_status=403
        )
    
    repo = WarrantySettingRepository(db)
    settings = repo.create_or_update(business_id, settings_data)
    db.commit()
    
    return get_warranty_settings(db, business_id)


# ========== Code Generation ==========

def generate_warranty_codes(
    db: Session,
    business_id: int,
    product_id: int,
    quantity: int,
    warranty_duration_days: int,
    user_id: Optional[int] = None,
    serial_format: str = "random",
    custom_serials: Optional[List[str]] = None,
    code_format: Optional[str] = None,
    custom_codes: Optional[List[str]] = None,
) -> List[Dict[str, Any]]:
    """تولید انبوه کدهای گارانتی"""
    if not _check_warranty_plugin_active(db, business_id):
        raise ApiError(
            "PLUGIN_NOT_ACTIVE",
            "پلاگین گارانتی برای این کسب و کار فعال نیست",
            http_status=403
        )
    
    # بررسی وجود کالا
    product = db.query(Product).filter(
        and_(
            Product.id == product_id,
            Product.business_id == business_id
        )
    ).first()
    
    if not product:
        raise ApiError("PRODUCT_NOT_FOUND", "کالا یافت نشد", http_status=404)
    
    # دریافت تنظیمات
    settings = _get_or_create_warranty_settings(db, business_id)
    
    # استفاده از تنظیمات یا مقادیر ارسالی
    code_format = code_format or settings.code_format
    serial_format = serial_format or settings.serial_format
    serial_length = settings.serial_length or 12
    code_prefix = settings.code_prefix or "WR"
    
    # بررسی تعداد سریال‌های دلخواه
    if serial_format == "custom":
        if not custom_serials or len(custom_serials) != quantity:
            raise ApiError(
                "INVALID_CUSTOM_SERIALS",
                f"تعداد سریال‌های دلخواه باید برابر با {quantity} باشد",
                http_status=400
            )
    
    if code_format == "custom":
        if not custom_codes or len(custom_codes) != quantity:
            raise ApiError(
                "INVALID_CUSTOM_CODES",
                f"تعداد کدهای دلخواه باید برابر با {quantity} باشد",
                http_status=400
            )
    
    repo = WarrantyCodeRepository(db)
    generated_codes = []
    
    for i in range(quantity):
        # تولید یا استفاده از کد دلخواه
        if code_format == "custom" and custom_codes:
            code = custom_codes[i]
            if repo.check_code_exists(code, business_id):
                raise ApiError(
                    "DUPLICATE_CODE",
                    f"کد {code} در این کسب و کار تکراری است",
                    http_status=409
                )
        elif code_format == "sequential":
            code = _generate_sequential_code(db, business_id, code_prefix)
        else:  # random
            for _ in range(10):
                code = f"{code_prefix}-{_generate_random_code(8)}"
                if not repo.check_code_exists(code, business_id):
                    break
            else:
                raise ApiError("CODE_GENERATION_FAILED", "تولید کد یکتا ناموفق بود", http_status=500)
        
        # تولید یا استفاده از سریال دلخواه
        if serial_format == "custom" and custom_serials:
            warranty_serial = custom_serials[i]
            if repo.check_serial_exists(business_id, warranty_serial):
                raise ApiError(
                    "DUPLICATE_SERIAL",
                    f"سریال {warranty_serial} تکراری است",
                    http_status=409
                )
        else:  # random
            for _ in range(10):
                warranty_serial = _generate_random_serial(serial_length)
                if not repo.check_serial_exists(business_id, warranty_serial):
                    break
            else:
                raise ApiError("SERIAL_GENERATION_FAILED", "تولید سریال یکتا ناموفق بود", http_status=500)
        
        # محاسبه تاریخ انقضا
        expires_at = None
        if warranty_duration_days > 0:
            expires_at = datetime.utcnow() + timedelta(days=warranty_duration_days)
        
        # ایجاد کد گارانتی
        warranty_code = WarrantyCode(
            business_id=business_id,
            code=code,
            warranty_serial=warranty_serial,
            product_id=product_id,
            status="generated",
            generated_by_user_id=user_id,
            generated_at=datetime.utcnow(),
            warranty_duration_days=warranty_duration_days,
            expires_at=expires_at,
        )
        
        db.add(warranty_code)
        db.flush()
        
        generated_codes.append({
            "id": warranty_code.id,
            "business_id": warranty_code.business_id,
            "code": warranty_code.code,
            "warranty_serial": warranty_code.warranty_serial,
            "product_id": warranty_code.product_id,
            "product_instance_id": warranty_code.product_instance_id,
            "status": warranty_code.status,
            "generated_by_user_id": warranty_code.generated_by_user_id,
            "generated_at": warranty_code.generated_at,
            "activated_at": warranty_code.activated_at,
            "activated_by_person_id": warranty_code.activated_by_person_id,
            "activated_by_customer_info": warranty_code.activated_by_customer_info,
            "expires_at": warranty_code.expires_at,
            "warranty_duration_days": warranty_code.warranty_duration_days,
            "tracking_link_code": warranty_code.tracking_link_code,
            "extra_metadata": warranty_code.extra_metadata,
            "created_at": warranty_code.created_at,
            "updated_at": warranty_code.updated_at,
        })
    
    db.commit()
    
    return generated_codes


# ========== Activation ==========

def _check_activation_attempts(
    db: Session,
    warranty_code: WarrantyCode,
    ip_address: Optional[str],
    settings: WarrantySetting
) -> None:
    """بررسی محدودیت تلاش برای فعال‌سازی"""
    if not settings.max_activation_attempts:
        return
    
    cache = get_cache()
    if not cache:
        return
    
    # کلید cache برای IP
    cache_key = f"warranty_activation_attempts:{warranty_code.id}:{ip_address or 'unknown'}"
    
    attempts = cache.get(cache_key)
    if attempts is None:
        attempts = 0
    
    lockout_minutes = settings.activation_lockout_duration_minutes or 30
    if attempts >= settings.max_activation_attempts:
        raise ApiError(
            "TOO_MANY_ATTEMPTS",
            f"تعداد تلاش‌های شما بیش از حد مجاز است. لطفاً {lockout_minutes} دقیقه دیگر تلاش کنید.",
            http_status=429
        )
    
    # افزایش تعداد تلاش
    cache.set(cache_key, attempts + 1, timeout=lockout_minutes * 60)


def _clear_activation_attempts(
    warranty_code_id: int,
    ip_address: Optional[str]
) -> None:
    """پاک کردن تعداد تلاش‌ها پس از موفقیت"""
    cache = get_cache()
    if cache:
        cache_key = f"warranty_activation_attempts:{warranty_code_id}:{ip_address or 'unknown'}"
        cache.delete(cache_key)


def activate_warranty(
    db: Session,
    business_id: int,
    warranty_code_str: str,
    warranty_serial: str,
    customer_name: str,
    customer_phone: str,
    customer_email: Optional[str] = None,
    product_serial: Optional[str] = None,
    ip_address: Optional[str] = None,
    user_agent: Optional[str] = None,
) -> Dict[str, Any]:
    """فعال‌سازی گارانتی توسط مشتری"""
    repo = WarrantyCodeRepository(db)
    
    # یافتن کد گارانتی در کسب و کار مشخص شده
    warranty_code = repo.get_by_code(warranty_code_str, business_id)
    if not warranty_code:
        raise ApiError("WARRANTY_CODE_NOT_FOUND", "کد گارانتی در این کسب و کار یافت نشد", http_status=404)
    
    # بررسی فعال بودن پلاگین برای کسب و کار
    if not _check_warranty_plugin_active(db, warranty_code.business_id):
        raise ApiError(
            "PLUGIN_NOT_ACTIVE",
            "پلاگین گارانتی برای این کسب و کار فعال نیست",
            http_status=403
        )
    
    # بررسی سریال گارانتی
    if warranty_code.warranty_serial != warranty_serial:
        raise ApiError("INVALID_WARRANTY_SERIAL", "سریال گارانتی معتبر نیست", http_status=400)
    
    # بررسی وضعیت
    if warranty_code.status != "generated":
        if warranty_code.status == "activated":
            raise ApiError("WARRANTY_ALREADY_ACTIVATED", "این گارانتی قبلاً فعال شده است", http_status=400)
        elif warranty_code.status == "expired":
            raise ApiError("WARRANTY_EXPIRED", "این گارانتی منقضی شده است", http_status=400)
        elif warranty_code.status == "revoked":
            raise ApiError("WARRANTY_REVOKED", "این گارانتی لغو شده است", http_status=400)
        else:
            raise ApiError("INVALID_WARRANTY_STATUS", f"وضعیت گارانتی معتبر نیست: {warranty_code.status}", http_status=400)
    
    # بررسی انقضا
    if warranty_code.expires_at and warranty_code.expires_at < datetime.utcnow():
        warranty_code.status = "expired"
        db.commit()
        raise ApiError("WARRANTY_EXPIRED", "این گارانتی منقضی شده است", http_status=400)
    
    # دریافت تنظیمات
    settings = _get_or_create_warranty_settings(db, warranty_code.business_id)
    
    # بررسی محدودیت تلاش
    _check_activation_attempts(db, warranty_code, ip_address, settings)
    
    # بررسی نیاز به تأیید سریال کالا
    product_instance = None
    if settings.require_serial_verification or settings.require_product_instance_match:
        if not product_serial:
            raise ApiError("PRODUCT_SERIAL_REQUIRED", "وارد کردن سریال کالا الزامی است", http_status=400)
        
        # جستجوی product_instance
        product_instance = db.query(ProductInstance).filter(
            and_(
                ProductInstance.business_id == warranty_code.business_id,
                ProductInstance.product_id == warranty_code.product_id,
                ProductInstance.serial_number == product_serial
            )
        ).first()
        
        if not product_instance:
            raise ApiError("PRODUCT_SERIAL_NOT_FOUND", "سریال کالا یافت نشد", http_status=404)
        
        if settings.require_product_instance_match:
            warranty_code.product_instance_id = product_instance.id
    
    # اتصال به Person (اگر فعال باشد)
    person = None
    if settings.auto_link_to_person:
        person = _find_person_by_phone(db, warranty_code.business_id, customer_phone)
    
    # فعال‌سازی
    warranty_code.status = "activated"
    warranty_code.activated_at = datetime.utcnow()
    warranty_code.activated_by_person_id = person.id if person else None
    warranty_code.activated_by_customer_info = {
        "name": customer_name,
        "phone": customer_phone,
        "email": customer_email,
    } if not person else None
    
    if product_instance:
        warranty_code.product_instance_id = product_instance.id
    
    # ایجاد لینک رهگیری (اگر فعال باشد)
    tracking_link = None
    if settings.enable_tracking_link and person:
        link_code = _generate_tracking_link_code(db)
        warranty_code.tracking_link_code = link_code
        
        expires_at = None
        if settings.tracking_link_expires_days:
            expires_at = datetime.utcnow() + timedelta(days=settings.tracking_link_expires_days)
        
        tracking_link = WarrantyTrackingLink(
            warranty_code_id=warranty_code.id,
            person_id=person.id,
            link_code=link_code,
            expires_at=expires_at,
            is_active=True,
        )
        db.add(tracking_link)
    
    # ثبت فعال‌سازی
    activation = WarrantyActivation(
        warranty_code_id=warranty_code.id,
        person_id=person.id if person else None,
        product_instance_id=product_instance.id if product_instance else None,
        warranty_serial=warranty_serial,
        product_serial=product_serial,
        customer_name=customer_name,
        customer_phone=customer_phone,
        customer_email=customer_email,
        activation_date=datetime.utcnow(),
        ip_address=ip_address,
        user_agent=user_agent,
        verification_method="product_instance_match" if product_instance else "serial_match" if product_serial else "manual",
    )
    db.add(activation)
    
    # ثبت رویداد رهگیری
    tracking_event = WarrantyTracking(
        warranty_code_id=warranty_code.id,
        product_instance_id=product_instance.id if product_instance else None,
        person_id=person.id if person else None,
        event_type="activation",
        description=f"گارانتی توسط {customer_name} فعال شد",
    )
    db.add(tracking_event)
    
    db.commit()
    
    # پاک کردن تعداد تلاش‌ها
    _clear_activation_attempts(warranty_code.id, ip_address)
    
    return {
        "id": warranty_code.id,
        "code": warranty_code.code,
        "warranty_serial": warranty_code.warranty_serial,
        "status": warranty_code.status,
        "activated_at": warranty_code.activated_at,
        "expires_at": warranty_code.expires_at,
        "tracking_link_code": warranty_code.tracking_link_code,
        "person_id": person.id if person else None,
    }


# ========== Tracking ==========

def track_warranty(
    db: Session,
    code_or_serial: str,
    business_id: Optional[int] = None
) -> Dict[str, Any]:
    """رهگیری گارانتی"""
    repo = WarrantyCodeRepository(db)
    
    # جستجو بر اساس کد یا سریال
    warranty_code = repo.get_by_code(code_or_serial)
    
    if not warranty_code:
        # اگر business_id مشخص است، جستجو بر اساس سریال
        if business_id:
            warranty_code = repo.get_by_serial(business_id, code_or_serial)
    
    if not warranty_code:
        raise ApiError("WARRANTY_NOT_FOUND", "گارانتی یافت نشد", http_status=404)
    
    # دریافت اطلاعات کالا
    product = db.query(Product).filter(Product.id == warranty_code.product_id).first()
    
    # دریافت اطلاعات کسب و کار
    business = db.query(Business).filter(Business.id == warranty_code.business_id).first()
    
    # دریافت تاریخچه رهگیری
    tracking_repo = WarrantyTrackingRepository(db)
    tracking_events = tracking_repo.list_by_warranty_code(warranty_code.id)
    
    return {
        "id": warranty_code.id,
        "code": warranty_code.code,
        "warranty_serial": warranty_code.warranty_serial,
        "status": warranty_code.status,
        "generated_at": warranty_code.generated_at,
        "activated_at": warranty_code.activated_at,
        "expires_at": warranty_code.expires_at,
        "warranty_duration_days": warranty_code.warranty_duration_days,
        "product": {
            "id": product.id if product else None,
            "name": product.name if product else None,
            "code": product.code if product else None,
        } if product else None,
        "business": {
            "id": business.id if business else None,
            "name": business.name if business else None,
            "code": business.code if business else None,
        } if business else None,
        "tracking_events": [
            {
                "id": event.id,
                "event_type": event.event_type,
                "description": event.description,
                "created_at": event.created_at,
            }
            for event in tracking_events
        ],
    }


def track_warranty_by_link(
    db: Session,
    link_code: str
) -> Dict[str, Any]:
    """رهگیری گارانتی از طریق لینک یکتا"""
    link_repo = WarrantyTrackingLinkRepository(db)
    link = link_repo.get_by_link_code(link_code)
    
    if not link:
        raise ApiError("LINK_NOT_FOUND", "لینک رهگیری یافت نشد", http_status=404)
    
    # بررسی انقضا
    if link.expires_at and link.expires_at < datetime.utcnow():
        raise ApiError("LINK_EXPIRED", "لینک رهگیری منقضی شده است", http_status=400)
    
    # بررسی فعال بودن
    if not link.is_active:
        raise ApiError("LINK_INACTIVE", "لینک رهگیری غیرفعال است", http_status=400)
    
    # افزایش تعداد دسترسی
    link_repo.increment_access_count(link.id)
    db.commit()
    
    # دریافت اطلاعات گارانتی
    warranty_code_repo = WarrantyCodeRepository(db)
    warranty_code = warranty_code_repo.get_by_id(link.warranty_code_id)
    
    if not warranty_code:
        raise ApiError("WARRANTY_CODE_NOT_FOUND", "کد گارانتی مرتبط با لینک یافت نشد", http_status=404)
    
    return track_warranty(db, warranty_code.code, warranty_code.business_id)


# ========== List Codes ==========

def list_warranty_codes(
    db: Session,
    business_id: int,
    status: Optional[str] = None,
    product_id: Optional[int] = None,
    limit: int = 100,
    skip: int = 0
) -> Dict[str, Any]:
    """لیست کدهای گارانتی"""
    if not _check_warranty_plugin_active(db, business_id):
        raise ApiError(
            "PLUGIN_NOT_ACTIVE",
            "پلاگین گارانتی برای این کسب و کار فعال نیست",
            http_status=403
        )
    
    repo = WarrantyCodeRepository(db)
    codes = repo.list_by_business(business_id, status, product_id, limit, skip)
    total = repo.count_by_business(business_id, status, product_id)
    
    page = (skip // limit) + 1 if limit > 0 else 1
    total_pages = (total + limit - 1) // limit if limit > 0 else 0
    
    return {
        "items": [
            {
                "id": code.id,
                "business_id": code.business_id,
                "code": code.code,
                "warranty_serial": code.warranty_serial,
                "product_id": code.product_id,
                "product_instance_id": code.product_instance_id,
                "status": code.status,
                "generated_by_user_id": code.generated_by_user_id,
                "generated_at": code.generated_at,
                "activated_at": code.activated_at,
                "activated_by_person_id": code.activated_by_person_id,
                "activated_by_customer_info": code.activated_by_customer_info,
                "expires_at": code.expires_at,
                "warranty_duration_days": code.warranty_duration_days,
                "tracking_link_code": code.tracking_link_code,
                "extra_metadata": code.extra_metadata,
                "created_at": code.created_at,
                "updated_at": code.updated_at,
            }
            for code in codes
        ],
        "total": total,
        "limit": limit,
        "skip": skip,
        "page": page,
        "total_pages": total_pages,
    }


def list_warranty_codes_by_person(
    db: Session,
    business_id: int,
    person_id: int,
    status: Optional[str] = None,
    limit: int = 100,
    skip: int = 0
) -> Dict[str, Any]:
    """لیست کدهای گارانتی یک Person"""
    if not _check_warranty_plugin_active(db, business_id):
        raise ApiError(
            "PLUGIN_NOT_ACTIVE",
            "پلاگین گارانتی برای این کسب و کار فعال نیست",
            http_status=403
        )
    
    repo = WarrantyCodeRepository(db)
    codes = repo.list_by_person(business_id, person_id, status, limit, skip)
    total = repo.count_by_person(business_id, person_id, status)
    
    page = (skip // limit) + 1 if limit > 0 else 1
    total_pages = (total + limit - 1) // limit if limit > 0 else 0
    
    return {
        "items": [
            {
                "id": code.id,
                "business_id": code.business_id,
                "code": code.code,
                "warranty_serial": code.warranty_serial,
                "product_id": code.product_id,
                "product_instance_id": code.product_instance_id,
                "status": code.status,
                "generated_by_user_id": code.generated_by_user_id,
                "generated_at": code.generated_at,
                "activated_at": code.activated_at,
                "activated_by_person_id": code.activated_by_person_id,
                "activated_by_customer_info": code.activated_by_customer_info,
                "expires_at": code.expires_at,
                "warranty_duration_days": code.warranty_duration_days,
                "tracking_link_code": code.tracking_link_code,
                "extra_metadata": code.extra_metadata,
                "created_at": code.created_at,
                "updated_at": code.updated_at,
            }
            for code in codes
        ],
        "total": total,
        "limit": limit,
        "skip": skip,
        "page": page,
        "total_pages": total_pages,
    }


# ========== Delete Codes ==========

def delete_warranty_code(
    db: Session,
    business_id: int,
    code_id: int,
    force: bool = False
) -> Dict[str, Any]:
    """حذف یک کد گارانتی به صورت ایمن"""
    if not _check_warranty_plugin_active(db, business_id):
        raise ApiError(
            "PLUGIN_NOT_ACTIVE",
            "پلاگین گارانتی برای این کسب و کار فعال نیست",
            http_status=403
        )
    
    repo = WarrantyCodeRepository(db)
    warranty_code = repo.get_by_id(code_id)
    
    if not warranty_code:
        raise ApiError("WARRANTY_CODE_NOT_FOUND", "کد گارانتی یافت نشد", http_status=404)
    
    # بررسی تعلق به کسب و کار
    if warranty_code.business_id != business_id:
        raise ApiError("ACCESS_DENIED", "شما دسترسی به این کد گارانتی ندارید", http_status=403)
    
    # بررسی وضعیت کد برای حذف ایمن
    if not force and warranty_code.status in ["activated", "used"]:
        raise ApiError(
            "WARRANTY_CODE_ACTIVE",
            "این کد گارانتی فعال شده است. برای حذف از پارامتر force استفاده کنید.",
            http_status=400
        )
    
    # حذف رکوردهای مرتبط
    # 1. حذف رویدادهای رهگیری
    tracking_repo = WarrantyTrackingRepository(db)
    tracking_events = tracking_repo.list_by_warranty_code(warranty_code.id)
    for event in tracking_events:
        db.delete(event)
    
    # 2. حذف لینک‌های رهگیری
    link_repo = WarrantyTrackingLinkRepository(db)
    tracking_links = link_repo.list_by_warranty_code(warranty_code.id)
    for link in tracking_links:
        db.delete(link)
    
    # 3. حذف رکورد فعال‌سازی
    activation_repo = WarrantyActivationRepository(db)
    activation = activation_repo.get_by_warranty_code(warranty_code.id)
    if activation:
        db.delete(activation)
    
    # 4. حذف کد گارانتی
    code_data = {
        "id": warranty_code.id,
        "code": warranty_code.code,
        "warranty_serial": warranty_code.warranty_serial,
        "status": warranty_code.status,
    }
    
    db.delete(warranty_code)
    db.commit()
    
    return {
        "success": True,
        "message": "کد گارانتی با موفقیت حذف شد",
        "deleted_code": code_data,
    }


def delete_warranty_codes_bulk(
    db: Session,
    business_id: int,
    code_ids: List[int],
    force: bool = False
) -> Dict[str, Any]:
    """حذف گروهی کدهای گارانتی به صورت ایمن"""
    if not _check_warranty_plugin_active(db, business_id):
        raise ApiError(
            "PLUGIN_NOT_ACTIVE",
            "پلاگین گارانتی برای این کسب و کار فعال نیست",
            http_status=403
        )
    
    if not code_ids:
        raise ApiError("INVALID_INPUT", "لیست کدها خالی است", http_status=400)
    
    repo = WarrantyCodeRepository(db)
    tracking_repo = WarrantyTrackingRepository(db)
    link_repo = WarrantyTrackingLinkRepository(db)
    activation_repo = WarrantyActivationRepository(db)
    
    deleted_codes = []
    failed_codes = []
    skipped_codes = []
    
    for code_id in code_ids:
        try:
            warranty_code = repo.get_by_id(code_id)
            
            if not warranty_code:
                failed_codes.append({
                    "id": code_id,
                    "reason": "کد گارانتی یافت نشد"
                })
                continue
            
            # بررسی تعلق به کسب و کار
            if warranty_code.business_id != business_id:
                failed_codes.append({
                    "id": code_id,
                    "code": warranty_code.code,
                    "reason": "عدم دسترسی"
                })
                continue
            
            # بررسی وضعیت کد برای حذف ایمن
            if not force and warranty_code.status in ["activated", "used"]:
                skipped_codes.append({
                    "id": code_id,
                    "code": warranty_code.code,
                    "status": warranty_code.status,
                    "reason": "کد فعال شده است"
                })
                continue
            
            # حذف رکوردهای مرتبط
            # 1. حذف رویدادهای رهگیری
            tracking_events = tracking_repo.list_by_warranty_code(warranty_code.id)
            for event in tracking_events:
                db.delete(event)
            
            # 2. حذف لینک‌های رهگیری
            tracking_links = link_repo.list_by_warranty_code(warranty_code.id)
            for link in tracking_links:
                db.delete(link)
            
            # 3. حذف رکورد فعال‌سازی
            activation = activation_repo.get_by_warranty_code(warranty_code.id)
            if activation:
                db.delete(activation)
            
            # 4. حذف کد گارانتی
            deleted_codes.append({
                "id": warranty_code.id,
                "code": warranty_code.code,
                "warranty_serial": warranty_code.warranty_serial,
                "status": warranty_code.status,
            })
            
            db.delete(warranty_code)
        
        except Exception as e:
            logger.error(f"Error deleting warranty code {code_id}: {e}")
            failed_codes.append({
                "id": code_id,
                "reason": str(e)
            })
    
    db.commit()
    
    return {
        "success": True,
        "message": f"عملیات حذف گروهی انجام شد",
        "summary": {
            "total_requested": len(code_ids),
            "deleted": len(deleted_codes),
            "skipped": len(skipped_codes),
            "failed": len(failed_codes),
        },
        "deleted_codes": deleted_codes,
        "skipped_codes": skipped_codes,
        "failed_codes": failed_codes,
    }

