from __future__ import annotations

from decimal import Decimal
from typing import Any, Dict, List, Optional

from sqlalchemy import and_
from sqlalchemy.orm import Session

from adapters.db.models.document import Document
from adapters.db.models.document_line import DocumentLine
from app.services.account_balance_core import (
    build_account_tree,
    build_tree_items,
    compute_leaf_balances,
    fetch_business_accounts,
    resolve_date_range,
    sum_root_items_only,
    validate_trial_balance,
)


def _document_type_name(doc_type: str | None) -> str:
    if not doc_type:
        return ""
    mapping = {
        "invoice_sales": "فاکتور فروش",
        "invoice_sales_return": "برگشت از فروش",
        "invoice_purchase": "فاکتور خرید",
        "invoice_purchase_return": "برگشت از خرید",
        "receipt": "دریافت",
        "payment": "پرداخت",
        "transfer": "انتقال",
        "expense_income": "درآمد/هزینه",
        "opening_balance": "تراز افتتاحیه",
        "manual_document": "سند دستی",
    }
    return mapping.get(doc_type, doc_type)


def _line_amount_for_report(
    line: DocumentLine,
    *,
    use_base: bool,
    side: str,
) -> Decimal:
    """مبلغ بدهکار/بستانکار ردیف؛ در حالت همه ارزها از معادل پایه استفاده می‌شود."""
    if side == "debit":
        native = Decimal(str(line.debit or 0))
        if not use_base:
            return native
        base = getattr(line, "debit_base", None)
        return Decimal(str(base)) if base is not None else native
    native = Decimal(str(line.credit or 0))
    if not use_base:
        return native
    base = getattr(line, "credit_base", None)
    return Decimal(str(base)) if base is not None else native


def get_accounts_review_report(
    db: Session,
    business_id: int,
    fiscal_year_id: Optional[int] = None,
    currency_id: Optional[int] = None,
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
    account_type: Optional[str] = None,
    include_zero_balance: bool = False,
    account_id: Optional[int] = None,
    skip: int = 0,
    take: int = 50,
) -> Dict[str, Any]:
    """
    گزارش مرور حساب‌ها با همان قرارداد چندارزی تراز آزمایشی:
    - currency_id خالی → مبالغ معادل ارز پایه (debit_base/credit_base)
    - currency_id مشخص → فقط اسناد همان ارز با مبالغ بومی
    """
    fy_id, date_from_obj, date_to_obj = resolve_date_range(
        db, business_id, fiscal_year_id, date_from, date_to
    )
    use_base = currency_id is None

    all_accounts = fetch_business_accounts(db, business_id, account_type)
    empty_pagination = {
        "total": 0,
        "page": 1,
        "per_page": take,
        "total_pages": 1,
        "has_next": False,
        "has_prev": False,
    }
    if not all_accounts:
        return {
            "accounts": [],
            "account_details": [],
            "summary": {
                "total_opening_debit": 0.0,
                "total_opening_credit": 0.0,
                "total_period_debit": 0.0,
                "total_period_credit": 0.0,
                "total_closing_debit": 0.0,
                "total_closing_credit": 0.0,
                "balance_valid": True,
                "balance_error": None,
                "opening_balance_diff": 0.0,
                "period_balance_diff": 0.0,
                "closing_balance_diff": 0.0,
            },
            "pagination": empty_pagination,
            "meta": {
                "currency_id": currency_id,
                "amounts_in_base": use_base,
                "date_from": date_from_obj.isoformat(),
                "date_to": date_to_obj.isoformat(),
                "fiscal_year_id": fy_id,
            },
        }

    account_ids = [acc.id for acc in all_accounts]
    account_tree = build_account_tree(all_accounts)
    leaf_balances = compute_leaf_balances(
        db,
        business_id,
        account_ids,
        date_from_obj,
        date_to_obj,
        fy_id,
        currency_id,
    )
    accounts_list = build_tree_items(
        account_tree,
        leaf_balances,
        include_zero_balance=include_zero_balance,
    )

    totals = sum_root_items_only(accounts_list)
    validation = validate_trial_balance(totals)

    account_details: List[Dict[str, Any]] = []
    details_pagination = dict(empty_pagination)

    if account_id and account_id in account_ids:
        leaf = leaf_balances.get(account_id)
        running_balance = Decimal(0)
        if leaf is not None:
            running_balance = leaf.opening_debit - leaf.opening_credit

        details_query = (
            db.query(DocumentLine, Document)
            .join(Document, DocumentLine.document_id == Document.id)
            .filter(
                and_(
                    Document.business_id == business_id,
                    Document.is_proforma == False,  # noqa: E712
                    DocumentLine.account_id == account_id,
                    Document.document_date >= date_from_obj,
                    Document.document_date <= date_to_obj,
                    Document.fiscal_year_id == fy_id,
                )
            )
            .order_by(
                Document.document_date.asc(),
                Document.id.asc(),
                DocumentLine.id.asc(),
            )
        )
        if currency_id:
            details_query = details_query.filter(Document.currency_id == currency_id)

        total_details = details_query.count()
        details_lines = details_query.offset(skip).limit(take).all()

        person_ids = list(
            {line.person_id for line, _doc in details_lines if line.person_id is not None}
        )
        persons_map: Dict[int, Dict[str, Any]] = {}
        if person_ids:
            from adapters.db.models.person import Person

            for person in db.query(Person).filter(Person.id.in_(person_ids)).all():
                persons_map[person.id] = {
                    "id": person.id,
                    "code": person.code,
                    "name": person.alias_name or person.name or "",
                }

        for line, doc in details_lines:
            debit = _line_amount_for_report(line, use_base=use_base, side="debit")
            credit = _line_amount_for_report(line, use_base=use_base, side="credit")
            running_balance = running_balance + debit - credit

            balance_type = "balanced"
            if running_balance > 0:
                balance_type = "debit"
            elif running_balance < 0:
                balance_type = "credit"

            counterpart_name = ""
            if line.person_id and line.person_id in persons_map:
                counterpart_name = persons_map[line.person_id]["name"]

            account_details.append(
                {
                    "document_id": doc.id,
                    "document_code": doc.code or "",
                    "document_date": doc.document_date.isoformat() if doc.document_date else None,
                    "document_type": doc.document_type or "",
                    "document_type_name": _document_type_name(doc.document_type),
                    "counterpart_name": counterpart_name,
                    "debit": float(debit),
                    "credit": float(credit),
                    "balance": float(running_balance),
                    "balance_type": balance_type,
                    "description": line.description or doc.description or "",
                    "document_currency_id": doc.currency_id,
                    "amounts_in_base": use_base,
                }
            )

        details_pagination = {
            "total": total_details,
            "page": (skip // take) + 1 if take > 0 else 1,
            "per_page": take,
            "total_pages": (total_details + take - 1) // take if take > 0 else 1,
            "has_next": (skip + take) < total_details,
            "has_prev": skip > 0,
        }

    return {
        "accounts": accounts_list,
        "account_details": account_details,
        "summary": {
            "total_opening_debit": float(totals["opening_debit"]),
            "total_opening_credit": float(totals["opening_credit"]),
            "total_period_debit": float(totals["period_debit"]),
            "total_period_credit": float(totals["period_credit"]),
            "total_closing_debit": float(totals["closing_debit"]),
            "total_closing_credit": float(totals["closing_credit"]),
            **validation,
        },
        "pagination": details_pagination,
        "meta": {
            "currency_id": currency_id,
            "amounts_in_base": use_base,
            "date_from": date_from_obj.isoformat(),
            "date_to": date_to_obj.isoformat(),
            "fiscal_year_id": fy_id,
        },
    }
