from __future__ import annotations

from datetime import date, timedelta
from decimal import Decimal
from typing import Any, Dict, List, Optional, Tuple

from sqlalchemy import and_
from sqlalchemy.orm import Session

from adapters.db.models.account import Account
from adapters.db.models.document import Document
from adapters.db.models.document_line import DocumentLine
from adapters.db.models.fiscal_year import FiscalYear
from app.services.opening_balance_service import _ensure_fiscal_year
from app.services.pnl_account_classification import (
    is_pnl_cogs_account,
    is_pnl_expense_gl_account,
    is_pnl_non_operating_expense_account,
    is_pnl_non_operating_income_account,
    is_pnl_operating_expense_account,
    is_pnl_operating_other_income_account,
    is_pnl_revenue_gl_account,
    is_pnl_sales_account,
    is_pnl_tax_expense_account,
)

PNL_SECTION_LABELS_FA = {
    "sales": "فروش و درآمد عملیاتی",
    "other_income": "درآمدهای عملیاتی (گروه ۶۰۱)",
    "non_operating_income": "درآمدهای غیرعملیاتی",
    "cogs": "بهای تمام‌شده کالای فروش‌رفته",
    "operating_expense": "هزینه‌های عملیاتی",
    "non_operating_expense": "هزینه‌های غیرعملیاتی",
    "tax_expense": "مالیات بر درآمد",
}

PNL_SECTION_LABELS_EN = {
    "sales": "Sales & Operating Revenue",
    "other_income": "Operating Other Income",
    "non_operating_income": "Non-Operating Income",
    "cogs": "Cost of Goods Sold",
    "operating_expense": "Operating Expenses",
    "non_operating_expense": "Non-Operating Expenses",
    "tax_expense": "Income Tax Expense",
}

SUMMARY_COMPARE_KEYS = (
    "total_sales",
    "total_other_income",
    "total_revenue",
    "total_cogs",
    "gross_profit",
    "total_operating_expense",
    "operating_profit",
    "total_non_operating_income",
    "total_non_operating_expense",
    "profit_before_tax",
    "total_tax_expense",
    "net_profit_after_tax",
    "net_profit_loss",
)

COMPARE_MODES = frozenset({"prior_period", "prior_year"})


def _parse_iso_date(dt: str | date) -> date:
    if isinstance(dt, date):
        return dt
    if isinstance(dt, str):
        return date.fromisoformat(dt.split("T")[0])
    raise ValueError(f"Invalid date format: {dt}")


def _turnover_by_account_in_base_currency(
    db: Session,
    business_id: int,
    account_ids: List[int],
    date_from_obj: date,
    date_to_obj: date,
    currency_id: Optional[int],
    project_id: Optional[int],
    fiscal_year_id: Optional[int] = None,
) -> Dict[int, Dict[str, Decimal]]:
    from app.services.person_service import _person_line_amount_to_base

    q = (
        db.query(DocumentLine, Document)
        .join(Document, DocumentLine.document_id == Document.id)
        .filter(
            and_(
                Document.business_id == business_id,
                Document.is_proforma == False,  # noqa: E712
                DocumentLine.account_id.isnot(None),
                DocumentLine.account_id.in_(account_ids),
                Document.document_date >= date_from_obj,
                Document.document_date <= date_to_obj,
            )
        )
    )
    if project_id:
        q = q.filter(Document.project_id == project_id)
    if currency_id:
        q = q.filter(Document.currency_id == currency_id)
    if fiscal_year_id:
        q = q.filter(Document.fiscal_year_id == fiscal_year_id)

    rows = q.all()
    rate_cache: Dict[int, Decimal] = {}
    base_currency_by_business: Dict[int, Optional[int]] = {}
    turnover_by_account: Dict[int, Dict[str, Decimal]] = {}

    for line, doc in rows:
        aid = line.account_id
        if aid is None:
            continue
        if aid not in turnover_by_account:
            turnover_by_account[aid] = {"debit": Decimal(0), "credit": Decimal(0)}
        turnover_by_account[aid]["debit"] += _person_line_amount_to_base(
            db,
            doc,
            line.debit,
            rate_cache=rate_cache,
            base_currency_by_business=base_currency_by_business,
            line=line,
            side="debit",
        )
        turnover_by_account[aid]["credit"] += _person_line_amount_to_base(
            db,
            doc,
            line.credit,
            rate_cache=rate_cache,
            base_currency_by_business=base_currency_by_business,
            line=line,
            side="credit",
        )
    return turnover_by_account


def _has_nonzero_turnover(turnover: Dict[str, Decimal]) -> bool:
    return turnover["debit"] != Decimal(0) or turnover["credit"] != Decimal(0)


def _account_item(account: Account, turnover: Dict[str, Decimal], section: str) -> Dict[str, Any]:
    if section in ("sales", "other_income", "non_operating_income"):
        net = turnover["credit"] - turnover["debit"]
        return {
            "account_id": account.id,
            "account_code": account.code,
            "account_name": account.name,
            "account_type": account.account_type,
            "section": section,
            "debit": float(turnover["debit"]),
            "credit": float(turnover["credit"]),
            "amount": float(net),
            "revenue": float(net),
            "expense": 0.0,
        }
    net = turnover["debit"] - turnover["credit"]
    return {
        "account_id": account.id,
        "account_code": account.code,
        "account_name": account.name,
        "account_type": account.account_type,
        "section": section,
        "debit": float(turnover["debit"]),
        "credit": float(turnover["credit"]),
        "amount": float(net),
        "revenue": 0.0,
        "expense": float(net),
    }


def _sum_section_amount(items: List[Dict[str, Any]], amount_key: str = "amount") -> Decimal:
    return sum(Decimal(str(item.get(amount_key, 0) or 0)) for item in items)


def _variance_pct(current: float, prior: float) -> Optional[float]:
    if prior == 0:
        return None
    return round((current - prior) / abs(prior) * 100, 2)


def _build_statement_lines(
    sales_items: List[Dict[str, Any]],
    other_income_items: List[Dict[str, Any]],
    cogs_items: List[Dict[str, Any]],
    operating_items: List[Dict[str, Any]],
    tax_items: List[Dict[str, Any]],
    summary: Dict[str, float],
    prior_summary: Optional[Dict[str, float]] = None,
    non_operating_income_items: Optional[List[Dict[str, Any]]] = None,
    non_operating_expense_items: Optional[List[Dict[str, Any]]] = None,
) -> List[Dict[str, Any]]:
    non_operating_income_items = non_operating_income_items or []
    non_operating_expense_items = non_operating_expense_items or []
    lines: List[Dict[str, Any]] = []

    def _line_amount(key: str, default: float = 0.0) -> float:
        return float(summary.get(key, default))

    def _prior_amount(key: str) -> Optional[float]:
        if prior_summary is None:
            return None
        return float(prior_summary.get(key, 0.0))

    def _attach_comparison(line: Dict[str, Any], summary_key: Optional[str] = None) -> Dict[str, Any]:
        if prior_summary is None:
            return line
        if line.get("type") == "account":
            code = line.get("account_code")
            # prior lookup done externally via merged lines
            return line
        if summary_key:
            cur = _line_amount(summary_key)
            pri = _prior_amount(summary_key) or 0.0
            line["prior_amount"] = pri
            line["variance"] = round(cur - pri, 2)
            pct = _variance_pct(cur, pri)
            if pct is not None:
                line["variance_pct"] = pct
        return line

    def add_section(
        key: str,
        items: List[Dict[str, Any]],
        subtotal_label_fa: str,
        subtotal_label_en: str,
        subtotal_key: str,
    ) -> None:
        if not items:
            return
        lines.append({
            "type": "section_header",
            "section": key,
            "label_fa": PNL_SECTION_LABELS_FA[key],
            "label_en": PNL_SECTION_LABELS_EN[key],
        })
        for item in items:
            row = {
                "type": "account",
                "section": key,
                "account_id": item.get("account_id"),
                "account_code": item["account_code"],
                "account_name": item["account_name"],
                "account_type": item.get("account_type", "accounting_document"),
                "amount": item["amount"],
            }
            if prior_summary and item.get("prior_amount") is not None:
                row["prior_amount"] = item["prior_amount"]
                row["variance"] = item.get("variance")
                row["variance_pct"] = item.get("variance_pct")
            lines.append(row)
        lines.append(_attach_comparison({
            "type": "subtotal",
            "section": key,
            "label_fa": subtotal_label_fa,
            "label_en": subtotal_label_en,
            "amount": summary.get(subtotal_key, 0.0),
        }, subtotal_key))

    add_section("sales", sales_items, "جمع فروش", "Total Sales", "total_sales")
    add_section("other_income", other_income_items, "جمع سایر درآمدها", "Total Other Income", "total_other_income")

    if sales_items or other_income_items:
        lines.append(_attach_comparison({
            "type": "subtotal",
            "section": "revenue_total",
            "label_fa": "جمع درآمد",
            "label_en": "Total Revenue",
            "amount": summary.get("total_revenue", 0.0),
            "highlight": True,
        }, "total_revenue"))

    add_section("cogs", cogs_items, "جمع بهای تمام‌شده", "Total COGS", "total_cogs")

    if cogs_items and (sales_items or other_income_items):
        lines.append(_attach_comparison({
            "type": "subtotal",
            "section": "gross_profit",
            "label_fa": "سود ناخالص",
            "label_en": "Gross Profit",
            "amount": summary.get("gross_profit", 0.0),
            "highlight": True,
        }, "gross_profit"))

    add_section(
        "operating_expense",
        operating_items,
        "جمع هزینه‌های عملیاتی",
        "Total Operating Expenses",
        "total_operating_expense",
    )

    if operating_items or sales_items or other_income_items or cogs_items:
        lines.append(_attach_comparison({
            "type": "subtotal",
            "section": "operating_profit",
            "label_fa": "سود عملیاتی",
            "label_en": "Operating Profit",
            "amount": summary.get("operating_profit", 0.0),
            "highlight": True,
        }, "operating_profit"))

    add_section(
        "non_operating_income",
        non_operating_income_items,
        "جمع درآمدهای غیرعملیاتی",
        "Total Non-Operating Income",
        "total_non_operating_income",
    )
    add_section(
        "non_operating_expense",
        non_operating_expense_items,
        "جمع هزینه‌های غیرعملیاتی",
        "Total Non-Operating Expenses",
        "total_non_operating_expense",
    )

    lines.append(_attach_comparison({
        "type": "subtotal",
        "section": "profit_before_tax",
        "label_fa": "سود قبل از مالیات",
        "label_en": "Profit Before Tax",
        "amount": summary.get("profit_before_tax", 0.0),
        "highlight": True,
    }, "profit_before_tax"))

    add_section(
        "tax_expense",
        tax_items,
        "جمع مالیات بر درآمد",
        "Total Income Tax",
        "total_tax_expense",
    )

    lines.append(_attach_comparison({
        "type": "grand_total",
        "section": "net",
        "label_fa": "سود/زیان خالص پس از مالیات",
        "label_en": "Net Profit / Loss After Tax",
        "amount": summary.get("net_profit_after_tax", summary.get("net_profit_loss", 0.0)),
        "highlight": True,
    }, "net_profit_after_tax"))

    return lines


def _merge_item_comparison(
    current_items: List[Dict[str, Any]],
    prior_items: List[Dict[str, Any]],
) -> List[Dict[str, Any]]:
    prior_by_code = {i["account_code"]: i for i in prior_items}
    merged = []
    for item in current_items:
        code = item["account_code"]
        pri = prior_by_code.get(code, {})
        cur_amt = float(item.get("amount", 0))
        pri_amt = float(pri.get("amount", 0))
        row = dict(item)
        row["prior_amount"] = pri_amt
        row["variance"] = round(cur_amt - pri_amt, 2)
        pct = _variance_pct(cur_amt, pri_amt)
        if pct is not None:
            row["variance_pct"] = pct
        merged.append(row)
    return merged


def _build_comparison_summary(
    current: Dict[str, float],
    prior: Dict[str, float],
) -> Dict[str, Dict[str, Any]]:
    out: Dict[str, Dict[str, Any]] = {}
    for key in SUMMARY_COMPARE_KEYS:
        cur = float(current.get(key, 0))
        pri = float(prior.get(key, 0))
        entry: Dict[str, Any] = {
            "current": cur,
            "prior": pri,
            "variance": round(cur - pri, 2),
        }
        pct = _variance_pct(cur, pri)
        if pct is not None:
            entry["variance_pct"] = pct
        out[key] = entry
    return out


def _prior_period_dates(date_from_obj: date, date_to_obj: date) -> Tuple[date, date]:
    length_days = (date_to_obj - date_from_obj).days + 1
    prior_to = date_from_obj - timedelta(days=1)
    prior_from = prior_to - timedelta(days=length_days - 1)
    return prior_from, prior_to


def _shift_date_by_years(d: date, years: int) -> date:
    try:
        return d.replace(year=d.year + years)
    except ValueError:
        return d.replace(year=d.year + years, day=28)


def _prior_year_dates(date_from_obj: date, date_to_obj: date) -> Tuple[date, date]:
    return _shift_date_by_years(date_from_obj, -1), _shift_date_by_years(date_to_obj, -1)


def _resolve_compare_mode(
    compare_prior_period: bool,
    compare_mode: Optional[str],
    *,
    is_cumulative: bool,
) -> Optional[str]:
    if compare_mode in COMPARE_MODES:
        return compare_mode
    if compare_prior_period:
        return "prior_year" if is_cumulative else "prior_period"
    return None


def _prior_cumulative_dates(
    db: Session,
    business_id: int,
    fy_id: int,
    fy_start: date,
    date_to_obj: date,
) -> Optional[Tuple[date, date]]:
    current_fy = db.query(FiscalYear).filter(FiscalYear.id == fy_id).first()
    if not current_fy or not current_fy.start_date:
        return None
    prev_fy = (
        db.query(FiscalYear)
        .filter(
            FiscalYear.business_id == business_id,
            FiscalYear.start_date < current_fy.start_date,
        )
        .order_by(FiscalYear.start_date.desc())
        .first()
    )
    if not prev_fy or not prev_fy.start_date:
        return None
    prev_end = prev_fy.end_date or date_to_obj
    days_offset = max((date_to_obj - fy_start).days, 0)
    prior_to = min(prev_fy.start_date + timedelta(days=days_offset), prev_end)
    return prev_fy.start_date, prior_to


def _empty_summary(extra: Optional[Dict[str, Any]] = None) -> Dict[str, float]:
    base = {
        "total_sales": 0.0,
        "total_other_income": 0.0,
        "total_revenue": 0.0,
        "total_cogs": 0.0,
        "gross_profit": 0.0,
        "total_operating_expense": 0.0,
        "operating_profit": 0.0,
        "total_non_operating_income": 0.0,
        "total_non_operating_expense": 0.0,
        "profit_before_tax": 0.0,
        "total_tax_expense": 0.0,
        "total_expense": 0.0,
        "net_profit_after_tax": 0.0,
        "net_profit_loss": 0.0,
    }
    if extra:
        for k, v in extra.items():
            if k in base and isinstance(v, (int, float)):
                base[k] = float(v)
    return base


def _build_pnl_report(
    db: Session,
    business_id: int,
    date_from_obj: date,
    date_to_obj: date,
    fiscal_year_id: Optional[int] = None,
    currency_id: Optional[int] = None,
    project_id: Optional[int] = None,
    include_zero_balance: bool = False,
    skip: int = 0,
    take: int = 100,
    extra_summary: Optional[Dict[str, Any]] = None,
    prior_summary: Optional[Dict[str, float]] = None,
    prior_items_by_section: Optional[Dict[str, List[Dict[str, Any]]]] = None,
) -> Dict[str, Any]:
    fy_id, _fy_start, _fy_end = _ensure_fiscal_year(db, business_id, fiscal_year_id)

    all_accounts = (
        db.query(Account)
        .filter(
            and_(
                (Account.business_id == None) | (Account.business_id == business_id),  # noqa: E711
            )
        )
        .order_by(Account.code.asc())
        .all()
    )

    sales_accounts = [a for a in all_accounts if is_pnl_revenue_gl_account(a) and is_pnl_sales_account(a.code)]
    other_income_accounts = [
        a for a in all_accounts if is_pnl_revenue_gl_account(a) and is_pnl_operating_other_income_account(a.code)
    ]
    non_operating_income_accounts = [
        a for a in all_accounts if is_pnl_revenue_gl_account(a) and is_pnl_non_operating_income_account(a.code)
    ]
    cogs_accounts = [a for a in all_accounts if is_pnl_expense_gl_account(a) and is_pnl_cogs_account(a.code)]
    operating_accounts = [
        a for a in all_accounts if is_pnl_expense_gl_account(a) and is_pnl_operating_expense_account(a.code)
    ]
    non_operating_expense_accounts = [
        a for a in all_accounts if is_pnl_expense_gl_account(a) and is_pnl_non_operating_expense_account(a.code)
    ]
    tax_accounts = [a for a in all_accounts if is_pnl_expense_gl_account(a) and is_pnl_tax_expense_account(a.code)]

    account_ids = [
        a.id
        for a in (
            sales_accounts
            + other_income_accounts
            + non_operating_income_accounts
            + cogs_accounts
            + operating_accounts
            + non_operating_expense_accounts
            + tax_accounts
        )
    ]
    empty = _empty_summary(extra_summary)

    if not account_ids:
        return {
            "sales_items": [],
            "other_income_items": [],
            "non_operating_income_items": [],
            "cogs_items": [],
            "operating_expense_items": [],
            "non_operating_expense_items": [],
            "tax_expense_items": [],
            "revenue_items": [],
            "expense_items": [],
            "statement_lines": _build_statement_lines([], [], [], [], [], empty_summary),
            "summary": empty,
            "pagination": {"total": 0, "page": 1, "per_page": take, "total_pages": 1, "has_next": False, "has_prev": False},
        }

    turnover_by_account = _turnover_by_account_in_base_currency(
        db, business_id, account_ids, date_from_obj, date_to_obj, currency_id, project_id, fiscal_year_id=fy_id,
    )

    def collect_items(accounts: List[Account], section: str) -> List[Dict[str, Any]]:
        items: List[Dict[str, Any]] = []
        prior_items = (prior_items_by_section or {}).get(section, [])
        prior_by_code = {i["account_code"]: i for i in prior_items}
        for account in accounts:
            turnover = turnover_by_account.get(account.id, {"debit": Decimal(0), "credit": Decimal(0)})
            if not include_zero_balance and not _has_nonzero_turnover(turnover):
                pri = prior_by_code.get(account.code)
                if not pri or float(pri.get("amount", 0)) == 0:
                    continue
            item = _account_item(account, turnover, section)
            if prior_items_by_section is not None:
                pri_amt = float(prior_by_code.get(account.code, {}).get("amount", 0))
                item["prior_amount"] = pri_amt
                item["variance"] = round(float(item["amount"]) - pri_amt, 2)
                pct = _variance_pct(float(item["amount"]), pri_amt)
                if pct is not None:
                    item["variance_pct"] = pct
            items.append(item)
        return items

    sales_items = collect_items(sales_accounts, "sales")
    other_income_items = collect_items(other_income_accounts, "other_income")
    non_operating_income_items = collect_items(non_operating_income_accounts, "non_operating_income")
    cogs_items = collect_items(cogs_accounts, "cogs")
    operating_items = collect_items(operating_accounts, "operating_expense")
    non_operating_expense_items = collect_items(non_operating_expense_accounts, "non_operating_expense")
    tax_items = collect_items(tax_accounts, "tax_expense")

    total_sales = _sum_section_amount(sales_items)
    total_other_income = _sum_section_amount(other_income_items)
    total_revenue = total_sales + total_other_income
    total_cogs = _sum_section_amount(cogs_items)
    gross_profit = total_revenue - total_cogs
    total_operating_expense = _sum_section_amount(operating_items)
    operating_profit = gross_profit - total_operating_expense
    total_non_operating_income = _sum_section_amount(non_operating_income_items)
    total_non_operating_expense = _sum_section_amount(non_operating_expense_items)
    profit_before_tax = operating_profit + total_non_operating_income - total_non_operating_expense
    total_tax_expense = _sum_section_amount(tax_items)
    net_profit_after_tax = profit_before_tax - total_tax_expense
    total_expense = total_cogs + total_operating_expense + total_non_operating_expense + total_tax_expense

    summary = {
        "total_sales": float(total_sales),
        "total_other_income": float(total_other_income),
        "total_revenue": float(total_revenue),
        "total_cogs": float(total_cogs),
        "gross_profit": float(gross_profit),
        "total_operating_expense": float(total_operating_expense),
        "operating_profit": float(operating_profit),
        "total_non_operating_income": float(total_non_operating_income),
        "total_non_operating_expense": float(total_non_operating_expense),
        "profit_before_tax": float(profit_before_tax),
        "total_tax_expense": float(total_tax_expense),
        "total_expense": float(total_expense),
        "net_profit_after_tax": float(net_profit_after_tax),
        "net_profit_loss": float(net_profit_after_tax),
    }
    if extra_summary:
        summary.update({k: v for k, v in extra_summary.items() if k not in summary or k.startswith("date_")})

    revenue_items = sales_items + other_income_items
    expense_items = cogs_items + operating_items + non_operating_expense_items + tax_items

    return {
        "sales_items": sales_items,
        "other_income_items": other_income_items,
        "non_operating_income_items": non_operating_income_items,
        "cogs_items": cogs_items,
        "operating_expense_items": operating_items,
        "non_operating_expense_items": non_operating_expense_items,
        "tax_expense_items": tax_items,
        "revenue_items": revenue_items,
        "expense_items": expense_items,
        "statement_lines": _build_statement_lines(
            sales_items,
            other_income_items,
            cogs_items,
            operating_items,
            tax_items,
            summary,
            prior_summary,
            non_operating_income_items=non_operating_income_items,
            non_operating_expense_items=non_operating_expense_items,
        ),
        "summary": summary,
        "pagination": {
            "total": len(revenue_items) + len(expense_items),
            "page": 1,
            "per_page": take,
            "total_pages": 1,
            "has_next": False,
            "has_prev": False,
        },
    }


def _attach_prior_period(
    result: Dict[str, Any],
    prior_result: Dict[str, Any],
    prior_from: date,
    prior_to: date,
) -> Dict[str, Any]:
    prior_summary = prior_result.get("summary") or {}
    current_summary = result.get("summary") or {}

    section_map = {
        "sales_items": "sales",
        "other_income_items": "other_income",
        "non_operating_income_items": "non_operating_income",
        "cogs_items": "cogs",
        "operating_expense_items": "operating_expense",
        "non_operating_expense_items": "non_operating_expense",
        "tax_expense_items": "tax_expense",
    }
    prior_sections = {
        "sales": prior_result.get("sales_items") or [],
        "other_income": prior_result.get("other_income_items") or [],
        "non_operating_income": prior_result.get("non_operating_income_items") or [],
        "cogs": prior_result.get("cogs_items") or [],
        "operating_expense": prior_result.get("operating_expense_items") or [],
        "non_operating_expense": prior_result.get("non_operating_expense_items") or [],
        "tax_expense": prior_result.get("tax_expense_items") or [],
    }

    for items_key, section in section_map.items():
        result[items_key] = _merge_item_comparison(
            result.get(items_key) or [],
            prior_sections.get(section, []),
        )

    result["revenue_items"] = (result.get("sales_items") or []) + (result.get("other_income_items") or [])
    result["expense_items"] = (
        (result.get("cogs_items") or [])
        + (result.get("operating_expense_items") or [])
        + (result.get("non_operating_expense_items") or [])
        + (result.get("tax_expense_items") or [])
    )
    result["statement_lines"] = _build_statement_lines(
        result.get("sales_items") or [],
        result.get("other_income_items") or [],
        result.get("cogs_items") or [],
        result.get("operating_expense_items") or [],
        result.get("tax_expense_items") or [],
        current_summary,
        prior_summary,
        non_operating_income_items=result.get("non_operating_income_items") or [],
        non_operating_expense_items=result.get("non_operating_expense_items") or [],
    )
    result["prior_summary"] = prior_summary
    result["prior_period"] = {
        "date_from": prior_from.isoformat(),
        "date_to": prior_to.isoformat(),
    }
    result["comparison"] = _build_comparison_summary(current_summary, prior_summary)
    return result


def get_pnl_period_report(
    db: Session,
    business_id: int,
    fiscal_year_id: Optional[int] = None,
    currency_id: Optional[int] = None,
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
    project_id: Optional[int] = None,
    include_zero_balance: bool = False,
    compare_prior_period: bool = False,
    compare_mode: Optional[str] = None,
    skip: int = 0,
    take: int = 100,
) -> Dict[str, Any]:
    fy_id, fy_start_date, _fy_end = _ensure_fiscal_year(db, business_id, fiscal_year_id)

    date_from_obj = None
    date_to_obj = None
    if date_from:
        try:
            date_from_obj = _parse_iso_date(date_from)
        except Exception:
            pass
    if date_to:
        try:
            date_to_obj = _parse_iso_date(date_to)
        except Exception:
            pass

    if date_from_obj is None:
        date_from_obj = fy_start_date
    if date_to_obj is None:
        fiscal_year = db.query(FiscalYear).filter(FiscalYear.id == fy_id).first()
        date_to_obj = fiscal_year.end_date if fiscal_year and fiscal_year.end_date else date.today()

    result = _build_pnl_report(
        db=db,
        business_id=business_id,
        date_from_obj=date_from_obj,
        date_to_obj=date_to_obj,
        fiscal_year_id=fy_id,
        currency_id=currency_id,
        project_id=project_id,
        include_zero_balance=include_zero_balance,
        skip=skip,
        take=take,
        extra_summary={
            "date_from": date_from_obj.isoformat(),
            "date_to": date_to_obj.isoformat(),
        },
    )

    mode = _resolve_compare_mode(compare_prior_period, compare_mode, is_cumulative=False)
    if mode:
        if mode == "prior_year":
            prior_from, prior_to = _prior_year_dates(date_from_obj, date_to_obj)
        else:
            prior_from, prior_to = _prior_period_dates(date_from_obj, date_to_obj)
        prior_result = _build_pnl_report(
            db=db,
            business_id=business_id,
            date_from_obj=prior_from,
            date_to_obj=prior_to,
            fiscal_year_id=None,
            currency_id=currency_id,
            project_id=project_id,
            include_zero_balance=include_zero_balance,
            extra_summary={
                "date_from": prior_from.isoformat(),
                "date_to": prior_to.isoformat(),
            },
        )
        result = _attach_prior_period(result, prior_result, prior_from, prior_to)
        result["compare_mode"] = mode
    return result


def get_pnl_cumulative_report(
    db: Session,
    business_id: int,
    fiscal_year_id: Optional[int] = None,
    currency_id: Optional[int] = None,
    date_to: Optional[str] = None,
    project_id: Optional[int] = None,
    include_zero_balance: bool = False,
    compare_prior_period: bool = False,
    compare_mode: Optional[str] = None,
    skip: int = 0,
    take: int = 100,
) -> Dict[str, Any]:
    fy_id, fy_start_date, _fy_end = _ensure_fiscal_year(db, business_id, fiscal_year_id)

    date_to_obj = None
    if date_to:
        try:
            date_to_obj = _parse_iso_date(date_to)
        except Exception:
            pass
    if date_to_obj is None:
        fiscal_year = db.query(FiscalYear).filter(FiscalYear.id == fy_id).first()
        date_to_obj = fiscal_year.end_date if fiscal_year and fiscal_year.end_date else date.today()

    result = _build_pnl_report(
        db=db,
        business_id=business_id,
        date_from_obj=fy_start_date,
        date_to_obj=date_to_obj,
        fiscal_year_id=fy_id,
        currency_id=currency_id,
        project_id=project_id,
        include_zero_balance=include_zero_balance,
        skip=skip,
        take=take,
        extra_summary={
            "date_from": fy_start_date.isoformat(),
            "date_to": date_to_obj.isoformat(),
        },
    )

    mode = _resolve_compare_mode(compare_prior_period, compare_mode, is_cumulative=True)
    if mode:
        prior_range = _prior_cumulative_dates(db, business_id, fy_id, fy_start_date, date_to_obj)
        if prior_range:
            prior_from, prior_to = prior_range
            prior_result = _build_pnl_report(
                db=db,
                business_id=business_id,
                date_from_obj=prior_from,
                date_to_obj=prior_to,
                fiscal_year_id=None,
                currency_id=currency_id,
                project_id=project_id,
                include_zero_balance=include_zero_balance,
                extra_summary={
                    "date_from": prior_from.isoformat(),
                    "date_to": prior_to.isoformat(),
                },
            )
            result = _attach_prior_period(result, prior_result, prior_from, prior_to)
            result["compare_mode"] = mode
    return result
