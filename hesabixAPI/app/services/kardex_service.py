from __future__ import annotations

from typing import Any, Dict, List, Optional, Tuple
from datetime import date, datetime, time, timezone
from decimal import Decimal, ROUND_HALF_UP
from bisect import bisect_right

from sqlalchemy.orm import Session
import logging
from sqlalchemy import and_, or_, exists, select, Integer, cast

from adapters.db.models.document import Document
from adapters.db.models.document_line import DocumentLine
from adapters.db.models.business import Business
from adapters.db.models.business_currency_rate import BusinessCurrencyRate
from adapters.db.models.currency import BusinessCurrency, Currency
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


KARDEX_SORT_ALLOWED = frozenset(
    {"document_date", "document_code", "debit", "credit", "debit_base", "credit_base", "quantity", "created_at"}
)


def _kardex_sort_column(sort_key: str):
    if sort_key == "document_code":
        return Document.code
    if sort_key == "debit":
        return DocumentLine.debit
    if sort_key == "credit":
        return DocumentLine.credit
    if sort_key == "debit_base":
        return DocumentLine.debit_base
    if sort_key == "credit_base":
        return DocumentLine.credit_base
    if sort_key == "quantity":
        return DocumentLine.quantity
    if sort_key == "created_at":
        return DocumentLine.created_at
    return Document.document_date


def _apply_kardex_sort(q, query: Dict[str, Any]):
    from app.services.sort_resolution import effective_sort_specs, query_info_for_sort

    qi = query_info_for_sort(query, default_sort_desc=True)
    specs = effective_sort_specs(qi, allowed=KARDEX_SORT_ALLOWED, default_when_empty=("document_date", True))
    parts = []
    for name, desc in specs:
        col = _kardex_sort_column(name)
        parts.append(col.desc() if desc else col.asc())
    if not parts:
        parts.append(Document.document_date.desc())
    return q.order_by(*parts)


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
      - currency_id: اختیاری؛ واحد نمایش مبالغ، در غیر این صورت ارز پایه (همهٔ اسناد نمایش داده می‌شوند)
      - sort_by: یکی از: document_date, document_code, debit, credit, debit_base, credit_base, quantity, created_at
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

    # ارز انتخاب‌شده در کاردکس، واحد نمایش است؛ همهٔ ارزهای سند باید باقی بمانند.
    currency_id = query.get("currency_id")
    try:
        currency_id_int = int(currency_id) if currency_id is not None else None
    except Exception:
        currency_id_int = None
    amounts_in_base = currency_id_int is None
    business = db.get(Business, int(business_id))
    base_currency_id = int(business.default_currency_id) if business and business.default_currency_id else None
    multi_currency = False
    if base_currency_id is not None:
        try:
            multi_currency = db.query(BusinessCurrency.id).filter(
                BusinessCurrency.business_id == int(business_id),
                BusinessCurrency.currency_id != base_currency_id,
            ).first() is not None
        except Exception:
            multi_currency = False
    if currency_id_int is not None and currency_id_int != base_currency_id:
        allowed = db.query(BusinessCurrency.id).filter(
            BusinessCurrency.business_id == int(business_id),
            BusinessCurrency.currency_id == currency_id_int,
        ).first()
        if allowed is None:
            currency_id_int = None
            amounts_in_base = True

    target_currency = db.get(Currency, currency_id_int) if currency_id_int is not None else None
    base_currency = db.get(Currency, base_currency_id) if base_currency_id is not None else None
    target_quant, target_round = (Decimal("1"), True)
    if currency_id_int is not None:
        try:
            from app.services.currency_quant import get_currency_quant_and_round
            target_quant, target_round = get_currency_quant_and_round(db, currency_id_int)
        except Exception:
            pass

    # Preload target currency rate history once. Each document uses the effective
    # rate at its own FX valuation timestamp, matching the source document rate.
    target_rates: List[Tuple[datetime, int, Decimal]] = []
    target_rate_keys: List[Tuple[datetime, int]] = []
    if currency_id_int is not None and currency_id_int != base_currency_id:
        for rate_row in db.query(BusinessCurrencyRate).filter(
            BusinessCurrencyRate.business_id == int(business_id),
            BusinessCurrencyRate.currency_id == currency_id_int,
        ).order_by(BusinessCurrencyRate.effective_at.asc(), BusinessCurrencyRate.id.asc()).all():
            eff = rate_row.effective_at
            if eff.tzinfo is None:
                eff = eff.replace(tzinfo=timezone.utc)
            else:
                eff = eff.astimezone(timezone.utc)
            target_rates.append((eff, int(rate_row.id), Decimal(str(rate_row.rate))))
            target_rate_keys.append((eff, int(rate_row.id)))

    valuation_time_cache: Dict[int, datetime] = {}
    source_rate_cache: Dict[int, Optional[Decimal]] = {}

    def _document_fx_valuation_time(doc: Document) -> datetime:
        cached = valuation_time_cache.get(int(doc.id))
        if cached is not None:
            return cached
        registered_at = getattr(doc, "registered_at", None) or datetime.now(timezone.utc)
        if registered_at.tzinfo is None:
            registered_at = registered_at.replace(tzinfo=timezone.utc)
        else:
            registered_at = registered_at.astimezone(timezone.utc)
        try:
            from app.services.invoice_fx_revaluation import compute_fx_as_of_utc, get_fx_revaluation_policy
            policy = get_fx_revaluation_policy(business) if business is not None else None
            as_of = compute_fx_as_of_utc(doc.document_date, registered_at, policy)
            if as_of.tzinfo is None:
                as_of = as_of.replace(tzinfo=timezone.utc)
            else:
                as_of = as_of.astimezone(timezone.utc)
        except Exception:
            as_of = datetime.combine(doc.document_date, time(23, 59, 59, 999999), tzinfo=timezone.utc)
        valuation_time_cache[int(doc.id)] = as_of
        return as_of

    def _target_rate_for_document(doc: Document) -> Optional[Decimal]:
        if currency_id_int is None or currency_id_int == base_currency_id:
            return Decimal(1)
        if not target_rates:
            return None
        as_of = _document_fx_valuation_time(doc)
        idx = bisect_right(target_rate_keys, (as_of, 2**63 - 1)) - 1
        if idx >= 0:
            return target_rates[idx][2]
        # Legacy source-rate resolution also permits the last rate on the
        # document date when the policy timestamp has no matching rate.
        day_end = datetime.combine(doc.document_date, time(23, 59, 59, 999999), tzinfo=timezone.utc)
        idx = bisect_right(target_rate_keys, (day_end, 2**63 - 1)) - 1
        return target_rates[idx][2] if idx >= 0 else None

    def _base_amounts(line: DocumentLine, doc: Document) -> Tuple[Optional[Decimal], Optional[Decimal]]:
        doc_currency_id = int(getattr(doc, "currency_id", 0) or 0)
        rate: Optional[Decimal]
        if doc_currency_id == base_currency_id:
            rate = Decimal(1)
        elif getattr(line, "exchange_rate", None) is not None and Decimal(str(line.exchange_rate)) > 0:
            rate = Decimal(str(line.exchange_rate))
        else:
            rate = source_rate_cache.get(int(doc.id))
            if int(doc.id) not in source_rate_cache:
                try:
                    from app.services.document_line_fx_service import resolve_document_fx_rate
                    rate, _source = resolve_document_fx_rate(
                        db, doc, business=business, allow_infer=True, fallback_one_on_missing=False
                    )
                except Exception:
                    rate = None
                source_rate_cache[int(doc.id)] = rate

        def side_amount(native: Any, stored_base: Any) -> Optional[Decimal]:
            if stored_base is not None:
                return Decimal(str(stored_base))
            native_amount = Decimal(str(native or 0))
            if native_amount == 0:
                return Decimal(0)
            if rate is None:
                return None
            return native_amount * rate

        return side_amount(line.debit, getattr(line, "debit_base", None)), side_amount(
            line.credit, getattr(line, "credit_base", None)
        )

    def _display_amount(base_amount: Optional[Decimal], doc: Document) -> Optional[Decimal]:
        if base_amount is None:
            return None
        rate = _target_rate_for_document(doc)
        if rate is None or rate <= 0:
            return None
        amount = base_amount / rate
        if target_round:
            amount = amount.quantize(target_quant, rounding=ROUND_HALF_UP)
        return amount

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
    # برای PostgreSQL از astext استفاده می‌کنیم
    if warehouse_ids:
        try:
            q = q.filter(cast(DocumentLine.extra_info["warehouse_id"].astext, Integer).in_(warehouse_ids))
        except Exception:
            # در صورت عدم پشتیبانی از عملگر JSON، از فیلتر نرم‌افزاری بعد از واکشی استفاده خواهد شد
            pass

    # Sorting (چندستونه / تک‌ستونه)
    q = _apply_kardex_sort(q, query)

    # Pagination
    try:
        skip = max(int(query.get("skip", 0)), 0)
    except Exception:
        skip = 0
    try:
        take = max(int(query.get("take", 20)), 1)
    except Exception:
        take = 20

    total = q.count()
    needs_base_recovery = False
    if base_currency_id is not None:
        try:
            needs_base_recovery = q.filter(
                Document.currency_id != base_currency_id,
                or_(DocumentLine.debit_base.is_(None), DocumentLine.credit_base.is_(None)),
            ).first() is not None
        except Exception:
            needs_base_recovery = False

    # Totals cover every matched row, not only the current page.
    totals = {
        "debit": Decimal(0),
        "credit": Decimal(0),
        "debit_base": Decimal(0),
        "credit_base": Decimal(0),
        "quantity": None,
        "conversion_missing_count": 0 if currency_id_int is not None else None,
    }
    try:
        logger.debug("KARDEX query total=%s (after filters)", total)
    except Exception:
        pass

    def _line_amounts(line: DocumentLine, doc: Document) -> Tuple[Optional[float], Optional[float], Optional[float], Optional[float]]:
        debit_base, credit_base = _base_amounts(line, doc)
        if currency_id_int is None:
            debit, credit = debit_base, credit_base
        elif int(getattr(doc, "currency_id", 0) or 0) == currency_id_int:
            # Preserve exact native amounts when a row already uses the display currency.
            debit, credit = Decimal(str(line.debit or 0)), Decimal(str(line.credit or 0))
        else:
            debit, credit = _display_amount(debit_base, doc), _display_amount(credit_base, doc)
        return (
            float(debit) if debit is not None else None,
            float(credit) if credit is not None else None,
            float(debit_base) if debit_base is not None else None,
            float(credit_base) if credit_base is not None else None,
        )

    def _sort_rows_in_display_currency(rows_to_sort: List[Tuple[DocumentLine, Document]]) -> None:
        from functools import cmp_to_key
        from app.services.sort_resolution import effective_sort_specs, query_info_for_sort

        specs = effective_sort_specs(
            query_info_for_sort(query, default_sort_desc=True),
            allowed=KARDEX_SORT_ALLOWED,
            default_when_empty=("document_date", True),
        )

        def sort_value(line: DocumentLine, doc: Document, name: str):
            if name == "document_date":
                return doc.document_date
            if name == "document_code":
                return doc.code
            if name == "debit":
                return _line_amounts(line, doc)[0]
            if name == "credit":
                return _line_amounts(line, doc)[1]
            if name == "debit_base":
                return _line_amounts(line, doc)[2]
            if name == "credit_base":
                return _line_amounts(line, doc)[3]
            if name == "quantity":
                return line.quantity
            return line.created_at

        def compare(left: Tuple[DocumentLine, Document], right: Tuple[DocumentLine, Document]) -> int:
            for name, descending in specs:
                a = sort_value(left[0], left[1], name)
                b = sort_value(right[0], right[1], name)
                if a is None and b is None:
                    continue
                if a is None:
                    return 1
                if b is None:
                    return -1
                if a == b:
                    continue
                result = -1 if a < b else 1
                return -result if descending else result
            return (int(left[0].id) > int(right[0].id)) - (int(left[0].id) < int(right[0].id))

        rows_to_sort.sort(key=cmp_to_key(compare))

    include_running = bool(query.get("include_running_balance", False))
    running_amount: float = 0.0
    running_quantity: float = 0.0
    running_is_complete = True
    displayed_by_line_id: Dict[int, Tuple[Optional[float], Optional[float], Optional[float], Optional[float]]] = {}

    if currency_id_int is not None or needs_base_recovery:
        # Historical conversion and totals require the same per-document rates.
        all_rows: List[Tuple[DocumentLine, Document]] = q.all()
        _sort_rows_in_display_currency(all_rows)
        rows = all_rows[skip : skip + take]
        for line, doc in all_rows:
            values = _line_amounts(line, doc)
            displayed_by_line_id[int(line.id)] = values
            debit, credit, debit_base, credit_base = values
            if debit is not None:
                totals["debit"] += Decimal(str(debit))
            if credit is not None:
                totals["credit"] += Decimal(str(credit))
            if debit_base is not None:
                totals["debit_base"] += Decimal(str(debit_base))
            if credit_base is not None:
                totals["credit_base"] += Decimal(str(credit_base))
            if debit is None or credit is None or debit_base is None or credit_base is None:
                totals["conversion_missing_count"] = (totals["conversion_missing_count"] or 0) + 1
            if line.quantity is not None:
                totals["quantity"] = (totals["quantity"] or 0.0) + float(line.quantity or 0)
        if include_running:
            for line, _doc in all_rows[:skip]:
                debit, credit, _debit_base, _credit_base = displayed_by_line_id[int(line.id)]
                if debit is None or credit is None:
                    running_is_complete = False
                elif running_is_complete:
                    running_amount += debit - credit
                if line.quantity is not None:
                    running_quantity += float(line.quantity or 0)
    else:
        # Preserve the efficient aggregate path for the default base-currency view.
        from sqlalchemy import func
        try:
            sum_q = q.order_by(None).with_entities(
                func.coalesce(func.sum(func.coalesce(DocumentLine.debit_base, DocumentLine.debit)), 0),
                func.coalesce(func.sum(func.coalesce(DocumentLine.credit_base, DocumentLine.credit)), 0),
                func.sum(DocumentLine.quantity),
            ).one()
            totals["debit"] = Decimal(str(sum_q[0] or 0))
            totals["credit"] = Decimal(str(sum_q[1] or 0))
            totals["debit_base"] = totals["debit"]
            totals["credit_base"] = totals["credit"]
            totals["quantity"] = float(sum_q[2]) if sum_q[2] is not None else None
        except Exception:
            pass
        if include_running and skip > 0:
            window: List[Tuple[DocumentLine, Document]] = q.limit(skip + take).all()
            for line, doc in window[:skip]:
                debit, credit, _debit_base, _credit_base = _line_amounts(line, doc)
                if debit is None or credit is None:
                    running_is_complete = False
                elif running_is_complete:
                    running_amount += debit - credit
                if line.quantity is not None:
                    running_quantity += float(line.quantity or 0)
            rows = window[skip:]
        else:
            rows = q.offset(skip).limit(take).all()

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

    check_ids_in_page: set[int] = set()
    for line, _ in rows:
        if line.check_id is not None:
            try:
                check_ids_in_page.add(int(line.check_id))
            except Exception:
                pass
    check_number_map: Dict[int, str] = {}
    if check_ids_in_page:
        from adapters.db.models.check import Check

        for ch in db.query(Check).filter(
            Check.business_id == business_id,
            Check.id.in_(list(check_ids_in_page)),
        ).all():
            try:
                check_number_map[int(ch.id)] = str(ch.check_number or "")
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
            "check": "چک",
        }
        return mapping.get(doc_type, doc_type)

    items: List[Dict[str, Any]] = []
    for line, doc in rows:
        doc_type = getattr(doc, "document_type", None)
        debit_native = float(line.debit or 0)
        credit_native = float(line.credit or 0)
        amounts = displayed_by_line_id.get(int(line.id))
        if amounts is None:
            amounts = _line_amounts(line, doc)
        debit, credit, debit_base, credit_base = amounts
        item: Dict[str, Any] = {
            "line_id": line.id,
            "document_id": doc.id,
            "document_code": getattr(doc, "code", None),
            "document_date": getattr(doc, "document_date", None),
            "document_type": doc_type,
            "document_type_name": _get_document_type_name(doc_type),
            "description": line.description,
            "debit": debit,
            "credit": credit,
            "debit_base": debit_base,
            "credit_base": credit_base,
            "debit_native": debit_native,
            "credit_native": credit_native,
            "document_currency_id": getattr(doc, "currency_id", None),
            "exchange_rate": float(line.exchange_rate) if getattr(line, "exchange_rate", None) is not None else None,
            "amounts_in_base": amounts_in_base,
            "display_currency_id": currency_id_int or base_currency_id,
            "display_currency_code": getattr(target_currency or base_currency, "code", None),
            "display_currency_decimal_places": getattr(target_currency or base_currency, "decimal_places", 2),
            "base_currency_id": base_currency_id,
            "base_currency_code": getattr(base_currency, "code", None),
            "base_currency_decimal_places": getattr(base_currency, "decimal_places", 2),
            "currency_conversion_missing": debit is None or credit is None,
            "base_conversion_missing": debit_base is None or credit_base is None,
            "quantity": float(line.quantity or 0) if line.quantity is not None else None,
            "account_id": line.account_id,
            "person_id": line.person_id,
            "product_id": line.product_id,
            "bank_account_id": line.bank_account_id,
            "cash_register_id": line.cash_register_id,
            "petty_cash_id": line.petty_cash_id,
            "check_id": line.check_id,
        }
        if line.check_id is not None:
            try:
                cn = check_number_map.get(int(line.check_id))
                if cn:
                    item["check_number"] = cn
            except Exception:
                pass

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
            if debit is None or credit is None:
                running_is_complete = False
            elif running_is_complete:
                running_amount += debit - credit
            try:
                if line.quantity is not None:
                    running_quantity += float(line.quantity or 0)
            except Exception:
                pass
            item["running_amount"] = running_amount if running_is_complete else None
            # فقط اگر ستون quantity وجود داشته باشد
            if line.quantity is not None:
                item["running_quantity"] = running_quantity

        items.append(item)

    for total_key in ("debit", "credit", "debit_base", "credit_base"):
        totals[total_key] = float(totals[total_key])

    return {
        "items": items,
        "totals": totals,
        "pagination": {
            "total": total,
            "page": (skip // take) + 1,
            "per_page": take,
            "total_pages": (total + take - 1) // take,
            "has_next": skip + take < total,
            "has_prev": skip > 0,
        },
        "query_info": query,
        "meta": {
            "currency_id": currency_id_int,
            "amounts_in_base": amounts_in_base,
            "display_currency_id": currency_id_int or base_currency_id,
            "display_currency_code": getattr(target_currency or base_currency, "code", None),
            "display_currency_decimal_places": getattr(target_currency or base_currency, "decimal_places", 2),
            "base_currency_id": base_currency_id,
            "base_currency_code": getattr(base_currency, "code", None),
            "base_currency_decimal_places": getattr(base_currency, "decimal_places", 2),
            "multi_currency": multi_currency,
        },
    }


