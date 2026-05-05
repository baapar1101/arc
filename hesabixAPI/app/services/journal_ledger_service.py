from __future__ import annotations

from typing import Any, Dict, List, Optional
from datetime import date
from decimal import Decimal

from sqlalchemy.orm import Session
from sqlalchemy import and_, func

from adapters.db.models.document import Document
from adapters.db.models.document_line import DocumentLine
from adapters.db.models.account import Account
from adapters.db.models.fiscal_year import FiscalYear
from adapters.db.models.person import Person
from app.services.opening_balance_service import _ensure_fiscal_year


def _parse_iso_date(dt: str | date) -> date:
    if isinstance(dt, date):
        return dt
    if isinstance(dt, str):
        return date.fromisoformat(dt.split('T')[0])
    raise ValueError(f"Invalid date format: {dt}")


def _get_document_type_name(doc_type: str | None) -> str:
    """تبدیل نوع سند به نام فارسی"""
    if not doc_type:
        return ''
    
    mapping = {
        'invoice_sales': 'فاکتور فروش',
        'invoice_sales_return': 'برگشت از فروش',
        'invoice_purchase': 'فاکتور خرید',
        'invoice_purchase_return': 'برگشت از خرید',
        'invoice_production': 'فاکتور تولید',
        'invoice_direct_consumption': 'مصرف مستقیم',
        'invoice_waste': 'ضایعات',
        'receipt': 'دریافت',
        'payment': 'پرداخت',
        'transfer': 'انتقال',
        'expense': 'هزینه',
        'income': 'درآمد',
        'expense_income': 'درآمد/هزینه',
        'opening_balance': 'تراز افتتاحیه',
        'manual': 'سند دستی',
        'manual_document': 'سند دستی',
        'check_endorse': 'پاسخگویی چک',
        'check_clear': 'وصول چک',
        'check_pay': 'پرداخت چک',
        'check_return': 'برگشت چک',
        'check_bounce': 'برگشت خوردن چک',
        'check_deposit': 'واریز به حساب',
        'check_delete': 'حذف چک',
    }
    return mapping.get(doc_type, doc_type)


def _find_general_account(account_id: int, accounts_map: Dict[int, Dict[str, Any]]) -> Optional[Dict[str, Any]]:
    """
    پیدا کردن حساب کل با پیمایش به سمت بالا تا parent_id = NULL
    
    Args:
        account_id: شناسه حساب
        accounts_map: دیکشنری کامل تمام حساب‌ها با parent_id
    
    Returns:
        دیکشنری حساب کل یا None
    """
    if account_id not in accounts_map:
        return None
    
    current_id = account_id
    visited = set()  # جلوگیری از حلقه بی‌نهایت
    
    while current_id and current_id in accounts_map:
        if current_id in visited:
            break  # حلقه پیدا شد
        visited.add(current_id)
        
        account = accounts_map[current_id]
        # اگر parent_id ندارد، این حساب کل است
        if account['parent_id'] is None:
            return account
        
        # به والد برو
        current_id = account['parent_id']
    
    return None


def _find_subsidiary_account(
    account_id: int, 
    accounts_map: Dict[int, Dict[str, Any]], 
    general_account: Optional[Dict[str, Any]]
) -> Optional[Dict[str, Any]]:
    """
    پیدا کردن حساب معین:
    - اگر خود حساب، مستقیماً زیر حساب کل است → خودش حساب معین است
    - اگر حساب زیر حساب معین است → والد مستقیم حساب معین است
    
    Args:
        account_id: شناسه حساب
        accounts_map: دیکشنری کامل تمام حساب‌ها با parent_id
        general_account: حساب کل (اگر پیدا شده باشد)
    
    Returns:
        دیکشنری حساب معین یا None
    """
    if account_id not in accounts_map:
        return None
    
    account = accounts_map[account_id]
    
    # اگر خودش حساب کل است
    if account['parent_id'] is None:
        return None  # حساب معین ندارد
    
    # اگر حساب کل پیدا نشده، ابتدا آن را پیدا کن
    if general_account is None:
        general_account = _find_general_account(account_id, accounts_map)
        if general_account is None:
            return None
    
    # اگر والد مستقیم، حساب کل است
    parent_id = account['parent_id']
    if parent_id == general_account['id']:
        # خود حساب، حساب معین است
        return account
    
    # اگر والد مستقیم، خودش حساب معین است (parent_id آن = حساب کل)
    if parent_id in accounts_map:
        parent = accounts_map[parent_id]
        if parent['parent_id'] == general_account['id']:
            return parent
    
    # در غیر این صورت، به سمت بالا برو تا حساب معین را پیدا کنی
    current_id = account_id
    visited = set()
    
    while current_id and current_id in accounts_map:
        if current_id in visited:
            break
        visited.add(current_id)
        
        acc = accounts_map[current_id]
        if acc['parent_id'] is None:
            break
        
        parent_id = acc['parent_id']
        if parent_id in accounts_map:
            parent = accounts_map[parent_id]
            # اگر والد، مستقیماً زیر حساب کل است
            if parent['parent_id'] == general_account['id']:
                return parent
        
        current_id = parent_id
    
    return None


def get_journal_ledger_report(
    db: Session,
    business_id: int,
    fiscal_year_id: Optional[int] = None,
    currency_id: Optional[int] = None,
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
    document_type: Optional[str] = None,
    project_id: Optional[int] = None,  # 🆕 فیلتر پروژه
    include_proforma: bool = False,
    skip: int = 0,
    take: int = 50,
) -> Dict[str, Any]:
    """
    گزارش دفتر روزنامه
    
    این گزارش تمام تراکنش‌های مالی را به ترتیب تاریخ نمایش می‌دهد:
    - لیست تمام DocumentLine ها مرتب شده بر اساس تاریخ
    - برای هر خط: حساب بدهکار و بستانکار با مبالغ
    - بررسی تراز (جمع بدهکارها باید برابر جمع بستانکارها باشد)
    
    Args:
        db: نشست پایگاه داده
        business_id: شناسه کسب‌وکار
        fiscal_year_id: شناسه سال مالی (اختیاری)
        currency_id: شناسه ارز (اختیاری)
        date_from: از تاریخ (اختیاری، فرمت YYYY-MM-DD)
        date_to: تا تاریخ (اختیاری، فرمت YYYY-MM-DD)
        document_type: نوع سند برای فیلتر (اختیاری)
        include_proforma: شامل اسناد پیش‌نویس (پیش‌فرض: False)
        skip: تعداد رکوردهای رد شده برای pagination
        take: تعداد رکوردهای برگشتی
    
    Returns:
        dict: {
            'items': لیست تراکنش‌ها با حساب بدهکار و بستانکار,
            'summary': خلاصه آمار (جمع بدهکار/بستانکار، وضعیت تراز),
            'pagination': اطلاعات pagination
        }
    """
    fy_id, fy_start_date, _fy_end = _ensure_fiscal_year(db, business_id, fiscal_year_id)
    
    # تبدیل تاریخ‌ها
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
    
    # اگر تاریخ‌ها مشخص نشده‌اند، از سال مالی استفاده کن
    if date_from_obj is None:
        date_from_obj = fy_start_date
    if date_to_obj is None:
        fiscal_year = db.query(FiscalYear).filter(FiscalYear.id == fy_id).first()
        date_to_obj = fiscal_year.end_date if fiscal_year and fiscal_year.end_date else date.today()
    
    # Query خطوط DocumentLine در بازه تاریخ
    lines_query = db.query(
        DocumentLine,
        Document,
    ).join(
        Document, DocumentLine.document_id == Document.id
    ).filter(
        and_(
            Document.business_id == business_id,
            DocumentLine.account_id.isnot(None),
            Document.document_date >= date_from_obj,
            Document.document_date <= date_to_obj,
        )
    )
    
    if not include_proforma:
        lines_query = lines_query.filter(Document.is_proforma == False)
    
    if fiscal_year_id:
        lines_query = lines_query.filter(Document.fiscal_year_id == fy_id)
    
    if currency_id:
        lines_query = lines_query.filter(Document.currency_id == currency_id)
    
    if document_type:
        lines_query = lines_query.filter(Document.document_type == document_type)
    
    # 🆕 فیلتر پروژه
    if project_id:
        lines_query = lines_query.filter(Document.project_id == project_id)
    
    # مرتب‌سازی بر اساس تاریخ سند و سپس شناسه سند و خط
    lines_query = lines_query.order_by(
        Document.document_date.asc(),
        Document.id.asc(),
        DocumentLine.id.asc()
    )
    
    # دریافت تمام خطوط (برای محاسبه summary)
    all_lines = lines_query.all()
    
    # استخراج شناسه‌های حساب و شخص
    account_ids = list(set(
        line.account_id for line, doc in all_lines
        if line.account_id is not None
    ))
    person_ids = list(set(
        line.person_id for line, doc in all_lines
        if line.person_id is not None
    ))
    
    # دریافت تمام حساب‌های کسب‌وکار (برای پیدا کردن حساب کل و معین)
    all_accounts = db.query(Account).filter(
        (Account.business_id == None) | (Account.business_id == business_id)  # noqa: E711
    ).all()
    
    # ساخت دیکشنری کامل از حساب‌ها با parent_id
    accounts_full_map = {}
    for acc in all_accounts:
        accounts_full_map[acc.id] = {
            'id': acc.id,
            'code': acc.code,
            'name': acc.name,
            'parent_id': acc.parent_id,
        }
    
    # دریافت اطلاعات حساب‌های استفاده شده (برای نمایش در خروجی)
    accounts_map = {}
    if account_ids:
        accounts = db.query(Account).filter(Account.id.in_(account_ids)).all()
        for acc in accounts:
            accounts_map[acc.id] = {
                'id': acc.id,
                'code': acc.code,
                'name': acc.name,
            }
    
    # دریافت اطلاعات اشخاص
    persons_map = {}
    if person_ids:
        persons = db.query(Person).filter(Person.id.in_(person_ids)).all()
        for person in persons:
            persons_map[person.id] = {
                'id': person.id,
                'code': person.code,
                'name': person.alias_name or person.name or '',
            }
    
    # ساخت آیتم‌ها
    items = []
    total_debit = Decimal(0)
    total_credit = Decimal(0)
    
    for line, doc in all_lines:
        debit = Decimal(str(line.debit or 0))
        credit = Decimal(str(line.credit or 0))
        
        total_debit += debit
        total_credit += credit
        
        # تعیین حساب بدهکار و بستانکار
        debit_account = None
        credit_account = None
        
        if debit > 0 and line.account_id:
            acc = accounts_map.get(line.account_id)
            if acc:
                debit_account = {
                    'id': acc['id'],
                    'code': acc['code'],
                    'name': acc['name'],
                }
        
        if credit > 0 and line.account_id:
            acc = accounts_map.get(line.account_id)
            if acc:
                credit_account = {
                    'id': acc['id'],
                    'code': acc['code'],
                    'name': acc['name'],
                }
        
        # اطلاعات شخص
        person_info = None
        if line.person_id and line.person_id in persons_map:
            person = persons_map[line.person_id]
            person_info = {
                'id': person['id'],
                'code': person['code'],
                'name': person['name'],
            }
        
        document_type_name = _get_document_type_name(doc.document_type)
        
        # پیدا کردن حساب کل و معین برای حساب استفاده شده در این خط
        # هر خط یک حساب دارد (بدهکار یا بستانکار)
        account_id_for_general_subsidiary = None
        if debit > 0 and line.account_id:
            account_id_for_general_subsidiary = line.account_id
        elif credit > 0 and line.account_id:
            account_id_for_general_subsidiary = line.account_id
        
        general_account = None
        subsidiary_account = None
        if account_id_for_general_subsidiary:
            general_account = _find_general_account(account_id_for_general_subsidiary, accounts_full_map)
            subsidiary_account = _find_subsidiary_account(
                account_id_for_general_subsidiary, 
                accounts_full_map, 
                general_account
            )
        
        items.append({
            'document_id': doc.id,
            'document_code': doc.code or '',
            'document_date': doc.document_date if doc.document_date else None,  # Keep as date object for format_datetime_fields
            'document_type': doc.document_type or '',
            'document_type_name': document_type_name,
            'description': line.description or doc.description or '',
            'general_account_code': general_account['code'] if general_account else None,
            'general_account_name': general_account['name'] if general_account else None,
            'subsidiary_account_code': subsidiary_account['code'] if subsidiary_account else None,
            'subsidiary_account_name': subsidiary_account['name'] if subsidiary_account else None,
            'debit_account_id': debit_account['id'] if debit_account else None,
            'debit_account_code': debit_account['code'] if debit_account else None,
            'debit_account_name': debit_account['name'] if debit_account else None,
            'debit_amount': float(debit),
            'credit_account_id': credit_account['id'] if credit_account else None,
            'credit_account_code': credit_account['code'] if credit_account else None,
            'credit_account_name': credit_account['name'] if credit_account else None,
            'credit_amount': float(credit),
            'person_id': person_info['id'] if person_info else None,
            'person_name': person_info['name'] if person_info else None,
            'person_code': person_info['code'] if person_info else None,
        })
    
    # Pagination
    total = len(items)
    current_page = (skip // take) + 1
    total_pages = (total + take - 1) // take if take > 0 else 1
    paginated_items = items[skip:skip + take]
    
    # بررسی تراز (Trial Balance Check)
    balance_valid = True
    balance_diff = Decimal(0)
    tolerance = Decimal('0.01')  # تحمل خطای گرد کردن
    
    balance_diff = abs(total_debit - total_credit)
    if balance_diff > tolerance:
        balance_valid = False
    
    return {
        'items': paginated_items,
        'summary': {
            'total_debit': float(total_debit),
            'total_credit': float(total_credit),
            'balance_valid': balance_valid,
            'balance_diff': float(balance_diff),
        },
        'pagination': {
            'total': total,
            'page': current_page,
            'per_page': take,
            'total_pages': total_pages,
            'has_next': current_page < total_pages,
            'has_prev': current_page > 1,
        }
    }

