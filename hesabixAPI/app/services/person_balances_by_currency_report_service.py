"""گزارش مانده اشخاص به تفکیک ارز — اصول حسابداری چندارزی.

هر ارز سند به‌صورت جداگانه مانده بومی دارد؛ معادل پایه برای تجمیع و مقایسه
بین ارزها اضافه می‌شود. تسویه بین‌ارزی و تسعیر پایان‌دوره از سرویس موجود
`calculate_person_balances_by_currency` پیروی می‌کند.
"""
from __future__ import annotations

from decimal import Decimal
from typing import Any, Dict, List, Optional

from sqlalchemy import String, func, or_
from sqlalchemy.orm import Session

from adapters.db.models.business import Business
from adapters.db.models.currency import Currency
from adapters.db.models.person import Person
from app.services.fx_rate_provider_service import business_is_multi_currency
from app.services.person_service import calculate_person_balances_by_currency


def _person_display_name(person: Person) -> str:
    return (
        person.alias_name
        or person.company_name
        or " ".join(x for x in [person.first_name or "", person.last_name or ""] if x).strip()
        or (person.code or "")
        or str(person.id)
    )


def get_person_balances_by_currency_report(
    db: Session,
    business_id: int,
    *,
    fiscal_year_id: Optional[int] = None,
    person_ids: Optional[List[int]] = None,
    search: Optional[str] = None,
    only_with_balance: bool = True,
    skip: int = 0,
    take: int = 50,
) -> Dict[str, Any]:
    """
    خروجی تخت: یک ردیف به‌ازای هر (شخص، ارز) با مانده بومی + معادل پایه.

    قواعد:
    - balance = credit − debit (بومی همان ارز)
    - base_equivalent از مسیر استاندارد تسعیر خطوط
    - total_base در سطح شخص جمع معادل‌های پایه است
    """
    query = db.query(Person).filter(Person.business_id == business_id)
    if person_ids:
        query = query.filter(Person.id.in_([int(x) for x in person_ids]))
    if search and str(search).strip():
        q = str(search).strip()
        query = query.filter(
            or_(
                Person.alias_name.ilike(f"%{q}%"),
                Person.company_name.ilike(f"%{q}%"),
                Person.first_name.ilike(f"%{q}%"),
                Person.last_name.ilike(f"%{q}%"),
                func.cast(Person.code, String).ilike(f"%{q}%"),
            )
        )
    persons = query.order_by(Person.id.asc()).all()

    biz = db.get(Business, business_id)
    base_currency_id = int(biz.default_currency_id) if biz and biz.default_currency_id else None
    base_currency = db.get(Currency, base_currency_id) if base_currency_id else None
    is_mc = business_is_multi_currency(db, business_id)

    person_rows: List[Dict[str, Any]] = []
    flat_items: List[Dict[str, Any]] = []

    for person in persons:
        detail = calculate_person_balances_by_currency(
            db, int(person.id), fiscal_year_id=fiscal_year_id
        )
        balances = list(detail.get("balances") or [])
        total_base = Decimal(str(detail.get("total_base") or 0))
        if only_with_balance:
            balances = [b for b in balances if abs(float(b.get("balance") or 0)) > 1e-9]
            if not balances and abs(float(total_base)) <= 1e-9:
                continue

        person_payload = {
            "person_id": int(person.id),
            "person_code": person.code or "",
            "person_name": _person_display_name(person),
            "status": detail.get("status"),
            "total_base": float(total_base),
            "balances": balances,
        }
        person_rows.append(person_payload)

        for bal in balances:
            flat_items.append(
                {
                    "person_id": int(person.id),
                    "person_code": person.code or "",
                    "person_name": _person_display_name(person),
                    "currency_id": bal.get("currency_id"),
                    "currency_code": bal.get("currency_code"),
                    "currency_title": bal.get("currency_title"),
                    "currency_symbol": bal.get("currency_symbol"),
                    "decimal_places": bal.get("decimal_places"),
                    "is_base_currency": bal.get("is_base_currency"),
                    "total_debit": bal.get("total_debit"),
                    "total_credit": bal.get("total_credit"),
                    "balance": bal.get("balance"),
                    "base_equivalent": bal.get("base_equivalent"),
                    "status": bal.get("status"),
                    "person_total_base": float(total_base),
                    "person_status": detail.get("status"),
                }
            )

    # مرتب‌سازی: بیشترین |معادل پایه| شخص، سپس ارز
    flat_items.sort(
        key=lambda x: (
            -abs(float(x.get("person_total_base") or 0)),
            str(x.get("person_name") or ""),
            str(x.get("currency_code") or ""),
        )
    )

    total = len(flat_items)
    page_items = flat_items[skip : skip + take]
    total_pages = (total + take - 1) // take if take > 0 else 0
    current_page = (skip // take) + 1 if take > 0 else 1

    summary_base = sum((Decimal(str(p.get("total_base") or 0)) for p in person_rows), Decimal(0))
    debtor_base = sum(
        (Decimal(str(p.get("total_base") or 0)) for p in person_rows if float(p.get("total_base") or 0) < 0),
        Decimal(0),
    )
    creditor_base = sum(
        (Decimal(str(p.get("total_base") or 0)) for p in person_rows if float(p.get("total_base") or 0) > 0),
        Decimal(0),
    )

    return {
        "items": page_items,
        "persons": person_rows,  # ساختار درختی کامل (بدون pagination روی persons)
        "summary": {
            "person_count": len(person_rows),
            "currency_row_count": total,
            "total_base": float(summary_base),
            "total_debtor_base": float(abs(debtor_base)),
            "total_creditor_base": float(creditor_base),
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
            "fiscal_year_id": fiscal_year_id,
            "is_multi_currency": is_mc,
            "amounts_in_base": False,  # ردیف‌ها بومی per-currency هستند
            "base_currency": {
                "id": base_currency_id,
                "code": getattr(base_currency, "code", None),
                "symbol": getattr(base_currency, "symbol", None),
                "name": getattr(base_currency, "name", None) or getattr(base_currency, "title", None),
            }
            if base_currency_id
            else None,
            "note": "هر ردیف مانده بومی یک ارز است؛ base_equivalent و person_total_base برای مقایسه به ارز پایه‌اند.",
        },
    }
