from __future__ import annotations

from typing import List

from fastapi import APIRouter, Depends, Request, HTTPException, Path
from sqlalchemy.orm import Session
from sqlalchemy import and_

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.permissions import require_business_access_dep
from app.core.responses import success_response
from adapters.db.models.document_numbering import BusinessDocumentNumberingSetting
from adapters.api.v1.schemas import (
    DocumentNumberingSettingRequest,
    DocumentNumberingSettingResponse,
)

router = APIRouter(
    prefix="/businesses/{business_id}/document-numbering-settings",
    tags=["document-numbering"],
)


def _get_default_setting(document_type: str) -> dict:
    """
    برگرداندن تنظیمات پیش‌فرض برای هر نوع سند
    """
    defaults = {
        "invoice_sales": {
            "prefix": "INV",
            "include_date": True,
            "calendar_type": "gregorian",
            "date_format": "YYYYMMDD",
        },
        "invoice_sales_return": {
            "prefix": "INV-RET",
            "include_date": True,
            "calendar_type": "gregorian",
            "date_format": "YYYYMMDD",
        },
        "invoice_purchase": {
            "prefix": "INV-PUR",
            "include_date": True,
            "calendar_type": "gregorian",
            "date_format": "YYYYMMDD",
        },
        "invoice_purchase_return": {
            "prefix": "INV-PUR-RET",
            "include_date": True,
            "calendar_type": "gregorian",
            "date_format": "YYYYMMDD",
        },
        "invoice_direct_consumption": {
            "prefix": "INV-CON",
            "include_date": True,
            "calendar_type": "gregorian",
            "date_format": "YYYYMMDD",
        },
        "invoice_production": {
            "prefix": "INV-PROD",
            "include_date": True,
            "calendar_type": "gregorian",
            "date_format": "YYYYMMDD",
        },
        "invoice_waste": {
            "prefix": "INV-WASTE",
            "include_date": True,
            "calendar_type": "gregorian",
            "date_format": "YYYYMMDD",
        },
        "receipt": {
            "prefix": "RC",
            "include_date": True,
            "calendar_type": "gregorian",
            "date_format": "YYYYMMDD",
        },
        "payment": {
            "prefix": "PY",
            "include_date": True,
            "calendar_type": "gregorian",
            "date_format": "YYYYMMDD",
        },
        "transfer": {
            "prefix": "TR",
            "include_date": True,
            "calendar_type": "gregorian",
            "date_format": "YYYYMMDD",
        },
        "expense": {
            "prefix": "EXP",
            "include_date": True,
            "calendar_type": "gregorian",
            "date_format": "YYYYMMDD",
        },
        "income": {
            "prefix": "INC",
            "include_date": True,
            "calendar_type": "gregorian",
            "date_format": "YYYYMMDD",
        },
        "crm_lead": {
            "prefix": "L",
            "include_date": True,
            "calendar_type": "gregorian",
            "date_format": "YYYYMMDD",
        },
        "crm_deal": {
            "prefix": "D",
            "include_date": True,
            "calendar_type": "gregorian",
            "date_format": "YYYYMMDD",
        },
        "crm_activity": {
            "prefix": "A",
            "include_date": True,
            "calendar_type": "gregorian",
            "date_format": "YYYYMMDD",
        },
        "warehouse_document": {
            "prefix": "WH",
            "include_date": True,
            "calendar_type": "gregorian",
            "date_format": "YYYYMMDD",
        },
    }

    default = defaults.get(
        document_type,
        {
            "prefix": "DOC",
            "include_date": True,
            "calendar_type": "gregorian",
            "date_format": "YYYYMMDD",
            "separator": "-",
            "start_number": 1,
            "number_padding": 4,
            "reset_period": "never",
        },
    )

    return default


@router.get(
    "",
    summary="دریافت تمام تنظیمات شماره‌گذاری اسناد یک کسب و کار",
)
def get_document_numbering_settings(
    request: Request,
    business_id: int = Path(..., description="شناسه کسب و کار"),
    _: None = Depends(require_business_access_dep),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> dict:
    """
    دریافت تمام تنظیمات شماره‌گذاری اسناد یک کسب و کار
    """
    if not ctx.has_business_permission("settings", "join"):
        raise HTTPException(status_code=403, detail="دسترسی غیرمجاز")

    settings = (
        db.query(BusinessDocumentNumberingSetting)
        .filter(BusinessDocumentNumberingSetting.business_id == business_id)
        .all()
    )

    return success_response(
        [DocumentNumberingSettingResponse.from_orm(s).dict() for s in settings], request
    )


@router.get(
    "/{document_type}",
    summary="دریافت تنظیمات شماره‌گذاری برای یک نوع سند خاص",
)
def get_document_numbering_setting(
    request: Request,
    business_id: int = Path(..., description="شناسه کسب و کار"),
    document_type: str = Path(..., description="نوع سند"),
    _: None = Depends(require_business_access_dep),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> dict:
    """
    دریافت تنظیمات شماره‌گذاری برای یک نوع سند خاص
    """
    if not ctx.has_business_permission("settings", "join"):
        raise HTTPException(status_code=403, detail="دسترسی غیرمجاز")

    setting = (
        db.query(BusinessDocumentNumberingSetting)
        .filter(
            and_(
                BusinessDocumentNumberingSetting.business_id == business_id,
                BusinessDocumentNumberingSetting.document_type == document_type,
            )
        )
        .first()
    )

    if not setting:
        # برگرداندن تنظیمات پیش‌فرض
        default = _get_default_setting(document_type)
        return success_response(default, request)

    return success_response(
        DocumentNumberingSettingResponse.from_orm(setting).dict(), request
    )


@router.post(
    "",
    summary="ایجاد یا به‌روزرسانی تنظیمات شماره‌گذاری",
)
def create_or_update_document_numbering_setting(
    request: Request,
    business_id: int = Path(..., description="شناسه کسب و کار"),
    data: DocumentNumberingSettingRequest = ...,
    _: None = Depends(require_business_access_dep),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> dict:
    """
    ایجاد یا به‌روزرسانی تنظیمات شماره‌گذاری
    """
    if not ctx.has_business_permission("settings", "join"):
        raise HTTPException(status_code=403, detail="دسترسی غیرمجاز")

    from datetime import datetime

    existing = (
        db.query(BusinessDocumentNumberingSetting)
        .filter(
            and_(
                BusinessDocumentNumberingSetting.business_id == business_id,
                BusinessDocumentNumberingSetting.document_type == data.document_type,
            )
        )
        .first()
    )

    if existing:
        # به‌روزرسانی
        for key, value in data.dict(exclude_unset=True).items():
            setattr(existing, key, value)
        existing.updated_at = datetime.utcnow()
        db.commit()
        db.refresh(existing)
        return success_response(
            DocumentNumberingSettingResponse.from_orm(existing).dict(),
            request,
            message="تنظیمات به‌روزرسانی شد",
        )
    else:
        # ایجاد جدید
        new_setting = BusinessDocumentNumberingSetting(
            business_id=business_id, **data.dict()
        )
        db.add(new_setting)
        db.commit()
        db.refresh(new_setting)
        return success_response(
            DocumentNumberingSettingResponse.from_orm(new_setting).dict(),
            request,
            message="تنظیمات ایجاد شد",
        )


@router.delete(
    "/{document_type}",
    summary="حذف تنظیمات شماره‌گذاری (بازگشت به پیش‌فرض)",
)
def delete_document_numbering_setting(
    request: Request,
    business_id: int = Path(..., description="شناسه کسب و کار"),
    document_type: str = Path(..., description="نوع سند"),
    _: None = Depends(require_business_access_dep),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> dict:
    """
    حذف تنظیمات شماره‌گذاری (بازگشت به پیش‌فرض)
    """
    if not ctx.has_business_permission("settings", "join"):
        raise HTTPException(status_code=403, detail="دسترسی غیرمجاز")

    setting = (
        db.query(BusinessDocumentNumberingSetting)
        .filter(
            and_(
                BusinessDocumentNumberingSetting.business_id == business_id,
                BusinessDocumentNumberingSetting.document_type == document_type,
            )
        )
        .first()
    )

    if setting:
        db.delete(setting)
        db.commit()

    return success_response(
        {"message": "تنظیمات حذف شد و به حالت پیش‌فرض بازگشت"}, request
    )


