from typing import Dict, Any
from fastapi import APIRouter, Depends, Request, Body
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.permissions import require_business_access
from app.core.responses import success_response
from adapters.db.models.document import Document
from adapters.db.models.warehouse_document import WarehouseDocument
from adapters.db.models.warehouse_document_line import WarehouseDocumentLine
from app.services.warehouse_service import create_from_invoice, post_warehouse_document, warehouse_document_to_dict


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
	inv = db.query(Document).filter(Document.id == invoice_id).first()
	if not inv or inv.business_id != business_id:
		from app.core.responses import ApiError
		raise ApiError("DOCUMENT_NOT_FOUND", "Invoice document not found", http_status=404)
	lines = payload.get("lines") or []
	wh_type = payload.get("doc_type") or ("issue" if inv.document_type in ("invoice_sales", "invoice_purchase_return", "invoice_waste", "invoice_direct_consumption") else "receipt")
	wh = create_from_invoice(db, business_id, inv, lines, wh_type, ctx.get_user_id())
	db.commit()
	return success_response(data={"id": wh.id, "code": wh.code, "status": wh.status}, request=request)


@router.post("/business/{business_id}/{wh_id}/post")
@require_business_access("business_id")
def post_warehouse_doc_endpoint(
	request: Request,
	business_id: int,
	wh_id: int,
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
) -> Dict[str, Any]:
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
	wh = db.query(WarehouseDocument).filter(WarehouseDocument.id == wh_id).first()
	if not wh or wh.business_id != business_id:
		from app.core.responses import ApiError
		raise ApiError("NOT_FOUND", "Warehouse document not found", http_status=404)
	return success_response(data={"item": warehouse_document_to_dict(db, wh)}, request=request)


@router.post("/business/{business_id}/search")
@require_business_access("business_id")
def search_warehouse_docs(
	request: Request,
	business_id: int,
	body: Dict[str, Any] = Body(default={}),
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
) -> Dict[str, Any]:
	q = db.query(WarehouseDocument).filter(WarehouseDocument.business_id == business_id)
	# فیلتر ساده بر اساس نوع/وضعیت/تاریخ
	doc_type = body.get("doc_type")
	status = body.get("status")
	source_document_id = body.get("source_document_id")
	source_type = body.get("source_type")
	from_date = body.get("from_date")
	to_date = body.get("to_date")
	try:
		if isinstance(doc_type, str) and doc_type:
			q = q.filter(WarehouseDocument.doc_type == doc_type)
		if isinstance(status, str) and status:
			q = q.filter(WarehouseDocument.status == status)
		if isinstance(source_document_id, int):
			q = q.filter(WarehouseDocument.source_document_id == source_document_id)
		if isinstance(source_type, str) and source_type:
			q = q.filter(WarehouseDocument.source_type == source_type)
		if isinstance(from_date, str) and from_date:
			from app.services.transfer_service import _parse_iso_date as _p
			q = q.filter(WarehouseDocument.document_date >= _p(from_date))
		if isinstance(to_date, str) and to_date:
			from app.services.transfer_service import _parse_iso_date as _p
			q = q.filter(WarehouseDocument.document_date <= _p(to_date))
	except Exception:
		pass
	q = q.order_by(WarehouseDocument.document_date.desc(), WarehouseDocument.id.desc())
	take = int(body.get("take") or 20)
	skip = int(body.get("skip") or 0)
	total = q.count()
	items = q.offset(skip).limit(take).all()
	return success_response(data={
		"items": [warehouse_document_to_dict(db, wh) for wh in items],
		"total": total,
		"page": (skip // max(1, take)) + 1,
		"limit": take,
	}, request=request)


