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
from app.services.opening_balance_service import _find_existing_ob_document, _ensure_fiscal_year


def _parse_iso_date(dt: str | date) -> date:
    if isinstance(dt, date):
        return dt
    if isinstance(dt, str):
        return date.fromisoformat(dt.split('T')[0])
    raise ValueError(f"Invalid date format: {dt}")


def _build_account_tree(accounts: List[Account]) -> Dict[int, Dict[str, Any]]:
    """ساخت ساختار درختی حساب‌ها"""
    account_dict = {}
    
    # ساخت دیکشنری برای دسترسی سریع
    for acc in accounts:
        account_dict[acc.id] = {
            'id': acc.id,
            'code': acc.code,
            'name': acc.name,
            'account_type': acc.account_type,
            'parent_id': acc.parent_id,
            'business_id': acc.business_id,
            'children': [],
            'has_children': False,
        }
    
    # اضافه کردن فرزندان به والدین
    for acc_id, acc_data in account_dict.items():
        parent_id = acc_data['parent_id']
        if parent_id and parent_id in account_dict:
            account_dict[parent_id]['children'].append(acc_id)
            account_dict[parent_id]['has_children'] = True
    
    return account_dict


def _get_root_accounts(account_tree: Dict[int, Dict[str, Any]]) -> List[int]:
    """دریافت حساب‌های ریشه (بدون والد)"""
    roots = []
    for acc_id, acc_data in account_tree.items():
        if acc_data['parent_id'] is None:
            roots.append(acc_id)
    # مرتب‌سازی بر اساس کد حساب
    roots.sort(key=lambda aid: account_tree[aid]['code'])
    return roots


def _calculate_account_balances(
    db: Session,
    business_id: int,
    account_id: int,
    account_tree: Dict[int, Dict[str, Any]],
    balances_by_account: Dict[int, Dict[str, Decimal]],
    date_from_obj: date,
    date_to_obj: date,
    fiscal_year_id: Optional[int] = None,
    currency_id: Optional[int] = None,
) -> Dict[str, Decimal]:
    """
    محاسبه مانده‌های یک حساب (شامل فرزندانش)
    
    Returns:
        {
            'opening_debit': Decimal,
            'opening_credit': Decimal,
            'period_debit': Decimal,
            'period_credit': Decimal,
            'closing_debit': Decimal,
            'closing_credit': Decimal,
        }
    """
    acc_data = account_tree[account_id]
    
    # اگر حساب فرزند دارد، مانده آن را از مجموع فرزندانش محاسبه کن
    # همچنین مانده خود حساب را هم اضافه کن (در صورت وجود تراکنش مستقیم)
    if acc_data['has_children']:
        opening_debit = Decimal(0)
        opening_credit = Decimal(0)
        period_debit = Decimal(0)
        period_credit = Decimal(0)
        
        # اضافه کردن مانده خود حساب (اگر تراکنش مستقیم داشته باشد)
        account_balances = balances_by_account.get(account_id, {
            'opening_debit': Decimal(0),
            'opening_credit': Decimal(0),
            'period_debit': Decimal(0),
            'period_credit': Decimal(0),
        })
        opening_debit += account_balances['opening_debit']
        opening_credit += account_balances['opening_credit']
        period_debit += account_balances['period_debit']
        period_credit += account_balances['period_credit']
        
        # اضافه کردن مانده فرزندان
        for child_id in acc_data['children']:
            child_balances = _calculate_account_balances(
                db, business_id, child_id, account_tree, balances_by_account,
                date_from_obj, date_to_obj, fiscal_year_id, currency_id
            )
            opening_debit += child_balances['opening_debit']
            opening_credit += child_balances['opening_credit']
            period_debit += child_balances['period_debit']
            period_credit += child_balances['period_credit']
        
        # محاسبه مانده انتهای دوره از مانده خالص
        opening_balance = opening_debit - opening_credit
        closing_balance = opening_balance + period_debit - period_credit
        
        closing_debit_final = Decimal(0)
        closing_credit_final = Decimal(0)
        if closing_balance > 0:
            closing_debit_final = closing_balance
        elif closing_balance < 0:
            closing_credit_final = -closing_balance
        
        return {
            'opening_debit': opening_debit,
            'opening_credit': opening_credit,
            'period_debit': period_debit,
            'period_credit': period_credit,
            'closing_debit': closing_debit_final,
            'closing_credit': closing_credit_final,
        }
    else:
        # حساب برگ (leaf) - مانده را از balances_by_account بگیر
        balances = balances_by_account.get(account_id, {
            'opening_debit': Decimal(0),
            'opening_credit': Decimal(0),
            'period_debit': Decimal(0),
            'period_credit': Decimal(0),
        })
        
        # محاسبه مانده انتهای دوره از مانده خالص
        opening_balance = balances['opening_debit'] - balances['opening_credit']
        closing_balance = opening_balance + balances['period_debit'] - balances['period_credit']
        
        closing_debit_final = Decimal(0)
        closing_credit_final = Decimal(0)
        if closing_balance > 0:
            closing_debit_final = closing_balance
        elif closing_balance < 0:
            closing_credit_final = -closing_balance
        
        return {
            'opening_debit': balances['opening_debit'],
            'opening_credit': balances['opening_credit'],
            'period_debit': balances['period_debit'],
            'period_credit': balances['period_credit'],
            'closing_debit': closing_debit_final,
            'closing_credit': closing_credit_final,
        }


def get_accounts_review_report(
    db: Session,
    business_id: int,
    fiscal_year_id: Optional[int] = None,
    currency_id: Optional[int] = None,
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
    account_type: Optional[str] = None,
    include_zero_balance: bool = False,
    account_id: Optional[int] = None,  # برای دریافت جزئیات یک حساب خاص
    skip: int = 0,
    take: int = 50,
) -> Dict[str, Any]:
    """
    گزارش مرور حساب‌ها
    
    این گزارش ساختار درختی حساب‌ها را با مانده‌هایشان نمایش می‌دهد:
    - ساختار درختی حساب‌ها (چارت حساب‌ها)
    - مانده ابتدای دوره برای هر حساب
    - گردش بدهکار/بستانکار دوره
    - مانده انتهای دوره
    - برای حساب‌های والد: مجموع مانده فرزندان
    - امکان دریافت جزئیات تراکنش‌های یک حساب خاص
    
    Args:
        db: نشست پایگاه داده
        business_id: شناسه کسب‌وکار
        fiscal_year_id: شناسه سال مالی (اختیاری)
        currency_id: شناسه ارز (اختیاری)
        date_from: از تاریخ (اختیاری، فرمت YYYY-MM-DD)
        date_to: تا تاریخ (اختیاری، فرمت YYYY-MM-DD)
        account_type: نوع حساب (اختیاری)
        include_zero_balance: نمایش حساب‌های با مانده صفر (پیش‌فرض: False)
        account_id: شناسه حساب برای دریافت جزئیات (اختیاری)
        skip: تعداد رکوردهای رد شده برای pagination (فقط برای جزئیات)
        take: تعداد رکوردهای برگشتی (فقط برای جزئیات)
    
    Returns:
        dict: {
            'accounts': لیست حساب‌ها با ساختار درختی و مانده‌ها,
            'account_details': جزئیات تراکنش‌های حساب انتخاب شده (اگر account_id مشخص شده باشد),
            'summary': خلاصه آمار,
            'pagination': اطلاعات pagination (فقط برای جزئیات)
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
    
    # دریافت تمام حساب‌های کسب‌وکار
    accounts_query = db.query(Account).filter(
        and_(
            (Account.business_id == None) | (Account.business_id == business_id)  # noqa: E711
        )
    )
    
    if account_type:
        accounts_query = accounts_query.filter(Account.account_type == account_type)
    
    all_accounts = accounts_query.order_by(Account.code.asc()).all()
    
    # Debug: Log accounts count
    print(f"DEBUG: Found {len(all_accounts)} accounts for business_id={business_id}, account_type={account_type}")
    
    if not all_accounts:
        return {
            'accounts': [],
            'account_details': [],
            'summary': {
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
    
    # ساخت ساختار درختی
    account_tree = _build_account_tree(all_accounts)
    
    # دریافت مانده ابتدای دوره از تراز افتتاحیه
    opening_balance_data = {}
    if fy_id:
        try:
            ob_doc = _find_existing_ob_document(db, business_id, fy_id)
            if ob_doc:
                # دریافت خطوط سند تراز افتتاحیه
                ob_lines_query = db.query(
                    DocumentLine.account_id,
                    func.sum(DocumentLine.debit).label('debit'),
                    func.sum(DocumentLine.credit).label('credit')
                ).filter(
                    DocumentLine.document_id == ob_doc.id,
                    DocumentLine.account_id.isnot(None)
                )
                if currency_id:
                    ob_lines_query = ob_lines_query.join(Document, DocumentLine.document_id == Document.id).filter(Document.currency_id == currency_id)
                
                ob_lines_query = ob_lines_query.group_by(DocumentLine.account_id)
                ob_results = ob_lines_query.all()
                
                for result in ob_results:
                    acc_id = result.account_id
                    if acc_id:
                        if acc_id not in opening_balance_data:
                            opening_balance_data[acc_id] = {'debit': Decimal(0), 'credit': Decimal(0)}
                        opening_balance_data[acc_id]['debit'] += Decimal(str(result.debit or 0))
                        opening_balance_data[acc_id]['credit'] += Decimal(str(result.credit or 0))
        except Exception:
            pass
    
    # محاسبه مانده ابتدای دوره از DocumentLine ها تا قبل از date_from
    account_ids = [acc.id for acc in all_accounts]
    
    # محاسبه date_before_from برای فیلتر صحیح
    date_before_from = None
    if date_from_obj:
        date_before_from = date_from_obj - timedelta(days=1)
    
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
            Document.document_type != "opening_balance",  # حذف سند تراز افتتاحیه برای جلوگیری از شمارش دوباره
            DocumentLine.account_id.isnot(None),
            DocumentLine.account_id.in_(account_ids),
        )
    )
    
    # اضافه کردن فیلتر تاریخ فقط اگر date_before_from مشخص باشد
    if date_before_from:
        opening_query = opening_query.filter(Document.document_date <= date_before_from)
    
    if fiscal_year_id:
        opening_query = opening_query.filter(Document.fiscal_year_id == fy_id)
    
    if currency_id:
        opening_query = opening_query.filter(Document.currency_id == currency_id)
    
    opening_query = opening_query.group_by(DocumentLine.account_id)
    opening_results = opening_query.all()
    
    # محاسبه گردش دوره
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
            DocumentLine.account_id.in_(account_ids),
            Document.document_date >= date_from_obj,
            Document.document_date <= date_to_obj,
        )
    )
    
    if fiscal_year_id:
        period_query = period_query.filter(Document.fiscal_year_id == fy_id)
    
    if currency_id:
        period_query = period_query.filter(Document.currency_id == currency_id)
    
    period_query = period_query.group_by(DocumentLine.account_id)
    period_results = period_query.all()
    
    # ساخت دیکشنری برای دسترسی سریع به مانده‌ها
    balances_by_account = {}
    for acc_id in account_ids:
        balances_by_account[acc_id] = {
            'opening_debit': Decimal(0),
            'opening_credit': Decimal(0),
            'period_debit': Decimal(0),
            'period_credit': Decimal(0),
        }
    
    # اضافه کردن مانده از تراز افتتاحیه
    for acc_id in account_ids:
        if acc_id in opening_balance_data:
            balances_by_account[acc_id]['opening_debit'] += opening_balance_data[acc_id]['debit']
            balances_by_account[acc_id]['opening_credit'] += opening_balance_data[acc_id]['credit']
    
    # اضافه کردن مانده از تراکنش‌های قبل از دوره
    for result in opening_results:
        acc_id = result.account_id
        if acc_id in balances_by_account:
            balances_by_account[acc_id]['opening_debit'] += Decimal(str(result.total_debit or 0))
            balances_by_account[acc_id]['opening_credit'] += Decimal(str(result.total_credit or 0))
    
    # اضافه کردن گردش دوره
    for result in period_results:
        acc_id = result.account_id
        if acc_id in balances_by_account:
            balances_by_account[acc_id]['period_debit'] += Decimal(str(result.total_debit or 0))
            balances_by_account[acc_id]['period_credit'] += Decimal(str(result.total_credit or 0))
    
    # ساخت لیست حساب‌ها با مانده‌های محاسبه شده (به صورت بازگشتی)
    def _build_account_item(acc_id: int, level: int = 0) -> Dict[str, Any]:
        """ساخت آیتم حساب با مانده‌هایش"""
        acc_data = account_tree[acc_id]
        balances = _calculate_account_balances(
            db, business_id, acc_id, account_tree, balances_by_account,
            date_from_obj, date_to_obj, fy_id, currency_id
        )
        
        # اگر include_zero_balance=False و همه مانده‌ها صفر است، نادیده بگیر
        # اما فقط برای حساب‌های برگ (leaf) - حساب‌های والد باید بررسی شوند حتی اگر خودشان مانده صفر دارند
        if not include_zero_balance and not acc_data['has_children']:
            if (balances['opening_debit'] == 0 and balances['opening_credit'] == 0 and
                balances['period_debit'] == 0 and balances['period_credit'] == 0 and
                balances['closing_debit'] == 0 and balances['closing_credit'] == 0):
                return None
        
        account = next((acc for acc in all_accounts if acc.id == acc_id), None)
        if not account:
            return None
        
        item = {
            'account_id': acc_id,
            'account_code': acc_data['code'],
            'account_name': acc_data['name'],
            'account_type': acc_data['account_type'],
            'level': level,
            'has_children': acc_data['has_children'],
            'children': [],
            'opening_debit': float(balances['opening_debit']),
            'opening_credit': float(balances['opening_credit']),
            'period_debit': float(balances['period_debit']),
            'period_credit': float(balances['period_credit']),
            'closing_debit': float(balances['closing_debit']),
            'closing_credit': float(balances['closing_credit']),
        }
        
        # اضافه کردن فرزندان
        if acc_data['has_children']:
            for child_id in sorted(acc_data['children'], key=lambda aid: account_tree[aid]['code']):
                child_item = _build_account_item(child_id, level + 1)
                if child_item is not None:
                    item['children'].append(child_item)
        
        return item
    
    # ساخت لیست حساب‌های ریشه
    root_accounts = _get_root_accounts(account_tree)
    accounts_list = []
    for root_id in root_accounts:
        root_item = _build_account_item(root_id, 0)
        if root_item is not None:
            accounts_list.append(root_item)
    
    # محاسبه خلاصه
    total_opening_debit = Decimal(0)
    total_opening_credit = Decimal(0)
    total_period_debit = Decimal(0)
    total_period_credit = Decimal(0)
    total_closing_debit = Decimal(0)
    total_closing_credit = Decimal(0)
    
    def _sum_accounts(accounts: List[Dict[str, Any]]):
        nonlocal total_opening_debit, total_opening_credit, total_period_debit, total_period_credit, total_closing_debit, total_closing_credit
        for acc in accounts:
            total_opening_debit += Decimal(str(acc['opening_debit']))
            total_opening_credit += Decimal(str(acc['opening_credit']))
            total_period_debit += Decimal(str(acc['period_debit']))
            total_period_credit += Decimal(str(acc['period_credit']))
            total_closing_debit += Decimal(str(acc['closing_debit']))
            total_closing_credit += Decimal(str(acc['closing_credit']))
            if acc['children']:
                _sum_accounts(acc['children'])
    
    _sum_accounts(accounts_list)
    
    # اعتبارسنجی تراز (Trial Balance Check)
    # در حسابداری دوبل، جمع بدهکارها باید برابر جمع بستانکارها باشد
    balance_valid = True
    balance_error = None
    tolerance = Decimal('0.01')  # تحمل خطای گرد کردن
    
    # بررسی تراز ابتدای دوره
    opening_diff = abs(total_opening_debit - total_opening_credit)
    if opening_diff > tolerance:
        balance_valid = False
        balance_error = f"تراز ابتدای دوره برقرار نیست: تفاوت = {float(opening_diff)}"
    
    # بررسی تراز دوره
    period_diff = abs(total_period_debit - total_period_credit)
    if period_diff > tolerance:
        balance_valid = False
        if balance_error:
            balance_error += f" | تراز دوره برقرار نیست: تفاوت = {float(period_diff)}"
        else:
            balance_error = f"تراز دوره برقرار نیست: تفاوت = {float(period_diff)}"
    
    # بررسی تراز انتهای دوره
    closing_diff = abs(total_closing_debit - total_closing_credit)
    if closing_diff > tolerance:
        balance_valid = False
        if balance_error:
            balance_error += f" | تراز انتهای دوره برقرار نیست: تفاوت = {float(closing_diff)}"
        else:
            balance_error = f"تراز انتهای دوره برقرار نیست: تفاوت = {float(closing_diff)}"
    
    # دریافت جزئیات تراکنش‌ها برای حساب انتخاب شده
    account_details = []
    details_pagination = {
        'total': 0,
        'page': 1,
        'per_page': take,
        'total_pages': 1,
        'has_next': False,
        'has_prev': False,
    }
    
    if account_id and account_id in account_ids:
        # محاسبه مانده ابتدای دوره برای حساب انتخاب شده
        account_opening_balance = balances_by_account.get(account_id, {
            'opening_debit': Decimal(0),
            'opening_credit': Decimal(0),
        })
        account_opening_debit = account_opening_balance['opening_debit']
        account_opening_credit = account_opening_balance['opening_credit']
        running_balance = account_opening_debit - account_opening_credit
        
        # دریافت تراکنش‌های حساب
        details_query = db.query(
            DocumentLine,
            Document,
        ).join(
            Document, DocumentLine.document_id == Document.id
        ).filter(
            and_(
                Document.business_id == business_id,
                Document.is_proforma == False,
                DocumentLine.account_id == account_id,
                Document.document_date >= date_from_obj,
                Document.document_date <= date_to_obj,
            )
        ).order_by(
            Document.document_date.asc(),
            Document.id.asc(),
            DocumentLine.id.asc()
        )
        
        if currency_id:
            details_query = details_query.filter(Document.currency_id == currency_id)
        
        # Pagination
        total_details = details_query.count()
        details_lines = details_query.offset(skip).limit(take).all()
        
        # استخراج اطلاعات
        person_ids = list(set(line.person_id for line, doc in details_lines if line.person_id is not None))
        persons_map = {}
        if person_ids:
            from adapters.db.models.person import Person
            persons = db.query(Person).filter(Person.id.in_(person_ids)).all()
            for person in persons:
                persons_map[person.id] = {
                    'id': person.id,
                    'code': person.code,
                    'name': person.alias_name or person.name or '',
                }
        
        for line, doc in details_lines:
            debit = Decimal(str(line.debit or 0))
            credit = Decimal(str(line.credit or 0))
            running_balance = running_balance + debit - credit
            
            balance_type = 'balanced'
            if running_balance > 0:
                balance_type = 'debit'
            elif running_balance < 0:
                balance_type = 'credit'
            
            counterpart_name = ''
            if line.person_id and line.person_id in persons_map:
                counterpart_name = persons_map[line.person_id]['name']
            
            def _get_document_type_name(doc_type: str | None) -> str:
                if not doc_type:
                    return ''
                mapping = {
                    'invoice_sales': 'فاکتور فروش',
                    'invoice_sales_return': 'برگشت از فروش',
                    'invoice_purchase': 'فاکتور خرید',
                    'invoice_purchase_return': 'برگشت از خرید',
                    'receipt': 'دریافت',
                    'payment': 'پرداخت',
                    'transfer': 'انتقال',
                    'expense_income': 'درآمد/هزینه',
                    'opening_balance': 'تراز افتتاحیه',
                    'manual_document': 'سند دستی',
                }
                return mapping.get(doc_type, doc_type)
            
            account_details.append({
                'document_id': doc.id,
                'document_code': doc.code or '',
                'document_date': doc.document_date.isoformat() if doc.document_date else None,
                'document_type': doc.document_type or '',
                'document_type_name': _get_document_type_name(doc.document_type),
                'counterpart_name': counterpart_name,
                'debit': float(debit),
                'credit': float(credit),
                'balance': float(running_balance),
                'balance_type': balance_type,
                'description': line.description or doc.description or '',
            })
        
        details_pagination = {
            'total': total_details,
            'page': (skip // take) + 1,
            'per_page': take,
            'total_pages': (total_details + take - 1) // take if take > 0 else 1,
            'has_next': (skip + take) < total_details,
            'has_prev': skip > 0,
        }
    
    return {
        'accounts': accounts_list,
        'account_details': account_details,
        'summary': {
            'total_opening_debit': float(total_opening_debit),
            'total_opening_credit': float(total_opening_credit),
            'total_period_debit': float(total_period_debit),
            'total_period_credit': float(total_period_credit),
            'total_closing_debit': float(total_closing_debit),
            'total_closing_credit': float(total_closing_credit),
            'balance_valid': balance_valid,
            'balance_error': balance_error,
            'opening_balance_diff': float(opening_diff),
            'period_balance_diff': float(period_diff),
            'closing_balance_diff': float(closing_diff),
        },
        'pagination': details_pagination,
    }

