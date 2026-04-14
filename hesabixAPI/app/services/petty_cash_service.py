from __future__ import annotations

from typing import Any, Dict, List, Optional
from decimal import Decimal
from sqlalchemy.orm import Session
from sqlalchemy import and_, func

from adapters.db.models.petty_cash import PettyCash
from adapters.db.models.document import Document
from adapters.db.models.document_line import DocumentLine
from adapters.db.models.fiscal_year import FiscalYear
from adapters.db.repositories.petty_cash_repository import PettyCashRepository
from app.core.responses import ApiError


def create_petty_cash(db: Session, business_id: int, data: Dict[str, Any]) -> Dict[str, Any]:
	# validate required fields
	name = (data.get("name") or "").strip()
	if name == "":
		raise ApiError("STRING_TOO_SHORT", "Name is required", http_status=400)

	# code uniqueness in business if provided; else auto-generate numeric min 3 digits
	code = data.get("code")
	if code is not None and str(code).strip() != "":
		if not str(code).isdigit():
			raise ApiError("INVALID_PETTY_CASH_CODE", "Petty cash code must be numeric", http_status=400)
		if len(str(code)) < 3:
			raise ApiError("INVALID_PETTY_CASH_CODE", "Petty cash code must be at least 3 digits", http_status=400)
		exists = db.query(PettyCash).filter(and_(PettyCash.business_id == business_id, PettyCash.code == str(code))).first()
		if exists:
			raise ApiError("DUPLICATE_PETTY_CASH_CODE", "Duplicate petty cash code", http_status=400)
	else:
		max_code = db.query(func.max(PettyCash.code)).filter(PettyCash.business_id == business_id).scalar()
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

	repo = PettyCashRepository(db)
	obj = repo.create(business_id, {
		"name": name,
		"code": code,
		"description": data.get("description"),
		"currency_id": int(data["currency_id"]),
		"is_active": bool(data.get("is_active", True)),
		"is_default": bool(data.get("is_default", False)),
	})

	# ensure single default
	if obj.is_default:
		repo.clear_default(business_id, except_id=obj.id)

	db.commit()
	db.refresh(obj)
	return petty_cash_to_dict(obj)


def get_petty_cash_by_id(db: Session, id_: int) -> Optional[Dict[str, Any]]:
	obj = db.query(PettyCash).filter(PettyCash.id == id_).first()
	return petty_cash_to_dict(obj) if obj else None


def update_petty_cash(db: Session, id_: int, data: Dict[str, Any]) -> Optional[Dict[str, Any]]:
	repo = PettyCashRepository(db)
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
			raise ApiError("INVALID_PETTY_CASH_CODE", "Petty cash code must be numeric", http_status=400)
		if len(str(data["code"])) < 3:
			raise ApiError("INVALID_PETTY_CASH_CODE", "Petty cash code must be at least 3 digits", http_status=400)
		exists = db.query(PettyCash).filter(and_(PettyCash.business_id == obj.business_id, PettyCash.code == str(data["code"]), PettyCash.id != obj.id)).first()
		if exists:
			raise ApiError("DUPLICATE_PETTY_CASH_CODE", "Duplicate petty cash code", http_status=400)

	repo.update(obj, data)
	if obj.is_default:
		repo.clear_default(obj.business_id, except_id=obj.id)

	db.commit()
	db.refresh(obj)
	return petty_cash_to_dict(obj)


def check_petty_cash_has_accounting_documents(db: Session, petty_cash_id: int) -> tuple[bool, list[str]]:
	"""
	بررسی وجود اسناد حسابداری مرتبط با تنخواه
	
	Returns:
		tuple: (has_documents, document_types)
		- has_documents: True اگر سند مرتبطی وجود داشته باشد
		- document_types: لیست انواع اسناد مرتبط
	"""
	from sqlalchemy import func
	from adapters.db.models.document import Document
	from adapters.db.models.document_line import DocumentLine
	
	# بررسی وجود خطوط سند با petty_cash_id در اسناد قطعی (غیر پیش‌نویس)
	document_lines_count = db.query(func.count(DocumentLine.id)).join(
		Document, DocumentLine.document_id == Document.id
	).filter(
		DocumentLine.petty_cash_id == petty_cash_id,
		Document.is_proforma == False
	).scalar()
	
	if document_lines_count and document_lines_count > 0:
		# دریافت انواع اسناد مرتبط
		document_types = db.query(Document.document_type).join(
			DocumentLine, Document.id == DocumentLine.document_id
		).filter(
			DocumentLine.petty_cash_id == petty_cash_id,
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


def delete_petty_cash(db: Session, id_: int) -> tuple[bool, str | None]:
	"""
	حذف تنخواه
	
	Returns:
		tuple: (success, error_message)
		- success: True اگر حذف موفق باشد
		- error_message: پیام خطا در صورت عدم موفقیت
	"""
	obj = db.query(PettyCash).filter(PettyCash.id == id_).first()
	if obj is None:
		return False, "تنخواه یافت نشد"
	
	# بررسی وجود اسناد حسابداری مرتبط
	has_documents, document_types = check_petty_cash_has_accounting_documents(db, id_)
	
	if has_documents:
		types_str = "، ".join(document_types)
		error_msg = f"امکان حذف این تنخواه وجود ندارد زیرا دارای اسناد حسابداری مرتبط است. انواع اسناد: {types_str}"
		return False, error_msg
	
	try:
		db.delete(obj)
		db.commit()
		return True, None
	except Exception as e:
		db.rollback()
		return False, f"خطا در حذف تنخواه: {str(e)}"


def bulk_delete_petty_cash(db: Session, business_id: int, ids: List[int]) -> Dict[str, Any]:
	"""
	حذف گروهی تنخواه‌ها
	"""
	if not ids:
		return {"deleted": 0, "skipped": 0, "errors": []}
	
	# بررسی وجود تنخواه‌ها و دسترسی به کسب‌وکار
	petty_cash_list = db.query(PettyCash).filter(
		PettyCash.id.in_(ids),
		PettyCash.business_id == business_id
	).all()
	
	deleted_count = 0
	skipped_count = 0
	errors = []
	
	for petty_cash in petty_cash_list:
		try:
			success, error_message = delete_petty_cash(db, petty_cash.id)
			if success:
				deleted_count += 1
			else:
				skipped_count += 1
				if error_message:
					errors.append(f"تنخواه {petty_cash.name or petty_cash.code or petty_cash.id}: {error_message}")
				else:
					errors.append(f"تنخواه {petty_cash.name or petty_cash.code or petty_cash.id}: امکان حذف وجود ندارد")
		except Exception as e:
			skipped_count += 1
			errors.append(f"خطا در حذف تنخواه {petty_cash.name or petty_cash.code or petty_cash.id}: {str(e)}")
	
	return {
		"deleted": deleted_count,
		"skipped": skipped_count,
		"total_requested": len(ids),
		"errors": errors
	}


def _calculate_petty_cash_balance(
	db: Session,
	petty_cash_id: int,
	business_id: int,
	fiscal_year_id: Optional[int] = None,
) -> Decimal:
	"""
	محاسبه موجودی یک تنخواه
	
	Args:
		db: نشست پایگاه داده
		petty_cash_id: شناسه تنخواه
		business_id: شناسه کسب‌وکار
		fiscal_year_id: شناسه سال مالی (اختیاری)
	
	Returns:
		Decimal: موجودی تنخواه (debit - credit)
	"""
	query = db.query(
		func.coalesce(func.sum(DocumentLine.debit), 0).label('total_debit'),
		func.coalesce(func.sum(DocumentLine.credit), 0).label('total_credit')
	).join(
		Document, DocumentLine.document_id == Document.id
	).filter(
		Document.business_id == business_id,
		Document.is_proforma == False,
		DocumentLine.petty_cash_id == petty_cash_id
	)
	
	# فیلتر سال مالی
	if fiscal_year_id:
		query = query.filter(Document.fiscal_year_id == fiscal_year_id)
	
	result = query.first()
	if result:
		total_debit = Decimal(str(result.total_debit or 0))
		total_credit = Decimal(str(result.total_credit or 0))
		return total_debit - total_credit
	
	return Decimal(0)


def _calculate_petty_cash_balances_bulk(
	db: Session,
	petty_cash_ids: List[int],
	business_id: int,
	fiscal_year_id: Optional[int] = None,
) -> Dict[int, Decimal]:
	"""
	محاسبه موجودی چند تنخواه به صورت bulk
	
	Args:
		db: نشست پایگاه داده
		petty_cash_ids: لیست شناسه‌های تنخواه‌ها
		business_id: شناسه کسب‌وکار
		fiscal_year_id: شناسه سال مالی (اختیاری)
	
	Returns:
		Dict[int, Decimal]: دیکشنری {petty_cash_id: balance}
	"""
	if not petty_cash_ids:
		return {}
	
	query = db.query(
		DocumentLine.petty_cash_id,
		func.coalesce(func.sum(DocumentLine.debit), 0).label('total_debit'),
		func.coalesce(func.sum(DocumentLine.credit), 0).label('total_credit')
	).join(
		Document, DocumentLine.document_id == Document.id
	).filter(
		Document.business_id == business_id,
		Document.is_proforma == False,
		DocumentLine.petty_cash_id.in_(petty_cash_ids)
	).group_by(
		DocumentLine.petty_cash_id
	)
	
	# فیلتر سال مالی
	if fiscal_year_id:
		query = query.filter(Document.fiscal_year_id == fiscal_year_id)
	
	results = query.all()
	
	balances = {}
	for result in results:
		pc_id = result.petty_cash_id
		total_debit = Decimal(str(result.total_debit or 0))
		total_credit = Decimal(str(result.total_credit or 0))
		balances[pc_id] = total_debit - total_credit
	
	# برای تنخواه‌هایی که تراکنشی ندارند، موجودی صفر است
	for pc_id in petty_cash_ids:
		if pc_id not in balances:
			balances[pc_id] = Decimal(0)
	
	return balances


def list_petty_cash(db: Session, business_id: int, query: Dict[str, Any]) -> Dict[str, Any]:
	# دریافت سال مالی از query (اختیاری)
	fiscal_year_id = query.get("fiscal_year_id")
	if fiscal_year_id is not None:
		try:
			fiscal_year_id = int(fiscal_year_id)
		except (ValueError, TypeError):
			fiscal_year_id = None
	
	# اگر سال مالی مشخص نشده، از سال مالی جاری استفاده کن
	if fiscal_year_id is None:
		fiscal_year = db.query(FiscalYear).filter(
			and_(
				FiscalYear.business_id == business_id,
				FiscalYear.is_last == True
			)
		).first()
		if fiscal_year:
			fiscal_year_id = fiscal_year.id
	
	repo = PettyCashRepository(db)
	res = repo.list(business_id, query)
	
	# محاسبه موجودی برای همه تنخواه‌ها به صورت bulk
	petty_cash_ids = [item.id for item in res["items"]]
	balances = _calculate_petty_cash_balances_bulk(
		db, petty_cash_ids, business_id, fiscal_year_id
	)
	
	# ساخت لیست با موجودی
	result_items = []
	for item in res["items"]:
		item_dict = petty_cash_to_dict(item)
		item_dict["balance"] = float(balances.get(item.id, Decimal(0)))
		result_items.append(item_dict)
	
	return {
		"items": result_items,
		"pagination": res["pagination"],
		"query_info": res["query_info"],
	}


def petty_cash_to_dict(obj: PettyCash, balance: Optional[float] = None) -> Dict[str, Any]:
	result = {
		"id": obj.id,
		"business_id": obj.business_id,
		"name": obj.name,
		"code": obj.code,
		"description": obj.description,
		"currency_id": obj.currency_id,
		"is_active": bool(obj.is_active),
		"is_default": bool(obj.is_default),
		"created_at": obj.created_at.isoformat(),
		"updated_at": obj.updated_at.isoformat(),
	}
	if balance is not None:
		result["balance"] = balance
	return result
