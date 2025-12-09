from __future__ import annotations

from typing import Any, Dict, List, Optional
from datetime import datetime, date, timedelta
from decimal import Decimal
from sqlalchemy.orm import Session
from sqlalchemy import and_, or_, func

from adapters.db.models.cash_register import CashRegister
from adapters.db.models.petty_cash import PettyCash
from adapters.db.models.document import Document
from adapters.db.models.document_line import DocumentLine
from adapters.db.repositories.cash_register_repository import CashRegisterRepository
from app.core.responses import ApiError


def create_cash_register(db: Session, business_id: int, data: Dict[str, Any]) -> Dict[str, Any]:
	# validate required fields
	name = (data.get("name") or "").strip()
	if name == "":
		raise ApiError("STRING_TOO_SHORT", "Name is required", http_status=400)

	# code uniqueness in business if provided; else auto-generate numeric min 3 digits
	code = data.get("code")
	if code is not None and str(code).strip() != "":
		if not str(code).isdigit():
			raise ApiError("INVALID_CASH_CODE", "Cash register code must be numeric", http_status=400)
		if len(str(code)) < 3:
			raise ApiError("INVALID_CASH_CODE", "Cash register code must be at least 3 digits", http_status=400)
		exists = db.query(CashRegister).filter(and_(CashRegister.business_id == business_id, CashRegister.code == str(code))).first()
		if exists:
			raise ApiError("DUPLICATE_CASH_CODE", "Duplicate cash register code", http_status=400)
	else:
		max_code = db.query(func.max(CashRegister.code)).filter(CashRegister.business_id == business_id).scalar()
		try:
			if max_code is not None and str(max_code).isdigit():
				next_code_int = int(max_code) + 1
			else:
				next_code_int = 100
			if next_code_int < 100:
				next_code_int = 100
			code = str(next_code_int)
		except Exception:
			code = "100"

	repo = CashRegisterRepository(db)
	obj = repo.create(business_id, {
		"name": name,
		"code": code,
		"description": data.get("description"),
		"currency_id": int(data["currency_id"]),
		"is_active": bool(data.get("is_active", True)),
		"is_default": bool(data.get("is_default", False)),
		"payment_switch_number": data.get("payment_switch_number"),
		"payment_terminal_number": data.get("payment_terminal_number"),
		"merchant_id": data.get("merchant_id"),
	})

	# ensure single default
	if obj.is_default:
		repo.clear_default(business_id, except_id=obj.id)

	db.commit()
	db.refresh(obj)
	return cash_register_to_dict(obj)


def get_cash_register_by_id(db: Session, id_: int) -> Optional[Dict[str, Any]]:
	obj = db.query(CashRegister).filter(CashRegister.id == id_).first()
	return cash_register_to_dict(obj) if obj else None


def update_cash_register(db: Session, id_: int, data: Dict[str, Any]) -> Optional[Dict[str, Any]]:
	repo = CashRegisterRepository(db)
	obj = repo.get_by_id(id_)
	if obj is None:
		return None

	# validate name if provided
	if "name" in data:
		name_val = (data.get("name") or "").strip()
		if name_val == "":
			raise ApiError("STRING_TOO_SHORT", "Name is required", http_status=400)

	if "code" in data and data["code"] is not None and str(data["code"]).strip() != "":
		if not str(data["code"]).isdigit():
			raise ApiError("INVALID_CASH_CODE", "Cash register code must be numeric", http_status=400)
		if len(str(data["code"])) < 3:
			raise ApiError("INVALID_CASH_CODE", "Cash register code must be at least 3 digits", http_status=400)
		exists = db.query(CashRegister).filter(and_(CashRegister.business_id == obj.business_id, CashRegister.code == str(data["code"]), CashRegister.id != obj.id)).first()
		if exists:
			raise ApiError("DUPLICATE_CASH_CODE", "Duplicate cash register code", http_status=400)

	repo.update(obj, data)
	if obj.is_default:
		repo.clear_default(obj.business_id, except_id=obj.id)

	db.commit()
	db.refresh(obj)
	return cash_register_to_dict(obj)


def check_cash_register_has_accounting_documents(db: Session, cash_register_id: int) -> tuple[bool, list[str]]:
	"""
	بررسی وجود اسناد حسابداری مرتبط با صندوق
	
	Returns:
		tuple: (has_documents, document_types)
		- has_documents: True اگر سند مرتبطی وجود داشته باشد
		- document_types: لیست انواع اسناد مرتبط
	"""
	from sqlalchemy import func
	
	# بررسی وجود خطوط سند با cash_register_id در اسناد قطعی (غیر پیش‌نویس)
	document_lines_count = db.query(func.count(DocumentLine.id)).join(
		Document, DocumentLine.document_id == Document.id
	).filter(
		DocumentLine.cash_register_id == cash_register_id,
		Document.is_proforma == False
	).scalar()
	
	if document_lines_count and document_lines_count > 0:
		# دریافت انواع اسناد مرتبط
		document_types = db.query(Document.document_type).join(
			DocumentLine, Document.id == DocumentLine.document_id
		).filter(
			DocumentLine.cash_register_id == cash_register_id,
			Document.is_proforma == False
		).distinct().all()
		
		types_list = [doc_type[0] for doc_type in document_types if doc_type[0]]
		
		# تبدیل انواع اسناد به نام‌های فارسی
		type_names = []
		type_mapping = {
			"invoice_sales": "فاکتور فروش",
			"invoice_sales_return": "برگشت از فروش",
			"invoice_purchase": "فاکتور خرید",
			"invoice_purchase_return": "برگشت از خرید",
			"invoice_direct_consumption": "مصرف مستقیم",
			"invoice_production": "تولید",
			"invoice_waste": "ضایعات",
			"receipt": "دریافت",
			"payment": "پرداخت",
			"expense": "هزینه",
			"income": "درآمد",
			"transfer": "انتقال",
			"manual": "سند دستی",
			"check": "چک",
		}
		
		for doc_type in types_list:
			type_name = type_mapping.get(doc_type, doc_type)
			if type_name not in type_names:
				type_names.append(type_name)
		
		return True, type_names
	
	return False, []


def delete_cash_register(db: Session, id_: int) -> tuple[bool, str | None]:
	"""
	حذف صندوق
	
	Returns:
		tuple: (success, error_message)
		- success: True اگر حذف موفق باشد
		- error_message: پیام خطا در صورت عدم موفقیت
	"""
	obj = db.query(CashRegister).filter(CashRegister.id == id_).first()
	if obj is None:
		return False, "صندوق یافت نشد"
	
	# بررسی وجود اسناد حسابداری مرتبط
	has_documents, document_types = check_cash_register_has_accounting_documents(db, id_)
	
	if has_documents:
		types_str = "، ".join(document_types)
		error_msg = f"امکان حذف این صندوق وجود ندارد زیرا دارای اسناد حسابداری مرتبط است. انواع اسناد: {types_str}"
		return False, error_msg
	
	try:
		db.delete(obj)
		db.commit()
		return True, None
	except Exception as e:
		db.rollback()
		return False, f"خطا در حذف صندوق: {str(e)}"


def bulk_delete_cash_registers(db: Session, business_id: int, ids: List[int]) -> Dict[str, Any]:
	"""
	حذف گروهی صندوق‌ها
	"""
	if not ids:
		return {"deleted": 0, "skipped": 0, "errors": []}
	
	# بررسی وجود صندوق‌ها و دسترسی به کسب‌وکار
	cash_registers = db.query(CashRegister).filter(
		CashRegister.id.in_(ids),
		CashRegister.business_id == business_id
	).all()
	
	deleted_count = 0
	skipped_count = 0
	errors = []
	
	for cash_register in cash_registers:
		try:
			success, error_message = delete_cash_register(db, cash_register.id)
			if success:
				deleted_count += 1
			else:
				skipped_count += 1
				if error_message:
					errors.append(f"صندوق {cash_register.name or cash_register.code or cash_register.id}: {error_message}")
				else:
					errors.append(f"صندوق {cash_register.name or cash_register.code or cash_register.id}: امکان حذف وجود ندارد")
		except Exception as e:
			skipped_count += 1
			errors.append(f"خطا در حذف صندوق {cash_register.name or cash_register.code or cash_register.id}: {str(e)}")
	
	return {
		"deleted": deleted_count,
		"skipped": skipped_count,
		"total_requested": len(ids),
		"errors": errors
	}


def list_cash_registers(db: Session, business_id: int, query: Dict[str, Any]) -> Dict[str, Any]:
	repo = CashRegisterRepository(db)
	res = repo.list(business_id, query)
	return {
		"items": [cash_register_to_dict(i) for i in res["items"]],
		"pagination": res["pagination"],
		"query_info": res["query_info"],
	}


def cash_register_to_dict(obj: CashRegister) -> Dict[str, Any]:
	return {
		"id": obj.id,
		"business_id": obj.business_id,
		"name": obj.name,
		"code": obj.code,
		"description": obj.description,
		"currency_id": obj.currency_id,
		"is_active": bool(obj.is_active),
		"is_default": bool(obj.is_default),
		"payment_switch_number": obj.payment_switch_number,
		"payment_terminal_number": obj.payment_terminal_number,
		"merchant_id": obj.merchant_id,
		"created_at": obj.created_at.isoformat(),
		"updated_at": obj.updated_at.isoformat(),
	}


def get_cash_petty_turnover_report(
    db: Session,
    business_id: int,
    fiscal_year_id: Optional[int] = None,
    currency_id: Optional[int] = None,
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
    cash_register_ids: Optional[List[int]] = None,
    petty_cash_ids: Optional[List[int]] = None,
    search: Optional[str] = None,
    skip: int = 0,
    take: int = 50,
) -> Dict[str, Any]:
    """
    گزارش گردش صندوق و تنخواه
    
    نمایش برداشت‌ها و واریزهای هر صندوق و تنخواه در یک بازه زمانی با محاسبه مانده تجمعی
    
    Args:
        db: نشست پایگاه داده
        business_id: شناسه کسب‌وکار
        fiscal_year_id: شناسه سال مالی (اختیاری)
        currency_id: شناسه ارز (اختیاری)
        date_from: از تاریخ (اختیاری، فرمت YYYY-MM-DD)
        date_to: تا تاریخ (اختیاری، فرمت YYYY-MM-DD)
        cash_register_ids: لیست شناسه‌های صندوق‌ها (اختیاری)
        petty_cash_ids: لیست شناسه‌های تنخواه‌ها (اختیاری)
        search: جستجو در کد سند یا نام صندوق/تنخواه (اختیاری)
        skip: تعداد رکوردهای رد شده برای pagination
        take: تعداد رکوردهای برگشتی
    
    Returns:
        dict: {
            'items': لیست تراکنش‌ها,
            'summary': خلاصه آمار,
            'pagination': اطلاعات pagination
        }
    """
    # Query پایه: DocumentLine join Document و CashRegister/PettyCash
    # استفاده از union برای ترکیب صندوق‌ها و تنخواه‌ها
    query_cash = db.query(
        DocumentLine,
        Document,
        CashRegister,
        None  # برای PettyCash
    ).join(
        Document, DocumentLine.document_id == Document.id
    ).outerjoin(
        CashRegister, DocumentLine.cash_register_id == CashRegister.id
    ).filter(
        Document.business_id == business_id,
        Document.is_proforma == False,
        DocumentLine.cash_register_id.isnot(None)
    )
    
    query_petty = db.query(
        DocumentLine,
        Document,
        None,  # برای CashRegister
        PettyCash
    ).join(
        Document, DocumentLine.document_id == Document.id
    ).outerjoin(
        PettyCash, DocumentLine.petty_cash_id == PettyCash.id
    ).filter(
        Document.business_id == business_id,
        Document.is_proforma == False,
        DocumentLine.petty_cash_id.isnot(None)
    )
    
    # فیلتر سال مالی
    if fiscal_year_id:
        query_cash = query_cash.filter(Document.fiscal_year_id == fiscal_year_id)
        query_petty = query_petty.filter(Document.fiscal_year_id == fiscal_year_id)
    
    # فیلتر ارز
    if currency_id:
        query_cash = query_cash.filter(Document.currency_id == currency_id)
        query_petty = query_petty.filter(Document.currency_id == currency_id)
    
    # فیلتر تاریخ
    if date_from:
        try:
            date_from_obj = datetime.strptime(date_from, '%Y-%m-%d').date()
            query_cash = query_cash.filter(Document.document_date >= date_from_obj)
            query_petty = query_petty.filter(Document.document_date >= date_from_obj)
        except ValueError:
            pass
    
    if date_to:
        try:
            date_to_obj = datetime.strptime(date_to, '%Y-%m-%d').date()
            query_cash = query_cash.filter(Document.document_date <= date_to_obj)
            query_petty = query_petty.filter(Document.document_date <= date_to_obj)
        except ValueError:
            pass
    
    # فیلتر صندوق‌ها
    if cash_register_ids:
        query_cash = query_cash.filter(DocumentLine.cash_register_id.in_(cash_register_ids))
    
    # فیلتر تنخواه‌ها
    if petty_cash_ids:
        query_petty = query_petty.filter(DocumentLine.petty_cash_id.in_(petty_cash_ids))
    
    # فیلتر جستجو
    if search and search.strip():
        search_filter = or_(
            Document.code.ilike(f'%{search}%'),
            CashRegister.code.ilike(f'%{search}%'),
            CashRegister.name.ilike(f'%{search}%'),
            PettyCash.code.ilike(f'%{search}%'),
            PettyCash.name.ilike(f'%{search}%'),
        )
        query_cash = query_cash.filter(
            or_(
                Document.code.ilike(f'%{search}%'),
                CashRegister.code.ilike(f'%{search}%'),
                CashRegister.name.ilike(f'%{search}%'),
            )
        )
        query_petty = query_petty.filter(
            or_(
                Document.code.ilike(f'%{search}%'),
                PettyCash.code.ilike(f'%{search}%'),
                PettyCash.name.ilike(f'%{search}%'),
            )
        )
    
    # مرتب‌سازی: تاریخ سند، شناسه سند، شناسه خط
    query_cash = query_cash.order_by(
        Document.document_date.asc(),
        Document.id.asc(),
        DocumentLine.id.asc()
    )
    query_petty = query_petty.order_by(
        Document.document_date.asc(),
        Document.id.asc(),
        DocumentLine.id.asc()
    )
    
    # دریافت همه نتایج
    all_results_cash = query_cash.all()
    all_results_petty = query_petty.all()
    
    # ترکیب نتایج
    all_results = []
    for line, doc, cash, _ in all_results_cash:
        all_results.append((line, doc, cash, None))
    for line, doc, _, petty in all_results_petty:
        all_results.append((line, doc, None, petty))
    
    # مرتب‌سازی ترکیبی بر اساس تاریخ
    all_results.sort(key=lambda x: (x[1].document_date, x[1].id, x[0].id))
    
    if not all_results:
        return {
            'items': [],
            'summary': {
                'total_count': 0,
                'total_deposit': 0.0,
                'total_withdrawal': 0.0,
            },
            'pagination': {
                'total': 0,
                'page': 1,
                'per_page': take,
                'total_pages': 0,
                'has_next': False,
                'has_prev': False,
            }
        }
    
    # تابع برای تبدیل document_type به نام فارسی
    def _get_document_type_name(doc_type: str | None) -> str:
        if not doc_type:
            return ""
        doc_type = doc_type.strip()
        mapping = {
            "invoice_sales": "فروش",
            "invoice_sales_return": "برگشت از فروش",
            "invoice_purchase": "خرید",
            "invoice_purchase_return": "برگشت از خرید",
            "invoice_direct_consumption": "مصرف مستقیم",
            "invoice_production": "تولید",
            "invoice_waste": "ضایعات",
            "inventory_transfer": "انتقال موجودی",
            "production": "تولید",
            "opening_balance": "موجودی اولیه",
            "expense": "هزینه",
            "income": "درآمد",
            "receipt": "دریافت",
            "payment": "پرداخت",
            "transfer": "انتقال",
            "manual": "سند دستی",
            "invoice": "فاکتور",
            "check": "چک",
        }
        return mapping.get(doc_type, doc_type)
    
    # محاسبه running balance برای هر صندوق/تنخواه
    items = []
    balance_by_cash = {}  # {cash_register_id: Decimal}
    balance_by_petty = {}  # {petty_cash_id: Decimal}
    
    # محاسبه مانده ابتدای دوره
    if date_from:
        try:
            date_from_obj = datetime.strptime(date_from, '%Y-%m-%d').date()
            date_before_from = date_from_obj - timedelta(days=1)
            
            # برای صندوق‌ها
            unique_cash_ids = list(set(
                line.cash_register_id for line, doc, cash, petty in all_results 
                if line.cash_register_id is not None
            ))
            
            for cash_id in unique_cash_ids:
                opening_query = db.query(
                    func.coalesce(func.sum(DocumentLine.debit), 0).label('total_deposit'),
                    func.coalesce(func.sum(DocumentLine.credit), 0).label('total_withdrawal')
                ).join(
                    Document, DocumentLine.document_id == Document.id
                ).filter(
                    Document.business_id == business_id,
                    Document.is_proforma == False,
                    DocumentLine.cash_register_id == cash_id,
                    Document.document_date <= date_before_from
                )
                
                if fiscal_year_id:
                    opening_query = opening_query.filter(Document.fiscal_year_id == fiscal_year_id)
                if currency_id:
                    opening_query = opening_query.filter(Document.currency_id == currency_id)
                
                opening_result = opening_query.first()
                if opening_result:
                    total_deposit = Decimal(str(opening_result.total_deposit or 0))
                    total_withdrawal = Decimal(str(opening_result.total_withdrawal or 0))
                    balance_by_cash[cash_id] = total_deposit - total_withdrawal
                else:
                    balance_by_cash[cash_id] = Decimal(0)
            
            # برای تنخواه‌ها
            unique_petty_ids = list(set(
                line.petty_cash_id for line, doc, cash, petty in all_results 
                if line.petty_cash_id is not None
            ))
            
            for petty_id in unique_petty_ids:
                opening_query = db.query(
                    func.coalesce(func.sum(DocumentLine.debit), 0).label('total_deposit'),
                    func.coalesce(func.sum(DocumentLine.credit), 0).label('total_withdrawal')
                ).join(
                    Document, DocumentLine.document_id == Document.id
                ).filter(
                    Document.business_id == business_id,
                    Document.is_proforma == False,
                    DocumentLine.petty_cash_id == petty_id,
                    Document.document_date <= date_before_from
                )
                
                if fiscal_year_id:
                    opening_query = opening_query.filter(Document.fiscal_year_id == fiscal_year_id)
                if currency_id:
                    opening_query = opening_query.filter(Document.currency_id == currency_id)
                
                opening_result = opening_query.first()
                if opening_result:
                    total_deposit = Decimal(str(opening_result.total_deposit or 0))
                    total_withdrawal = Decimal(str(opening_result.total_withdrawal or 0))
                    balance_by_petty[petty_id] = total_deposit - total_withdrawal
                else:
                    balance_by_petty[petty_id] = Decimal(0)
        except Exception:
            pass
    
    total_deposit = Decimal(0)
    total_withdrawal = Decimal(0)
    
    for line, doc, cash, petty in all_results:
        deposit = Decimal(str(line.debit or 0))
        withdrawal = Decimal(str(line.credit or 0))
        
        # تعیین نوع (صندوق یا تنخواه)
        source_type = None
        source_id = None
        source_code = ''
        source_name = ''
        
        if cash and line.cash_register_id:
            source_type = 'cash_register'
            source_id = line.cash_register_id
            source_code = cash.code or ''
            source_name = cash.name or ''
            
            if source_id not in balance_by_cash:
                balance_by_cash[source_id] = Decimal(0)
            balance_by_cash[source_id] += deposit - withdrawal
            current_balance = balance_by_cash[source_id]
        elif petty and line.petty_cash_id:
            source_type = 'petty_cash'
            source_id = line.petty_cash_id
            source_code = petty.code or ''
            source_name = petty.name or ''
            
            if source_id not in balance_by_petty:
                balance_by_petty[source_id] = Decimal(0)
            balance_by_petty[source_id] += deposit - withdrawal
            current_balance = balance_by_petty[source_id]
        else:
            continue  # Skip if neither cash nor petty
        
        total_deposit += deposit
        total_withdrawal += withdrawal
        
        document_type_name = _get_document_type_name(doc.document_type)
        
        items.append({
            'source_type': source_type,
            'source_id': source_id,
            'source_code': source_code,
            'source_name': source_name,
            'document_date': doc.document_date.isoformat(),
            'document_type': doc.document_type,
            'document_type_name': document_type_name,
            'document_code': doc.code or '',
            'document_id': doc.id,
            'deposit': float(deposit),
            'withdrawal': float(withdrawal),
            'balance': float(current_balance),
            'description': line.description or doc.description or '',
        })
    
    # اعمال pagination
    total = len(items)
    paginated_items = items[skip:skip + take]
    
    total_pages = (total + take - 1) // take if take > 0 else 0
    current_page = (skip // take) + 1 if take > 0 else 1
    
    # محاسبه موجودی فعلی (مجموع مانده آخرین تراکنش هر صندوق/تنخواه)
    current_balance_by_source = {}
    
    for item in items:
        source_type = item.get('source_type')
        source_id = item.get('source_id')
        balance = item.get('balance')
        if source_type and source_id is not None and balance is not None:
            key = f"{source_type}_{source_id}"
            try:
                current_balance_by_source[key] = float(balance)
            except (ValueError, TypeError):
                pass
    
    total_current_balance = sum(current_balance_by_source.values())
    
    return {
        'items': paginated_items,
        'summary': {
            'total_count': total,
            'total_deposit': float(total_deposit),
            'total_withdrawal': float(total_withdrawal),
            'current_balance': float(total_current_balance),
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


