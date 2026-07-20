"""Data Gateway امن — فقط سرویس‌های دامنه با business_id قفل‌شده."""

from __future__ import annotations

from datetime import date, datetime, timedelta
from typing import Any, Optional

from app.services.hscript.errors import TypeErrorHS
from app.services.hscript.gateway.context import GatewayContext
from app.services.hscript.values import HModule, HTable, sanitize_jsonish


def _parse_date(value: Any) -> Optional[date]:
	if value is None:
		return None
	if isinstance(value, date) and not isinstance(value, datetime):
		return value
	if isinstance(value, datetime):
		return value.date()
	s = str(value).strip()
	if not s:
		return None
	return datetime.fromisoformat(s.replace("Z", "+00:00")).date()


def _month_bounds(ref: Optional[date] = None) -> tuple[date, date]:
	today = ref or date.today()
	start = today.replace(day=1)
	if start.month == 12:
		end = start.replace(year=start.year + 1, month=1, day=1) - timedelta(days=1)
	else:
		end = start.replace(month=start.month + 1, day=1) - timedelta(days=1)
	return start, end


def _last_month_bounds(ref: Optional[date] = None) -> tuple[date, date]:
	today = ref or date.today()
	first_this = today.replace(day=1)
	end = first_this - timedelta(days=1)
	start = end.replace(day=1)
	return start, end


def _safe_items(result: Any) -> list[dict[str, Any]]:
	if isinstance(result, dict):
		items = result.get("items") or result.get("data") or []
	elif isinstance(result, list):
		items = result
	else:
		items = []
	out: list[dict[str, Any]] = []
	for item in items:
		if isinstance(item, dict):
			# حذف فیلدهای بالقوه حساس
			clean = {
				k: sanitize_jsonish(v)
				for k, v in item.items()
				if not str(k).startswith("_")
				and k not in {"developer_settings", "api_key", "password", "token", "secret"}
			}
			out.append(clean)
	return out


class InvoicesGateway:
	def __init__(self, ctx: GatewayContext):
		self.ctx = ctx

	def filter(
		self,
		*,
		status: Optional[str] = None,
		document_type: str = "invoice_sales",
		from_date: Any = None,
		to_date: Any = None,
		person_id: Optional[int] = None,
		search: Optional[str] = None,
		limit: Optional[int] = None,
		is_proforma: Optional[bool] = None,
	) -> HTable:
		self.ctx.bump_call()
		from app.services.document_service import list_documents

		take = self.ctx.row_limit(limit)
		query: dict[str, Any] = {
			"document_type": str(document_type),
			"take": take,
			"skip": 0,
			"sort_by": "document_date",
			"sort_desc": True,
		}
		fd = _parse_date(from_date)
		td = _parse_date(to_date)
		if fd:
			query["from_date"] = fd.isoformat()
		if td:
			query["to_date"] = td.isoformat()
		if person_id is not None:
			query["person_id"] = int(person_id)
		if search:
			query["search"] = str(search)[:200]
		if is_proforma is not None:
			query["is_proforma"] = bool(is_proforma)
		if self.ctx.fiscal_year_id:
			query["fiscal_year_id"] = self.ctx.fiscal_year_id
		# status در مدل فعلی ممکن است در extra_info باشد؛ به‌صورت فیلتر نرم نگه می‌داریم
		result = list_documents(self.ctx.db, self.ctx.business_id, query)
		rows = _safe_items(result)
		if status:
			# فیلتر نرم سمت sandbox روی فیلدهای موجود
			status_s = str(status).lower()
			filtered = []
			for r in rows:
				blob = " ".join(str(r.get(k, "")).lower() for k in ("status", "document_type", "description"))
				if status_s in blob or r.get("status") == status:
					filtered.append(r)
			rows = filtered
		return HTable.from_rows(rows, max_rows=self.ctx.limits.max_gateway_rows_per_call)

	def all(self, *, limit: Optional[int] = None) -> HTable:
		return self.filter(limit=limit)

	def last_month(self, *, document_type: str = "invoice_sales", limit: Optional[int] = None) -> HTable:
		start, end = _last_month_bounds()
		return self.filter(document_type=document_type, from_date=start, to_date=end, limit=limit)

	def this_month(self, *, document_type: str = "invoice_sales", limit: Optional[int] = None) -> HTable:
		start, end = _month_bounds()
		return self.filter(document_type=document_type, from_date=start, to_date=end, limit=limit)

	def count(self, **kwargs: Any) -> int:
		table = self.filter(**kwargs)
		return table.count()


class CustomersGateway:
	"""اشخاص با نقش مشتری — از person_service."""

	def __init__(self, ctx: GatewayContext):
		self.ctx = ctx

	def filter(
		self,
		*,
		search: Optional[str] = None,
		limit: Optional[int] = None,
	) -> HTable:
		self.ctx.bump_call()
		from app.services.person_service import search_persons

		take = self.ctx.row_limit(limit)
		persons = search_persons(
			self.ctx.db,
			self.ctx.business_id,
			search_query=search,
			page=1,
			limit=take,
		)
		rows = []
		for p in persons:
			types_raw = getattr(p, "person_types", "") or ""
			rows.append({
				"id": p.id,
				"code": getattr(p, "code", None),
				"alias_name": getattr(p, "alias_name", None),
				"first_name": getattr(p, "first_name", None),
				"last_name": getattr(p, "last_name", None),
				"company_name": getattr(p, "company_name", None),
				"phone": getattr(p, "phone", None),
				"mobile": getattr(p, "mobile", None),
				"email": getattr(p, "email", None),
				"person_types": types_raw,
			})
		# ترجیح اشخاصی که مشتری‌اند
		customers = [r for r in rows if "customer" in str(r.get("person_types", "")).lower()] or rows
		return HTable.from_rows(customers, max_rows=self.ctx.limits.max_gateway_rows_per_call)

	def all(self, *, limit: Optional[int] = None) -> HTable:
		return self.filter(limit=limit)

	def count(self, **kwargs: Any) -> int:
		return self.filter(**kwargs).count()


class ProductsGateway:
	def __init__(self, ctx: GatewayContext):
		self.ctx = ctx

	def filter(self, *, search: Optional[str] = None, limit: Optional[int] = None) -> HTable:
		self.ctx.bump_call()
		from adapters.db.models.product import Product

		take = self.ctx.row_limit(limit)
		q = self.ctx.db.query(Product).filter(Product.business_id == self.ctx.business_id)
		if search:
			like = f"%{str(search)[:100]}%"
			q = q.filter(Product.name.ilike(like))
		items = q.order_by(Product.id.desc()).limit(take).all()
		rows = []
		for p in items:
			price = getattr(p, "base_sales_price", None)
			rows.append({
				"id": p.id,
				"name": getattr(p, "name", None),
				"code": getattr(p, "code", None),
				"barcode": getattr(p, "general_barcodes", None),
				"sale_price": float(price) if price is not None else 0.0,
				"is_active": bool(getattr(p, "is_active", True)),
			})
		return HTable.from_rows(rows, max_rows=self.ctx.limits.max_gateway_rows_per_call)

	def all(self, *, limit: Optional[int] = None) -> HTable:
		return self.filter(limit=limit)

	def top(self, n: int = 10, *, by: str = "sale_price") -> HTable:
		table = self.all(limit=self.ctx.row_limit(500))
		return table.top(int(n), by=by, desc=True)


class PaymentsGateway:
	"""اسناد دریافت/پرداخت."""

	def __init__(self, ctx: GatewayContext):
		self.ctx = ctx

	def filter(
		self,
		*,
		kind: str = "receipt",
		from_date: Any = None,
		to_date: Any = None,
		limit: Optional[int] = None,
	) -> HTable:
		self.ctx.bump_call()
		from app.services.document_service import list_documents

		# kind: receipt | payment
		doc_type = "receipt" if str(kind) == "receipt" else "payment"
		if kind not in ("receipt", "payment"):
			raise TypeErrorHS("kind باید receipt یا payment باشد")
		take = self.ctx.row_limit(limit)
		query: dict[str, Any] = {
			"document_type": doc_type,
			"take": take,
			"skip": 0,
			"sort_by": "document_date",
			"sort_desc": True,
		}
		fd = _parse_date(from_date)
		td = _parse_date(to_date)
		if fd:
			query["from_date"] = fd.isoformat()
		if td:
			query["to_date"] = td.isoformat()
		if self.ctx.fiscal_year_id:
			query["fiscal_year_id"] = self.ctx.fiscal_year_id
		result = list_documents(self.ctx.db, self.ctx.business_id, query)
		return HTable.from_rows(_safe_items(result), max_rows=self.ctx.limits.max_gateway_rows_per_call)

	def last_month(self, *, kind: str = "receipt", limit: Optional[int] = None) -> HTable:
		start, end = _last_month_bounds()
		return self.filter(kind=kind, from_date=start, to_date=end, limit=limit)

	def this_month(self, *, kind: str = "receipt", limit: Optional[int] = None) -> HTable:
		start, end = _month_bounds()
		return self.filter(kind=kind, from_date=start, to_date=end, limit=limit)


def build_gateway_modules(ctx: GatewayContext) -> dict[str, HModule]:
	inv = InvoicesGateway(ctx)
	cust = CustomersGateway(ctx)
	prod = ProductsGateway(ctx)
	pay = PaymentsGateway(ctx)

	def _bind(obj: Any, names: list[str]) -> dict[str, Any]:
		methods = {}
		for n in names:
			fn = getattr(obj, n)
			methods[n] = fn
		return methods

	return {
		"invoices": HModule(name="invoices", methods=_bind(inv, ["filter", "all", "last_month", "this_month", "count"])),
		"customers": HModule(name="customers", methods=_bind(cust, ["filter", "all", "count"])),
		"products": HModule(name="products", methods=_bind(prod, ["filter", "all", "top"])),
		"payments": HModule(name="payments", methods=_bind(pay, ["filter", "last_month", "this_month"])),
	}


def build_params_module(params: dict[str, Any]) -> HModule:
	"""params فقط خواندنی؛ بدون امکان نوشتن به سیستم."""
	safe = {str(k): sanitize_jsonish(v) for k, v in (params or {}).items() if not str(k).startswith("_")}

	def get(name: str, default: Any = None) -> Any:
		return safe.get(str(name), default)

	def all() -> dict[str, Any]:
		return dict(safe)

	# برای params.start به صورت attribute — از dict proxy استفاده می‌کنیم
	# Attribute روی HModule فقط متد است؛ پس params را هم به‌صورت dict در globals می‌گذاریم.
	return HModule(name="params", methods={"get": get, "all": all})
