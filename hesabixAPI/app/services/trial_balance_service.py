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
from app.services.opening_balance_service import _find_existing_ob_document
from adapters.db.repositories.document_repository import DocumentRepository


def _parse_iso_date(dt: str | date) -> date:
    if isinstance(dt, date):
        return dt
    if isinstance(dt, str):
        return date.fromisoformat(dt.split('T')[0])
    raise ValueError(f"Invalid date format: {dt}")


def get_trial_balance_report(
    db: Session,
    business_id: int,
    fiscal_year_id: Optional[int] = None,
    currency_id: Optional[int] = None,
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
    account_type: Optional[str] = None,
    account_ids: Optional[List[int]] = None,
    project_id: Optional[int] = None,  # 🆕 فیلتر پروژه
    include_zero_balance: bool = False,
    skip: int = 0,
    take: int = 50,
) -> Dict[str, Any]:
    """
    گزارش تراز آزمایشی
    
    این گزارش برای هر حساب حسابداری نمایش می‌دهد:
    - مانده ابتدای دوره (بدهکار/بستانکار)
    - جمع بدهکار دوره
    - جمع بستانکار دوره
    - مانده انتهای دوره (بدهکار/بستانکار)
    
    Args:
        db: نشست پایگاه داده
        business_id: شناسه کسب‌وکار
        fiscal_year_id: شناسه سال مالی (اختیاری)
        currency_id: شناسه ارز (اختیاری)
        date_from: از تاریخ (اختیاری، فرمت YYYY-MM-DD)
        date_to: تا تاریخ (اختیاری، فرمت YYYY-MM-DD)
        account_type: نوع حساب (اختیاری)
        account_ids: لیست شناسه‌های حساب (اختیاری)
        include_zero_balance: نمایش حساب‌های با مانده صفر (پیش‌فرض: False)
        skip: تعداد رکوردهای رد شده برای pagination
        take: تعداد رکوردهای برگشتی
    
    Returns:
        dict: {
            'items': لیست حساب‌ها با تراز,
            'summary': خلاصه آمار,
            'pagination': اطلاعات pagination
        }
    """
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
    
    # دریافت تمام حساب‌ها (عمومی + اختصاصی کسب‌وکار)
    accounts_query = db.query(Account).filter(
        (Account.business_id == None) | (Account.business_id == business_id)  # noqa: E711
    )
    
    if account_type:
        accounts_query = accounts_query.filter(Account.account_type == account_type)
    
    if account_ids:
        accounts_query = accounts_query.filter(Account.id.in_(account_ids))
    
    accounts = accounts_query.order_by(Account.code.asc()).all()
    
    if not accounts:
        return {
            'items': [],
            'summary': {
                'total_accounts': 0,
                'total_opening_debit': 0.0,
                'total_opening_credit': 0.0,
                'total_period_debit': 0.0,
                'total_period_credit': 0.0,
                'total_closing_debit': 0.0,
                'total_closing_credit': 0.0,
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
                    if acc_id:
                        if acc_id not in opening_balance_data:
                            opening_balance_data[acc_id] = {'debit': Decimal(0), 'credit': Decimal(0)}
                        opening_balance_data[acc_id]['debit'] += Decimal(str(line.get('debit', 0) or 0))
                        opening_balance_data[acc_id]['credit'] += Decimal(str(line.get('credit', 0) or 0))
        except Exception:
            pass
    
    # محاسبه مانده ابتدای دوره برای هر حساب (از تراز افتتاحیه + تمام DocumentLine ها تا قبل از date_from)
    account_ids_list = [acc.id for acc in accounts]
    opening_debit_by_account = {}
    opening_credit_by_account = {}
    
    if date_from_obj:
        date_before_from = date_from_obj - timedelta(days=1)
        
        # دریافت مانده‌ها از تراز افتتاحیه
        for acc_id in account_ids_list:
            if acc_id in opening_balance_data:
                opening_debit_by_account[acc_id] = opening_balance_data[acc_id]['debit']
                opening_credit_by_account[acc_id] = opening_balance_data[acc_id]['credit']
            else:
                opening_debit_by_account[acc_id] = Decimal(0)
                opening_credit_by_account[acc_id] = Decimal(0)
        
        # محاسبه مانده از DocumentLine ها تا قبل از date_from
        opening_query = db.query(
            DocumentLine.account_id,
            func.coalesce(func.sum(DocumentLine.debit), 0).label('total_debit'),
            func.coalesce(func.sum(DocumentLine.credit), 0).label('total_credit')
        ).join(
            Document, DocumentLine.document_id == Document.id
        ).filter(
            and_(
                Document.business_id == business_id,
                Document.is_proforma == False,
                DocumentLine.account_id.isnot(None),
                DocumentLine.account_id.in_(account_ids_list),
                Document.document_date <= date_before_from
            )
        )
        
        if fiscal_year_id:
            opening_query = opening_query.filter(Document.fiscal_year_id == fiscal_year_id)
        
        if currency_id:
            opening_query = opening_query.filter(Document.currency_id == currency_id)
        
        # 🆕 فیلتر پروژه برای مانده ابتدای دوره
        if project_id:
            opening_query = opening_query.filter(Document.project_id == project_id)
        
        opening_query = opening_query.group_by(DocumentLine.account_id)
        opening_results = opening_query.all()
        
        for result in opening_results:
            acc_id = result.account_id
            if acc_id not in opening_debit_by_account:
                opening_debit_by_account[acc_id] = Decimal(0)
                opening_credit_by_account[acc_id] = Decimal(0)
            opening_debit_by_account[acc_id] += Decimal(str(result.total_debit or 0))
            opening_credit_by_account[acc_id] += Decimal(str(result.total_credit or 0))
    else:
        for acc_id in account_ids_list:
            opening_debit_by_account[acc_id] = Decimal(0)
            opening_credit_by_account[acc_id] = Decimal(0)
            if acc_id in opening_balance_data:
                opening_debit_by_account[acc_id] = opening_balance_data[acc_id]['debit']
                opening_credit_by_account[acc_id] = opening_balance_data[acc_id]['credit']
    
    # محاسبه جمع بدهکار و بستانکار دوره (در بازه date_from تا date_to)
    period_debit_by_account = {}
    period_credit_by_account = {}
    
    period_query = db.query(
        DocumentLine.account_id,
        func.coalesce(func.sum(DocumentLine.debit), 0).label('total_debit'),
        func.coalesce(func.sum(DocumentLine.credit), 0).label('total_credit')
    ).join(
        Document, DocumentLine.document_id == Document.id
    ).filter(
        and_(
            Document.business_id == business_id,
            Document.is_proforma == False,
            DocumentLine.account_id.isnot(None),
            DocumentLine.account_id.in_(account_ids_list),
            Document.document_date >= date_from_obj,
            Document.document_date <= date_to_obj,
        )
    )
    
    if fiscal_year_id:
        period_query = period_query.filter(Document.fiscal_year_id == fiscal_year_id)
    
    if currency_id:
        period_query = period_query.filter(Document.currency_id == currency_id)
    
    # 🆕 فیلتر پروژه برای گردش دوره
    if project_id:
        period_query = period_query.filter(Document.project_id == project_id)
    
    period_query = period_query.group_by(DocumentLine.account_id)
    period_results = period_query.all()
    
    for result in period_results:
        acc_id = result.account_id
        period_debit_by_account[acc_id] = Decimal(str(result.total_debit or 0))
        period_credit_by_account[acc_id] = Decimal(str(result.total_credit or 0))
    
    # محاسبه مانده انتهای دوره و ساخت آیتم‌ها
    items = []
    total_opening_debit = Decimal(0)
    total_opening_credit = Decimal(0)
    total_period_debit = Decimal(0)
    total_period_credit = Decimal(0)
    total_closing_debit = Decimal(0)
    total_closing_credit = Decimal(0)
    
    for account in accounts:
        acc_id = account.id
        
        # مانده ابتدای دوره
        opening_debit = opening_debit_by_account.get(acc_id, Decimal(0))
        opening_credit = opening_credit_by_account.get(acc_id, Decimal(0))
        opening_balance = opening_debit - opening_credit
        
        # جمع بدهکار و بستانکار دوره
        period_debit = period_debit_by_account.get(acc_id, Decimal(0))
        period_credit = period_credit_by_account.get(acc_id, Decimal(0))
        
        # مانده انتهای دوره
        closing_debit = opening_debit + period_debit
        closing_credit = opening_credit + period_credit
        closing_balance = closing_debit - closing_credit
        
        # اگر include_zero_balance=False و همه مقادیر صفر است، از لیست خارج کن
        if not include_zero_balance:
            if (opening_balance == 0 and period_debit == 0 and period_credit == 0 and closing_balance == 0):
                continue
        
        # تعیین نوع مانده (بدهکار/بستانکار)
        opening_debit_bal = max(opening_balance, Decimal(0)) if opening_balance >= 0 else Decimal(0)
        opening_credit_bal = max(-opening_balance, Decimal(0)) if opening_balance < 0 else Decimal(0)
        
        closing_debit_bal = max(closing_balance, Decimal(0)) if closing_balance >= 0 else Decimal(0)
        closing_credit_bal = max(-closing_balance, Decimal(0)) if closing_balance < 0 else Decimal(0)
        
        items.append({
            'account_id': acc_id,
            'account_code': account.code,
            'account_name': account.name,
            'account_type': account.account_type,
            'opening_debit': float(opening_debit_bal),
            'opening_credit': float(opening_credit_bal),
            'period_debit': float(period_debit),
            'period_credit': float(period_credit),
            'closing_debit': float(closing_debit_bal),
            'closing_credit': float(closing_credit_bal),
        })
        
        total_opening_debit += opening_debit_bal
        total_opening_credit += opening_credit_bal
        total_period_debit += period_debit
        total_period_credit += period_credit
        total_closing_debit += closing_debit_bal
        total_closing_credit += closing_credit_bal
    
    # Pagination
    total = len(items)
    current_page = (skip // take) + 1
    total_pages = (total + take - 1) // take if take > 0 else 1
    paginated_items = items[skip:skip + take]
    
    return {
        'items': paginated_items,
        'summary': {
            'total_accounts': total,
            'total_opening_debit': float(total_opening_debit),
            'total_opening_credit': float(total_opening_credit),
            'total_period_debit': float(total_period_debit),
            'total_period_credit': float(total_period_credit),
            'total_closing_debit': float(total_closing_debit),
            'total_closing_credit': float(total_closing_credit),
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

