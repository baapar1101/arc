"""
سرویس بستن سال مالی (Year End Closing)

این سرویس برای بستن سال مالی و انتقال مانده‌ها به سال جدید استفاده می‌شود.
"""

from __future__ import annotations

import io
import json
import zipfile
from typing import Any, Dict, List, Optional, Tuple
from datetime import date, timedelta, datetime
from decimal import Decimal

from sqlalchemy.orm import Session
from sqlalchemy import and_, func, or_, inspect, text
from fastapi import UploadFile

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
from app.services.invoice_service import _compute_available_stock, _iter_product_movements
from app.services.file_storage_service import FileStorageService
from collections import defaultdict, deque


def _json_default(o: Any):
    """تابع helper برای JSON serialization"""
    if isinstance(o, (datetime, date)):
        return o.isoformat()
    if isinstance(o, Decimal):
        return str(o)
    return str(o)


def _discover_scoped_tables(db: Session) -> Dict[str, Dict[str, Any]]:
    """کشف جداول مرتبط با business_id"""
    engine = db.get_bind()
    inspector = inspect(engine)
    tables_info: Dict[str, Dict[str, Any]] = {}
    for table_name in inspector.get_table_names():
        try:
            cols = inspector.get_columns(table_name)
        except Exception:
            continue
        col_names = {c["name"] for c in cols}
        if "business_id" in col_names or table_name == "businesses":
            pk_cols = inspector.get_pk_constraint(table_name).get("constrained_columns") or []
            tables_info[table_name] = {
                "columns": [c["name"] for c in cols],
                "pk": pk_cols,
            }
    return tables_info


def _dump_business_data(db: Session, business_id: int) -> Dict[str, Any]:
    """استخراج داده‌های کسب‌وکار برای پشتیبان‌گیری"""
    tables = _discover_scoped_tables(db)
    data_out: Dict[str, List[Dict[str, Any]]] = {}

    for table_name, meta in tables.items():
        if table_name == "businesses":
            stmt = text(f"SELECT * FROM {table_name} WHERE id = :bid")
            rows = [dict(r._mapping) for r in db.execute(stmt, {"bid": business_id}).all()]
        else:
            stmt = text(f"SELECT * FROM {table_name} WHERE business_id = :bid")
            try:
                rows = [dict(r._mapping) for r in db.execute(stmt, {"bid": business_id}).all()]
            except Exception:
                rows = []
        data_out[table_name] = rows

    metadata = {
        "schema_version": "v1",
        "created_at": datetime.utcnow().isoformat(),
        "business_id": business_id,
        "tables": list(data_out.keys()),
        "backup_reason": "year_end_closing",
    }
    return {"metadata": metadata, "tables": data_out}


async def _create_backup_before_closing(
    db: Session,
    business_id: int,
    user_id: int,
    fiscal_year_id: int,
) -> Dict[str, Any]:
    """
    ایجاد پشتیبان همزمان قبل از بستن سال مالی
    
    Returns:
        dict: {"success": True, "backup_id": "...", "filename": "..."} یا {"success": False, "error": "..."}
    """
    try:
        # استخراج داده‌ها
        snapshot = _dump_business_data(db, business_id)
        
        # ساخت فایل ZIP
        buf = io.BytesIO()
        with zipfile.ZipFile(buf, mode="w", compression=zipfile.ZIP_DEFLATED) as zf:
            zf.writestr("metadata.json", json.dumps(snapshot["metadata"], ensure_ascii=False, indent=2, default=_json_default))
            for table_name, rows in snapshot["tables"].items():
                out = io.StringIO()
                for row in rows:
                    out.write(json.dumps(row, ensure_ascii=False, default=_json_default))
                    out.write("\n")
                zf.writestr(f"tables/{table_name}.jsonl", out.getvalue().encode("utf-8"))
        
        buf.seek(0)
        filename = f"business_{business_id}_pre_closing_fy_{fiscal_year_id}_{datetime.utcnow().strftime('%Y%m%dT%H%M%SZ')}.hbx"
        
        # ذخیره فایل
        storage = FileStorageService(db)
        faux_upload = UploadFile(filename=filename, file=io.BytesIO(buf.getvalue()))
        saved = await storage.upload_file(
            faux_upload,
            user_id=user_id,
            module_context="business_backup",
            developer_data={
                "business_id": business_id,
                "schema_version": snapshot["metadata"]["schema_version"],
                "backup_reason": "year_end_closing",
                "fiscal_year_id": fiscal_year_id,
            },
            is_temporary=False,
            expires_in_days=3650,
            business_id=business_id,
            check_storage_limit=True,
        )
        
        return {
            "success": True,
            "backup_id": str(saved.get("id", "")),
            "filename": filename,
            "file_info": saved,
        }
    except Exception as e:
        return {
            "success": False,
            "error": str(e),
        }


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
    total_expense = Decimal(0)  # برای مدیریت مانده منفی حساب‌های درآمد
    
    for account in revenue_accounts:
        balance_info = _calculate_account_balance(
            db, business_id, account.id, fiscal_year_id, fiscal_year.end_date
        )
        closing_balance = balance_info['closing_balance']
        
        # بستن همه حساب‌های درآمد (چه مثبت چه منفی)
        if closing_balance != 0:  # فقط حساب‌هایی که مانده دارند
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
            # فقط مانده مثبت به درآمد اضافه می‌شود (مانده منفی در واقع هزینه است)
            if closing_balance > 0:
                total_revenue += closing_balance
            else:
                # مانده منفی در حساب درآمد = هزینه، باید به هزینه اضافه شود
                total_expense += abs(closing_balance)
    
    # محاسبه مانده حساب‌های هزینه
    expense_items = []
    # total_expense قبلاً در بخش درآمد تعریف شده (برای مدیریت مانده منفی)
    
    for account in expense_accounts:
        balance_info = _calculate_account_balance(
            db, business_id, account.id, fiscal_year_id, fiscal_year.end_date
        )
        closing_balance = balance_info['closing_balance']
        
        # بستن همه حساب‌های هزینه (چه مثبت چه منفی)
        if closing_balance != 0:  # فقط حساب‌هایی که مانده دارند
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
            # فقط مانده مثبت به هزینه اضافه می‌شود (مانده منفی در واقع درآمد است)
            if closing_balance > 0:
                total_expense += closing_balance
            else:
                # مانده منفی در حساب هزینه = درآمد، باید به درآمد اضافه شود
                total_revenue += abs(closing_balance)
    
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


async def close_fiscal_year(
    db: Session,
    business_id: int,
    fiscal_year_id: int,
    user_id: int,
    new_fiscal_year_title: str,
    auto_create_opening_balance: bool = True,
    # مالیات
    tax_percentage: Optional[float] = None,
    tax_amount: Optional[float] = None,
    # تقسیم سود
    profit_distribution_percentage: Optional[float] = None,
    profit_distribution_amount: Optional[float] = None,
    shareholder_profit_account_id: Optional[int] = None,
    # سود انباشته سنواتی
    retained_earnings_from_previous_years: Optional[float] = None,
    # تنظیمات
    auto_issue_person_balance_document: bool = False,
    # تنظیمات سال مالی جدید
    new_fiscal_year_start_date: Optional[date] = None,
    new_fiscal_year_end_date: Optional[date] = None,
    inventory_valuation_method: str = "FIFO",
    # تقسیم سود بین سهامداران
    shareholder_distributions: Optional[List[Dict[str, Any]]] = None,
) -> Dict[str, Any]:
    """
    بستن سال مالی
    
    این تابع:
    1. از دیتابیس پشتیبان تهیه می‌کند
    2. حساب‌های درآمد و هزینه را می‌بندد
    3. مالیات بر درآمد را محاسبه و ثبت می‌کند
    4. سود را بین سهامداران تقسیم می‌کند
    5. سود/زیان را به حساب سود یا زیان انباشته منتقل می‌کند
    6. سند توازن اشخاص را ایجاد می‌کند (در صورت نیاز)
    7. سال مالی جدید ایجاد می‌کند
    8. تراز افتتاحیه سال جدید را ایجاد می‌کند (در صورت نیاز)
    """
    # مرحله 1: ایجاد پشتیبان قبل از بستن
    backup_result = await _create_backup_before_closing(db, business_id, user_id, fiscal_year_id)
    if not backup_result.get("success", False):
        raise ApiError(
            "BACKUP_FAILED",
            f"خطا در ایجاد پشتیبان قبل از بستن سال مالی: {backup_result.get('error', 'خطای نامشخص')}. عملیات بستن سال مالی لغو شد.",
            http_status=500
        )
    
    backup_id = backup_result.get("backup_id")
    backup_filename = backup_result.get("filename", "")
    
    # اعتبارسنجی اولیه
    preview_data = preview_year_end_closing(db, business_id, fiscal_year_id)
    
    fy_repo = FiscalYearRepository(db)
    fiscal_year = fy_repo.get_by_id(fiscal_year_id)
    
    if not fiscal_year:
        raise ApiError("FISCAL_YEAR_NOT_FOUND", "سال مالی یافت نشد", http_status=404)
    
    # دریافت حساب‌های لازم
    summary_account = _get_fixed_account_by_code(db, "80301")  # خلاصه سود و زیان
    retained_earnings_account = _get_fixed_account_by_code(db, "30106")  # سود یا زیان انباشته
    
    # بررسی مانده سود یا زیان انباشته قبل از بستن
    retained_earnings_balance_check = _calculate_account_balance(
        db, business_id, retained_earnings_account.id, fiscal_year_id, fiscal_year.end_date
    )
    retained_earnings_current = (
        retained_earnings_balance_check['opening_debit'] - retained_earnings_balance_check['opening_credit']
    ) + (
        retained_earnings_balance_check['period_debit'] - retained_earnings_balance_check['period_credit']
    )
    
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
    
    # بستن حساب‌های درآمد (هم مثبت هم منفی)
    for revenue_item in preview_data['revenue_accounts']:
        balance = Decimal(str(revenue_item['closing_balance']))
        if balance != 0:  # بستن همه حساب‌هایی که مانده دارند
            if balance > 0:
                # مانده مثبت = درآمد، باید بدهکار شود
                lines.append({
                    'account_id': revenue_item['account_id'],
                    'debit': float(balance),
                    'credit': 0.0,
                    'description': f"بستن حساب {revenue_item['account_name']}",
                })
                total_revenue += balance
            else:
                # مانده منفی = هزینه، باید بستانکار شود
                lines.append({
                    'account_id': revenue_item['account_id'],
                    'debit': 0.0,
                    'credit': float(abs(balance)),
                    'description': f"بستن حساب {revenue_item['account_name']} (مانده منفی)",
                })
                total_expense += abs(balance)
    
    # خط بستانکار خلاصه سود و زیان (جمع درآمدها)
    if total_revenue > 0:
        lines.append({
            'account_id': summary_account.id,
            'debit': 0.0,
            'credit': float(total_revenue),
            'description': 'جمع درآمدهای سال',
        })
    
    # بستن حساب‌های هزینه (هم مثبت هم منفی)
    for expense_item in preview_data['expense_accounts']:
        balance = Decimal(str(expense_item['closing_balance']))
        if balance != 0:  # بستن همه حساب‌هایی که مانده دارند
            if balance > 0:
                # مانده مثبت = هزینه، باید بستانکار شود
                lines.append({
                    'account_id': expense_item['account_id'],
                    'debit': 0.0,
                    'credit': float(balance),
                    'description': f"بستن حساب {expense_item['account_name']}",
                })
                total_expense += balance
            else:
                # مانده منفی = درآمد، باید بدهکار شود
                lines.append({
                    'account_id': expense_item['account_id'],
                    'debit': float(abs(balance)),
                    'credit': 0.0,
                    'description': f"بستن حساب {expense_item['account_name']} (مانده منفی)",
                })
                total_revenue += abs(balance)
    
    # خط بدهکار خلاصه سود و زیان (جمع هزینه‌ها)
    if total_expense > 0:
        lines.append({
            'account_id': summary_account.id,
            'debit': float(total_expense),
            'credit': 0.0,
            'description': 'جمع هزینه‌های سال',
        })
    
    # محاسبه سود/زیان خالص قبل از مالیات
    net_profit_loss_before_tax = total_revenue - total_expense
    
    # محاسبه مالیات
    tax_amount_calculated = Decimal(0)
    if net_profit_loss_before_tax > 0:  # فقط در صورت سود مالیات محاسبه می‌شود
        if tax_percentage is not None:
            tax_amount_calculated = Decimal(str(net_profit_loss_before_tax)) * Decimal(str(tax_percentage)) / Decimal(100)
        elif tax_amount is not None:
            tax_amount_calculated = Decimal(str(tax_amount))
    
    # سود/زیان خالص پس از مالیات
    net_profit_loss_after_tax = net_profit_loss_before_tax - tax_amount_calculated
    
    # ثبت مالیات (اگر وجود داشته باشد)
    if tax_amount_calculated > 0:
        tax_account = _get_fixed_account_by_code(db, "50101")  # مالیات بر درآمد
        lines.append({
            'account_id': summary_account.id,
            'debit': float(tax_amount_calculated),
            'credit': 0.0,
            'description': 'مالیات بر درآمد',
        })
        lines.append({
            'account_id': tax_account.id,
            'debit': 0.0,
            'credit': float(tax_amount_calculated),
            'description': 'ثبت مالیات بر درآمد',
        })
    
    # بستن خلاصه سود و زیان
    if net_profit_loss_after_tax > 0:  # سود
        # بستن خلاصه سود و زیان (سود)
        lines.append({
            'account_id': summary_account.id,
            'debit': float(net_profit_loss_after_tax),
            'credit': 0.0,
            'description': 'بستن خلاصه سود و زیان (سود پس از مالیات)',
        })
        # خط مقابل: انتقال سود به سود یا زیان انباشته
        lines.append({
            'account_id': retained_earnings_account.id,
            'debit': 0.0,
            'credit': float(net_profit_loss_after_tax),
            'description': 'انتقال سود به سود یا زیان انباشته',
        })
    elif net_profit_loss_after_tax < 0:  # زیان
        # بستن خلاصه سود و زیان (زیان)
        lines.append({
            'account_id': summary_account.id,
            'debit': 0.0,
            'credit': float(abs(net_profit_loss_after_tax)),
            'description': 'بستن خلاصه سود و زیان (زیان پس از مالیات)',
        })
        # خط مقابل: انتقال زیان به سود یا زیان انباشته
        lines.append({
            'account_id': retained_earnings_account.id,
            'debit': float(abs(net_profit_loss_after_tax)),
            'credit': 0.0,
            'description': 'انتقال زیان به سود یا زیان انباشته',
        })
    
    # محاسبه تقسیم سود
    profit_to_distribute = Decimal(0)
    if net_profit_loss_after_tax > 0:  # فقط در صورت سود تقسیم می‌شود
        if profit_distribution_percentage is not None:
            profit_to_distribute = Decimal(str(net_profit_loss_after_tax)) * Decimal(str(profit_distribution_percentage)) / Decimal(100)
        elif profit_distribution_amount is not None:
            profit_to_distribute = Decimal(str(profit_distribution_amount))
    
    # بررسی محدودیت تقسیم سود
    if profit_to_distribute > net_profit_loss_after_tax:
        profit_to_distribute = net_profit_loss_after_tax
    
    # سود باقی‌مانده برای انباشته
    profit_to_retained = net_profit_loss_after_tax - profit_to_distribute
    if retained_earnings_from_previous_years is not None:
        profit_to_retained += Decimal(str(retained_earnings_from_previous_years))
    
    # بررسی مانده نهایی سود یا زیان انباشته
    final_retained_earnings = retained_earnings_current + profit_to_retained
    
    # هشدار در صورت زیان زیاد (اگر زیان انباشته از سرمایه بیشتر شود)
    capital_account = _get_fixed_account_by_code(db, "30101")  # سرمایه اولیه
    capital_balance = _calculate_account_balance(
        db, business_id, capital_account.id, fiscal_year_id, fiscal_year.end_date
    )
    capital_amount = (
        capital_balance['opening_debit'] - capital_balance['opening_credit']
    ) + (
        capital_balance['period_debit'] - capital_balance['period_credit']
    )
    
    if final_retained_earnings < 0 and abs(final_retained_earnings) > capital_amount:
        # هشدار: زیان انباشته از سرمایه بیشتر شده است
        import logging
        logging.warning(
            f"هشدار: زیان انباشته ({final_retained_earnings}) از سرمایه ({capital_amount}) بیشتر شده است. "
            f"کسب‌وکار {business_id} ممکن است ورشکسته باشد."
        )
    
    # تقسیم سود بین سهامداران (اگر وجود داشته باشد)
    shareholder_profit_account = None
    if profit_to_distribute > 0 and shareholder_profit_account_id:
        shareholder_profit_account = db.query(Account).filter(Account.id == shareholder_profit_account_id).first()
        if not shareholder_profit_account:
            raise ApiError("ACCOUNT_NOT_FOUND", "حساب سود سهامداران یافت نشد", http_status=400)
        
        # دریافت سهامداران
        from adapters.db.models.person import PersonType
        
        # دریافت تمام اشخاص و فیلتر کردن سهامداران با استفاده از JSON parsing
        all_persons = db.query(Person).filter(
            Person.business_id == business_id
        ).all()
        
        shareholders = []
        for person in all_persons:
            try:
                # پارس کردن person_types از JSON
                person_types_list = json.loads(person.person_types) if person.person_types else []
                if isinstance(person_types_list, list) and "سهامدار" in person_types_list:
                    shareholders.append(person)
            except (json.JSONDecodeError, TypeError):
                # اگر JSON معتبر نبود، از contains استفاده می‌کنیم (fallback)
                if person.person_types and "سهامدار" in person.person_types:
                    shareholders.append(person)
        
        # محاسبه سهم هر سهامدار
        total_shares = sum(Decimal(str(sh.share_count or 0)) for sh in shareholders if sh.share_count)
        
        # اگر تقسیم دستی وارد شده، از آن استفاده می‌شود
        if shareholder_distributions:
            total_manual_distribution = sum(Decimal(str(dist.get('profit_amount', 0))) for dist in shareholder_distributions)
            if total_manual_distribution != profit_to_distribute:
                raise ApiError(
                    "INVALID_PROFIT_DISTRIBUTION",
                    f"جمع تقسیم دستی سود ({total_manual_distribution}) باید برابر با سود قابل تقسیم ({profit_to_distribute}) باشد",
                    http_status=400
                )
            
            # استفاده از تقسیم دستی
            for dist in shareholder_distributions:
                person_id = dist.get('person_id')
                profit_amt = Decimal(str(dist.get('profit_amount', 0)))
                if profit_amt > 0:
                    shareholder = next((sh for sh in shareholders if sh.id == person_id), None)
                    if shareholder:
                        # ثبت تقسیم سود طبق اصول حسابداری:
                        # Dr. سود یا زیان انباشته - Cr. سود تقسیم شده (Dividends Payable)
                        # برای هر سهامدار به تفکیک ثبت می‌شود
                        lines.append({
                            'account_id': retained_earnings_account.id,
                            'person_id': person_id,
                            'debit': float(profit_amt),
                            'credit': 0.0,
                            'description': f'تقسیم سود به {shareholder.alias_name}',
                        })
                        lines.append({
                            'account_id': shareholder_profit_account.id,
                            'person_id': person_id,
                            'debit': 0.0,
                            'credit': float(profit_amt),
                            'description': f'سود تقسیم شده - {shareholder.alias_name}',
                        })
        elif total_shares > 0:
            # تقسیم بر اساس درصد سهام
            for shareholder in shareholders:
                if shareholder.share_count and shareholder.share_count > 0:
                    share_ratio = Decimal(str(shareholder.share_count)) / total_shares
                    shareholder_profit = profit_to_distribute * share_ratio
                    if shareholder_profit > 0:
                        # ثبت تقسیم سود طبق اصول حسابداری:
                        # Dr. سود یا زیان انباشته - Cr. سود تقسیم شده (Dividends Payable)
                        # برای هر سهامدار به تفکیک ثبت می‌شود
                        lines.append({
                            'account_id': retained_earnings_account.id,
                            'person_id': shareholder.id,
                            'debit': float(shareholder_profit),
                            'credit': 0.0,
                            'description': f'تقسیم سود به {shareholder.alias_name}',
                        })
                        lines.append({
                            'account_id': shareholder_profit_account.id,
                            'person_id': shareholder.id,
                            'debit': 0.0,
                            'credit': float(shareholder_profit),
                            'description': f'سود تقسیم شده - {shareholder.alias_name}',
                        })
        
        # توجه: ثبت تقسیم سود قبلاً برای هر سهامدار به تفکیک انجام شده است
        # در اینجا نیازی به ثبت اضافی نیست، چون هر سهامدار به صورت جداگانه ثبت شده است
    
    # توجه: انتقال سود/زیان به سود یا زیان انباشته قبلاً در بستن خلاصه سود و زیان انجام شده است
    # تقسیم سود نیز قبلاً انجام شده است (کسر از سود یا زیان انباشته و اضافه به حساب سود تقسیم شده)
    # سود باقی‌مانده (profit_to_retained) قبلاً در سود یا زیان انباشته است و نیازی به ثبت اضافی ندارد
    
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
    
    # ایجاد سند توازن اشخاص (در صورت نیاز)
    person_balance_document = None
    if auto_issue_person_balance_document:
        try:
            person_balance_document = _create_person_balance_document(
                db=db,
                business_id=business_id,
                fiscal_year_id=fiscal_year_id,
                user_id=user_id,
                currency_id=currency_id,
                fiscal_year_end_date=fiscal_year.end_date,
            )
        except Exception as e:
            # در صورت خطا، فقط log می‌کنیم و ادامه می‌دهیم
            import logging
            logging.error(f"خطا در ایجاد سند توازن اشخاص: {str(e)}")
    
    # ایجاد سال مالی جدید
    if new_fiscal_year_start_date and new_fiscal_year_end_date:
        new_start_date = new_fiscal_year_start_date
        new_end_date = new_fiscal_year_end_date
        # بررسی اعتبار تاریخ‌ها
        if new_start_date >= new_end_date:
            raise ApiError("INVALID_DATE_RANGE", "تاریخ شروع باید قبل از تاریخ پایان باشد", http_status=400)
        if new_start_date <= fiscal_year.end_date:
            raise ApiError("INVALID_START_DATE", "تاریخ شروع سال مالی جدید باید بعد از تاریخ پایان سال مالی فعلی باشد", http_status=400)
    else:
        # استفاده از منطق خودکار در صورت عدم ارسال تاریخ
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
    
    # تنظیم روش ارزیابی انبار
    new_fiscal_year.inventory_valuation_method = inventory_valuation_method
    db.commit()
    db.refresh(new_fiscal_year)
    
    result = {
        'closing_document': doc_repo.get_document_details(closing_document.id) or {},
        'new_fiscal_year': {
            'id': new_fiscal_year.id,
            'title': new_fiscal_year.title,
            'start_date': new_fiscal_year.start_date.isoformat(),
            'end_date': new_fiscal_year.end_date.isoformat(),
            'inventory_valuation_method': new_fiscal_year.inventory_valuation_method,
        },
        'backup_info': {
            'backup_id': backup_id,
            'filename': backup_filename,
        },
        'tax_info': {
            'tax_amount': float(tax_amount_calculated),
        },
        'profit_distribution_info': {
            'distributed_amount': float(profit_to_distribute),
            'retained_amount': float(profit_to_retained),
        },
    }
    
    if person_balance_document:
        result['person_balance_document'] = doc_repo.get_document_details(person_balance_document.id) or {}
    
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


def _create_person_balance_document(
    db: Session,
    business_id: int,
    fiscal_year_id: int,
    user_id: int,
    currency_id: int,
    fiscal_year_end_date: date,
) -> Document:
    """
    ایجاد سند توازن اشخاص در پایان سال مالی
    
    این تابع مانده تمام اشخاص را محاسبه کرده و یک سند برای بستن آن‌ها ایجاد می‌کند.
    """
    doc_repo = DocumentRepository(db)
    
    # دریافت تمام اشخاص
    persons = db.query(Person).filter(Person.business_id == business_id).all()
    
    person_lines: List[Dict[str, Any]] = []
    
    for person in persons:
        # محاسبه مانده شخص تا پایان سال مالی
        person_balance_query = db.query(
            func.coalesce(func.sum(DocumentLine.debit), 0).label('total_debit'),
            func.coalesce(func.sum(DocumentLine.credit), 0).label('total_credit')
        ).join(
            Document, DocumentLine.document_id == Document.id
        ).filter(
            and_(
                Document.business_id == business_id,
                Document.fiscal_year_id == fiscal_year_id,
                DocumentLine.person_id == person.id,
                Document.document_date <= fiscal_year_end_date,
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
        
        # حساب کنترل اشخاص (مدل Person فیلد account_id ندارد؛ از حساب‌های ثابت نمودار استفاده می‌شود)
        if person_balance > 0:
            person_account = _get_fixed_account_by_code(db, "13101")
        else:
            person_account = _get_fixed_account_by_code(db, "21101")
        person_account_id = person_account.id

        # اضافه کردن به خطوط سند
        if person_balance > 0:
            person_lines.append({
                'account_id': person_account_id,
                'person_id': person.id,
                'debit': 0.0,
                'credit': float(person_balance),
                'description': f'بستن مانده {person.alias_name} (بدهکار)',
            })
        else:
            person_lines.append({
                'account_id': person_account_id,
                'person_id': person.id,
                'debit': float(-person_balance),
                'credit': 0.0,
                'description': f'بستن مانده {person.alias_name} (بستانکار)',
            })
    
    # اگر هیچ مانده‌ای وجود ندارد، سند ایجاد نمی‌کنیم (به صورت graceful)
    if not person_lines:
        return None  # به جای خطا، None برمی‌گردانیم
    
    # ایجاد سند توازن اشخاص
    person_balance_doc_code = doc_repo.generate_document_code(business_id, "person_balance")
    
    person_balance_doc_payload = {
        'code': person_balance_doc_code,
        'business_id': business_id,
        'fiscal_year_id': fiscal_year_id,
        'currency_id': currency_id,
        'created_by_user_id': user_id,
        'document_date': fiscal_year_end_date,
        'document_type': 'person_balance',
        'is_proforma': False,
        'description': 'بستن مانده اشخاص پایان سال مالی',
        'lines': person_lines,
    }
    
    person_balance_document = doc_repo.create_document(person_balance_doc_payload)
    
    return person_balance_document


def _calculate_remaining_inventory_cost(
    db: Session,
    business_id: int,
    product_id: int,
    warehouse_id: int,
    up_to_date: date,
    valuation_method: str,
) -> Tuple[Decimal, Decimal]:
    """
    محاسبه قیمت تمام شده موجودی باقی‌مانده بر اساس روش ارزیابی انبار
    
    Args:
        db: Session دیتابیس
        business_id: شناسه کسب‌وکار
        product_id: شناسه کالا
        warehouse_id: شناسه انبار
        up_to_date: تاریخ تا
        valuation_method: روش ارزیابی انبار (FIFO, LIFO, WeightedAverage)
    
    Returns:
        Tuple[quantity, cost_price]: مقدار موجودی و قیمت تمام شده
    """
    # دریافت حرکات موجودی
    movements = _iter_product_movements(
        db=db,
        business_id=business_id,
        product_ids=[product_id],
        warehouse_ids=[warehouse_id],
        up_to_date=up_to_date,
        exclude_document_id=None,
    )
    
    # فیلتر حرکات برای این انبار
    filtered_movements = [
        mv for mv in movements
        if mv.get("warehouse_id") is not None and int(mv.get("warehouse_id")) == int(warehouse_id)
    ]
    
    if not filtered_movements:
        return Decimal(0), Decimal(0)
    
    # محاسبه موجودی باقی‌مانده
    remaining_quantity = _compute_available_stock(
        db=db,
        business_id=business_id,
        product_id=product_id,
        warehouse_id=warehouse_id,
        up_to_date=up_to_date,
    )
    
    if remaining_quantity <= 0:
        return Decimal(0), Decimal(0)
    
    # محاسبه قیمت تمام شده بر اساس روش ارزیابی
    if valuation_method.upper() == "FIFO":
        # FIFO: قیمت آخرین ورودی‌ها
        return _calculate_fifo_cost(filtered_movements, remaining_quantity)
    elif valuation_method.upper() == "LIFO":
        # LIFO: قیمت اولین ورودی‌ها
        return _calculate_lifo_cost(filtered_movements, remaining_quantity)
    elif valuation_method.upper() == "WEIGHTEDAVERAGE":
        # WeightedAverage: میانگین موزون
        return _calculate_weighted_average_cost(filtered_movements, remaining_quantity)
    else:
        # پیش‌فرض: WeightedAverage
        return _calculate_weighted_average_cost(filtered_movements, remaining_quantity)


def _calculate_fifo_cost(movements: List[Dict[str, Any]], remaining_quantity: Decimal) -> Tuple[Decimal, Decimal]:
    """محاسبه قیمت تمام شده بر اساس FIFO"""
    # ساخت لایه‌های FIFO
    layers = deque()
    for mv in movements:
        if mv["movement"] == "in":
            cost_price = mv.get("cost_price") or Decimal(0)
            if cost_price > 0:
                layers.append({
                    "qty": mv["quantity"],
                    "cost": cost_price,
                })
        elif mv["movement"] == "out":
            remain = mv["quantity"]
            while remain > 0 and layers:
                top = layers[0]
                take = min(remain, top["qty"])
                top["qty"] -= take
                remain -= take
                if top["qty"] <= 0:
                    layers.popleft()
    
    # محاسبه قیمت برای موجودی باقی‌مانده
    if not layers:
        return remaining_quantity, Decimal(0)
    
    total_cost = Decimal(0)
    remain = remaining_quantity
    for layer in layers:
        if remain <= 0:
            break
        take = min(remain, layer["qty"])
        total_cost += take * layer["cost"]
        remain -= take
    
    if remaining_quantity > 0:
        avg_cost = total_cost / remaining_quantity
    else:
        avg_cost = Decimal(0)
    
    return remaining_quantity, avg_cost


def _calculate_lifo_cost(movements: List[Dict[str, Any]], remaining_quantity: Decimal) -> Tuple[Decimal, Decimal]:
    """محاسبه قیمت تمام شده بر اساس LIFO"""
    # ساخت لایه‌های LIFO (معکوس FIFO)
    layers = deque()
    for mv in movements:
        if mv["movement"] == "in":
            cost_price = mv.get("cost_price") or Decimal(0)
            if cost_price > 0:
                layers.append({
                    "qty": mv["quantity"],
                    "cost": cost_price,
                })
        elif mv["movement"] == "out":
            remain = mv["quantity"]
            while remain > 0 and layers:
                top = layers[-1]  # از آخرین لایه
                take = min(remain, top["qty"])
                top["qty"] -= take
                remain -= take
                if top["qty"] <= 0:
                    layers.pop()
    
    # محاسبه قیمت برای موجودی باقی‌مانده (از اولین لایه‌ها)
    if not layers:
        return remaining_quantity, Decimal(0)
    
    total_cost = Decimal(0)
    remain = remaining_quantity
    # از اولین لایه‌ها شروع می‌کنیم (قدیمی‌ترین)
    for layer in layers:
        if remain <= 0:
            break
        take = min(remain, layer["qty"])
        total_cost += take * layer["cost"]
        remain -= take
    
    if remaining_quantity > 0:
        avg_cost = total_cost / remaining_quantity
    else:
        avg_cost = Decimal(0)
    
    return remaining_quantity, avg_cost


def _calculate_weighted_average_cost(movements: List[Dict[str, Any]], remaining_quantity: Decimal) -> Tuple[Decimal, Decimal]:
    """محاسبه قیمت تمام شده بر اساس میانگین موزون"""
    total_cost = Decimal(0)
    total_quantity = Decimal(0)
    
    # محاسبه میانگین موزون از تمام ورودی‌هایی که cost_price دارند
    for mv in movements:
        if mv["movement"] == "in":
            cost_price = mv.get("cost_price")
            if cost_price is not None and cost_price > 0:
                qty = mv["quantity"]
                total_cost += qty * Decimal(str(cost_price))
                total_quantity += qty
    
    if total_quantity > 0:
        avg_cost = total_cost / total_quantity
    else:
        avg_cost = Decimal(0)
    
    return remaining_quantity, avg_cost


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
        
        # حساب کنترل اشخاص (مدل Person فیلد account_id ندارد؛ از حساب‌های ثابت نمودار استفاده می‌شود)
        if person_balance > 0:
            person_account = _get_fixed_account_by_code(db, "13101")
        else:
            person_account = _get_fixed_account_by_code(db, "21101")
        person_account_id = person_account.id

        # اضافه کردن به خطوط سند
        if person_balance > 0:
            account_lines.append({
                'account_id': person_account_id,
                'person_id': person.id,
                'debit': float(person_balance),
                'credit': 0.0,
                'description': f'مانده ابتدای دوره - {person.alias_name}',
            })
        else:
            account_lines.append({
                'account_id': person_account_id,
                'person_id': person.id,
                'debit': 0.0,
                'credit': float(-person_balance),
                'description': f'مانده ابتدای دوره - {person.alias_name}',
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
    
    # دریافت روش ارزیابی انبار سال مالی قبلی
    valuation_method = old_fiscal_year.inventory_valuation_method or "FIFO"
    
    for product in products:
        for warehouse in warehouses:
            # محاسبه موجودی و قیمت تمام شده بر اساس روش ارزیابی انبار
            stock, cost_price = _calculate_remaining_inventory_cost(
                db=db,
                business_id=business_id,
                product_id=product.id,
                warehouse_id=warehouse.id,
                up_to_date=date_to,
                valuation_method=valuation_method,
            )
            
            if stock <= 0:
                continue
            
            # اگر قیمت تمام شده صفر است، از قیمت خرید محصول استفاده می‌کنیم (fallback)
            if cost_price <= 0:
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

