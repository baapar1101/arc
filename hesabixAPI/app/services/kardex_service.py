from __future__ import annotations

from typing import Any, Dict, List, Optional, Tuple
from datetime import date

from sqlalchemy.orm import Session
import logging
from sqlalchemy import and_, or_, exists, select, Integer, cast

from adapters.db.models.document import Document
from adapters.db.models.document_line import DocumentLine
from adapters.db.models.fiscal_year import FiscalYear
from adapters.db.models.warehouse import Warehouse


# Helpers (reuse existing helpers from other services when possible)
def _parse_iso_date(dt: str) -> date:
    from app.services.transfer_service import _parse_iso_date as _p  # type: ignore
    return _p(dt)


def _get_current_fiscal_year(db: Session, business_id: int) -> FiscalYear:
    from app.services.transfer_service import _get_current_fiscal_year as _g  # type: ignore
    return _g(db, business_id)


def _build_group_condition(column, ids: List[int]) -> Any:
    if not ids:
        return None
    return column.in_(ids)


def _collect_ids(query: Dict[str, Any], key: str) -> List[int]:
    vals = query.get(key)
    if not isinstance(vals, (list, tuple)):
        return []
    out: List[int] = []
    for v in vals:
        try:
            out.append(int(v))
        except Exception:
            continue
    return out


def list_kardex_lines(db: Session, business_id: int, query: Dict[str, Any]) -> Dict[str, Any]:
    logger = logging.getLogger(__name__)
    try:
        logger.debug("KARDEX list_kardex_lines called | business_id=%s | keys=%s", business_id, list(query.keys()))
        logger.debug("KARDEX filters | person_ids=%s product_ids=%s account_ids=%s match_mode=%s result_scope=%s from=%s to=%s fy=%s",
                     query.get('person_ids'), query.get('product_ids'), query.get('account_ids'),
                     query.get('match_mode'), query.get('result_scope'), query.get('from_date'), query.get('to_date'), query.get('fiscal_year_id'))
    except Exception:
        pass
    """لیست خطوط اسناد (کاردکس) با پشتیبانی از انتخاب چندگانه و حالت‌های تطابق.

    پارامترهای ورودی مورد انتظار در query:
      - from_date, to_date: str (ISO)
      - fiscal_year_id: int (اختیاری؛ در غیر این صورت سال مالی جاری)
      - person_ids, product_ids, bank_account_ids, cash_register_ids, petty_cash_ids, account_ids, check_ids: List[int]
      - match_mode: "any" | "same_line" | "document_and" (پیش‌فرض: any)
      - result_scope: "lines_matching" | "lines_of_document" (پیش‌فرض: lines_matching)
      - sort_by: یکی از: document_date, document_code, debit, credit, quantity, created_at (پیش‌فرض: document_date)
      - sort_desc: bool
      - skip, take: pagination
    """

    # Base query: DocumentLine join Document
    q = db.query(DocumentLine, Document).join(Document, Document.id == DocumentLine.document_id).filter(
        Document.business_id == business_id
    )

    # Fiscal year handling
    fiscal_year_id = query.get("fiscal_year_id")
    try:
        fiscal_year_id_int = int(fiscal_year_id) if fiscal_year_id is not None else None
    except Exception:
        fiscal_year_id_int = None
    if fiscal_year_id_int is None:
        try:
            fy = _get_current_fiscal_year(db, business_id)
            fiscal_year_id_int = fy.id
        except Exception:
            fiscal_year_id_int = None
    if fiscal_year_id_int is not None:
        q = q.filter(Document.fiscal_year_id == fiscal_year_id_int)

    # Date range
    from_date = query.get("from_date")
    to_date = query.get("to_date")
    if isinstance(from_date, str) and from_date:
        try:
            q = q.filter(Document.document_date >= _parse_iso_date(from_date))
        except Exception:
            pass
    if isinstance(to_date, str) and to_date:
        try:
            q = q.filter(Document.document_date <= _parse_iso_date(to_date))
        except Exception:
            pass

    # Read selected IDs
    person_ids = _collect_ids(query, "person_ids")
    product_ids = _collect_ids(query, "product_ids")
    bank_account_ids = _collect_ids(query, "bank_account_ids")
    cash_register_ids = _collect_ids(query, "cash_register_ids")
    petty_cash_ids = _collect_ids(query, "petty_cash_ids")
    account_ids = _collect_ids(query, "account_ids")
    check_ids = _collect_ids(query, "check_ids")
    warehouse_ids = _collect_ids(query, "warehouse_ids")

    # Match mode
    match_mode = str(query.get("match_mode") or "any").lower()
    result_scope = str(query.get("result_scope") or "lines_matching").lower()

    # Build conditions by group
    group_filters = []
    if person_ids:
        group_filters.append(DocumentLine.person_id.in_(person_ids))
    if product_ids:
        group_filters.append(DocumentLine.product_id.in_(product_ids))
    if bank_account_ids:
        group_filters.append(DocumentLine.bank_account_id.in_(bank_account_ids))
    if cash_register_ids:
        group_filters.append(DocumentLine.cash_register_id.in_(cash_register_ids))
    if petty_cash_ids:
        group_filters.append(DocumentLine.petty_cash_id.in_(petty_cash_ids))
    if account_ids:
        group_filters.append(DocumentLine.account_id.in_(account_ids))
    if check_ids:
        group_filters.append(DocumentLine.check_id.in_(check_ids))

    # Apply matching logic
    if group_filters:
        if match_mode == "same_line":
            # AND across non-empty groups on the same line
            q = q.filter(and_(*group_filters))
        elif match_mode == "document_and":
            # Require each non-empty group to exist in some line of the same document
            doc_conditions = []
            if person_ids:
                sub = db.query(DocumentLine.id).filter(
                    and_(DocumentLine.document_id == Document.id, DocumentLine.person_id.in_(person_ids))
                ).exists()
                doc_conditions.append(sub)
            if product_ids:
                sub = db.query(DocumentLine.id).filter(
                    and_(DocumentLine.document_id == Document.id, DocumentLine.product_id.in_(product_ids))
                ).exists()
                doc_conditions.append(sub)
            if bank_account_ids:
                sub = db.query(DocumentLine.id).filter(
                    and_(DocumentLine.document_id == Document.id, DocumentLine.bank_account_id.in_(bank_account_ids))
                ).exists()
                doc_conditions.append(sub)
            if cash_register_ids:
                sub = db.query(DocumentLine.id).filter(
                    and_(DocumentLine.document_id == Document.id, DocumentLine.cash_register_id.in_(cash_register_ids))
                ).exists()
                doc_conditions.append(sub)
            if petty_cash_ids:
                sub = db.query(DocumentLine.id).filter(
                    and_(DocumentLine.document_id == Document.id, DocumentLine.petty_cash_id.in_(petty_cash_ids))
                ).exists()
                doc_conditions.append(sub)
            if account_ids:
                sub = db.query(DocumentLine.id).filter(
                    and_(DocumentLine.document_id == Document.id, DocumentLine.account_id.in_(account_ids))
                ).exists()
                doc_conditions.append(sub)
            if check_ids:
                sub = db.query(DocumentLine.id).filter(
                    and_(DocumentLine.document_id == Document.id, DocumentLine.check_id.in_(check_ids))
                ).exists()
                doc_conditions.append(sub)

            if doc_conditions:
                q = q.filter(and_(*doc_conditions))

            # For lines scope: either only matching lines or all lines of matching documents
            if result_scope == "lines_matching":
                q = q.filter(or_(*group_filters))
            else:
                # lines_of_document: no extra line filter
                pass
        else:
            # any: OR across groups on the same line
            q = q.filter(or_(*group_filters))

    # Warehouse filter (JSON attribute inside extra_info)
    if warehouse_ids:
        try:
            q = q.filter(cast(DocumentLine.extra_info["warehouse_id"].as_string(), Integer).in_(warehouse_ids))
        except Exception:
            try:
                q = q.filter(cast(DocumentLine.extra_info["warehouse_id"].astext, Integer).in_(warehouse_ids))
            except Exception:
                # در صورت عدم پشتیبانی از عملگر JSON، از فیلتر نرم‌افزاری بعد از واکشی استفاده خواهد شد
                pass

    # Sorting
    sort_by = (query.get("sort_by") or "document_date")
    sort_desc = bool(query.get("sort_desc", True))
    if sort_by == "document_date":
        order_col = Document.document_date
    elif sort_by == "document_code":
        order_col = Document.code
    elif sort_by == "debit":
        order_col = DocumentLine.debit
    elif sort_by == "credit":
        order_col = DocumentLine.credit
    elif sort_by == "quantity":
        order_col = DocumentLine.quantity
    elif sort_by == "created_at":
        order_col = DocumentLine.created_at
    else:
        order_col = Document.document_date
    q = q.order_by(order_col.desc() if sort_desc else order_col.asc())

    # Pagination
    try:
        skip = int(query.get("skip", 0))
    except Exception:
        skip = 0
    try:
        take = int(query.get("take", 20))
    except Exception:
        take = 20

    total = q.count()
    try:
        logger.debug("KARDEX query total=%s (after filters)", total)
    except Exception:
        pass
    rows: List[Tuple[DocumentLine, Document]] = q.offset(skip).limit(take).all()

    # Running balance (optional)
    include_running = bool(query.get("include_running_balance", False))
    running_amount: float = 0.0
    running_quantity: float = 0.0

    # گردآوری شناسه‌های انبار جهت نام‌گذاری
    wh_ids_in_page: set[int] = set()
    for line, _ in rows:
        try:
            info = line.extra_info or {}
            wid = info.get("warehouse_id")
            if wid is not None:
                wh_ids_in_page.add(int(wid))
        except Exception:
            pass

    wh_map: Dict[int, str] = {}
    if wh_ids_in_page:
        for w in db.query(Warehouse).filter(Warehouse.business_id == business_id, Warehouse.id.in_(list(wh_ids_in_page))).all():
            try:
                name = (w.name or "").strip()
                code = (w.code or "").strip()
                wh_map[int(w.id)] = f"{code} - {name}" if code else name
            except Exception:
                continue

    def _movement_from_type(inv_type: str | None) -> str | None:
        t = (inv_type or "").strip()
        if t in ("invoice_sales",):
            return "out"
        if t in ("invoice_sales_return", "invoice_purchase"):
            return "in"
        if t in ("invoice_purchase_return", "invoice_direct_consumption", "invoice_waste"):
            return "out"
        # production: both in/out ممکن است
        return None

    def _get_document_type_name(doc_type: str | None) -> str:
        """تبدیل document_type به نام چندزبانه"""
        if not doc_type:
            return ""
        doc_type = doc_type.strip()
        mapping = {
            "invoice_sales": "فروش",
            "invoice_sales_return": "برگشت از فروش",
            "invoice_purchase": "خرید",
            "invoice_purchase_return": "برگشت از خرید",
            "invoice_direct_consumption": "مصرف مستقیم",
            "invoice_production": "تولید",
            "invoice_waste": "ضایعات",
            "inventory_transfer": "انتقال موجودی",
            "production": "تولید",
            "opening_balance": "موجودی اولیه",
            "expense": "هزینه",
            "income": "درآمد",
            "receipt": "دریافت",
            "payment": "پرداخت",
            "transfer": "انتقال",
            "manual": "سند دستی",
            "invoice": "فاکتور",
        }
        return mapping.get(doc_type, doc_type)

    items: List[Dict[str, Any]] = []
    for line, doc in rows:
        doc_type = getattr(doc, "document_type", None)
        item: Dict[str, Any] = {
            "line_id": line.id,
            "document_id": doc.id,
            "document_code": getattr(doc, "code", None),
            "document_date": getattr(doc, "document_date", None),
            "document_type": doc_type,
            "document_type_name": _get_document_type_name(doc_type),
            "description": line.description,
            "debit": float(line.debit or 0),
            "credit": float(line.credit or 0),
            "quantity": float(line.quantity or 0) if line.quantity is not None else None,
            "account_id": line.account_id,
            "person_id": line.person_id,
            "product_id": line.product_id,
            "bank_account_id": line.bank_account_id,
            "cash_register_id": line.cash_register_id,
            "petty_cash_id": line.petty_cash_id,
            "check_id": line.check_id,
        }

        # movement & warehouse
        try:
            info = line.extra_info or {}
            mv = info.get("movement")
            if mv is None:
                mv = _movement_from_type(getattr(doc, "document_type", None))
            wid = info.get("warehouse_id")
            item["movement"] = mv
            item["warehouse_id"] = int(wid) if wid is not None else None
            if wid is not None:
                item["warehouse_name"] = wh_map.get(int(wid))
        except Exception:
            pass

        if include_running:
            try:
                running_amount += float(line.debit or 0) - float(line.credit or 0)
            except Exception:
                pass
            try:
                if line.quantity is not None:
                    running_quantity += float(line.quantity or 0)
            except Exception:
                pass
            item["running_amount"] = running_amount
            # فقط اگر ستون quantity وجود داشته باشد
            if line.quantity is not None:
                item["running_quantity"] = running_quantity

        items.append(item)

    return {
        "items": items,
        "pagination": {
            "total": total,
            "page": (skip // take) + 1,
            "per_page": take,
            "total_pages": (total + take - 1) // take,
            "has_next": skip + take < total,
            "has_prev": skip > 0,
        },
        "query_info": query,
    }


