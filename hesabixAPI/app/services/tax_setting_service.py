from __future__ import annotations

from typing import Dict, Any
from datetime import datetime

from sqlalchemy.orm import Session

from adapters.db.models.tax_setting import TaxSetting
from app.services.encryption_service import encrypt_private_key, decrypt_private_key


def get_tax_setting(db: Session, business_id: int) -> TaxSetting | None:
    """
    دریافت تنظیمات مالیاتی کسب‌وکار
    کلید خصوصی به صورت خودکار رمزگشایی می‌شود
    """
    setting = (
        db.query(TaxSetting)
        .filter(TaxSetting.business_id == int(business_id))
        .first()
    )
    
    if setting and setting.private_key:
        # رمزگشایی کلید خصوصی
        try:
            setting.private_key = decrypt_private_key(setting.private_key)
        except Exception:
            # اگر رمزگشایی ناموفق بود، احتمالا کلید رمز نشده است (داده‌های قدیمی)
            pass
    
    return setting


def upsert_tax_setting(
    db: Session,
    *,
    business_id: int,
    user_id: int,
    payload: Dict[str, Any],
) -> TaxSetting:
    """
    ایجاد یا به‌روزرسانی تنظیمات مالیاتی
    کلید خصوصی به صورت خودکار رمزنگاری می‌شود
    """
    setting = (
        db.query(TaxSetting)
        .filter(TaxSetting.business_id == int(business_id))
        .first()
    )
    
    now = datetime.utcnow()
    
    if setting is None:
        setting = TaxSetting(
            business_id=int(business_id),
            created_by_user_id=int(user_id),
            created_at=now,
        )
        db.add(setting)

    # به‌روزرسانی فیلدها
    setting.tax_memory_id = payload.get("tax_memory_id")
    setting.economic_code = payload.get("economic_code")
    
    # رمزنگاری کلید خصوصی قبل از ذخیره
    private_key = payload.get("private_key")
    if private_key:
        try:
            setting.private_key = encrypt_private_key(private_key)
        except Exception:
            # اگر رمزنگاری ناموفق بود، به صورت plain text ذخیره می‌شود (fallback)
            setting.private_key = private_key
    
    setting.public_key = payload.get("public_key")
    setting.certificate = payload.get("certificate")
    setting.certificate_request = payload.get("certificate_request")
    setting.sandbox_mode = bool(payload.get("sandbox_mode", False))
    setting.updated_at = now

    db.flush()
    db.refresh(setting)
    
    # رمزگشایی برای برگرداندن به کاربر
    if setting.private_key:
        try:
            setting.private_key = decrypt_private_key(setting.private_key)
        except Exception:
            pass
    
    return setting


def serialize_tax_setting(
    setting: TaxSetting | None,
    business_id: int,
    *,
    db: Session | None = None,
) -> Dict[str, Any]:
    """
    سریالایز کردن تنظیمات مالیاتی برای API response
    کلید خصوصی به صورت خودکار رمزگشایی می‌شود
    """
    if setting is None:
        return {
            "business_id": int(business_id),
            "tax_memory_id": None,
            "economic_code": None,
            "private_key": None,
            "public_key": None,
            "certificate": None,
            "certificate_request": None,
            "sandbox_mode": False,
            "has_private_key": False,
            "updated_at": None,
            "configuration_warnings": [],
            "identity_check": None,
        }

    # رمزگشایی کلید خصوصی برای نمایش
    private_key = setting.private_key
    if private_key:
        try:
            private_key = decrypt_private_key(private_key)
        except Exception:
            pass

    from app.services.tax_setting_health_service import (
        build_configuration_warnings,
        build_identity_check,
    )

    warnings = build_configuration_warnings(setting)
    identity_check = None
    if db is not None:
        identity_check = build_identity_check(db, int(business_id))

    return {
        "business_id": int(setting.business_id),
        "tax_memory_id": setting.tax_memory_id,
        "economic_code": setting.economic_code,
        "private_key": private_key,
        "public_key": setting.public_key,
        "certificate": setting.certificate,
        "certificate_request": setting.certificate_request,
        "sandbox_mode": bool(setting.sandbox_mode),
        "has_private_key": bool(setting.private_key),
        "updated_at": setting.updated_at.isoformat() if setting.updated_at else None,
        "configuration_warnings": warnings,
        "identity_check": identity_check,
    }


