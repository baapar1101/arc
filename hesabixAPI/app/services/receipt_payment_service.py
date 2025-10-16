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
import logging

from sqlalchemy.orm import Session
from sqlalchemy import and_, or_, func

from adapters.db.models.document import Document
from adapters.db.models.document_line import DocumentLine
from adapters.db.models.account import Account
from adapters.db.models.person import Person
from adapters.db.models.currency import Currency
from adapters.db.models.user import User
from adapters.db.models.fiscal_year import FiscalYear
from app.core.responses import ApiError

# تنظیم لاگر
logger = logging.getLogger(__name__)


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


def _get_current_fiscal_year(db: Session, business_id: int) -> FiscalYear:
    """دریافت سال مالی فعلی برای کسب‌وکار"""
    fiscal_year = db.query(FiscalYear).filter(
        and_(
            FiscalYear.business_id == business_id,
            FiscalYear.is_last == True
        )
    ).first()
    
    if not fiscal_year:
        raise ApiError("NO_FISCAL_YEAR", "No active fiscal year found for this business", http_status=400)
    
    return fiscal_year


def _get_fixed_account_by_code(db: Session, account_code: str) -> Account:
    """
    دریافت حساب ثابت بر اساس کد
    
    Args:
        db: Session پایگاه داده
        account_code: کد حساب (مثل 10201, 10202, 10203)
    
    Returns:
        Account: حساب ثابت
    """
    account = db.query(Account).filter(
        and_(
            Account.business_id == None,  # حساب‌های عمومی
            Account.code == account_code
        )
    ).first()
    
    if not account:
        raise ApiError(
            "ACCOUNT_NOT_FOUND",
            f"Account with code {account_code} not found",
            http_status=500
        )
    
    return account


def _get_person_account(
    db: Session,
    business_id: int,
    person_id: int,
    is_receivable: bool
) -> Account:
    """
    دریافت حساب شخص (حساب دریافتنی یا پرداختنی عمومی)
    
    Args:
        business_id: شناسه کسب‌وکار
        person_id: شناسه شخص
        is_receivable: اگر True باشد، حساب دریافتنی و اگر False باشد حساب پرداختنی
    
    Returns:
        Account: حساب شخص عمومی
    """
    person = db.query(Person).filter(
        and_(Person.id == person_id, Person.business_id == business_id)
    ).first()
    
    if not person:
        raise ApiError("PERSON_NOT_FOUND", "Person not found", http_status=404)
    
    # کد حساب عمومی (بدون ایجاد حساب جداگانه)
    account_code = "10401" if is_receivable else "20201"
    
    # استفاده از تابع کمکی
    return _get_fixed_account_by_code(db, account_code)


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
    logger.info(f"=== شروع ایجاد سند دریافت/پرداخت ===")
    logger.info(f"business_id: {business_id}, user_id: {user_id}")
    logger.info(f"داده‌های ورودی: {data}")
    # اعتبارسنجی نوع سند
    document_type = str(data.get("document_type", "")).lower()
    logger.info(f"نوع سند: {document_type}")
    if document_type not in (DOCUMENT_TYPE_RECEIPT, DOCUMENT_TYPE_PAYMENT):
        raise ApiError("INVALID_DOCUMENT_TYPE", "document_type must be 'receipt' or 'payment'", http_status=400)
    
    is_receipt = (document_type == DOCUMENT_TYPE_RECEIPT)
    logger.info(f"آیا دریافت است: {is_receipt}")
    
    # اعتبارسنجی تاریخ
    document_date = _parse_iso_date(data.get("document_date", datetime.now()))
    
    # اعتبارسنجی ارز
    currency_id = data.get("currency_id")
    if not currency_id:
        raise ApiError("CURRENCY_REQUIRED", "currency_id is required", http_status=400)
    
    currency = db.query(Currency).filter(Currency.id == int(currency_id)).first()
    if not currency:
        raise ApiError("CURRENCY_NOT_FOUND", "Currency not found", http_status=404)
    
    # دریافت سال مالی فعلی
    logger.info(f"دریافت سال مالی فعلی برای business_id={business_id}")
    fiscal_year = _get_current_fiscal_year(db, business_id)
    logger.info(f"سال مالی فعلی: id={fiscal_year.id}, title={fiscal_year.title}")
    
    # اعتبارسنجی خطوط اشخاص
    person_lines = data.get("person_lines", [])
    logger.info(f"تعداد خطوط اشخاص: {len(person_lines)}")
    logger.info(f"خطوط اشخاص: {person_lines}")
    if not person_lines or not isinstance(person_lines, list):
        raise ApiError("PERSON_LINES_REQUIRED", "At least one person line is required", http_status=400)
    
    # اعتبارسنجی خطوط حساب‌ها
    account_lines = data.get("account_lines", [])
    logger.info(f"تعداد خطوط حساب‌ها: {len(account_lines)}")
    logger.info(f"خطوط حساب‌ها: {account_lines}")
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
        fiscal_year_id=fiscal_year.id,
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
    logger.info(f"=== شروع ایجاد خطوط اشخاص ===")
    for i, person_line in enumerate(person_lines):
        logger.info(f"پردازش خط شخص {i+1}: {person_line}")
        person_id = person_line.get("person_id")
        logger.info(f"person_id: {person_id}")
        if not person_id:
            logger.warning(f"خط شخص {i+1}: person_id موجود نیست، رد می‌شود")
            continue
        
        amount = Decimal(str(person_line.get("amount", 0)))
        logger.info(f"مبلغ: {amount}")
        if amount <= 0:
            logger.warning(f"خط شخص {i+1}: مبلغ صفر یا منفی، رد می‌شود")
            continue
        
        description = person_line.get("description", "").strip() or None
        logger.info(f"توضیحات: {description}")
        
        # دریافت حساب شخص عمومی
        # در دریافت: حساب دریافتنی (receivable) - کد 10401
        # در پرداخت: حساب پرداختنی (payable) - کد 20201
        logger.info(f"دریافت حساب شخص برای person_id={person_id}, is_receivable={is_receipt}")
        person_account = _get_person_account(
            db,
            business_id,
            int(person_id),
            is_receivable=is_receipt
        )
        logger.info(f"حساب شخص پیدا شد: id={person_account.id}, code={person_account.code}, name={person_account.name}")
        
        # ایجاد خط سند برای شخص
        # در دریافت: شخص بستانکار (credit)
        # در پرداخت: شخص بدهکار (debit)
        debit_amount = amount if not is_receipt else Decimal(0)
        credit_amount = amount if is_receipt else Decimal(0)
        logger.info(f"مقادیر بدهکار/بستانکار: debit={debit_amount}, credit={credit_amount}")
        
        line = DocumentLine(
            document_id=document.id,
            account_id=person_account.id,
            person_id=int(person_id),
            quantity=person_line.get("quantity"),
            debit=debit_amount,
            credit=credit_amount,
            description=description,
            extra_info={
                "person_id": int(person_id),
                "person_name": person_line.get("person_name"),
            }
        )
        logger.info(f"خط سند شخص ایجاد شد: {line}")
        db.add(line)
    
    # ایجاد خطوط سند برای حساب‌ها
    logger.info(f"=== شروع ایجاد خطوط حساب‌ها ===")
    total_commission = Decimal(0)  # مجموع کارمزدها
    
    for i, account_line in enumerate(account_lines):
        logger.info(f"پردازش خط حساب {i+1}: {account_line}")
        account_id = account_line.get("account_id")
        logger.info(f"account_id: {account_id}")
        if not account_id:
            logger.info(f"خط حساب {i+1}: account_id موجود نیست، ادامه می‌دهد")
        
        amount = Decimal(str(account_line.get("amount", 0)))
        logger.info(f"مبلغ: {amount}")
        if amount <= 0:
            logger.warning(f"خط حساب {i+1}: مبلغ صفر یا منفی، رد می‌شود")
            continue
        
        description = account_line.get("description", "").strip() or None
        transaction_type = account_line.get("transaction_type")
        transaction_date = account_line.get("transaction_date")
        commission = account_line.get("commission")
        
        logger.info(f"نوع تراکنش: {transaction_type}")
        logger.info(f"تاریخ تراکنش: {transaction_date}")
        logger.info(f"کمیسیون: {commission}")
        
        # اضافه کردن کارمزد به مجموع
        if commission:
            commission_amount = Decimal(str(commission))
            total_commission += commission_amount
            logger.info(f"کارمزد اضافه شد: {commission_amount}, مجموع: {total_commission}")
        
        # تعیین حساب بر اساس transaction_type
        account = None
        
        if transaction_type == "bank":
            # برای بانک، از حساب بانک استفاده کن
            account_code = "10203"  # بانک
            logger.info(f"انتخاب حساب بانک با کد: {account_code}")
            account = _get_fixed_account_by_code(db, account_code)
        elif transaction_type == "cash_register":
            # برای صندوق، از حساب صندوق استفاده کن
            account_code = "10202"  # صندوق
            logger.info(f"انتخاب حساب صندوق با کد: {account_code}")
            account = _get_fixed_account_by_code(db, account_code)
        elif transaction_type == "petty_cash":
            # برای تنخواهگردان، از حساب تنخواهگردان استفاده کن
            account_code = "10201"  # تنخواه گردان
            logger.info(f"انتخاب حساب تنخواهگردان با کد: {account_code}")
            account = _get_fixed_account_by_code(db, account_code)
        elif transaction_type == "check":
            # برای چک، بر اساس نوع سند از کد مناسب استفاده کن
            if is_receipt:
                account_code = "10403"  # اسناد دریافتنی (چک دریافتی)
            else:
                account_code = "20202"  # اسناد پرداختنی (چک پرداختی)
            logger.info(f"انتخاب حساب چک با کد: {account_code}")
            account = _get_fixed_account_by_code(db, account_code)
        elif transaction_type == "person":
            # برای شخص، از حساب شخص عمومی استفاده کن
            account_code = "20201"  # حساب‌های پرداختنی
            logger.info(f"انتخاب حساب شخص با کد: {account_code}")
            account = _get_fixed_account_by_code(db, account_code)
        elif account_id:
            # اگر account_id مشخص باشد، از آن استفاده کن
            logger.info(f"استفاده از account_id مشخص: {account_id}")
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
            logger.error(f"خط حساب {i+1}: حساب پیدا نشد برای transaction_type: {transaction_type}")
            raise ApiError(
                "ACCOUNT_NOT_FOUND",
                f"Account not found for transaction_type: {transaction_type}",
                http_status=404
            )
        
        logger.info(f"حساب پیدا شد: id={account.id}, code={account.code}, name={account.name}")
        
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
        debit_amount = amount if is_receipt else Decimal(0)
        credit_amount = amount if not is_receipt else Decimal(0)
        logger.info(f"مقادیر بدهکار/بستانکار برای حساب: debit={debit_amount}, credit={credit_amount}")
        
        # تنظیم bank_account_id بر اساس bank_id ارسالی
        bank_account_id = None
        if transaction_type == "bank" and account_line.get("bank_id"):
            try:
                bank_account_id = int(account_line.get("bank_id"))
                logger.info(f"bank_account_id تنظیم شد: {bank_account_id}")
            except (ValueError, TypeError):
                logger.warning(f"خطا در تبدیل bank_id: {account_line.get('bank_id')}")
        
        # تنظیم person_id برای transaction_type="person"
        person_id_for_line = None
        if transaction_type == "person" and account_line.get("person_id"):
            try:
                person_id_for_line = int(account_line.get("person_id"))
                logger.info(f"person_id تنظیم شد: {person_id_for_line}")
            except (ValueError, TypeError):
                logger.warning(f"خطا در تبدیل person_id: {account_line.get('person_id')}")
        
        line = DocumentLine(
            document_id=document.id,
            account_id=account.id,
            person_id=person_id_for_line,
            bank_account_id=bank_account_id,
            cash_register_id=account_line.get("cash_register_id"),
            petty_cash_id=account_line.get("petty_cash_id"),
            check_id=account_line.get("check_id"),
            quantity=account_line.get("quantity"),
            debit=debit_amount,
            credit=credit_amount,
            description=description,
            extra_info=extra_info if extra_info else None,
        )
        logger.info(f"خط سند حساب ایجاد شد: {line}")
        db.add(line)
    
    # ایجاد خطوط کارمزد اگر کارمزدی وجود دارد
    if total_commission > 0:
        logger.info(f"=== ایجاد خطوط کارمزد ===")
        logger.info(f"مجموع کارمزد: {total_commission}")
        
        # ایجاد خط کارمزد برای هر تراکنش که کارمزد دارد
        for i, account_line in enumerate(account_lines):
            commission = account_line.get("commission")
            if not commission or Decimal(str(commission)) <= 0:
                continue
                
            commission_amount = Decimal(str(commission))
            transaction_type = account_line.get("transaction_type")
            logger.info(f"ایجاد خط کارمزد برای تراکنش {i+1}: مبلغ={commission_amount}, نوع={transaction_type}")
            
            # تعیین حساب کارمزد بر اساس نوع تراکنش
            commission_account = None
            commission_account_code = None
            
            if transaction_type == "bank":
                commission_account_code = "10203"  # بانک
            elif transaction_type == "cash_register":
                commission_account_code = "10202"  # صندوق
            elif transaction_type == "petty_cash":
                commission_account_code = "10201"  # تنخواه گردان
            elif transaction_type == "check":
                if is_receipt:
                    commission_account_code = "10403"  # اسناد دریافتنی
                else:
                    commission_account_code = "20202"  # اسناد پرداختنی
            elif transaction_type == "person":
                commission_account_code = "20201"  # حساب‌های پرداختنی
            
            if commission_account_code:
                commission_account = _get_fixed_account_by_code(db, commission_account_code)
                logger.info(f"حساب کارمزد پیدا شد: id={commission_account.id}, code={commission_account.code}, name={commission_account.name}")
                
                # ایجاد خط کارمزد برای حساب (بانک/صندوق/تنخواهگردان)
                # در دریافت: کارمزد از حساب کم می‌شود (credit)
                # در پرداخت: کارمزد به حساب اضافه می‌شود (debit)
                commission_debit = commission_amount if not is_receipt else Decimal(0)
                commission_credit = commission_amount if is_receipt else Decimal(0)
                
                commission_line = DocumentLine(
                    document_id=document.id,
                    account_id=commission_account.id,
                    bank_account_id=account_line.get("bank_id"),
                    cash_register_id=account_line.get("cash_register_id"),
                    petty_cash_id=account_line.get("petty_cash_id"),
                    check_id=account_line.get("check_id"),
                    debit=commission_debit,
                    credit=commission_credit,
                    description=f"کارمزد تراکنش {transaction_type}",
                    extra_info={
                        "transaction_type": transaction_type,
                        "commission": float(commission_amount),
                        "is_commission_line": True,
                        "original_transaction_index": i,
                    }
                )
                logger.info(f"خط کارمزد حساب ایجاد شد: {commission_line}")
                db.add(commission_line)
                
                # ایجاد خط کارمزد برای حساب کارمزد خدمات بانکی (کد 70902)
                # در دریافت: کارمزد به حساب کارمزد اضافه می‌شود (debit)
                # در پرداخت: کارمزد از حساب کارمزد کم می‌شود (credit)
                logger.info(f"ایجاد خط کارمزد برای حساب کارمزد خدمات بانکی")
                
                # دریافت حساب کارمزد خدمات بانکی
                commission_service_account = _get_fixed_account_by_code(db, "70902")
                logger.info(f"حساب کارمزد خدمات بانکی پیدا شد: id={commission_service_account.id}, code={commission_service_account.code}, name={commission_service_account.name}")
                
                commission_service_debit = commission_amount if is_receipt else Decimal(0)
                commission_service_credit = commission_amount if not is_receipt else Decimal(0)
                
                commission_service_line = DocumentLine(
                    document_id=document.id,
                    account_id=commission_service_account.id,
                    debit=commission_service_debit,
                    credit=commission_service_credit,
                    description=f"کارمزد خدمات بانکی",
                    extra_info={
                        "commission": float(commission_amount),
                        "is_commission_line": True,
                        "original_transaction_index": i,
                        "commission_type": "banking_service",
                    }
                )
                logger.info(f"خط کارمزد خدمات بانکی ایجاد شد: {commission_service_line}")
                db.add(commission_service_line)
    
    # ذخیره تغییرات
    logger.info(f"=== ذخیره تغییرات ===")
    db.commit()
    db.refresh(document)
    logger.info(f"سند با موفقیت ایجاد شد: id={document.id}, code={document.code}")
    
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

    # فیلتر بر اساس سال مالی (از query یا پیشفرض سال جاری)
    fiscal_year_id = query.get("fiscal_year_id")
    if fiscal_year_id is not None:
        try:
            fiscal_year_id = int(fiscal_year_id)
        except (TypeError, ValueError):
            fiscal_year_id = None
    if fiscal_year_id is None:
        try:
            fiscal_year = _get_current_fiscal_year(db, business_id)
            fiscal_year_id = fiscal_year.id
        except Exception:
            fiscal_year_id = None
    if fiscal_year_id is not None:
        q = q.filter(Document.fiscal_year_id == fiscal_year_id)
    
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
    
    # بررسی اینکه sort_by معتبر است
    if sort_by and isinstance(sort_by, str) and hasattr(Document, sort_by):
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

    # 1) جلوگیری از حذف در سال مالی غیر جاری
    try:
        fiscal_year = db.query(FiscalYear).filter(FiscalYear.id == document.fiscal_year_id).first()
        if fiscal_year is not None and getattr(fiscal_year, "is_last", False) is not True:
            raise ApiError(
                "FISCAL_YEAR_LOCKED",
                "سند متعلق به سال مالی جاری نیست و قابل حذف نمی‌باشد",
                http_status=409,
            )
    except ApiError:
        # عبور خطای آگاهانه
        raise
    except Exception:
        # اگر به هر دلیل نتوانستیم وضعیت سال مالی را بررسی کنیم، حذف را متوقف نکن
        pass

    # 2) جلوگیری از حذف در صورت قفل بودن سند (براساس extra_info یا developer_settings)
    try:
        locked_flags = []
        if isinstance(document.extra_info, dict):
            locked_flags.append(bool(document.extra_info.get("locked")))
            locked_flags.append(bool(document.extra_info.get("is_locked")))
        if isinstance(document.developer_settings, dict):
            locked_flags.append(bool(document.developer_settings.get("locked")))
            locked_flags.append(bool(document.developer_settings.get("is_locked")))
        if any(locked_flags):
            raise ApiError(
                "DOCUMENT_LOCKED",
                "این سند قفل است و قابل حذف نمی‌باشد",
                http_status=409,
            )
    except ApiError:
        raise
    except Exception:
        pass

    # 3) جلوگیری از حذف اگر خطوط سند به چک مرتبط باشند
    try:
        has_related_checks = db.query(DocumentLine).filter(
            and_(
                DocumentLine.document_id == document.id,
                DocumentLine.check_id.isnot(None),
            )
        ).first() is not None
        if has_related_checks:
            raise ApiError(
                "DOCUMENT_REFERENCED",
                "این سند دارای اقلام مرتبط با چک است و قابل حذف نمی‌باشد",
                http_status=409,
            )
    except ApiError:
        raise
    except Exception:
        pass
    
    db.delete(document)
    db.commit()
    
    return True


def update_receipt_payment(
    db: Session,
    document_id: int,
    user_id: int,
    data: Dict[str, Any]
) -> Dict[str, Any]:
    """به‌روزرسانی سند دریافت/پرداخت - استراتژی Full-Replace خطوط"""
    document = db.query(Document).filter(Document.id == document_id).first()
    if document is None:
        raise ApiError("DOCUMENT_NOT_FOUND", "Document not found", http_status=404)

    if document.document_type not in (DOCUMENT_TYPE_RECEIPT, DOCUMENT_TYPE_PAYMENT):
        raise ApiError("INVALID_DOCUMENT_TYPE", "Invalid document type", http_status=400)

    # 1) محدودیت‌های سال مالی/قفل/وابستگی مشابه حذف
    try:
        fiscal_year = db.query(FiscalYear).filter(FiscalYear.id == document.fiscal_year_id).first()
        if fiscal_year is not None and getattr(fiscal_year, "is_last", False) is not True:
            raise ApiError(
                "FISCAL_YEAR_LOCKED",
                "سند متعلق به سال مالی جاری نیست و قابل ویرایش نمی‌باشد",
                http_status=409,
            )
    except ApiError:
        raise
    except Exception:
        pass

    try:
        locked_flags = []
        if isinstance(document.extra_info, dict):
            locked_flags.append(bool(document.extra_info.get("locked")))
            locked_flags.append(bool(document.extra_info.get("is_locked")))
        if isinstance(document.developer_settings, dict):
            locked_flags.append(bool(document.developer_settings.get("locked")))
            locked_flags.append(bool(document.developer_settings.get("is_locked")))
        if any(locked_flags):
            raise ApiError(
                "DOCUMENT_LOCKED",
                "این سند قفل است و قابل ویرایش نمی‌باشد",
                http_status=409,
            )
    except ApiError:
        raise
    except Exception:
        pass

    try:
        has_related_checks = db.query(DocumentLine).filter(
            and_(
                DocumentLine.document_id == document.id,
                DocumentLine.check_id.isnot(None),
            )
        ).first() is not None
        if has_related_checks:
            raise ApiError(
                "DOCUMENT_REFERENCED",
                "این سند دارای اقلام مرتبط با چک است و قابل ویرایش نمی‌باشد",
                http_status=409,
            )
    except ApiError:
        raise
    except Exception:
        pass

    # 2) اعتبارسنجی ورودی‌ها (مشابه create)
    document_date = _parse_iso_date(data.get("document_date", document.document_date))
    currency_id = data.get("currency_id", document.currency_id)
    if not currency_id:
        raise ApiError("CURRENCY_REQUIRED", "currency_id is required", http_status=400)
    currency = db.query(Currency).filter(Currency.id == int(currency_id)).first()
    if not currency:
        raise ApiError("CURRENCY_NOT_FOUND", "Currency not found", http_status=404)

    person_lines = data.get("person_lines", [])
    account_lines = data.get("account_lines", [])
    if not isinstance(person_lines, list) or not person_lines:
        raise ApiError("PERSON_LINES_REQUIRED", "At least one person line is required", http_status=400)
    if not isinstance(account_lines, list) or not account_lines:
        raise ApiError("ACCOUNT_LINES_REQUIRED", "At least one account line is required", http_status=400)

    person_total = sum(float(line.get("amount", 0)) for line in person_lines)
    account_total = sum(float(line.get("amount", 0)) for line in account_lines)
    if abs(person_total - account_total) > 0.01:
        raise ApiError("UNBALANCED_AMOUNTS", "Totals must be balanced", http_status=400)

    # 3) اعمال تغییرات در سند (بدون تغییر code و document_type)
    document.document_date = document_date
    document.currency_id = int(currency_id)
    if isinstance(data.get("extra_info"), dict) or data.get("extra_info") is None:
        document.extra_info = data.get("extra_info")

    # تعیین نوع دریافت/پرداخت برای محاسبات بدهکار/بستانکار
    is_receipt = (document.document_type == DOCUMENT_TYPE_RECEIPT)

    # حذف خطوط فعلی و ایجاد مجدد
    db.query(DocumentLine).filter(DocumentLine.document_id == document.id).delete(synchronize_session=False)

    # خطوط شخص
    for person_line in person_lines:
        person_id = person_line.get("person_id")
        if not person_id:
            continue
        amount = Decimal(str(person_line.get("amount", 0)))
        if amount <= 0:
            continue
        description = (person_line.get("description") or "").strip() or None
        person_account = _get_person_account(db, document.business_id, int(person_id), is_receivable=is_receipt)
        debit_amount = amount if not is_receipt else Decimal(0)
        credit_amount = amount if is_receipt else Decimal(0)
        line = DocumentLine(
            document_id=document.id,
            account_id=person_account.id,
            person_id=int(person_id),
            quantity=person_line.get("quantity"),
            debit=debit_amount,
            credit=credit_amount,
            description=description,
            extra_info={
                "person_id": int(person_id),
                "person_name": person_line.get("person_name"),
            },
        )
        db.add(line)

    # خطوط حساب‌ها + کارمزدها
    total_commission = Decimal(0)
    for i, account_line in enumerate(account_lines):
        amount = Decimal(str(account_line.get("amount", 0)))
        if amount <= 0:
            continue
        description = (account_line.get("description") or "").strip() or None
        transaction_type = account_line.get("transaction_type")
        transaction_date = account_line.get("transaction_date")
        commission = account_line.get("commission")
        if commission:
            total_commission += Decimal(str(commission))

        # انتخاب حساب بر اساس transaction_type یا account_id
        account = None
        if transaction_type == "bank":
            account = _get_fixed_account_by_code(db, "10203")
        elif transaction_type == "cash_register":
            account = _get_fixed_account_by_code(db, "10202")
        elif transaction_type == "petty_cash":
            account = _get_fixed_account_by_code(db, "10201")
        elif transaction_type == "check":
            account = _get_fixed_account_by_code(db, "10403" if is_receipt else "20202")
        elif transaction_type == "person":
            account = _get_fixed_account_by_code(db, "20201")
        elif account_line.get("account_id"):
            account = db.query(Account).filter(
                and_(
                    Account.id == int(account_line.get("account_id")),
                    or_(Account.business_id == document.business_id, Account.business_id == None),
                )
            ).first()
        if not account:
            raise ApiError("ACCOUNT_NOT_FOUND", "Account not found for transaction_type", http_status=404)

        extra_info: Dict[str, Any] = {}
        if transaction_type:
            extra_info["transaction_type"] = transaction_type
        if transaction_date:
            extra_info["transaction_date"] = transaction_date
        if commission:
            extra_info["commission"] = float(commission)
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

        debit_amount = amount if is_receipt else Decimal(0)
        credit_amount = amount if not is_receipt else Decimal(0)

        bank_account_id = None
        if transaction_type == "bank" and account_line.get("bank_id"):
            try:
                bank_account_id = int(account_line.get("bank_id"))
            except Exception:
                bank_account_id = None

        person_id_for_line = None
        if transaction_type == "person" and account_line.get("person_id"):
            try:
                person_id_for_line = int(account_line.get("person_id"))
            except Exception:
                person_id_for_line = None

        line = DocumentLine(
            document_id=document.id,
            account_id=account.id,
            person_id=person_id_for_line,
            bank_account_id=bank_account_id,
            cash_register_id=account_line.get("cash_register_id"),
            petty_cash_id=account_line.get("petty_cash_id"),
            check_id=account_line.get("check_id"),
            quantity=account_line.get("quantity"),
            debit=debit_amount,
            credit=credit_amount,
            description=description,
            extra_info=extra_info if extra_info else None,
        )
        db.add(line)

    # خطوط کارمزد
    if total_commission > 0:
        for i, account_line in enumerate(account_lines):
            commission = account_line.get("commission")
            if not commission or Decimal(str(commission)) <= 0:
                continue
            commission_amount = Decimal(str(commission))
            transaction_type = account_line.get("transaction_type")
            commission_account_code = None
            if transaction_type == "bank":
                commission_account_code = "10203"
            elif transaction_type == "cash_register":
                commission_account_code = "10202"
            elif transaction_type == "petty_cash":
                commission_account_code = "10201"
            elif transaction_type == "check":
                commission_account_code = "10403" if is_receipt else "20202"
            elif transaction_type == "person":
                commission_account_code = "20201"
            if commission_account_code:
                commission_account = _get_fixed_account_by_code(db, commission_account_code)
                commission_debit = commission_amount if not is_receipt else Decimal(0)
                commission_credit = commission_amount if is_receipt else Decimal(0)
                db.add(DocumentLine(
                    document_id=document.id,
                    account_id=commission_account.id,
                    bank_account_id=account_line.get("bank_id"),
                    cash_register_id=account_line.get("cash_register_id"),
                    petty_cash_id=account_line.get("petty_cash_id"),
                    check_id=account_line.get("check_id"),
                    debit=commission_debit,
                    credit=commission_credit,
                    description=f"کارمزد تراکنش {transaction_type}",
                    extra_info={
                        "transaction_type": transaction_type,
                        "commission": float(commission_amount),
                        "is_commission_line": True,
                        "original_transaction_index": i,
                    },
                ))
                commission_service_account = _get_fixed_account_by_code(db, "70902")
                commission_service_debit = commission_amount if is_receipt else Decimal(0)
                commission_service_credit = commission_amount if not is_receipt else Decimal(0)
                db.add(DocumentLine(
                    document_id=document.id,
                    account_id=commission_service_account.id,
                    debit=commission_service_debit,
                    credit=commission_service_credit,
                    description="کارمزد خدمات بانکی",
                    extra_info={
                        "commission": float(commission_amount),
                        "is_commission_line": True,
                        "original_transaction_index": i,
                        "commission_type": "banking_service",
                    },
                ))

    db.commit()
    db.refresh(document)
    return document_to_dict(db, document)
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
            "person_id": line.person_id,
            "product_id": line.product_id,
            "bank_account_id": line.bank_account_id,
            "cash_register_id": line.cash_register_id,
            "petty_cash_id": line.petty_cash_id,
            "check_id": line.check_id,
            "quantity": float(line.quantity) if line.quantity else None,
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
            if "person_name" in line.extra_info:
                line_dict["person_name"] = line.extra_info["person_name"]
        
        # اگر person_id موجود است، نام شخص را از دیتابیس دریافت کن
        if line.person_id and "person_name" not in line_dict:
            person = db.query(Person).filter(Person.id == line.person_id).first()
            if person:
                line_dict["person_name"] = person.alias_name or f"{person.first_name} {person.last_name}".strip()
            else:
                line_dict["person_name"] = "نامشخص"
        
        # تشخیص اینکه آیا این خط مربوط به شخص است یا حساب
        # خطوط کارمزد را جداگانه تشخیص می‌دهیم
        is_commission_line = line.extra_info and line.extra_info.get("is_commission_line", False)
        
        if is_commission_line:
            # خط کارمزد - همیشه در account_lines قرار می‌گیرد
            account_lines.append(line_dict)
        elif line.extra_info and line.extra_info.get("person_id"):
            person_lines.append(line_dict)
        else:
            account_lines.append(line_dict)
    
    # دریافت اطلاعات کاربر ایجادکننده
    created_by = db.query(User).filter(User.id == document.created_by_user_id).first()
    created_by_name = f"{created_by.first_name} {created_by.last_name}".strip() if created_by else None
    
    # دریافت اطلاعات ارز
    currency = db.query(Currency).filter(Currency.id == document.currency_id).first()
    currency_code = currency.code if currency else None
    
    # محاسبه مبلغ کل و تعداد خطوط
    total_amount = sum(line.get("amount", 0) for line in person_lines)
    person_lines_count = len(person_lines)
    account_lines_count = len(account_lines)
    
    # ایجاد لیست نام اشخاص برای نمایش
    person_names = []
    for line in person_lines:
        person_name = line.get("person_name")
        if person_name and person_name not in person_names:
            person_names.append(person_name)
    person_names_str = ", ".join(person_names) if person_names else "نامشخص"
    
    # تعیین نام نوع سند
    document_type_name = "دریافت" if document.document_type == DOCUMENT_TYPE_RECEIPT else "پرداخت"
    
    return {
        "id": document.id,
        "code": document.code,
        "business_id": document.business_id,
        "document_type": document.document_type,
        "document_type_name": document_type_name,
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
        "total_amount": total_amount,
        "person_lines_count": person_lines_count,
        "account_lines_count": account_lines_count,
        "person_names": person_names_str,
        "created_at": document.created_at.isoformat(),
        "updated_at": document.updated_at.isoformat(),
    }

