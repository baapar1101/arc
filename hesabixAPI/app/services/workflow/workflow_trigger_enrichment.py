"""
غنی‌سازی trigger_data برای اجرای ورک‌فلو تا فیلترهای UI و قالب‌های پیام دادهٔ کامل داشته باشند.
"""

from __future__ import annotations

import logging
from decimal import Decimal
from typing import Any, Dict, List, Optional, Set

from sqlalchemy.orm import Session

from adapters.db.models.document import Document
from adapters.db.models.document_line import DocumentLine

logger = logging.getLogger(__name__)

DOCUMENT_TYPES_RECEIPT_PAYMENT = frozenset({"receipt", "payment"})


def _infer_payment_method_from_line(line: DocumentLine) -> Optional[str]:
    if line.check_id:
        return "check"
    if line.bank_account_id:
        return "bank"
    if line.cash_register_id or line.petty_cash_id:
        return "cash"
    ex = line.extra_info or {}
    if isinstance(ex, dict):
        tt = ex.get("transaction_type")
        if tt == "bank":
            return "bank"
        if tt in ("cash_register", "petty_cash"):
            return "cash"
        if tt in ("check", "check_expense"):
            return "check"
        if ex.get("card") or ex.get("is_card"):
            return "card"
    return None


def build_receipt_payment_trigger_enrichment(
    db: Session,
    business_id: int,
    document_id: int,
) -> Dict[str, Any]:
    doc = db.query(Document).filter(Document.id == int(document_id)).first()
    if not doc or int(doc.business_id) != int(business_id):
        return {}
    if doc.document_type not in DOCUMENT_TYPES_RECEIPT_PAYMENT:
        return {}

    lines = db.query(DocumentLine).filter(DocumentLine.document_id == doc.id).all()

    person_ids: Set[int] = set()
    account_ids: Set[int] = set()
    methods: Set[str] = set()
    primary_account_id: Optional[int] = None
    primary_person_id: Optional[int] = None
    primary_method: Optional[str] = None

    total_debit = Decimal(0)
    for line in lines:
        total_debit += line.debit or Decimal(0)
        if line.person_id:
            pid = int(line.person_id)
            person_ids.add(pid)
            if primary_person_id is None:
                primary_person_id = pid
        if line.account_id:
            aid = int(line.account_id)
            account_ids.add(aid)
            if primary_account_id is None and not line.person_id:
                primary_account_id = aid
        m = _infer_payment_method_from_line(line)
        if m:
            methods.add(m)
            if primary_method is None:
                primary_method = m

    if primary_account_id is None and account_ids:
        primary_account_id = next(iter(account_ids))

    amt = float(total_debit)
    out: Dict[str, Any] = {
        "amount": amt,
        "fiscal_year_id": int(doc.fiscal_year_id),
        "currency_id": int(doc.currency_id),
        "created_by_user_id": int(doc.created_by_user_id),
        "is_proforma": bool(doc.is_proforma),
        "description": doc.description or "",
        "account_ids": sorted(account_ids),
        "person_ids": sorted(person_ids),
        "payment_methods": sorted(methods),
    }

    if doc.project_id is not None:
        out["project_id"] = int(doc.project_id)

    if primary_person_id is not None:
        out["person_id"] = primary_person_id
    if primary_account_id is not None:
        out["account_id"] = primary_account_id
    if primary_method is not None:
        out["payment_method"] = primary_method

    return {k: v for k, v in out.items() if v is not None and v != "" and v != []}


def _classify_expense_income_item_lines(lines: List[DocumentLine]) -> List[int]:
    """سطرهای «اقلام» هزینه/درآمد: بدون transaction_type در extra_info طرف‌حساب."""
    item_accounts: List[int] = []
    for ln in lines:
        ex = ln.extra_info or {}
        if isinstance(ex, dict) and ex.get("transaction_type"):
            continue
        if ex.get("is_commission_line"):
            continue
        if ln.account_id:
            item_accounts.append(int(ln.account_id))
    return item_accounts


def build_document_trigger_enrichment(
    db: Session,
    business_id: int,
    document_id: int,
) -> Dict[str, Any]:
    doc = db.query(Document).filter(Document.id == int(document_id)).first()
    if not doc or int(doc.business_id) != int(business_id):
        return {}

    lines = db.query(DocumentLine).filter(DocumentLine.document_id == doc.id).all()

    total_debit = Decimal(0)
    person_ids: Set[int] = set()
    line_account_ids: Set[int] = set()

    for line in lines:
        total_debit += line.debit or Decimal(0)
        if line.person_id:
            person_ids.add(int(line.person_id))
        if line.account_id:
            line_account_ids.add(int(line.account_id))

    item_line_accounts = _classify_expense_income_item_lines(lines)
    if not item_line_accounts:
        item_line_accounts = [int(l.account_id) for l in lines if l.account_id]

    out: Dict[str, Any] = {
        "document_id": int(doc.id),
        "document_type": str(doc.document_type),
        "fiscal_year_id": int(doc.fiscal_year_id),
        "currency_id": int(doc.currency_id),
        "created_by_user_id": int(doc.created_by_user_id),
        "is_proforma": bool(doc.is_proforma),
        "description": doc.description or "",
        "total_amount": float(total_debit),
        "person_ids": sorted(person_ids),
        "line_account_ids": sorted(line_account_ids),
        "item_line_account_ids": sorted(set(item_line_accounts)),
    }

    if doc.project_id is not None:
        out["project_id"] = int(doc.project_id)

    if person_ids:
        out["person_id"] = min(person_ids)

    return {k: v for k, v in out.items() if v is not None and v != ""}
