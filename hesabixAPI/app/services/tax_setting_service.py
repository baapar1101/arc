from __future__ import annotations

from typing import Dict, Any
from datetime import datetime

from sqlalchemy.orm import Session

from adapters.db.models.tax_setting import TaxSetting


def get_tax_setting(db: Session, business_id: int) -> TaxSetting | None:
    return (
        db.query(TaxSetting)
        .filter(TaxSetting.business_id == int(business_id))
        .first()
    )


def upsert_tax_setting(
    db: Session,
    *,
    business_id: int,
    user_id: int,
    payload: Dict[str, Any],
) -> TaxSetting:
    setting = get_tax_setting(db, business_id)
    now = datetime.utcnow()
    if setting is None:
        setting = TaxSetting(
            business_id=int(business_id),
            created_by_user_id=int(user_id),
            created_at=now,
        )
        db.add(setting)

    setting.tax_memory_id = payload.get("tax_memory_id")
    setting.economic_code = payload.get("economic_code")
    setting.private_key = payload.get("private_key")
    setting.public_key = payload.get("public_key")
    setting.certificate = payload.get("certificate")
    setting.certificate_request = payload.get("certificate_request")
    setting.sandbox_mode = bool(payload.get("sandbox_mode", False))
    setting.updated_at = now

    db.flush()
    db.refresh(setting)
    return setting


def serialize_tax_setting(setting: TaxSetting | None, business_id: int) -> Dict[str, Any]:
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
        }

    return {
        "business_id": int(setting.business_id),
        "tax_memory_id": setting.tax_memory_id,
        "economic_code": setting.economic_code,
        "private_key": setting.private_key,
        "public_key": setting.public_key,
        "certificate": setting.certificate,
        "certificate_request": setting.certificate_request,
        "sandbox_mode": bool(setting.sandbox_mode),
        "has_private_key": bool(setting.private_key),
        "updated_at": setting.updated_at.isoformat() if setting.updated_at else None,
    }


