"""کیفیت داده چندارزی: خطوط سند بدون معادل پایه."""
from __future__ import annotations

from datetime import date, datetime
from typing import Any, Dict, List, Optional

from sqlalchemy import and_, or_
from sqlalchemy.orm import Session

from adapters.db.models.business import Business
from adapters.db.models.currency import Currency
from adapters.db.models.document import Document
from adapters.db.models.document_line import DocumentLine
from adapters.db.models.fiscal_year import FiscalYear
from app.services.fx_rate_provider_service import business_is_multi_currency


def _parse_date(value: Optional[str]) -> Optional[date]:
    if not value:
        return None
    try:
        return datetime.strptime(str(value)[:10], "%Y-%m-%d").date()
    except Exception:
        return None


def get_missing_base_amount_warnings(
    db: Session,
    business_id: int,
    *,
    fiscal_year_id: Optional[int] = None,
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
    sample_limit: int = 20,
) -> Dict[str, Any]:
    """
    هشدار حسابداری: اسناد ارزی که debit_base/credit_base ندارند.

    بدون معادل پایه، تجمیع «همه ارزها → پایه» ناقص یا گمراه‌کننده است.
    """
    is_mc = business_is_multi_currency(db, business_id)
    biz = db.get(Business, business_id)
    base_id = int(biz.default_currency_id) if biz and biz.default_currency_id else None
    base_cur = db.get(Currency, base_id) if base_id else None

    empty = {
        "is_multi_currency": is_mc,
        "base_currency_id": base_id,
        "base_currency_code": getattr(base_cur, "code", None),
        "missing_line_count": 0,
        "affected_document_count": 0,
        "severity": "ok",
        "samples": [],
        "message_fa": "مشکل کیفیت داده چندارزی یافت نشد.",
        "message_en": "No multi-currency base-amount data quality issues found.",
    }
    if not is_mc or base_id is None:
        empty["severity"] = "n/a"
        empty["message_fa"] = "کسب‌وکار تک‌ارزی است یا ارز پایه تعریف نشده."
        return empty

    fy = None
    if fiscal_year_id:
        fy = db.query(FiscalYear).filter(FiscalYear.id == fiscal_year_id).first()
    if fy is None:
        fy = (
            db.query(FiscalYear)
            .filter(FiscalYear.business_id == business_id, FiscalYear.is_last == True)  # noqa: E712
            .first()
        )

    date_from_obj = _parse_date(date_from) or (fy.start_date if fy else None)
    date_to_obj = _parse_date(date_to) or (fy.end_date if fy and fy.end_date else date.today())

    q = (
        db.query(DocumentLine, Document)
        .join(Document, DocumentLine.document_id == Document.id)
        .filter(
            and_(
                Document.business_id == business_id,
                Document.is_proforma == False,  # noqa: E712
                Document.currency_id.isnot(None),
                Document.currency_id != base_id,
                or_(
                    and_(DocumentLine.debit.isnot(None), DocumentLine.debit != 0, DocumentLine.debit_base.is_(None)),
                    and_(DocumentLine.credit.isnot(None), DocumentLine.credit != 0, DocumentLine.credit_base.is_(None)),
                ),
            )
        )
    )
    if fy:
        q = q.filter(Document.fiscal_year_id == fy.id)
    if date_from_obj:
        q = q.filter(Document.document_date >= date_from_obj)
    if date_to_obj:
        q = q.filter(Document.document_date <= date_to_obj)

    rows = q.order_by(Document.document_date.desc(), Document.id.desc()).all()
    doc_ids = {int(doc.id) for _line, doc in rows}
    samples: List[Dict[str, Any]] = []
    for line, doc in rows[: max(0, int(sample_limit))]:
        samples.append(
            {
                "document_id": doc.id,
                "document_code": doc.code or "",
                "document_date": doc.document_date.isoformat() if doc.document_date else None,
                "document_currency_id": doc.currency_id,
                "line_id": line.id,
                "account_id": line.account_id,
                "debit": float(line.debit or 0),
                "credit": float(line.credit or 0),
                "debit_base": float(line.debit_base) if line.debit_base is not None else None,
                "credit_base": float(line.credit_base) if line.credit_base is not None else None,
            }
        )

    missing = len(rows)
    severity = "ok"
    if missing > 0:
        severity = "warning" if missing < 50 else "high"
    message_fa = (
        "مشکل کیفیت داده چندارزی یافت نشد."
        if missing == 0
        else f"{missing} خط سند ارزی بدون معادل پایه (*_base) یافت شد؛ گزارش‌های «همه ارزها» ممکن است ناقص باشند."
    )

    return {
        "is_multi_currency": True,
        "base_currency_id": base_id,
        "base_currency_code": getattr(base_cur, "code", None),
        "missing_line_count": missing,
        "affected_document_count": len(doc_ids),
        "severity": severity,
        "samples": samples,
        "date_from": date_from_obj.isoformat() if date_from_obj else None,
        "date_to": date_to_obj.isoformat() if date_to_obj else None,
        "fiscal_year_id": fy.id if fy else None,
        "message_fa": message_fa,
        "message_en": (
            "No issues."
            if missing == 0
            else f"{missing} foreign-currency lines lack base equivalents."
        ),
    }
