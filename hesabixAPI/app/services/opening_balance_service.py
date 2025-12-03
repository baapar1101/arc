from __future__ import annotations

from typing import Any, Dict, List, Optional, Tuple
from datetime import date
from decimal import Decimal

from sqlalchemy.orm import Session

from adapters.db.repositories.document_repository import DocumentRepository
from adapters.db.repositories.fiscal_year_repo import FiscalYearRepository
from adapters.db.models.document import Document
from app.core.responses import ApiError


def _ensure_fiscal_year(db: Session, business_id: int, fiscal_year_id: Optional[int]) -> Tuple[int, date]:
    fy_repo = FiscalYearRepository(db)
    fiscal_year = None
    if fiscal_year_id:
        fiscal_year = fy_repo.get_by_id(int(fiscal_year_id))
        if not fiscal_year or int(fiscal_year.business_id) != int(business_id):
            raise ApiError("FISCAL_YEAR_NOT_FOUND", "سال مالی پیدا نشد یا متعلق به این کسب‌وکار نیست", http_status=404)
    else:
        fiscal_year = fy_repo.get_current_for_business(business_id)
        if not fiscal_year:
            raise ApiError("NO_CURRENT_FISCAL_YEAR", "سال مالی فعالی برای این کسب‌وکار یافت نشد", http_status=400)
    return int(fiscal_year.id), fiscal_year.start_date


def _find_existing_ob_document(db: Session, business_id: int, fiscal_year_id: int) -> Optional[Document]:
    from sqlalchemy import and_
    return (
        db.query(Document)
        .filter(
            and_(
                Document.business_id == int(business_id),
                Document.fiscal_year_id == int(fiscal_year_id),
                Document.document_type == "opening_balance",
            )
        )
        .order_by(Document.id.desc())
        .first()
    )


def get_opening_balance(
    db: Session,
    business_id: int,
    fiscal_year_id: Optional[int],
) -> Optional[Dict[str, Any]]:
    fy_id, _ = _ensure_fiscal_year(db, business_id, fiscal_year_id)
    existing = _find_existing_ob_document(db, business_id, fy_id)
    if not existing:
        return None
    repo = DocumentRepository(db)
    return repo.to_dict_with_lines(existing)


def upsert_opening_balance(
    db: Session,
    business_id: int,
    user_id: int,
    data: Dict[str, Any],
) -> Dict[str, Any]:
    repo = DocumentRepository(db)
    fy_id, fy_start_date = _ensure_fiscal_year(db, business_id, data.get("fiscal_year_id"))

    document_date = data.get("document_date") or fy_start_date
    currency_id = data.get("currency_id")
    if not currency_id:
        raise ApiError("CURRENCY_REQUIRED", "currency_id الزامی است", http_status=400)

    account_lines: List[Dict[str, Any]] = list(data.get("account_lines") or [])
    inventory_lines: List[Dict[str, Any]] = list(data.get("inventory_lines") or [])
    inventory_account_id: Optional[int] = data.get("inventory_account_id")
    auto_balance_to_equity: bool = bool(data.get("auto_balance_to_equity", False))
    equity_account_id: Optional[int] = data.get("equity_account_id")

    # Build document lines
    lines: List[Dict[str, Any]] = []

    def _norm_amount(v: Any) -> Decimal:
        try:
            return Decimal(str(v or 0))
        except Exception:
            return Decimal(0)

    # 1) Account/person/bank/cash/petty-cash lines
    for ln in account_lines:
        debit = _norm_amount(ln.get("debit"))
        credit = _norm_amount(ln.get("credit"))
        if debit <= 0 and credit <= 0:
            continue
        lines.append(
            {
                "account_id": ln.get("account_id"),
                "person_id": ln.get("person_id"),
                "bank_account_id": ln.get("bank_account_id"),
                "cash_register_id": ln.get("cash_register_id"),
                "petty_cash_id": ln.get("petty_cash_id"),
                "debit": float(debit),
                "credit": float(credit),
                "description": ln.get("description"),
                "extra_info": ln.get("extra_info"),
            }
        )

    # 2) Inventory lines (movement=in) + total valuation
    inventory_total_value = Decimal(0)
    for inv in inventory_lines:
        qty = _norm_amount(inv.get("quantity"))
        if qty <= 0:
            continue
        info = dict(inv.get("extra_info") or {})
        info.setdefault("movement", "in")
        if info.get("movement") != "in":
            info["movement"] = "in"
        if info.get("warehouse_id") is None:
            raise ApiError("WAREHOUSE_REQUIRED", "warehouse_id برای خطوط موجودی الزامی است", http_status=400)
        cost_price = _norm_amount(info.get("cost_price"))
        if cost_price > 0:
            inventory_total_value += qty * cost_price
        lines.append(
            {
                "product_id": int(inv.get("product_id")),
                "quantity": float(qty),
                "debit": 0.0,
                "credit": 0.0,
                "description": inv.get("description"),
                "extra_info": info,
            }
        )

    if inventory_lines:
        if not inventory_account_id:
            raise ApiError(
                "INVENTORY_ACCOUNT_REQUIRED",
                "inventory_account_id برای ثبت موجودی الزامی است",
                http_status=400,
            )
        if inventory_total_value > 0:
            lines.append(
                {
                    "account_id": int(inventory_account_id),
                    "debit": float(inventory_total_value),
                    "credit": 0.0,
                    "description": "موجودی ابتدای دوره",
                }
            )

    # Auto-balance difference to equity
    if auto_balance_to_equity:
        total_debit = sum(Decimal(str(line.get("debit", 0) or 0)) for line in lines)
        total_credit = sum(Decimal(str(line.get("credit", 0) or 0)) for line in lines)
        diff = total_debit - total_credit
        tolerance = Decimal("0.01")
        if abs(diff) > tolerance:
            if not equity_account_id:
                raise ApiError(
                    "EQUITY_ACCOUNT_REQUIRED",
                    "برای بستن خودکار اختلاف، انتخاب حساب حقوق صاحبان سهام الزامی است",
                    http_status=400,
                )
            if diff > 0:
                lines.append(
                    {
                        "account_id": int(equity_account_id),
                        "debit": 0.0,
                        "credit": float(diff),
                        "description": "بستن اختلاف تراز افتتاحیه",
                    }
                )
            else:
                lines.append(
                    {
                        "account_id": int(equity_account_id),
                        "debit": float(-diff),
                        "credit": 0.0,
                        "description": "بستن اختلاف تراز افتتاحیه",
                    }
                )

    # Validate balance
    is_valid, err = repo.validate_document_balance(lines)
    if not is_valid:
        raise ApiError("INVALID_DOCUMENT", err, http_status=400)

    # Upsert
    existing = _find_existing_ob_document(db, business_id, fy_id)
    document_payload = {
        "code": (existing.code if existing and existing.code else repo.generate_document_code(business_id, "opening_balance")),
        "business_id": int(business_id),
        "fiscal_year_id": int(fy_id),
        "currency_id": int(currency_id),
        "created_by_user_id": int(user_id),
        "document_date": document_date,
        "document_type": "opening_balance",
        "is_proforma": False,
        "description": data.get("description"),
        "extra_info": data.get("extra_info") or {},
        "lines": lines,
    }

    if existing:
        updated = repo.update_document(existing.id, document_payload)
        if not updated:
            raise ApiError("UPDATE_FAILED", "ویرایش سند تراز افتتاحیه ناموفق بود", http_status=500)
        return repo.get_document_details(updated.id) or {}
    else:
        created = repo.create_document(document_payload)
        return repo.get_document_details(created.id) or {}


def preview_opening_balance(
    db: Session,
    business_id: int,
    data: Dict[str, Any],
) -> Dict[str, Any]:
    """پیش‌نمایش تراز افتتاحیه بدون ذخیره"""
    repo = DocumentRepository(db)
    fy_id, fy_start_date = _ensure_fiscal_year(db, business_id, data.get("fiscal_year_id"))

    document_date = data.get("document_date") or fy_start_date
    currency_id = data.get("currency_id")
    if not currency_id:
        raise ApiError("CURRENCY_REQUIRED", "currency_id الزامی است", http_status=400)

    account_lines: List[Dict[str, Any]] = list(data.get("account_lines") or [])
    inventory_lines: List[Dict[str, Any]] = list(data.get("inventory_lines") or [])
    inventory_account_id: Optional[int] = data.get("inventory_account_id")
    auto_balance_to_equity: bool = bool(data.get("auto_balance_to_equity", False))
    equity_account_id: Optional[int] = data.get("equity_account_id")

    # Build document lines (بدون ذخیره)
    lines: List[Dict[str, Any]] = []

    def _norm_amount(v: Any) -> Decimal:
        try:
            return Decimal(str(v or 0))
        except Exception:
            return Decimal(0)

    # 1) Account/person/bank/cash/petty-cash lines
    for ln in account_lines:
        debit = _norm_amount(ln.get("debit"))
        credit = _norm_amount(ln.get("credit"))
        if debit <= 0 and credit <= 0:
            continue
        lines.append(
            {
                "account_id": ln.get("account_id"),
                "person_id": ln.get("person_id"),
                "bank_account_id": ln.get("bank_account_id"),
                "cash_register_id": ln.get("cash_register_id"),
                "petty_cash_id": ln.get("petty_cash_id"),
                "debit": float(debit),
                "credit": float(credit),
                "description": ln.get("description"),
                "extra_info": ln.get("extra_info"),
            }
        )

    # 2) Inventory lines (movement=in) + total valuation
    inventory_total_value = Decimal(0)
    for inv in inventory_lines:
        qty = _norm_amount(inv.get("quantity"))
        if qty <= 0:
            continue
        info = dict(inv.get("extra_info") or {})
        info.setdefault("movement", "in")
        if info.get("movement") != "in":
            info["movement"] = "in"
        if info.get("warehouse_id") is None:
            raise ApiError("WAREHOUSE_REQUIRED", "warehouse_id برای خطوط موجودی الزامی است", http_status=400)
        cost_price = _norm_amount(info.get("cost_price"))
        if cost_price > 0:
            inventory_total_value += qty * cost_price
        lines.append(
            {
                "product_id": int(inv.get("product_id")),
                "quantity": float(qty),
                "debit": 0.0,
                "credit": 0.0,
                "description": inv.get("description"),
                "extra_info": info,
            }
        )

    if inventory_lines:
        if not inventory_account_id:
            raise ApiError(
                "INVENTORY_ACCOUNT_REQUIRED",
                "inventory_account_id برای ثبت موجودی الزامی است",
                http_status=400,
            )
        if inventory_total_value > 0:
            lines.append(
                {
                    "account_id": int(inventory_account_id),
                    "debit": float(inventory_total_value),
                    "credit": 0.0,
                    "description": "موجودی ابتدای دوره",
                }
            )

    # Auto-balance difference to equity
    if auto_balance_to_equity:
        total_debit = sum(Decimal(str(line.get("debit", 0) or 0)) for line in lines)
        total_credit = sum(Decimal(str(line.get("credit", 0) or 0)) for line in lines)
        diff = total_debit - total_credit
        tolerance = Decimal("0.01")
        if abs(diff) > tolerance:
            if not equity_account_id:
                raise ApiError(
                    "EQUITY_ACCOUNT_REQUIRED",
                    "برای بستن خودکار اختلاف، انتخاب حساب حقوق صاحبان سهام الزامی است",
                    http_status=400,
                )
            if diff > 0:
                lines.append(
                    {
                        "account_id": int(equity_account_id),
                        "debit": 0.0,
                        "credit": float(diff),
                        "description": "بستن اختلاف تراز افتتاحیه",
                    }
                )
            else:
                lines.append(
                    {
                        "account_id": int(equity_account_id),
                        "debit": float(-diff),
                        "credit": 0.0,
                        "description": "بستن اختلاف تراز افتتاحیه",
                    }
                )

    # Validate balance
    is_valid, err = repo.validate_document_balance(lines)
    if not is_valid:
        raise ApiError("INVALID_DOCUMENT", err, http_status=400)

    # محاسبه مجموع‌ها
    total_debit = sum(float(line.get("debit", 0) or 0) for line in lines)
    total_credit = sum(float(line.get("credit", 0) or 0) for line in lines)

    return {
        "fiscal_year_id": fy_id,
        "document_date": document_date,
        "currency_id": currency_id,
        "lines": lines,
        "total_debit": total_debit,
        "total_credit": total_credit,
        "balance_diff": total_debit - total_credit,
        "is_balanced": abs(total_debit - total_credit) <= 0.01,
        "lines_count": len(lines),
        "inventory_account_id": inventory_account_id,
        "equity_account_id": equity_account_id,
        "auto_balance_to_equity": auto_balance_to_equity,
    }


def post_opening_balance(
    db: Session,
    business_id: int,
    user_id: int,
    fiscal_year_id: Optional[int],
) -> Dict[str, Any]:
    fy_id, _ = _ensure_fiscal_year(db, business_id, fiscal_year_id)
    existing = _find_existing_ob_document(db, business_id, fy_id)
    if not existing:
        raise ApiError("OPENING_BALANCE_NOT_FOUND", "سند تراز افتتاحیه برای این سال مالی یافت نشد", http_status=404)

    if (existing.extra_info or {}).get("posted") is True:
        return DocumentRepository(db).to_dict_with_lines(existing)

    payload = {
        "extra_info": {**(existing.extra_info or {}), "posted": True, "posted_by": int(user_id)},
    }
    repo = DocumentRepository(db)
    updated = repo.update_document(existing.id, payload)
    if not updated:
        raise ApiError("POST_FAILED", "نهایی‌سازی تراز افتتاحیه ناموفق بود", http_status=500)
    return repo.get_document_details(updated.id) or {}


