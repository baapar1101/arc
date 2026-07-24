"""گزارش ترازنامه (صورت وضعیت مالی) با رعایت اصول حسابداری."""
from __future__ import annotations

from datetime import date, timedelta
from decimal import Decimal
from typing import Any, Dict, List, Optional, Tuple

from sqlalchemy.orm import Session

from adapters.db.models.fiscal_year import FiscalYear
from app.services.account_balance_core import (
    ACCOUNT_LEVELS,
    BALANCE_TOLERANCE,
    build_account_tree,
    build_tree_items,
    compute_leaf_balances,
    fetch_business_accounts,
    parse_iso_date,
    resolve_date_range,
    rollup_account_balance,
)
from app.services.balance_sheet_account_classification import (
    BS_MAIN_SECTION_LABELS_EN,
    BS_MAIN_SECTION_LABELS_FA,
    BS_SECTION_LABELS_EN,
    BS_SECTION_LABELS_FA,
    balance_sheet_main_section,
    balance_sheet_presentation_amount,
    balance_sheet_subsection,
    is_permanent_account,
)
from app.services.pnl_service import (
    _prior_period_dates,
    _prior_year_dates,
    _resolve_compare_mode,
    _variance_pct,
    get_pnl_period_report,
)

BS_SUMMARY_COMPARE_KEYS = (
    "total_assets",
    "total_liabilities",
    "total_equity",
    "total_liabilities_and_equity",
    "current_period_profit",
    "balance_difference",
)

CURRENT_PERIOD_PROFIT_ACCOUNT_CODE = "__current_period_profit__"


def _build_bs_comparison_summary(
    current: Dict[str, float],
    prior: Dict[str, float],
) -> Dict[str, Dict[str, Any]]:
    out: Dict[str, Dict[str, Any]] = {}
    for key in BS_SUMMARY_COMPARE_KEYS:
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


def _empty_bs_summary() -> Dict[str, float]:
    return {
        "total_current_assets": 0.0,
        "total_non_current_assets": 0.0,
        "total_assets": 0.0,
        "total_current_liabilities": 0.0,
        "total_non_current_liabilities": 0.0,
        "total_liabilities": 0.0,
        "total_equity_accounts": 0.0,
        "current_period_profit": 0.0,
        "total_equity": 0.0,
        "total_liabilities_and_equity": 0.0,
        "balance_difference": 0.0,
        "equation_balanced": True,
    }


def _account_bs_item(
    account_id: int,
    account_tree: Dict[int, Dict[str, Any]],
    amount: float,
    *,
    level: int = 0,
    has_children: bool = False,
    children: Optional[List[Dict[str, Any]]] = None,
    prior_amount: Optional[float] = None,
) -> Dict[str, Any]:
    acc_data = account_tree[account_id]
    subsection = balance_sheet_subsection(acc_data["code"])
    row: Dict[str, Any] = {
        "account_id": account_id,
        "account_code": acc_data["code"],
        "account_name": acc_data["name"],
        "account_type": acc_data["account_type"],
        "section": balance_sheet_main_section(acc_data["code"]),
        "subsection": subsection,
        "level": level,
        "has_children": has_children,
        "children": children or [],
        "amount": amount,
    }
    if prior_amount is not None:
        row["prior_amount"] = prior_amount
        row["variance"] = round(amount - prior_amount, 2)
        pct = _variance_pct(amount, prior_amount)
        if pct is not None:
            row["variance_pct"] = pct
    return row


def _build_permanent_account_tree(
    account_tree: Dict[int, Dict[str, Any]],
    leaf_balances: Dict[int, Any],
    *,
    include_zero_balance: bool,
    max_depth: Optional[int],
    prior_amounts_by_code: Optional[Dict[str, float]] = None,
) -> Dict[str, List[Dict[str, Any]]]:
    """ساخت درخت حساب‌های دائمی به تفکیک بخش ترازنامه."""

    def build_nodes(parent_id: Optional[int], level: int) -> List[Dict[str, Any]]:
        if parent_id is None:
            from app.services.account_balance_core import get_root_account_ids

            node_ids = [
                aid
                for aid in get_root_account_ids(account_tree)
                if is_permanent_account(account_tree[aid]["code"])
            ]
        else:
            node_ids = [
                cid
                for cid in account_tree[parent_id]["children"]
                if is_permanent_account(account_tree[cid]["code"])
            ]

        nodes: List[Dict[str, Any]] = []
        for acc_id in node_ids:
            acc_data = account_tree[acc_id]
            balance = rollup_account_balance(acc_id, account_tree, leaf_balances)
            closing_debit = balance.opening_debit + balance.period_debit
            closing_credit = balance.opening_credit + balance.period_credit
            amount = balance_sheet_presentation_amount(
                float(closing_debit),
                float(closing_credit),
                acc_data["code"],
            )

            children: List[Dict[str, Any]] = []
            show_children = acc_data["has_children"] and (max_depth is None or level + 1 < max_depth)
            if show_children:
                children = build_nodes(acc_id, level + 1)

            prior_amount = None
            if prior_amounts_by_code is not None:
                prior_amount = prior_amounts_by_code.get(acc_data["code"])

            if not include_zero_balance and amount == 0 and not children:
                continue

            nodes.append(
                _account_bs_item(
                    acc_id,
                    account_tree,
                    amount,
                    level=level,
                    has_children=bool(children) or acc_data["has_children"],
                    children=children,
                    prior_amount=prior_amount,
                )
            )
        return nodes

    all_nodes = build_nodes(None, 0)
    return _group_nodes_by_subsection(all_nodes)


def _group_nodes_by_subsection(
    nodes: List[Dict[str, Any]],
) -> Dict[str, List[Dict[str, Any]]]:
    """توزیع گره‌های درخت به زیربخش‌های ترازنامه.

    ریشه‌های گروه (۱، ۲) subsection ندارند؛ فرزندان مستقیم و غیرمستقیم آن‌ها
    (مثلاً ۱۰۱، ۱۰۲، ۲۰۱) بر اساس کد حساب در بخش مناسب قرار می‌گیرند.
    ریشه حقوق صاحبان سهام (۳) خودش subsection دارد و با زیردرخت کامل نگه داشته می‌شود.
    """
    grouped: Dict[str, List[Dict[str, Any]]] = {
        "current_assets": [],
        "non_current_assets": [],
        "current_liabilities": [],
        "non_current_liabilities": [],
        "equity": [],
    }

    def assign_node(node: Dict[str, Any]) -> None:
        subsection = node.get("subsection")
        if subsection in grouped:
            grouped[subsection].append(node)
            return
        for child in node.get("children") or []:
            assign_node(child)

    for node in nodes:
        assign_node(node)
    return grouped


def _sum_section_amount(items: List[Dict[str, Any]]) -> Decimal:
    """جمع مبالغ سطرهای سطح اول هر بخش (مانده والد از قبل rollup شده است)."""
    total = Decimal(0)
    for item in items:
        total += Decimal(str(item.get("amount", 0) or 0))
    return total


def _flatten_amounts_by_code(items: List[Dict[str, Any]]) -> Dict[str, float]:
    out: Dict[str, float] = {}

    def walk(nodes: List[Dict[str, Any]]) -> None:
        for node in nodes:
            code = node.get("account_code")
            if code:
                out[str(code)] = float(node.get("amount", 0) or 0)
            if node.get("children"):
                walk(node["children"])

    walk(items)
    return out


def _collect_all_section_items(grouped: Dict[str, List[Dict[str, Any]]]) -> List[Dict[str, Any]]:
    items: List[Dict[str, Any]] = []
    for key in ("current_assets", "non_current_assets", "current_liabilities", "non_current_liabilities", "equity"):
        items.extend(grouped.get(key) or [])
    return items


def _build_statement_lines(
    grouped: Dict[str, List[Dict[str, Any]]],
    summary: Dict[str, float],
    *,
    prior_summary: Optional[Dict[str, float]] = None,
    has_compare: bool = False,
) -> List[Dict[str, Any]]:
    lines: List[Dict[str, Any]] = []

    def prior_val(key: str) -> Optional[float]:
        if prior_summary is None:
            return None
        return float(prior_summary.get(key, 0))

    def add_compare(line: Dict[str, Any], summary_key: Optional[str] = None) -> Dict[str, Any]:
        if not has_compare or summary_key is None:
            return line
        cur = float(summary.get(summary_key, 0))
        pri = prior_val(summary_key) or 0.0
        line["prior_amount"] = pri
        line["variance"] = round(cur - pri, 2)
        pct = _variance_pct(cur, pri)
        if pct is not None:
            line["variance_pct"] = pct
        return line

    def add_section_header(subsection: str) -> None:
        lines.append({
            "type": "section_header",
            "section": subsection,
            "label_fa": BS_SECTION_LABELS_FA.get(subsection, subsection),
            "label_en": BS_SECTION_LABELS_EN.get(subsection, subsection),
        })

    def add_accounts(subsection: str, items: List[Dict[str, Any]]) -> None:
        if not items:
            return
        add_section_header(subsection)

        def walk(nodes: List[Dict[str, Any]], depth: int = 0) -> None:
            for node in nodes:
                row = {
                    "type": "account",
                    "section": subsection,
                    "account_id": node.get("account_id"),
                    "account_code": node.get("account_code"),
                    "account_name": node.get("account_name"),
                    "account_type": node.get("account_type"),
                    "amount": node.get("amount", 0),
                    "level": depth,
                }
                if has_compare and node.get("prior_amount") is not None:
                    row["prior_amount"] = node.get("prior_amount")
                    row["variance"] = node.get("variance")
                    row["variance_pct"] = node.get("variance_pct")
                lines.append(row)
                if node.get("children"):
                    walk(node["children"], depth + 1)

        walk(items)

    def add_subtotal(subsection: str, summary_key: str, label_fa: str, label_en: str, *, highlight: bool = False) -> None:
        lines.append(add_compare({
            "type": "subtotal",
            "section": subsection,
            "label_fa": label_fa,
            "label_en": label_en,
            "amount": summary.get(summary_key, 0),
            "highlight": highlight,
        }, summary_key))

    add_accounts("current_assets", grouped.get("current_assets") or [])
    add_subtotal("current_assets", "total_current_assets", "جمع دارایی‌های جاری", "Total Current Assets")
    add_accounts("non_current_assets", grouped.get("non_current_assets") or [])
    add_subtotal("non_current_assets", "total_non_current_assets", "جمع دارایی‌های غیرجاری", "Total Non-Current Assets")
    add_subtotal("assets", "total_assets", "جمع دارایی‌ها", "Total Assets", highlight=True)

    add_accounts("current_liabilities", grouped.get("current_liabilities") or [])
    add_subtotal("current_liabilities", "total_current_liabilities", "جمع بدهی‌های جاری", "Total Current Liabilities")
    add_accounts("non_current_liabilities", grouped.get("non_current_liabilities") or [])
    add_subtotal(
        "non_current_liabilities",
        "total_non_current_liabilities",
        "جمع بدهی‌های غیرجاری",
        "Total Non-Current Liabilities",
    )
    add_subtotal("liabilities", "total_liabilities", "جمع بدهی‌ها", "Total Liabilities", highlight=True)

    add_accounts("equity", grouped.get("equity") or [])
    if summary.get("current_period_profit", 0) != 0 or (prior_summary and prior_summary.get("current_period_profit")):
        cpp_row = {
            "type": "account",
            "section": "equity",
            "account_code": CURRENT_PERIOD_PROFIT_ACCOUNT_CODE,
            "account_name": BS_SECTION_LABELS_FA["current_period_profit"],
            "amount": summary.get("current_period_profit", 0),
        }
        if has_compare:
            cpp_row["prior_amount"] = prior_val("current_period_profit") or 0.0
            cpp_row["variance"] = round(float(summary.get("current_period_profit", 0)) - float(cpp_row["prior_amount"]), 2)
            pct = _variance_pct(float(summary.get("current_period_profit", 0)), float(cpp_row["prior_amount"]))
            if pct is not None:
                cpp_row["variance_pct"] = pct
        lines.append(cpp_row)

    add_subtotal("equity", "total_equity", "جمع حقوق صاحبان سهام", "Total Equity", highlight=True)
    lines.append(add_compare({
        "type": "grand_total",
        "section": "liabilities_and_equity",
        "label_fa": "جمع بدهی‌ها و حقوق صاحبان سهام",
        "label_en": "Total Liabilities & Equity",
        "amount": summary.get("total_liabilities_and_equity", 0),
        "highlight": True,
    }, "total_liabilities_and_equity"))

    equation_ok = abs(float(summary.get("balance_difference", 0))) <= float(BALANCE_TOLERANCE)
    lines.append({
        "type": "equation_check",
        "label_fa": "معادله ترازنامه (دارایی = بدهی + حقوق صاحبان سهام)",
        "label_en": "Balance Sheet Equation (Assets = Liabilities + Equity)",
        "amount": summary.get("balance_difference", 0),
        "equation_balanced": equation_ok,
        "total_assets": summary.get("total_assets", 0),
        "total_liabilities_and_equity": summary.get("total_liabilities_and_equity", 0),
    })
    return lines


def _compute_current_period_profit(
    db: Session,
    business_id: int,
    fiscal_year_id: int,
    fy_start: date,
    date_to_obj: date,
    currency_id: Optional[int],
    project_id: Optional[int],
) -> float:
    pnl = get_pnl_period_report(
        db=db,
        business_id=business_id,
        fiscal_year_id=fiscal_year_id,
        currency_id=currency_id,
        date_from=fy_start.isoformat(),
        date_to=date_to_obj.isoformat(),
        project_id=project_id,
        include_zero_balance=True,
        skip=0,
        take=1,
    )
    summary = pnl.get("summary") or {}
    return float(summary.get("net_profit_after_tax", summary.get("net_profit_loss", 0)) or 0)


def _build_balance_sheet_report(
    db: Session,
    business_id: int,
    date_from_obj: date,
    date_to_obj: date,
    fy_id: int,
    fy_start: date,
    *,
    currency_id: Optional[int] = None,
    project_id: Optional[int] = None,
    include_zero_balance: bool = False,
    account_level: int = 4,
    prior_grouped: Optional[Dict[str, List[Dict[str, Any]]]] = None,
    prior_summary: Optional[Dict[str, float]] = None,
    has_compare: bool = False,
) -> Dict[str, Any]:
    accounts = fetch_business_accounts(db, business_id)
    permanent_accounts = [a for a in accounts if is_permanent_account(a.code)]
    if not permanent_accounts:
        summary = _empty_bs_summary()
        grouped = {
            "current_assets": [],
            "non_current_assets": [],
            "current_liabilities": [],
            "non_current_liabilities": [],
            "equity": [],
        }
        return {
            "grouped": grouped,
            "summary": summary,
            "statement_lines": _build_statement_lines(grouped, summary),
            "current_period_profit_item": None,
        }

    account_tree = build_account_tree(permanent_accounts)
    account_ids = [a.id for a in permanent_accounts]
    leaf_balances = compute_leaf_balances(
        db,
        business_id,
        account_ids,
        date_from_obj,
        date_to_obj,
        fy_id,
        currency_id,
        project_id,
    )

    prior_amounts_by_code: Optional[Dict[str, float]] = None
    if prior_grouped is not None:
        prior_amounts_by_code = {}
        for section_items in prior_grouped.values():
            prior_amounts_by_code.update(_flatten_amounts_by_code(section_items))

    max_depth = account_level if account_level < 4 else None
    grouped = _build_permanent_account_tree(
        account_tree,
        leaf_balances,
        include_zero_balance=include_zero_balance,
        max_depth=max_depth,
        prior_amounts_by_code=prior_amounts_by_code,
    )

    total_current_assets = _sum_section_amount(grouped["current_assets"])
    total_non_current_assets = _sum_section_amount(grouped["non_current_assets"])
    total_assets = total_current_assets + total_non_current_assets
    total_current_liabilities = _sum_section_amount(grouped["current_liabilities"])
    total_non_current_liabilities = _sum_section_amount(grouped["non_current_liabilities"])
    total_liabilities = total_current_liabilities + total_non_current_liabilities
    total_equity_accounts = _sum_section_amount(grouped["equity"])
    current_period_profit = Decimal(
        str(
            _compute_current_period_profit(
                db,
                business_id,
                fy_id,
                fy_start,
                date_to_obj,
                currency_id,
                project_id,
            )
        )
    )
    total_equity = total_equity_accounts + current_period_profit
    total_liabilities_and_equity = total_liabilities + total_equity
    balance_difference = total_assets - total_liabilities_and_equity

    summary = {
        "total_current_assets": float(total_current_assets),
        "total_non_current_assets": float(total_non_current_assets),
        "total_assets": float(total_assets),
        "total_current_liabilities": float(total_current_liabilities),
        "total_non_current_liabilities": float(total_non_current_liabilities),
        "total_liabilities": float(total_liabilities),
        "total_equity_accounts": float(total_equity_accounts),
        "current_period_profit": float(current_period_profit),
        "total_equity": float(total_equity),
        "total_liabilities_and_equity": float(total_liabilities_and_equity),
        "balance_difference": float(balance_difference),
        "equation_balanced": abs(balance_difference) <= BALANCE_TOLERANCE,
    }

    current_period_profit_item = {
        "account_code": CURRENT_PERIOD_PROFIT_ACCOUNT_CODE,
        "account_name": BS_SECTION_LABELS_FA["current_period_profit"],
        "section": "equity",
        "subsection": "current_period_profit",
        "amount": float(current_period_profit),
    }
    if has_compare and prior_summary is not None:
        pri = float(prior_summary.get("current_period_profit", 0))
        current_period_profit_item["prior_amount"] = pri
        current_period_profit_item["variance"] = round(float(current_period_profit) - pri, 2)
        pct = _variance_pct(float(current_period_profit), pri)
        if pct is not None:
            current_period_profit_item["variance_pct"] = pct

    statement_lines = _build_statement_lines(
        grouped,
        summary,
        prior_summary=prior_summary,
        has_compare=has_compare,
    )

    return {
        "grouped": grouped,
        "summary": summary,
        "statement_lines": statement_lines,
        "current_period_profit_item": current_period_profit_item,
    }


def get_balance_sheet_report(
    db: Session,
    business_id: int,
    fiscal_year_id: Optional[int] = None,
    currency_id: Optional[int] = None,
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
    project_id: Optional[int] = None,
    include_zero_balance: bool = False,
    account_level: int = 4,
    compare_prior_period: bool = False,
    compare_mode: Optional[str] = None,
) -> Dict[str, Any]:
    """
    گزارش ترازنامه (صورت وضعیت مالی).

    - مانده حساب‌های دائم (گروه ۱، ۲، ۳) در تاریخ پایان
    - سود (زیان) دوره جاری از محاسبه سود و زیان
    - اعتبارسنجی معادله: دارایی = بدهی + حقوق صاحبان سهام
    """
    if account_level not in ACCOUNT_LEVELS:
        account_level = 4

    fy_id, date_from_obj, date_to_obj = resolve_date_range(
        db, business_id, fiscal_year_id, date_from, date_to
    )
    fiscal_year = db.query(FiscalYear).filter(FiscalYear.id == fy_id).first()
    fy_start = fiscal_year.start_date if fiscal_year and fiscal_year.start_date else date_from_obj

    resolved_compare = _resolve_compare_mode(
        compare_prior_period,
        compare_mode,
        is_cumulative=False,
    )

    report = _build_balance_sheet_report(
        db,
        business_id,
        date_from_obj,
        date_to_obj,
        fy_id,
        fy_start,
        currency_id=currency_id,
        project_id=project_id,
        include_zero_balance=include_zero_balance,
        account_level=account_level,
        has_compare=bool(resolved_compare),
    )

    result: Dict[str, Any] = {
        "grouped": report["grouped"],
        "summary": report["summary"],
        "statement_lines": report["statement_lines"],
        "current_period_profit_item": report["current_period_profit_item"],
        "meta": {
            "account_level": account_level,
            "date_from": date_from_obj.isoformat(),
            "date_to": date_to_obj.isoformat(),
            "as_of_date": date_to_obj.isoformat(),
            "fiscal_year_id": fy_id,
            "currency_id": currency_id,
            "project_id": project_id,
            "compare_mode": resolved_compare,
        },
        "section_labels_fa": BS_SECTION_LABELS_FA,
        "section_labels_en": BS_SECTION_LABELS_EN,
        "main_section_labels_fa": BS_MAIN_SECTION_LABELS_FA,
        "main_section_labels_en": BS_MAIN_SECTION_LABELS_EN,
    }

    if resolved_compare:
        if resolved_compare == "prior_year":
            prior_from, prior_to = _prior_year_dates(date_from_obj, date_to_obj)
        else:
            prior_from, prior_to = _prior_period_dates(date_from_obj, date_to_obj)

        prior_fy = (
            db.query(FiscalYear)
            .filter(
                FiscalYear.business_id == business_id,
                FiscalYear.start_date <= prior_to,
                FiscalYear.end_date >= prior_from,
            )
            .order_by(FiscalYear.start_date.desc())
            .first()
        )
        prior_fy_id = prior_fy.id if prior_fy else fy_id
        prior_fy_start = prior_fy.start_date if prior_fy and prior_fy.start_date else prior_from

        prior_report = _build_balance_sheet_report(
            db,
            business_id,
            prior_from,
            prior_to,
            prior_fy_id,
            prior_fy_start,
            currency_id=currency_id,
            project_id=project_id,
            include_zero_balance=include_zero_balance,
            account_level=account_level,
        )
        prior_summary = prior_report["summary"]

        report = _build_balance_sheet_report(
            db,
            business_id,
            date_from_obj,
            date_to_obj,
            fy_id,
            fy_start,
            currency_id=currency_id,
            project_id=project_id,
            include_zero_balance=include_zero_balance,
            account_level=account_level,
            prior_grouped=prior_report["grouped"],
            prior_summary=prior_summary,
            has_compare=True,
        )
        result["grouped"] = report["grouped"]
        result["summary"] = report["summary"]
        result["statement_lines"] = report["statement_lines"]
        result["current_period_profit_item"] = report["current_period_profit_item"]
        result["prior_summary"] = prior_summary
        result["prior_period"] = {
            "date_from": prior_from.isoformat(),
            "date_to": prior_to.isoformat(),
        }
        result["comparison"] = _build_bs_comparison_summary(
            {k: float(v) for k, v in result["summary"].items() if k in BS_SUMMARY_COMPARE_KEYS},
            {k: float(v) for k, v in prior_summary.items() if k in BS_SUMMARY_COMPARE_KEYS},
        )

    return result
