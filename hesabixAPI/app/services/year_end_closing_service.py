"""
سرویس بستن سال مالی (Year End Closing)

این سرویس برای بستن سال مالی و انتقال مانده‌ها به سال جدید استفاده می‌شود.
"""

from __future__ import annotations

from typing import Any, Dict, List, Optional, Tuple
from datetime import date, timedelta
from decimal import Decimal

from sqlalchemy.orm import Session
from sqlalchemy import and_, func, or_

from adapters.db.repositories.document_repository import DocumentRepository
from adapters.db.repositories.fiscal_year_repo import FiscalYearRepository
from adapters.db.models.document import Document
from adapters.db.models.document_line import DocumentLine
from adapters.db.models.account import Account
from adapters.db.models.fiscal_year import FiscalYear
from adapters.db.models.person import Person
from adapters.db.models.product import Product
from adapters.db.models.warehouse import Warehouse
from app.core.responses import ApiError
from app.services.opening_balance_service import upsert_opening_balance
from app.services.invoice_service import _compute_available_stock


def _get_fixed_account_by_code(db: Session, account_code: str) -> Account:
    """دریافت حساب عمومی بر اساس کد"""
    account = db.query(Account).filter(
        and_(
            Account.business_id == None,  # noqa: E711
            Account.code == str(account_code),
        )
    ).first()
    if not account:
        raise ApiError("ACCOUNT_NOT_FOUND", f"حساب با کد {account_code} یافت نشد", http_status=500)
    return account


def _is_revenue_account(code: str) -> bool:
    """تشخیص اینکه آیا یک حساب، حساب درآمد است یا نه (گروه 5 و 6)"""
    if not code:
        return False
    code_clean = str(code).strip()
    return code_clean.startswith('5') or code_clean.startswith('6')


def _is_expense_account(code: str) -> bool:
    """تشخیص اینکه آیا یک حساب، حساب هزینه است یا نه (گروه 4 و 7)"""
    if not code:
        return False
    code_clean = str(code).strip()
    return code_clean.startswith('4') or code_clean.startswith('7')


def _is_permanent_account(code: str) -> bool:
    """تشخیص اینکه آیا یک حساب، حساب دائمی است یا نه (گروه 1، 2، 3)"""
    if not code:
        return False
    code_clean = str(code).strip()
    return code_clean.startswith('1') or code_clean.startswith('2') or code_clean.startswith('3')


def _calculate_account_balance(
    db: Session,
    business_id: int,
    account_id: int,
    fiscal_year_id: int,
    date_to: date,
) -> Dict[str, Decimal]:
    """
    محاسبه مانده یک حساب از ابتدای سال مالی تا تاریخ مشخص
    
    Returns:
        {
            'opening_debit': Decimal,
            'opening_credit': Decimal,
            'period_debit': Decimal,
            'period_credit': Decimal,
            'closing_balance': Decimal  # برای درآمد: credit - debit، برای هزینه: debit - credit
        }
    """
    fiscal_year = db.query(FiscalYear).filter(FiscalYear.id == fiscal_year_id).first()
    if not fiscal_year:
        raise ApiError("FISCAL_YEAR_NOT_FOUND", "سال مالی یافت نشد", http_status=404)
    
    date_from = fiscal_year.start_date
    
    # محاسبه مانده ابتدای دوره (از تراز افتتاحیه)
    opening_query = db.query(
        func.sum(DocumentLine.debit).label('total_debit'),
        func.sum(DocumentLine.credit).label('total_credit')
    ).join(
        Document, DocumentLine.document_id == Document.id
    ).filter(
        and_(
            Document.business_id == business_id,
            Document.fiscal_year_id == fiscal_year_id,
            Document.document_type == "opening_balance",
            DocumentLine.account_id == account_id,
            Document.is_proforma == False,
        )
    )
    
    opening_result = opening_query.first()
    opening_debit = Decimal(str(opening_result.total_debit or 0))
    opening_credit = Decimal(str(opening_result.total_credit or 0))
    
    # محاسبه گردش دوره
    period_query = db.query(
        func.sum(DocumentLine.debit).label('total_debit'),
        func.sum(DocumentLine.credit).label('total_credit')
    ).join(
        Document, DocumentLine.document_id == Document.id
    ).filter(
        and_(
            Document.business_id == business_id,
            Document.fiscal_year_id == fiscal_year_id,
            DocumentLine.account_id == account_id,
            Document.document_date >= date_from,
            Document.document_date <= date_to,
            Document.is_proforma == False,
            Document.document_type != "opening_balance",  # تراز افتتاحیه جدا محاسبه شد
        )
    )
    
    period_result = period_query.first()
    period_debit = Decimal(str(period_result.total_debit or 0))
    period_credit = Decimal(str(period_result.total_credit or 0))
    
    # محاسبه مانده نهایی
    account = db.query(Account).filter(Account.id == account_id).first()
    if not account:
        closing_balance = Decimal(0)
    elif _is_revenue_account(account.code):
        # برای حساب‌های درآمد: مانده = Credit - Debit
        closing_balance = (opening_credit + period_credit) - (opening_debit + period_debit)
    elif _is_expense_account(account.code):
        # برای حساب‌های هزینه: مانده = Debit - Credit
        closing_balance = (opening_debit + period_debit) - (opening_credit + period_credit)
    else:
        closing_balance = Decimal(0)
    
    return {
        'opening_debit': opening_debit,
        'opening_credit': opening_credit,
        'period_debit': period_debit,
        'period_credit': period_credit,
        'closing_balance': closing_balance,
    }


def preview_year_end_closing(
    db: Session,
    business_id: int,
    fiscal_year_id: int,
) -> Dict[str, Any]:
    """
    پیش‌نمایش بستن سال مالی
    
    این تابع مانده حساب‌های موقت را محاسبه می‌کند و اطلاعات لازم برای بستن را برمی‌گرداند.
    """
    fy_repo = FiscalYearRepository(db)
    fiscal_year = fy_repo.get_by_id(fiscal_year_id)
    
    if not fiscal_year:
        raise ApiError("FISCAL_YEAR_NOT_FOUND", "سال مالی یافت نشد", http_status=404)
    
    if int(fiscal_year.business_id) != int(business_id):
        raise ApiError("FISCAL_YEAR_NOT_FOUND", "سال مالی متعلق به این کسب‌وکار نیست", http_status=404)
    
    if not fiscal_year.is_last:
        raise ApiError("FISCAL_YEAR_NOT_CURRENT", "این سال مالی سال جاری نیست", http_status=400)
    
    # بررسی اینکه آیا قبلاً بسته شده یا نه
    existing_closing = db.query(Document).filter(
        and_(
            Document.business_id == business_id,
            Document.fiscal_year_id == fiscal_year_id,
            Document.document_type == "year_end_closing",
        )
    ).first()
    
    if existing_closing:
        raise ApiError("FISCAL_YEAR_ALREADY_CLOSED", "این سال مالی قبلاً بسته شده است", http_status=400)
    
    # دریافت تمام حساب‌های کسب‌وکار
    all_accounts = db.query(Account).filter(
        (Account.business_id == None) | (Account.business_id == business_id)  # noqa: E711
    ).order_by(Account.code.asc()).all()
    
    # جدا کردن حساب‌های درآمد و هزینه
    revenue_accounts = [acc for acc in all_accounts if _is_revenue_account(acc.code)]
    expense_accounts = [acc for acc in all_accounts if _is_expense_account(acc.code)]
    
    # محاسبه مانده حساب‌های درآمد
    revenue_items = []
    total_revenue = Decimal(0)
    
    for account in revenue_accounts:
        balance_info = _calculate_account_balance(
            db, business_id, account.id, fiscal_year_id, fiscal_year.end_date
        )
        closing_balance = balance_info['closing_balance']
        
        if closing_balance > 0:  # فقط حساب‌هایی که مانده مثبت دارند
            revenue_items.append({
                'account_id': account.id,
                'account_code': account.code,
                'account_name': account.name,
                'opening_debit': float(balance_info['opening_debit']),
                'opening_credit': float(balance_info['opening_credit']),
                'period_debit': float(balance_info['period_debit']),
                'period_credit': float(balance_info['period_credit']),
                'closing_balance': float(closing_balance),
            })
            total_revenue += closing_balance
    
    # محاسبه مانده حساب‌های هزینه
    expense_items = []
    total_expense = Decimal(0)
    
    for account in expense_accounts:
        balance_info = _calculate_account_balance(
            db, business_id, account.id, fiscal_year_id, fiscal_year.end_date
        )
        closing_balance = balance_info['closing_balance']
        
        if closing_balance > 0:  # فقط حساب‌هایی که مانده مثبت دارند
            expense_items.append({
                'account_id': account.id,
                'account_code': account.code,
                'account_name': account.name,
                'opening_debit': float(balance_info['opening_debit']),
                'opening_credit': float(balance_info['opening_credit']),
                'period_debit': float(balance_info['period_debit']),
                'period_credit': float(balance_info['period_credit']),
                'closing_balance': float(closing_balance),
            })
            total_expense += closing_balance
    
    # محاسبه سود/زیان خالص
    net_profit_loss = total_revenue - total_expense
    
    # محاسبه مانده حساب سود یا زیان انباشته
    retained_earnings_account = _get_fixed_account_by_code(db, "30106")
    retained_earnings_balance = _calculate_account_balance(
        db, business_id, retained_earnings_account.id, fiscal_year_id, fiscal_year.end_date
    )
    
    # مانده ابتدای سال = مانده از تراز افتتاحیه + گردش دوره تا قبل از بستن
    retained_earnings_opening = (
        retained_earnings_balance['opening_debit'] - retained_earnings_balance['opening_credit']
    ) + (
        retained_earnings_balance['period_debit'] - retained_earnings_balance['period_credit']
    )
    
    # مانده انتهای سال = مانده ابتدای سال + سود/زیان سال جاری
    retained_earnings_closing = retained_earnings_opening + net_profit_loss
    
    return {
        'fiscal_year': {
            'id': fiscal_year.id,
            'title': fiscal_year.title,
            'start_date': fiscal_year.start_date,  # date object برای format_datetime_fields
            'end_date': fiscal_year.end_date,  # date object برای format_datetime_fields
        },
        'revenue_accounts': revenue_items,
        'expense_accounts': expense_items,
        'summary': {
            'total_revenue': float(total_revenue),
            'total_expense': float(total_expense),
            'net_profit_loss': float(net_profit_loss),
        },
        'retained_earnings': {
            'account_id': retained_earnings_account.id,
            'account_code': retained_earnings_account.code,
            'account_name': retained_earnings_account.name,
            'opening_balance': float(retained_earnings_opening),
            'current_year_profit_loss': float(net_profit_loss),
            'closing_balance': float(retained_earnings_closing),
        },
    }


def close_fiscal_year(
    db: Session,
    business_id: int,
    fiscal_year_id: int,
    user_id: int,
    new_fiscal_year_title: str,
    auto_create_opening_balance: bool = True,
) -> Dict[str, Any]:
    """
    بستن سال مالی
    
    این تابع:
    1. حساب‌های درآمد و هزینه را می‌بندد
    2. سود/زیان را به حساب سود یا زیان انباشته منتقل می‌کند
    3. سال مالی جدید ایجاد می‌کند
    4. تراز افتتاحیه سال جدید را ایجاد می‌کند (در صورت نیاز)
    """
    # اعتبارسنجی اولیه
    preview_data = preview_year_end_closing(db, business_id, fiscal_year_id)
    
    fy_repo = FiscalYearRepository(db)
    fiscal_year = fy_repo.get_by_id(fiscal_year_id)
    
    if not fiscal_year:
        raise ApiError("FISCAL_YEAR_NOT_FOUND", "سال مالی یافت نشد", http_status=404)
    
    # دریافت حساب‌های لازم
    summary_account = _get_fixed_account_by_code(db, "80301")  # خلاصه سود و زیان
    retained_earnings_account = _get_fixed_account_by_code(db, "30106")  # سود یا زیان انباشته
    
    # دریافت ارز پیش‌فرض (از اولین سند سال مالی)
    first_doc = db.query(Document).filter(
        and_(
            Document.business_id == business_id,
            Document.fiscal_year_id == fiscal_year_id,
        )
    ).order_by(Document.id.asc()).first()
    
    if not first_doc:
        raise ApiError("NO_DOCUMENTS_FOUND", "هیچ سندی در این سال مالی یافت نشد", http_status=400)
    
    currency_id = first_doc.currency_id
    
    # ساخت خطوط سند بستن سال مالی
    doc_repo = DocumentRepository(db)
    lines: List[Dict[str, Any]] = []
    
    total_revenue = Decimal(0)
    total_expense = Decimal(0)
    
    # بستن حساب‌های درآمد
    for revenue_item in preview_data['revenue_accounts']:
        balance = Decimal(str(revenue_item['closing_balance']))
        if balance > 0:
            lines.append({
                'account_id': revenue_item['account_id'],
                'debit': float(balance),
                'credit': 0.0,
                'description': f"بستن حساب {revenue_item['account_name']}",
            })
            total_revenue += balance
    
    # خط بستانکار خلاصه سود و زیان (جمع درآمدها)
    if total_revenue > 0:
        lines.append({
            'account_id': summary_account.id,
            'debit': 0.0,
            'credit': float(total_revenue),
            'description': 'جمع درآمدهای سال',
        })
    
    # بستن حساب‌های هزینه
    for expense_item in preview_data['expense_accounts']:
        balance = Decimal(str(expense_item['closing_balance']))
        if balance > 0:
            lines.append({
                'account_id': expense_item['account_id'],
                'debit': 0.0,
                'credit': float(balance),
                'description': f"بستن حساب {expense_item['account_name']}",
            })
            total_expense += balance
    
    # خط بدهکار خلاصه سود و زیان (جمع هزینه‌ها)
    if total_expense > 0:
        lines.append({
            'account_id': summary_account.id,
            'debit': float(total_expense),
            'credit': 0.0,
            'description': 'جمع هزینه‌های سال',
        })
    
    # بستن خلاصه سود و زیان و انتقال به سود یا زیان انباشته
    net_profit_loss = total_revenue - total_expense
    
    if net_profit_loss > 0:  # سود
        lines.append({
            'account_id': summary_account.id,
            'debit': float(net_profit_loss),
            'credit': 0.0,
            'description': 'بستن خلاصه سود و زیان (سود)',
        })
        lines.append({
            'account_id': retained_earnings_account.id,
            'debit': 0.0,
            'credit': float(net_profit_loss),
            'description': 'انتقال سود به سود یا زیان انباشته',
        })
    elif net_profit_loss < 0:  # زیان
        lines.append({
            'account_id': summary_account.id,
            'debit': 0.0,
            'credit': float(abs(net_profit_loss)),
            'description': 'بستن خلاصه سود و زیان (زیان)',
        })
        lines.append({
            'account_id': retained_earnings_account.id,
            'debit': float(abs(net_profit_loss)),
            'credit': 0.0,
            'description': 'انتقال زیان به سود یا زیان انباشته',
        })
    
    # ایجاد سند بستن سال مالی
    closing_document_code = doc_repo.generate_document_code(business_id, "year_end_closing")
    
    closing_document_payload = {
        'code': closing_document_code,
        'business_id': business_id,
        'fiscal_year_id': fiscal_year_id,
        'currency_id': currency_id,
        'created_by_user_id': user_id,
        'document_date': fiscal_year.end_date,
        'document_type': 'year_end_closing',
        'is_proforma': False,
        'description': f'بستن سال مالی {fiscal_year.title}',
        'lines': lines,
    }
    
    closing_document = doc_repo.create_document(closing_document_payload)
    
    # ایجاد سال مالی جدید
    new_start_date = fiscal_year.end_date + timedelta(days=1)
    # محاسبه end_date: یک سال بعد از start_date
    try:
        # اگر سال بعد 29 فوریه داشته باشد، باید مدیریت شود
        if new_start_date.month == 2 and new_start_date.day == 29:
            new_end_date = date(new_start_date.year + 1, 2, 28)
        else:
            new_end_date = date(new_start_date.year + 1, new_start_date.month, new_start_date.day)
    except ValueError:
        # اگر روز معتبر نبود (مثلاً 29 فوریه در سال غیر کبیسه)
        new_end_date = date(new_start_date.year + 1, new_start_date.month, new_start_date.day - 1)
    
    # تغییر is_last سال قبلی به False
    fiscal_year.is_last = False
    db.commit()
    db.refresh(fiscal_year)
    
    # ایجاد سال مالی جدید
    new_fiscal_year = fy_repo.create_fiscal_year(
        business_id=business_id,
        title=new_fiscal_year_title,
        start_date=new_start_date,
        end_date=new_end_date,
        is_last=True,
    )
    
    result = {
        'closing_document': doc_repo.get_document_details(closing_document.id) or {},
        'new_fiscal_year': {
            'id': new_fiscal_year.id,
            'title': new_fiscal_year.title,
            'start_date': new_fiscal_year.start_date.isoformat(),
            'end_date': new_fiscal_year.end_date.isoformat(),
        },
    }
    
    # ایجاد تراز افتتاحیه سال جدید (در صورت نیاز)
    if auto_create_opening_balance:
        try:
            opening_balance_doc = _create_opening_balance_for_new_fiscal_year(
                db=db,
                business_id=business_id,
                old_fiscal_year_id=fiscal_year_id,
                new_fiscal_year_id=new_fiscal_year.id,
                user_id=user_id,
                currency_id=currency_id,
            )
            result['opening_balance_created'] = True
            result['opening_balance_document'] = doc_repo.get_document_details(opening_balance_doc.id) or {}
            result['opening_balance_note'] = f'تراز افتتاحیه سال جدید با کد {opening_balance_doc.code} ایجاد شد'
        except Exception as e:
            result['opening_balance_created'] = False
            result['opening_balance_note'] = f'خطا در ایجاد تراز افتتاحیه: {str(e)}'
    
    return result


def _create_opening_balance_for_new_fiscal_year(
    db: Session,
    business_id: int,
    old_fiscal_year_id: int,
    new_fiscal_year_id: int,
    user_id: int,
    currency_id: int,
) -> Document:
    """
    ایجاد سند تراز افتتاحیه برای سال مالی جدید
    
    این تابع:
    1. مانده تمام حساب‌های دائمی (گروه 1، 2، 3) را از سال قبل می‌گیرد
    2. مانده اشخاص (بدهکاران و بستانکاران) را می‌گیرد
    3. مانده حساب‌های بانکی و صندوق را می‌گیرد
    4. موجودی کالا را می‌گیرد
    5. همه این‌ها را در سند افتتاحیه سال جدید ثبت می‌کند
    """
    old_fiscal_year = db.query(FiscalYear).filter(FiscalYear.id == old_fiscal_year_id).first()
    new_fiscal_year = db.query(FiscalYear).filter(FiscalYear.id == new_fiscal_year_id).first()
    
    if not old_fiscal_year or not new_fiscal_year:
        raise ApiError("FISCAL_YEAR_NOT_FOUND", "سال مالی یافت نشد", http_status=404)
    
    # تاریخ پایان سال مالی قبلی
    date_to = old_fiscal_year.end_date
    
    # دریافت تمام حساب‌های دائمی (گروه 1، 2، 3)
    permanent_accounts = db.query(Account).filter(
        and_(
            or_(
                Account.business_id == None,  # noqa: E711
                Account.business_id == business_id,
            ),
            or_(
                Account.code.like('1%'),
                Account.code.like('2%'),
                Account.code.like('3%'),
            ),
        )
    ).all()
    
    account_lines: List[Dict[str, Any]] = []
    inventory_lines: List[Dict[str, Any]] = []
    
    # محاسبه مانده حساب‌های دائمی
    for account in permanent_accounts:
        if not _is_permanent_account(account.code):
            continue
            
        # محاسبه مانده حساب تا پایان سال مالی قبلی (از تمام اسناد)
        account_balance_query = db.query(
            func.coalesce(func.sum(DocumentLine.debit), 0).label('total_debit'),
            func.coalesce(func.sum(DocumentLine.credit), 0).label('total_credit')
        ).join(
            Document, DocumentLine.document_id == Document.id
        ).filter(
            and_(
                Document.business_id == business_id,
                Document.fiscal_year_id == old_fiscal_year_id,
                DocumentLine.account_id == account.id,
                Document.document_date <= date_to,
                Document.is_proforma == False,
            )
        )
        
        account_result = account_balance_query.first()
        total_debit = Decimal(str(account_result.total_debit or 0))
        total_credit = Decimal(str(account_result.total_credit or 0))
        closing_balance = total_debit - total_credit
        
        # اگر مانده صفر است، از لیست خارج کن
        if closing_balance == 0:
            continue
        
        # اضافه کردن به خطوط سند
        if closing_balance > 0:
            account_lines.append({
                'account_id': account.id,
                'debit': float(closing_balance),
                'credit': 0.0,
                'description': f'مانده ابتدای دوره - {account.name}',
            })
        else:
            account_lines.append({
                'account_id': account.id,
                'debit': 0.0,
                'credit': float(-closing_balance),
                'description': f'مانده ابتدای دوره - {account.name}',
            })
    
    # محاسبه مانده اشخاص (بدهکاران و بستانکاران)
    persons = db.query(Person).filter(Person.business_id == business_id).all()
    
    for person in persons:
        # محاسبه مانده شخص تا پایان سال مالی قبلی
        person_balance_query = db.query(
            func.coalesce(func.sum(DocumentLine.debit), 0).label('total_debit'),
            func.coalesce(func.sum(DocumentLine.credit), 0).label('total_credit')
        ).join(
            Document, DocumentLine.document_id == Document.id
        ).filter(
            and_(
                Document.business_id == business_id,
                Document.fiscal_year_id == old_fiscal_year_id,
                DocumentLine.person_id == person.id,
                Document.document_date <= date_to,
                Document.is_proforma == False,
            )
        )
        
        person_result = person_balance_query.first()
        person_debit = Decimal(str(person_result.total_debit or 0))
        person_credit = Decimal(str(person_result.total_credit or 0))
        person_balance = person_debit - person_credit
        
        # اگر مانده صفر است، از لیست خارج کن
        if person_balance == 0:
            continue
        
        # پیدا کردن حساب مربوط به شخص
        person_account_id = person.account_id
        
        if not person_account_id:
            # اگر حساب مشخص نشده، از حساب پیش‌فرض استفاده کن
            if person_balance > 0:
                # بدهکار = حساب دریافتنی
                person_account = _get_fixed_account_by_code(db, "13101")
            else:
                # بستانکار = حساب پرداختنی
                person_account = _get_fixed_account_by_code(db, "21101")
            person_account_id = person_account.id
        
        # اضافه کردن به خطوط سند
        if person_balance > 0:
            account_lines.append({
                'account_id': person_account_id,
                'person_id': person.id,
                'debit': float(person_balance),
                'credit': 0.0,
                'description': f'مانده ابتدای دوره - {person.name}',
            })
        else:
            account_lines.append({
                'account_id': person_account_id,
                'person_id': person.id,
                'debit': 0.0,
                'credit': float(-person_balance),
                'description': f'مانده ابتدای دوره - {person.name}',
            })
    
    # محاسبه مانده حساب‌های بانکی و صندوق
    bank_cash_query = db.query(
        DocumentLine.bank_account_id,
        DocumentLine.cash_register_id,
        DocumentLine.petty_cash_id,
        DocumentLine.account_id,
        func.coalesce(func.sum(DocumentLine.debit), 0).label('total_debit'),
        func.coalesce(func.sum(DocumentLine.credit), 0).label('total_credit')
    ).join(
        Document, DocumentLine.document_id == Document.id
    ).filter(
        and_(
            Document.business_id == business_id,
            Document.fiscal_year_id == old_fiscal_year_id,
            Document.document_date <= date_to,
            Document.is_proforma == False,
            or_(
                DocumentLine.bank_account_id.isnot(None),
                DocumentLine.cash_register_id.isnot(None),
                DocumentLine.petty_cash_id.isnot(None),
            ),
        )
    ).group_by(
        DocumentLine.bank_account_id,
        DocumentLine.cash_register_id,
        DocumentLine.petty_cash_id,
        DocumentLine.account_id,
    )
    
    bank_cash_results = bank_cash_query.all()
    
    for result in bank_cash_results:
        total_debit = Decimal(str(result.total_debit or 0))
        total_credit = Decimal(str(result.total_credit or 0))
        balance = total_debit - total_credit
        
        # اگر مانده صفر است، از لیست خارج کن
        if balance == 0:
            continue
        
        line_data = {
            'account_id': result.account_id,
            'debit': float(balance) if balance > 0 else 0.0,
            'credit': float(-balance) if balance < 0 else 0.0,
            'description': 'مانده ابتدای دوره',
        }
        
        if result.bank_account_id:
            line_data['bank_account_id'] = result.bank_account_id
            line_data['description'] = f'مانده ابتدای دوره - حساب بانکی'
        elif result.cash_register_id:
            line_data['cash_register_id'] = result.cash_register_id
            line_data['description'] = f'مانده ابتدای دوره - صندوق'
        elif result.petty_cash_id:
            line_data['petty_cash_id'] = result.petty_cash_id
            line_data['description'] = f'مانده ابتدای دوره - تنخواه'
        
        account_lines.append(line_data)
    
    # محاسبه موجودی کالا
    products = db.query(Product).filter(
        and_(
            Product.business_id == business_id,
            Product.track_inventory == True,
        )
    ).all()
    
    warehouses = db.query(Warehouse).filter(Warehouse.business_id == business_id).all()
    
    inventory_account = _get_fixed_account_by_code(db, "12101")  # موجودی کالا
    
    for product in products:
        for warehouse in warehouses:
            # محاسبه موجودی کالا در انبار تا پایان سال مالی قبلی
            stock = _compute_available_stock(
                db=db,
                business_id=business_id,
                product_id=product.id,
                warehouse_id=warehouse.id,
                up_to_date=date_to,
            )
            
            if stock <= 0:
                continue
            
            # محاسبه ارزش موجودی (از آخرین قیمت تمام شده)
            cost_price = Decimal(str(product.purchase_price or 0))
            if cost_price <= 0:
                extra_info = product.extra_info or {}
                cost_price = Decimal(str(extra_info.get('cost_price', 0) or 0))
            
            if cost_price <= 0:
                cost_price = Decimal(0)
            
            inventory_value = stock * cost_price
            
            # اضافه کردن به خطوط موجودی
            inventory_lines.append({
                'product_id': product.id,
                'quantity': float(stock),
                'description': f'موجودی ابتدای دوره - {product.name}',
                'extra_info': {
                    'movement': 'in',
                    'warehouse_id': warehouse.id,
                    'cost_price': float(cost_price),
                },
            })
            
            # اضافه کردن به خطوط حساب (بدهکار حساب موجودی کالا)
            account_lines.append({
                'account_id': inventory_account.id,
                'debit': float(inventory_value),
                'credit': 0.0,
                'description': f'موجودی ابتدای دوره - {product.name}',
            })
    
    # ایجاد سند تراز افتتاحیه
    opening_balance_data = {
        'fiscal_year_id': new_fiscal_year_id,
        'currency_id': currency_id,
        'document_date': new_fiscal_year.start_date,
        'description': f'تراز افتتاحیه سال مالی {new_fiscal_year.title}',
        'account_lines': account_lines,
        'inventory_lines': inventory_lines,
        'inventory_account_id': inventory_account.id if inventory_lines else None,
        'auto_balance_to_equity': True,
        'equity_account_id': _get_fixed_account_by_code(db, "30106").id,  # سود یا زیان انباشته
    }
    
    created_doc_dict = upsert_opening_balance(
        db=db,
        business_id=business_id,
        user_id=user_id,
        data=opening_balance_data,
    )
    
    # دریافت سند ایجاد شده
    doc_repo = DocumentRepository(db)
    created_doc = db.query(Document).filter(Document.id == created_doc_dict.get('id')).first()
    
    if not created_doc:
        raise ApiError("OPENING_BALANCE_CREATION_FAILED", "ایجاد سند تراز افتتاحیه ناموفق بود", http_status=500)
    
    return created_doc

