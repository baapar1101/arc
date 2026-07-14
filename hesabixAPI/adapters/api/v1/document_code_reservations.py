from __future__ import annotations

from datetime import date

from fastapi import APIRouter, Body, Depends, Path, Request
from sqlalchemy.orm import Session

from adapters.api.v1.schemas import (
    DocumentCodeReservationRequest,
    DocumentCodeReservationResponse,
)
from adapters.db.session import get_db
from app.core.auth_dependency import AuthContext, get_current_user
from app.core.permissions import (
    require_business_access_dep,
    require_business_permission_dep,
    require_invoice_type_permission_from_payload_dep,
)
from app.core.responses import ApiError, success_response
from app.services.document_code_reservation_service import (
    cancel_document_code_reservation,
    reserve_document_code,
)

router = APIRouter(
    prefix="/businesses/{business_id}/document-code-reservations",
    tags=["document-numbering"],
)


def _parse_document_date(value: str) -> date:
    raw = str(value or "").strip()
    if not raw:
        raise ApiError("DOCUMENT_DATE_REQUIRED", "تاریخ سند الزامی است", http_status=400)
    try:
        if "T" in raw:
            raw = raw.split("T", 1)[0]
        return date.fromisoformat(raw)
    except ValueError as exc:
        raise ApiError("INVALID_DOCUMENT_DATE", "تاریخ سند نامعتبر است", http_status=400) from exc


@router.post(
    "",
    summary="رزرو شماره سند (قطعی)",
    description="برای نمایش شماره قطعی فاکتور در فرم ایجاد؛ شمارنده افزایش می‌یابد و شماره تا زمان انقضا یا ثبت محفوظ می‌ماند.",
)
def reserve_document_code_endpoint(
    request: Request,
    business_id: int = Path(..., description="شناسه کسب و کار"),
    data: DocumentCodeReservationRequest = Body(...),
    _: None = Depends(require_business_access_dep),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    __: None = Depends(require_business_permission_dep("invoices", "add")),
    ___: None = Depends(
        require_invoice_type_permission_from_payload_dep("add", payload_field="document_type")
    ),
) -> dict:
    document_date = _parse_document_date(data.document_date)
    result = reserve_document_code(
        db,
        business_id=business_id,
        user_id=ctx.get_user_id(),
        document_type=data.document_type,
        document_date=document_date,
    )
    db.commit()
    return success_response(
        DocumentCodeReservationResponse(**result).dict(),
        request,
        message="DOCUMENT_CODE_RESERVED",
    )


@router.delete(
    "/{reservation_id}",
    summary="لغو رزرو شماره سند",
)
def cancel_document_code_reservation_endpoint(
    request: Request,
    business_id: int = Path(..., description="شناسه کسب و کار"),
    reservation_id: str = Path(..., description="شناسه رزرو"),
    _: None = Depends(require_business_access_dep),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    __: None = Depends(require_business_permission_dep("invoices", "add")),
) -> dict:
    cancelled = cancel_document_code_reservation(
        db,
        business_id=business_id,
        user_id=ctx.get_user_id(),
        reservation_id=reservation_id,
    )
    db.commit()
    return success_response(
        {"cancelled": cancelled},
        request,
        message="DOCUMENT_CODE_RESERVATION_CANCELLED",
    )
