from __future__ import annotations

from typing import Any, Dict, List, Optional
from sqlalchemy.orm import Session
from sqlalchemy import and_, or_, func

from adapters.db.models.cash_register import CashRegister


class CashRegisterRepository:
	def __init__(self, db: Session) -> None:
		self.db = db

	def create(self, business_id: int, data: Dict[str, Any]) -> CashRegister:
		obj = CashRegister(
			business_id=business_id,
			name=data.get("name"),
			code=data.get("code"),
			description=data.get("description"),
			currency_id=int(data["currency_id"]),
			is_active=bool(data.get("is_active", True)),
			is_default=bool(data.get("is_default", False)),
			payment_switch_number=data.get("payment_switch_number"),
			payment_terminal_number=data.get("payment_terminal_number"),
			merchant_id=data.get("merchant_id"),
		)
		self.db.add(obj)
		self.db.flush()
		return obj

	def get_by_id(self, id_: int) -> Optional[CashRegister]:
		return self.db.query(CashRegister).filter(CashRegister.id == id_).first()

	def update(self, obj: CashRegister, data: Dict[str, Any]) -> CashRegister:
		for key in [
			"name","code","description","currency_id","is_active","is_default",
			"payment_switch_number","payment_terminal_number","merchant_id",
		]:
			if key in data and data[key] is not None:
				setattr(obj, key, data[key] if key != "currency_id" else int(data[key]))
		return obj

	def delete(self, obj: CashRegister) -> None:
		self.db.delete(obj)

	def bulk_delete(self, business_id: int, ids: List[int]) -> Dict[str, int]:
		items = self.db.query(CashRegister).filter(
			CashRegister.business_id == business_id,
			CashRegister.id.in_(ids)
		).all()
		deleted = 0
		skipped = 0
		for it in items:
			try:
				self.db.delete(it)
				deleted += 1
			except Exception:
				skipped += 1
		return {"deleted": deleted, "skipped": skipped, "total_requested": len(ids)}

	def clear_default(self, business_id: int, except_id: Optional[int] = None) -> None:
		q = self.db.query(CashRegister).filter(CashRegister.business_id == business_id)
		if except_id is not None:
			q = q.filter(CashRegister.id != except_id)
		q.update({CashRegister.is_default: False})

	def list(self, business_id: int, query: Dict[str, Any]) -> Dict[str, Any]:
		q = self.db.query(CashRegister).filter(CashRegister.business_id == business_id)

		# search
		search = query.get("search")
		search_fields = query.get("search_fields") or []
		if search and search_fields:
			term = f"%{search}%"
			conditions = []
			for f in search_fields:
				if f == "name":
					conditions.append(CashRegister.name.ilike(term))
				if f == "code":
					conditions.append(CashRegister.code.ilike(term))
				elif f == "description":
					conditions.append(CashRegister.description.ilike(term))
				elif f in {"payment_switch_number","payment_terminal_number","merchant_id"}:
					conditions.append(getattr(CashRegister, f).ilike(term))
			if conditions:
				q = q.filter(or_(*conditions))

		# filters
		for flt in (query.get("filters") or []):
			prop = flt.get("property")
			op = flt.get("operator")
			val = flt.get("value")
			if not prop or not op:
				continue
			if prop in {"is_active","is_default"} and op == "=":
				q = q.filter(getattr(CashRegister, prop) == val)
			elif prop == "currency_id" and op == "=":
				q = q.filter(CashRegister.currency_id == val)

		# sort
		sort_by = query.get("sort_by") or "created_at"
		sort_desc = bool(query.get("sort_desc", True))
		col = getattr(CashRegister, sort_by, CashRegister.created_at)
		q = q.order_by(col.desc() if sort_desc else col.asc())

		# pagination
		skip = int(query.get("skip", 0))
		take = int(query.get("take", 20))
		total = q.count()
		items = q.offset(skip).limit(take).all()

		return {
			"items": items,
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


