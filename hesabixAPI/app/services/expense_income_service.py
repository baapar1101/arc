"""
سرویس هزینه و درآمد (Expense & Income)

این سرویس ثبت اسناد «هزینه/درآمد» را با چند سطر حساب و چند سطر طرف‌حساب پشتیبانی می‌کند.
الگوی پیاده‌سازی بر اساس سرویس دریافت/پرداخت است.
"""

from __future__ import annotations

from typing import Any, Dict, List, Optional
from datetime import datetime, date
from decimal import Decimal
import logging

from sqlalchemy.orm import Session
from sqlalchemy import and_, or_

from adapters.db.models.document import Document
from adapters.db.models.document_line import DocumentLine
from adapters.db.models.account import Account
from adapters.db.models.currency import Currency
from adapters.db.models.fiscal_year import FiscalYear
from adapters.db.models.user import User
from app.core.responses import ApiError


logger = logging.getLogger(__name__)


# نوع‌های سند
DOCUMENT_TYPE_EXPENSE = "expense"
DOCUMENT_TYPE_INCOME = "income"


def _parse_iso_date(dt: str | datetime | date) -> date:
    if isinstance(dt, date) and not isinstance(dt, datetime):
        return dt
    if isinstance(dt, datetime):
        return dt.date()
    try:
        return datetime.fromisoformat(str(dt)).date()
    except Exception:
        return datetime.utcnow().date()


def _get_fixed_account_by_code(db: Session, account_code: str) -> Account:
    account = db.query(Account).filter(Account.code == str(account_code)).first()
    if not account:
        raise ApiError("ACCOUNT_NOT_FOUND", f"Account with code {account_code} not found", http_status=404)
    return account


def _get_business_fiscal_year(db: Session, business_id: int) -> FiscalYear:
    fy = db.query(FiscalYear).filter(
        and_(FiscalYear.business_id == business_id, FiscalYear.is_closed == False)  # noqa: E712
    ).order_by(FiscalYear.start_date.desc()).first()
    if not fy:
        raise ApiError("FISCAL_YEAR_NOT_FOUND", "Active fiscal year not found", http_status=404)
    return fy


def create_expense_income(
    db: Session,
    business_id: int,
    user_id: int,
    data: Dict[str, Any],
) -> Dict[str, Any]:
    """
    ایجاد سند هزینه/درآمد با چند سطر حساب و چند سطر طرف‌حساب

    data = {
      "document_type": "expense" | "income",
      "document_date": "2025-10-20",
      "currency_id": 1,
      "description": str?,
      "item_lines": [  # سطرهای حساب‌های هزینه/درآمد
        {"account_id": 123, "amount": 100000, "description": str?},
      ],
      "counterparty_lines": [  # سطرهای طرف‌حساب (بانک/صندوق/شخص/چک ...)
        {
          "transaction_type": "bank" | "cash_register" | "petty_cash" | "check" | "person",
          "amount": 100000,
          "transaction_date": "2025-10-20T10:00:00",
          "description": str?,
          "commission": float?,  # اختیاری
          # فیلدهای اختیاری متناسب با نوع
          "bank_id": int?, "bank_name": str?,
          "cash_register_id": int?, "cash_register_name": str?,
          "petty_cash_id": int?, "petty_cash_name": str?,
          "check_id": int?, "check_number": str?,
          "person_id": int?, "person_name": str?,
        }
      ]
    }
    """
    document_type = str(data.get("document_type", "")).lower()
    if document_type not in (DOCUMENT_TYPE_EXPENSE, DOCUMENT_TYPE_INCOME):
        raise ApiError("INVALID_DOCUMENT_TYPE", "document_type must be 'expense' or 'income'", http_status=400)

    is_income = document_type == DOCUMENT_TYPE_INCOME

    # تاریخ
    document_date = _parse_iso_date(data.get("document_date", datetime.utcnow()))

    # ارز
    currency_id = data.get("currency_id")
    if not currency_id:
        raise ApiError("CURRENCY_REQUIRED", "currency_id is required", http_status=400)
    currency = db.query(Currency).filter(Currency.id == int(currency_id)).first()
    if not currency:
        raise ApiError("CURRENCY_NOT_FOUND", "Currency not found", http_status=404)

    # سال مالی فعال
    fiscal_year = _get_business_fiscal_year(db, business_id)

    # اعتبارسنجی خطوط
    item_lines: List[Dict[str, Any]] = list(data.get("item_lines") or [])
    counterparty_lines: List[Dict[str, Any]] = list(data.get("counterparty_lines") or [])
    if not item_lines:
        raise ApiError("LINES_REQUIRED", "item_lines is required", http_status=400)
    if not counterparty_lines:
        raise ApiError("LINES_REQUIRED", "counterparty_lines is required", http_status=400)

    sum_items = Decimal(0)
    for idx, line in enumerate(item_lines):
        if not line.get("account_id"):
            raise ApiError("ACCOUNT_REQUIRED", f"item_lines[{idx}].account_id is required", http_status=400)
        amount = Decimal(str(line.get("amount", 0)))
        if amount <= 0:
            raise ApiError("AMOUNT_INVALID", f"item_lines[{idx}].amount must be > 0", http_status=400)
        sum_items += amount

    sum_counterparties = Decimal(0)
    for idx, line in enumerate(counterparty_lines):
        amount = Decimal(str(line.get("amount", 0)))
        if amount <= 0:
            raise ApiError("AMOUNT_INVALID", f"counterparty_lines[{idx}].amount must be > 0", http_status=400)
        sum_counterparties += amount

    if sum_items != sum_counterparties:
        raise ApiError("LINES_NOT_BALANCED", "Sum of items and counterparties must be equal", http_status=400)

    # ایجاد سند
    user = db.query(User).filter(User.id == int(user_id)).first()
    if not user:
        raise ApiError("USER_NOT_FOUND", "User not found", http_status=404)

    # کد سند ساده: EI-YYYYMMDD-<rand>
    code = f"EI-{document_date.strftime('%Y%m%d')}-{int(datetime.utcnow().timestamp())%100000}"

    document = Document(
        code=code,
        business_id=business_id,
        fiscal_year_id=fiscal_year.id,
        currency_id=int(currency_id),
        created_by_user_id=int(user_id),
        document_date=document_date,
        document_type=document_type,
        is_proforma=False,
        description=(data.get("description") or None),
        extra_info=(data.get("extra_info") if isinstance(data.get("extra_info"), dict) else None),
    )
    db.add(document)
    db.flush()

    # سطرهای حساب‌های هزینه/درآمد
    for line in item_lines:
        account = db.query(Account).filter(
            and_(
                Account.id == int(line.get("account_id")),
                or_(Account.business_id == business_id, Account.business_id == None),  # noqa: E711
            )
        ).first()
        if not account:
            raise ApiError("ACCOUNT_NOT_FOUND", "Item account not found", http_status=404)

        amount = Decimal(str(line.get("amount", 0)))
        description = (line.get("description") or "").strip() or None

        debit_amount = amount if not is_income else Decimal(0)
        credit_amount = amount if is_income else Decimal(0)

        db.add(DocumentLine(
            document_id=document.id,
            account_id=account.id,
            debit=debit_amount,
            credit=credit_amount,
            description=description,
        ))

    # سطرهای طرف‌حساب (بانک/صندوق/شخص/چک/تنخواه)
    for line in counterparty_lines:
        amount = Decimal(str(line.get("amount", 0)))
        description = (line.get("description") or "").strip() or None
        transaction_type: Optional[str] = line.get("transaction_type")

        # انتخاب حساب طرف‌حساب
        account: Optional[Account] = None
        if transaction_type == "bank":
            account = _get_fixed_account_by_code(db, "10203")
        elif transaction_type == "cash_register":
            account = _get_fixed_account_by_code(db, "10202")
        elif transaction_type == "petty_cash":
            account = _get_fixed_account_by_code(db, "10201")
        elif transaction_type == "check":
            # برای چک‌ها از کدهای اسناد دریافتنی/پرداختنی استفاده شود
            account = _get_fixed_account_by_code(db, "10403" if is_income else "20202")
        elif transaction_type == "person":
            # پرداخت/دریافت با شخص عمومی پرداختنی
            account = _get_fixed_account_by_code(db, "20201")
        elif line.get("account_id"):
            account = db.query(Account).filter(
                and_(
                    Account.id == int(line.get("account_id")),
                    or_(Account.business_id == business_id, Account.business_id == None),  # noqa: E711
                )
            ).first()
        if not account:
            raise ApiError("ACCOUNT_NOT_FOUND", "Account not found for counterparty line", http_status=404)

        extra_info: Dict[str, Any] = {}
        if transaction_type:
            extra_info["transaction_type"] = transaction_type
        if line.get("transaction_date"):
            extra_info["transaction_date"] = line.get("transaction_date")
        if line.get("commission"):
            extra_info["commission"] = float(line.get("commission"))
        if transaction_type == "bank":
            if line.get("bank_id"):
                extra_info["bank_id"] = line.get("bank_id")
            if line.get("bank_name"):
                extra_info["bank_name"] = line.get("bank_name")
        elif transaction_type == "cash_register":
            if line.get("cash_register_id"):
                extra_info["cash_register_id"] = line.get("cash_register_id")
            if line.get("cash_register_name"):
                extra_info["cash_register_name"] = line.get("cash_register_name")
        elif transaction_type == "petty_cash":
            if line.get("petty_cash_id"):
                extra_info["petty_cash_id"] = line.get("petty_cash_id")
            if line.get("petty_cash_name"):
                extra_info["petty_cash_name"] = line.get("petty_cash_name")
        elif transaction_type == "check":
            if line.get("check_id"):
                extra_info["check_id"] = line.get("check_id")
            if line.get("check_number"):
                extra_info["check_number"] = line.get("check_number")
        elif transaction_type == "person":
            if line.get("person_id"):
                extra_info["person_id"] = line.get("person_id")
            if line.get("person_name"):
                extra_info["person_name"] = line.get("person_name")

        debit_amount = amount if is_income else Decimal(0)
        credit_amount = amount if not is_income else Decimal(0)

        db.add(DocumentLine(
            document_id=document.id,
            account_id=account.id,
            person_id=(int(line["person_id"]) if transaction_type == "person" and line.get("person_id") else None),
            bank_account_id=(int(line["bank_id"]) if transaction_type == "bank" and line.get("bank_id") else None),
            cash_register_id=line.get("cash_register_id"),
            petty_cash_id=line.get("petty_cash_id"),
            check_id=line.get("check_id"),
            debit=debit_amount,
            credit=credit_amount,
            description=description,
            extra_info=extra_info or None,
        ))

    # توجه: خطوط کارمزد در این نسخه پیاده‌سازی نمی‌شود (می‌توان مشابه سرویس دریافت/پرداخت اضافه کرد)

    db.commit()
    db.refresh(document)
    return document_to_dict(db, document)


def document_to_dict(db: Session, document: Document) -> Dict[str, Any]:
    lines = db.query(DocumentLine).filter(DocumentLine.document_id == document.id).all()
    items: List[Dict[str, Any]] = []
    counterparties: List[Dict[str, Any]] = []
    for ln in lines:
        account = db.query(Account).filter(Account.id == ln.account_id).first()
        row = {
            "id": ln.id,
            "account_id": ln.account_id,
            "account_name": account.name if account else None,
            "debit": float(ln.debit or 0),
            "credit": float(ln.credit or 0),
            "description": ln.description,
            "extra_info": ln.extra_info,
            "person_id": ln.person_id,
            "bank_account_id": ln.bank_account_id,
            "cash_register_id": ln.cash_register_id,
            "petty_cash_id": ln.petty_cash_id,
            "check_id": ln.check_id,
        }
        # ساده: بر اساس وجود transaction_type در extra_info، به عنوان طرف‌حساب تلقی می‌شود
        if ln.extra_info and ln.extra_info.get("transaction_type"):
            counterparties.append(row)
        else:
            items.append(row)

    return {
        "id": document.id,
        "code": document.code,
        "business_id": document.business_id,
        "fiscal_year_id": document.fiscal_year_id,
        "currency_id": document.currency_id,
        "document_type": document.document_type,
        "document_date": document.document_date.isoformat(),
        "description": document.description,
        "items": items,
        "counterparties": counterparties,
    }


def list_expense_income(
    db: Session,
    business_id: int,
    query: Dict[str, Any],
) -> Dict[str, Any]:
    """لیست اسناد هزینه و درآمد با فیلتر، جست‌وجو و صفحه‌بندی"""
    q = db.query(Document).filter(
        and_(
            Document.business_id == business_id,
            Document.document_type.in_([DOCUMENT_TYPE_EXPENSE, DOCUMENT_TYPE_INCOME]),
        )
    )

    # سال مالی
    fiscal_year_id = query.get("fiscal_year_id")
    try:
        fiscal_year_id_int = int(fiscal_year_id) if fiscal_year_id is not None else None
    except Exception:
        fiscal_year_id_int = None
    if fiscal_year_id_int is None:
        try:
            fy = _get_business_fiscal_year(db, business_id)
            fiscal_year_id_int = fy.id
        except Exception:
            fiscal_year_id_int = None
    if fiscal_year_id_int is not None:
        q = q.filter(Document.fiscal_year_id == fiscal_year_id_int)

    # نوع سند
    doc_type = query.get("document_type")
    if doc_type in (DOCUMENT_TYPE_EXPENSE, DOCUMENT_TYPE_INCOME):
        q = q.filter(Document.document_type == doc_type)

    # فیلتر تاریخ
    from_date = query.get("from_date")
    to_date = query.get("to_date")
    if from_date:
        try:
            q = q.filter(Document.document_date >= _parse_iso_date(from_date))
        except Exception:
            pass
    if to_date:
        try:
            q = q.filter(Document.document_date <= _parse_iso_date(to_date))
        except Exception:
            pass

    # جست‌وجو در کد سند
    search = query.get("search")
    if search:
        q = q.filter(Document.code.ilike(f"%{search}%"))

    # مرتب‌سازی
    sort_by = query.get("sort_by", "document_date")
    sort_desc = bool(query.get("sort_desc", True))
    if isinstance(sort_by, str) and hasattr(Document, sort_by):
        col = getattr(Document, sort_by)
        q = q.order_by(col.desc() if sort_desc else col.asc())
    else:
        q = q.order_by(Document.document_date.desc())

    # صفحه‌بندی
    skip = int(query.get("skip", 0))
    take = int(query.get("take", 20))
    total = q.count()
    docs = q.offset(skip).limit(take).all()

    return {
        "items": [document_to_dict(db, d) for d in docs],
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


