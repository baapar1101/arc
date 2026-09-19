from __future__ import annotations

from typing import Any, Dict
from datetime import datetime

from sqlalchemy.orm import Session

from adapters.db.models.tax_setting import TaxSetting
from app.integrations.moadian.client import uses_moadian_v2
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
    
    pub = payload.get("public_key")
    if pub is not None and str(pub).strip():
        setting.public_key = str(pub).strip()
    cert = payload.get("certificate")
    if cert is not None and str(cert).strip():
        setting.certificate = str(cert).strip()
    csr = payload.get("certificate_request")
    if csr is not None and str(csr).strip():
        setting.certificate_request = str(csr).strip()
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


def validate_tax_setting_complete(setting: TaxSetting | None) -> list[str]:
    """فیلدهای الزامی برای اتصال (v1: کلید خصوصی؛ v2: علاوه بر آن گواهی PEM)."""
    if setting is None:
        return ["tax_memory_id", "economic_code", "private_key"]
    missing: list[str] = []
    if not (setting.tax_memory_id or "").strip():
        missing.append("tax_memory_id")
    if not (setting.economic_code or "").strip():
        missing.append("economic_code")
    if not (setting.private_key or "").strip():
        missing.append("private_key")
    if uses_moadian_v2(setting) and not (setting.certificate or "").strip():
        missing.append("certificate")
    return missing


def merge_tax_setting_for_test(
    stored: TaxSetting | None,
    payload: Any | None,
    *,
    business_id: int,
) -> TaxSetting:
    """
    ادغام تنظیمات DB با مقادیر فرم UI برای تست اتصال بدون ذخیره اجباری.
    یک نمونه جدا (detached) برمی‌گرداند تا رکورد DB تغییر نکند.
    """
    setting = TaxSetting(business_id=int(business_id))
    if stored is not None:
        setting.tax_memory_id = stored.tax_memory_id
        setting.economic_code = stored.economic_code
        setting.private_key = stored.private_key
        setting.public_key = stored.public_key
        setting.certificate = stored.certificate
        setting.certificate_request = stored.certificate_request
        setting.sandbox_mode = bool(stored.sandbox_mode)

    if payload is None:
        return setting

    def _pick(new_val: Any, old_val: Any) -> Any:
        if new_val is None:
            return old_val
        if isinstance(new_val, str) and not new_val.strip():
            return old_val
        return new_val

    setting.tax_memory_id = _pick(getattr(payload, "tax_memory_id", None), setting.tax_memory_id)
    setting.economic_code = _pick(getattr(payload, "economic_code", None), setting.economic_code)
    setting.private_key = _pick(getattr(payload, "private_key", None), setting.private_key)
    setting.public_key = _pick(getattr(payload, "public_key", None), setting.public_key)
    setting.certificate = _pick(getattr(payload, "certificate", None), setting.certificate)
    setting.certificate_request = _pick(
        getattr(payload, "certificate_request", None),
        setting.certificate_request,
    )
    sandbox = getattr(payload, "sandbox_mode", None)
    if sandbox is not None:
        setting.sandbox_mode = bool(sandbox)
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
    suggested_person_type = _resolve_suggested_person_type(db, business_id)

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
            "suggested_person_type": suggested_person_type,
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
        "suggested_person_type": suggested_person_type,
    }


def _resolve_suggested_person_type(db: Session | None, business_id: int) -> str:
    if db is None:
        return "legal"
    from adapters.db.models.business import Business
    from app.services.tax_key_material_service import suggested_moadian_person_type

    business = db.query(Business).filter(Business.id == int(business_id)).first()
    if not business:
        return "legal"
    return suggested_moadian_person_type(business.business_type)


