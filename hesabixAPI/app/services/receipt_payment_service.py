"""
سرویس دریافت و پرداخت (Receipt & Payment)

این سرویس برای ثبت اسناد دریافت و پرداخت استفاده می‌شود که شامل:
- دریافت وجه از اشخاص (مشتریان)
- پرداخت به اشخاص (تامین‌کنندگان)
"""

from __future__ import annotations

from typing import Any, Dict, List, Optional
from datetime import datetime, date
from decimal import Decimal

from sqlalchemy.orm import Session
from sqlalchemy import and_, or_, func

from adapters.db.models.document import Document
from adapters.db.models.document_line import DocumentLine
from adapters.db.models.account import Account
from adapters.db.models.person import Person
from adapters.db.models.currency import Currency
from adapters.db.models.user import User
from app.core.responses import ApiError


# نوع‌های سند
DOCUMENT_TYPE_RECEIPT = "receipt"  # دریافت
DOCUMENT_TYPE_PAYMENT = "payment"  # پرداخت

# نوع‌های حساب (از migration)
ACCOUNT_TYPE_RECEIVABLE = "person"  # حساب دریافتنی
ACCOUNT_TYPE_PAYABLE = "person"      # حساب پرداختنی
ACCOUNT_TYPE_CASH = "cash_register"         # صندوق
ACCOUNT_TYPE_BANK = "bank"         # بانک
ACCOUNT_TYPE_CHECK_RECEIVED = "check"  # اسناد دریافتنی (چک دریافتی)
ACCOUNT_TYPE_CHECK_PAYABLE = "check"  # اسناد پرداختنی (چک پرداختی)


def _parse_iso_date(dt: str | datetime | date) -> date:
    """تبدیل تاریخ به فرمت date"""
    if isinstance(dt, date):
        return dt
    if isinstance(dt, datetime):
        return dt.date()
    try:
        parsed = datetime.fromisoformat(str(dt).replace('Z', '+00:00'))
        return parsed.date()
    except Exception:
        raise ApiError("INVALID_DATE", f"Invalid date: {dt}", http_status=400)


def _get_or_create_person_account(
    db: Session,
    business_id: int,
    person_id: int,
    is_receivable: bool
) -> Account:
    """
    ایجاد یا دریافت حساب شخص (حساب دریافتنی یا پرداختنی)
    
    Args:
        business_id: شناسه کسب‌وکار
        person_id: شناسه شخص
        is_receivable: اگر True باشد، حساب دریافتنی و اگر False باشد حساب پرداختنی
    
    Returns:
        Account: حساب شخص
    """
    person = db.query(Person).filter(
        and_(Person.id == person_id, Person.business_id == business_id)
    ).first()
    
    if not person:
        raise ApiError("PERSON_NOT_FOUND", "Person not found", http_status=404)
    
    # کد حساب والد
    parent_code = "10401" if is_receivable else "20201"
    account_type = ACCOUNT_TYPE_RECEIVABLE if is_receivable else ACCOUNT_TYPE_PAYABLE
    
    # پیدا کردن حساب والد
    parent_account = db.query(Account).filter(
        and_(
            Account.business_id == None,  # حساب‌های عمومی
            Account.code == parent_code
        )
    ).first()
    
    if not parent_account:
        raise ApiError(
            "PARENT_ACCOUNT_NOT_FOUND",
            f"Parent account with code {parent_code} not found",
            http_status=500
        )
    
    # بررسی وجود حساب شخص
    person_account_code = f"{parent_code}-{person_id}"
    person_account = db.query(Account).filter(
        and_(
            Account.business_id == business_id,
            Account.code == person_account_code
        )
    ).first()
    
    if not person_account:
        # ایجاد حساب جدید برای شخص
        account_name = f"{person.alias_name}"
        if is_receivable:
            account_name = f"طلب از {account_name}"
        else:
            account_name = f"بدهی به {account_name}"
        
        person_account = Account(
            business_id=business_id,
            code=person_account_code,
            name=account_name,
            account_type=account_type,
            parent_id=parent_account.id,
        )
        db.add(person_account)
        db.flush()  # برای دریافت ID
    
    return person_account


def create_receipt_payment(
    db: Session,
    business_id: int,
    user_id: int,
    data: Dict[str, Any]
) -> Dict[str, Any]:
    """
    ایجاد سند دریافت یا پرداخت
    
    Args:
        business_id: شناسه کسب‌وکار
        user_id: شناسه کاربر ایجادکننده
        data: اطلاعات سند شامل:
            - document_type: "receipt" یا "payment"
            - document_date: تاریخ سند
            - currency_id: شناسه ارز
            - person_lines: لیست تراکنش‌های اشخاص [{"person_id": int, "amount": float, "description": str?}, ...]
            - account_lines: لیست تراکنش‌های حساب‌ها [{"account_id": int, "amount": float, "description": str?}, ...]
            - extra_info: اطلاعات اضافی (اختیاری)
    
    Returns:
        Dict: اطلاعات سند ایجاد شده
    """
    # اعتبارسنجی نوع سند
    document_type = str(data.get("document_type", "")).lower()
    if document_type not in (DOCUMENT_TYPE_RECEIPT, DOCUMENT_TYPE_PAYMENT):
        raise ApiError("INVALID_DOCUMENT_TYPE", "document_type must be 'receipt' or 'payment'", http_status=400)
    
    is_receipt = (document_type == DOCUMENT_TYPE_RECEIPT)
    
    # اعتبارسنجی تاریخ
    document_date = _parse_iso_date(data.get("document_date", datetime.now()))
    
    # اعتبارسنجی ارز
    currency_id = data.get("currency_id")
    if not currency_id:
        raise ApiError("CURRENCY_REQUIRED", "currency_id is required", http_status=400)
    
    currency = db.query(Currency).filter(Currency.id == int(currency_id)).first()
    if not currency:
        raise ApiError("CURRENCY_NOT_FOUND", "Currency not found", http_status=404)
    
    # اعتبارسنجی خطوط اشخاص
    person_lines = data.get("person_lines", [])
    if not person_lines or not isinstance(person_lines, list):
        raise ApiError("PERSON_LINES_REQUIRED", "At least one person line is required", http_status=400)
    
    # اعتبارسنجی خطوط حساب‌ها
    account_lines = data.get("account_lines", [])
    if not account_lines or not isinstance(account_lines, list):
        raise ApiError("ACCOUNT_LINES_REQUIRED", "At least one account line is required", http_status=400)
    
    # محاسبه مجموع مبالغ
    person_total = sum(float(line.get("amount", 0)) for line in person_lines)
    account_total = sum(float(line.get("amount", 0)) for line in account_lines)
    
    # بررسی تعادل مبالغ
    if abs(person_total - account_total) > 0.01:  # tolerance برای خطای ممیز شناور
        raise ApiError(
            "UNBALANCED_AMOUNTS",
            f"Person total ({person_total}) must equal account total ({account_total})",
            http_status=400
        )
    
    # تولید کد سند
    # فرمت: RP-YYYYMMDD-NNNN (RP = Receipt/Payment)
    today = datetime.now().date()
    prefix = f"{'RC' if is_receipt else 'PY'}-{today.strftime('%Y%m%d')}"
    
    last_doc = db.query(Document).filter(
        and_(
            Document.business_id == business_id,
            Document.code.like(f"{prefix}-%")
        )
    ).order_by(Document.code.desc()).first()
    
    if last_doc:
        try:
            last_num = int(last_doc.code.split("-")[-1])
            next_num = last_num + 1
        except Exception:
            next_num = 1
    else:
        next_num = 1
    
    doc_code = f"{prefix}-{next_num:04d}"
    
    # ایجاد سند
    document = Document(
        business_id=business_id,
        code=doc_code,
        document_type=document_type,
        document_date=document_date,
        currency_id=int(currency_id),
        created_by_user_id=user_id,
        registered_at=datetime.utcnow(),
        is_proforma=False,
        extra_info=data.get("extra_info"),
    )
    db.add(document)
    db.flush()  # برای دریافت document.id
    
    # ایجاد خطوط سند برای اشخاص
    for person_line in person_lines:
        person_id = person_line.get("person_id")
        if not person_id:
            continue
        
        amount = Decimal(str(person_line.get("amount", 0)))
        if amount <= 0:
            continue
        
        description = person_line.get("description", "").strip() or None
        
        # دریافت یا ایجاد حساب شخص
        # در دریافت: حساب دریافتنی (receivable)
        # در پرداخت: حساب پرداختنی (payable)
        person_account = _get_or_create_person_account(
            db,
            business_id,
            int(person_id),
            is_receivable=is_receipt
        )
        
        # ایجاد خط سند برای شخص
        # در دریافت: شخص بستانکار (credit)
        # در پرداخت: شخص بدهکار (debit)
        line = DocumentLine(
            document_id=document.id,
            account_id=person_account.id,
            debit=amount if not is_receipt else Decimal(0),
            credit=amount if is_receipt else Decimal(0),
            description=description,
            extra_info={
                "person_id": int(person_id),
                "person_name": person_line.get("person_name"),
            }
        )
        db.add(line)
    
    # ایجاد خطوط سند برای حساب‌ها
    for account_line in account_lines:
        account_id = account_line.get("account_id")
        if not account_id:
            continue
        
        amount = Decimal(str(account_line.get("amount", 0)))
        if amount <= 0:
            continue
        
        description = account_line.get("description", "").strip() or None
        transaction_type = account_line.get("transaction_type")
        transaction_date = account_line.get("transaction_date")
        commission = account_line.get("commission")
        
        # بررسی وجود حساب
        account = db.query(Account).filter(
            and_(
                Account.id == int(account_id),
                or_(
                    Account.business_id == business_id,
                    Account.business_id == None  # حساب‌های عمومی
                )
            )
        ).first()
        
        if not account:
            raise ApiError(
                "ACCOUNT_NOT_FOUND",
                f"Account with id {account_id} not found",
                http_status=404
            )
        
        # ایجاد اطلاعات اضافی برای خط سند
        extra_info = {}
        if transaction_type:
            extra_info["transaction_type"] = transaction_type
        if transaction_date:
            extra_info["transaction_date"] = transaction_date
        if commission:
            extra_info["commission"] = float(commission)
        
        # اطلاعات اضافی بر اساس نوع تراکنش
        if transaction_type == "bank":
            if account_line.get("bank_id"):
                extra_info["bank_id"] = account_line.get("bank_id")
            if account_line.get("bank_name"):
                extra_info["bank_name"] = account_line.get("bank_name")
        elif transaction_type == "cash_register":
            if account_line.get("cash_register_id"):
                extra_info["cash_register_id"] = account_line.get("cash_register_id")
            if account_line.get("cash_register_name"):
                extra_info["cash_register_name"] = account_line.get("cash_register_name")
        elif transaction_type == "petty_cash":
            if account_line.get("petty_cash_id"):
                extra_info["petty_cash_id"] = account_line.get("petty_cash_id")
            if account_line.get("petty_cash_name"):
                extra_info["petty_cash_name"] = account_line.get("petty_cash_name")
        elif transaction_type == "check":
            if account_line.get("check_id"):
                extra_info["check_id"] = account_line.get("check_id")
            if account_line.get("check_number"):
                extra_info["check_number"] = account_line.get("check_number")
        
        # ایجاد خط سند برای حساب
        # در دریافت: حساب بدهکار (debit) - دارایی افزایش می‌یابد
        # در پرداخت: حساب بستانکار (credit) - دارایی کاهش می‌یابد
        line = DocumentLine(
            document_id=document.id,
            account_id=account.id,
            debit=amount if is_receipt else Decimal(0),
            credit=amount if not is_receipt else Decimal(0),
            description=description,
            extra_info=extra_info if extra_info else None,
        )
        db.add(line)
    
    # ذخیره تغییرات
    db.commit()
    db.refresh(document)
    
    return document_to_dict(db, document)


def get_receipt_payment(db: Session, document_id: int) -> Optional[Dict[str, Any]]:
    """دریافت جزئیات یک سند دریافت/پرداخت"""
    document = db.query(Document).filter(Document.id == document_id).first()
    if not document:
        return None
    
    if document.document_type not in (DOCUMENT_TYPE_RECEIPT, DOCUMENT_TYPE_PAYMENT):
        return None
    
    return document_to_dict(db, document)


def list_receipts_payments(
    db: Session,
    business_id: int,
    query: Dict[str, Any]
) -> Dict[str, Any]:
    """لیست اسناد دریافت و پرداخت"""
    q = db.query(Document).filter(
        and_(
            Document.business_id == business_id,
            Document.document_type.in_([DOCUMENT_TYPE_RECEIPT, DOCUMENT_TYPE_PAYMENT])
        )
    )
    
    # فیلتر بر اساس نوع
    doc_type = query.get("document_type")
    if doc_type:
        q = q.filter(Document.document_type == doc_type)
    
    # فیلتر بر اساس تاریخ
    from_date = query.get("from_date")
    to_date = query.get("to_date")
    
    if from_date:
        try:
            from_dt = _parse_iso_date(from_date)
            q = q.filter(Document.document_date >= from_dt)
        except Exception:
            pass
    
    if to_date:
        try:
            to_dt = _parse_iso_date(to_date)
            q = q.filter(Document.document_date <= to_dt)
        except Exception:
            pass
    
    # جستجو
    search = query.get("search")
    if search:
        q = q.filter(Document.code.ilike(f"%{search}%"))
    
    # مرتب‌سازی
    sort_by = query.get("sort_by", "document_date")
    sort_desc = query.get("sort_desc", True)
    
    if hasattr(Document, sort_by):
        col = getattr(Document, sort_by)
        q = q.order_by(col.desc() if sort_desc else col.asc())
    else:
        q = q.order_by(Document.document_date.desc())
    
    # صفحه‌بندی
    skip = int(query.get("skip", 0))
    take = int(query.get("take", 20))
    
    total = q.count()
    items = q.offset(skip).limit(take).all()
    
    return {
        "items": [document_to_dict(db, doc) for doc in items],
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


def delete_receipt_payment(db: Session, document_id: int) -> bool:
    """حذف سند دریافت/پرداخت"""
    document = db.query(Document).filter(Document.id == document_id).first()
    
    if not document:
        return False
    
    if document.document_type not in (DOCUMENT_TYPE_RECEIPT, DOCUMENT_TYPE_PAYMENT):
        return False
    
    db.delete(document)
    db.commit()
    
    return True


def document_to_dict(db: Session, document: Document) -> Dict[str, Any]:
    """تبدیل سند به دیکشنری"""
    # دریافت خطوط سند
    lines = db.query(DocumentLine).filter(DocumentLine.document_id == document.id).all()
    
    # جداسازی خطوط اشخاص و حساب‌ها
    person_lines = []
    account_lines = []
    
    for line in lines:
        account = db.query(Account).filter(Account.id == line.account_id).first()
        if not account:
            continue
        
        line_dict = {
            "id": line.id,
            "account_id": line.account_id,
            "account_name": account.name,
            "account_code": account.code,
            "account_type": account.account_type,
            "debit": float(line.debit),
            "credit": float(line.credit),
            "amount": float(line.debit if line.debit > 0 else line.credit),
            "description": line.description,
            "extra_info": line.extra_info,
        }
        
        # اضافه کردن اطلاعات اضافی از extra_info
        if line.extra_info:
            if "transaction_type" in line.extra_info:
                line_dict["transaction_type"] = line.extra_info["transaction_type"]
            if "transaction_date" in line.extra_info:
                line_dict["transaction_date"] = line.extra_info["transaction_date"]
            if "commission" in line.extra_info:
                line_dict["commission"] = line.extra_info["commission"]
            if "bank_id" in line.extra_info:
                line_dict["bank_id"] = line.extra_info["bank_id"]
            if "bank_name" in line.extra_info:
                line_dict["bank_name"] = line.extra_info["bank_name"]
            if "cash_register_id" in line.extra_info:
                line_dict["cash_register_id"] = line.extra_info["cash_register_id"]
            if "cash_register_name" in line.extra_info:
                line_dict["cash_register_name"] = line.extra_info["cash_register_name"]
            if "petty_cash_id" in line.extra_info:
                line_dict["petty_cash_id"] = line.extra_info["petty_cash_id"]
            if "petty_cash_name" in line.extra_info:
                line_dict["petty_cash_name"] = line.extra_info["petty_cash_name"]
            if "check_id" in line.extra_info:
                line_dict["check_id"] = line.extra_info["check_id"]
            if "check_number" in line.extra_info:
                line_dict["check_number"] = line.extra_info["check_number"]
        
        # تشخیص اینکه آیا این خط مربوط به شخص است یا حساب
        if line.extra_info and line.extra_info.get("person_id"):
            person_lines.append(line_dict)
        else:
            account_lines.append(line_dict)
    
    # دریافت اطلاعات کاربر ایجادکننده
    created_by = db.query(User).filter(User.id == document.created_by_user_id).first()
    created_by_name = f"{created_by.first_name} {created_by.last_name}".strip() if created_by else None
    
    # دریافت اطلاعات ارز
    currency = db.query(Currency).filter(Currency.id == document.currency_id).first()
    currency_code = currency.code if currency else None
    
    return {
        "id": document.id,
        "code": document.code,
        "business_id": document.business_id,
        "document_type": document.document_type,
        "document_date": document.document_date.isoformat(),
        "registered_at": document.registered_at.isoformat(),
        "currency_id": document.currency_id,
        "currency_code": currency_code,
        "created_by_user_id": document.created_by_user_id,
        "created_by_name": created_by_name,
        "is_proforma": document.is_proforma,
        "extra_info": document.extra_info,
        "person_lines": person_lines,
        "account_lines": account_lines,
        "created_at": document.created_at.isoformat(),
        "updated_at": document.updated_at.isoformat(),
    }

