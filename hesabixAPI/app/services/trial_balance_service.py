from __future__ import annotations

from typing import Any, Dict, List, Optional

from sqlalchemy.orm import Session

from app.services.account_balance_core import (
    ACCOUNT_LEVELS,
    COLUMN_MODES,
    DISPLAY_MODES,
    apply_column_mode,
    apply_column_mode_to_tree,
    build_account_tree,
    build_tree_items,
    compute_leaf_balances,
    fetch_business_accounts,
    flatten_tree_at_level,
    paginate_items,
    resolve_date_range,
    sum_root_items_only,
    validate_trial_balance,
)


def get_trial_balance_report(
    db: Session,
    business_id: int,
    fiscal_year_id: Optional[int] = None,
    currency_id: Optional[int] = None,
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
    account_type: Optional[str] = None,
    account_ids: Optional[List[int]] = None,
    project_id: Optional[int] = None,
    include_zero_balance: bool = False,
    column_mode: int = 8,
    display_mode: str = "flat",
    account_level: int = 4,
    skip: int = 0,
    take: int = 50,
) -> Dict[str, Any]:
    """
    گزارش تراز آزمایشی با پشتیبانی از:
    - حالت ستونی ۲ / ۴ / ۶ / ۸
    - نمایش تخت یا درختی
    - سطوح گروه / کل / معین / تفصیل
    """
    if column_mode not in COLUMN_MODES:
        column_mode = 8
    if display_mode not in DISPLAY_MODES:
        display_mode = "flat"
    if account_level not in ACCOUNT_LEVELS:
        account_level = 4

    fy_id, date_from_obj, date_to_obj = resolve_date_range(
        db, business_id, fiscal_year_id, date_from, date_to
    )

    accounts = fetch_business_accounts(db, business_id, account_type, account_ids)
    if not accounts:
        empty_summary = {
            "total_accounts": 0,
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
        }
        return {
            "items": [],
            "accounts": [],
            "summary": empty_summary,
            "pagination": paginate_items([], skip, take)["pagination"],
            "meta": {
                "column_mode": column_mode,
                "display_mode": display_mode,
                "account_level": account_level,
                "date_from": date_from_obj.isoformat(),
                "date_to": date_to_obj.isoformat(),
                "fiscal_year_id": fy_id,
            },
        }

    account_ids_list = [acc.id for acc in accounts]
    account_tree = build_account_tree(accounts)
    leaf_balances = compute_leaf_balances(
        db,
        business_id,
        account_ids_list,
        date_from_obj,
        date_to_obj,
        fy_id,
        currency_id,
        project_id,
    )

    max_depth = account_level if account_level < 4 else None
    tree_items = build_tree_items(
        account_tree,
        leaf_balances,
        include_zero_balance=include_zero_balance,
        max_depth=max_depth,
    )

    if display_mode == "tree":
        output_items = apply_column_mode_to_tree(tree_items, column_mode)
        flat_for_totals = tree_items
    else:
        flat_items = flatten_tree_at_level(tree_items, account_level)
        output_items = [apply_column_mode(item, column_mode) for item in flat_items]
        flat_for_totals = flat_items

    totals = sum_root_items_only(flat_for_totals if display_mode == "flat" else tree_items)
    validation = validate_trial_balance(totals)

    page = paginate_items(output_items if display_mode == "flat" else output_items, skip, take)

    summary = {
        "total_accounts": len(output_items),
        "total_opening_debit": float(totals["opening_debit"]),
        "total_opening_credit": float(totals["opening_credit"]),
        "total_period_debit": float(totals["period_debit"]),
        "total_period_credit": float(totals["period_credit"]),
        "total_closing_debit": float(totals["closing_debit"]),
        "total_closing_credit": float(totals["closing_credit"]),
        **validation,
    }

    result: Dict[str, Any] = {
        "summary": summary,
        "pagination": page["pagination"],
        "meta": {
            "column_mode": column_mode,
            "display_mode": display_mode,
            "account_level": account_level,
            "date_from": date_from_obj.isoformat(),
            "date_to": date_to_obj.isoformat(),
            "fiscal_year_id": fy_id,
            "currency_id": currency_id,
            "project_id": project_id,
        },
    }

    if display_mode == "tree":
        result["accounts"] = page["items"]
        result["items"] = []
    else:
        result["items"] = page["items"]
        result["accounts"] = []

    return result
