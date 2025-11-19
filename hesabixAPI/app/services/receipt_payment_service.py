"""
سرویس دریافت و پرداخت (Receipt & Payment)

این سرویس برای ثبت اسناد دریافت و پرداخت استفاده می‌شود که شامل:
- دریافت وجه از اشخاص (مشتریان)
- پرداخت به اشخاص (تامین‌کنندگان)
"""

from __future__ import annotations

from typing import Any, Dict, List, Optional, Tuple
from datetime import datetime, date
from decimal import Decimal
import logging

from sqlalchemy.orm import Session
from sqlalchemy.orm.attributes import flag_modified
from sqlalchemy import and_, or_, func

from adapters.db.models.document import Document
from adapters.db.models.document_line import DocumentLine
from adapters.db.models.account import Account
from adapters.db.models.person import Person
from adapters.db.models.currency import Currency
from adapters.db.models.check import Check, CheckType, CheckStatus
from adapters.db.models.user import User
from adapters.db.models.fiscal_year import FiscalYear
from app.core.responses import ApiError
from app.services.document_monetization_service import ensure_document_policy_allows_creation
import jdatetime

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

ALLOWED_RECEIPT_CHECK_STATUSES = {CheckStatus.RECEIVED_ON_HAND}
ALLOWED_PAYMENT_CHECK_STATUSES = {CheckStatus.TRANSFERRED_ISSUED}


def _parse_iso_date(dt: str | datetime | date) -> date:
    """تبدیل تاریخ به فرمت date - پشتیبانی از تاریخ‌های شمسی و میلادی"""
    if isinstance(dt, date):
        return dt
    if isinstance(dt, datetime):
        return dt.date()
    
    dt_str = str(dt).strip()
    
    try:
        # ابتدا سعی کن ISO8601 را پردازش کنی
        dt_str_clean = dt_str.replace('Z', '+00:00')
        parsed = datetime.fromisoformat(dt_str_clean)
        return parsed.date()
    except Exception:
        pass
    
    try:
        # بررسی فرمت YYYY-MM-DD (میلادی)
        if len(dt_str) == 10 and dt_str.count('-') == 2:
            return datetime.strptime(dt_str, '%Y-%m-%d').date()
    except Exception:
        pass
    
    try:
        # بررسی فرمت YYYY/MM/DD (ممکن است شمسی باشد)
        if len(dt_str) == 10 and dt_str.count('/') == 2:
            parts = dt_str.split('/')
            if len(parts) == 3:
                year, month, day = parts
                try:
                    year_int = int(year)
                    month_int = int(month)
                    day_int = int(day)
                    
                    # اگر سال بزرگتر از 1500 باشد، احتمالاً شمسی است
                    if year_int > 1500:
                        # تبدیل شمسی به میلادی
                        jalali_date = jdatetime.date(year_int, month_int, day_int)
                        gregorian_date = jalali_date.togregorian()
                        return gregorian_date
                    else:
                        # احتمالاً میلادی است
                        return datetime.strptime(dt_str, '%Y/%m/%d').date()
                except (ValueError, jdatetime.JalaliDateError):
                    # اگر تبدیل شمسی ناموفق بود، سعی کن میلادی کنی
                    return datetime.strptime(dt_str, '%Y/%m/%d').date()
    except Exception:
        pass
    
    # اگر هیچ فرمتی کار نکرد، خطا بده
    raise ApiError("INVALID_DATE", f"Invalid date format: {dt}", http_status=400)


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


def _validate_check_transaction_line(
    db: Session,
    *,
    business_id: int,
    account_line: Dict[str, Any],
    is_receipt: bool,
    document_currency_id: int,
    amount_decimal: Decimal,
    exclude_document_id: Optional[int] = None,
) -> Tuple[Check, int]:
    """اعتبارسنجی الزامات انتخاب چک برای سطر دریافت/پرداخت"""
    check_id_raw = account_line.get("check_id")
    if not check_id_raw:
        raise ApiError(
            "CHECK_ID_REQUIRED",
            "برای تراکنش از نوع چک، انتخاب چک الزامی است",
            http_status=400,
        )
    try:
        check_id = int(check_id_raw)
    except Exception:
        raise ApiError("CHECK_ID_INVALID", "شناسه چک نامعتبر است", http_status=400)

    check = (
        db.query(Check)
        .filter(
            and_(
                Check.id == check_id,
                Check.business_id == business_id,
            )
        )
        .first()
    )
    if not check:
        raise ApiError("CHECK_NOT_FOUND", "چک انتخاب‌شده یافت نشد", http_status=404)

    expected_type = CheckType.RECEIVED if is_receipt else CheckType.TRANSFERRED
    if check.type != expected_type:
        raise ApiError(
            "CHECK_TYPE_MISMATCH",
            "نوع چک با نوع سند هم‌خوانی ندارد",
            http_status=400,
        )

    allowed_statuses = ALLOWED_RECEIPT_CHECK_STATUSES if is_receipt else ALLOWED_PAYMENT_CHECK_STATUSES
    if check.status not in allowed_statuses:
        raise ApiError(
            "CHECK_STATUS_INVALID",
            "وضعیت فعلی چک اجازه استفاده در این سند را نمی‌دهد",
            http_status=409,
        )

    if int(check.currency_id) != int(document_currency_id):
        raise ApiError(
            "CHECK_CURRENCY_MISMATCH",
            "ارز چک با ارز سند دریافت/پرداخت یکسان نیست",
            http_status=400,
        )

    if amount_decimal != Decimal(str(check.amount)):
        raise ApiError(
            "CHECK_AMOUNT_MISMATCH",
            "مبلغ تراکنش با مبلغ ثبت‌شده چک برابر نیست",
            http_status=400,
        )

    existing_q = (
        db.query(DocumentLine)
        .join(Document, DocumentLine.document_id == Document.id)
        .filter(
            DocumentLine.check_id == check_id,
            Document.document_type.in_([DOCUMENT_TYPE_RECEIPT, DOCUMENT_TYPE_PAYMENT]),
        )
    )
    if exclude_document_id:
        existing_q = existing_q.filter(Document.id != exclude_document_id)

    if existing_q.first():
        raise ApiError(
            "CHECK_ALREADY_LINKED",
            "این چک قبلاً در سند دریافت/پرداخت دیگری استفاده شده است",
            http_status=409,
        )

    return check, check_id


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

    # امکان override نوع حساب طرف‌شخص (دریافتنی/پرداختنی) برای سناریوهایی مثل برگشت فاکتور
    extra_info_all = data.get("extra_info") or {}
    person_is_receivable_override = extra_info_all.get("person_is_receivable")
    if isinstance(person_is_receivable_override, bool):
        is_person_receivable = person_is_receivable_override
    else:
        # پیش‌فرض: دریافت → دریافتنی، پرداخت → پرداختنی
        is_person_receivable = is_receipt
    
    # اعتبارسنجی تاریخ
    document_date = _parse_iso_date(data.get("document_date", datetime.now()))
    
    # اعتبارسنجی ارز
    currency_id = data.get("currency_id")
    if not currency_id:
        raise ApiError("CURRENCY_REQUIRED", "currency_id is required", http_status=400)
    
    currency = db.query(Currency).filter(Currency.id == int(currency_id)).first()
    if not currency:
        raise ApiError("CURRENCY_NOT_FOUND", "Currency not found", http_status=404)
    currency_id = int(currency_id)
    
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
    
    amount_decimal = Decimal(str(person_total))

    ensure_document_policy_allows_creation(
        db,
        business_id,
        document_type=document_type,
        document_date=document_date,
        amount=amount_decimal,
    )

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
        description=data.get("description"),
        extra_info=data.get("extra_info"),
    )
    db.add(document)
    db.flush()  # برای دریافت document.id
    
    # --- اعتبارسنجی اقساط قبل از اعمال (سختگیرانه) ---
    extra_info_all = data.get("extra_info") or {}
    settlements_input = extra_info_all.get("settlements") or []
    if settlements_input:
        # فقط روی دریافت مجاز است
        if not is_receipt:
            raise ApiError(
                "INSTALLMENT_NOT_ALLOWED_FOR_PAYMENT",
                "تخصیص اقساط فقط در اسناد دریافت مجاز است",
                http_status=400,
            )
        # نقشه مبلغ خطوط هر شخص
        person_amount_by_id: Dict[int, Decimal] = {}
        for pl in person_lines:
            try:
                pid = int(pl.get("person_id"))
                amt = Decimal(str(pl.get("amount", 0) or 0))
                if pid and amt > 0:
                    person_amount_by_id[pid] = person_amount_by_id.get(pid, Decimal(0)) + amt
            except Exception:
                continue
        # مجموع تخصیص اقساط به ازای هر شخص
        allocated_by_person: Dict[int, Decimal] = {}
        for st in settlements_input:
            # الزام person_id در هر settlement برای تطبیق با خطوط شخص
            try:
                st_person_id = int(st.get("person_id"))
            except Exception:
                raise ApiError(
                    "INSTALLMENT_PERSON_REQUIRED",
                    "برای هر تخصیص قسط، person_id الزامی است",
                    http_status=400,
                )
            if st_person_id not in person_amount_by_id:
                raise ApiError(
                    "INSTALLMENT_PERSON_MISMATCH",
                    "شخص تخصیص قسط باید در خطوط اشخاص سند وجود داشته باشد",
                    http_status=400,
                )
            # اعتبارسنجی فاکتور و ارز
            try:
                invoice_id = int(st.get("invoice_id"))
            except Exception:
                raise ApiError("INSTALLMENT_INVOICE_INVALID", "شناسه فاکتور اقساط نامعتبر است", http_status=400)
            invoice_doc = db.query(Document).filter(Document.id == invoice_id).first()
            if not invoice_doc:
                raise ApiError("INSTALLMENT_INVOICE_NOT_FOUND", "فاکتور اقساط پیدا نشد", http_status=404)
            if int(invoice_doc.currency_id) != int(currency_id):
                raise ApiError(
                    "INSTALLMENT_CURRENCY_MISMATCH",
                    "ارز فاکتور اقساط با ارز سند دریافت یکسان نیست",
                    http_status=400,
                )
            inv_extra = invoice_doc.extra_info or {}
            plan = inv_extra.get("installment_plan")
            schedule = (plan or {}).get("schedule")
            if not (isinstance(plan, dict) and isinstance(schedule, list) and schedule):
                raise ApiError(
                    "INSTALLMENT_PLAN_NOT_FOUND",
                    "برای فاکتور انتخاب‌شده، طرح اقساط ثبت نشده است",
                    http_status=404,
                )
            # بررسی عدم بیش‌پرداخت در هر قسط
            remaining_by_seq: Dict[int, Decimal] = {}
            for item in schedule:
                try:
                    seq_i = int(item.get("seq") or 0)
                    total_i = Decimal(str(item.get("total", 0) or 0))
                    paid_i = Decimal(str(item.get("paid_amount", 0) or 0))
                    remaining_by_seq[seq_i] = max(total_i - paid_i, Decimal(0))
                except Exception:
                    continue
            allocations = st.get("allocations") or []
            if not isinstance(allocations, list) or not allocations:
                raise ApiError("INSTALLMENT_ALLOCATIONS_REQUIRED", "لیست تخصیص اقساط خالی است", http_status=400)
            for al in allocations:
                try:
                    seq = int(al.get("seq"))
                    amt = Decimal(str(al.get("amount", 0) or 0))
                except Exception:
                    raise ApiError("INSTALLMENT_ALLOCATION_INVALID", "تخصیص قسط نامعتبر است", http_status=400)
                if seq <= 0 or amt <= 0:
                    raise ApiError("INSTALLMENT_ALLOCATION_INVALID", "تخصیص قسط نامعتبر است", http_status=400)
                remain = remaining_by_seq.get(seq, None)
                if remain is None:
                    raise ApiError("INSTALLMENT_SEQ_NOT_FOUND", "شماره قسط در طرح اقساط یافت نشد", http_status=404)
                if amt > remain:
                    raise ApiError(
                        "INSTALLMENT_OVERPAY_PER_SEQ",
                        "مبلغ تخصیص از مانده همان قسط بیشتر است",
                        http_status=400,
                    )
                allocated_by_person[st_person_id] = allocated_by_person.get(st_person_id, Decimal(0)) + amt
        # کنترل سقف مجموع تخصیص هر شخص نسبت به مبلغ خطوط همان شخص
        for pid, alloc_sum in allocated_by_person.items():
            if alloc_sum > person_amount_by_id.get(pid, Decimal(0)):
                raise ApiError(
                    "INSTALLMENT_OVER_PERSON_LINES",
                    "جمع تخصیص اقساط یک شخص از مجموع مبلغ خطوط همان شخص بیشتر است",
                    http_status=400,
                )
    
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
        # در حالت عادی: دریافت → حساب دریافتنی (10401)، پرداخت → حساب پرداختنی (20201)
        # در صورت وجود person_is_receivable در extra_info، از همان تبعیت می‌کند
        logger.info(f"دریافت حساب شخص برای person_id={person_id}, is_receivable={is_person_receivable}")
        person_account = _get_person_account(
            db,
            business_id,
            int(person_id),
            is_receivable=is_person_receivable,
        )
        logger.info(f"حساب شخص پیدا شد: id={person_account.id}, code={person_account.code}, name={person_account.name}")
        
        # ایجاد خط سند برای شخص
        # در دریافت: شخص بستانکار (credit)
        # در پرداخت: شخص بدهکار (debit)
        debit_amount = amount if not is_receipt else Decimal(0)
        credit_amount = amount if is_receipt else Decimal(0)
        logger.info(f"مقادیر بدهکار/بستانکار: debit={debit_amount}, credit={credit_amount}")
        
        # ساخت extra_info برای خط شخص
        line_extra_info = {
            "person_id": int(person_id),
            "person_name": person_line.get("person_name"),
        }
        
        # اضافه کردن اطلاعات فاکتور از extra_info شخص
        person_line_extra = person_line.get("extra_info")
        if isinstance(person_line_extra, dict):
            if person_line_extra.get("invoice_id"):
                line_extra_info["invoice_id"] = person_line_extra["invoice_id"]
            if person_line_extra.get("invoice_code"):
                line_extra_info["invoice_code"] = person_line_extra["invoice_code"]
            if person_line_extra.get("link_to_invoice"):
                line_extra_info["link_to_invoice"] = person_line_extra["link_to_invoice"]
        
        line = DocumentLine(
            document_id=document.id,
            account_id=person_account.id,
            person_id=int(person_id),
            quantity=person_line.get("quantity"),
            debit=debit_amount,
            credit=credit_amount,
            description=description,
            extra_info=line_extra_info
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
        
        amount = Decimal(str(account_line.get("amount", 0)))
        logger.info(f"مبلغ: {amount}")
        if amount <= 0:
            logger.warning(f"خط حساب {i+1}: مبلغ صفر یا منفی، رد می‌شود")
            continue
        
        # مدیریت description که ممکن است None باشد
        description_raw = account_line.get("description")
        description = None
        if description_raw:
            if isinstance(description_raw, str):
                description = description_raw.strip() or None
            else:
                description = str(description_raw).strip() or None
        
        transaction_type = account_line.get("transaction_type")
        normalized_transaction_type = transaction_type
        if transaction_type == "check_expense":
            normalized_transaction_type = "check"
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
        
        check_id_val: Optional[int] = None
        if normalized_transaction_type == "check":
            check_obj, check_id_val = _validate_check_transaction_line(
                db,
                business_id=business_id,
                account_line=account_line,
                is_receipt=is_receipt,
                document_currency_id=currency_id,
                amount_decimal=amount,
            )
            account_line["check_id"] = check_id_val
            if not account_line.get("check_number"):
                account_line["check_number"] = check_obj.check_number

        if normalized_transaction_type == "bank":
            # برای بانک، از حساب بانک استفاده کن
            account_code = "10203"  # بانک
            logger.info(f"انتخاب حساب بانک با کد: {account_code}")
            account = _get_fixed_account_by_code(db, account_code)
        elif normalized_transaction_type == "cash_register":
            # برای صندوق، از حساب صندوق استفاده کن
            account_code = "10202"  # صندوق
            logger.info(f"انتخاب حساب صندوق با کد: {account_code}")
            account = _get_fixed_account_by_code(db, account_code)
        elif normalized_transaction_type == "petty_cash":
            # برای تنخواهگردان، از حساب تنخواهگردان استفاده کن
            account_code = "10201"  # تنخواه گردان
            logger.info(f"انتخاب حساب تنخواهگردان با کد: {account_code}")
            account = _get_fixed_account_by_code(db, account_code)
        elif normalized_transaction_type == "check":
            # برای چک، بر اساس نوع سند از کد مناسب استفاده کن
            if is_receipt:
                account_code = "10403"  # اسناد دریافتنی (چک دریافتی)
            else:
                account_code = "20202"  # اسناد پرداختنی (چک پرداختی)
            logger.info(f"انتخاب حساب چک با کد: {account_code}")
            account = _get_fixed_account_by_code(db, account_code)
        elif normalized_transaction_type == "person":
            # برای شخص، از حساب شخص عمومی استفاده کن
            account_code = "20201"  # حساب‌های پرداختنی
            logger.info(f"انتخاب حساب شخص با کد: {account_code}")
            account = _get_fixed_account_by_code(db, account_code)
        elif normalized_transaction_type == "wallet":
            # کیف‌پول (حساب نزد پرداخت‌یار)
            account_code = "10204"
            logger.info(f"انتخاب حساب کیف‌پول با کد: {account_code}")
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
            # اگر transaction_type موجود نباشد، از account_id استفاده کن
            if not transaction_type and account_id:
                logger.warning(f"خط حساب {i+1}: transaction_type موجود نیست اما account_id موجود است: {account_id}")
                # تلاش مجدد برای پیدا کردن حساب با account_id
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
                logger.error(f"خط حساب {i+1}: حساب پیدا نشد برای transaction_type: {transaction_type}, account_id: {account_id}")
                raise ApiError(
                    "ACCOUNT_NOT_FOUND",
                    f"Account not found for transaction_type: {transaction_type}, account_id: {account_id}",
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
        if normalized_transaction_type == "bank":
            if account_line.get("bank_id"):
                extra_info["bank_id"] = account_line.get("bank_id")
            if account_line.get("bank_name"):
                extra_info["bank_name"] = account_line.get("bank_name")
        elif normalized_transaction_type == "cash_register":
            if account_line.get("cash_register_id"):
                extra_info["cash_register_id"] = account_line.get("cash_register_id")
            if account_line.get("cash_register_name"):
                extra_info["cash_register_name"] = account_line.get("cash_register_name")
        elif normalized_transaction_type == "petty_cash":
            if account_line.get("petty_cash_id"):
                extra_info["petty_cash_id"] = account_line.get("petty_cash_id")
            if account_line.get("petty_cash_name"):
                extra_info["petty_cash_name"] = account_line.get("petty_cash_name")
        elif normalized_transaction_type == "check":
            if account_line.get("check_id"):
                extra_info["check_id"] = int(account_line.get("check_id"))
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
        
        resolved_check_id = check_id_val
        if resolved_check_id is None and account_line.get("check_id"):
            try:
                resolved_check_id = int(account_line.get("check_id"))
            except Exception:
                resolved_check_id = None

        line = DocumentLine(
            document_id=document.id,
            account_id=account.id,
            person_id=person_id_for_line,
            bank_account_id=bank_account_id,
            cash_register_id=account_line.get("cash_register_id"),
            petty_cash_id=account_line.get("petty_cash_id"),
            check_id=resolved_check_id,
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
            normalized_transaction_type = transaction_type
            if transaction_type == "check_expense":
                normalized_transaction_type = "check"
            logger.info(f"ایجاد خط کارمزد برای تراکنش {i+1}: مبلغ={commission_amount}, نوع={transaction_type}")
            
            # تعیین حساب کارمزد بر اساس نوع تراکنش
            commission_account = None
            commission_account_code = None
            
            if normalized_transaction_type == "bank":
                commission_account_code = "10203"  # بانک
            elif normalized_transaction_type == "cash_register":
                commission_account_code = "10202"  # صندوق
            elif normalized_transaction_type == "petty_cash":
                commission_account_code = "10201"  # تنخواه گردان
            elif normalized_transaction_type == "check":
                if is_receipt:
                    commission_account_code = "10403"  # اسناد دریافتنی
                else:
                    commission_account_code = "20202"  # اسناد پرداختنی
            elif normalized_transaction_type == "person":
                commission_account_code = "20201"  # حساب‌های پرداختنی
            
            if commission_account_code:
                commission_account = _get_fixed_account_by_code(db, commission_account_code)
                logger.info(f"حساب کارمزد پیدا شد: id={commission_account.id}, code={commission_account.code}, name={commission_account.name}")
                
                # ایجاد خط کارمزد برای حساب (بانک/صندوق/تنخواهگردان)
                # در دریافت: کارمزد از حساب کم می‌شود (credit)
                # در پرداخت: کارمزد به حساب اضافه می‌شود (debit)
                commission_debit = commission_amount if not is_receipt else Decimal(0)
                commission_credit = commission_amount if is_receipt else Decimal(0)

                commission_check_id = None
                if account_line.get("check_id"):
                    try:
                        commission_check_id = int(account_line.get("check_id"))
                    except Exception:
                        commission_check_id = None
                
                commission_line = DocumentLine(
                    document_id=document.id,
                    account_id=commission_account.id,
                    bank_account_id=account_line.get("bank_id"),
                    cash_register_id=account_line.get("cash_register_id"),
                    petty_cash_id=account_line.get("petty_cash_id"),
                    check_id=commission_check_id,
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
    
    # --- فروش اقساطی: تخصیص به اقساط و شناسایی سود (بدون try/except ساکت) ---
    extra_info_all = data.get("extra_info") or {}
    settlements = extra_info_all.get("settlements") or []
    total_interest_to_recognize = Decimal(0)
    updated_invoice_ids: List[int] = []
    if is_receipt and isinstance(settlements, list) and settlements:
        for st in settlements:
            invoice_id = int(st.get("invoice_id"))
            invoice_doc = db.query(Document).filter(Document.id == invoice_id).first()
            if not invoice_doc:
                raise ApiError("INSTALLMENT_INVOICE_NOT_FOUND", "فاکتور اقساط پیدا نشد", http_status=404)
            inv_extra = invoice_doc.extra_info or {}
            plan = inv_extra.get("installment_plan")
            schedule = (plan or {}).get("schedule")
            if not (isinstance(plan, dict) and isinstance(schedule, list) and schedule):
                raise ApiError("INSTALLMENT_PLAN_NOT_FOUND", "طرح اقساط برای فاکتور یافت نشد", http_status=404)
            allocations = st.get("allocations") or []
            if not isinstance(allocations, list) or not allocations:
                raise ApiError("INSTALLMENT_ALLOCATIONS_REQUIRED", "لیست تخصیص اقساط خالی است", http_status=400)
            seq_to_amount: Dict[int, Decimal] = {}
            for al in allocations:
                seq = int(al.get("seq"))
                amt = Decimal(str(al.get("amount", 0) or 0))
                if seq <= 0 or amt <= 0:
                    raise ApiError("INSTALLMENT_ALLOCATION_INVALID", "تخصیص قسط نامعتبر است", http_status=400)
                seq_to_amount[seq] = seq_to_amount.get(seq, Decimal(0)) + amt
            # کنترل مانده هر قسط (با اتکا به اعتبارسنجی بالادستی remaining)
            remaining_by_seq: Dict[int, Decimal] = {}
            for item in schedule:
                seq_i = int(item.get("seq") or 0)
                total_i = Decimal(str(item.get("total", 0) or 0))
                paid_i = Decimal(str(item.get("paid_amount", 0) or 0))
                remaining_by_seq[seq_i] = max(total_i - paid_i, Decimal(0))
            for seq, alloc in seq_to_amount.items():
                remain = remaining_by_seq.get(seq)
                if remain is None:
                    raise ApiError("INSTALLMENT_SEQ_NOT_FOUND", "شماره قسط یافت نشد", http_status=404)
                if alloc > remain:
                    raise ApiError("INSTALLMENT_OVERPAY_PER_SEQ", "مبلغ تخصیص از مانده قسط بیشتر است", http_status=400)
            # اعمال و محاسبه سود
            interest_delta_for_invoice = Decimal(0)
            new_schedule: List[Dict[str, Any]] = []
            for item in schedule:
                seq = int(item.get("seq") or 0)
                paid_before = Decimal(str(item.get("paid_amount", 0) or 0))
                interest_part = Decimal(str(item.get("interest", 0) or 0))
                total_part = Decimal(str(item.get("total", 0) or 0))
                alloc_amt = seq_to_amount.get(seq, Decimal(0))
                paid_after = paid_before + alloc_amt
                prev_interest_recognized = min(paid_before, interest_part)
                new_interest_recognized = min(paid_after, interest_part)
                delta = new_interest_recognized - prev_interest_recognized
                if delta > 0:
                    interest_delta_for_invoice += delta
                # محاسبه status با tolerance برای خطای ممیز شناور
                tolerance = Decimal("0.01")
                if total_part > 0 and (paid_after >= total_part or (total_part - paid_after) <= tolerance):
                    new_status = "paid"
                elif paid_after > tolerance:
                    new_status = "partial"
                else:
                    new_status = "pending"
                logger.info(f"قسط #{seq}: total={total_part}, paid_before={paid_before}, alloc={alloc_amt}, paid_after={paid_after}, status={new_status}")
                new_item = dict(item)
                new_item["paid_amount"] = float(paid_after)
                new_item["status"] = new_status
                new_schedule.append(new_item)
            new_plan = dict(plan or {})
            new_plan["schedule"] = new_schedule
            inv_extra["installment_plan"] = new_plan
            invoice_doc.extra_info = inv_extra
            # flag کردن تغییرات در JSON field برای SQLAlchemy
            flag_modified(invoice_doc, "extra_info")
            updated_invoice_ids.append(invoice_doc.id)
            total_interest_to_recognize += interest_delta_for_invoice
        if total_interest_to_recognize > 0:
            # عدم ساکت کردن خطا؛ اگر حساب ثابت نبود، خطا می‌دهیم تا وضعیت شفاف باشد
            unearned = _get_fixed_account_by_code(db, "10405")
            earned = _get_fixed_account_by_code(db, "60205")
            db.add(DocumentLine(
                document_id=document.id,
                account_id=unearned.id,
                debit=total_interest_to_recognize,
                credit=Decimal(0),
                description="انتقال سود اقساط از سود تحقق‌نیافته",
                extra_info={"installment": True, "reclassification": True},
            ))
            db.add(DocumentLine(
                document_id=document.id,
                account_id=earned.id,
                debit=Decimal(0),
                credit=total_interest_to_recognize,
                description="شناسایی سود فروش اقساطی",
                extra_info={"installment": True, "reclassification": True},
            ))

    # ذخیره تغییرات
    logger.info(f"=== ذخیره تغییرات ===")
    # flush کردن تغییرات قبل از commit برای اطمینان از ذخیره شدن
    db.flush()
    db.commit()
    db.refresh(document)
    # refresh کردن فاکتورهای اقساطی که به‌روزرسانی شدند
    for invoice_id in updated_invoice_ids:
        invoice_doc = db.query(Document).filter(Document.id == invoice_id).first()
        if invoice_doc:
            db.refresh(invoice_doc)
            logger.info(f"فاکتور اقساطی refresh شد: id={invoice_id}")
            # بررسی محتوای extra_info بعد از refresh
            if invoice_doc.extra_info:
                plan = invoice_doc.extra_info.get("installment_plan")
                if plan:
                    schedule = plan.get("schedule", [])
                    logger.info(f"   تعداد اقساط در فاکتور: {len(schedule)}")
                    for item in schedule:
                        seq = item.get("seq")
                        status = item.get("status")
                        paid = item.get("paid_amount", 0)
                        total = item.get("total", 0)
                        logger.info(f"   قسط #{seq}: status={status}, paid={paid}, total={total}")
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
    logger.info(f"فیلتر نوع سند: {doc_type}")
    if doc_type:
        q = q.filter(Document.document_type == doc_type)
        logger.info(f"فیلتر نوع سند اعمال شد: {doc_type}")
    else:
        logger.info("فیلتر نوع سند اعمال نشد - نمایش همه انواع")
    
    # فیلتر بر اساس تاریخ
    from_date = query.get("from_date")
    to_date = query.get("to_date")
    
    if from_date:
        try:
            from_dt = _parse_iso_date(from_date)
            q = q.filter(Document.document_date >= from_dt)
            logger.info(f"فیلتر تاریخ از: {from_date} -> {from_dt}")
        except Exception as e:
            logger.warning(f"خطا در پردازش تاریخ از: {from_date}, خطا: {e}")
            pass
    
    if to_date:
        try:
            to_dt = _parse_iso_date(to_date)
            q = q.filter(Document.document_date <= to_dt)
            logger.info(f"فیلتر تاریخ تا: {to_date} -> {to_dt}")
        except Exception as e:
            logger.warning(f"خطا در پردازش تاریخ تا: {to_date}, خطا: {e}")
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
    logger.info(f"[UPDATE_RECEIPT_PAYMENT] شروع ویرایش سند {document_id}")
    logger.info(f"[UPDATE_RECEIPT_PAYMENT] data دریافتی: {data}")
    document = db.query(Document).filter(Document.id == document_id).first()
    if document is None:
        raise ApiError("DOCUMENT_NOT_FOUND", "Document not found", http_status=404)
    logger.info(f"[UPDATE_RECEIPT_PAYMENT] document.extra_info قبل از تغییر: {document.extra_info}")

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
    if isinstance(data.get("description"), str) or data.get("description") is None:
        document.description = data.get("description")

    # تعیین نوع دریافت/پرداخت برای محاسبات بدهکار/بستانکار
    is_receipt = (document.document_type == DOCUMENT_TYPE_RECEIPT)
    logger.info(f"[UPDATE_RECEIPT_PAYMENT] document.document_type={document.document_type}, is_receipt={is_receipt}")

    # امکان override نوع حساب طرف‌شخص (دریافتنی/پرداختنی) از extra_info در ویرایش
    extra_info_all = data.get("extra_info") or document.extra_info or {}
    logger.info(f"[UPDATE_RECEIPT_PAYMENT] extra_info_all: {extra_info_all}")
    person_is_receivable_override = extra_info_all.get("person_is_receivable")
    if isinstance(person_is_receivable_override, bool):
        is_person_receivable = person_is_receivable_override
    else:
        is_person_receivable = is_receipt

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
        person_account = _get_person_account(db, document.business_id, int(person_id), is_receivable=is_person_receivable)
        debit_amount = amount if not is_receipt else Decimal(0)
        credit_amount = amount if is_receipt else Decimal(0)
        
        # ساخت extra_info برای خط شخص
        line_extra_info = {
            "person_id": int(person_id),
            "person_name": person_line.get("person_name"),
        }
        
        # اضافه کردن اطلاعات فاکتور از extra_info شخص
        person_line_extra = person_line.get("extra_info")
        if isinstance(person_line_extra, dict):
            if person_line_extra.get("invoice_id"):
                line_extra_info["invoice_id"] = person_line_extra["invoice_id"]
            if person_line_extra.get("invoice_code"):
                line_extra_info["invoice_code"] = person_line_extra["invoice_code"]
            if person_line_extra.get("link_to_invoice"):
                line_extra_info["link_to_invoice"] = person_line_extra["link_to_invoice"]
        
        line = DocumentLine(
            document_id=document.id,
            account_id=person_account.id,
            person_id=int(person_id),
            quantity=person_line.get("quantity"),
            debit=debit_amount,
            credit=credit_amount,
            description=description,
            extra_info=line_extra_info,
        )
        db.add(line)

    # --- اعتبارسنجی اقساط در ویرایش (هم‌راستا با ایجاد) ---
    extra_info_all = data.get("extra_info") or {}
    settlements_input = extra_info_all.get("settlements") or []
    logger.info(f"[UPDATE_RECEIPT_PAYMENT] settlements_input برای validation: {settlements_input}")
    if settlements_input:
        # فقط روی دریافت مجاز است
        if not is_receipt:
            logger.error(f"[UPDATE_RECEIPT_PAYMENT] خطا: settlements برای payment مجاز نیست")
            raise ApiError(
                "INSTALLMENT_NOT_ALLOWED_FOR_PAYMENT",
                "تخصیص اقساط فقط در اسناد دریافت مجاز است",
                http_status=400,
            )
        person_amount_by_id: Dict[int, Decimal] = {}
        for pl in person_lines:
            try:
                pid = int(pl.get("person_id"))
                amt = Decimal(str(pl.get("amount", 0) or 0))
                if pid and amt > 0:
                    person_amount_by_id[pid] = person_amount_by_id.get(pid, Decimal(0)) + amt
            except Exception:
                continue
        logger.info(f"[UPDATE_RECEIPT_PAYMENT] person_amount_by_id: {person_amount_by_id}")
        
        # یافتن allocations قبلی این سند برای کم کردن از paid_amount در validation
        old_settlements = (document.extra_info or {}).get("settlements") or []
        logger.info(f"[UPDATE_RECEIPT_PAYMENT] old_settlements برای validation: {old_settlements}")
        
        allocated_by_person: Dict[int, Decimal] = {}
        for st in settlements_input:
            try:
                st_person_id = int(st.get("person_id"))
            except Exception:
                raise ApiError("INSTALLMENT_PERSON_REQUIRED", "برای هر تخصیص قسط، person_id الزامی است", http_status=400)
            if st_person_id not in person_amount_by_id:
                raise ApiError("INSTALLMENT_PERSON_MISMATCH", "شخص تخصیص قسط باید در خطوط اشخاص سند وجود داشته باشد", http_status=400)
            try:
                invoice_id = int(st.get("invoice_id"))
            except Exception:
                raise ApiError("INSTALLMENT_INVOICE_INVALID", "شناسه فاکتور اقساط نامعتبر است", http_status=400)
            invoice_doc = db.query(Document).filter(Document.id == invoice_id).first()
            if not invoice_doc:
                raise ApiError("INSTALLMENT_INVOICE_NOT_FOUND", "فاکتور اقساط پیدا نشد", http_status=404)
            if int(invoice_doc.currency_id) != int(currency_id):
                raise ApiError("INSTALLMENT_CURRENCY_MISMATCH", "ارز فاکتور اقساط با ارز سند دریافت یکسان نیست", http_status=400)
            inv_extra = invoice_doc.extra_info or {}
            plan = inv_extra.get("installment_plan")
            schedule = (plan or {}).get("schedule")
            if not (isinstance(plan, dict) and isinstance(schedule, list) and schedule):
                raise ApiError("INSTALLMENT_PLAN_NOT_FOUND", "برای فاکتور انتخاب‌شده، طرح اقساط ثبت نشده است", http_status=404)
            
            # یافتن allocations قبلی این سند برای این فاکتور
            old_allocations_by_seq_for_validation: Dict[int, Decimal] = {}
            for old_st in old_settlements:
                if int(old_st.get("invoice_id", 0)) == invoice_id:
                    old_allocs = old_st.get("allocations") or []
                    for old_al in old_allocs:
                        old_seq = int(old_al.get("seq", 0))
                        old_amt = Decimal(str(old_al.get("amount", 0) or 0))
                        if old_seq > 0 and old_amt > 0:
                            old_allocations_by_seq_for_validation[old_seq] = old_allocations_by_seq_for_validation.get(old_seq, Decimal(0)) + old_amt
            logger.info(f"[UPDATE_RECEIPT_PAYMENT] old_allocations_by_seq_for_validation برای فاکتور {invoice_id}: {old_allocations_by_seq_for_validation}")
            
            remaining_by_seq: Dict[int, Decimal] = {}
            for item in schedule:
                try:
                    seq_i = int(item.get("seq") or 0)
                    total_i = Decimal(str(item.get("total", 0) or 0))
                    paid_i = Decimal(str(item.get("paid_amount", 0) or 0))
                    # کم کردن allocations قبلی این سند از paid_amount
                    old_alloc_for_seq = old_allocations_by_seq_for_validation.get(seq_i, Decimal(0))
                    paid_i_adjusted = max(paid_i - old_alloc_for_seq, Decimal(0))
                    remaining_by_seq[seq_i] = max(total_i - paid_i_adjusted, Decimal(0))
                    logger.info(f"[UPDATE_RECEIPT_PAYMENT] validation قسط {seq_i}: total={total_i}, paid_i={paid_i}, old_alloc={old_alloc_for_seq}, paid_i_adjusted={paid_i_adjusted}, remaining={remaining_by_seq[seq_i]}")
                except Exception:
                    continue
            allocations = st.get("allocations") or []
            if not isinstance(allocations, list) or not allocations:
                raise ApiError("INSTALLMENT_ALLOCATIONS_REQUIRED", "لیست تخصیص اقساط خالی است", http_status=400)
            for al in allocations:
                try:
                    seq = int(al.get("seq"))
                    amt = Decimal(str(al.get("amount", 0) or 0))
                except Exception:
                    raise ApiError("INSTALLMENT_ALLOCATION_INVALID", "تخصیص قسط نامعتبر است", http_status=400)
                if seq <= 0 or amt <= 0:
                    raise ApiError("INSTALLMENT_ALLOCATION_INVALID", "تخصیص قسط نامعتبر است", http_status=400)
                remain = remaining_by_seq.get(seq, None)
                if remain is None:
                    raise ApiError("INSTALLMENT_SEQ_NOT_FOUND", "شماره قسط در طرح اقساط یافت نشد", http_status=404)
                logger.info(f"[UPDATE_RECEIPT_PAYMENT] validation قسط {seq}: alloc={amt}, remain={remain}")
                if amt > remain:
                    logger.error(f"[UPDATE_RECEIPT_PAYMENT] خطا در validation قسط {seq}: alloc={amt} > remain={remain}")
                    raise ApiError("INSTALLMENT_OVERPAY_PER_SEQ", "مبلغ تخصیص از مانده همان قسط بیشتر است", http_status=400)
                allocated_by_person[st_person_id] = allocated_by_person.get(st_person_id, Decimal(0)) + amt
        for pid, alloc_sum in allocated_by_person.items():
            if alloc_sum > person_amount_by_id.get(pid, Decimal(0)):
                raise ApiError("INSTALLMENT_OVER_PERSON_LINES", "جمع تخصیص اقساط یک شخص از مجموع مبلغ خطوط همان شخص بیشتر است", http_status=400)

    # خطوط حساب‌ها + کارمزدها
    total_commission = Decimal(0)
    for i, account_line in enumerate(account_lines):
        amount = Decimal(str(account_line.get("amount", 0)))
        if amount <= 0:
            continue
        description = (account_line.get("description") or "").strip() or None
        transaction_type = account_line.get("transaction_type")
        normalized_transaction_type = transaction_type
        if transaction_type == "check_expense":
            normalized_transaction_type = "check"
        transaction_date = account_line.get("transaction_date")
        commission = account_line.get("commission")
        if commission:
            total_commission += Decimal(str(commission))

        # انتخاب حساب بر اساس transaction_type یا account_id
        account = None
        check_id_val: Optional[int] = None
        if normalized_transaction_type == "check":
            check_obj, check_id_val = _validate_check_transaction_line(
                db,
                business_id=document.business_id,
                account_line=account_line,
                is_receipt=is_receipt,
                document_currency_id=currency_id,
                amount_decimal=amount,
                exclude_document_id=document.id,
            )
            account_line["check_id"] = check_id_val
            if not account_line.get("check_number"):
                account_line["check_number"] = check_obj.check_number

        if normalized_transaction_type == "bank":
            account = _get_fixed_account_by_code(db, "10203")
        elif normalized_transaction_type == "cash_register":
            account = _get_fixed_account_by_code(db, "10202")
        elif normalized_transaction_type == "petty_cash":
            account = _get_fixed_account_by_code(db, "10201")
        elif normalized_transaction_type == "check":
            account = _get_fixed_account_by_code(db, "10403" if is_receipt else "20202")
        elif normalized_transaction_type == "person":
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
        if normalized_transaction_type == "bank":
            if account_line.get("bank_id"):
                extra_info["bank_id"] = account_line.get("bank_id")
            if account_line.get("bank_name"):
                extra_info["bank_name"] = account_line.get("bank_name")
        elif normalized_transaction_type == "cash_register":
            if account_line.get("cash_register_id"):
                extra_info["cash_register_id"] = account_line.get("cash_register_id")
            if account_line.get("cash_register_name"):
                extra_info["cash_register_name"] = account_line.get("cash_register_name")
        elif normalized_transaction_type == "petty_cash":
            if account_line.get("petty_cash_id"):
                extra_info["petty_cash_id"] = account_line.get("petty_cash_id")
            if account_line.get("petty_cash_name"):
                extra_info["petty_cash_name"] = account_line.get("petty_cash_name")
        elif normalized_transaction_type == "check":
            if account_line.get("check_id"):
                extra_info["check_id"] = int(account_line.get("check_id"))
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

        resolved_check_id = check_id_val
        if resolved_check_id is None and account_line.get("check_id"):
            try:
                resolved_check_id = int(account_line.get("check_id"))
            except Exception:
                resolved_check_id = None

        line = DocumentLine(
            document_id=document.id,
            account_id=account.id,
            person_id=person_id_for_line,
            bank_account_id=bank_account_id,
            cash_register_id=account_line.get("cash_register_id"),
            petty_cash_id=account_line.get("petty_cash_id"),
            check_id=resolved_check_id,
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
            normalized_transaction_type = transaction_type
            if transaction_type == "check_expense":
                normalized_transaction_type = "check"
            commission_account_code = None
            if normalized_transaction_type == "bank":
                commission_account_code = "10203"
            elif normalized_transaction_type == "cash_register":
                commission_account_code = "10202"
            elif normalized_transaction_type == "petty_cash":
                commission_account_code = "10201"
            elif normalized_transaction_type == "check":
                commission_account_code = "10403" if is_receipt else "20202"
            elif normalized_transaction_type == "person":
                commission_account_code = "20201"
            if commission_account_code:
                commission_account = _get_fixed_account_by_code(db, commission_account_code)
                commission_debit = commission_amount if not is_receipt else Decimal(0)
                commission_credit = commission_amount if is_receipt else Decimal(0)
                commission_check_id = None
                if account_line.get("check_id"):
                    try:
                        commission_check_id = int(account_line.get("check_id"))
                    except Exception:
                        commission_check_id = None
                db.add(DocumentLine(
                    document_id=document.id,
                    account_id=commission_account.id,
                    bank_account_id=account_line.get("bank_id"),
                    cash_register_id=account_line.get("cash_register_id"),
                    petty_cash_id=account_line.get("petty_cash_id"),
                    check_id=commission_check_id,
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

    # --- اعمال اقساط در ویرایش، مشابه ایجاد ---
    settlements = (data.get("extra_info") or {}).get("settlements") or []
    logger.info(f"[UPDATE_RECEIPT_PAYMENT] settlements جدید از data: {settlements}")
    total_interest_to_recognize = Decimal(0)
    updated_invoice_ids: List[int] = []
    if is_receipt and isinstance(settlements, list) and settlements:
        logger.info(f"[UPDATE_RECEIPT_PAYMENT] تعداد settlements: {len(settlements)}")
        for st in settlements:
            invoice_id = int(st.get("invoice_id"))
            invoice_doc = db.query(Document).filter(Document.id == invoice_id).first()
            if not invoice_doc:
                raise ApiError("INSTALLMENT_INVOICE_NOT_FOUND", "فاکتور اقساط پیدا نشد", http_status=404)
            inv_extra = invoice_doc.extra_info or {}
            plan = inv_extra.get("installment_plan")
            schedule = (plan or {}).get("schedule")
            logger.info(f"[INSTALLMENT] فاکتور {invoice_id}: plan={plan}")
            logger.info(f"[INSTALLMENT] فاکتور {invoice_id}: schedule={schedule}")
            if not (isinstance(plan, dict) and isinstance(schedule, list) and schedule):
                raise ApiError("INSTALLMENT_PLAN_NOT_FOUND", "طرح اقساط برای فاکتور یافت نشد", http_status=404)
            allocations = st.get("allocations") or []
            logger.info(f"[INSTALLMENT] شروع پردازش allocations برای فاکتور {invoice_id} (سند {document.id})")
            
            # یافتن allocations قبلی این سند برای کم کردن از paid_amount
            old_settlements = (document.extra_info or {}).get("settlements") or []
            old_allocations_by_seq: Dict[int, Decimal] = {}
            logger.info(f"[INSTALLMENT] old_settlements برای فاکتور {invoice_id}: {old_settlements}")
            for old_st in old_settlements:
                if int(old_st.get("invoice_id", 0)) == invoice_id:
                    old_allocs = old_st.get("allocations") or []
                    logger.info(f"[INSTALLMENT] old_allocs برای فاکتور {invoice_id}: {old_allocs}")
                    for old_al in old_allocs:
                        old_seq = int(old_al.get("seq", 0))
                        old_amt = Decimal(str(old_al.get("amount", 0) or 0))
                        if old_seq > 0 and old_amt > 0:
                            old_allocations_by_seq[old_seq] = old_allocations_by_seq.get(old_seq, Decimal(0)) + old_amt
            logger.info(f"[INSTALLMENT] old_allocations_by_seq برای فاکتور {invoice_id}: {old_allocations_by_seq}")
            
            seq_to_amount: Dict[int, Decimal] = {}
            logger.info(f"[INSTALLMENT] allocations جدید برای فاکتور {invoice_id}: {allocations}")
            for al in allocations:
                seq = int(al.get("seq"))
                amt = Decimal(str(al.get("amount", 0) or 0))
                if seq <= 0 or amt <= 0:
                    raise ApiError("INSTALLMENT_ALLOCATION_INVALID", "تخصیص قسط نامعتبر است", http_status=400)
                seq_to_amount[seq] = seq_to_amount.get(seq, Decimal(0)) + amt
            logger.info(f"[INSTALLMENT] seq_to_amount برای فاکتور {invoice_id}: {seq_to_amount}")
            
            # بررسی اینکه آیا allocations جدید با allocations قبلی یکسان هستند
            # باید هم seq ها و هم amount ها را بررسی کنیم
            allocations_changed = False
            old_seqs = set(old_allocations_by_seq.keys())
            new_seqs = set(seq_to_amount.keys())
            
            # بررسی تغییرات در seq ها
            if old_seqs != new_seqs:
                allocations_changed = True
                logger.info(f"[INSTALLMENT] seq های allocations تغییر کرده: old_seqs={old_seqs}, new_seqs={new_seqs}")
            else:
                # اگر seq ها یکسان باشند، amount ها را بررسی می‌کنیم
                for seq in new_seqs:
                    old_amt = old_allocations_by_seq.get(seq, Decimal(0))
                    new_amt = seq_to_amount.get(seq, Decimal(0))
                    diff = abs(new_amt - old_amt)
                    logger.info(f"[INSTALLMENT] مقایسه قسط {seq}: old={old_amt}, new={new_amt}, diff={diff}")
                    if diff > Decimal("0.01"):  # tolerance برای خطای ممیز شناور
                        allocations_changed = True
                        logger.info(f"[INSTALLMENT] قسط {seq} تغییر کرده: diff={diff} > 0.01")
                        break
            logger.info(f"[INSTALLMENT] allocations_changed برای فاکتور {invoice_id}: {allocations_changed}")
            
            remaining_by_seq: Dict[int, Decimal] = {}
            logger.info(f"[INSTALLMENT] محاسبه remaining_by_seq برای فاکتور {invoice_id}")
            for item in schedule:
                seq_i = int(item.get("seq") or 0)
                total_i = Decimal(str(item.get("total", 0) or 0))
                paid_i = Decimal(str(item.get("paid_amount", 0) or 0))
                # کم کردن allocations قبلی این سند از paid_amount
                old_alloc_for_seq = old_allocations_by_seq.get(seq_i, Decimal(0))
                paid_i_adjusted = max(paid_i - old_alloc_for_seq, Decimal(0))
                remaining = max(total_i - paid_i_adjusted, Decimal(0))
                remaining_by_seq[seq_i] = remaining
                logger.info(f"[INSTALLMENT] قسط {seq_i}: total={total_i}, paid_i={paid_i}, old_alloc={old_alloc_for_seq}, paid_i_adjusted={paid_i_adjusted}, remaining={remaining}")
            
            # اعتبارسنجی فقط اگر allocations تغییر کرده باشند
            if allocations_changed:
                logger.info(f"[INSTALLMENT] اعتبارسنجی allocations برای فاکتور {invoice_id}")
                for seq, alloc in seq_to_amount.items():
                    remain = remaining_by_seq.get(seq)
                    if remain is None:
                        logger.error(f"[INSTALLMENT] قسط {seq} در schedule یافت نشد")
                        raise ApiError("INSTALLMENT_SEQ_NOT_FOUND", "شماره قسط یافت نشد", http_status=404)
                    logger.info(f"[INSTALLMENT] اعتبارسنجی قسط {seq}: alloc={alloc}, remain={remain}")
                    if alloc > remain:
                        logger.error(f"[INSTALLMENT] خطا در قسط {seq}: alloc={alloc} > remain={remain}")
                        logger.error(f"[INSTALLMENT] جزئیات قسط {seq}: total={schedule[seq-1].get('total') if seq <= len(schedule) else 'N/A'}, paid_i={schedule[seq-1].get('paid_amount') if seq <= len(schedule) else 'N/A'}, old_alloc={old_allocations_by_seq.get(seq, 0)}")
                        raise ApiError("INSTALLMENT_OVERPAY_PER_SEQ", "مبلغ تخصیص از مانده قسط بیشتر است", http_status=400)
                logger.info(f"[INSTALLMENT] اعتبارسنجی موفق برای فاکتور {invoice_id}")
            else:
                # اگر allocations تغییر نکرده باشند، از اعمال مجدد صرف نظر می‌کنیم
                logger.info(f"[INSTALLMENT] allocations برای فاکتور {invoice_id} تغییر نکرده است، از اعمال مجدد صرف نظر می‌کنیم")
                continue
            interest_delta_for_invoice = Decimal(0)
            new_schedule: List[Dict[str, Any]] = []
            logger.info(f"[INSTALLMENT] شروع اعمال allocations برای فاکتور {invoice_id}")
            for item in schedule:
                seq = int(item.get("seq") or 0)
                paid_before_raw = Decimal(str(item.get("paid_amount", 0) or 0))
                # کم کردن allocations قبلی این سند از paid_before (فقط در حالت ویرایش)
                old_alloc_for_seq = old_allocations_by_seq.get(seq, Decimal(0))
                paid_before = max(paid_before_raw - old_alloc_for_seq, Decimal(0))
                interest_part = Decimal(str(item.get("interest", 0) or 0))
                total_part = Decimal(str(item.get("total", 0) or 0))
                alloc_amt = seq_to_amount.get(seq, Decimal(0))
                paid_after = paid_before + alloc_amt
                logger.info(f"[INSTALLMENT] قسط {seq}: paid_before_raw={paid_before_raw}, old_alloc={old_alloc_for_seq}, paid_before={paid_before}, alloc_amt={alloc_amt}, paid_after={paid_after}")
                
                # محاسبه interest_delta: فقط برای allocations جدید (نه allocations قبلی)
                # اگر allocations قبلی وجود داشته باشد، interest_delta قبلی را rollback می‌کنیم
                # interest_delta قبلی = interest_delta که با allocations قبلی ایجاد شده بود
                # interest_delta جدید = interest_delta که با allocations جدید ایجاد می‌شود
                # interest_delta کل = interest_delta جدید - interest_delta قبلی
                prev_interest_recognized_with_old = min(paid_before_raw, interest_part)
                prev_interest_recognized_without_old = min(paid_before, interest_part)
                new_interest_recognized = min(paid_after, interest_part)
                # interest_delta قبلی (که باید rollback شود)
                old_interest_delta = prev_interest_recognized_with_old - prev_interest_recognized_without_old
                # interest_delta جدید (با allocations جدید)
                new_interest_delta = new_interest_recognized - prev_interest_recognized_without_old
                # interest_delta کل = جدید - قبلی
                delta = new_interest_delta - old_interest_delta
                logger.info(f"[INSTALLMENT] قسط {seq} interest_delta: interest_part={interest_part}, prev_with_old={prev_interest_recognized_with_old}, prev_without_old={prev_interest_recognized_without_old}, new={new_interest_recognized}, old_delta={old_interest_delta}, new_delta={new_interest_delta}, delta={delta}")
                if delta > 0:
                    interest_delta_for_invoice += delta
                elif delta < 0:
                    # اگر allocations جدید کمتر از allocations قبلی باشد، interest_delta منفی می‌شود
                    interest_delta_for_invoice += delta
                # محاسبه status با tolerance برای خطای ممیز شناور
                tolerance = Decimal("0.01")
                if total_part > 0 and (paid_after >= total_part or (total_part - paid_after) <= tolerance):
                    new_status = "paid"
                elif paid_after > tolerance:
                    new_status = "partial"
                else:
                    new_status = "pending"
                logger.info(f"[INSTALLMENT] قسط {seq}: total={total_part}, status={new_status}")
                new_item = dict(item)
                new_item["paid_amount"] = float(paid_after)
                new_item["status"] = new_status
                new_schedule.append(new_item)
            new_plan = dict(plan or {})
            new_plan["schedule"] = new_schedule
            inv_extra["installment_plan"] = new_plan
            invoice_doc.extra_info = inv_extra
            # flag کردن تغییرات در JSON field برای SQLAlchemy
            flag_modified(invoice_doc, "extra_info")
            updated_invoice_ids.append(invoice_doc.id)
            total_interest_to_recognize += interest_delta_for_invoice
        if total_interest_to_recognize > 0:
            unearned = _get_fixed_account_by_code(db, "10405")
            earned = _get_fixed_account_by_code(db, "60205")
            db.add(DocumentLine(
                document_id=document.id,
                account_id=unearned.id,
                debit=total_interest_to_recognize,
                credit=Decimal(0),
                description="انتقال سود اقساط از سود تحقق‌نیافته",
                extra_info={"installment": True, "reclassification": True},
            ))
            db.add(DocumentLine(
                document_id=document.id,
                account_id=earned.id,
                debit=Decimal(0),
                credit=total_interest_to_recognize,
                description="شناسایی سود فروش اقساطی",
                extra_info={"installment": True, "reclassification": True},
            ))

    # flush کردن تغییرات قبل از commit برای اطمینان از ذخیره شدن
    db.flush()
    db.commit()
    db.refresh(document)
    # refresh کردن فاکتورهای اقساطی که به‌روزرسانی شدند
    for invoice_id in updated_invoice_ids:
        invoice_doc = db.query(Document).filter(Document.id == invoice_id).first()
        if invoice_doc:
            db.refresh(invoice_doc)
            logger.info(f"فاکتور اقساطی refresh شد: id={invoice_id}")
            # بررسی محتوای extra_info بعد از refresh
            if invoice_doc.extra_info:
                plan = invoice_doc.extra_info.get("installment_plan")
                if plan:
                    schedule = plan.get("schedule", [])
                    logger.info(f"   تعداد اقساط در فاکتور: {len(schedule)}")
                    for item in schedule:
                        seq = item.get("seq")
                        status = item.get("status")
                        paid = item.get("paid_amount", 0)
                        total = item.get("total", 0)
                        logger.info(f"   قسط #{seq}: status={status}, paid={paid}, total={total}")
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
            # اضافه کردن اطلاعات فاکتور از extra_info
            if "invoice_id" in line.extra_info:
                line_dict["invoice_id"] = line.extra_info["invoice_id"]
            if "invoice_code" in line.extra_info:
                line_dict["invoice_code"] = line.extra_info["invoice_code"]
            if "link_to_invoice" in line.extra_info:
                line_dict["link_to_invoice"] = line.extra_info["link_to_invoice"]
        
        # اگر person_id موجود است، نام شخص را از دیتابیس دریافت کن
        if line.person_id and "person_name" not in line_dict:
            person = db.query(Person).filter(Person.id == line.person_id).first()
            if person:
                line_dict["person_name"] = person.alias_name or f"{person.first_name} {person.last_name}".strip()
            else:
                line_dict["person_name"] = "نامشخص"
        
        # تشخیص اینکه آیا این خط مربوط به شخص است یا حساب
        # خطوط کارمزد را جداگانه تشخیص می‌دهیم
        # خطوط اقساط (سود تحقق‌نیافته و سود فروش اقساطی) را از نمایش حذف می‌کنیم
        is_commission_line = line.extra_info and line.extra_info.get("is_commission_line", False)
        is_installment_line = line.extra_info and (line.extra_info.get("installment", False) or line.extra_info.get("reclassification", False))
        
        # خطوط اقساط را از نمایش حذف می‌کنیم (فقط در پشت صحنه ثبت می‌شوند)
        if is_installment_line:
            continue  # این خط را نادیده بگیر و به لیست اضافه نکن
        
        if is_commission_line:
            # خط کارمزد - در account_lines قرار می‌گیرد
            account_lines.append(line_dict)
        elif line.extra_info and line.extra_info.get("person_id"):
            # خط شخص
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
        "description": document.description,
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

