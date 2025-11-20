from typing import Dict, Any
from fastapi import APIRouter, Depends, Request, Body, Response
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.permissions import require_business_access
from app.core.responses import success_response
from adapters.db.models.document import Document
from adapters.db.models.warehouse_document import WarehouseDocument
from adapters.db.models.warehouse_document_line import WarehouseDocumentLine
from app.services.warehouse_service import create_from_invoice, post_warehouse_document, warehouse_document_to_dict, create_manual_warehouse_document, update_warehouse_document, update_warehouse_document_line, delete_warehouse_document, cancel_warehouse_document


router = APIRouter(prefix="/warehouse-docs", tags=["warehouse_docs"])


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
		from app.core.responses import ApiError
		raise ApiError("FORBIDDEN", "Missing business permission: inventory.write", http_status=403)
	inv = db.query(Document).filter(Document.id == invoice_id).first()
	if not inv or inv.business_id != business_id:
		from app.core.responses import ApiError
		raise ApiError("DOCUMENT_NOT_FOUND", "Invoice document not found", http_status=404)
	lines = payload.get("lines") or []
	wh_type = payload.get("doc_type") or ("issue" if inv.document_type in ("invoice_sales", "invoice_purchase_return", "invoice_waste", "invoice_direct_consumption") else "receipt")
	wh = create_from_invoice(db, business_id, inv, lines, wh_type, ctx.get_user_id())
	db.commit()
	return success_response(data={"id": wh.id, "code": wh.code, "status": wh.status}, request=request)


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
		from app.core.responses import ApiError
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
		from app.core.responses import ApiError
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
		from app.core.responses import ApiError
		raise ApiError("FORBIDDEN", "Missing business permission: inventory.read", http_status=403)
	wh = db.query(WarehouseDocument).filter(WarehouseDocument.id == wh_id).first()
	if not wh or wh.business_id != business_id:
		from app.core.responses import ApiError
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
		from app.core.responses import ApiError
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
		from app.core.responses import ApiError
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
		from app.core.responses import ApiError
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
		from app.core.responses import ApiError
		raise ApiError("FORBIDDEN", "Missing business permission: inventory.delete", http_status=403)
	deleted = delete_warehouse_document(db, business_id, wh_id)
	db.commit()
	return success_response(data={"deleted": deleted}, request=request)


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
		from app.core.responses import ApiError
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
		from app.core.responses import ApiError
		raise ApiError("FORBIDDEN", "Missing business permission: inventory.read", http_status=403)
	from weasyprint import HTML
	from weasyprint.text.fonts import FontConfiguration
	from app.core.i18n import negotiate_locale
	from html import escape
	import datetime
	import re
	
	wh = db.query(WarehouseDocument).filter(WarehouseDocument.id == wh_id).first()
	if not wh or wh.business_id != business_id:
		from app.core.responses import ApiError
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
			document_date_jalali = formatted if formatted else None
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
				<td>{escape(document_date_jalali or doc_data.get('document_date', '-'))}</td>
			</tr>
			<tr>
				<td>وضعیت:</td>
				<td>{escape(status_name)}</td>
			</tr>
			{('<tr><td>انبار مبدا:</td><td>' + escape(warehouse_from_name) + '</td></tr>') if warehouse_from_name else ''}
			{('<tr><td>انبار مقصد:</td><td>' + escape(warehouse_to_name) + '</td></tr>') if warehouse_to_name else ''}
		</table>
		
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
		from app.core.responses import ApiError
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


