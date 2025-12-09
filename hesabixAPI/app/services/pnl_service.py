from __future__ import annotations

from typing import Any, Dict, List, Optional
from datetime import date
from decimal import Decimal

from sqlalchemy.orm import Session
from sqlalchemy import and_, func, or_

from adapters.db.models.document import Document
from adapters.db.models.document_line import DocumentLine
from adapters.db.models.account import Account
from adapters.db.models.fiscal_year import FiscalYear
from app.services.opening_balance_service import _ensure_fiscal_year


def _parse_iso_date(dt: str | date) -> date:
    if isinstance(dt, date):
        return dt
    if isinstance(dt, str):
        return date.fromisoformat(dt.split('T')[0])
    raise ValueError(f"Invalid date format: {dt}")


def _is_revenue_account(code: str) -> bool:
    """تشخیص اینکه آیا یک حساب، حساب درآمد است یا نه (بر اساس کد)"""
    if not code:
        return False
    # حساب‌های درآمد معمولاً با 5 شروع می‌شوند (مثلاً 50001, 50002, ...)
    code_clean = code.strip()
    return code_clean.startswith('5') or code_clean.startswith('۶')  # Support Persian digits


def _is_expense_account(code: str) -> bool:
    """تشخیص اینکه آیا یک حساب، حساب هزینه است یا نه (بر اساس کد)"""
    if not code:
        return False
    # حساب‌های هزینه معمولاً با 4 یا 7 شروع می‌شوند (مثلاً 40001, 70406, ...)
    code_clean = code.strip()
    return (code_clean.startswith('4') or code_clean.startswith('۷') or
            code_clean.startswith('7') or code_clean.startswith('۴'))


def get_pnl_period_report(
    db: Session,
    business_id: int,
    fiscal_year_id: Optional[int] = None,
    currency_id: Optional[int] = None,
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
    project_id: Optional[int] = None,  # 🆕 فیلتر پروژه
    skip: int = 0,
    take: int = 100,
) -> Dict[str, Any]:
    """
    گزارش سود و زیان دوره‌ای
    
    این گزارش نمایش می‌دهد:
    - درآمدهای دوره (جمع Credit حساب‌های درآمد)
    - هزینه‌های دوره (جمع Debit حساب‌های هزینه)
    - سود/زیان خالص
    
    Args:
        db: نشست پایگاه داده
        business_id: شناسه کسب‌وکار
        fiscal_year_id: شناسه سال مالی (اختیاری)
        currency_id: شناسه ارز (اختیاری)
        date_from: از تاریخ (اختیاری، فرمت YYYY-MM-DD)
        date_to: تا تاریخ (اختیاری، فرمت YYYY-MM-DD)
        skip: تعداد رکوردهای رد شده برای pagination
        take: تعداد رکوردهای برگشتی
    
    Returns:
        dict: {
            'revenue_items': لیست حساب‌های درآمد,
            'expense_items': لیست حساب‌های هزینه,
            'summary': خلاصه (جمع درآمد، جمع هزینه، سود/زیان),
            'pagination': اطلاعات pagination
        }
    """
    fy_id, fy_start_date = _ensure_fiscal_year(db, business_id, fiscal_year_id)
    
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
    
    # دریافت تمام حساب‌های کسب‌وکار
    all_accounts = db.query(Account).filter(
        and_(
            (Account.business_id == None) | (Account.business_id == business_id),  # noqa: E711
        )
    ).order_by(Account.code.asc()).all()
    
    # جدا کردن حساب‌های درآمد و هزینه
    revenue_accounts = [acc for acc in all_accounts if _is_revenue_account(acc.code)]
    expense_accounts = [acc for acc in all_accounts if _is_expense_account(acc.code)]
    
    account_ids = [acc.id for acc in revenue_accounts + expense_accounts]
    
    if not account_ids:
        return {
            'revenue_items': [],
            'expense_items': [],
            'summary': {
                'total_revenue': 0.0,
                'total_expense': 0.0,
                'net_profit_loss': 0.0,
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
    
    # محاسبه گردش بدهکار و بستانکار برای هر حساب در بازه تاریخ
    turnover_query = db.query(
        DocumentLine.account_id,
        func.sum(DocumentLine.debit).label('total_debit'),
        func.sum(DocumentLine.credit).label('total_credit')
    ).join(
        Document, DocumentLine.document_id == Document.id
    ).filter(
        and_(
            Document.business_id == business_id,
            Document.is_proforma == False,
            DocumentLine.account_id.isnot(None),
            DocumentLine.account_id.in_(account_ids),
            Document.document_date >= date_from_obj,
            Document.document_date <= date_to_obj,
        )
    )
    
    # 🆕 فیلتر پروژه
    if project_id:
        turnover_query = turnover_query.filter(Document.project_id == project_id)
    
    turnover_query = turnover_query.group_by(DocumentLine.account_id)
    
    if currency_id:
        turnover_query = turnover_query.filter(Document.currency_id == currency_id)
    
    turnover_results = turnover_query.all()
    
    # ساخت دیکشنری برای دسترسی سریع به گردش هر حساب
    turnover_by_account = {}
    for result in turnover_results:
        turnover_by_account[result.account_id] = {
            'debit': Decimal(str(result.total_debit or 0)),
            'credit': Decimal(str(result.total_credit or 0)),
        }
    
    # ساخت آیتم‌های درآمد
    revenue_items = []
    total_revenue = Decimal(0)
    
    for account in revenue_accounts:
        turnover = turnover_by_account.get(account.id, {'debit': Decimal(0), 'credit': Decimal(0)})
        # در حساب‌های درآمد، Credit = درآمد، Debit = برگشت/کاهش
        revenue = turnover['credit'] - turnover['debit']
        total_revenue += revenue
        
        revenue_items.append({
            'account_id': account.id,
            'account_code': account.code,
            'account_name': account.name,
            'debit': float(turnover['debit']),  # برگشت/کاهش
            'credit': float(turnover['credit']),  # درآمد
            'revenue': float(revenue),  # درآمد خالص
        })
    
    # ساخت آیتم‌های هزینه
    expense_items = []
    total_expense = Decimal(0)
    
    for account in expense_accounts:
        turnover = turnover_by_account.get(account.id, {'debit': Decimal(0), 'credit': Decimal(0)})
        # در حساب‌های هزینه، Debit = هزینه، Credit = برگشت/کاهش
        expense = turnover['debit'] - turnover['credit']
        total_expense += expense
        
        expense_items.append({
            'account_id': account.id,
            'account_code': account.code,
            'account_name': account.name,
            'debit': float(turnover['debit']),  # هزینه
            'credit': float(turnover['credit']),  # برگشت/کاهش
            'expense': float(expense),  # هزینه خالص
        })
    
    # محاسبه سود/زیان خالص
    net_profit_loss = total_revenue - total_expense
    
    # Pagination (برای هر دو لیست به صورت جداگانه یا ترکیبی)
    # در اینجا همه آیتم‌ها را برمی‌گردانیم (بدون pagination برای آیتم‌ها)
    # اما می‌توان pagination را برای آیتم‌ها نیز اضافه کرد
    
    return {
        'revenue_items': revenue_items,
        'expense_items': expense_items,
        'summary': {
            'total_revenue': float(total_revenue),
            'total_expense': float(total_expense),
            'net_profit_loss': float(net_profit_loss),
        },
        'pagination': {
            'total': len(revenue_items) + len(expense_items),
            'page': 1,
            'per_page': take,
            'total_pages': 1,
            'has_next': False,
            'has_prev': False,
        }
    }


def get_pnl_cumulative_report(
    db: Session,
    business_id: int,
    fiscal_year_id: Optional[int] = None,
    currency_id: Optional[int] = None,
    date_to: Optional[str] = None,
    project_id: Optional[int] = None,  # 🆕 فیلتر پروژه
    skip: int = 0,
    take: int = 100,
) -> Dict[str, Any]:
    """
    گزارش سود و زیان تجمعی
    
    این گزارش نمایش می‌دهد:
    - درآمدهای تجمعی از ابتدای سال مالی تا تاریخ مشخص (جمع Credit حساب‌های درآمد)
    - هزینه‌های تجمعی از ابتدای سال مالی تا تاریخ مشخص (جمع Debit حساب‌های هزینه)
    - سود/زیان خالص تجمعی
    
    تفاوت با گزارش دوره‌ای:
    - در گزارش دوره‌ای: فقط بین date_from و date_to
    - در گزارش تجمعی: از ابتدای سال مالی تا date_to
    
    Args:
        db: نشست پایگاه داده
        business_id: شناسه کسب‌وکار
        fiscal_year_id: شناسه سال مالی (اختیاری)
        currency_id: شناسه ارز (اختیاری)
        date_to: تا تاریخ (اختیاری، فرمت YYYY-MM-DD) - پیش‌فرض: امروز
        skip: تعداد رکوردهای رد شده برای pagination
        take: تعداد رکوردهای برگشتی
    
    Returns:
        dict: {
            'revenue_items': لیست حساب‌های درآمد با مانده تجمعی,
            'expense_items': لیست حساب‌های هزینه با مانده تجمعی,
            'summary': خلاصه (جمع درآمد، جمع هزینه، سود/زیان),
            'pagination': اطلاعات pagination
        }
    """
    fy_id, fy_start_date = _ensure_fiscal_year(db, business_id, fiscal_year_id)
    
    # تاریخ پایان
    date_to_obj = None
    
    if date_to:
        try:
            date_to_obj = _parse_iso_date(date_to)
        except Exception:
            pass
    
    if date_to_obj is None:
        fiscal_year = db.query(FiscalYear).filter(FiscalYear.id == fy_id).first()
        date_to_obj = fiscal_year.end_date if fiscal_year and fiscal_year.end_date else date.today()
    
    # تاریخ شروع همیشه ابتدای سال مالی است
    date_from_obj = fy_start_date
    
    # دریافت تمام حساب‌های کسب‌وکار
    all_accounts = db.query(Account).filter(
        and_(
            (Account.business_id == None) | (Account.business_id == business_id),  # noqa: E711
        )
    ).order_by(Account.code.asc()).all()
    
    # جدا کردن حساب‌های درآمد و هزینه
    revenue_accounts = [acc for acc in all_accounts if _is_revenue_account(acc.code)]
    expense_accounts = [acc for acc in all_accounts if _is_expense_account(acc.code)]
    
    account_ids = [acc.id for acc in revenue_accounts + expense_accounts]
    
    if not account_ids:
        return {
            'revenue_items': [],
            'expense_items': [],
            'summary': {
                'total_revenue': 0.0,
                'total_expense': 0.0,
                'net_profit_loss': 0.0,
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
    
    # محاسبه گردش بدهکار و بستانکار برای هر حساب از ابتدای سال مالی تا date_to
    turnover_query = db.query(
        DocumentLine.account_id,
        func.sum(DocumentLine.debit).label('total_debit'),
        func.sum(DocumentLine.credit).label('total_credit')
    ).join(
        Document, DocumentLine.document_id == Document.id
    ).filter(
        and_(
            Document.business_id == business_id,
            Document.is_proforma == False,
            DocumentLine.account_id.isnot(None),
            DocumentLine.account_id.in_(account_ids),
            Document.document_date >= date_from_obj,
            Document.document_date <= date_to_obj,
        )
    )
    
    # 🆕 فیلتر پروژه
    if project_id:
        turnover_query = turnover_query.filter(Document.project_id == project_id)
    
    turnover_query = turnover_query.group_by(DocumentLine.account_id)
    
    if currency_id:
        turnover_query = turnover_query.filter(Document.currency_id == currency_id)
    
    turnover_results = turnover_query.all()
    
    # ساخت دیکشنری برای دسترسی سریع به گردش هر حساب
    turnover_by_account = {}
    for result in turnover_results:
        turnover_by_account[result.account_id] = {
            'debit': Decimal(str(result.total_debit or 0)),
            'credit': Decimal(str(result.total_credit or 0)),
        }
    
    # ساخت آیتم‌های درآمد
    revenue_items = []
    total_revenue = Decimal(0)
    
    for account in revenue_accounts:
        turnover = turnover_by_account.get(account.id, {'debit': Decimal(0), 'credit': Decimal(0)})
        # در حساب‌های درآمد، Credit = درآمد، Debit = برگشت/کاهش
        revenue = turnover['credit'] - turnover['debit']
        total_revenue += revenue
        
        revenue_items.append({
            'account_id': account.id,
            'account_code': account.code,
            'account_name': account.name,
            'debit': float(turnover['debit']),  # برگشت/کاهش
            'credit': float(turnover['credit']),  # درآمد
            'revenue': float(revenue),  # درآمد خالص
        })
    
    # ساخت آیتم‌های هزینه
    expense_items = []
    total_expense = Decimal(0)
    
    for account in expense_accounts:
        turnover = turnover_by_account.get(account.id, {'debit': Decimal(0), 'credit': Decimal(0)})
        # در حساب‌های هزینه، Debit = هزینه، Credit = برگشت/کاهش
        expense = turnover['debit'] - turnover['credit']
        total_expense += expense
        
        expense_items.append({
            'account_id': account.id,
            'account_code': account.code,
            'account_name': account.name,
            'debit': float(turnover['debit']),  # هزینه
            'credit': float(turnover['credit']),  # برگشت/کاهش
            'expense': float(expense),  # هزینه خالص
        })
    
    # محاسبه سود/زیان خالص تجمعی
    net_profit_loss = total_revenue - total_expense
    
    return {
        'revenue_items': revenue_items,
        'expense_items': expense_items,
        'summary': {
            'total_revenue': float(total_revenue),
            'total_expense': float(total_expense),
            'net_profit_loss': float(net_profit_loss),
            'date_from': date_from_obj.isoformat(),  # ابتدای سال مالی
            'date_to': date_to_obj.isoformat(),  # تاریخ پایان
        },
        'pagination': {
            'total': len(revenue_items) + len(expense_items),
            'page': 1,
            'per_page': take,
            'total_pages': 1,
            'has_next': False,
            'has_prev': False,
        }
    }

