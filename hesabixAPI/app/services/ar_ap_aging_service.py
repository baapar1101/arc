"""گزارش سن بدهی / بستانکاری (AR/AP Aging) با پشتیبانی چندارزی."""
from __future__ import annotations

from collections import defaultdict, deque
from datetime import date, datetime
from decimal import Decimal
from typing import Any, Dict, List, Literal, Optional, Tuple

from sqlalchemy.orm import Session
from sqlalchemy import and_, or_, func, String

from adapters.db.models.document import Document
from adapters.db.models.document_line import DocumentLine
from adapters.db.models.person import Person
from adapters.db.models.business import Business
from adapters.db.models.currency import Currency

AgingMode = Literal["ar", "ap"]

DEFAULT_BUCKETS: Tuple[Tuple[str, int, Optional[int]], ...] = (
    ("0_30", 0, 30),
    ("31_60", 31, 60),
    ("61_90", 61, 90),
    ("91_120", 91, 120),
    ("120_plus", 121, None),
)


def _parse_date(value: Optional[str]) -> Optional[date]:
    if not value:
        return None
    try:
        return datetime.strptime(str(value)[:10], "%Y-%m-%d").date()
    except Exception:
        return None


def _bucket_key(age_days: int) -> str:
    for key, lo, hi in DEFAULT_BUCKETS:
        if hi is None:
            if age_days >= lo:
                return key
        elif lo <= age_days <= hi:
            return key
    return "120_plus"


def _empty_buckets() -> Dict[str, Decimal]:
    return {key: Decimal(0) for key, _lo, _hi in DEFAULT_BUCKETS}


def _person_display_name(person: Person) -> str:
    return (
        person.alias_name
        or person.company_name
        or " ".join(x for x in [person.first_name or "", person.last_name or ""] if x).strip()
        or (person.code or "")
        or str(person.id)
    )


def _line_amounts(
    line: DocumentLine,
    *,
    use_base: bool,
) -> Tuple[Decimal, Decimal]:
    if use_base:
        debit = (
            Decimal(str(line.debit_base))
            if getattr(line, "debit_base", None) is not None
            else Decimal(str(line.debit or 0))
        )
        credit = (
            Decimal(str(line.credit_base))
            if getattr(line, "credit_base", None) is not None
            else Decimal(str(line.credit or 0))
        )
        return debit, credit
    return Decimal(str(line.debit or 0)), Decimal(str(line.credit or 0))


def _age_open_items(
    open_items: List[Tuple[date, Decimal]],
    *,
    as_of: date,
) -> Dict[str, Decimal]:
    buckets = _empty_buckets()
    for doc_date, amount in open_items:
        if amount <= 0:
            continue
        age = max(0, (as_of - doc_date).days)
        buckets[_bucket_key(age)] += amount
    return buckets


def _fifo_open_debits(
    events: List[Tuple[date, Decimal, Decimal]],
) -> List[Tuple[date, Decimal]]:
    """رویدادها: (تاریخ، بدهکار، بستانکار). بستانکارها از قدیمی‌ترین بدهکارها کسر می‌شوند."""
    open_debits: deque[List[Any]] = deque()  # [date, remaining]
    for doc_date, debit, credit in events:
        if debit > 0:
            open_debits.append([doc_date, debit])
        rem_credit = credit
        while rem_credit > 0 and open_debits:
            oldest_date, oldest_amt = open_debits[0]
            take = min(oldest_amt, rem_credit)
            oldest_amt -= take
            rem_credit -= take
            if oldest_amt <= 0:
                open_debits.popleft()
            else:
                open_debits[0][1] = oldest_amt
    return [(d, a) for d, a in open_debits if a > 0]


def _fifo_open_credits(
    events: List[Tuple[date, Decimal, Decimal]],
) -> List[Tuple[date, Decimal]]:
    """بدهکارها از قدیمی‌ترین بستانکارها کسر می‌شوند (برای بستانکاران)."""
    open_credits: deque[List[Any]] = deque()
    for doc_date, debit, credit in events:
        if credit > 0:
            open_credits.append([doc_date, credit])
        rem_debit = debit
        while rem_debit > 0 and open_credits:
            oldest_date, oldest_amt = open_credits[0]
            take = min(oldest_amt, rem_debit)
            oldest_amt -= take
            rem_debit -= take
            if oldest_amt <= 0:
                open_credits.popleft()
            else:
                open_credits[0][1] = oldest_amt
    return [(d, a) for d, a in open_credits if a > 0]


def get_ar_ap_aging_report(
    db: Session,
    business_id: int,
    *,
    mode: AgingMode = "ar",
    fiscal_year_id: Optional[int] = None,
    currency_id: Optional[int] = None,
    as_of: Optional[str] = None,
    person_ids: Optional[List[int]] = None,
    search: Optional[str] = None,
    min_balance: Optional[float] = None,
    skip: int = 0,
    take: int = 50,
) -> Dict[str, Any]:
    """
    سن بدهی (ar) یا سن بستانکاری (ap).

    قرارداد چندارزی:
    - currency_id خالی → مبالغ معادل پایه (debit_base/credit_base)
    - currency_id مشخص → فقط همان ارز سند، مبالغ بومی
    """
    as_of_date = _parse_date(as_of) or date.today()
    use_base = currency_id is None
    mode = "ap" if mode == "ap" else "ar"

    query = db.query(Person).filter(Person.business_id == business_id)
    if person_ids:
        query = query.filter(Person.id.in_(person_ids))
    if search and search.strip():
        query = query.filter(
            or_(
                Person.alias_name.ilike(f"%{search}%"),
                Person.company_name.ilike(f"%{search}%"),
                Person.first_name.ilike(f"%{search}%"),
                Person.last_name.ilike(f"%{search}%"),
                func.cast(Person.code, String).ilike(f"%{search}%"),
            )
        )
    persons = query.all()
    if not persons:
        empty_summary = {
            "total_count": 0,
            "total_outstanding": 0.0,
            **{f"total_{k}": 0.0 for k, _a, _b in DEFAULT_BUCKETS},
        }
        return {
            "items": [],
            "summary": empty_summary,
            "pagination": {
                "total": 0,
                "page": 1,
                "per_page": take,
                "total_pages": 0,
                "has_next": False,
                "has_prev": False,
            },
            "meta": {
                "mode": mode,
                "as_of": as_of_date.isoformat(),
                "currency_id": currency_id,
                "amounts_in_base": use_base,
                "buckets": [
                    {"key": k, "from_days": lo, "to_days": hi}
                    for k, lo, hi in DEFAULT_BUCKETS
                ],
            },
        }

    person_map = {p.id: p for p in persons}
    pid_list = list(person_map.keys())

    lines_q = (
        db.query(DocumentLine, Document)
        .join(Document, DocumentLine.document_id == Document.id)
        .filter(
            and_(
                Document.business_id == business_id,
                Document.is_proforma == False,  # noqa: E712
                DocumentLine.person_id.in_(pid_list),
                Document.document_date <= as_of_date,
            )
        )
        .order_by(
            Document.document_date.asc(),
            Document.id.asc(),
            DocumentLine.id.asc(),
        )
    )
    if fiscal_year_id:
        lines_q = lines_q.filter(Document.fiscal_year_id == fiscal_year_id)
    if currency_id:
        lines_q = lines_q.filter(Document.currency_id == currency_id)

    events_by_person: Dict[int, List[Tuple[date, Decimal, Decimal]]] = defaultdict(list)
    for line, doc in lines_q.all():
        if not line.person_id or not doc.document_date:
            continue
        debit, credit = _line_amounts(line, use_base=use_base)
        if debit == 0 and credit == 0:
            continue
        events_by_person[int(line.person_id)].append((doc.document_date, debit, credit))

    items: List[Dict[str, Any]] = []
    for pid, person in person_map.items():
        events = events_by_person.get(pid) or []
        if not events:
            continue

        total_debit = sum((e[1] for e in events), Decimal(0))
        total_credit = sum((e[2] for e in events), Decimal(0))
        # همان قرارداد بدهکاران/بستانکاران: balance = credit - debit
        balance = total_credit - total_debit

        if mode == "ar":
            # بدهکار: balance < 0
            if balance >= 0:
                continue
            outstanding = -balance
            open_items = _fifo_open_debits(events)
        else:
            # بستانکار: balance > 0
            if balance <= 0:
                continue
            outstanding = balance
            open_items = _fifo_open_credits(events)

        if min_balance is not None and float(outstanding) < float(min_balance):
            continue

        buckets = _age_open_items(open_items, as_of=as_of_date)
        # نرمال‌سازی جمع سطل‌ها با مانده (اختلاف گرد کردن)
        bucket_sum = sum(buckets.values(), Decimal(0))
        if bucket_sum != outstanding and bucket_sum > 0:
            # مقیاس متناسب
            scale = outstanding / bucket_sum
            for k in buckets:
                buckets[k] = (buckets[k] * scale).quantize(Decimal("0.01"))
            drift = outstanding - sum(buckets.values(), Decimal(0))
            if drift != 0:
                # اختلاف را به آخرین سطل غیرصفر بده
                for k, _lo, _hi in reversed(DEFAULT_BUCKETS):
                    if buckets[k] > 0 or k == "120_plus":
                        buckets[k] += drift
                        break
        elif bucket_sum == 0 and outstanding > 0:
            buckets["0_30"] = outstanding

        last_date = events[-1][0]
        item = {
            "person_id": pid,
            "person_code": person.code or "",
            "person_name": _person_display_name(person),
            "outstanding": float(outstanding),
            "balance": float(balance),
            "last_transaction_date": last_date.isoformat() if last_date else None,
            **{k: float(v) for k, v in buckets.items()},
        }
        items.append(item)

    items.sort(key=lambda x: (-float(x["outstanding"]), str(x["person_name"])))

    summary_buckets = _empty_buckets()
    total_outstanding = Decimal(0)
    for it in items:
        total_outstanding += Decimal(str(it["outstanding"]))
        for k, _lo, _hi in DEFAULT_BUCKETS:
            summary_buckets[k] += Decimal(str(it[k]))

    total = len(items)
    page_items = items[skip : skip + take]
    total_pages = (total + take - 1) // take if take > 0 else 0
    current_page = (skip // take) + 1 if take > 0 else 1

    biz = db.query(Business).filter(Business.id == business_id).first()
    base_currency = None
    if biz and biz.default_currency_id:
        cur = db.query(Currency).filter(Currency.id == biz.default_currency_id).first()
        if cur:
            base_currency = {
                "id": cur.id,
                "code": cur.code,
                "symbol": cur.symbol,
                "name": cur.name,
            }

    return {
        "items": page_items,
        "summary": {
            "total_count": total,
            "total_outstanding": float(total_outstanding),
            **{f"total_{k}": float(v) for k, v in summary_buckets.items()},
        },
        "pagination": {
            "total": total,
            "page": current_page,
            "per_page": take,
            "total_pages": total_pages,
            "has_next": current_page < total_pages,
            "has_prev": current_page > 1,
        },
        "meta": {
            "mode": mode,
            "as_of": as_of_date.isoformat(),
            "currency_id": currency_id,
            "amounts_in_base": use_base,
            "base_currency": base_currency,
            "buckets": [
                {"key": k, "from_days": lo, "to_days": hi}
                for k, lo, hi in DEFAULT_BUCKETS
            ],
        },
    }
