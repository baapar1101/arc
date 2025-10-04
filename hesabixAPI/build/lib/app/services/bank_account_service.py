from __future__ import annotations

from typing import Any, Dict, List, Optional
from sqlalchemy.orm import Session
from sqlalchemy import and_, func

from adapters.db.models.bank_account import BankAccount
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


def delete_bank_account(db: Session, account_id: int) -> bool:
	obj = db.query(BankAccount).filter(BankAccount.id == account_id).first()
	if obj is None:
		return False
	db.delete(obj)
	db.commit()
	return True


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
		return {"deleted": 0, "skipped": 0}
	
	# بررسی وجود حساب‌ها و دسترسی به کسب‌وکار
	accounts = db.query(BankAccount).filter(
		BankAccount.id.in_(account_ids),
		BankAccount.business_id == business_id
	).all()
	
	deleted_count = 0
	skipped_count = 0
	
	for account in accounts:
		try:
			db.delete(account)
			deleted_count += 1
		except Exception:
			skipped_count += 1
	
	# commit تغییرات
	try:
		db.commit()
	except Exception:
		db.rollback()
		raise ApiError("BULK_DELETE_FAILED", "Bulk delete failed for bank accounts", http_status=500)
	
	return {
		"deleted": deleted_count,
		"skipped": skipped_count,
		"total_requested": len(account_ids)
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


