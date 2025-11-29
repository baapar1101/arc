from typing import Dict, Any, List
from fastapi import APIRouter, Depends, Request, Body, Response
from sqlalchemy import and_, or_, exists
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.permissions import require_business_access
from app.core.responses import success_response, ApiError
from adapters.db.models.document import Document
from adapters.db.models.invoice_item_line import InvoiceItemLine
from adapters.db.models.person import Person
from adapters.db.models.warehouse_document import WarehouseDocument
from adapters.db.models.warehouse_document_line import WarehouseDocumentLine
from app.services.invoice_service import (
	INVOICE_SALES,
	INVOICE_SALES_RETURN,
	INVOICE_PURCHASE,
	INVOICE_PURCHASE_RETURN,
	INVOICE_DIRECT_CONSUMPTION,
	INVOICE_PRODUCTION,
	INVOICE_WASTE,
)
from app.services.warehouse_service import create_from_invoice, post_warehouse_document, warehouse_document_to_dict, create_manual_warehouse_document, update_warehouse_document, update_warehouse_document_line, delete_warehouse_document, cancel_warehouse_document, bulk_delete_warehouse_documents


router = APIRouter(prefix="/warehouse-docs", tags=["warehouse_docs"])


_INVOICE_SOURCE_CONFIG: Dict[str, Dict[str, Any]] = {
	"sales": {
		"invoice_types": [INVOICE_SALES],
		"doc_type": "issue",
		"movement": "out",
	},
	"purchase": {
		"invoice_types": [INVOICE_PURCHASE],
		"doc_type": "receipt",
		"movement": "in",
	},
	"sales_return": {
		"invoice_types": [INVOICE_SALES_RETURN],
		"doc_type": "receipt",
		"movement": "in",
	},
	"purchase_return": {
		"invoice_types": [INVOICE_PURCHASE_RETURN],
		"doc_type": "issue",
		"movement": "out",
	},
	"waste": {
		"invoice_types": [INVOICE_WASTE],
		"doc_type": "issue",
		"movement": "out",
	},
	"direct_consumption": {
		"invoice_types": [INVOICE_DIRECT_CONSUMPTION],
		"doc_type": "issue",
		"movement": "out",
	},
	"production": {
		"invoice_types": [INVOICE_PRODUCTION],
		"doc_type": "issue",
		"movement": None,
	},
}


def _resolve_doc_type(invoice_type: str, movement: str | None, override: str | None = None) -> str:
	if override:
		return override
	if movement == "in":
		return "receipt"
	if movement == "out":
		return "issue"
	if invoice_type in (INVOICE_SALES, INVOICE_PURCHASE_RETURN, INVOICE_WASTE, INVOICE_DIRECT_CONSUMPTION):
		return "issue"
	if invoice_type in (INVOICE_PURCHASE, INVOICE_SALES_RETURN):
		return "receipt"
	if invoice_type == INVOICE_PRODUCTION:
		return "issue"
	return "issue"


def _load_invoice_lines(db: Session, invoice_id: int) -> List[Dict[str, Any]]:
	rows = (
		db.query(InvoiceItemLine)
		.filter(InvoiceItemLine.document_id == invoice_id)
		.order_by(InvoiceItemLine.id.asc())
		.all()
	)
	lines: List[Dict[str, Any]] = []
	for row in rows:
		lines.append({
			"product_id": row.product_id,
			"quantity": float(row.quantity or 0),
			"extra_info": row.extra_info or {},
		})
	return lines


@router.get("/business/{business_id}/invoice/{invoice_id}/line-quantities")
@require_business_access("business_id")
def get_invoice_line_quantities(
	request: Request,
	business_id: int,
	invoice_id: int,
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
) -> Dict[str, Any]:
	"""محاسبه مقادیر مورد نیاز، از قبل و باقی مانده برای خطوط فاکتور."""
	if not ctx.has_business_permission("inventory", "read"):
		raise ApiError("FORBIDDEN", "Missing business permission: inventory.read", http_status=403)
	
	inv = db.query(Document).filter(Document.id == invoice_id).first()
	if not inv or inv.business_id != business_id:
		raise ApiError("DOCUMENT_NOT_FOUND", "Invoice document not found", http_status=404)
	
	# بارگذاری خطوط فاکتور
	invoice_lines = _load_invoice_lines(db, invoice_id)
	
	# پیدا کردن حواله‌های مرتبط با فاکتور
	warehouse_docs = db.query(WarehouseDocument).filter(
		and_(
			WarehouseDocument.business_id == business_id,
			WarehouseDocument.source_type == "invoice",
			WarehouseDocument.source_document_id == invoice_id,
		)
	).all()
	
	# محاسبه مقادیر از قبل برای هر محصول
	from decimal import Decimal
	processed_quantities: Dict[int, Decimal] = {}  # product_id -> total processed quantity
	
	for wh_doc in warehouse_docs:
		# فقط حواله‌های posted را در نظر بگیریم
		if wh_doc.status != "posted":
			continue
		
		for wh_line in wh_doc.lines:
			pid = wh_line.product_id
			# فقط خطوط با movement مناسب را در نظر بگیریم
			# برای issue/production_out: movement باید out باشد
			# برای receipt/production_in: movement باید in باشد
			if inv.document_type in (INVOICE_SALES, INVOICE_PURCHASE_RETURN, INVOICE_DIRECT_CONSUMPTION, INVOICE_PRODUCTION, INVOICE_WASTE):
				# خروجی - فقط movement="out" را در نظر بگیریم
				if wh_line.movement == "out":
					processed_quantities[pid] = processed_quantities.get(pid, Decimal(0)) + Decimal(str(wh_line.quantity))
			elif inv.document_type in (INVOICE_PURCHASE, INVOICE_SALES_RETURN):
				# ورودی - فقط movement="in" را در نظر بگیریم
				if wh_line.movement == "in":
					processed_quantities[pid] = processed_quantities.get(pid, Decimal(0)) + Decimal(str(wh_line.quantity))
	
	# ساخت پاسخ برای هر خط فاکتور
	line_quantities = []
	for inv_line in invoice_lines:
		pid = inv_line.get("product_id")
		if not pid:
			continue
		
		required_qty = Decimal(str(inv_line.get("quantity", 0)))
		processed_qty = processed_quantities.get(pid, Decimal(0))
		remaining_qty = required_qty - processed_qty
		
		line_quantities.append({
			"product_id": pid,
			"required_quantity": float(required_qty),
			"processed_quantity": float(processed_qty),
			"remaining_quantity": float(remaining_qty) if remaining_qty > 0 else 0.0,
		})
	
	return success_response(data={"lines": line_quantities}, request=request)


@router.post("/business/{business_id}/from-invoice/{invoice_id}")
@require_business_access("business_id")
def create_warehouse_doc_from_invoice(
	request: Request,
	business_id: int,
	invoice_id: int,
	payload: Dict[str, Any] = Body(default={}),
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
) -> Dict[str, Any]:
	"""ایجاد حواله از فاکتور."""
	if not ctx.has_business_permission("inventory", "write"):
		raise ApiError("FORBIDDEN", "Missing business permission: inventory.write", http_status=403)
	inv = db.query(Document).filter(Document.id == invoice_id).first()
	if not inv or inv.business_id != business_id:
		raise ApiError("DOCUMENT_NOT_FOUND", "Invoice document not found", http_status=404)

	lines = payload.get("lines")
	if not isinstance(lines, list) or not lines:
		lines = _load_invoice_lines(db, invoice_id)
	if not lines:
		raise ApiError("LINES_REQUIRED", "هیچ کالایی برای این فاکتور ثبت نشده است", http_status=400)

	movement_filter = str(payload.get("movement") or "").strip().lower()
	if movement_filter not in ("", "in", "out"):
		movement_filter = ""
	if movement_filter:
		filtered = [
			ln for ln in lines
			if (ln.get("extra_info") or {}).get("movement") == movement_filter
		]
		if not filtered:
			raise ApiError("NO_LINES_FOR_MOVEMENT", "هیچ خطی با حرکت انتخاب‌شده یافت نشد", http_status=400)
		lines = filtered

	doc_type_override = payload.get("doc_type")
	wh_type = _resolve_doc_type(inv.document_type, movement_filter or None, doc_type_override)

	# استخراج فیلدهای ارسال از payload
	extra_data = {
		"description": payload.get("description"),
		"delivery_method": payload.get("delivery_method"),
		"carrier_name": payload.get("carrier_name"),
		"recipient_name": payload.get("recipient_name"),
		"recipient_phone": payload.get("recipient_phone"),
		"tracking_number": payload.get("tracking_number"),
	}
	# حذف فیلدهای None
	extra_data = {k: v for k, v in extra_data.items() if v is not None}

	wh = create_from_invoice(db, business_id, inv, lines, wh_type, ctx.get_user_id(), extra_data if extra_data else None)
	db.commit()
	return success_response(data={"id": wh.id, "code": wh.code, "status": wh.status}, request=request)


@router.post("/business/{business_id}/sources/invoices/search")
@require_business_access("business_id")
def search_invoice_sources_for_warehouse(
	request: Request,
	business_id: int,
	payload: Dict[str, Any] = Body(default={}),
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
) -> Dict[str, Any]:
	"""فهرست فاکتورهایی که می‌توان برای آن‌ها حواله انبار ایجاد کرد."""
	if not ctx.can_read_section("inventory"):
		raise ApiError("FORBIDDEN", "Missing business permission: inventory.read", http_status=403)

	body = payload or {}
	source_key = str(body.get("invoice_type") or "sales").strip().lower()
	cfg = _INVOICE_SOURCE_CONFIG.get(source_key)
	if not cfg:
		raise ApiError("INVALID_INVOICE_TYPE", "نوع فاکتور معتبر نیست", http_status=400)

	def _to_bool(val: Any) -> bool:
		if isinstance(val, bool):
			return val
		if isinstance(val, (int, float)):
			return bool(val)
		if isinstance(val, str):
			return val.strip().lower() in ("1", "true", "yes", "on")
		return False

	try:
		take = int(body.get("take") or 20)
	except Exception:
		take = 20
	take = max(1, min(100, take))

	try:
		skip = int(body.get("skip") or 0)
	except Exception:
		skip = 0
	skip = max(0, skip)

	search_term = str(body.get("search") or "").strip()
	include_completed = _to_bool(body.get("include_completed"))

	q = db.query(Document).filter(
		and_(
			Document.business_id == business_id,
			Document.document_type.in_(cfg["invoice_types"]),
			Document.is_proforma == False,  # noqa: E712
		)
	)

	if search_term:
		pattern = f"%{search_term}%"
		q = q.filter(Document.code.ilike(pattern))

	wh_exists = exists().where(
		and_(
			WarehouseDocument.business_id == business_id,
			WarehouseDocument.source_type == "invoice",
			WarehouseDocument.source_document_id == Document.id,
		)
	)

	wh_non_posted_exists = exists().where(
		and_(
			WarehouseDocument.business_id == business_id,
			WarehouseDocument.source_type == "invoice",
			WarehouseDocument.source_document_id == Document.id,
			WarehouseDocument.status != "posted",
		)
	)

	if not include_completed:
		q = q.filter(or_(~wh_exists, wh_non_posted_exists))

	total = q.count()
	rows = (
		q.order_by(Document.document_date.desc(), Document.id.desc())
		.offset(skip)
		.limit(take)
		.all()
	)

	invoice_ids = [doc.id for doc in rows]
	warehouse_map: Dict[int, List[WarehouseDocument]] = {}
	if invoice_ids:
		wh_rows = (
			db.query(WarehouseDocument)
			.filter(
				and_(
					WarehouseDocument.business_id == business_id,
					WarehouseDocument.source_type == "invoice",
					WarehouseDocument.source_document_id.in_(invoice_ids),
				)
			)
			.all()
		)
		for wh in wh_rows:
			warehouse_map.setdefault(int(wh.source_document_id or 0), []).append(wh)

	person_ids = []
	for doc in rows:
		extra = doc.extra_info or {}
		pid = extra.get("person_id")
		if pid:
			try:
				person_ids.append(int(pid))
			except Exception:
				continue
	person_ids = list({pid for pid in person_ids})
	person_map: Dict[int, str] = {}
	if person_ids:
		person_rows = (
			db.query(Person.id, Person.alias_name, Person.first_name, Person.last_name, Person.company_name)
			.filter(and_(Person.id.in_(person_ids), Person.business_id == business_id))
			.all()
		)
		for prow in person_rows:
			name = prow.alias_name
			if not name:
				parts = filter(None, [getattr(prow, "first_name", None), getattr(prow, "last_name", None)])
				joined = " ".join(parts).strip()
				name = joined or getattr(prow, "company_name", None) or ""
			person_map[int(prow.id)] = name

	items: List[Dict[str, Any]] = []
	for doc in rows:
		extra = doc.extra_info or {}
		person_name = extra.get("person_name")
		person_id = extra.get("person_id")
		if not person_name and person_id:
			try:
				person_name = person_map.get(int(person_id))
			except Exception:
				person_name = None

		totals = extra.get("totals") if isinstance(extra, dict) else None
		net_amount = None
		if isinstance(totals, dict):
			try:
				net_amount = float(totals.get("net") or 0)
			except Exception:
				net_amount = None

		wh_list = warehouse_map.get(doc.id, [])
		statuses = [wh.status for wh in wh_list]
		state = "missing"
		if wh_list:
			has_posted = any(st == "posted" for st in statuses)
			has_draft = any(st == "draft" for st in statuses)
			if has_posted and has_draft:
				state = "partial"
			elif has_posted:
				state = "posted"
			elif has_draft:
				state = "draft"
			else:
				state = statuses[0] or "unknown"

		items.append({
			"invoice_id": doc.id,
			"code": doc.code,
			"document_date": doc.document_date.isoformat(),
			"invoice_type": doc.document_type,
			"person_name": person_name,
			"person_id": person_id,
			"net_amount": net_amount,
			"warehouse_state": state,
			"warehouse_doc_type_hint": cfg.get("doc_type"),
			"warehouse_documents": [
				{
					"id": wh.id,
					"code": wh.code,
					"status": wh.status,
					"doc_type": wh.doc_type,
				}
				for wh in wh_list
			],
		})

	response = {
		"items": items,
		"total": total,
		"take": take,
		"skip": skip,
		"page": (skip // take) + 1,
		"total_pages": (total + take - 1) // take if take else 1,
	}
	return success_response(data=response, request=request)


@router.post("/business/{business_id}/create")
@require_business_access("business_id")
def create_warehouse_doc_manual(
	request: Request,
	business_id: int,
	payload: Dict[str, Any] = Body(...),
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
) -> Dict[str, Any]:
	"""ایجاد حواله انبار دستی."""
	if not ctx.has_business_permission("inventory", "write"):
		raise ApiError("FORBIDDEN", "Missing business permission: inventory.write", http_status=403)
	wh = create_manual_warehouse_document(db, business_id, ctx.get_user_id(), payload)
	db.commit()
	return success_response(data=warehouse_document_to_dict(db, wh), request=request)


@router.post("/business/{business_id}/{wh_id}/post")
@require_business_access("business_id")
def post_warehouse_doc_endpoint(
	request: Request,
	business_id: int,
	wh_id: int,
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
) -> Dict[str, Any]:
	"""پست کردن حواله."""
	if not ctx.has_business_permission("inventory", "write"):
		raise ApiError("FORBIDDEN", "Missing business permission: inventory.write", http_status=403)
	res = post_warehouse_document(db, wh_id)
	db.commit()
	return success_response(data=res, request=request)


@router.get("/business/{business_id}/{wh_id}")
@require_business_access("business_id")
def get_warehouse_doc(
	request: Request,
	business_id: int,
	wh_id: int,
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
) -> Dict[str, Any]:
	"""دریافت جزئیات حواله."""
	if not ctx.can_read_section("inventory"):
		raise ApiError("FORBIDDEN", "Missing business permission: inventory.read", http_status=403)
	wh = db.query(WarehouseDocument).filter(WarehouseDocument.id == wh_id).first()
	if not wh or wh.business_id != business_id:
		raise ApiError("NOT_FOUND", "Warehouse document not found", http_status=404)
	return success_response(data={"item": warehouse_document_to_dict(db, wh)}, request=request)


@router.put("/business/{business_id}/{wh_id}")
@require_business_access("business_id")
def update_warehouse_doc(
	request: Request,
	business_id: int,
	wh_id: int,
	payload: Dict[str, Any] = Body(...),
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
) -> Dict[str, Any]:
	"""ویرایش حواله انبار (فقط draft)."""
	if not ctx.has_business_permission("inventory", "write"):
		raise ApiError("FORBIDDEN", "Missing business permission: inventory.write", http_status=403)
	wh = update_warehouse_document(db, business_id, wh_id, ctx.get_user_id(), payload)
	db.commit()
	return success_response(data=warehouse_document_to_dict(db, wh), request=request)


@router.put("/business/{business_id}/{wh_id}/lines/{line_id}")
@require_business_access("business_id")
def update_warehouse_doc_line(
	request: Request,
	business_id: int,
	wh_id: int,
	line_id: int,
	payload: Dict[str, Any] = Body(...),
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
) -> Dict[str, Any]:
	"""به‌روزرسانی یک خط حواله."""
	if not ctx.has_business_permission("inventory", "write"):
		raise ApiError("FORBIDDEN", "Missing business permission: inventory.write", http_status=403)
	wline = update_warehouse_document_line(db, business_id, wh_id, line_id, payload)
	db.commit()
	return success_response(data={
		"id": wline.id,
		"product_id": wline.product_id,
		"warehouse_id": wline.warehouse_id,
		"movement": wline.movement,
		"quantity": float(wline.quantity),
		"extra_info": wline.extra_info,
	}, request=request)


@router.post("/business/{business_id}/search")
@require_business_access("business_id")
def search_warehouse_docs(
	request: Request,
	business_id: int,
	body: Dict[str, Any] = Body(default={}),
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
) -> Dict[str, Any]:
	"""جستجو و فیلتر حواله‌ها."""
	if not ctx.can_read_section("inventory"):
		raise ApiError("FORBIDDEN", "Missing business permission: inventory.read", http_status=403)
	from app.services.transfer_service import _parse_iso_date as _parse_date
	from sqlalchemy import or_
	
	q = db.query(WarehouseDocument).filter(WarehouseDocument.business_id == business_id)
	
	# فیلتر بر اساس نوع حواله
	doc_type = body.get("doc_type")
	if isinstance(doc_type, str) and doc_type:
		q = q.filter(WarehouseDocument.doc_type == doc_type)
	elif isinstance(doc_type, list):
		if doc_type:
			q = q.filter(WarehouseDocument.doc_type.in_(doc_type))
	
	# فیلتر بر اساس وضعیت
	status = body.get("status")
	if isinstance(status, str) and status:
		q = q.filter(WarehouseDocument.status == status)
	elif isinstance(status, list):
		if status:
			q = q.filter(WarehouseDocument.status.in_(status))
	
	# فیلتر بر اساس source
	source_document_id = body.get("source_document_id")
	if isinstance(source_document_id, int):
		q = q.filter(WarehouseDocument.source_document_id == source_document_id)
	
	source_type = body.get("source_type")
	if isinstance(source_type, str) and source_type:
		q = q.filter(WarehouseDocument.source_type == source_type)
	
	# فیلتر بر اساس تاریخ
	from_date = body.get("from_date")
	to_date = body.get("to_date")
	try:
		if isinstance(from_date, str) and from_date:
			q = q.filter(WarehouseDocument.document_date >= _parse_date(from_date))
		if isinstance(to_date, str) and to_date:
			q = q.filter(WarehouseDocument.document_date <= _parse_date(to_date))
	except Exception:
		pass
	
	# فیلتر بر اساس انبار
	warehouse_id = body.get("warehouse_id")
	warehouse_ids = body.get("warehouse_ids")
	if warehouse_id:
		q = q.filter(
			or_(
				WarehouseDocument.warehouse_id_from == int(warehouse_id),
				WarehouseDocument.warehouse_id_to == int(warehouse_id),
			)
		)
	elif isinstance(warehouse_ids, list) and warehouse_ids:
		wh_ids = [int(w) for w in warehouse_ids if w]
		if wh_ids:
			q = q.filter(
				or_(
					WarehouseDocument.warehouse_id_from.in_(wh_ids),
					WarehouseDocument.warehouse_id_to.in_(wh_ids),
				)
			)
	
	# جستجو در کد
	search = body.get("search")
	if isinstance(search, str) and search.strip():
		search_term = f"%{search.strip()}%"
		q = q.filter(WarehouseDocument.code.like(search_term))
	
	# مرتب‌سازی
	sort_by = body.get("sort_by", "document_date")
	sort_desc = body.get("sort_desc", True)
	if sort_by == "code":
		order_col = WarehouseDocument.code
	elif sort_by == "doc_type":
		order_col = WarehouseDocument.doc_type
	elif sort_by == "status":
		order_col = WarehouseDocument.status
	elif sort_by == "created_at":
		order_col = WarehouseDocument.created_at
	else:
		order_col = WarehouseDocument.document_date
	
	if sort_desc:
		q = q.order_by(order_col.desc(), WarehouseDocument.id.desc())
	else:
		q = q.order_by(order_col.asc(), WarehouseDocument.id.asc())
	
	# Pagination
	take = int(body.get("take") or 20)
	skip = int(body.get("skip") or 0)
	total = q.count()
	items = q.offset(skip).limit(take).all()
	
	return success_response(data={
		"items": [warehouse_document_to_dict(db, wh) for wh in items],
		"total": total,
		"page": (skip // max(1, take)) + 1,
		"limit": take,
		"total_pages": (total + take - 1) // take,
	}, request=request)


@router.delete("/business/{business_id}/{wh_id}")
@require_business_access("business_id")
def delete_warehouse_doc(
	request: Request,
	business_id: int,
	wh_id: int,
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
) -> Dict[str, Any]:
	"""حذف حواله انبار (فقط draft)."""
	if not ctx.has_business_permission("inventory", "delete"):
		raise ApiError("FORBIDDEN", "Missing business permission: inventory.delete", http_status=403)
	deleted = delete_warehouse_document(db, business_id, wh_id)
	db.commit()
	return success_response(data={"deleted": deleted}, request=request)


@router.post("/business/{business_id}/bulk-delete")
@require_business_access("business_id")
def bulk_delete_warehouse_docs(
	request: Request,
	business_id: int,
	payload: Dict[str, Any] = Body(default={}),
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
) -> Dict[str, Any]:
	"""حذف گروهی حواله‌های انبار (فقط draft)."""
	if not ctx.has_business_permission("inventory", "delete"):
		raise ApiError("FORBIDDEN", "Missing business permission: inventory.delete", http_status=403)
	doc_ids = payload.get("ids") or payload.get("doc_ids") or []
	if not isinstance(doc_ids, list) or not doc_ids:
		raise ApiError("INVALID_PAYLOAD", "ids list is required", http_status=400)
	doc_ids = [int(d) for d in doc_ids if d]
	result = bulk_delete_warehouse_documents(db, business_id, doc_ids)
	db.commit()
	return success_response(data=result, request=request)


@router.post("/business/{business_id}/{wh_id}/cancel")
@require_business_access("business_id")
def cancel_warehouse_doc(
	request: Request,
	business_id: int,
	wh_id: int,
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
) -> Dict[str, Any]:
	"""لغو حواله posted با ایجاد حواله معکوس."""
	if not ctx.has_business_permission("inventory", "write"):
		raise ApiError("FORBIDDEN", "Missing business permission: inventory.write", http_status=403)
	cancel_wh = cancel_warehouse_document(db, business_id, wh_id, ctx.get_user_id())
	db.commit()
	return success_response(data=warehouse_document_to_dict(db, cancel_wh), request=request)


@router.get("/business/{business_id}/{wh_id}/pdf")
@require_business_access("business_id")
async def get_warehouse_doc_pdf(
	request: Request,
	business_id: int,
	wh_id: int,
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
) -> Response:
	"""چاپ حواله انبار به صورت PDF."""
	if not ctx.can_read_section("inventory"):
		raise ApiError("FORBIDDEN", "Missing business permission: inventory.read", http_status=403)
	from weasyprint import HTML
	from weasyprint.text.fonts import FontConfiguration
	from app.core.i18n import negotiate_locale
	from html import escape
	import datetime
	import re
	
	wh = db.query(WarehouseDocument).filter(WarehouseDocument.id == wh_id).first()
	if not wh or wh.business_id != business_id:
		raise ApiError("NOT_FOUND", "Warehouse document not found", http_status=404)
	
	# دریافت اطلاعات کامل حواله
	doc_data = warehouse_document_to_dict(db, wh)
	
	# اطلاعات کسب‌وکار
	business_name = ""
	try:
		from adapters.db.models.business import Business
		b = db.query(Business).filter(Business.id == business_id).first()
		if b is not None:
			business_name = b.name or ""
	except Exception:
		business_name = ""
	
	# Locale
	locale = negotiate_locale(request.headers.get("Accept-Language"))
	is_fa = locale == "fa"
	now = datetime.datetime.now().strftime("%Y/%m/%d %H:%M")
	
	# تبدیل تاریخ
	document_date_jalali = None
	if doc_data.get("document_date"):
		try:
			from app.core.calendar import CalendarConverter
			dt = datetime.datetime.fromisoformat(str(doc_data.get("document_date")).replace("Z", "+00:00"))
			formatted = CalendarConverter.format_datetime(dt, "jalali")
			if isinstance(formatted, dict):
				document_date_jalali = formatted.get("formatted") or formatted.get("date_only")
			elif formatted:
				document_date_jalali = str(formatted)
		except Exception:
			document_date_jalali = None
	
	# نام نوع حواله
	doc_type_names = {
		"receipt": "حواله ورود",
		"issue": "حواله خروج",
		"transfer": "انتقال بین انبارها",
		"adjustment": "تعدیل موجودی",
		"production_in": "ورود تولید",
		"production_out": "خروج تولید",
	}
	doc_type_name = doc_type_names.get(doc_data.get("doc_type"), doc_data.get("doc_type", ""))
	
	# نام وضعیت
	status_names = {
		"draft": "پیش‌نویس",
		"posted": "پست شده",
		"cancelled": "لغو شده",
	}
	status_name = status_names.get(doc_data.get("status"), doc_data.get("status", ""))
	
	# اطلاعات انبارها
	warehouse_from_name = ""
	warehouse_to_name = ""
	if doc_data.get("warehouse_id_from"):
		try:
			from adapters.db.models.warehouse import Warehouse
			w = db.query(Warehouse).filter(Warehouse.id == doc_data.get("warehouse_id_from")).first()
			if w:
				warehouse_from_name = f"{w.code} - {w.name}"
		except Exception:
			pass
	if doc_data.get("warehouse_id_to"):
		try:
			from adapters.db.models.warehouse import Warehouse
			w = db.query(Warehouse).filter(Warehouse.id == doc_data.get("warehouse_id_to")).first()
			if w:
				warehouse_to_name = f"{w.code} - {w.name}"
		except Exception:
			pass
	
	# تابع کمکی برای ساخت HTML اطلاعات ارسال
	def _build_delivery_info_html(doc_data: Dict[str, Any]) -> str:
		has_delivery_info = any([
			doc_data.get('description'),
			doc_data.get('delivery_method'),
			doc_data.get('carrier_name'),
			doc_data.get('recipient_name'),
			doc_data.get('recipient_phone'),
			doc_data.get('tracking_number'),
		])
		if not has_delivery_info:
			return ''
		
		delivery_method_names = {
			'warehouse_door': 'تحویل درب انبار',
			'post_regular': 'پست عادی',
			'post_express': 'پست پیشتاز',
			'freight': 'باربری',
			'bus': 'اتوبوس',
			'tipax': 'تیپاکس',
			'courier': 'پیک',
		}
		
		rows = []
		if doc_data.get('description'):
			rows.append(f"<tr><td>شرح/توضیحات:</td><td>{escape(str(doc_data.get('description', '')))}</td></tr>")
		if doc_data.get('delivery_method'):
			method_name = delivery_method_names.get(doc_data.get('delivery_method', ''), doc_data.get('delivery_method', '-'))
			rows.append(f"<tr><td>روش ارسال:</td><td>{escape(method_name)}</td></tr>")
		if doc_data.get('carrier_name'):
			rows.append(f"<tr><td>نام باربری/حمل و نقل:</td><td>{escape(str(doc_data.get('carrier_name', '')))}</td></tr>")
		if doc_data.get('recipient_name'):
			rows.append(f"<tr><td>تحویل گیرنده:</td><td>{escape(str(doc_data.get('recipient_name', '')))}</td></tr>")
		if doc_data.get('recipient_phone'):
			rows.append(f"<tr><td>تلفن تحویل گیرنده:</td><td>{escape(str(doc_data.get('recipient_phone', '')))}</td></tr>")
		if doc_data.get('tracking_number'):
			rows.append(f"<tr><td>شماره پیگیری/بارنامه/قبض:</td><td>{escape(str(doc_data.get('tracking_number', '')))}</td></tr>")
		
		if rows:
			return f'<h3>اطلاعات ارسال:</h3><table class="info-table">{"".join(rows)}</table>'
		return ''
	
	def _to_display_str(value: Any, default: str = "-") -> str:
		if value in (None, ""):
			return default
		if isinstance(value, dict):
			for key in ("formatted", "date_only", "value", "gregorian"):
				date_value = value.get(key)
				if date_value:
					return str(date_value)
			return default
		return str(value)
	
	document_date_display = _to_display_str(document_date_jalali or doc_data.get("document_date"))
	
	# اطلاعات محصولات در خطوط
	lines_data = doc_data.get("lines", [])
	lines_html = ""
	for i, line in enumerate(lines_data, 1):
		product_name = f"محصول {line.get('product_id', '-')}"
		try:
			from adapters.db.models.product import Product
			p = db.query(Product).filter(Product.id == line.get("product_id")).first()
			if p:
				product_name = f"{p.code or ''} - {p.name or ''}".strip(" -")
		except Exception:
			pass
		
		warehouse_name = ""
		if line.get("warehouse_id"):
			try:
				from adapters.db.models.warehouse import Warehouse
				w = db.query(Warehouse).filter(Warehouse.id == line.get("warehouse_id")).first()
				if w:
					warehouse_name = f"{w.code} - {w.name}"
			except Exception:
				pass
		
		movement_name = "ورود" if line.get("movement") == "in" else "خروج"
		quantity = line.get("quantity", 0)
		
		lines_html += f"""
		<tr>
			<td>{i}</td>
			<td>{escape(product_name)}</td>
			<td>{escape(warehouse_name)}</td>
			<td>{escape(movement_name)}</td>
			<td>{quantity}</td>
		</tr>
		"""
	
	# HTML template
	html_content = f"""
	<!DOCTYPE html>
	<html dir="rtl" lang="fa">
	<head>
		<meta charset="UTF-8">
		<style>
			body {{ font-family: 'Tahoma', 'Arial', sans-serif; padding: 20px; direction: rtl; }}
			.header {{ text-align: center; margin-bottom: 30px; }}
			.info-table {{ width: 100%; border-collapse: collapse; margin-bottom: 20px; }}
			.info-table td {{ padding: 8px; border: 1px solid #ddd; }}
			.info-table td:first-child {{ background-color: #f5f5f5; font-weight: bold; width: 150px; }}
			.lines-table {{ width: 100%; border-collapse: collapse; }}
			.lines-table th, .lines-table td {{ padding: 8px; border: 1px solid #ddd; text-align: center; }}
			.lines-table th {{ background-color: #f5f5f5; font-weight: bold; }}
			.footer {{ margin-top: 30px; text-align: center; font-size: 12px; color: #666; }}
		</style>
	</head>
	<body>
		<div class="header">
			<h1>{escape(doc_type_name)}</h1>
			<h2>{escape(business_name)}</h2>
		</div>
		
		<table class="info-table">
			<tr>
				<td>کد حواله:</td>
				<td>{escape(doc_data.get('code', '-'))}</td>
			</tr>
			<tr>
				<td>نوع حواله:</td>
				<td>{escape(doc_type_name)}</td>
			</tr>
			<tr>
				<td>تاریخ:</td>
				<td>{escape(document_date_display)}</td>
			</tr>
			<tr>
				<td>وضعیت:</td>
				<td>{escape(status_name)}</td>
			</tr>
			{('<tr><td>انبار مبدا:</td><td>' + escape(warehouse_from_name) + '</td></tr>') if warehouse_from_name else ''}
			{('<tr><td>انبار مقصد:</td><td>' + escape(warehouse_to_name) + '</td></tr>') if warehouse_to_name else ''}
		</table>
		
		<!-- اطلاعات ارسال -->
		{_build_delivery_info_html(doc_data)}
		
		<h3>خطوط حواله:</h3>
		<table class="lines-table">
			<thead>
				<tr>
					<th>ردیف</th>
					<th>محصول</th>
					<th>انبار</th>
					<th>نوع حرکت</th>
					<th>تعداد</th>
				</tr>
			</thead>
			<tbody>
				{lines_html}
			</tbody>
		</table>
		
		<div class="footer">
			<p>تولید شده در: {now}</p>
		</div>
	</body>
	</html>
	"""
	
	# تولید PDF
	try:
		pdf_bytes = HTML(string=html_content).write_pdf(font_config=FontConfiguration())
	except Exception as e:
		import logging
		logger = logging.getLogger(__name__)
		logger.error(f"PDF generation failed: {e}", exc_info=True)
		raise ApiError("PDF_GENERATION_ERROR", "خطا در تولید فایل PDF", http_status=500)
	
	def _slugify(text: str) -> str:
		return re.sub(r"[^A-Za-z0-9_-]+", "_", (text or "")).strip("_") or "warehouse_doc"
	
	filename = f"warehouse_doc_{_slugify(doc_data.get('code', ''))}_{datetime.datetime.now().strftime('%Y%m%d_%H%M%S')}.pdf"
	
	return Response(
		content=pdf_bytes,
		media_type="application/pdf",
		headers={
			"Content-Disposition": f"attachment; filename={filename}",
			"Content-Length": str(len(pdf_bytes)),
			"Access-Control-Expose-Headers": "Content-Disposition",
		},
	)


