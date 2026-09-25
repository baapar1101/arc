from __future__ import annotations

from decimal import Decimal
from typing import Any, Dict, List, Optional, Tuple

from sqlalchemy import and_
from sqlalchemy.orm import Session

from adapters.db.models.business import Business
from adapters.db.models.document import Document
from adapters.db.repositories.document_repository import DocumentRepository
from adapters.db.repositories.fiscal_year_repo import FiscalYearRepository
from app.core.responses import ApiError
from app.services.invoice_service import _get_fixed_account_by_code
from app.services.opening_balance_service import (
    _ensure_fiscal_year,
    _find_existing_ob_document,
    get_opening_balance,
    upsert_opening_balance,
)

_AUTO_BALANCE_DESCRIPTION = "بستن اختلاف تراز افتتاحیه"
_DEFAULT_EQUITY_ACCOUNT_CODES = ("30201", "30106", "30101")


def _count_other_fiscal_year_documents(db: Session, business_id: int, fiscal_year_id: int) -> int:
    return (
        db.query(Document)
        .filter(
            and_(
                Document.business_id == int(business_id),
                Document.fiscal_year_id == int(fiscal_year_id),
                Document.document_type != "opening_balance",
            )
        )
        .count()
    )


def _resolve_default_equity_account_id(db: Session) -> int:
    for code in _DEFAULT_EQUITY_ACCOUNT_CODES:
        try:
            return int(_get_fixed_account_by_code(db, code).id)
        except ApiError:
            continue
    raise ApiError(
        "EQUITY_ACCOUNT_NOT_FOUND",
        "حساب حقوق صاحبان سهام برای بستن خودکار تراز افتتاحیه یافت نشد",
        http_status=400,
    )


def _get_person_ob_account_id(db: Session, balance_type: str) -> int:
    code = "10401" if balance_type == "debit" else "20201"
    return int(_get_fixed_account_by_code(db, code).id)


def _extract_person_ob_line(doc: Optional[Dict[str, Any]], person_id: int) -> Optional[Dict[str, Any]]:
    if not doc:
        return None
    pid = int(person_id)
    for line in doc.get("lines") or []:
        if line.get("person_id") is None:
            continue
        if int(line.get("person_id")) != pid:
            continue
        debit = float(line.get("debit") or 0)
        credit = float(line.get("credit") or 0)
        if debit > 0:
            return {"amount": debit, "balance_type": "debit"}
        if credit > 0:
            return {"amount": credit, "balance_type": "credit"}
    return None


def _document_lines_to_upsert_inputs(doc: Dict[str, Any]) -> Tuple[List[Dict[str, Any]], List[Dict[str, Any]], Dict[str, Any]]:
    """تبدیل خطوط سند افتتاحیه موجود به ورودی upsert (بدون خط auto-balance)."""
    account_lines: List[Dict[str, Any]] = []
    inventory_lines: List[Dict[str, Any]] = []

    for line in doc.get("lines") or []:
        if line.get("product_id"):
            inventory_lines.append(
                {
                    "product_id": line.get("product_id"),
                    "quantity": line.get("quantity"),
                    "extra_info": dict(line.get("extra_info") or {}),
                    "description": line.get("description"),
                }
            )
            continue

        if line.get("bank_account_id") or line.get("cash_register_id") or line.get("petty_cash_id"):
            account_lines.append(
                {
                    "account_id": line.get("account_id"),
                    "bank_account_id": line.get("bank_account_id"),
                    "cash_register_id": line.get("cash_register_id"),
                    "petty_cash_id": line.get("petty_cash_id"),
                    "debit": line.get("debit", 0),
                    "credit": line.get("credit", 0),
                    "description": line.get("description"),
                }
            )
            continue

        if line.get("person_id"):
            account_lines.append(
                {
                    "account_id": line.get("account_id"),
                    "person_id": line.get("person_id"),
                    "debit": line.get("debit", 0),
                    "credit": line.get("credit", 0),
                    "description": line.get("description"),
                }
            )
            continue

        if line.get("account_id"):
            desc = str(line.get("description") or "")
            if _AUTO_BALANCE_DESCRIPTION in desc:
                continue
            account_lines.append(
                {
                    "account_id": line.get("account_id"),
                    "debit": line.get("debit", 0),
                    "credit": line.get("credit", 0),
                    "description": line.get("description"),
                }
            )

    extra = dict(doc.get("extra_info") or {})
    settings = {
        "auto_balance_to_equity": (
            doc.get("auto_balance_to_equity")
            if doc.get("auto_balance_to_equity") is not None
            else extra.get("auto_balance_to_equity", True)
        ),
        "equity_account_id": doc.get("equity_account_id") or extra.get("equity_account_id"),
        "inventory_account_id": doc.get("inventory_account_id") or extra.get("inventory_account_id"),
    }
    return account_lines, inventory_lines, settings


def _validate_ob_editable(db: Session, business_id: int, fiscal_year_id: Optional[int]) -> Dict[str, Any]:
    """بررسی امکان ویرایش سند افتتاحیه؛ در صورت عدم مجاز بودن ApiError."""
    fy_id, fy_start, _ = _ensure_fiscal_year(db, business_id, fiscal_year_id)
    existing = _find_existing_ob_document(db, business_id, fy_id)

    if existing and (existing.extra_info or {}).get("posted") is True:
        raise ApiError(
            "OPENING_BALANCE_POSTED",
            "سند تراز افتتاحیه نهایی شده و امکان تغییر مانده افتتاحیه وجود ندارد",
            http_status=409,
        )

    if _count_other_fiscal_year_documents(db, business_id, fy_id) > 0:
        raise ApiError(
            "PERSON_OPENING_BALANCE_NOT_ALLOWED",
            "به‌دلیل ثبت اسناد حسابداری در این سال مالی، امکان تغییر مانده افتتاحیه وجود ندارد. "
            "از فاکتور، دریافت/پرداخت یا سند دستی استفاده کنید.",
            http_status=409,
        )

    fy_repo = FiscalYearRepository(db)
    fy = fy_repo.get_by_id(fy_id)
    return {
        "fiscal_year_id": fy_id,
        "fiscal_year_title": fy.title if fy else None,
        "fiscal_year_start_date": fy_start.isoformat() if fy_start else None,
        "opening_balance_exists": existing is not None,
        "opening_balance_posted": bool(existing and (existing.extra_info or {}).get("posted")),
    }


def validate_person_opening_balance_allowed(
    db: Session,
    business_id: int,
    fiscal_year_id: Optional[int],
    *,
    person_id: Optional[int] = None,
    for_update: bool = False,
) -> Dict[str, Any]:
    """اعتبارسنجی امکان ثبت مانده افتتاحیه شخص؛ در صورت عدم مجاز بودن ApiError."""
    ctx = _validate_ob_editable(db, business_id, fiscal_year_id)

    if not for_update and person_id is not None:
        existing = _find_existing_ob_document(db, business_id, int(ctx["fiscal_year_id"]))
        if existing is not None:
            for line in existing.lines:
                if line.person_id is not None and int(line.person_id) == int(person_id):
                    raise ApiError(
                        "DUPLICATE_OPENING_BALANCE_PERSON",
                        "این شخص قبلاً در سند تراز افتتاحیه ثبت شده است",
                        http_status=400,
                    )

    return ctx


def get_person_opening_balance_eligibility(
    db: Session,
    business_id: int,
    fiscal_year_id: Optional[int],
    *,
    can_edit_opening_balance: bool,
    person_id: Optional[int] = None,
) -> Dict[str, Any]:
    """وضعیت نمایش/ثبت مانده افتتاحیه در فرم افزودن یا ویرایش شخص."""
    try:
        fy_id, _, _ = _ensure_fiscal_year(db, business_id, fiscal_year_id)
    except ApiError as exc:
        err_code = ""
        if isinstance(exc.detail, dict):
            err_code = str((exc.detail.get("error") or {}).get("code") or "")
        if err_code == "NO_CURRENT_FISCAL_YEAR":
            return {
                "eligible": False,
                "editable": False,
                "show_tab": False,
                "reason": "no_fiscal_year",
                "message": "سال مالی فعالی برای این کسب‌وکار یافت نشد",
                "can_edit_opening_balance": can_edit_opening_balance,
                "person_opening_balance": None,
                "has_opening_balance_line": False,
            }
        raise

    fy_repo = FiscalYearRepository(db)
    fy = fy_repo.get_by_id(fy_id)
    existing = _find_existing_ob_document(db, business_id, fy_id)
    posted = bool(existing and (existing.extra_info or {}).get("posted"))
    other_docs = _count_other_fiscal_year_documents(db, business_id, fy_id) > 0

    ob_doc = get_opening_balance(db, business_id, fy_id)
    person_line = _extract_person_ob_line(ob_doc, int(person_id)) if person_id is not None else None
    has_line = person_line is not None

    base = {
        "fiscal_year_id": fy_id,
        "fiscal_year_title": fy.title if fy else None,
        "opening_balance_exists": existing is not None,
        "opening_balance_posted": posted,
        "has_other_documents": other_docs,
        "can_edit_opening_balance": can_edit_opening_balance,
        "person_opening_balance": person_line,
        "has_opening_balance_line": has_line,
    }

    editable = False
    reason: Optional[str] = None
    message = ""

    if not can_edit_opening_balance:
        reason = "no_permission"
        message = "برای تغییر مانده افتتاحیه به دسترسی ویرایش تراز افتتاحیه نیاز است"
    elif posted:
        reason = "posted"
        message = "سند تراز افتتاحیه نهایی شده و مانده افتتاحیه قابل تغییر نیست"
    elif other_docs:
        reason = "other_documents"
        message = (
            "به‌دلیل ثبت اسناد دیگر در این سال مالی، مانده افتتاحیه قابل تغییر نیست. "
            "از فاکتور، دریافت/پرداخت یا سند دستی استفاده کنید"
        )
    else:
        editable = True
        message = (
            "مانده در سند تراز افتتاحیه سال مالی جاری ثبت می‌شود"
            if not has_line
            else "مانده افتتاحیه قابل ویرایش است"
        )

    if person_id is None:
        show_tab = editable
    else:
        show_tab = has_line or editable

    return {
        **base,
        "eligible": editable,
        "editable": editable,
        "show_tab": show_tab,
        "reason": reason,
        "message": message,
    }


def _build_ob_payload_with_person_line(
    db: Session,
    business_id: int,
    fy_id: int,
    person_id: int,
    *,
    amount: Optional[float],
    balance_type: str,
    person_name: str,
    remove_line: bool,
) -> Dict[str, Any]:
    existing_doc = get_opening_balance(db, business_id, fy_id)
    _, fy_start, _ = _ensure_fiscal_year(db, business_id, fy_id)

    if existing_doc:
        account_lines, inventory_lines, settings = _document_lines_to_upsert_inputs(existing_doc)
        currency_id = existing_doc.get("currency_id")
        document_date = existing_doc.get("document_date")
    else:
        account_lines = []
        inventory_lines = []
        settings = {
            "auto_balance_to_equity": True,
            "equity_account_id": None,
            "inventory_account_id": None,
        }
        business = db.query(Business).filter(Business.id == int(business_id)).first()
        currency_id = getattr(business, "default_currency_id", None) if business else None
        if not currency_id:
            raise ApiError("CURRENCY_REQUIRED", "ارز پیش‌فرض کسب‌وکار تنظیم نشده است", http_status=400)
        document_date = fy_start

    account_lines = [
        ln for ln in account_lines if ln.get("person_id") is None or int(ln["person_id"]) != int(person_id)
    ]

    if not remove_line:
        balance_type_norm = str(balance_type or "").strip().lower()
        if balance_type_norm not in ("debit", "credit"):
            raise ApiError(
                "INVALID_OPENING_BALANCE_TYPE",
                "نوع مانده افتتاحیه باید debit یا credit باشد",
                http_status=400,
            )
        amount_dec = Decimal(str(amount or 0))
        if amount_dec <= 0:
            raise ApiError(
                "INVALID_OPENING_BALANCE_AMOUNT",
                "مبلغ مانده افتتاحیه باید بزرگتر از صفر باشد",
                http_status=400,
            )
        account_id = _get_person_ob_account_id(db, balance_type_norm)
        if balance_type_norm == "debit":
            account_lines.append(
                {
                    "account_id": account_id,
                    "person_id": int(person_id),
                    "debit": float(amount_dec),
                    "credit": 0.0,
                    "description": f"مانده افتتاحیه - {person_name}",
                }
            )
        else:
            account_lines.append(
                {
                    "account_id": account_id,
                    "person_id": int(person_id),
                    "debit": 0.0,
                    "credit": float(amount_dec),
                    "description": f"مانده افتتاحیه - {person_name}",
                }
            )

    auto_balance = bool(settings.get("auto_balance_to_equity", True))
    equity_account_id = settings.get("equity_account_id")
    if auto_balance and not equity_account_id and account_lines:
        equity_account_id = _resolve_default_equity_account_id(db)

    payload: Dict[str, Any] = {
        "fiscal_year_id": fy_id,
        "currency_id": int(currency_id),
        "document_date": document_date,
        "account_lines": account_lines,
        "inventory_lines": inventory_lines,
        "auto_balance_to_equity": auto_balance,
    }
    if settings.get("inventory_account_id"):
        payload["inventory_account_id"] = int(settings["inventory_account_id"])
    if equity_account_id:
        payload["equity_account_id"] = int(equity_account_id)
    return payload


def upsert_person_opening_balance_line(
    db: Session,
    business_id: int,
    user_id: int,
    person_id: int,
    *,
    amount: Optional[float],
    balance_type: str,
    fiscal_year_id: Optional[int],
    person_name: str,
    remove_line: bool = False,
) -> Dict[str, Any]:
    """افزودن، به‌روزرسانی یا حذف خط مانده شخص در سند تراز افتتاحیه."""
    ctx = validate_person_opening_balance_allowed(
        db, business_id, fiscal_year_id, person_id=person_id, for_update=True
    )
    fy_id = int(ctx["fiscal_year_id"])

    if remove_line:
        existing_doc = get_opening_balance(db, business_id, fy_id)
        if _extract_person_ob_line(existing_doc, person_id) is None:
            return existing_doc or {}

    payload = _build_ob_payload_with_person_line(
        db,
        business_id,
        fy_id,
        person_id,
        amount=amount,
        balance_type=balance_type,
        person_name=person_name,
        remove_line=remove_line,
    )
    return upsert_opening_balance(db, business_id, int(user_id), payload)


def append_person_line_to_opening_balance(
    db: Session,
    business_id: int,
    user_id: int,
    person_id: int,
    *,
    amount: float,
    balance_type: str,
    fiscal_year_id: Optional[int],
    person_name: str,
) -> Dict[str, Any]:
    """افزودن خط مانده شخص به سند تراز افتتاحیه (ایجاد شخص جدید)."""
    validate_person_opening_balance_allowed(db, business_id, fiscal_year_id, person_id=person_id)
    return upsert_person_opening_balance_line(
        db,
        business_id,
        user_id,
        person_id,
        amount=amount,
        balance_type=balance_type,
        fiscal_year_id=fiscal_year_id,
        person_name=person_name,
        remove_line=False,
    )


def create_person_with_opening_balance(
    db: Session,
    business_id: int,
    user_id: int,
    person_data: Any,
    *,
    create_person_fn: Any,
    delete_person_fn: Any,
) -> Dict[str, Any]:
    """ایجاد شخص و در صورت درخواست، ثبت مانده در سند افتتاحیه (با بازگشت در صورت خطا)."""
    ob = getattr(person_data, "opening_balance", None)

    if ob is not None and not getattr(ob, "clear", False):
        validate_person_opening_balance_allowed(db, business_id, ob.fiscal_year_id, person_id=None)

    result = create_person_fn(db, business_id, person_data)
    person_id = int(result["data"]["id"])
    person_name = str(result["data"].get("alias_name") or "")

    if ob is None:
        return result

    try:
        if getattr(ob, "clear", False):
            raise ApiError("INVALID_OPENING_BALANCE", "clear در ایجاد شخص مجاز نیست", http_status=400)
        ob_doc = append_person_line_to_opening_balance(
            db,
            business_id,
            user_id,
            person_id,
            amount=float(ob.amount),
            balance_type=ob.balance_type,
            fiscal_year_id=ob.fiscal_year_id,
            person_name=person_name,
        )
    except Exception:
        success, _ = delete_person_fn(db, person_id, business_id)
        if not success:
            db.rollback()
        raise

    data = dict(result["data"])
    data["opening_balance_document_id"] = ob_doc.get("id")
    data["opening_balance_applied"] = True
    return {
        "message": "شخص ایجاد شد و مانده افتتاحیه در سند تراز افتتاحیه ثبت شد",
        "data": data,
    }


def update_person_with_opening_balance(
    db: Session,
    business_id: int,
    user_id: int,
    person_id: int,
    person_data: Any,
    *,
    update_person_fn: Any,
) -> Dict[str, Any]:
    """ویرایش شخص و در صورت درخواست، به‌روزرسانی مانده در سند افتتاحیه."""
    ob = getattr(person_data, "opening_balance", None)
    result = update_person_fn(db, person_id, business_id, person_data)
    if not result:
        return {}

    if ob is None:
        return result

    person_name = str((result.get("data") or {}).get("alias_name") or "")
    if getattr(ob, "clear", False):
        upsert_person_opening_balance_line(
            db,
            business_id,
            user_id,
            person_id,
            amount=None,
            balance_type=ob.balance_type,
            fiscal_year_id=ob.fiscal_year_id,
            person_name=person_name,
            remove_line=True,
        )
        msg = "شخص ویرایش شد و مانده افتتاحیه از سند تراز افتتاحیه حذف شد"
    else:
        upsert_person_opening_balance_line(
            db,
            business_id,
            user_id,
            person_id,
            amount=float(ob.amount),
            balance_type=ob.balance_type,
            fiscal_year_id=ob.fiscal_year_id,
            person_name=person_name,
            remove_line=False,
        )
        msg = "شخص ویرایش شد و مانده افتتاحیه در سند تراز افتتاحیه به‌روزرسانی شد"

    data = dict(result.get("data") or {})
    data["opening_balance_applied"] = True
    return {"message": msg, "data": data}
