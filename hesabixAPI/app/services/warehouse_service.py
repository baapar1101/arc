from __future__ import annotations

from typing import Any, Dict, List, Optional
from decimal import Decimal
from datetime import datetime, date

from sqlalchemy.orm import Session
from sqlalchemy import and_

from adapters.db.models.warehouse_document import WarehouseDocument
from adapters.db.models.warehouse_document_line import WarehouseDocumentLine
from adapters.db.models.document import Document
from adapters.db.models.document_line import DocumentLine
from adapters.db.models.product import Product
from adapters.db.models.account import Account
from adapters.db.models.fiscal_year import FiscalYear
from app.core.responses import ApiError
from adapters.db.models.warehouse import Warehouse
from adapters.db.repositories.warehouse_repository import WarehouseRepository
from adapters.api.v1.schema_models.warehouse import WarehouseCreateRequest, WarehouseUpdateRequest
from adapters.api.v1.schemas import QueryInfo, FilterItem
from app.services.query_service import QueryService


def _get_current_fiscal_year(db: Session, business_id: int) -> FiscalYear:
	fy = db.query(FiscalYear).filter(and_(FiscalYear.business_id == business_id, FiscalYear.is_last == True)).first()
	if not fy:
		raise ApiError("NO_FISCAL_YEAR", "No active fiscal year found for this business", http_status=400)
	return fy


def _build_wh_code(prefix_base: str) -> str:
	today = datetime.now().date()
	return f"{prefix_base}-{today.strftime('%Y%m%d')}-{int(datetime.utcnow().timestamp())%100000}"


def create_from_invoice(
	db: Session,
	business_id: int,
	invoice: Document,
	lines: List[Dict[str, Any]],
	wh_doc_type: str,
	created_by_user_id: Optional[int] = None,
) -> WarehouseDocument:
	"""ساخت حواله انبار draft از روی فاکتور (بدون پست)."""
	fy = _get_current_fiscal_year(db, business_id)
	code = _build_wh_code("WH")
	wh = WarehouseDocument(
		business_id=business_id,
		fiscal_year_id=fy.id,
		code=code,
		document_date=invoice.document_date,
		status="draft",
		doc_type=wh_doc_type,
		source_type="invoice",
		source_document_id=invoice.id,
		created_by_user_id=created_by_user_id,
	)
	db.add(wh)
	db.flush()
	for ln in lines:
		pid = ln.get("product_id")
		qty = Decimal(str(ln.get("quantity") or 0))
		if not pid or qty <= 0:
			continue
		extra = ln.get("extra_info") or {}
		mv = (extra.get("movement") or ("out" if wh_doc_type in ("issue", "production_out") else "in"))
		# warehouse_id عمداً تعیین نمی‌شود؛ انباردار بعداً مشخص می‌کند
		wline = WarehouseDocumentLine(
			warehouse_document_id=wh.id,
			product_id=int(pid),
			warehouse_id=None,
			movement=str(mv),
			quantity=qty,
			extra_info=extra,
		)
		db.add(wline)
	db.flush()
	return wh


def post_warehouse_document(db: Session, wh_id: int) -> Dict[str, Any]:
	"""پست حواله: کنترل کسری برای خروج‌ها و محاسبه COGS ساده (fallback به unit_price).
	در پایان، در صورت وجود لینک به فاکتور منبع، سطرهای حسابداری COGS/Inventory را به همان سند اضافه می‌کند.
	"""
	wh = db.query(WarehouseDocument).filter(WarehouseDocument.id == wh_id).first()
	if not wh:
		raise ApiError("NOT_FOUND", "Warehouse document not found", http_status=404)
	if wh.status == "posted":
		return {"id": wh.id, "status": wh.status}

	lines = db.query(WarehouseDocumentLine).filter(WarehouseDocumentLine.warehouse_document_id == wh.id).all()
	# کنترل کسری برای خروج‌ها (اگر allow_negative_stock نباشد)
	for ln in lines:
		if ln.movement == "out":
			# در این نسخه اولیه صرفاً چک نرم (بدون ایندکس کاردکس): اگر quantity<=0 خطا
			if not ln.quantity or Decimal(str(ln.quantity)) <= 0:
				raise ApiError("INVALID_QUANTITY", "Quantity must be positive", http_status=400)

	# محاسبه cogs_amount (ساده)
	for ln in lines:
		qty = Decimal(str(ln.quantity or 0))
		if qty <= 0:
			continue
		if ln.cogs_amount is None:
			unit = Decimal(str((ln.cost_price or 0)))
			if unit <= 0:
				# تلاش برای fallback از extra_info.unit_price
				u = None
				try:
					u = Decimal(str((ln.extra_info or {}).get("unit_price", 0)))
				except Exception:
					u = Decimal(0)
				unit = u
			ln.cogs_amount = unit * qty

	wh.status = "posted"
	wh.touch()
	db.flush()

	# در صورت اتصال به فاکتور، بر اساس نوع فاکتور سطرهای حسابداری ثبت کن
	if wh.source_type == "invoice" and wh.source_document_id:
		inv: Document = db.query(Document).filter(Document.id == int(wh.source_document_id)).first()
		if inv:
			# حساب‌ها
			def get_fixed(db: Session, code: str) -> Account:
				return db.query(Account).filter(and_(Account.business_id == None, Account.code == code)).first()  # noqa: E711
			acc_inventory = get_fixed(db, "10102")
			acc_inventory_finished = get_fixed(db, "10102")
			acc_cogs = get_fixed(db, "40001")
			acc_direct = get_fixed(db, "70406")
			acc_waste = get_fixed(db, "70407")
			acc_wip = get_fixed(db, "10106")
			acc_grni = get_fixed(db, "30101")  # Goods Received Not Invoiced

			inv_type = inv.document_type
			# جمع مبالغ بر اساس حرکت
			out_total = Decimal(0)
			in_total = Decimal(0)
			for ln in lines:
				amt = Decimal(str(ln.cogs_amount or 0))
				if ln.movement == "out":
					out_total += amt
				elif ln.movement == "in":
					in_total += amt

			if inv_type == "invoice_sales":
				if out_total > 0:
					db.add(DocumentLine(document_id=inv.id, account_id=acc_cogs.id, debit=out_total, credit=Decimal(0), description="بهای تمام‌شده (پست حواله فروش)"))
					db.add(DocumentLine(document_id=inv.id, account_id=acc_inventory.id, debit=Decimal(0), credit=out_total, description="خروج موجودی (پست حواله فروش)"))
			elif inv_type == "invoice_sales_return":
				if in_total > 0:
					db.add(DocumentLine(document_id=inv.id, account_id=acc_inventory.id, debit=in_total, credit=Decimal(0), description="ورود موجودی (پست حواله برگشت از فروش)"))
					db.add(DocumentLine(document_id=inv.id, account_id=acc_cogs.id, debit=Decimal(0), credit=in_total, description="تعدیل بهای تمام‌شده (پست حواله برگشت از فروش)"))
			elif inv_type == "invoice_direct_consumption":
				if out_total > 0:
					db.add(DocumentLine(document_id=inv.id, account_id=acc_direct.id, debit=out_total, credit=Decimal(0), description="مصرف مستقیم (پست حواله)"))
					db.add(DocumentLine(document_id=inv.id, account_id=acc_inventory.id, debit=Decimal(0), credit=out_total, description="خروج موجودی (مصرف مستقیم)"))
			elif inv_type == "invoice_waste":
				if out_total > 0:
					db.add(DocumentLine(document_id=inv.id, account_id=acc_waste.id, debit=out_total, credit=Decimal(0), description="ضایعات (پست حواله)"))
					db.add(DocumentLine(document_id=inv.id, account_id=acc_inventory.id, debit=Decimal(0), credit=out_total, description="خروج موجودی (ضایعات)"))
			elif inv_type == "invoice_purchase":
				if in_total > 0:
					db.add(DocumentLine(document_id=inv.id, account_id=acc_inventory.id, debit=in_total, credit=Decimal(0), description="ورود موجودی خرید (پست حواله)"))
					db.add(DocumentLine(document_id=inv.id, account_id=acc_grni.id, debit=Decimal(0), credit=in_total, description="ثبت GRNI خرید"))
			elif inv_type == "invoice_purchase_return":
				if out_total > 0:
					db.add(DocumentLine(document_id=inv.id, account_id=acc_grni.id, debit=out_total, credit=Decimal(0), description="ثبت GRNI برگشت خرید"))
					db.add(DocumentLine(document_id=inv.id, account_id=acc_inventory.id, debit=Decimal(0), credit=out_total, description="خروج موجودی برگشت خرید (پست حواله)"))
			elif inv_type == "invoice_production":
				# مواد مصرفی (out): بدهکار WIP، بستانکار موجودی
				if out_total > 0:
					db.add(DocumentLine(document_id=inv.id, account_id=acc_wip.id, debit=out_total, credit=Decimal(0), description="انتقال مواد به کاردرجریان (پست حواله)"))
					db.add(DocumentLine(document_id=inv.id, account_id=acc_inventory.id, debit=Decimal(0), credit=out_total, description="خروج مواد اولیه (پست حواله)"))
				# کالای ساخته شده (in): بدهکار موجودی ساخته‌شده، بستانکار WIP
				if in_total > 0:
					db.add(DocumentLine(document_id=inv.id, account_id=acc_inventory_finished.id, debit=in_total, credit=Decimal(0), description="ورود کالای ساخته‌شده (پست حواله)"))
					db.add(DocumentLine(document_id=inv.id, account_id=acc_wip.id, debit=Decimal(0), credit=in_total, description="انتقال از کاردرجریان (پست حواله)"))
	return {"id": wh.id, "status": wh.status}


def warehouse_document_to_dict(db: Session, wh: WarehouseDocument) -> Dict[str, Any]:
	lines = db.query(WarehouseDocumentLine).filter(WarehouseDocumentLine.warehouse_document_id == wh.id).all()
	return {
		"id": wh.id,
		"code": wh.code,
		"business_id": wh.business_id,
		"fiscal_year_id": wh.fiscal_year_id,
		"document_date": wh.document_date.isoformat() if wh.document_date else None,
		"status": wh.status,
		"doc_type": wh.doc_type,
		"warehouse_id_from": wh.warehouse_id_from,
		"warehouse_id_to": wh.warehouse_id_to,
		"source_type": wh.source_type,
		"source_document_id": wh.source_document_id,
		"extra_info": wh.extra_info,
		"lines": [
			{
				"id": ln.id,
				"product_id": ln.product_id,
				"warehouse_id": ln.warehouse_id,
				"movement": ln.movement,
				"quantity": float(ln.quantity),
				"cost_price": float(ln.cost_price) if ln.cost_price is not None else None,
				"cogs_amount": float(ln.cogs_amount) if ln.cogs_amount is not None else None,
				"extra_info": ln.extra_info,
			}
			for ln in lines
		],
	}


def _to_dict(obj: Warehouse) -> Dict[str, Any]:
	return {
		"id": obj.id,
		"business_id": obj.business_id,
		"code": obj.code,
		"name": obj.name,
		"description": obj.description,
		"is_default": obj.is_default,
		"created_at": obj.created_at,
		"updated_at": obj.updated_at,
	}


def create_warehouse(db: Session, business_id: int, payload: WarehouseCreateRequest) -> Dict[str, Any]:
	code = payload.code.strip()
	dup = db.query(Warehouse).filter(and_(Warehouse.business_id == business_id, Warehouse.code == code)).first()
	if dup:
		raise ApiError("DUPLICATE_WAREHOUSE_CODE", "کد انبار تکراری است", http_status=400)
	repo = WarehouseRepository(db)
	obj = repo.create(
		business_id=business_id,
		code=code,
		name=payload.name.strip(),
		description=payload.description,
		is_default=bool(payload.is_default),
	)
	if obj.is_default:
		db.query(Warehouse).filter(and_(Warehouse.business_id == business_id, Warehouse.id != obj.id)).update({Warehouse.is_default: False})
		db.commit()
	return {"message": "WAREHOUSE_CREATED", "data": _to_dict(obj)}


def list_warehouses(db: Session, business_id: int) -> Dict[str, Any]:
	repo = WarehouseRepository(db)
	rows = repo.list(business_id)
	return {"items": [_to_dict(w) for w in rows]}


def get_warehouse(db: Session, business_id: int, warehouse_id: int) -> Optional[Dict[str, Any]]:
	obj = db.get(Warehouse, warehouse_id)
	if not obj or obj.business_id != business_id:
		return None
	return _to_dict(obj)


def update_warehouse(db: Session, business_id: int, warehouse_id: int, payload: WarehouseUpdateRequest) -> Optional[Dict[str, Any]]:
	repo = WarehouseRepository(db)
	obj = db.get(Warehouse, warehouse_id)
	if not obj or obj.business_id != business_id:
		return None
	if payload.code and payload.code.strip() != obj.code:
		dup = db.query(Warehouse).filter(and_(Warehouse.business_id == business_id, Warehouse.code == payload.code.strip(), Warehouse.id != warehouse_id)).first()
		if dup:
			raise ApiError("DUPLICATE_WAREHOUSE_CODE", "کد انبار تکراری است", http_status=400)

	updated = repo.update(
		warehouse_id,
		code=payload.code.strip() if isinstance(payload.code, str) else None,
		name=payload.name.strip() if isinstance(payload.name, str) else None,
		description=payload.description,
		is_default=payload.is_default if payload.is_default is not None else None,
	)
	if not updated:
		return None
	if updated.is_default:
		db.query(Warehouse).filter(and_(Warehouse.business_id == business_id, Warehouse.id != updated.id)).update({Warehouse.is_default: False})
		db.commit()
	return {"message": "WAREHOUSE_UPDATED", "data": _to_dict(updated)}


def delete_warehouse(db: Session, business_id: int, warehouse_id: int) -> bool:
	obj = db.get(Warehouse, warehouse_id)
	if not obj or obj.business_id != business_id:
		return False
	repo = WarehouseRepository(db)
	return repo.delete(warehouse_id)


def query_warehouses(db: Session, business_id: int, query_info: QueryInfo) -> Dict[str, Any]:
	# Ensure business scoping via filters
	base_filter = FilterItem(property="business_id", operator="=", value=business_id)
	merged_filters = [base_filter]
	if query_info.filters:
		merged_filters.extend(query_info.filters)

	effective_query = QueryInfo(
		sort_by=query_info.sort_by,
		sort_desc=query_info.sort_desc,
		take=query_info.take,
		skip=query_info.skip,
		search=query_info.search,
		search_fields=query_info.search_fields,
		filters=merged_filters,
	)

	results, total = QueryService.query_with_filters(Warehouse, db, effective_query)
	items = [_to_dict(w) for w in results]
	limit = max(1, effective_query.take)
	page = (effective_query.skip // limit) + 1
	total_pages = (total + limit - 1) // limit

	return {
		"items": items,
		"total": total,
		"page": page,
		"limit": limit,
		"total_pages": total_pages,
	}

