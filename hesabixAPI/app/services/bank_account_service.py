from __future__ import annotations

from typing import Any, Dict, List, Optional
from datetime import datetime, date, timedelta
from decimal import Decimal
from sqlalchemy.orm import Session
from sqlalchemy import and_, or_, func

from adapters.db.models.bank_account import BankAccount
from adapters.db.models.document import Document
from adapters.db.models.document_line import DocumentLine
from app.core.responses import ApiError


def create_bank_account(
	db: Session,
	business_id: int,
	data: Dict[str, Any],
) -> Dict[str, Any]:
	# مدیریت کد یکتا در هر کسب‌وکار (در صورت ارسال)
	code = data.get("code")
	if code is not None and str(code).strip() != "":
		# اعتبارسنجی عددی بودن کد
		if not str(code).isdigit():
			raise ApiError("INVALID_BANK_ACCOUNT_CODE", "Bank account code must be numeric", http_status=400)
		# اعتبارسنجی حداقل طول کد
		if len(str(code)) < 3:
			raise ApiError("INVALID_BANK_ACCOUNT_CODE", "Bank account code must be at least 3 digits", http_status=400)
		exists = db.query(BankAccount).filter(and_(BankAccount.business_id == business_id, BankAccount.code == str(code))).first()
		if exists:
			raise ApiError("DUPLICATE_BANK_ACCOUNT_CODE", "Duplicate bank account code", http_status=400)
	else:
		# تولید خودکار کد: max + 1 به صورت رشته (حداقل ۳ رقم)
		max_code = db.query(func.max(BankAccount.code)).filter(BankAccount.business_id == business_id).scalar()
		try:
			if max_code is not None and str(max_code).isdigit():
				next_code_int = int(max_code) + 1
			else:
				next_code_int = 100  # شروع از ۱۰۰ برای حداقل ۳ رقم
			
			# اگر کد کمتر از ۳ رقم است، آن را به ۳ رقم تبدیل کن
			if next_code_int < 100:
				next_code_int = 100
			
			code = str(next_code_int)
		except Exception:
			code = "100"  # در صورت خطا، حداقل کد ۳ رقمی

	obj = BankAccount(
		business_id=business_id,
		code=code,
		name=data.get("name"),
		branch=data.get("branch"),
		account_number=data.get("account_number"),
		sheba_number=data.get("sheba_number"),
		card_number=data.get("card_number"),
		owner_name=data.get("owner_name"),
		pos_number=data.get("pos_number"),
		payment_id=data.get("payment_id"),
		description=data.get("description"),
		currency_id=int(data.get("currency_id")),
		is_active=bool(data.get("is_active", True)),
		is_default=bool(data.get("is_default", False)),
	)

	# اگر پیش فرض شد، بقیه را غیر پیش فرض کن
	if obj.is_default:
		db.query(BankAccount).filter(BankAccount.business_id == business_id, BankAccount.id != obj.id).update({BankAccount.is_default: False})

	db.add(obj)
	db.commit()
	db.refresh(obj)
	return bank_account_to_dict(obj)


def get_bank_account_by_id(db: Session, account_id: int) -> Optional[Dict[str, Any]]:
	obj = db.query(BankAccount).filter(BankAccount.id == account_id).first()
	return bank_account_to_dict(obj) if obj else None


def update_bank_account(db: Session, account_id: int, data: Dict[str, Any]) -> Optional[Dict[str, Any]]:
	obj = db.query(BankAccount).filter(BankAccount.id == account_id).first()
	if obj is None:
		return None

	if "code" in data and data["code"] is not None and str(data["code"]).strip() != "":
		if not str(data["code"]).isdigit():
			raise ApiError("INVALID_BANK_ACCOUNT_CODE", "Bank account code must be numeric", http_status=400)
		if len(str(data["code"])) < 3:
			raise ApiError("INVALID_BANK_ACCOUNT_CODE", "Bank account code must be at least 3 digits", http_status=400)
		exists = db.query(BankAccount).filter(and_(BankAccount.business_id == obj.business_id, BankAccount.code == str(data["code"]), BankAccount.id != obj.id)).first()
		if exists:
			raise ApiError("DUPLICATE_BANK_ACCOUNT_CODE", "Duplicate bank account code", http_status=400)
		obj.code = str(data["code"])

	for field in [
		"name","branch","account_number","sheba_number","card_number",
		"owner_name","pos_number","payment_id","description",
	]:
		if field in data:
			setattr(obj, field, data.get(field))

	if "currency_id" in data and data["currency_id"] is not None:
		obj.currency_id = int(data["currency_id"])  # TODO: اعتبارسنجی وجود ارز

	if "is_active" in data and data["is_active"] is not None:
		obj.is_active = bool(data["is_active"])
	if "is_default" in data and data["is_default"] is not None:
		obj.is_default = bool(data["is_default"])
		if obj.is_default:
			# تنها یک حساب پیش‌فرض در هر بیزنس
			db.query(BankAccount).filter(BankAccount.business_id == obj.business_id, BankAccount.id != obj.id).update({BankAccount.is_default: False})

	db.commit()
	db.refresh(obj)
	return bank_account_to_dict(obj)


def check_bank_account_has_accounting_documents(db: Session, account_id: int) -> tuple[bool, list[str]]:
	"""
	بررسی وجود اسناد حسابداری مرتبط با حساب بانکی
	
	Returns:
		tuple: (has_documents, document_types)
		- has_documents: True اگر سند مرتبطی وجود داشته باشد
		- document_types: لیست انواع اسناد مرتبط
	"""
	from sqlalchemy import func
	from adapters.db.models.document import Document
	from adapters.db.models.document_line import DocumentLine
	
	# بررسی وجود خطوط سند با bank_account_id در اسناد قطعی (غیر پیش‌نویس)
	document_lines_count = db.query(func.count(DocumentLine.id)).join(
		Document, DocumentLine.document_id == Document.id
	).filter(
		DocumentLine.bank_account_id == account_id,
		Document.is_proforma == False
	).scalar()
	
	if document_lines_count and document_lines_count > 0:
		# دریافت انواع اسناد مرتبط
		document_types = db.query(Document.document_type).join(
			DocumentLine, Document.id == DocumentLine.document_id
		).filter(
			DocumentLine.bank_account_id == account_id,
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


def delete_bank_account(db: Session, account_id: int) -> tuple[bool, str | None]:
	"""
	حذف حساب بانکی
	
	Returns:
		tuple: (success, error_message)
		- success: True اگر حذف موفق باشد
		- error_message: پیام خطا در صورت عدم موفقیت
	"""
	obj = db.query(BankAccount).filter(BankAccount.id == account_id).first()
	if obj is None:
		return False, "حساب بانکی یافت نشد"
	
	# بررسی وجود اسناد حسابداری مرتبط
	has_documents, document_types = check_bank_account_has_accounting_documents(db, account_id)
	
	if has_documents:
		types_str = "، ".join(document_types)
		error_msg = f"امکان حذف این حساب بانکی وجود ندارد زیرا دارای اسناد حسابداری مرتبط است. انواع اسناد: {types_str}"
		return False, error_msg
	
	try:
		db.delete(obj)
		db.commit()
		return True, None
	except Exception as e:
		db.rollback()
		return False, f"خطا در حذف حساب بانکی: {str(e)}"


def list_bank_accounts(
	db: Session,
	business_id: int,
	query: Dict[str, Any],
) -> Dict[str, Any]:
	q = db.query(BankAccount).filter(BankAccount.business_id == business_id)

	# جستجو
	if query.get("search") and query.get("search_fields"):
		term = f"%{query['search']}%"
		from sqlalchemy import or_
		conditions = []
		for f in query["search_fields"]:
			if f == "code":
				conditions.append(BankAccount.code.ilike(term))
			elif f == "name":
				conditions.append(BankAccount.name.ilike(term))
			elif f == "branch":
				conditions.append(BankAccount.branch.ilike(term))
			elif f == "account_number":
				conditions.append(BankAccount.account_number.ilike(term))
			elif f == "sheba_number":
				conditions.append(BankAccount.sheba_number.ilike(term))
			elif f == "card_number":
				conditions.append(BankAccount.card_number.ilike(term))
			elif f == "owner_name":
				conditions.append(BankAccount.owner_name.ilike(term))
			elif f == "pos_number":
				conditions.append(BankAccount.pos_number.ilike(term))
			elif f == "payment_id":
				conditions.append(BankAccount.payment_id.ilike(term))
		if conditions:
			q = q.filter(or_(*conditions))

	# فیلترها
	if query.get("filters"):
		for flt in query["filters"]:
			prop = getattr(flt, 'property', None) if not isinstance(flt, dict) else flt.get('property')
			op = getattr(flt, 'operator', None) if not isinstance(flt, dict) else flt.get('operator')
			val = getattr(flt, 'value', None) if not isinstance(flt, dict) else flt.get('value')
			if not prop or not op:
				continue
			if prop in {"is_active", "is_default"} and op == "=":
				q = q.filter(getattr(BankAccount, prop) == val)
			elif prop == "currency_id" and op == "=":
				q = q.filter(BankAccount.currency_id == val)

	# مرتب سازی
	sort_by = query.get("sort_by") or "created_at"
	sort_desc = bool(query.get("sort_desc", True))
	col = getattr(BankAccount, sort_by, BankAccount.created_at)
	q = q.order_by(col.desc() if sort_desc else col.asc())

	# صفحه‌بندی
	skip = int(query.get("skip", 0))
	take = int(query.get("take", 20))
	total = q.count()
	items = q.offset(skip).limit(take).all()

	return {
		"items": [bank_account_to_dict(i) for i in items],
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


def bulk_delete_bank_accounts(db: Session, business_id: int, account_ids: List[int]) -> Dict[str, Any]:
	"""
	حذف گروهی حساب‌های بانکی
	"""
	if not account_ids:
		return {"deleted": 0, "skipped": 0, "errors": []}
	
	# بررسی وجود حساب‌ها و دسترسی به کسب‌وکار
	accounts = db.query(BankAccount).filter(
		BankAccount.id.in_(account_ids),
		BankAccount.business_id == business_id
	).all()
	
	deleted_count = 0
	skipped_count = 0
	errors = []
	
	for account in accounts:
		try:
			success, error_message = delete_bank_account(db, account.id)
			if success:
				deleted_count += 1
			else:
				skipped_count += 1
				if error_message:
					errors.append(f"حساب بانکی {account.name or account.code or account.id}: {error_message}")
				else:
					errors.append(f"حساب بانکی {account.name or account.code or account.id}: امکان حذف وجود ندارد")
		except Exception as e:
			skipped_count += 1
			errors.append(f"خطا در حذف حساب بانکی {account.name or account.code or account.id}: {str(e)}")
	
	return {
		"deleted": deleted_count,
		"skipped": skipped_count,
		"total_requested": len(account_ids),
		"errors": errors
	}


def bank_account_to_dict(obj: BankAccount) -> Dict[str, Any]:
	return {
		"id": obj.id,
		"business_id": obj.business_id,
		"code": obj.code,
		"name": obj.name,
		"branch": obj.branch,
		"account_number": obj.account_number,
		"sheba_number": obj.sheba_number,
		"card_number": obj.card_number,
		"owner_name": obj.owner_name,
		"pos_number": obj.pos_number,
		"payment_id": obj.payment_id,
		"description": obj.description,
		"currency_id": obj.currency_id,
		"is_active": bool(obj.is_active),
		"is_default": bool(obj.is_default),
		"created_at": obj.created_at.isoformat(),
		"updated_at": obj.updated_at.isoformat(),
	}


def get_bank_accounts_turnover_report(
    db: Session,
    business_id: int,
    fiscal_year_id: Optional[int] = None,
    currency_id: Optional[int] = None,
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
    bank_account_ids: Optional[List[int]] = None,
    search: Optional[str] = None,
    skip: int = 0,
    take: int = 50,
) -> Dict[str, Any]:
    """
    گزارش گردش حساب‌های بانکی
    
    نمایش برداشت‌ها و واریزهای هر حساب بانکی در یک بازه زمانی با محاسبه مانده تجمعی
    
    Args:
        db: نشست پایگاه داده
        business_id: شناسه کسب‌وکار
        fiscal_year_id: شناسه سال مالی (اختیاری)
        currency_id: شناسه ارز (اختیاری)
        date_from: از تاریخ (اختیاری، فرمت YYYY-MM-DD)
        date_to: تا تاریخ (اختیاری، فرمت YYYY-MM-DD)
        bank_account_ids: لیست شناسه‌های حساب‌های بانکی (اختیاری)
        search: جستجو در کد سند یا نام حساب بانکی (اختیاری)
        skip: تعداد رکوردهای رد شده برای pagination
        take: تعداد رکوردهای برگشتی
    
    Returns:
        dict: {
            'items': لیست تراکنش‌ها,
            'summary': خلاصه آمار,
            'pagination': اطلاعات pagination
        }
    """
    # Query پایه: DocumentLine join Document و BankAccount
    query = db.query(
        DocumentLine,
        Document,
        BankAccount
    ).join(
        Document, DocumentLine.document_id == Document.id
    ).outerjoin(
        BankAccount, DocumentLine.bank_account_id == BankAccount.id
    ).filter(
        Document.business_id == business_id,
        Document.is_proforma == False,  # فقط اسناد قطعی
        DocumentLine.bank_account_id.isnot(None)  # فقط خطوط با bank_account_id
    )
    
    # فیلتر سال مالی
    if fiscal_year_id:
        query = query.filter(Document.fiscal_year_id == fiscal_year_id)
    
    # فیلتر ارز
    if currency_id:
        query = query.filter(Document.currency_id == currency_id)
    
    # فیلتر تاریخ
    if date_from:
        try:
            date_from_obj = datetime.strptime(date_from, '%Y-%m-%d').date()
            query = query.filter(Document.document_date >= date_from_obj)
        except ValueError:
            pass
    
    if date_to:
        try:
            date_to_obj = datetime.strptime(date_to, '%Y-%m-%d').date()
            query = query.filter(Document.document_date <= date_to_obj)
        except ValueError:
            pass
    
    # فیلتر حساب‌های بانکی
    if bank_account_ids:
        query = query.filter(DocumentLine.bank_account_id.in_(bank_account_ids))
    
    # فیلتر جستجو
    if search and search.strip():
        search_filter = or_(
            Document.code.ilike(f'%{search}%'),
            BankAccount.code.ilike(f'%{search}%'),
            BankAccount.name.ilike(f'%{search}%'),
        )
        query = query.filter(search_filter)
    
    # مرتب‌سازی: تاریخ سند، شناسه سند، شناسه خط
    query = query.order_by(
        Document.document_date.asc(),
        Document.id.asc(),
        DocumentLine.id.asc()
    )
    
    # دریافت همه نتایج برای محاسبه running balance
    all_results = query.all()
    
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
    
    # محاسبه running balance برای هر حساب بانکی و ساخت لیست آیتم‌ها
    items = []
    balance_by_account = {}  # {bank_account_id: Decimal}
    
    # محاسبه مانده ابتدای دوره برای هر حساب بانکی
    if date_from:
        try:
            date_from_obj = datetime.strptime(date_from, '%Y-%m-%d').date()
            date_before_from = date_from_obj - timedelta(days=1)
            
            # برای هر حساب بانکی، محاسبه مانده تا یک روز قبل از date_from
            unique_bank_account_ids = list(set(
                line.bank_account_id for line, doc, ba in all_results 
                if line.bank_account_id is not None
            ))
            
            for ba_id in unique_bank_account_ids:
                # محاسبه مجموع واریز (debit) و برداشت (credit) تا date_before_from
                opening_query = db.query(
                    func.coalesce(func.sum(DocumentLine.debit), 0).label('total_deposit'),
                    func.coalesce(func.sum(DocumentLine.credit), 0).label('total_withdrawal')
                ).join(
                    Document, DocumentLine.document_id == Document.id
                ).filter(
                    Document.business_id == business_id,
                    Document.is_proforma == False,
                    DocumentLine.bank_account_id == ba_id,
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
                    balance_by_account[ba_id] = total_deposit - total_withdrawal
                else:
                    balance_by_account[ba_id] = Decimal(0)
        except Exception:
            # در صورت خطا، مانده ابتدا را صفر در نظر بگیر
            pass
    
    total_deposit = Decimal(0)
    total_withdrawal = Decimal(0)
    
    for line, doc, bank_account in all_results:
        if not bank_account or not line.bank_account_id:
            continue
        
        ba_id = line.bank_account_id
        
        # مقدار اولیه برای حساب بانکی اگر وجود نداشته باشد
        if ba_id not in balance_by_account:
            balance_by_account[ba_id] = Decimal(0)
        
        deposit = Decimal(str(line.debit or 0))
        withdrawal = Decimal(str(line.credit or 0))
        
        # به‌روزرسانی مانده: واریز (debit) اضافه می‌کند، برداشت (credit) کم می‌کند
        balance_by_account[ba_id] += deposit - withdrawal
        
        total_deposit += deposit
        total_withdrawal += withdrawal
        
        document_type_name = _get_document_type_name(doc.document_type)
        
        items.append({
            'bank_account_id': ba_id,
            'bank_account_code': bank_account.code or '',
            'bank_account_name': bank_account.name or '',
            'document_date': doc.document_date.isoformat(),
            'document_type': doc.document_type,
            'document_type_name': document_type_name,
            'document_code': doc.code or '',
            'document_id': doc.id,
            'deposit': float(deposit),
            'withdrawal': float(withdrawal),
            'balance': float(balance_by_account[ba_id]),
            'description': line.description or doc.description or '',
        })
    
    # اعمال pagination
    total = len(items)
    paginated_items = items[skip:skip + take]
    
    total_pages = (total + take - 1) // take if take > 0 else 0
    current_page = (skip // take) + 1 if take > 0 else 1
    
    # محاسبه موجودی فعلی (مجموع مانده آخرین تراکنش هر حساب بانکی)
    # برای محاسبه دقیق، مانده آخرین تراکنش هر حساب را پیدا می‌کنیم
    current_balance_by_account = {}  # {bank_account_id: last_balance}
    
    # مانده آخرین تراکنش هر حساب را از لیست کامل items پیدا می‌کنیم
    # (قبل از pagination)
    for item in items:
        ba_id = item.get('bank_account_id')
        balance = item.get('balance')
        if ba_id is not None and balance is not None:
            # همیشه آخرین مانده برای هر حساب را نگه می‌داریم
            try:
                current_balance_by_account[ba_id] = float(balance)
            except (ValueError, TypeError):
                pass
    
    # مجموع موجودی فعلی همه حساب‌ها
    total_current_balance = sum(current_balance_by_account.values())
    
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


