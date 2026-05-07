"""بارگذاری لوگوی کسب‌وکار برای لینک‌های اشتراک عمومی (بدون افزایش view_count)."""

from __future__ import annotations

from typing import Optional
from uuid import UUID

from sqlalchemy.orm import Session

from adapters.db.models.business import Business
from app.services.document_share_link_service import get_share_link_by_code as get_document_share_by_code
from app.services.person_share_link_service import get_share_link_by_code as get_person_share_by_code


def business_logo_file_id_for_invoice_share(db: Session, code: str) -> Optional[UUID]:
    link = get_document_share_by_code(db, code)
    if not link or not link.is_active:
        return None
    business = db.query(Business).filter(Business.id == link.business_id).first()
    if not business:
        return None
    fid = getattr(business, "logo_file_id", None)
    if not fid:
        return None
    try:
        return UUID(str(fid))
    except Exception:
        return None


def business_logo_file_id_for_person_share(db: Session, code: str) -> Optional[UUID]:
    link = get_person_share_by_code(db, code)
    if not link or not link.is_active:
        return None
    business = db.query(Business).filter(Business.id == link.business_id).first()
    if not business:
        return None
    fid = getattr(business, "logo_file_id", None)
    if not fid:
        return None
    try:
        return UUID(str(fid))
    except Exception:
        return None
