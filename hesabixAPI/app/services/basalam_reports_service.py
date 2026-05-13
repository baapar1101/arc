"""گزارش‌های یکپارچه‌سازی باسلام (فقط خواندنی؛ فرض PostgreSQL برای فیلتر JSON)."""

from __future__ import annotations

from datetime import date, datetime, timedelta
from typing import Any, Dict, List, Optional

from sqlalchemy import and_, cast, func, or_, select
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Session

from adapters.db.models.document import Document
from app.services import basalam_integration_service as basalam_svc


def _basalam_invoice_filter():
    """فاکتورهایی که از باسلام سینک شده‌اند (PostgreSQL JSONB)."""
    j = cast(Document.extra_info, JSONB)
    return and_(
        Document.extra_info.isnot(None),
        or_(
            j["source"].astext == "basalam",
            j["basalam_order_id"].astext.isnot(None),
        ),
        Document.document_type.in_(("invoice_sales", "invoice_sales_return")),
    )


def _net_from_extra(extra: Optional[Dict[str, Any]]) -> float:
    if not isinstance(extra, dict):
        return 0.0
    totals = extra.get("totals")
    if not isinstance(totals, dict):
        return 0.0
    try:
        return float(totals.get("net") or 0)
    except (TypeError, ValueError):
        return 0.0


def get_overview(db: Session, business_id: int, *, chart_days: int = 90) -> Dict[str, Any]:
    settings = basalam_svc.get_settings(db, business_id)
    dlq = settings.get("sync_dead_letter")
    dlq_list = [x for x in dlq if isinstance(x, dict)] if isinstance(dlq, list) else []
    conflicts = settings.get("pending_product_conflicts")
    conf_list = [x for x in conflicts if isinstance(x, dict)] if isinstance(conflicts, list) else []

    end_d = date.today()
    start_d = end_d - timedelta(days=max(1, min(int(chart_days), 366)) - 1)

    bid = int(business_id)
    day_series_stmt = (
        select(Document.document_date, func.count(Document.id))
        .where(
            and_(
                Document.business_id == bid,
                Document.is_proforma.is_(False),
                _basalam_invoice_filter(),
                Document.document_date >= start_d,
                Document.document_date <= end_d,
            )
        )
        .group_by(Document.document_date)
        .order_by(Document.document_date)
    )
    rows = list(db.execute(day_series_stmt).all())
    orders_by_day: List[Dict[str, Any]] = []
    for d, cnt in rows:
        c = int(cnt or 0)
        ds = d.isoformat() if hasattr(d, "isoformat") else str(d)
        orders_by_day.append({"date": ds, "count": c})

    sum_stmt = select(func.count(Document.id)).where(
        and_(
            Document.business_id == bid,
            Document.is_proforma.is_(False),
            _basalam_invoice_filter(),
            Document.document_date >= start_d,
            Document.document_date <= end_d,
        )
    )
    period_count = int(db.execute(sum_stmt).scalar() or 0)

    # مجموع خالص دوره (در پایتون برای اجتناب از پیچیدگی JSON در SQL)
    docs = (
        db.query(Document.id, Document.extra_info)
        .filter(
            and_(
                Document.business_id == bid,
                Document.is_proforma.is_(False),
                _basalam_invoice_filter(),
                Document.document_date >= start_d,
                Document.document_date <= end_d,
            )
        )
        .limit(5000)
        .all()
    )
    period_net = sum(_net_from_extra(ex if isinstance(ex, dict) else None) for _, ex in docs)

    return {
        "summary": {
            "integration_enabled": bool(settings.get("enabled")),
            "webhook_enabled": bool(settings.get("webhook_enabled")),
            "last_webhook_event_at": settings.get("last_webhook_event_at"),
            "last_webhook_event_type": settings.get("last_webhook_event_type"),
            "dead_letter_count": len(dlq_list),
            "pending_product_conflicts_count": len(conf_list),
            "chart_days": int(chart_days),
            "basalam_invoices_in_period": period_count,
            "basalam_invoices_net_sum_in_period": period_net,
        },
        "orders_by_day": orders_by_day,
    }


def list_synced_invoices(
    db: Session,
    business_id: int,
    *,
    date_from: Optional[date] = None,
    date_to: Optional[date] = None,
    skip: int = 0,
    take: int = 50,
) -> Dict[str, Any]:
    bid = int(business_id)
    take = max(1, min(int(take), 200))
    skip = max(0, int(skip))

    conds = [
        Document.business_id == bid,
        Document.is_proforma.is_(False),
        _basalam_invoice_filter(),
    ]
    if date_from is not None:
        conds.append(Document.document_date >= date_from)
    if date_to is not None:
        conds.append(Document.document_date <= date_to)

    count_stmt = select(func.count(Document.id)).where(and_(*conds))
    total = int(db.execute(count_stmt).scalar() or 0)

    list_stmt = (
        select(Document)
        .where(and_(*conds))
        .order_by(Document.document_date.desc(), Document.id.desc())
        .offset(skip)
        .limit(take)
    )
    items: List[Dict[str, Any]] = []
    for doc in db.execute(list_stmt).scalars().all():
        extra = doc.extra_info if isinstance(doc.extra_info, dict) else {}
        oid = str(extra.get("basalam_order_id") or "").strip()
        items.append(
            {
                "document_id": int(doc.id),
                "code": doc.code,
                "document_date": doc.document_date.isoformat() if doc.document_date else None,
                "document_type": doc.document_type,
                "basalam_order_id": oid or None,
                "source": extra.get("source"),
                "net": _net_from_extra(extra),
                "description": (doc.description or "")[:500],
            }
        )

    return {"items": items, "total": total, "skip": skip, "take": take}


def list_dead_letter_for_report(
    db: Session,
    business_id: int,
    *,
    item_type: Optional[str] = None,
    limit: int = 100,
    offset: int = 0,
) -> Dict[str, Any]:
    return basalam_svc.list_sync_dead_letter(
        db,
        business_id,
        limit=limit,
        offset=offset,
        item_type=item_type,
    )


def list_product_conflicts_for_report(
    db: Session,
    business_id: int,
    *,
    conflict_type: Optional[str] = None,
    direction: Optional[str] = None,
    search: Optional[str] = None,
    sort_by: str = "created_at",
    sort_dir: str = "desc",
    limit: int = 50,
    offset: int = 0,
) -> Dict[str, Any]:
    return basalam_svc.list_product_conflicts(
        db,
        business_id,
        conflict_type=conflict_type,
        direction=direction,
        search=search,
        sort_by=sort_by,
        sort_dir=sort_dir,
        limit=limit,
        offset=offset,
    )


def parse_report_date(value: Optional[str]) -> Optional[date]:
    if not value or not str(value).strip():
        return None
    s = str(value).strip()
    if "T" in s:
        s = s.split("T", 1)[0]
    try:
        return datetime.strptime(s[:10], "%Y-%m-%d").date()
    except ValueError:
        return None
