from __future__ import annotations

import uuid
from datetime import date, timedelta
from typing import Any, Dict, Optional

from sqlalchemy import and_
from sqlalchemy.orm import Session

from adapters.db.models.document_numbering import DocumentCodeReservation
from app.core.datetime_utils import utc_now_aware
from app.core.responses import ApiError
from app.services.document_numbering_service import generate_document_code, reclaim_trailing_unused_document_codes

RESERVABLE_INVOICE_DOCUMENT_TYPES = frozenset(
    {
        "invoice_sales",
        "invoice_sales_return",
        "invoice_purchase",
        "invoice_purchase_return",
        "invoice_direct_consumption",
        "invoice_production",
        "invoice_waste",
    }
)

RESERVATION_TTL_HOURS = 4

_STATUS_ACTIVE = "active"
_STATUS_USED = "used"
_STATUS_CANCELLED = "cancelled"
_STATUS_EXPIRED = "expired"


def _reservation_to_dict(reservation: DocumentCodeReservation) -> Dict[str, Any]:
    return {
        "reservation_id": reservation.id,
        "code": reservation.code,
        "document_type": reservation.document_type,
        "document_date": reservation.document_date.isoformat(),
        "expires_at": reservation.expires_at.isoformat() if reservation.expires_at else None,
        "status": reservation.status,
    }


def expire_stale_reservations(db: Session, *, business_id: Optional[int] = None) -> int:
    now = utc_now_aware()
    query = db.query(DocumentCodeReservation).filter(
        DocumentCodeReservation.status == _STATUS_ACTIVE,
        DocumentCodeReservation.expires_at < now,
    )
    if business_id is not None:
        query = query.filter(DocumentCodeReservation.business_id == business_id)
    rows = query.with_for_update().all()
    if not isinstance(rows, (list, tuple)):
        return 0
    reclaim_keys: set[tuple[int, str, date]] = set()
    for row in rows:
        row.status = _STATUS_EXPIRED
        row.cancelled_at = now
        reclaim_keys.add((row.business_id, row.document_type, row.document_date))
    if rows:
        db.flush()
        for bid, doc_type, doc_date in reclaim_keys:
            reclaim_trailing_unused_document_codes(
                db,
                business_id=bid,
                document_type=doc_type,
                document_date=doc_date,
            )
    return len(rows)


def reserve_document_code(
    db: Session,
    *,
    business_id: int,
    user_id: int,
    document_type: str,
    document_date: date,
) -> Dict[str, Any]:
    doc_type = str(document_type or "").strip()
    if doc_type not in RESERVABLE_INVOICE_DOCUMENT_TYPES:
        raise ApiError(
            "INVALID_DOCUMENT_TYPE",
            "نوع سند برای رزرو شماره معتبر نیست",
            http_status=400,
        )

    expire_stale_reservations(db, business_id=business_id)

    code = generate_document_code(db, business_id, doc_type, document_date)
    now = utc_now_aware()
    reservation = DocumentCodeReservation(
        id=str(uuid.uuid4()),
        business_id=business_id,
        reserved_by_user_id=user_id,
        document_type=doc_type,
        document_date=document_date,
        code=code,
        status=_STATUS_ACTIVE,
        expires_at=now + timedelta(hours=RESERVATION_TTL_HOURS),
        created_at=now,
    )
    db.add(reservation)
    db.flush()
    return _reservation_to_dict(reservation)


def _get_reservation_for_user(
    db: Session,
    *,
    business_id: int,
    user_id: int,
    reservation_id: str,
    for_update: bool = False,
) -> Optional[DocumentCodeReservation]:
    query = db.query(DocumentCodeReservation).filter(
        and_(
            DocumentCodeReservation.id == reservation_id,
            DocumentCodeReservation.business_id == business_id,
            DocumentCodeReservation.reserved_by_user_id == user_id,
        )
    )
    if for_update:
        query = query.with_for_update()
    return query.first()


def cancel_document_code_reservation(
    db: Session,
    *,
    business_id: int,
    user_id: int,
    reservation_id: str,
) -> bool:
    reservation = _get_reservation_for_user(
        db,
        business_id=business_id,
        user_id=user_id,
        reservation_id=reservation_id,
        for_update=True,
    )
    if not reservation:
        raise ApiError(
            "CODE_RESERVATION_NOT_FOUND",
            "رزرو شماره یافت نشد",
            http_status=404,
        )
    if reservation.status != _STATUS_ACTIVE:
        return False
    reservation.status = _STATUS_CANCELLED
    reservation.cancelled_at = utc_now_aware()
    db.flush()
    reclaim_trailing_unused_document_codes(
        db,
        business_id=business_id,
        document_type=reservation.document_type,
        document_date=reservation.document_date,
    )
    return True


def validate_reservation_for_invoice_create(
    db: Session,
    *,
    business_id: int,
    user_id: int,
    reservation_id: str,
    invoice_type: str,
    document_date: date,
) -> DocumentCodeReservation:
    expire_stale_reservations(db, business_id=business_id)

    reservation = _get_reservation_for_user(
        db,
        business_id=business_id,
        user_id=user_id,
        reservation_id=reservation_id,
        for_update=True,
    )
    if not reservation:
        raise ApiError(
            "CODE_RESERVATION_NOT_FOUND",
            "رزرو شماره یافت نشد. لطفاً صفحه را بازخوانی کنید.",
            http_status=404,
        )

    now = utc_now_aware()
    if reservation.status == _STATUS_USED:
        raise ApiError(
            "CODE_RESERVATION_ALREADY_USED",
            "این رزرو شماره قبلاً استفاده شده است",
            http_status=409,
        )
    if reservation.status != _STATUS_ACTIVE:
        raise ApiError(
            "CODE_RESERVATION_EXPIRED",
            "رزرو شماره منقضی شده است. لطفاً شماره جدید دریافت کنید.",
            http_status=409,
        )
    if reservation.expires_at < now:
        reservation.status = _STATUS_EXPIRED
        reservation.cancelled_at = now
        db.flush()
        raise ApiError(
            "CODE_RESERVATION_EXPIRED",
            "رزرو شماره منقضی شده است. لطفاً شماره جدید دریافت کنید.",
            http_status=409,
        )
    if reservation.document_type != invoice_type:
        raise ApiError(
            "CODE_RESERVATION_MISMATCH",
            "نوع فاکتور با شماره رزروشده هم‌خوان نیست",
            http_status=400,
        )
    if reservation.document_date != document_date:
        raise ApiError(
            "CODE_RESERVATION_MISMATCH",
            "تاریخ فاکتور با شماره رزروشده هم‌خوان نیست",
            http_status=400,
        )
    return reservation


def mark_reservation_used(db: Session, reservation: DocumentCodeReservation) -> None:
    now = utc_now_aware()
    reservation.status = _STATUS_USED
    reservation.used_at = now
    db.flush()
