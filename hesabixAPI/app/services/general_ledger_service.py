from __future__ import annotations

from typing import Any, Dict, List, Optional
from datetime import date, timedelta
from decimal import Decimal

from sqlalchemy.orm import Session
from sqlalchemy import and_, func

from adapters.db.models.document import Document
from adapters.db.models.document_line import DocumentLine
from adapters.db.models.account import Account
from adapters.db.models.fiscal_year import FiscalYear
from adapters.db.models.person import Person
from adapters.db.models.bank_account import BankAccount
from adapters.db.models.cash_register import CashRegister
from adapters.db.models.petty_cash import PettyCash
from adapters.db.models.product import Product
from app.services.opening_balance_service import _find_existing_ob_document
from adapters.db.repositories.document_repository import DocumentRepository


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
        'expense_income': 'درآمد/هزینه',
        'opening_balance': 'تراز افتتاحیه',
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


def get_general_ledger_report(
    db: Session,
    business_id: int,
    account_ids: List[int],  # اجباری - لیست حساب‌ها
    fiscal_year_id: Optional[int] = None,
    currency_id: Optional[int] = None,
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
    person_id: Optional[int] = None,
    include_proforma: bool = False,
    skip: int = 0,
    take: int = 50,
) -> Dict[str, Any]:
    """
    گزارش دفتر کل
    
    این گزارش برای یک یا چند حساب حسابداری نمایش می‌دهد:
    - لیست تمام تراکنش‌ها (DocumentLine) مرتب شده بر اساس تاریخ
    - مانده ابتدای دوره
    - مانده تجمعی بعد از هر تراکنش
    - مانده انتهای دوره
    
    Args:
        db: نشست پایگاه داده
        business_id: شناسه کسب‌وکار
        account_ids: لیست شناسه‌های حساب (اجباری)
        fiscal_year_id: شناسه سال مالی (اختیاری)
        currency_id: شناسه ارز (اختیاری)
        date_from: از تاریخ (اختیاری، فرمت YYYY-MM-DD)
        date_to: تا تاریخ (اختیاری، فرمت YYYY-MM-DD)
        person_id: شناسه شخص برای فیلتر (اختیاری)
        include_proforma: شامل اسناد پیش‌نویس (پیش‌فرض: False)
        skip: تعداد رکوردهای رد شده برای pagination
        take: تعداد رکوردهای برگشتی
    
    Returns:
        dict: {
            'items': لیست تراکنش‌ها با مانده تجمعی,
            'summary': خلاصه آمار (مانده ابتدای دوره، جمع بدهکار/بستانکار، مانده انتهای دوره),
            'pagination': اطلاعات pagination
        }
    """
    if not account_ids:
        return {
            'items': [],
            'summary': {
                'opening_balance': 0.0,
                'opening_balance_type': 'balanced',  # balanced, debit, credit
                'total_debit': 0.0,
                'total_credit': 0.0,
                'closing_balance': 0.0,
                'closing_balance_type': 'balanced',
            },
            'pagination': {
                'total': 0,
                'page': 1,
                'per_page': take,
                'total_pages': 1,
                'has_next': False,
                'has_prev': False,
            }
        }
    
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
    if date_from_obj is None or date_to_obj is None:
        try:
            if fiscal_year_id:
                fiscal_year = db.query(FiscalYear).filter(FiscalYear.id == fiscal_year_id).first()
            else:
                fiscal_year = db.query(FiscalYear).filter(
                    and_(
                        FiscalYear.business_id == business_id,
                        FiscalYear.is_last == True
                    )
                ).first()
            
            if fiscal_year:
                if date_from_obj is None:
                    date_from_obj = fiscal_year.start_date
                if date_to_obj is None:
                    date_to_obj = fiscal_year.end_date if fiscal_year.end_date else date.today()
        except Exception:
            pass
    
    # اگر هنوز تاریخ مشخص نشده، از یک بازه زمانی معقول استفاده کن
    if date_to_obj is None:
        date_to_obj = date.today()
    if date_from_obj is None:
        try:
            current_year = date.today().year
            date_from_obj = date(current_year, 1, 1)
        except Exception:
            date_from_obj = date.today()
    
    # دریافت سال مالی
    if not fiscal_year_id:
        fiscal_year = db.query(FiscalYear).filter(
            and_(
                FiscalYear.business_id == business_id,
                FiscalYear.is_last == True
            )
        ).first()
        if fiscal_year:
            fiscal_year_id = fiscal_year.id
    
    # دریافت اطلاعات حساب‌ها
    accounts = db.query(Account).filter(
        and_(
            Account.id.in_(account_ids),
            (Account.business_id == None) | (Account.business_id == business_id)  # noqa: E711
        )
    ).all()
    
    if not accounts:
        return {
            'items': [],
            'summary': {
                'opening_balance': 0.0,
                'opening_balance_type': 'balanced',
                'total_debit': 0.0,
                'total_credit': 0.0,
                'closing_balance': 0.0,
                'closing_balance_type': 'balanced',
            },
            'pagination': {
                'total': 0,
                'page': 1,
                'per_page': take,
                'total_pages': 1,
                'has_next': False,
                'has_prev': False,
            }
        }
    
    # دریافت سند تراز افتتاحیه (اگر وجود دارد)
    opening_balance_data = {}
    if fiscal_year_id:
        try:
            ob_doc = _find_existing_ob_document(db, business_id, fiscal_year_id)
            if ob_doc:
                repo = DocumentRepository(db)
                ob_dict = repo.to_dict_with_lines(ob_doc)
                lines = ob_dict.get('lines', [])
                for line in lines:
                    acc_id = line.get('account_id')
                    if acc_id and acc_id in account_ids:
                        if acc_id not in opening_balance_data:
                            opening_balance_data[acc_id] = {'debit': Decimal(0), 'credit': Decimal(0)}
                        opening_balance_data[acc_id]['debit'] += Decimal(str(line.get('debit', 0) or 0))
                        opening_balance_data[acc_id]['credit'] += Decimal(str(line.get('credit', 0) or 0))
        except Exception:
            pass
    
    # محاسبه مانده ابتدای دوره برای حساب‌ها
    opening_debit_total = Decimal(0)
    opening_credit_total = Decimal(0)
    
    # دریافت مانده‌ها از تراز افتتاحیه
    for acc_id in account_ids:
        if acc_id in opening_balance_data:
            opening_debit_total += opening_balance_data[acc_id]['debit']
            opening_credit_total += opening_balance_data[acc_id]['credit']
    
    # محاسبه مانده از DocumentLine ها تا قبل از date_from
    if date_from_obj:
        date_before_from = date_from_obj - timedelta(days=1)
        
        opening_query = db.query(
            func.coalesce(func.sum(DocumentLine.debit), 0).label('total_debit'),
            func.coalesce(func.sum(DocumentLine.credit), 0).label('total_credit')
        ).join(
            Document, DocumentLine.document_id == Document.id
        ).filter(
            and_(
                Document.business_id == business_id,
                Document.is_proforma == False,
                DocumentLine.account_id.isnot(None),
                DocumentLine.account_id.in_(account_ids),
                Document.document_date <= date_before_from
            )
        )
        
        if fiscal_year_id:
            opening_query = opening_query.filter(Document.fiscal_year_id == fiscal_year_id)
        
        if currency_id:
            opening_query = opening_query.filter(Document.currency_id == currency_id)
        
        opening_result = opening_query.first()
        if opening_result:
            opening_debit_total += Decimal(str(opening_result.total_debit or 0))
            opening_credit_total += Decimal(str(opening_result.total_credit or 0))
    
    # محاسبه مانده ابتدای دوره
    opening_balance = opening_debit_total - opening_credit_total
    opening_balance_type = 'balanced'
    if opening_balance > 0:
        opening_balance_type = 'debit'
    elif opening_balance < 0:
        opening_balance_type = 'credit'
    
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
            DocumentLine.account_id.in_(account_ids),
            Document.document_date >= date_from_obj,
            Document.document_date <= date_to_obj,
        )
    )
    
    if not include_proforma:
        lines_query = lines_query.filter(Document.is_proforma == False)
    
    if fiscal_year_id:
        lines_query = lines_query.filter(Document.fiscal_year_id == fiscal_year_id)
    
    if currency_id:
        lines_query = lines_query.filter(Document.currency_id == currency_id)
    
    if person_id:
        lines_query = lines_query.filter(DocumentLine.person_id == person_id)
    
    # مرتب‌سازی بر اساس تاریخ سند و سپس شناسه سند
    lines_query = lines_query.order_by(
        Document.document_date.asc(),
        Document.id.asc(),
        DocumentLine.id.asc()
    )
    
    all_lines = lines_query.all()
    
    # استخراج شناسه‌های شخص، حساب بانکی، صندوق، تنخواه، محصول
    person_ids = list(set(
        line.person_id for line, doc in all_lines
        if line.person_id is not None
    ))
    bank_account_ids = list(set(
        line.bank_account_id for line, doc in all_lines
        if line.bank_account_id is not None
    ))
    cash_register_ids = list(set(
        line.cash_register_id for line, doc in all_lines
        if line.cash_register_id is not None
    ))
    petty_cash_ids = list(set(
        line.petty_cash_id for line, doc in all_lines
        if line.petty_cash_id is not None
    ))
    product_ids = list(set(
        line.product_id for line, doc in all_lines
        if line.product_id is not None
    ))
    
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
    
    # دریافت اطلاعات حساب‌های بانکی
    bank_accounts_map = {}
    if bank_account_ids:
        bank_accounts = db.query(BankAccount).filter(BankAccount.id.in_(bank_account_ids)).all()
        for ba in bank_accounts:
            bank_accounts_map[ba.id] = {
                'id': ba.id,
                'code': ba.code,
                'name': ba.name or '',
            }
    
    # دریافت اطلاعات صندوق‌ها
    cash_registers_map = {}
    if cash_register_ids:
        cash_registers = db.query(CashRegister).filter(CashRegister.id.in_(cash_register_ids)).all()
        for cr in cash_registers:
            cash_registers_map[cr.id] = {
                'id': cr.id,
                'code': cr.code,
                'name': cr.name or '',
            }
    
    # دریافت اطلاعات تنخواه‌ها
    petty_cash_map = {}
    if petty_cash_ids:
        petty_cash_list = db.query(PettyCash).filter(PettyCash.id.in_(petty_cash_ids)).all()
        for pc in petty_cash_list:
            petty_cash_map[pc.id] = {
                'id': pc.id,
                'code': pc.code,
                'name': pc.name or '',
            }
    
    # دریافت اطلاعات محصولات
    products_map = {}
    if product_ids:
        products = db.query(Product).filter(Product.id.in_(product_ids)).all()
        for product in products:
            products_map[product.id] = {
                'id': product.id,
                'code': product.code,
                'name': product.name or '',
            }
    
    # ساخت آیتم‌ها با محاسبه مانده تجمعی
    items = []
    running_balance = opening_balance
    total_debit = Decimal(0)
    total_credit = Decimal(0)
    
    accounts_map = {acc.id: acc for acc in accounts}
    
    for line, doc in all_lines:
        debit = Decimal(str(line.debit or 0))
        credit = Decimal(str(line.credit or 0))
        
        # به‌روزرسانی مانده تجمعی: بدهکار اضافه می‌کند، بستانکار کم می‌کند
        running_balance = running_balance + debit - credit
        total_debit += debit
        total_credit += credit
        
        # تعیین نوع مانده
        balance_type = 'balanced'
        if running_balance > 0:
            balance_type = 'debit'
        elif running_balance < 0:
            balance_type = 'credit'
        
        # اطلاعات حساب
        account = accounts_map.get(line.account_id)
        
        # اطلاعات طرف مقابل
        counterpart_name = ''
        counterpart_code = ''
        if line.person_id and line.person_id in persons_map:
            person = persons_map[line.person_id]
            counterpart_name = person['name']
            counterpart_code = str(person['code'] or '')
        elif line.bank_account_id and line.bank_account_id in bank_accounts_map:
            ba = bank_accounts_map[line.bank_account_id]
            counterpart_name = ba['name']
            counterpart_code = ba['code'] or ''
        elif line.cash_register_id and line.cash_register_id in cash_registers_map:
            cr = cash_registers_map[line.cash_register_id]
            counterpart_name = cr['name']
            counterpart_code = cr['code'] or ''
        elif line.petty_cash_id and line.petty_cash_id in petty_cash_map:
            pc = petty_cash_map[line.petty_cash_id]
            counterpart_name = pc['name']
            counterpart_code = pc['code'] or ''
        elif line.product_id and line.product_id in products_map:
            product = products_map[line.product_id]
            counterpart_name = product['name']
            counterpart_code = product['code'] or ''
        
        document_type_name = _get_document_type_name(doc.document_type)
        
        items.append({
            'document_id': doc.id,
            'document_code': doc.code or '',
            'document_date': doc.document_date.isoformat() if doc.document_date else None,
            'document_type': doc.document_type or '',
            'document_type_name': document_type_name,
            'account_id': line.account_id,
            'account_code': account.code if account else '',
            'account_name': account.name if account else '',
            'person_id': line.person_id,
            'person_name': counterpart_name if line.person_id else '',
            'person_code': counterpart_code if line.person_id else '',
            'counterpart_name': counterpart_name,
            'counterpart_code': counterpart_code,
            'debit': float(debit),
            'credit': float(credit),
            'balance': float(running_balance),
            'balance_type': balance_type,
            'description': line.description or doc.description or '',
        })
    
    # Pagination
    total = len(items)
    current_page = (skip // take) + 1
    total_pages = (total + take - 1) // take if take > 0 else 1
    paginated_items = items[skip:skip + take]
    
    # محاسبه مانده انتهای دوره
    closing_balance = opening_balance + total_debit - total_credit
    closing_balance_type = 'balanced'
    if closing_balance > 0:
        closing_balance_type = 'debit'
    elif closing_balance < 0:
        closing_balance_type = 'credit'
    
    return {
        'items': paginated_items,
        'summary': {
            'opening_balance': float(opening_balance),
            'opening_balance_type': opening_balance_type,
            'total_debit': float(total_debit),
            'total_credit': float(total_credit),
            'closing_balance': float(closing_balance),
            'closing_balance_type': closing_balance_type,
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

