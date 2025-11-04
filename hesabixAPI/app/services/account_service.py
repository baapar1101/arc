from __future__ import annotations

from typing import Any, Dict, Optional

from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from adapters.db.models.account import Account


def account_to_dict(obj: Account) -> Dict[str, Any]:
	return {
		"id": obj.id,
		"name": obj.name,
		"code": obj.code,
		"account_type": obj.account_type,
		"parent_id": obj.parent_id,
		"business_id": obj.business_id,
		"created_at": obj.created_at,
		"updated_at": obj.updated_at,
	}


def _validate_parent(db: Session, parent_id: Optional[int], business_id: Optional[int]) -> Optional[int]:
	if parent_id is None:
		return None
	parent = db.get(Account, parent_id)
	if not parent:
		raise ValueError("PARENT_NOT_FOUND")
	# والد باید عمومی یا متعلق به همان کسب‌وکار باشد
	if parent.business_id is not None and parent.business_id != business_id:
		raise ValueError("INVALID_PARENT_BUSINESS")
	return parent.id


def create_account(
	db: Session,
	*,
	name: str,
	code: str,
	account_type: str,
	business_id: Optional[int],
	parent_id: Optional[int] = None,
) -> Dict[str, Any]:
	parent_id = _validate_parent(db, parent_id, business_id)
	obj = Account(
		name=name,
		code=code,
		account_type=account_type,
		business_id=business_id,
		parent_id=parent_id,
	)
	db.add(obj)
	try:
		db.commit()
	except IntegrityError as e:
		db.rollback()
		raise ValueError("ACCOUNT_CODE_NOT_UNIQUE") from e
	db.refresh(obj)
	return account_to_dict(obj)


def update_account(
	db: Session,
	account_id: int,
	*,
	name: Optional[str] = None,
	code: Optional[str] = None,
	account_type: Optional[str] = None,
	parent_id: Optional[int] = None,
) -> Optional[Dict[str, Any]]:
	obj = db.get(Account, account_id)
	if not obj:
		return None
	# جلوگیری از تغییر حساب‌های عمومی در لایه سرویس
	if obj.business_id is None:
		raise ValueError("PUBLIC_IMMUTABLE")
	if parent_id is not None:
		parent_id = _validate_parent(db, parent_id, obj.business_id)
	if name is not None:
		obj.name = name
	if code is not None:
		obj.code = code
	if account_type is not None:
		obj.account_type = account_type
	obj.parent_id = parent_id if parent_id is not None else obj.parent_id
	try:
		db.commit()
	except IntegrityError as e:
		db.rollback()
		raise ValueError("ACCOUNT_CODE_NOT_UNIQUE") from e
	db.refresh(obj)
	return account_to_dict(obj)


def delete_account(db: Session, account_id: int) -> bool:
	obj = db.get(Account, account_id)
	if not obj:
		return False
	# جلوگیری از حذف اگر فرزند دارد
	if obj.children and len(obj.children) > 0:
		raise ValueError("ACCOUNT_HAS_CHILDREN")
	# جلوگیری از حذف اگر در اسناد استفاده شده است
	if obj.document_lines and len(obj.document_lines) > 0:
		raise ValueError("ACCOUNT_IN_USE")
	db.delete(obj)
	db.commit()
	return True


def get_account(db: Session, account_id: int) -> Optional[Dict[str, Any]]:
	obj = db.get(Account, account_id)
	return account_to_dict(obj) if obj else None


