"""هسته مشترک محاسبه مانده حساب‌ها برای تراز آزمایشی، مرور حساب و ترازنامه."""
from __future__ import annotations

from dataclasses import dataclass
from datetime import date, timedelta
from decimal import Decimal
from typing import Any, Dict, List, Optional, Tuple

from sqlalchemy import and_, func
from sqlalchemy.orm import Session

from adapters.db.models.account import Account
from adapters.db.models.document import Document
from adapters.db.models.document_line import DocumentLine
from adapters.db.models.fiscal_year import FiscalYear
from app.services.opening_balance_service import _ensure_fiscal_year, _find_existing_ob_document

COLUMN_MODES = frozenset({2, 4, 6, 8})
DISPLAY_MODES = frozenset({"flat", "tree"})
ACCOUNT_LEVELS = frozenset({1, 2, 3, 4})
BALANCE_TOLERANCE = Decimal("0.01")

# نگاشت نوع حساب UI/API به مقادیر ممکن در دیتابیس (رشته‌ای یا عددی از seed قدیمی)
ACCOUNT_TYPE_FILTER_ALIASES: Dict[str, tuple[str, ...]] = {
    "bank": ("bank", "3"),
    "cash_register": ("cash_register", "1"),
    "petty_cash": ("petty_cash", "2"),
    "check": ("check", "4"),
    "person": ("person", "5"),
    "product": ("product", "6"),
    "service": ("service", "7"),
    "accounting_document": ("accounting_document", "0"),
}


@dataclass
class AccountBalance:
    opening_debit: Decimal
    opening_credit: Decimal
    period_debit: Decimal
    period_credit: Decimal

    @property
    def opening_net(self) -> Decimal:
        return self.opening_debit - self.opening_credit

    @property
    def closing_debit(self) -> Decimal:
        return self.opening_debit + self.period_debit

    @property
    def closing_credit(self) -> Decimal:
        return self.opening_credit + self.period_credit

    @property
    def closing_net(self) -> Decimal:
        return self.closing_debit - self.closing_credit

    def split_opening(self) -> Tuple[Decimal, Decimal]:
        return split_debit_credit_balance(self.opening_net)

    def split_closing(self) -> Tuple[Decimal, Decimal]:
        return split_debit_credit_balance(self.closing_net)


def parse_iso_date(dt: str | date) -> date:
    if isinstance(dt, date):
        return dt
    if isinstance(dt, str):
        return date.fromisoformat(dt.split("T")[0])
    raise ValueError(f"Invalid date format: {dt}")


def split_debit_credit_balance(net_balance: Decimal) -> Tuple[Decimal, Decimal]:
    if net_balance >= 0:
        return net_balance, Decimal(0)
    return Decimal(0), -net_balance


def resolve_date_range(
    db: Session,
    business_id: int,
    fiscal_year_id: Optional[int],
    date_from: Optional[str],
    date_to: Optional[str],
) -> Tuple[int, date, date]:
    fy_id, fy_start, fy_end = _ensure_fiscal_year(db, business_id, fiscal_year_id)

    date_from_obj: Optional[date] = None
    date_to_obj: Optional[date] = None

    if date_from:
        try:
            date_from_obj = parse_iso_date(date_from)
        except Exception:
            pass
    if date_to:
        try:
            date_to_obj = parse_iso_date(date_to)
        except Exception:
            pass

    if date_from_obj is None:
        date_from_obj = fy_start
    if date_to_obj is None:
        fiscal_year = db.query(FiscalYear).filter(FiscalYear.id == fy_id).first()
        date_to_obj = fiscal_year.end_date if fiscal_year and fiscal_year.end_date else date.today()

    return fy_id, date_from_obj, date_to_obj


def resolve_account_type_filter(account_type: Optional[str]) -> Optional[tuple[str, ...]]:
    """تبدیل نوع حساب درخواستی به مجموعه مقادیر قابل جستجو در دیتابیس."""
    if not account_type:
        return None
    key = str(account_type).strip()
    if not key:
        return None
    aliases = ACCOUNT_TYPE_FILTER_ALIASES.get(key)
    if aliases:
        return aliases
    return (key,)


def fetch_business_accounts(
    db: Session,
    business_id: int,
    account_type: Optional[str] = None,
    account_ids: Optional[List[int]] = None,
    account_codes_prefix: Optional[str] = None,
) -> List[Account]:
    query = db.query(Account).filter(
        (Account.business_id == None) | (Account.business_id == business_id)  # noqa: E711
    )
    type_filter = resolve_account_type_filter(account_type)
    if type_filter:
        if len(type_filter) == 1:
            query = query.filter(Account.account_type == type_filter[0])
        else:
            query = query.filter(Account.account_type.in_(type_filter))
    if account_ids:
        query = query.filter(Account.id.in_(account_ids))
    accounts = query.order_by(Account.code.asc()).all()
    if account_codes_prefix:
        prefix = str(account_codes_prefix).strip()
        accounts = [a for a in accounts if (a.code or "").startswith(prefix)]
    return accounts


def build_account_tree(accounts: List[Account]) -> Dict[int, Dict[str, Any]]:
    account_dict: Dict[int, Dict[str, Any]] = {}
    for acc in accounts:
        account_dict[acc.id] = {
            "id": acc.id,
            "code": acc.code,
            "name": acc.name,
            "account_type": acc.account_type,
            "parent_id": acc.parent_id,
            "children": [],
            "has_children": False,
        }
    for acc_id, acc_data in account_dict.items():
        parent_id = acc_data["parent_id"]
        if parent_id and parent_id in account_dict:
            account_dict[parent_id]["children"].append(acc_id)
            account_dict[parent_id]["has_children"] = True
    for acc_data in account_dict.values():
        acc_data["children"].sort(key=lambda cid: account_dict[cid]["code"])
    return account_dict


def get_root_account_ids(account_tree: Dict[int, Dict[str, Any]]) -> List[int]:
    """ریشه‌های درخت؛ حساب‌هایی که والدشان در مجموعه فیلترشده نیست نیز ریشه محسوب می‌شوند."""
    roots = [
        aid
        for aid, data in account_tree.items()
        if data["parent_id"] is None or data["parent_id"] not in account_tree
    ]
    roots.sort(key=lambda aid: account_tree[aid]["code"])
    return roots


def compute_leaf_balances(
    db: Session,
    business_id: int,
    account_ids: List[int],
    date_from_obj: date,
    date_to_obj: date,
    fiscal_year_id: int,
    currency_id: Optional[int] = None,
    project_id: Optional[int] = None,
    *,
    amounts_in_base: Optional[bool] = None,
) -> Dict[int, AccountBalance]:
    """مانده هر حساب برگ (بدون جمع‌زدن فرزندان).

    amounts_in_base:
      - True: جمع از debit_base/credit_base (با fallback به debit/credit)
      - False: جمع بومی debit/credit
      - None (پیش‌فرض): اگر currency_id مشخص باشد → بومی؛ وگرنه → پایه
        (جلوگیری از جمع خام چند ارز مختلف در حالت «همه ارزها»)
    """
    use_base = bool(amounts_in_base) if amounts_in_base is not None else (currency_id is None)

    debit_expr = (
        func.coalesce(DocumentLine.debit_base, DocumentLine.debit)
        if use_base
        else DocumentLine.debit
    )
    credit_expr = (
        func.coalesce(DocumentLine.credit_base, DocumentLine.credit)
        if use_base
        else DocumentLine.credit
    )

    balances: Dict[int, AccountBalance] = {
        acc_id: AccountBalance(Decimal(0), Decimal(0), Decimal(0), Decimal(0))
        for acc_id in account_ids
    }

    opening_balance_data: Dict[int, Dict[str, Decimal]] = {}
    try:
        ob_doc = _find_existing_ob_document(db, business_id, fiscal_year_id)
        if ob_doc:
            ob_lines_query = db.query(
                DocumentLine.account_id,
                func.coalesce(func.sum(debit_expr), 0).label("debit"),
                func.coalesce(func.sum(credit_expr), 0).label("credit"),
            ).filter(
                DocumentLine.document_id == ob_doc.id,
                DocumentLine.account_id.isnot(None),
            )
            if currency_id:
                ob_lines_query = ob_lines_query.join(
                    Document, DocumentLine.document_id == Document.id
                ).filter(Document.currency_id == currency_id)
            for result in ob_lines_query.group_by(DocumentLine.account_id).all():
                if result.account_id:
                    opening_balance_data[result.account_id] = {
                        "debit": Decimal(str(result.debit or 0)),
                        "credit": Decimal(str(result.credit or 0)),
                    }
    except Exception:
        pass

    date_before_from = date_from_obj - timedelta(days=1)

    opening_query = (
        db.query(
            DocumentLine.account_id,
            func.coalesce(func.sum(debit_expr), 0).label("total_debit"),
            func.coalesce(func.sum(credit_expr), 0).label("total_credit"),
        )
        .join(Document, DocumentLine.document_id == Document.id)
        .filter(
            and_(
                Document.business_id == business_id,
                Document.is_proforma == False,  # noqa: E712
                Document.document_type != "opening_balance",
                DocumentLine.account_id.isnot(None),
                DocumentLine.account_id.in_(account_ids),
                Document.document_date <= date_before_from,
                Document.fiscal_year_id == fiscal_year_id,
            )
        )
    )
    if currency_id:
        opening_query = opening_query.filter(Document.currency_id == currency_id)
    if project_id:
        opening_query = opening_query.filter(Document.project_id == project_id)

    period_query = (
        db.query(
            DocumentLine.account_id,
            func.coalesce(func.sum(debit_expr), 0).label("total_debit"),
            func.coalesce(func.sum(credit_expr), 0).label("total_credit"),
        )
        .join(Document, DocumentLine.document_id == Document.id)
        .filter(
            and_(
                Document.business_id == business_id,
                Document.is_proforma == False,  # noqa: E712
                DocumentLine.account_id.isnot(None),
                DocumentLine.account_id.in_(account_ids),
                Document.document_date >= date_from_obj,
                Document.document_date <= date_to_obj,
                Document.fiscal_year_id == fiscal_year_id,
            )
        )
    )
    if currency_id:
        period_query = period_query.filter(Document.currency_id == currency_id)
    if project_id:
        period_query = period_query.filter(Document.project_id == project_id)

    for acc_id in account_ids:
        if acc_id in opening_balance_data:
            balances[acc_id].opening_debit += opening_balance_data[acc_id]["debit"]
            balances[acc_id].opening_credit += opening_balance_data[acc_id]["credit"]

    for result in opening_query.group_by(DocumentLine.account_id).all():
        if result.account_id in balances:
            balances[result.account_id].opening_debit += Decimal(str(result.total_debit or 0))
            balances[result.account_id].opening_credit += Decimal(str(result.total_credit or 0))

    for result in period_query.group_by(DocumentLine.account_id).all():
        if result.account_id in balances:
            balances[result.account_id].period_debit += Decimal(str(result.total_debit or 0))
            balances[result.account_id].period_credit += Decimal(str(result.total_credit or 0))

    return balances


def rollup_account_balance(
    account_id: int,
    account_tree: Dict[int, Dict[str, Any]],
    leaf_balances: Dict[int, AccountBalance],
) -> AccountBalance:
    acc_data = account_tree[account_id]
    own = leaf_balances.get(
        account_id,
        AccountBalance(Decimal(0), Decimal(0), Decimal(0), Decimal(0)),
    )
    if not acc_data["has_children"]:
        return own

    total = AccountBalance(
        own.opening_debit,
        own.opening_credit,
        own.period_debit,
        own.period_credit,
    )
    for child_id in acc_data["children"]:
        child_bal = rollup_account_balance(child_id, account_tree, leaf_balances)
        total.opening_debit += child_bal.opening_debit
        total.opening_credit += child_bal.opening_credit
        total.period_debit += child_bal.period_debit
        total.period_credit += child_bal.period_credit
    return total


def balance_to_item_dict(
    account_id: int,
    account_tree: Dict[int, Dict[str, Any]],
    balance: AccountBalance,
    *,
    level: int = 0,
    has_children: bool = False,
    children: Optional[List[Dict[str, Any]]] = None,
) -> Dict[str, Any]:
    acc_data = account_tree[account_id]
    opening_debit, opening_credit = balance.split_opening()
    closing_debit, closing_credit = balance.split_closing()
    return {
        "account_id": account_id,
        "account_code": acc_data["code"],
        "account_name": acc_data["name"],
        "account_type": acc_data["account_type"],
        "level": level,
        "has_children": has_children,
        "children": children or [],
        "opening_debit": float(opening_debit),
        "opening_credit": float(opening_credit),
        "period_debit": float(balance.period_debit),
        "period_credit": float(balance.period_credit),
        "closing_debit": float(closing_debit),
        "closing_credit": float(closing_credit),
    }


def is_zero_balance_item(item: Dict[str, Any]) -> bool:
    keys = (
        "opening_debit",
        "opening_credit",
        "period_debit",
        "period_credit",
        "closing_debit",
        "closing_credit",
    )
    return all(float(item.get(k, 0) or 0) == 0 for k in keys)


def build_tree_items(
    account_tree: Dict[int, Dict[str, Any]],
    leaf_balances: Dict[int, AccountBalance],
    *,
    include_zero_balance: bool = False,
    max_depth: Optional[int] = None,
    parent_id: Optional[int] = None,
    level: int = 0,
) -> List[Dict[str, Any]]:
    if parent_id is None:
        account_ids = get_root_account_ids(account_tree)
    else:
        account_ids = account_tree[parent_id]["children"]

    items: List[Dict[str, Any]] = []
    for acc_id in account_ids:
        acc_data = account_tree[acc_id]
        balance = rollup_account_balance(acc_id, account_tree, leaf_balances)
        children: List[Dict[str, Any]] = []
        show_children = acc_data["has_children"] and (max_depth is None or level + 1 < max_depth)
        if show_children:
            children = build_tree_items(
                account_tree,
                leaf_balances,
                include_zero_balance=include_zero_balance,
                max_depth=max_depth,
                parent_id=acc_id,
                level=level + 1,
            )

        item = balance_to_item_dict(
            acc_id,
            account_tree,
            balance,
            level=level,
            has_children=bool(children) or acc_data["has_children"],
            children=children,
        )

        if not include_zero_balance:
            if is_zero_balance_item(item) and not children:
                continue
            if is_zero_balance_item(item) and children and not any(not is_zero_balance_item(c) for c in _flatten_items(children)):
                continue

        items.append(item)
    return items


def _flatten_items(items: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    flat: List[Dict[str, Any]] = []
    for item in items:
        flat.append(item)
        if item.get("children"):
            flat.extend(_flatten_items(item["children"]))
    return flat


def flatten_tree_at_level(
    tree_items: List[Dict[str, Any]],
    account_level: int,
) -> List[Dict[str, Any]]:
    """استخراج حساب‌ها در سطح مشخص (۱=گروه، ۲=کل، ۳=معین، ۴=تفصیل)."""
    target_depth = account_level - 1
    result: List[Dict[str, Any]] = []

    def walk(nodes: List[Dict[str, Any]]) -> None:
        for node in nodes:
            depth = int(node.get("level", 0))
            if account_level >= 4:
                if node.get("children"):
                    walk(node["children"])
                else:
                    row = dict(node)
                    row["children"] = []
                    result.append(row)
            elif depth == target_depth:
                row = dict(node)
                row["children"] = []
                row["has_children"] = bool(node.get("has_children"))
                result.append(row)
            elif depth < target_depth and node.get("children"):
                walk(node["children"])

    walk(tree_items)
    return result


def build_flat_leaf_items(
    account_tree: Dict[int, Dict[str, Any]],
    leaf_balances: Dict[int, AccountBalance],
    *,
    include_zero_balance: bool = False,
) -> List[Dict[str, Any]]:
    """لیست تخت همه حساب‌ها با مانده مستقیم (سطح تفصیل)."""
    items: List[Dict[str, Any]] = []
    for acc_id in sorted(account_tree.keys(), key=lambda aid: account_tree[aid]["code"]):
        acc_data = account_tree[acc_id]
        balance = leaf_balances.get(
            acc_id,
            AccountBalance(Decimal(0), Decimal(0), Decimal(0), Decimal(0)),
        )
        item = balance_to_item_dict(
            acc_id,
            account_tree,
            balance,
            level=0,
            has_children=acc_data["has_children"],
        )
        if not include_zero_balance and is_zero_balance_item(item):
            continue
        items.append(item)
    return items


def apply_column_mode(item: Dict[str, Any], column_mode: int) -> Dict[str, Any]:
    """فیلتر ستون‌ها بر اساس حالت ۲/۴/۶/۸ ستونی."""
    if column_mode not in COLUMN_MODES:
        column_mode = 8
    row = dict(item)
    if column_mode <= 2:
        for key in ("opening_debit", "opening_credit", "period_debit", "period_credit"):
            row.pop(key, None)
    elif column_mode <= 4:
        for key in ("opening_debit", "opening_credit"):
            row.pop(key, None)
    elif column_mode <= 6:
        pass
    return row


def apply_column_mode_to_tree(items: List[Dict[str, Any]], column_mode: int) -> List[Dict[str, Any]]:
    result = []
    for item in items:
        row = apply_column_mode(item, column_mode)
        if item.get("children"):
            row["children"] = apply_column_mode_to_tree(item["children"], column_mode)
        result.append(row)
    return result


def sum_balance_items(items: List[Dict[str, Any]]) -> Dict[str, Decimal]:
    totals = {
        "opening_debit": Decimal(0),
        "opening_credit": Decimal(0),
        "period_debit": Decimal(0),
        "period_credit": Decimal(0),
        "closing_debit": Decimal(0),
        "closing_credit": Decimal(0),
    }
    for item in items:
        for key in totals:
            totals[key] += Decimal(str(item.get(key, 0) or 0))
        if item.get("children"):
            child_totals = sum_balance_items(item["children"])
            for key in totals:
                totals[key] += child_totals[key]
    return totals


def sum_root_items_only(items: List[Dict[str, Any]]) -> Dict[str, Decimal]:
    totals = {
        "opening_debit": Decimal(0),
        "opening_credit": Decimal(0),
        "period_debit": Decimal(0),
        "period_credit": Decimal(0),
        "closing_debit": Decimal(0),
        "closing_credit": Decimal(0),
    }
    for item in items:
        for key in totals:
            totals[key] += Decimal(str(item.get(key, 0) or 0))
    return totals


def validate_trial_balance(totals: Dict[str, Decimal]) -> Dict[str, Any]:
    opening_diff = abs(totals["opening_debit"] - totals["opening_credit"])
    period_diff = abs(totals["period_debit"] - totals["period_credit"])
    closing_diff = abs(totals["closing_debit"] - totals["closing_credit"])
    balance_valid = (
        opening_diff <= BALANCE_TOLERANCE
        and period_diff <= BALANCE_TOLERANCE
        and closing_diff <= BALANCE_TOLERANCE
    )
    errors: List[str] = []
    if opening_diff > BALANCE_TOLERANCE:
        errors.append(f"تراز ابتدای دوره برقرار نیست: تفاوت = {float(opening_diff)}")
    if period_diff > BALANCE_TOLERANCE:
        errors.append(f"تراز گردش دوره برقرار نیست: تفاوت = {float(period_diff)}")
    if closing_diff > BALANCE_TOLERANCE:
        errors.append(f"تراز انتهای دوره برقرار نیست: تفاوت = {float(closing_diff)}")
    return {
        "balance_valid": balance_valid,
        "balance_error": " | ".join(errors) if errors else None,
        "opening_balance_diff": float(opening_diff),
        "period_balance_diff": float(period_diff),
        "closing_balance_diff": float(closing_diff),
    }


def paginate_items(items: List[Dict[str, Any]], skip: int, take: int) -> Dict[str, Any]:
    total = len(items)
    current_page = (skip // take) + 1 if take > 0 else 1
    total_pages = (total + take - 1) // take if take > 0 else 1
    return {
        "items": items[skip : skip + take],
        "pagination": {
            "total": total,
            "page": current_page,
            "per_page": take,
            "total_pages": total_pages,
            "has_next": current_page < total_pages,
            "has_prev": current_page > 1,
        },
    }
