from __future__ import annotations

from typing import Any, Dict, List, Optional
from sqlalchemy.orm import Session
from sqlalchemy import and_, func

from adapters.db.models.cash_register import CashRegister
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


def delete_cash_register(db: Session, id_: int) -> bool:
	obj = db.query(CashRegister).filter(CashRegister.id == id_).first()
	if obj is None:
		return False
	db.delete(obj)
	db.commit()
	return True


def bulk_delete_cash_registers(db: Session, business_id: int, ids: List[int]) -> Dict[str, Any]:
	repo = CashRegisterRepository(db)
	result = repo.bulk_delete(business_id, ids)
	try:
		db.commit()
	except Exception:
		db.rollback()
		raise ApiError("BULK_DELETE_FAILED", "Bulk delete failed for cash registers", http_status=500)
	return result


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


