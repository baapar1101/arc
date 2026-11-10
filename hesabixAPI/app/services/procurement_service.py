"""عملیات افزونه تدارکات روی شخص، فاکتور خرید، رسید انبار و بودجه تعهدی."""
from __future__ import annotations

import hashlib
import json
import logging
import secrets
from datetime import date, datetime, timedelta
from decimal import Decimal
from typing import Any, Dict, List, Optional, Sequence

from sqlalchemy.orm import Session

from adapters.db.models.person import Person
from adapters.db.models.procurement import (
	ProcApproval,
	ProcBudget,
	ProcBudgetMovement,
	ProcCommitment,
	ProcContract,
	ProcContractLine,
	ProcCostCenter,
	ProcDelegation,
	ProcGuarantee,
	ProcInvoiceLink,
	ProcMatchLine,
	ProcOrder,
	ProcOrderLine,
	ProcPortalInvoice,
	ProcPrepayment,
	ProcReceipt,
	ProcReceiptLine,
	ProcReorderSuggestion,
	ProcRequisition,
	ProcRequisitionLine,
	ProcScore,
	ProcSettings,
	ProcShareLink,
	ProcSourcingBid,
	ProcSourcingBidLine,
	ProcSourcingEvent,
	ProcSourcingInvite,
	ProcSourcingLine,
	ProcSupplierDocument,
	ProcSupplierProfile,
)
from adapters.db.models.product import Product
from adapters.db.models.product_supplier import ProductSupplier
from app.core.responses import ApiError
from app.services.activity_log_service import log_activity
from app.services.document_numbering_service import generate_document_code
from app.services.procurement_domain import (
	D,
	QTY,
	aggregate_match,
	budget_available,
	compare_bids,
	covered_by_stock,
	line_amount,
	match_line,
	money,
	qty,
	suggested_buy_qty,
	supplier_score,
)

logger = logging.getLogger(__name__)

_OPEN_ORDER = ("approved", "sent", "partial", "received", "invoiced")
_RECEIPT_ORDER = ("approved", "sent", "partial", "received")


def _num(value: Any) -> Optional[float]:
	if value is None:
		return None
	return float(D(value))


def _json_safe(value: Any) -> Any:
	if isinstance(value, Decimal):
		return float(value)
	if isinstance(value, dict):
		return {key: _json_safe(item) for key, item in value.items()}
	if isinstance(value, list):
		return [_json_safe(item) for item in value]
	return value


def _budget_warn(budget: ProcBudget, increases: Decimal, transfer_in: Decimal, transfer_out: Decimal, available: Decimal) -> bool:
	"""هشدار وقتی سهم مصرف‌شده به آستانه برسد؛ ۸۰ یعنی پس از مصرف ۸۰ درصد."""
	base = D(budget.amount) + increases + transfer_in - transfer_out
	if base <= 0:
		return available < 0
	consumed = base - available
	return consumed >= base * D(budget.warn_percent or 80) / D(100)


def _iso(value: Any) -> Optional[str]:
	if value is None:
		return None
	return value.isoformat() if hasattr(value, "isoformat") else str(value)


def _today() -> date:
	return date.today()


def _code(db: Session, business_id: int, document_type: str, on: Optional[date] = None) -> str:
	return generate_document_code(db, business_id, document_type, on or _today())


def _owned_file_ids(db: Session, business_id: int, raw: Any) -> List[str]:
	ids: List[str] = []
	for item in list(raw or []):
		file_id = str(item or "").strip()
		if file_id and file_id not in ids:
			ids.append(file_id)
	if not ids:
		return []
	from adapters.db.models.file_storage import FileStorage

	found = {
		row[0]
		for row in db.query(FileStorage.id)
		.filter(
			FileStorage.id.in_(ids),
			FileStorage.business_id == int(business_id),
			FileStorage.deleted_at.is_(None),
			FileStorage.is_active.is_(True),
		)
		.all()
	}
	if any(file_id not in found for file_id in ids):
		raise ApiError("FILE_NOT_FOUND", "پیوست باید فایل فعال همین کسب‌وکار باشد.", http_status=400)
	return ids


def _owned_file_id(db: Session, business_id: int, raw: Any) -> Optional[str]:
	if raw is None or str(raw).strip() == "":
		return None
	return _owned_file_ids(db, business_id, [raw])[0]


def _audit(db: Session, user_id: int, business_id: int, action: str, entity_type: str, entity_id: int, description: str, after: Optional[dict] = None) -> None:
	log_activity(
		db,
		user_id=user_id,
		business_id=business_id,
		category="procurement",
		action=action,
		entity_type=entity_type,
		entity_id=entity_id,
		description=description,
		after_data=after,
	)


def _emit(db: Session, business_id: int, user_id: int, trigger: str, data: Dict[str, Any]) -> None:
	try:
		from app.services.workflow.workflow_trigger_service import trigger_workflows

		trigger_workflows(db, business_id, trigger, data, user_id=user_id)
	except Exception:
		logger.exception("procurement trigger failed type=%s", trigger)


def _load_person(db: Session, business_id: int, person_id: int) -> Person:
	person = (
		db.query(Person)
		.filter(Person.id == int(person_id), Person.business_id == int(business_id))
		.first()
	)
	if not person:
		raise ApiError("SUPPLIER_NOT_FOUND", "تأمین‌کننده در اشخاص این کسب‌وکار پیدا نشد.", http_status=404)
	raw = person.person_types or "[]"
	try:
		types = json.loads(raw) if isinstance(raw, str) else list(raw)
	except (TypeError, ValueError):
		types = []
	if "تامین‌کننده" not in types and "تأمین‌کننده" not in types:
		raise ApiError("NOT_A_SUPPLIER", "این شخص به‌عنوان تأمین‌کننده ثبت نشده است.", http_status=400)
	return person


def _settings(db: Session, business_id: int) -> ProcSettings:
	row = db.query(ProcSettings).filter(ProcSettings.business_id == int(business_id)).first()
	if row:
		return row
	row = ProcSettings(business_id=int(business_id), mode="standard", allow_direct_po=False, require_approved_supplier=True)
	db.add(row)
	db.flush()
	return row


def _profile(db: Session, business_id: int, person_id: int) -> Optional[ProcSupplierProfile]:
	return (
		db.query(ProcSupplierProfile)
		.filter(ProcSupplierProfile.business_id == int(business_id), ProcSupplierProfile.person_id == int(person_id))
		.first()
	)


def _assert_can_order(db: Session, business_id: int, person_id: int) -> ProcSettings:
	settings = _settings(db, business_id)
	_load_person(db, business_id, person_id)
	profile = _profile(db, business_id, person_id)
	needs_approval = settings.mode != "small" or bool(settings.require_approved_supplier)
	if needs_approval:
		if not profile or profile.status != "approved":
			raise ApiError("SUPPLIER_NOT_APPROVED", "سفارش فقط برای تأمین‌کننده مجاز ممکن است.", http_status=400)
	elif profile and profile.status in {"suspended", "ended"}:
		raise ApiError("SUPPLIER_BLOCKED", "همکاری با این تأمین‌کننده متوقف شده است.", http_status=400)
	if profile:
		expired = (
			db.query(ProcSupplierDocument)
			.filter(
				ProcSupplierDocument.business_id == int(business_id),
				ProcSupplierDocument.profile_id == profile.id,
				ProcSupplierDocument.expires_on.isnot(None),
				ProcSupplierDocument.expires_on < _today(),
			)
			.first()
		)
		if expired:
			raise ApiError("SUPPLIER_DOCUMENT_EXPIRED", f"مدرک «{expired.title}» منقضی شده است.", http_status=400)
	return settings


def _lines_of(db: Session, order_id: int) -> List[ProcOrderLine]:
	return db.query(ProcOrderLine).filter(ProcOrderLine.order_id == int(order_id)).order_by(ProcOrderLine.sort_order, ProcOrderLine.id).all()


def _req_lines(db: Session, requisition_id: int) -> List[ProcRequisitionLine]:
	return (
		db.query(ProcRequisitionLine)
		.filter(ProcRequisitionLine.requisition_id == int(requisition_id))
		.order_by(ProcRequisitionLine.sort_order, ProcRequisitionLine.id)
		.all()
	)


def _order_total(order: ProcOrder, lines: Sequence[ProcOrderLine]) -> Any:
	total = D(0)
	active_found = False
	for line in lines:
		original = D(line.qty)
		active = original - D(line.cancelled_qty) - D(line.rejected_qty)
		if active <= 0 or original <= 0:
			continue
		active_found = True
		ratio = active / original
		total += line_amount(active, line.unit_price, D(line.discount) * ratio, D(line.tax) * ratio)
	if not active_found:
		return money(0)
	return money(total + D(order.freight) - D(order.header_discount))


def _open_product_qty(db: Session, business_id: int, product_id: int) -> Any:
	rows = (
		db.query(ProcOrderLine)
		.join(ProcOrder, ProcOrder.id == ProcOrderLine.order_id)
		.filter(
			ProcOrder.business_id == int(business_id),
			ProcOrder.status.in_(_OPEN_ORDER),
			ProcOrderLine.product_id == int(product_id),
		)
		.all()
	)
	total = D(0)
	for line in rows:
		total += D(line.qty) - D(line.cancelled_qty) - D(line.accepted_qty)
	return qty(total if total > 0 else 0)


def _stock(db: Session, business_id: int, product_id: int) -> Any:
	from app.services.invoice_service import get_financial_stock_bulk

	found = get_financial_stock_bulk(db, int(business_id), [int(product_id)])
	return qty(found.get(int(product_id), 0))


def _require_money_refs(db: Session, business_id: int, payload: Dict[str, Any]) -> None:
	if payload.get("budget_id"):
		budget = db.query(ProcBudget).filter(ProcBudget.id == int(payload["budget_id"]), ProcBudget.business_id == int(business_id)).first()
		if not budget:
			raise ApiError("BUDGET_NOT_FOUND", "ردیف بودجه در این کسب‌وکار پیدا نشد.", http_status=404)
	if payload.get("cost_center_id"):
		center = db.query(ProcCostCenter).filter(ProcCostCenter.id == int(payload["cost_center_id"]), ProcCostCenter.business_id == int(business_id)).first()
		if not center:
			raise ApiError("COST_CENTER_NOT_FOUND", "مرکز هزینه در این کسب‌وکار پیدا نشد.", http_status=404)
	if payload.get("project_id"):
		from adapters.db.models.project import Project

		project = db.query(Project).filter(Project.id == int(payload["project_id"]), Project.business_id == int(business_id)).first()
		if not project:
			raise ApiError("PROJECT_NOT_FOUND", "پروژه در این کسب‌وکار پیدا نشد.", http_status=404)


def _kind_from_product(db: Session, business_id: int, product_id: Any) -> str:
	if not product_id:
		return "service"
	from adapters.db.models.product import ProductItemType

	product = db.query(Product).filter(Product.id == int(product_id), Product.business_id == int(business_id)).first()
	if not product:
		return "service"
	raw = getattr(product.item_type, "value", product.item_type)
	if str(raw) == ProductItemType.SERVICE.value:
		return "service"
	return "goods"


def _tracks_stock(db: Session, business_id: int, product_id: Any) -> bool:
	if not product_id:
		return False
	product = db.query(Product).filter(Product.id == int(product_id), Product.business_id == int(business_id)).first()
	return bool(product and product.track_inventory)


def _require_warehouse(db: Session, business_id: int, warehouse_id: int) -> None:
	from adapters.db.models.warehouse import Warehouse

	row = db.query(Warehouse).filter(Warehouse.id == int(warehouse_id), Warehouse.business_id == int(business_id)).first()
	if not row:
		raise ApiError("WAREHOUSE_NOT_FOUND", "انبار در این کسب‌وکار پیدا نشد.", http_status=404)


def _parse_item_rows(db: Session, business_id: int, rows: Any) -> List[Dict[str, Any]]:
	if not isinstance(rows, list) or not rows:
		raise ApiError("LINES_REQUIRED", "حداقل یک قلم لازم است.", http_status=400)
	out: List[Dict[str, Any]] = []
	for index, row in enumerate(rows):
		if not isinstance(row, dict):
			raise ApiError("INVALID_LINE", "قلم نامعتبر است.", http_status=400)
		quantity = D(row.get("qty"))
		if quantity <= 0:
			raise ApiError("INVALID_QTY", "مقدار باید بزرگ‌تر از صفر باشد.", http_status=400)
		description = str(row.get("description") or "").strip()
		product_id = row.get("product_id")
		if not description and not product_id:
			raise ApiError("LINE_DESCRIPTION_REQUIRED", "شرح یا کالا لازم است.", http_status=400)
		kind = str(row.get("item_kind") or "goods")
		if kind not in {"goods", "service"}:
			raise ApiError("INVALID_ITEM_KIND", "نوع قلم باید کالا یا خدمت باشد.", http_status=400)
		out.append(
			{
				"product_id": int(product_id) if product_id else None,
				"description": description or f"قلم {index + 1}",
				"item_kind": kind,
				"qty": quantity,
				"uom": row.get("uom"),
				"unit_price": D(row.get("unit_price") if row.get("unit_price") is not None else row.get("unit_price_estimate") or 0),
				"discount": D(row.get("discount") or 0),
				"tax": D(row.get("tax") or 0),
				"warehouse_id": int(row["warehouse_id"]) if row.get("warehouse_id") else None,
				"requisition_line_id": int(row["requisition_line_id"]) if row.get("requisition_line_id") else None,
				"sort_order": index,
			}
		)
	for item in out:
		if item["product_id"]:
			product = db.query(Product).filter(Product.id == int(item["product_id"]), Product.business_id == int(business_id)).first()
			if not product:
				raise ApiError("PRODUCT_NOT_FOUND", "کالا در این کسب‌وکار پیدا نشد.", http_status=404)
		if item["warehouse_id"]:
			_require_warehouse(db, business_id, int(item["warehouse_id"]))
		if item["discount"] - (item["qty"] * item["unit_price"]) > MONEY_EPS():
			raise ApiError("DISCOUNT_EXCEEDS_LINE", "تخفیف قلم از مبلغ آن بیشتر است.", http_status=400)
	return out


def _serialize_settings(row: ProcSettings) -> Dict[str, Any]:
	return {
		"mode": row.mode,
		"qty_tolerance_pct": _num(row.qty_tolerance_pct),
		"price_tolerance": _num(row.price_tolerance),
		"budget_required": bool(row.budget_required),
		"allow_direct_po": bool(row.allow_direct_po),
		"require_approved_supplier": bool(row.require_approved_supplier),
		"budget_warn_percent": int(row.budget_warn_percent or 80),
		"default_approver_user_id": row.default_approver_user_id,
		"weights": row.weights or {},
	}


def get_settings(db: Session, business_id: int) -> Dict[str, Any]:
	return _serialize_settings(_settings(db, business_id))


def update_settings(db: Session, business_id: int, payload: Dict[str, Any], user_id: int) -> Dict[str, Any]:
	row = _settings(db, business_id)
	if payload.get("mode") in {"small", "standard", "enterprise"}:
		row.mode = payload["mode"]
		if payload["mode"] == "small":
			if "allow_direct_po" not in payload:
				row.allow_direct_po = True
			if "require_approved_supplier" not in payload:
				row.require_approved_supplier = False
		else:
			if "allow_direct_po" not in payload:
				row.allow_direct_po = False
			if "require_approved_supplier" not in payload:
				row.require_approved_supplier = True
		if payload["mode"] == "enterprise" and "budget_required" not in payload:
			row.budget_required = True
	for key in ("qty_tolerance_pct", "price_tolerance", "budget_warn_percent", "default_approver_user_id"):
		if key in payload:
			setattr(row, key, payload[key])
	for key in ("budget_required", "allow_direct_po", "require_approved_supplier"):
		if key in payload:
			setattr(row, key, bool(payload[key]))
	if isinstance(payload.get("weights"), dict):
		row.weights = payload["weights"]
	row.updated_at = datetime.utcnow()
	db.flush()
	_audit(db, user_id, business_id, "update", "proc_settings", row.id, "تنظیمات تدارکات به‌روز شد")
	return _serialize_settings(row)


def _serialize_profile(row: ProcSupplierProfile) -> Dict[str, Any]:
	return {
		"id": row.id,
		"person_id": row.person_id,
		"status": row.status,
		"category": row.category,
		"payment_terms": row.payment_terms,
		"payment_days": row.payment_days,
		"risk_score": _num(row.risk_score),
		"notes": row.notes,
	}


def list_suppliers(db: Session, business_id: int, status: Optional[str] = None) -> Dict[str, Any]:
	query = db.query(ProcSupplierProfile).filter(ProcSupplierProfile.business_id == int(business_id))
	if status:
		query = query.filter(ProcSupplierProfile.status == status)
	rows = query.order_by(ProcSupplierProfile.id.desc()).all()
	return {"items": [_serialize_profile(row) for row in rows], "total": len(rows)}


def upsert_supplier(db: Session, business_id: int, payload: Dict[str, Any], user_id: int) -> Dict[str, Any]:
	person_id = int(payload["person_id"])
	_load_person(db, business_id, person_id)
	row = _profile(db, business_id, person_id)
	status = str(payload.get("status") or (row.status if row else "prospective"))
	if status not in {"prospective", "review", "approved", "suspended", "ended"}:
		raise ApiError("INVALID_SUPPLIER_STATUS", "وضعیت تأمین‌کننده نامعتبر است.", http_status=400)
	if not row:
		row = ProcSupplierProfile(business_id=int(business_id), person_id=person_id, status=status)
		db.add(row)
	row.status = status
	row.category = payload.get("category", row.category)
	row.payment_terms = payload.get("payment_terms", row.payment_terms)
	if payload.get("payment_days") is not None:
		row.payment_days = int(payload["payment_days"])
	if "risk_score" in payload:
		row.risk_score = payload.get("risk_score")
	if "notes" in payload:
		row.notes = payload.get("notes")
	row.updated_at = datetime.utcnow()
	db.flush()
	_audit(db, user_id, business_id, "update", "proc_supplier", row.id, "پرونده تأمین‌کننده ذخیره شد", _serialize_profile(row))
	return _serialize_profile(row)


def add_supplier_document(db: Session, business_id: int, profile_id: int, payload: Dict[str, Any], user_id: int) -> Dict[str, Any]:
	profile = db.query(ProcSupplierProfile).filter(ProcSupplierProfile.id == int(profile_id), ProcSupplierProfile.business_id == int(business_id)).first()
	if not profile:
		raise ApiError("SUPPLIER_NOT_FOUND", "پرونده تأمین‌کننده پیدا نشد.", http_status=404)
	title = str(payload.get("title") or "").strip()
	if not title:
		raise ApiError("TITLE_REQUIRED", "عنوان مدرک لازم است.", http_status=400)
	row = ProcSupplierDocument(
		business_id=int(business_id),
		profile_id=profile.id,
		title=title,
		doc_type=str(payload.get("doc_type") or "other"),
		expires_on=_parse_date(payload.get("expires_on")),
		file_id=_owned_file_id(db, business_id, payload.get("file_id")),
		notes=payload.get("notes"),
	)
	db.add(row)
	db.flush()
	_audit(db, user_id, business_id, "create", "proc_supplier_document", row.id, "مدرک تأمین‌کننده ثبت شد")
	return {"id": row.id, "title": row.title, "expires_on": _iso(row.expires_on), "file_id": row.file_id}


def list_supplier_documents(db: Session, business_id: int, profile_id: int) -> Dict[str, Any]:
	rows = (
		db.query(ProcSupplierDocument)
		.filter(ProcSupplierDocument.business_id == int(business_id), ProcSupplierDocument.profile_id == int(profile_id))
		.order_by(ProcSupplierDocument.id.desc())
		.all()
	)
	return {
		"items": [
			{"id": row.id, "title": row.title, "doc_type": row.doc_type, "expires_on": _iso(row.expires_on), "file_id": row.file_id, "notes": row.notes}
			for row in rows
		]
	}


def list_cost_centers(db: Session, business_id: int) -> Dict[str, Any]:
	rows = db.query(ProcCostCenter).filter(ProcCostCenter.business_id == int(business_id)).order_by(ProcCostCenter.code).all()
	return {"items": [{"id": row.id, "code": row.code, "name": row.name, "is_active": row.is_active} for row in rows]}


def create_cost_center(db: Session, business_id: int, payload: Dict[str, Any], user_id: int) -> Dict[str, Any]:
	code = str(payload.get("code") or "").strip()
	name = str(payload.get("name") or "").strip()
	if not code or not name:
		raise ApiError("COST_CENTER_REQUIRED", "کد و نام مرکز هزینه لازم است.", http_status=400)
	taken = db.query(ProcCostCenter).filter(ProcCostCenter.business_id == int(business_id), ProcCostCenter.code == code).first()
	if taken:
		raise ApiError("COST_CENTER_EXISTS", "این کد مرکز هزینه قبلاً ثبت شده است.", http_status=400)
	row = ProcCostCenter(business_id=int(business_id), code=code, name=name)
	db.add(row)
	db.flush()
	_audit(db, user_id, business_id, "create", "proc_cost_center", row.id, "مرکز هزینه ایجاد شد")
	return {"id": row.id, "code": row.code, "name": row.name, "is_active": True}


def create_delegation(db: Session, business_id: int, payload: Dict[str, Any], user_id: int) -> Dict[str, Any]:
	approver_id = int(payload["user_id"])
	delegate_id = int(payload["delegate_user_id"])
	if approver_id == delegate_id:
		raise ApiError("DELEGATION_SELF", "تأییدکننده نمی‌تواند جانشین خودش باشد.", http_status=400)
	ends_at = _parse_dt(payload.get("ends_at"))
	if ends_at and ends_at < datetime.utcnow():
		raise ApiError("DELEGATION_EXPIRED", "پایان جانشینی نمی‌تواند در گذشته باشد.", http_status=400)
	row = ProcDelegation(
		business_id=int(business_id),
		user_id=approver_id,
		delegate_user_id=delegate_id,
		ends_at=ends_at,
	)
	db.add(row)
	db.flush()
	_audit(db, user_id, business_id, "create", "proc_delegation", row.id, "جانشین تأییدکننده ثبت شد")
	return {"id": row.id, "user_id": row.user_id, "delegate_user_id": row.delegate_user_id, "ends_at": _iso(row.ends_at)}


def _parse_date(value: Any) -> Optional[date]:
	if not value:
		return None
	if isinstance(value, date) and not isinstance(value, datetime):
		return value
	text = str(value)[:10]
	return date.fromisoformat(text)


def _parse_dt(value: Any) -> Optional[datetime]:
	if not value:
		return None
	if isinstance(value, datetime):
		return value
	text = str(value).replace("Z", "")
	return datetime.fromisoformat(text)


def preview_demand(db: Session, business_id: int, payload: Dict[str, Any]) -> Dict[str, Any]:
	needed = D(payload.get("qty") or 0)
	product_id = payload.get("product_id")
	on_hand = D(0)
	open_qty = D(0)
	if product_id:
		on_hand = D(_stock(db, business_id, int(product_id)))
		open_qty = D(_open_product_qty(db, business_id, int(product_id)))
	return {
		"on_hand": _num(on_hand),
		"open_qty": _num(open_qty),
		"covered": bool(product_id) and covered_by_stock(needed=needed, on_hand=on_hand, open_qty=open_qty),
		"suggested_qty": _num(suggested_buy_qty(on_hand=on_hand, open_qty=open_qty, reorder_point=payload.get("reorder_point") or 0, min_order_qty=payload.get("min_order_qty") or 0)) if product_id else 0,
	}


def _serialize_req(db: Session, row: ProcRequisition) -> Dict[str, Any]:
	lines = _req_lines(db, row.id)
	return {
		"id": row.id,
		"code": row.code,
		"status": row.status,
		"requester_user_id": row.requester_user_id,
		"org_unit_name": row.org_unit_name,
		"project_id": row.project_id,
		"cost_center_id": row.cost_center_id,
		"needed_by": _iso(row.needed_by),
		"priority": row.priority,
		"reason": row.reason,
		"description": row.description,
		"currency_id": row.currency_id,
		"suggested_budget": _num(row.suggested_budget),
		"source": row.source,
		"duplicate_risk": bool(row.duplicate_risk),
		"duplicate_ack": bool(row.duplicate_ack),
		"file_ids": row.file_ids or [],
		"approvals": _approval_rows(db, row.business_id, "requisition", row.id),
		"lines": [
			{
				"id": line.id,
				"product_id": line.product_id,
				"description": line.description,
				"item_kind": line.item_kind,
				"qty": _num(line.qty),
				"uom": line.uom,
				"unit_price_estimate": _num(line.unit_price_estimate),
				"warehouse_id": line.warehouse_id,
				"on_hand_snapshot": _num(line.on_hand_snapshot),
				"open_po_snapshot": _num(line.open_po_snapshot),
			}
			for line in lines
		],
	}


def list_requisitions(db: Session, business_id: int, status: Optional[str] = None, limit: int = 100, skip: int = 0) -> Dict[str, Any]:
	query = db.query(ProcRequisition).filter(ProcRequisition.business_id == int(business_id))
	if status:
		query = query.filter(ProcRequisition.status == status)
	total = query.count()
	rows = query.order_by(ProcRequisition.id.desc()).offset(int(skip)).limit(int(limit)).all()
	return {"items": [_serialize_req(db, row) for row in rows], "total": total}


def get_requisition(db: Session, business_id: int, requisition_id: int) -> Dict[str, Any]:
	return _serialize_req(db, _require_req(db, business_id, requisition_id))


def _require_req(db: Session, business_id: int, requisition_id: int) -> ProcRequisition:
	row = db.query(ProcRequisition).filter(ProcRequisition.id == int(requisition_id), ProcRequisition.business_id == int(business_id)).first()
	if not row:
		raise ApiError("REQUISITION_NOT_FOUND", "درخواست خرید پیدا نشد.", http_status=404)
	return row


def _demand_snapshots(db: Session, business_id: int, items: Sequence[Dict[str, Any]]) -> tuple[bool, List[Dict[str, Any]]]:
	risk = False
	snapshots: List[Dict[str, Any]] = []
	for item in items:
		snap = {"on_hand": None, "open_qty": None}
		if item["product_id"]:
			preview = preview_demand(db, business_id, {"product_id": item["product_id"], "qty": item["qty"]})
			snap = {"on_hand": preview["on_hand"], "open_qty": preview["open_qty"]}
			if preview["covered"]:
				risk = True
		snapshots.append(snap)
	return risk, snapshots


def _require_duplicate_ack(payload: Dict[str, Any], risk: bool) -> None:
	if risk and not payload.get("acknowledge_duplicate"):
		raise ApiError("DUPLICATE_BUY_RISK", "موجودی و سفارش باز این نیاز را می‌پوشاند. برای ادامه، خرید را صریحاً تأیید کنید.", http_status=400)


def create_requisition(db: Session, business_id: int, payload: Dict[str, Any], user_id: int) -> Dict[str, Any]:
	items = _parse_item_rows(db, business_id, payload.get("lines"))
	_require_money_refs(db, business_id, payload)
	risk, snapshots = _demand_snapshots(db, business_id, items)
	_require_duplicate_ack(payload, risk)
	row = ProcRequisition(
		business_id=int(business_id),
		code=_code(db, business_id, "proc_requisition"),
		requester_user_id=int(user_id),
		org_unit_name=payload.get("org_unit_name"),
		project_id=payload.get("project_id"),
		cost_center_id=payload.get("cost_center_id"),
		needed_by=_parse_date(payload.get("needed_by")),
		priority=str(payload.get("priority") or "normal"),
		reason=payload.get("reason"),
		description=payload.get("description"),
		currency_id=payload.get("currency_id"),
		suggested_budget=payload.get("suggested_budget"),
		source=str(payload.get("source") or "manual"),
		duplicate_risk=risk,
		duplicate_ack=bool(payload.get("acknowledge_duplicate")),
		file_ids=_owned_file_ids(db, business_id, payload.get("file_ids")),
	)
	db.add(row)
	db.flush()
	for item, snap in zip(items, snapshots):
		db.add(
			ProcRequisitionLine(
				requisition_id=row.id,
				product_id=item["product_id"],
				description=item["description"],
				item_kind=item["item_kind"],
				qty=item["qty"],
				uom=item["uom"],
				unit_price_estimate=item["unit_price"],
				warehouse_id=item["warehouse_id"],
				on_hand_snapshot=snap["on_hand"],
				open_po_snapshot=snap["open_qty"],
				sort_order=item["sort_order"],
			)
		)
	db.flush()
	_audit(db, user_id, business_id, "create", "proc_requisition", row.id, f"درخواست {row.code} ثبت شد")
	_emit(db, business_id, user_id, "procurement.requisition.created", {"id": row.id, "code": row.code})
	return _serialize_req(db, row)


def update_requisition(db: Session, business_id: int, requisition_id: int, payload: Dict[str, Any], user_id: int) -> Dict[str, Any]:
	row = _require_req(db, business_id, requisition_id)
	if row.status not in {"draft", "returned"}:
		raise ApiError("REQUISITION_LOCKED", "فقط پیش‌نویس یا درخواست برگشتی قابل ویرایش است.", http_status=400)
	for key in ("org_unit_name", "reason", "description", "priority"):
		if key in payload:
			setattr(row, key, payload[key])
	if "needed_by" in payload:
		row.needed_by = _parse_date(payload.get("needed_by"))
	if "file_ids" in payload:
		row.file_ids = _owned_file_ids(db, business_id, payload.get("file_ids"))
	if payload.get("lines") is not None:
		items = _parse_item_rows(db, business_id, payload.get("lines"))
		risk, snapshots = _demand_snapshots(db, business_id, items)
		_require_duplicate_ack(payload, risk)
		row.duplicate_risk = risk
		row.duplicate_ack = bool(payload.get("acknowledge_duplicate"))
		db.query(ProcRequisitionLine).filter(ProcRequisitionLine.requisition_id == row.id).delete()
		for item, snap in zip(items, snapshots):
			db.add(
				ProcRequisitionLine(
					requisition_id=row.id,
					product_id=item["product_id"],
					description=item["description"],
					item_kind=item["item_kind"],
					qty=item["qty"],
					uom=item["uom"],
					unit_price_estimate=item["unit_price"],
					warehouse_id=item["warehouse_id"],
					on_hand_snapshot=snap["on_hand"],
					open_po_snapshot=snap["open_qty"],
					sort_order=item["sort_order"],
				)
			)
	row.updated_at = datetime.utcnow()
	db.flush()
	_audit(db, user_id, business_id, "update", "proc_requisition", row.id, f"درخواست {row.code} ویرایش شد")
	return _serialize_req(db, row)


def _replace_approvals(db: Session, business_id: int, entity_type: str, entity_id: int, approver_ids: Sequence[Any], position_id: Optional[int]) -> None:
	db.query(ProcApproval).filter(
		ProcApproval.business_id == int(business_id),
		ProcApproval.entity_type == entity_type,
		ProcApproval.entity_id == int(entity_id),
		ProcApproval.status == "pending",
	).delete()
	ids = [int(item) for item in approver_ids if item]
	if not ids:
		ids = [None]
	for index, approver in enumerate(ids, start=1):
		db.add(
			ProcApproval(
				business_id=int(business_id),
				entity_type=entity_type,
				entity_id=int(entity_id),
				step_no=index,
				approver_user_id=approver,
				position_id=int(position_id) if position_id and index == 1 else None,
			)
		)
	db.flush()


def _approval_rows(db: Session, business_id: int, entity_type: str, entity_id: int) -> List[Dict[str, Any]]:
	rows = (
		db.query(ProcApproval)
		.filter(ProcApproval.business_id == int(business_id), ProcApproval.entity_type == entity_type, ProcApproval.entity_id == int(entity_id))
		.order_by(ProcApproval.step_no)
		.all()
	)
	return [
		{
			"id": row.id,
			"step_no": row.step_no,
			"approver_user_id": row.approver_user_id,
			"position_id": row.position_id,
			"status": row.status,
			"note": row.note,
			"acted_by_user_id": row.acted_by_user_id,
			"acted_at": _iso(row.acted_at),
		}
		for row in rows
	]


def _actor_allowed(db: Session, business_id: int, user_id: int, step: ProcApproval) -> bool:
	if step.approver_user_id is None and step.position_id is None:
		return True
	if step.approver_user_id and int(step.approver_user_id) == int(user_id):
		return True
	now = datetime.utcnow()
	if step.approver_user_id:
		delegation = (
			db.query(ProcDelegation)
			.filter(
				ProcDelegation.business_id == int(business_id),
				ProcDelegation.user_id == int(step.approver_user_id),
				ProcDelegation.delegate_user_id == int(user_id),
				ProcDelegation.is_active.is_(True),
			)
			.first()
		)
		if delegation and delegation.starts_at <= now and (delegation.ends_at is None or delegation.ends_at >= now):
			return True
	if step.position_id:
		try:
			from sqlalchemy import or_

			from adapters.db.models.office_automation import OaDelegation, OaPositionHolder

			holder = (
				db.query(OaPositionHolder)
				.filter(
					OaPositionHolder.business_id == int(business_id),
					OaPositionHolder.position_id == int(step.position_id),
					OaPositionHolder.user_id == int(user_id),
					OaPositionHolder.is_active.is_(True),
					OaPositionHolder.starts_at <= now,
					or_(OaPositionHolder.ends_at.is_(None), OaPositionHolder.ends_at >= now),
				)
				.first()
			)
			if holder:
				return True
			delegation = (
				db.query(OaDelegation)
				.filter(
					OaDelegation.business_id == int(business_id),
					OaDelegation.position_id == int(step.position_id),
					OaDelegation.delegate_user_id == int(user_id),
					OaDelegation.is_active.is_(True),
					OaDelegation.scope == "full",
					OaDelegation.starts_at <= now,
					or_(OaDelegation.ends_at.is_(None), OaDelegation.ends_at >= now),
				)
				.first()
			)
			if delegation:
				return True
		except Exception:
			logger.exception("oa position lookup failed")
	return False


def submit_requisition(db: Session, business_id: int, requisition_id: int, payload: Dict[str, Any], user_id: int) -> Dict[str, Any]:
	row = _require_req(db, business_id, requisition_id)
	if row.status not in {"draft", "returned"}:
		raise ApiError("REQUISITION_NOT_SUBMITTABLE", "این درخواست قابل ارسال برای تأیید نیست.", http_status=400)
	if not _req_lines(db, row.id):
		raise ApiError("LINES_REQUIRED", "درخواست بدون قلم قابل ارسال نیست.", http_status=400)
	settings = _settings(db, business_id)
	approvers = list(payload.get("approver_user_ids") or [])
	if not approvers and settings.default_approver_user_id:
		approvers = [settings.default_approver_user_id]
	_replace_approvals(db, business_id, "requisition", row.id, approvers, payload.get("position_id"))
	row.status = "pending_approval"
	row.updated_at = datetime.utcnow()
	db.flush()
	_audit(db, user_id, business_id, "submit", "proc_requisition", row.id, f"درخواست {row.code} برای تأیید ارسال شد")
	return get_requisition(db, business_id, row.id)


def decide(db: Session, business_id: int, entity_type: str, entity_id: int, action: str, note: Optional[str], user_id: int) -> Dict[str, Any]:
	if action not in {"approve", "reject", "return"}:
		raise ApiError("INVALID_DECISION", "تصمیم نامعتبر است.", http_status=400)
	if action in {"reject", "return"} and not str(note or "").strip():
		raise ApiError("NOTE_REQUIRED", "دلیل رد یا برگشت لازم است.", http_status=400)
	step = (
		db.query(ProcApproval)
		.filter(
			ProcApproval.business_id == int(business_id),
			ProcApproval.entity_type == entity_type,
			ProcApproval.entity_id == int(entity_id),
			ProcApproval.status == "pending",
		)
		.order_by(ProcApproval.step_no)
		.first()
	)
	if not step:
		raise ApiError("NO_PENDING_APPROVAL", "گام تأیید بازی وجود ندارد.", http_status=400)
	if not _actor_allowed(db, business_id, user_id, step):
		raise ApiError("NOT_THE_APPROVER", "این گام برای شما نیست.", http_status=403)
	previous = step.status
	step.note = note
	step.acted_by_user_id = int(user_id)
	step.acted_at = datetime.utcnow()
	step.status = {"approve": "approved", "reject": "rejected", "return": "returned"}[action]
	try:
		if action == "approve":
			nxt = (
				db.query(ProcApproval)
				.filter(
					ProcApproval.business_id == int(business_id),
					ProcApproval.entity_type == entity_type,
					ProcApproval.entity_id == int(entity_id),
					ProcApproval.status == "pending",
					ProcApproval.id != step.id,
				)
				.first()
			)
			if not nxt:
				_apply_approved(db, business_id, entity_type, entity_id, user_id)
		else:
			_apply_negative(db, business_id, entity_type, entity_id, action, user_id)
		db.flush()
	except Exception:
		step.status = previous
		step.note = None
		step.acted_by_user_id = None
		step.acted_at = None
		raise
	pending = (
		db.query(ProcApproval)
		.filter(
			ProcApproval.business_id == int(business_id),
			ProcApproval.entity_type == entity_type,
			ProcApproval.entity_id == int(entity_id),
			ProcApproval.status == "pending",
		)
		.first()
	)
	if action == "approve":
		return {"status": "pending_approval" if pending else "approved", "entity_type": entity_type, "entity_id": entity_id}
	return {"status": "returned" if action == "return" else "rejected", "entity_type": entity_type, "entity_id": entity_id}


def _apply_approved(db: Session, business_id: int, entity_type: str, entity_id: int, user_id: int) -> None:
	if entity_type == "requisition":
		row = _require_req(db, business_id, entity_id)
		row.status = "approved"
		_audit(db, user_id, business_id, "approve", "proc_requisition", row.id, f"درخواست {row.code} تأیید شد")
		_emit(db, business_id, user_id, "procurement.requisition.approved", {"id": row.id, "code": row.code})
	elif entity_type == "order":
		order = _require_order(db, business_id, entity_id)
		_assert_can_order(db, business_id, order.person_id)
		_commit_order_budget(db, business_id, order, user_id)
		order.status = "approved"
		_audit(db, user_id, business_id, "approve", "proc_order", order.id, f"سفارش {order.code} تأیید شد")
		_emit(db, business_id, user_id, "procurement.order.approved", {"id": order.id, "code": order.code})
	elif entity_type == "budget_movement":
		movement = _require_movement(db, business_id, entity_id)
		if movement.kind == "transfer_out":
			source = db.query(ProcBudget).filter(ProcBudget.id == int(movement.budget_id), ProcBudget.business_id == int(business_id)).first()
			if not source:
				raise ApiError("BUDGET_NOT_FOUND", "ردیف بودجه مبدأ پیدا نشد.", http_status=404)
			if D(_budget_figures(db, source)["available"]) < -MONEY_EPS():
				raise ApiError("BUDGET_EXCEEDED", "مانده مبدأ برای تأیید انتقال کافی نیست.", http_status=400)
		movement.status = "approved"
		movement.acted_by_user_id = int(user_id)
		pair = _movement_pair(db, business_id, movement, "pending")
		if pair:
			pair.status = "approved"
			pair.acted_by_user_id = int(user_id)
		_audit(db, user_id, business_id, "approve", "proc_budget_movement", movement.id, "حرکت بودجه تأیید شد")
	db.flush()


def _cancel_pending_steps(db: Session, business_id: int, entity_type: str, entity_id: int) -> None:
	now = datetime.utcnow()
	rows = (
		db.query(ProcApproval)
		.filter(
			ProcApproval.business_id == int(business_id),
			ProcApproval.entity_type == entity_type,
			ProcApproval.entity_id == int(entity_id),
			ProcApproval.status == "pending",
		)
		.all()
	)
	for row in rows:
		row.status = "cancelled"
		row.acted_at = now


def _apply_negative(db: Session, business_id: int, entity_type: str, entity_id: int, action: str, user_id: int) -> None:
	status = "returned" if action == "return" else "rejected"
	_cancel_pending_steps(db, business_id, entity_type, entity_id)
	if entity_type == "requisition":
		row = _require_req(db, business_id, entity_id)
		row.status = status
		_audit(db, user_id, business_id, action, "proc_requisition", row.id, f"درخواست {row.code} {row.status} شد")
	elif entity_type == "order":
		order = _require_order(db, business_id, entity_id)
		order.status = "draft" if action == "return" else "cancelled"
		if action == "reject":
			_reopen_requisition(db, order)
		_audit(db, user_id, business_id, action, "proc_order", order.id, f"سفارش {order.code} {order.status} شد")
	elif entity_type == "budget_movement":
		movement = _require_movement(db, business_id, entity_id)
		movement.status = status
		movement.acted_by_user_id = int(user_id)
		pair = _movement_pair(db, business_id, movement, "pending")
		if pair:
			pair.status = status
			pair.acted_by_user_id = int(user_id)
	db.flush()


def _movement_pair(db: Session, business_id: int, movement: ProcBudgetMovement, status: str) -> Optional[ProcBudgetMovement]:
	if not movement.counter_budget_id or movement.kind != "transfer_out":
		return None
	return (
		db.query(ProcBudgetMovement)
		.filter(
			ProcBudgetMovement.business_id == int(business_id),
			ProcBudgetMovement.budget_id == movement.counter_budget_id,
			ProcBudgetMovement.counter_budget_id == movement.budget_id,
			ProcBudgetMovement.kind == "transfer_in",
			ProcBudgetMovement.status == status,
		)
		.first()
	)


def _require_order(db: Session, business_id: int, order_id: int) -> ProcOrder:
	row = db.query(ProcOrder).filter(ProcOrder.id == int(order_id), ProcOrder.business_id == int(business_id)).first()
	if not row:
		raise ApiError("ORDER_NOT_FOUND", "سفارش خرید پیدا نشد.", http_status=404)
	return row


def _require_movement(db: Session, business_id: int, movement_id: int) -> ProcBudgetMovement:
	row = db.query(ProcBudgetMovement).filter(ProcBudgetMovement.id == int(movement_id), ProcBudgetMovement.business_id == int(business_id)).first()
	if not row:
		raise ApiError("MOVEMENT_NOT_FOUND", "حرکت بودجه پیدا نشد.", http_status=404)
	return row


def _budget_figures(db: Session, budget: ProcBudget) -> Dict[str, Any]:
	movements = db.query(ProcBudgetMovement).filter(ProcBudgetMovement.budget_id == budget.id, ProcBudgetMovement.status == "approved").all()
	increases = sum((D(row.amount) for row in movements if row.kind == "increase"), D(0))
	transfer_in = sum((D(row.amount) for row in movements if row.kind == "transfer_in"), D(0))
	transfer_out = sum((D(row.amount) for row in movements if row.kind == "transfer_out"), D(0))
	actuals = sum((D(row.amount) for row in movements if row.kind == "actual"), D(0))
	pending_out = sum(
		(
			D(row.amount)
			for row in db.query(ProcBudgetMovement).filter(
				ProcBudgetMovement.budget_id == budget.id,
				ProcBudgetMovement.status == "pending",
				ProcBudgetMovement.kind == "transfer_out",
			).all()
		),
		D(0),
	)
	commitments = db.query(ProcCommitment).filter(ProcCommitment.budget_id == budget.id).all()
	open_commitments = sum((D(row.amount) - D(row.released_amount) for row in commitments), D(0))
	available = budget_available(budget.amount, increases, transfer_in, transfer_out, open_commitments, actuals) - pending_out
	return {
		"id": budget.id,
		"name": budget.name,
		"period_key": budget.period_key,
		"amount": _num(budget.amount),
		"increases": _num(increases),
		"transfer_in": _num(transfer_in),
		"transfer_out": _num(transfer_out),
		"pending_transfers": _num(pending_out),
		"actuals": _num(actuals),
		"open_commitments": _num(open_commitments),
		"available": _num(available),
		"warn": _budget_warn(budget, increases, transfer_in, transfer_out, available),
		"org_unit_name": budget.org_unit_name,
		"project_id": budget.project_id,
		"cost_center_id": budget.cost_center_id,
	}


def _commit_order_budget(db: Session, business_id: int, order: ProcOrder, user_id: int) -> None:
	settings = _settings(db, business_id)
	total = _order_total(order, _lines_of(db, order.id))
	if total < 0:
		raise ApiError("NEGATIVE_ORDER_TOTAL", "مبلغ سفارش منفی است.", http_status=400)
	if not order.budget_id:
		if settings.budget_required:
			raise ApiError("BUDGET_REQUIRED", "برای تأیید سفارش باید ردیف بودجه انتخاب شود.", http_status=400)
		return
	budget = db.query(ProcBudget).filter(ProcBudget.id == int(order.budget_id), ProcBudget.business_id == int(business_id)).first()
	if not budget:
		raise ApiError("BUDGET_NOT_FOUND", "ردیف بودجه پیدا نشد.", http_status=404)
	figures_available = D(_budget_figures(db, budget)["available"])
	existing = db.query(ProcCommitment).filter(ProcCommitment.order_id == order.id).first()
	already = D(existing.amount) - D(existing.released_amount) if existing else D(0)
	if figures_available + already + QTY < total:
		raise ApiError("BUDGET_EXCEEDED", "مانده بودجه برای این تعهد کافی نیست.", http_status=400)
	if existing:
		existing.amount = total
	else:
		db.add(ProcCommitment(business_id=int(business_id), budget_id=budget.id, order_id=order.id, amount=total, released_amount=0))
	db.flush()
	_audit(db, user_id, business_id, "commit", "proc_commitment", order.id, f"تعهد بودجه سفارش {order.code} ثبت شد", {"amount": _num(total)})


def _requisition_line_for_order(db: Session, order: ProcOrder, raw: Any) -> Optional[int]:
	if not raw:
		return None
	row = (
		db.query(ProcRequisitionLine)
		.join(ProcRequisition, ProcRequisition.id == ProcRequisitionLine.requisition_id)
		.filter(ProcRequisitionLine.id == int(raw), ProcRequisition.business_id == int(order.business_id))
		.first()
	)
	if not row or not order.requisition_id or int(row.requisition_id) != int(order.requisition_id):
		raise ApiError("REQUISITION_LINE_MISMATCH", "قلم درخواست به این سفارش وصل نیست.", http_status=400)
	return int(row.id)


def _add_order_lines(db: Session, order: ProcOrder, items: Sequence[Dict[str, Any]], requisition_line_ids: Optional[Sequence[Optional[int]]] = None, contract_line_ids: Optional[Sequence[Optional[int]]] = None) -> None:
	if requisition_line_ids is None:
		requisition_line_ids = [item.get("requisition_line_id") for item in items]
	for index, item in enumerate(items):
		db.add(
			ProcOrderLine(
				order_id=order.id,
				product_id=item["product_id"],
				description=item["description"],
				item_kind=item["item_kind"],
				qty=item["qty"],
				uom=item["uom"],
				unit_price=item["unit_price"],
				discount=item["discount"],
				tax=item["tax"],
				warehouse_id=item["warehouse_id"],
				requisition_line_id=_requisition_line_for_order(db, order, requisition_line_ids[index] if requisition_line_ids else None),
				contract_line_id=(contract_line_ids[index] if contract_line_ids else None),
				sort_order=item["sort_order"],
			)
		)
	db.flush()
	_assert_discounts(order, _lines_of(db, order.id))


def _new_order(db: Session, business_id: int, user_id: int, person_id: int, payload: Dict[str, Any]) -> ProcOrder:
	_assert_can_order(db, business_id, person_id)
	_require_money_refs(db, business_id, payload)
	order = ProcOrder(
		business_id=int(business_id),
		code=_code(db, business_id, "proc_order"),
		person_id=int(person_id),
		requisition_id=payload.get("requisition_id"),
		sourcing_event_id=payload.get("sourcing_event_id"),
		contract_id=payload.get("contract_id"),
		budget_id=payload.get("budget_id"),
		project_id=payload.get("project_id"),
		cost_center_id=payload.get("cost_center_id"),
		currency_id=payload.get("currency_id"),
		payment_terms=payload.get("payment_terms"),
		delivery_date=_parse_date(payload.get("delivery_date")),
		delivery_place=payload.get("delivery_place"),
		warranty=payload.get("warranty"),
		freight=D(payload.get("freight") or 0),
		header_discount=D(payload.get("header_discount") or 0),
		notes=payload.get("notes"),
		file_ids=_owned_file_ids(db, business_id, payload.get("file_ids")),
		created_by_user_id=int(user_id),
	)
	db.add(order)
	db.flush()
	return order


def _reopen_requisition(db: Session, order: ProcOrder) -> None:
	if order.status != "cancelled" or not order.requisition_id:
		return
	if any(D(line.received_qty) > QTY for line in _lines_of(db, order.id)):
		return
	other = (
		db.query(ProcOrder)
		.filter(
			ProcOrder.business_id == order.business_id,
			ProcOrder.requisition_id == order.requisition_id,
			ProcOrder.id != order.id,
			ProcOrder.status != "cancelled",
		)
		.first()
	)
	if other:
		return
	requisition = _require_req(db, order.business_id, int(order.requisition_id))
	if requisition.status == "converted":
		requisition.status = "approved"


def create_order(db: Session, business_id: int, payload: Dict[str, Any], user_id: int) -> Dict[str, Any]:
	settings = _settings(db, business_id)
	if payload.get("requisition_id") or payload.get("contract_id") or payload.get("sourcing_event_id"):
		raise ApiError("ORDER_SOURCE_PATH", "سفارش درخواست از تبدیل، سفارش قرارداد از آزادسازی و سفارش استعلام از اعطا ساخته می‌شود.", http_status=400)
	if not settings.allow_direct_po:
		raise ApiError("DIRECT_PO_DISABLED", "سفارش مستقیم در این حالت کسب‌وکار بسته است.", http_status=400)
	items = _parse_item_rows(db, business_id, payload.get("lines"))
	order = _new_order(db, business_id, user_id, int(payload["person_id"]), payload)
	_add_order_lines(db, order, items)
	_audit(db, user_id, business_id, "create", "proc_order", order.id, f"سفارش {order.code} ایجاد شد")
	return get_order(db, business_id, order.id)


def create_order_from_requisition(db: Session, business_id: int, requisition_id: int, payload: Dict[str, Any], user_id: int) -> Dict[str, Any]:
	req = _require_req(db, business_id, requisition_id)
	if req.status != "approved":
		raise ApiError("REQUISITION_NOT_APPROVED", "فقط درخواست تأییدشده به سفارش تبدیل می‌شود.", http_status=400)
	if (
		db.query(ProcSourcingEvent)
		.filter(
			ProcSourcingEvent.business_id == int(business_id),
			ProcSourcingEvent.requisition_id == req.id,
			ProcSourcingEvent.status != "cancelled",
		)
		.first()
	):
		raise ApiError("REQUISITION_IN_SOURCING", "برای این درخواست استعلام باز وجود دارد.", http_status=400)
	person_id = int(payload["person_id"])
	lines = _req_lines(db, req.id)
	items = [
		{
			"product_id": line.product_id,
			"description": line.description,
			"item_kind": line.item_kind,
			"qty": D(line.qty),
			"uom": line.uom,
			"unit_price": D(payload.get("unit_price") or line.unit_price_estimate or 0),
			"discount": D(0),
			"tax": D(0),
			"warehouse_id": line.warehouse_id,
			"sort_order": line.sort_order,
		}
		for line in lines
	]
	body = dict(payload)
	body["requisition_id"] = req.id
	body.setdefault("project_id", req.project_id)
	body.setdefault("cost_center_id", req.cost_center_id)
	body.setdefault("currency_id", req.currency_id)
	order = _new_order(db, business_id, user_id, person_id, body)
	_add_order_lines(db, order, items, [line.id for line in lines])
	req.status = "converted"
	db.flush()
	_audit(db, user_id, business_id, "convert", "proc_order", order.id, f"سفارش {order.code} از درخواست {req.code} ساخته شد")
	return get_order(db, business_id, order.id)


def _serialize_order(db: Session, order: ProcOrder) -> Dict[str, Any]:
	lines = _lines_of(db, order.id)
	receipts = db.query(ProcReceipt).filter(ProcReceipt.order_id == order.id).order_by(ProcReceipt.id).all()
	receipt_ids = [row.id for row in receipts]
	receipt_lines = (
		db.query(ProcReceiptLine).filter(ProcReceiptLine.receipt_id.in_(receipt_ids)).order_by(ProcReceiptLine.id).all()
		if receipt_ids
		else []
	)
	lines_by_receipt: Dict[int, List[Dict[str, Any]]] = {}
	for item in receipt_lines:
		lines_by_receipt.setdefault(item.receipt_id, []).append(
			{
				"id": item.id,
				"order_line_id": item.order_line_id,
				"qty": _num(item.qty),
				"rejected_qty": _num(item.rejected_qty),
				"qc_status": item.qc_status,
			}
		)
	links = db.query(ProcInvoiceLink).filter(ProcInvoiceLink.order_id == order.id).all()
	notices = db.query(ProcPortalInvoice).filter(ProcPortalInvoice.order_id == order.id).all()
	prepayments = db.query(ProcPrepayment).filter(ProcPrepayment.order_id == order.id).all()
	share_links = (
		db.query(ProcShareLink)
		.filter(ProcShareLink.business_id == order.business_id, ProcShareLink.entity_id == order.id, ProcShareLink.kind.in_(["order", "invoice"]))
		.order_by(ProcShareLink.id.desc())
		.all()
	)
	return {
		"id": order.id,
		"code": order.code,
		"status": order.status,
		"person_id": order.person_id,
		"requisition_id": order.requisition_id,
		"sourcing_event_id": order.sourcing_event_id,
		"contract_id": order.contract_id,
		"budget_id": order.budget_id,
		"project_id": order.project_id,
		"cost_center_id": order.cost_center_id,
		"currency_id": order.currency_id,
		"payment_terms": order.payment_terms,
		"delivery_date": _iso(order.delivery_date),
		"delivery_place": order.delivery_place,
		"warranty": order.warranty,
		"freight": _num(order.freight),
		"header_discount": _num(order.header_discount),
		"notes": order.notes,
		"version": order.version,
		"file_ids": order.file_ids or [],
		"supplier_acknowledged_at": _iso(order.supplier_acknowledged_at),
		"total": _num(_order_total(order, lines)),
		"lines": [
			{
				"id": line.id,
				"product_id": line.product_id,
				"description": line.description,
				"item_kind": line.item_kind,
				"qty": _num(line.qty),
				"uom": line.uom,
				"unit_price": _num(line.unit_price),
				"discount": _num(line.discount),
				"tax": _num(line.tax),
				"warehouse_id": line.warehouse_id,
				"requisition_line_id": line.requisition_line_id,
				"received_qty": _num(line.received_qty),
				"accepted_qty": _num(line.accepted_qty),
				"rejected_qty": _num(line.rejected_qty),
				"invoiced_qty": _num(line.invoiced_qty),
				"cancelled_qty": _num(line.cancelled_qty),
				"service_confirmed": bool(line.service_confirmed),
				"open_qty": _num(D(line.qty) - D(line.cancelled_qty) - D(line.accepted_qty)),
			}
			for line in lines
		],
		"receipts": [
			{
				"id": row.id,
				"received_on": _iso(row.received_on),
				"warehouse_document_id": row.warehouse_document_id,
				"warehouse_document_ids": list(row.warehouse_document_ids or ([row.warehouse_document_id] if row.warehouse_document_id else [])),
				"note": row.note,
				"lines": lines_by_receipt.get(row.id, []),
			}
			for row in receipts
		],
		"invoices": [{"id": row.id, "document_id": row.document_id, "match_status": row.match_status, "price_variance_accepted": row.price_variance_accepted} for row in links],
		"portal_invoices": [{"id": row.id, "reference": row.reference, "amount": _num(row.amount), "note": row.note, "status": row.status} for row in notices],
		"prepayments": [{"id": row.id, "document_id": row.document_id, "amount": _num(row.amount)} for row in prepayments],
		"share_links": [{"id": row.id, "kind": row.kind, "expires_at": _iso(row.expires_at), "revoked": row.revoked_at is not None} for row in share_links],
		"approvals": _approval_rows(db, order.business_id, "order", order.id),
	}


def list_orders(db: Session, business_id: int, status: Optional[str] = None, limit: int = 100, skip: int = 0) -> Dict[str, Any]:
	query = db.query(ProcOrder).filter(ProcOrder.business_id == int(business_id))
	if status:
		query = query.filter(ProcOrder.status == status)
	total = query.count()
	rows = query.order_by(ProcOrder.id.desc()).offset(int(skip)).limit(int(limit)).all()
	return {"items": [_serialize_order(db, row) for row in rows], "total": total}


def get_order(db: Session, business_id: int, order_id: int) -> Dict[str, Any]:
	return _serialize_order(db, _require_order(db, business_id, order_id))


def update_order(db: Session, business_id: int, order_id: int, payload: Dict[str, Any], user_id: int) -> Dict[str, Any]:
	order = _require_order(db, business_id, order_id)
	if order.status != "draft":
		raise ApiError("ORDER_LOCKED", "فقط پیش‌نویس سفارش قابل ویرایش است.", http_status=400)
	_require_money_refs(db, business_id, payload)
	for key in ("payment_terms", "delivery_place", "warranty", "notes", "budget_id", "currency_id", "cost_center_id"):
		if key in payload:
			setattr(order, key, payload[key])
	if "file_ids" in payload:
		order.file_ids = _owned_file_ids(db, business_id, payload.get("file_ids"))
	if "delivery_date" in payload:
		order.delivery_date = _parse_date(payload.get("delivery_date"))
	if "freight" in payload:
		order.freight = D(payload.get("freight") or 0)
	if "header_discount" in payload:
		order.header_discount = D(payload.get("header_discount") or 0)
	if payload.get("lines") is not None:
		if any(D(line.received_qty) > 0 for line in _lines_of(db, order.id)):
			raise ApiError("ORDER_HAS_RECEIPTS", "سفارش دریافت‌شده قابل جایگزینی قلم نیست.", http_status=400)
		db.query(ProcOrderLine).filter(ProcOrderLine.order_id == order.id).delete()
		_add_order_lines(db, order, _parse_item_rows(db, business_id, payload.get("lines")))
	order.updated_at = datetime.utcnow()
	_assert_discounts(order, _lines_of(db, order.id))
	db.flush()
	_audit(db, user_id, business_id, "update", "proc_order", order.id, f"سفارش {order.code} ویرایش شد")
	return get_order(db, business_id, order.id)


def submit_order(db: Session, business_id: int, order_id: int, payload: Dict[str, Any], user_id: int) -> Dict[str, Any]:
	order = _require_order(db, business_id, order_id)
	if order.status != "draft":
		raise ApiError("ORDER_NOT_SUBMITTABLE", "این سفارش قابل ارسال برای تأیید نیست.", http_status=400)
	if not _lines_of(db, order.id):
		raise ApiError("LINES_REQUIRED", "سفارش بدون قلم قابل ارسال نیست.", http_status=400)
	settings = _settings(db, business_id)
	approvers = list(payload.get("approver_user_ids") or [])
	if not approvers and settings.default_approver_user_id:
		approvers = [settings.default_approver_user_id]
	_replace_approvals(db, business_id, "order", order.id, approvers, payload.get("position_id"))
	order.status = "pending_approval"
	db.flush()
	_audit(db, user_id, business_id, "submit", "proc_order", order.id, f"سفارش {order.code} برای تأیید ارسال شد")
	return get_order(db, business_id, order.id)


def mark_order_sent(db: Session, business_id: int, order_id: int, user_id: int) -> Dict[str, Any]:
	order = _require_order(db, business_id, order_id)
	if order.status != "approved":
		raise ApiError("ORDER_NOT_APPROVED", "فقط سفارش تأییدشده ارسال می‌شود.", http_status=400)
	order.status = "sent"
	db.flush()
	_audit(db, user_id, business_id, "send", "proc_order", order.id, f"سفارش {order.code} برای فروشنده ارسال شد")
	_emit(db, business_id, user_id, "procurement.order.sent", {"id": order.id, "code": order.code, "person_id": order.person_id})
	return get_order(db, business_id, order.id)


def _restore_contract_release(db: Session, line: ProcOrderLine, quantity: Any) -> None:
	qty = D(quantity)
	if qty <= 0 or not line.contract_line_id:
		return
	contract_line = db.query(ProcContractLine).filter(ProcContractLine.id == int(line.contract_line_id)).first()
	if not contract_line:
		return
	contract_line.released_qty = max(D(0), D(contract_line.released_qty) - qty)


def cancel_order(db: Session, business_id: int, order_id: int, user_id: int) -> Dict[str, Any]:
	order = _require_order(db, business_id, order_id)
	if order.status in {"closed", "cancelled"}:
		raise ApiError("ORDER_NOT_CANCELLABLE", "این سفارش قابل لغو نیست.", http_status=400)
	for line in _lines_of(db, order.id):
		open_qty = D(line.qty) - D(line.cancelled_qty) - D(line.received_qty)
		if open_qty > 0:
			line.cancelled_qty = D(line.cancelled_qty) + open_qty
			_restore_contract_release(db, line, open_qty)
	_resize_commitment(db, order)
	remaining = [line for line in _lines_of(db, order.id) if D(line.qty) - D(line.cancelled_qty) > QTY]
	order.status = "cancelled" if not remaining else order.status
	_refresh_fulfillment(order, _lines_of(db, order.id))
	if order.status == "cancelled":
		_reopen_requisition(db, order)
	db.flush()
	_audit(db, user_id, business_id, "cancel", "proc_order", order.id, f"مقدار باز سفارش {order.code} لغو شد")
	return get_order(db, business_id, order.id)


def _resize_commitment(db: Session, order: ProcOrder) -> None:
	commitment = db.query(ProcCommitment).filter(ProcCommitment.order_id == order.id).first()
	if not commitment:
		return
	total = _order_total(order, _lines_of(db, order.id))
	if D(commitment.released_amount) - total > MONEY_EPS():
		commitment.released_amount = total
	commitment.amount = max(total, D(commitment.released_amount))


def MONEY_EPS():
	return D("0.01")


def _refresh_fulfillment(order: ProcOrder, lines: Sequence[ProcOrderLine]) -> None:
	if order.status in {"draft", "pending_approval", "cancelled", "closed"}:
		return
	active = [line for line in lines if D(line.qty) - D(line.cancelled_qty) > QTY]
	if not active:
		order.status = "cancelled"
		return
	all_accepted = True
	any_accepted = False
	all_invoiced = True
	for line in active:
		target = D(line.qty) - D(line.cancelled_qty)
		if D(line.accepted_qty) + QTY < target:
			all_accepted = False
		if D(line.accepted_qty) > QTY:
			any_accepted = True
		if D(line.invoiced_qty) + QTY < D(line.accepted_qty):
			all_invoiced = False
	if all_accepted and all_invoiced and any_accepted:
		order.status = "invoiced"
	elif all_accepted and any_accepted:
		order.status = "received"
	elif any_accepted:
		order.status = "partial"


def receive_order(db: Session, business_id: int, order_id: int, payload: Dict[str, Any], user_id: int) -> Dict[str, Any]:
	order = _require_order(db, business_id, order_id)
	if order.status not in _RECEIPT_ORDER:
		raise ApiError("ORDER_NOT_RECEIVABLE", "سفارش در وضعیت دریافت نیست.", http_status=400)
	received_on = _parse_date(payload.get("received_on")) or _today()
	rows = payload.get("lines") or []
	if not rows:
		raise ApiError("LINES_REQUIRED", "اقلام رسید لازم است.", http_status=400)
	by_id = {line.id: line for line in _lines_of(db, order.id)}
	receipt = ProcReceipt(
		business_id=int(business_id),
		order_id=order.id,
		received_on=received_on,
		note=payload.get("note"),
		created_by_user_id=int(user_id),
	)
	db.add(receipt)
	db.flush()
	stock_lines = []
	for raw in rows:
		line = by_id.get(int(raw["order_line_id"]))
		if not line:
			raise ApiError("ORDER_LINE_NOT_FOUND", "قلم سفارش پیدا نشد.", http_status=404)
		quantity = D(raw.get("qty") or 0)
		rejected = D(raw.get("rejected_qty") or 0)
		qc = str(raw.get("qc_status") or "accept")
		if qc not in {"accept", "conditional", "reject"}:
			raise ApiError("INVALID_QC", "وضعیت کیفیت نامعتبر است.", http_status=400)
		if quantity + rejected <= 0:
			raise ApiError("INVALID_QTY", "مقدار رسید باید مثبت باشد.", http_status=400)
		if line.item_kind == "service":
			arrived = quantity + rejected
			open_qty = D(line.qty) - D(line.cancelled_qty) - D(line.received_qty)
			if arrived - open_qty > QTY:
				raise ApiError("OVER_RECEIPT", "مقدار بیش از مانده سفارش است.", http_status=400)
			if qc == "reject":
				if arrived <= 0:
					raise ApiError("INVALID_QTY", "مقدار خدمت مردود باید مثبت باشد.", http_status=400)
				line.rejected_qty = D(line.rejected_qty) + arrived
				line.received_qty = D(line.received_qty) + arrived
				quantity = D(0)
				rejected = arrived
			else:
				if quantity <= 0:
					raise ApiError("INVALID_QTY", "مقدار خدمت باید مثبت باشد.", http_status=400)
				line.service_confirmed = True
				line.accepted_qty = D(line.accepted_qty) + quantity
				line.rejected_qty = D(line.rejected_qty) + rejected
				line.received_qty = D(line.received_qty) + arrived
		else:
			arrived = quantity + rejected
			open_qty = D(line.qty) - D(line.cancelled_qty) - D(line.received_qty)
			if arrived - open_qty > QTY:
				raise ApiError("OVER_RECEIPT", "مقدار رسید بیش از مانده سفارش است.", http_status=400)
			if qc == "reject":
				line.rejected_qty = D(line.rejected_qty) + arrived
				line.received_qty = D(line.received_qty) + arrived
				quantity = D(0)
				rejected = arrived
			else:
				line.accepted_qty = D(line.accepted_qty) + quantity
				line.rejected_qty = D(line.rejected_qty) + rejected
				line.received_qty = D(line.received_qty) + arrived
			if quantity > 0 and _tracks_stock(db, business_id, line.product_id):
				warehouse_id = raw.get("warehouse_id") or line.warehouse_id
				if not warehouse_id:
					raise ApiError("WAREHOUSE_REQUIRED", "برای کالای قابل انبار، انبار مقصد لازم است.", http_status=400)
				_require_warehouse(db, business_id, int(warehouse_id))
				stock_lines.append((line, quantity, int(warehouse_id)))
		if rejected > 0:
			_restore_contract_release(db, line, rejected)
		db.add(ProcReceiptLine(receipt_id=receipt.id, order_line_id=line.id, qty=quantity, rejected_qty=rejected, qc_status=qc, note=raw.get("note")))
	if stock_lines:
		document_ids = _post_receipt_warehouse(db, business_id, order, receipt, stock_lines, received_on, user_id)
		receipt.warehouse_document_id = document_ids[0]
		receipt.warehouse_document_ids = document_ids
	_refresh_fulfillment(order, _lines_of(db, order.id))
	_resize_commitment(db, order)
	order.updated_at = datetime.utcnow()
	db.flush()
	_audit(db, user_id, business_id, "receive", "proc_receipt", receipt.id, f"رسید سفارش {order.code} ثبت شد")
	_emit(db, business_id, user_id, "procurement.receipt.posted", {"order_id": order.id, "receipt_id": receipt.id})
	return get_order(db, business_id, order.id)


def _active_fiscal_year_id(db: Session, business_id: int) -> int:
	from app.services.invoice_service import _get_current_fiscal_year

	return int(_get_current_fiscal_year(db, int(business_id)).id)


def _post_receipt_warehouse(db: Session, business_id: int, order: ProcOrder, receipt: ProcReceipt, stock_lines, received_on: date, user_id: int) -> List[int]:
	from adapters.db.models.warehouse_document import WarehouseDocument
	from adapters.db.models.warehouse_document_line import WarehouseDocumentLine
	from app.services.warehouse_service import post_warehouse_document

	grouped: Dict[int, List[Any]] = {}
	for line, quantity, wh_id in stock_lines:
		grouped.setdefault(int(wh_id), []).append((line, quantity, int(wh_id)))
	fiscal_year_id = _active_fiscal_year_id(db, business_id)
	order_lines = _lines_of(db, order.id)
	document_ids: List[int] = []
	for warehouse_id, group in grouped.items():
		document = WarehouseDocument(
			business_id=int(business_id),
			code=_code(db, business_id, "warehouse_document", received_on),
			document_date=received_on,
			status="draft",
			doc_type="receipt",
			fiscal_year_id=fiscal_year_id,
			warehouse_id_to=warehouse_id,
			source_type="purchase_order",
			extra_info={"procurement_order_id": order.id, "procurement_receipt_id": receipt.id},
			created_by_user_id=int(user_id),
		)
		db.add(document)
		db.flush()
		for line, quantity, wh_id in group:
			db.add(
				WarehouseDocumentLine(
					warehouse_document_id=document.id,
					product_id=int(line.product_id),
					warehouse_id=int(wh_id),
					movement="in",
					quantity=quantity,
					extra_info={"procurement_order_line_id": line.id, "unit_price": _num(_payable_unit(order, line, order_lines))},
				)
			)
		db.flush()
		post_warehouse_document(db, int(document.id))
		document_ids.append(int(document.id))
	return document_ids


def return_to_supplier(db: Session, business_id: int, order_id: int, payload: Dict[str, Any], user_id: int) -> Dict[str, Any]:
	order = _require_order(db, business_id, order_id)
	if order.status in {"draft", "pending_approval", "cancelled", "closed"}:
		raise ApiError("ORDER_NOT_RETURNABLE", "پیش‌نویس، سفارشِ در انتظار تأیید، سفارش لغوشده و سفارش بسته برگشت نمی‌گیرند.", http_status=400)
	by_id = {line.id: line for line in _lines_of(db, order.id)}
	stock_lines = []
	returned = []
	for raw in payload.get("lines") or []:
		line = by_id.get(int(raw["order_line_id"]))
		if not line:
			raise ApiError("ORDER_LINE_NOT_FOUND", "قلم سفارش پیدا نشد.", http_status=404)
		quantity = D(raw.get("qty") or 0)
		returnable = D(line.accepted_qty) - D(line.invoiced_qty)
		if quantity <= 0 or quantity - returnable > QTY:
			raise ApiError("INVALID_RETURN_QTY", "برگشت فقط از مقدار پذیرفتهٔ فاکتورنشده ممکن است.", http_status=400)
		line.accepted_qty = D(line.accepted_qty) - quantity
		line.rejected_qty = D(line.rejected_qty) + quantity
		returned.append((line, quantity))
		_restore_contract_release(db, line, quantity)
		if line.item_kind != "service" and _tracks_stock(db, business_id, line.product_id):
			wh_id = int(raw.get("warehouse_id") or line.warehouse_id or 0)
			if not wh_id:
				raise ApiError("WAREHOUSE_REQUIRED", "انبار برگشت لازم است.", http_status=400)
			_require_warehouse(db, business_id, wh_id)
			stock_lines.append((line, quantity, wh_id))
	if stock_lines:
		_post_issue_warehouse(db, business_id, order, stock_lines, _today(), user_id)
	_refresh_fulfillment(order, _lines_of(db, order.id))
	_resize_commitment(db, order)
	if returned:
		return_receipt = ProcReceipt(
			business_id=int(business_id),
			order_id=order.id,
			received_on=_today(),
			note="supplier_return",
			created_by_user_id=int(user_id),
		)
		db.add(return_receipt)
		db.flush()
		for line, quantity in returned:
			db.add(ProcReceiptLine(receipt_id=return_receipt.id, order_line_id=line.id, qty=0, rejected_qty=quantity, qc_status="return"))
	db.flush()
	_audit(db, user_id, business_id, "return", "proc_order", order.id, f"برگشت به تأمین‌کننده برای {order.code}")
	return get_order(db, business_id, order.id)


def _post_issue_warehouse(db: Session, business_id: int, order: ProcOrder, stock_lines, on: date, user_id: int) -> None:
	from adapters.db.models.warehouse_document import WarehouseDocument
	from adapters.db.models.warehouse_document_line import WarehouseDocumentLine
	from app.services.warehouse_service import post_warehouse_document

	grouped: Dict[int, List[Any]] = {}
	for line, quantity, wh_id in stock_lines:
		grouped.setdefault(int(wh_id), []).append((line, quantity, int(wh_id)))
	fiscal_year_id = _active_fiscal_year_id(db, business_id)
	order_lines = _lines_of(db, order.id)
	for warehouse_id, group in grouped.items():
		document = WarehouseDocument(
			business_id=int(business_id),
			code=_code(db, business_id, "warehouse_document", on),
			document_date=on,
			status="draft",
			doc_type="issue",
			fiscal_year_id=fiscal_year_id,
			warehouse_id_from=warehouse_id,
			source_type="purchase_order",
			extra_info={"procurement_order_id": order.id, "procurement_return": True},
			created_by_user_id=int(user_id),
		)
		db.add(document)
		db.flush()
		for line, quantity, wh_id in group:
			db.add(
				WarehouseDocumentLine(
					warehouse_document_id=document.id,
					product_id=int(line.product_id),
					warehouse_id=int(wh_id),
					movement="out",
					quantity=quantity,
					extra_info={"procurement_order_line_id": line.id, "unit_price": _num(_payable_unit(order, line, order_lines))},
				)
			)
		db.flush()
		post_warehouse_document(db, int(document.id))


def _payable_unit(order: ProcOrder, line: ProcOrderLine, lines: Sequence[ProcOrderLine]) -> Decimal:
	own = D(line.qty) * D(line.unit_price) - D(line.discount)
	if own < 0:
		own = D(0)
	base = D(0)
	for item in lines:
		part = D(item.qty) * D(item.unit_price) - D(item.discount)
		if part > 0:
			base += part
	share = D(0) if base <= 0 else D(order.header_discount) * own / base
	net = own - share
	if net < 0:
		net = D(0)
	if D(line.qty) <= 0:
		return money(D(line.unit_price))
	return money(net / D(line.qty))


def _line_tax_share(line: ProcOrderLine, invoice_qty: Decimal) -> Decimal:
	original = D(line.qty)
	if original <= 0 or D(line.tax) <= 0:
		return D(0)
	already = D(line.invoiced_qty)
	before = money(D(line.tax) * already / original) if already > 0 else D(0)
	if already + D(invoice_qty) + QTY >= original:
		return money(D(line.tax) - before)
	return money(D(line.tax) * (already + D(invoice_qty)) / original) - before


def _assert_discounts(order: ProcOrder, lines: Sequence[ProcOrderLine]) -> None:
	base = D(0)
	for line in lines:
		part = D(line.qty) * D(line.unit_price) - D(line.discount)
		if part > 0:
			base += part
	if D(order.header_discount) - base > MONEY_EPS():
		raise ApiError("DISCOUNT_EXCEEDS_ORDER", "تخفیف سربرگ از مبلغ اقلام بیشتر است.", http_status=400)


def create_invoice_for_order(db: Session, business_id: int, order_id: int, payload: Dict[str, Any], user_id: int) -> Dict[str, Any]:
	order = _require_order(db, business_id, order_id)
	if order.status in {"draft", "pending_approval", "closed"}:
		raise ApiError("ORDER_NOT_BILLABLE", "پیش‌نویس، سفارشِ در انتظار تأیید و سفارش بسته فاکتور نمی‌گیرند.", http_status=400)
	if not order.currency_id:
		raise ApiError("CURRENCY_REQUIRED", "ارز سفارش برای فاکتور لازم است.", http_status=400)
	settings = _settings(db, business_id)
	order_lines = _lines_of(db, order.id)
	by_id = {line.id: line for line in order_lines}
	selected = payload.get("lines") or []
	if not selected:
		raise ApiError("LINES_REQUIRED", "اقلام فاکتور لازم است.", http_status=400)
	matches = []
	invoice_lines = []
	accept_price = bool(payload.get("accept_price_variance"))
	for raw in selected:
		line = by_id.get(int(raw["order_line_id"]))
		if not line or not line.product_id:
			raise ApiError("PRODUCT_REQUIRED_FOR_INVOICE", "فاکتور خرید هسته برای هر قلم به کالا نیاز دارد.", http_status=400)
		invoice_qty = D(raw.get("qty") or 0)
		payable = _payable_unit(order, line, order_lines)
		invoice_price = D(raw.get("unit_price") if raw.get("unit_price") is not None else payable)
		if invoice_qty <= 0:
			raise ApiError("INVALID_QTY", "مقدار فاکتور باید مثبت باشد.", http_status=400)
		result = match_line(
			ordered=D(line.qty) - D(line.cancelled_qty) - D(line.invoiced_qty),
			accepted=D(line.accepted_qty) - D(line.invoiced_qty),
			invoice_qty=invoice_qty,
			po_price=payable,
			invoice_price=invoice_price,
			qty_tolerance_pct=settings.qty_tolerance_pct,
			price_tolerance=settings.price_tolerance,
			item_kind=line.item_kind,
			service_confirmed=bool(line.service_confirmed),
		)
		if "qty" in result["reasons"] and result["status"] == "exception":
			raise ApiError("MATCH_QTY_BLOCKED", "مقدار فاکتور از مقدار پذیرفته‌شده بیشتر است.", http_status=400)
		if "price" in result["reasons"] and result["status"] == "exception" and not accept_price:
			raise ApiError("MATCH_PRICE_BLOCKED", "قیمت فاکتور با سفارش اختلاف دارد و تأیید نشده است.", http_status=400)
		tax_share = _line_tax_share(line, invoice_qty)
		matches.append((line, invoice_qty, invoice_price, result, tax_share))
		invoice_lines.append(
			{
				"product_id": int(line.product_id),
				"quantity": float(invoice_qty),
				"description": line.description,
				"extra_info": {
					"unit_price": float(invoice_price),
					"tax_amount": float(tax_share),
					"line_total": float(money(D(invoice_qty) * D(invoice_price) + tax_share)),
					"warehouse_id": line.warehouse_id,
					"procurement_order_line_id": line.id,
					"procurement_stocked_on_receipt": line.item_kind == "goods" and _tracks_stock(db, business_id, line.product_id),
					"procurement_skip_inventory": line.item_kind == "service",
				},
			}
		)
	from app.services.invoice_service import create_invoice

	created = create_invoice(
		db,
		int(business_id),
		int(user_id),
		{
			"invoice_type": "invoice_purchase",
			"document_date": (_parse_date(payload.get("document_date")) or _today()).isoformat(),
			"currency_id": int(order.currency_id),
			"person_id": int(order.person_id),
			"project_id": order.project_id,
			"description": payload.get("description") or f"فاکتور خرید سفارش {order.code}",
			"extra_info": {"person_id": int(order.person_id), "procurement_order_id": order.id},
			"lines": invoice_lines,
		},
		commit=False,
	)
	document_id = int(created["data"]["id"])
	_mark_receipt_stock_not_on_invoice(db, document_id)
	_clear_grni(db, order.id, document_id)
	status = aggregate_match([item[3] for item in matches])
	price_exception = any(item[3]["status"] == "exception" and "price" in item[3]["reasons"] for item in matches)
	link = ProcInvoiceLink(
		business_id=int(business_id),
		order_id=order.id,
		document_id=document_id,
		match_status="tolerance" if price_exception and accept_price else status,
		price_variance_accepted=bool(price_exception and accept_price),
		created_by_user_id=int(user_id),
	)
	db.add(link)
	db.flush()
	invoiced_amount = D(0)
	for line, invoice_qty, invoice_price, result, tax_share in matches:
		line.invoiced_qty = D(line.invoiced_qty) + invoice_qty
		invoiced_amount += line_amount(invoice_qty, invoice_price, 0, 0) + tax_share
		db.add(
			ProcMatchLine(
				link_id=link.id,
				order_line_id=line.id,
				po_qty=D(line.qty) - D(line.cancelled_qty),
				receipt_qty=line.accepted_qty,
				invoice_qty=invoice_qty,
				po_price=_payable_unit(order, line, order_lines),
				invoice_price=invoice_price,
				status=result["status"],
				reasons={"reasons": result["reasons"]},
			)
		)
	_consume_commitment(db, business_id, order, invoiced_amount, user_id)
	_refresh_fulfillment(order, _lines_of(db, order.id))
	db.flush()
	_audit(db, user_id, business_id, "invoice", "proc_invoice_link", link.id, f"فاکتور خرید سفارش {order.code} ثبت شد", {"document_id": document_id, "match": link.match_status})
	return get_order(db, business_id, order.id) | {"document_id": document_id, "match_status": link.match_status}


def _mark_receipt_stock_not_on_invoice(db: Session, document_id: int) -> None:
	from adapters.db.models.invoice_item_line import InvoiceItemLine

	for line in db.query(InvoiceItemLine).filter(InvoiceItemLine.document_id == int(document_id)).all():
		info = dict(line.extra_info or {})
		if info.get("procurement_stocked_on_receipt") or info.get("procurement_skip_inventory"):
			info["inventory_posted"] = False
			line.extra_info = info
	db.flush()


def _clear_grni(db: Session, order_id: int, document_id: int) -> None:
	from app.services.purchase_accounting_service import post_grni_clearance_for_receipt_invoice

	receipts = db.query(ProcReceipt).filter(ProcReceipt.order_id == int(order_id)).all()
	seen = set()
	for receipt in receipts:
		raw_ids = list(receipt.warehouse_document_ids or [])
		if receipt.warehouse_document_id:
			raw_ids.append(receipt.warehouse_document_id)
		for raw_id in raw_ids:
			doc_id = int(raw_id)
			if doc_id in seen:
				continue
			seen.add(doc_id)
			post_grni_clearance_for_receipt_invoice(db, invoice_id=int(document_id), warehouse_document_id=doc_id)


def _consume_commitment(db: Session, business_id: int, order: ProcOrder, amount: Any, user_id: int) -> None:
	if not order.budget_id:
		return
	commitment = db.query(ProcCommitment).filter(ProcCommitment.order_id == order.id).first()
	if commitment:
		remaining = D(commitment.amount) - D(commitment.released_amount)
		commitment.released_amount = money(D(commitment.released_amount) + min(D(amount), remaining if remaining > 0 else D(0)))
	db.add(
		ProcBudgetMovement(
			business_id=int(business_id),
			budget_id=int(order.budget_id),
			kind="actual",
			amount=money(amount),
			status="approved",
			reason=f"فاکتور سفارش {order.code}",
			created_by_user_id=int(user_id),
			acted_by_user_id=int(user_id),
		)
	)


def close_order(db: Session, business_id: int, order_id: int, user_id: int) -> Dict[str, Any]:
	order = _require_order(db, business_id, order_id)
	lines = _lines_of(db, order.id)
	for line in lines:
		ordered = D(line.qty) - D(line.cancelled_qty)
		if ordered <= QTY:
			continue
		if D(line.received_qty) + QTY < ordered or D(line.invoiced_qty) + QTY < D(line.accepted_qty):
			raise ApiError("ORDER_NOT_CLOSABLE", "سفارش هنوز مانده دریافت یا فاکتور دارد.", http_status=400)
	bad = db.query(ProcInvoiceLink).filter(ProcInvoiceLink.order_id == order.id, ProcInvoiceLink.match_status == "exception").first()
	if bad:
		raise ApiError("OPEN_MATCH_EXCEPTION", "مغایرت فاکتور باز است.", http_status=400)
	commitment = db.query(ProcCommitment).filter(ProcCommitment.order_id == order.id).first()
	if commitment:
		commitment.released_amount = commitment.amount
	order.status = "closed"
	db.flush()
	_audit(db, user_id, business_id, "close", "proc_order", order.id, f"سفارش {order.code} بسته شد")
	return get_order(db, business_id, order.id)


def link_prepayment(db: Session, business_id: int, order_id: int, payload: Dict[str, Any], user_id: int) -> Dict[str, Any]:
	from adapters.db.models.document import Document
	from adapters.db.models.document_line import DocumentLine

	order = _require_order(db, business_id, order_id)
	if order.status in {"cancelled", "closed"}:
		raise ApiError("ORDER_NOT_PREPAYABLE", "سفارش بسته یا لغوشده پیش‌پرداخت نمی‌گیرد.", http_status=400)
	document = db.query(Document).filter(Document.id == int(payload["document_id"]), Document.business_id == int(business_id)).first()
	if not document or document.document_type != "payment":
		raise ApiError("PAYMENT_DOCUMENT_REQUIRED", "پیش‌پرداخت باید سند پرداخت هسته باشد.", http_status=400)
	if order.currency_id and int(document.currency_id) != int(order.currency_id):
		raise ApiError("PAYMENT_CURRENCY_MISMATCH", "ارز سند پرداخت با سفارش یکی نیست.", http_status=400)
	amount = D(payload.get("amount") or 0)
	if amount <= 0:
		raise ApiError("INVALID_AMOUNT", "مبلغ پیش‌پرداخت باید مثبت باشد.", http_status=400)
	lines = db.query(DocumentLine).filter(DocumentLine.document_id == document.id).all()
	if not lines:
		raise ApiError("PAYMENT_LINES_REQUIRED", "سند پرداخت بدون ردیف مبلغ قابل اتکا نیست.", http_status=400)
	person_lines = [line for line in lines if line.person_id]
	if person_lines and not any(int(line.person_id) == int(order.person_id) for line in person_lines):
		raise ApiError("PAYMENT_SUPPLIER_MISMATCH", "این پرداخت برای تأمین‌کننده سفارش نیست.", http_status=400)
	relevant = [line for line in person_lines if int(line.person_id) == int(order.person_id)] if person_lines else lines
	cap = sum((D(line.debit) for line in relevant), D(0))
	if cap <= 0:
		raise ApiError("PAYMENT_AMOUNT_UNKNOWN", "مبلغ قابل اتکای سند پرداخت پیدا نشد.", http_status=400)
	already = sum(
		(D(row.amount) for row in db.query(ProcPrepayment).filter(ProcPrepayment.business_id == int(business_id), ProcPrepayment.document_id == document.id).all()),
		D(0),
	)
	if already + amount - cap > MONEY_EPS():
		raise ApiError("PREPAYMENT_EXCEEDS_PAYMENT", "جمع پیش‌پرداخت از مبلغ سند پرداخت بیشتر است.", http_status=400)
	order_total = _order_total(order, _lines_of(db, order.id))
	on_order = sum((D(row.amount) for row in db.query(ProcPrepayment).filter(ProcPrepayment.order_id == order.id).all()), D(0))
	if on_order + amount - order_total > MONEY_EPS():
		raise ApiError("PREPAYMENT_EXCEEDS_ORDER", "جمع پیش‌پرداخت از مبلغ سفارش بیشتر است.", http_status=400)
	row = ProcPrepayment(
		business_id=int(business_id),
		order_id=order.id,
		document_id=document.id,
		amount=amount,
		note=payload.get("note"),
		created_by_user_id=int(user_id),
	)
	db.add(row)
	db.flush()
	_audit(db, user_id, business_id, "prepay", "proc_prepayment", row.id, f"پیش‌پرداخت سفارش {order.code} لینک شد")
	return get_order(db, business_id, order.id)


def _insert_sourcing_lines(db: Session, event_id: int, items: Sequence[Dict[str, Any]]) -> None:
	for item in items:
		db.add(
			ProcSourcingLine(
				event_id=int(event_id),
				product_id=item["product_id"],
				description=item["description"],
				qty=item["qty"],
				uom=item["uom"],
				item_kind=item["item_kind"],
				warehouse_id=item.get("warehouse_id"),
				requisition_line_id=item.get("requisition_line_id"),
			)
		)


def create_sourcing(db: Session, business_id: int, payload: Dict[str, Any], user_id: int) -> Dict[str, Any]:
	event_type = str(payload.get("event_type") or "rfq")
	if event_type not in {"rfq", "tender"}:
		raise ApiError("INVALID_EVENT_TYPE", "نوع رویداد باید استعلام یا مناقصه باشد.", http_status=400)
	requisition_id = payload.get("requisition_id")
	if requisition_id:
		requisition = _require_req(db, business_id, int(requisition_id))
		if requisition.status != "approved":
			raise ApiError("REQUISITION_NOT_APPROVED", "استعلام فقط روی درخواست تأییدشده ساخته می‌شود.", http_status=400)
		if (
			db.query(ProcSourcingEvent)
			.filter(
				ProcSourcingEvent.business_id == int(business_id),
				ProcSourcingEvent.requisition_id == requisition.id,
				ProcSourcingEvent.status != "cancelled",
			)
			.first()
		):
			raise ApiError("REQUISITION_IN_SOURCING", "برای این درخواست استعلام باز وجود دارد.", http_status=400)
		if (
			db.query(ProcOrder)
			.filter(ProcOrder.business_id == int(business_id), ProcOrder.requisition_id == requisition.id, ProcOrder.status != "cancelled")
			.first()
		):
			raise ApiError("REQUISITION_ALREADY_ORDERED", "برای این درخواست سفارش باز وجود دارد.", http_status=400)
		requisition_id = requisition.id
		source_lines = _req_lines(db, requisition.id)
		items = _parse_item_rows(
			db,
			business_id,
			[
				{
					"product_id": line.product_id,
					"description": line.description,
					"item_kind": line.item_kind,
					"qty": line.qty,
					"uom": line.uom,
					"unit_price": line.unit_price_estimate,
					"warehouse_id": line.warehouse_id,
				}
				for line in source_lines
			],
		)
		for item, source in zip(items, source_lines):
			item["requisition_line_id"] = source.id
	else:
		items = _parse_item_rows(db, business_id, payload.get("lines"))
	event = ProcSourcingEvent(
		business_id=int(business_id),
		code=_code(db, business_id, "proc_rfq"),
		event_type=event_type,
		title=str(payload.get("title") or "استعلام"),
		deadline_at=_parse_dt(payload.get("deadline_at")),
		requisition_id=requisition_id,
		created_by_user_id=int(user_id),
	)
	db.add(event)
	db.flush()
	_insert_sourcing_lines(db, event.id, items)
	db.flush()
	_audit(db, user_id, business_id, "create", "proc_sourcing", event.id, f"رویداد {event.code} ایجاد شد")
	return get_sourcing(db, business_id, event.id, reveal=True)


def _event(db: Session, business_id: int, event_id: int) -> ProcSourcingEvent:
	row = db.query(ProcSourcingEvent).filter(ProcSourcingEvent.id == int(event_id), ProcSourcingEvent.business_id == int(business_id)).first()
	if not row:
		raise ApiError("EVENT_NOT_FOUND", "رویداد منبع‌یابی پیدا نشد.", http_status=404)
	return row


def invite_suppliers(db: Session, business_id: int, event_id: int, person_ids: Sequence[int], user_id: int) -> Dict[str, Any]:
	event = _event(db, business_id, event_id)
	if event.status in {"awarded", "cancelled"}:
		raise ApiError("EVENT_CLOSED", "رویداد بسته است.", http_status=400)
	for person_id in person_ids:
		_load_person(db, business_id, int(person_id))
		exists = db.query(ProcSourcingInvite).filter(ProcSourcingInvite.event_id == event.id, ProcSourcingInvite.person_id == int(person_id)).first()
		if exists:
			continue
		db.add(ProcSourcingInvite(business_id=int(business_id), event_id=event.id, person_id=int(person_id)))
	event.status = "open"
	db.flush()
	_audit(db, user_id, business_id, "invite", "proc_sourcing", event.id, f"تأمین‌کنندگان به {event.code} دعوت شدند")
	return get_sourcing(db, business_id, event.id, reveal=True)


def submit_bid(db: Session, business_id: int, invite_id: int, payload: Dict[str, Any], user_id: Optional[int] = None) -> Dict[str, Any]:
	invite = db.query(ProcSourcingInvite).filter(ProcSourcingInvite.id == int(invite_id), ProcSourcingInvite.business_id == int(business_id)).first()
	if not invite:
		raise ApiError("INVITE_NOT_FOUND", "دعوت پیدا نشد.", http_status=404)
	event = _event(db, business_id, invite.event_id)
	if event.status not in {"draft", "open"}:
		raise ApiError("EVENT_CLOSED", "مهلت پیشنهاد بسته است.", http_status=400)
	if event.event_type == "tender" and event.technical_opened_at:
		raise ApiError("BID_LOCKED", "پس از بازگشایی پاکت فنی پیشنهاد عوض نمی‌شود.", http_status=400)
	if event.deadline_at and event.deadline_at < datetime.utcnow():
		raise ApiError("DEADLINE_PASSED", "مهلت پاسخ گذشته است.", http_status=400)
	lines = db.query(ProcSourcingLine).filter(ProcSourcingLine.event_id == event.id).all()
	raw_lines = payload.get("lines") or []
	prices = {int(row["sourcing_line_id"]): D(row["unit_price"]) for row in raw_lines}
	if set(prices) != {line.id for line in lines}:
		raise ApiError("BID_LINES_MISMATCH", "پیشنهاد باید برای همه اقلام قیمت داشته باشد.", http_status=400)
	_assert_bid_money(payload, prices, lines)
	bid = db.query(ProcSourcingBid).filter(ProcSourcingBid.invite_id == invite.id).first()
	if not bid:
		bid = ProcSourcingBid(business_id=int(business_id), invite_id=invite.id)
		db.add(bid)
	bid.payment_terms = payload.get("payment_terms")
	bid.payment_days = int(payload.get("payment_days") or 0)
	bid.delivery_days = int(payload.get("delivery_days") or 0)
	bid.warranty = payload.get("warranty")
	bid.freight = D(payload.get("freight") or 0)
	bid.tax = D(payload.get("tax") or 0)
	bid.discount = D(payload.get("discount") or 0)
	bid.valid_until = _parse_date(payload.get("valid_until"))
	bid.file_id = _owned_file_id(db, business_id, payload.get("file_id"))
	bid.note = payload.get("note")
	bid.submitted_at = datetime.utcnow()
	db.flush()
	db.query(ProcSourcingBidLine).filter(ProcSourcingBidLine.bid_id == bid.id).delete()
	for line in lines:
		db.add(ProcSourcingBidLine(bid_id=bid.id, sourcing_line_id=line.id, unit_price=prices[line.id]))
	invite.status = "responded"
	db.flush()
	if user_id:
		_audit(db, user_id, business_id, "bid", "proc_sourcing_bid", bid.id, f"پیشنهاد رویداد {event.code} ثبت شد")
	return {"bid_id": bid.id, "invite_id": invite.id}


def _bid_total(bid: ProcSourcingBid, lines: Sequence[ProcSourcingLine], prices: Dict[int, Any]) -> Any:
	total = D(bid.freight) + D(bid.tax) - D(bid.discount)
	for line in lines:
		total += D(line.qty) * D(prices.get(line.id, 0))
	return money(total)


def list_sourcing(db: Session, business_id: int) -> Dict[str, Any]:
	rows = (
		db.query(ProcSourcingEvent)
		.filter(ProcSourcingEvent.business_id == int(business_id))
		.order_by(ProcSourcingEvent.id.desc())
		.all()
	)
	return {
		"items": [
			{
				"id": row.id,
				"code": row.code,
				"event_type": row.event_type,
				"title": row.title,
				"status": row.status,
				"deadline_at": _iso(row.deadline_at),
				"financial_visible": row.event_type != "tender" or row.financial_opened_at is not None,
			}
			for row in rows
		]
	}


def get_sourcing(db: Session, business_id: int, event_id: int, reveal: bool = False) -> Dict[str, Any]:
	event = _event(db, business_id, event_id)
	lines = db.query(ProcSourcingLine).filter(ProcSourcingLine.event_id == event.id).order_by(ProcSourcingLine.id).all()
	invites = db.query(ProcSourcingInvite).filter(ProcSourcingInvite.event_id == event.id).all()
	financial_open = event.event_type != "tender" or event.financial_opened_at is not None or reveal
	share_by_invite: Dict[int, List[Dict[str, Any]]] = {}
	invite_ids = [invite.id for invite in invites]
	if invite_ids:
		for row in (
			db.query(ProcShareLink)
			.filter(ProcShareLink.business_id == int(business_id), ProcShareLink.kind == "rfq", ProcShareLink.entity_id.in_(invite_ids))
			.order_by(ProcShareLink.id.desc())
			.all()
		):
			share_by_invite.setdefault(int(row.entity_id), []).append(
				{"id": row.id, "kind": row.kind, "expires_at": _iso(row.expires_at), "revoked": row.revoked_at is not None}
			)
	invite_rows = []
	for invite in invites:
		bid = db.query(ProcSourcingBid).filter(ProcSourcingBid.invite_id == invite.id).first()
		prices = {}
		if bid:
			for row in db.query(ProcSourcingBidLine).filter(ProcSourcingBidLine.bid_id == bid.id).all():
				prices[row.sourcing_line_id] = row.unit_price
		invite_rows.append(
			{
				"id": invite.id,
				"person_id": invite.person_id,
				"status": invite.status,
				"reject_reason": invite.reject_reason,
				"share_links": share_by_invite.get(invite.id, []),
				"bid": None
				if not bid
				else {
					"id": bid.id,
					"payment_days": bid.payment_days,
					"delivery_days": bid.delivery_days,
					"warranty": bid.warranty,
					"technical_score": _num(bid.technical_score) if event.technical_opened_at or event.event_type == "rfq" else None,
					"total": _num(_bid_total(bid, lines, prices)) if financial_open else None,
					"lines": [{"sourcing_line_id": key, "unit_price": _num(value)} for key, value in prices.items()] if financial_open else [],
				},
			}
		)
	return {
		"id": event.id,
		"code": event.code,
		"event_type": event.event_type,
		"title": event.title,
		"status": event.status,
		"deadline_at": _iso(event.deadline_at),
		"requisition_id": event.requisition_id,
		"technical_opened_at": _iso(event.technical_opened_at),
		"financial_opened_at": _iso(event.financial_opened_at),
		"award_reason": event.award_reason,
		"awarded_invite_id": event.awarded_invite_id,
		"minutes": event.minutes,
		"financial_visible": financial_open,
		"lines": [{"id": line.id, "product_id": line.product_id, "description": line.description, "qty": _num(line.qty), "uom": line.uom, "item_kind": line.item_kind, "warehouse_id": line.warehouse_id, "requisition_line_id": line.requisition_line_id} for line in lines],
		"invites": invite_rows,
	}


def _event_score_period(event: ProcSourcingEvent) -> str:
	moment = event.deadline_at or event.created_at or datetime.utcnow()
	return f"{moment.year:04d}-{moment.month:02d}"


def _comparison_quality(db: Session, business_id: int, person_id: int, period_key: str, technical_score: Any) -> Any:
	if technical_score is not None:
		return technical_score
	score = (
		db.query(ProcScore)
		.filter(
			ProcScore.business_id == int(business_id),
			ProcScore.person_id == int(person_id),
			ProcScore.period_key == period_key,
		)
		.first()
	)
	metrics = score.metrics if score and isinstance(score.metrics, dict) else {}
	return metrics.get("quality")


def compare_sourcing(db: Session, business_id: int, event_id: int) -> Dict[str, Any]:
	event = _event(db, business_id, event_id)
	data = get_sourcing(db, business_id, event_id)
	if not data["financial_visible"]:
		raise ApiError("FINANCIAL_SEALED", "پاکت مالی هنوز باز نشده است.", http_status=400)
	settings = _settings(db, business_id)
	period_key = _event_score_period(event)
	rows = []
	for invite in data["invites"]:
		bid = invite.get("bid")
		if not bid or bid.get("total") is None:
			continue
		profile = _profile(db, business_id, invite["person_id"])
		rows.append(
			{
				"invite_id": invite["id"],
				"price_total": bid["total"],
				"delivery_days": bid["delivery_days"],
				"payment_days": bid["payment_days"],
				"quality": _comparison_quality(db, business_id, invite["person_id"], period_key, bid.get("technical_score")),
				"risk": _num(profile.risk_score) if profile and profile.risk_score is not None else None,
			}
		)
	ranking = _json_safe(compare_bids(rows, settings.weights))
	return {"event_id": event_id, "quality_period": period_key, "ranking": ranking, "matrix": data}


def add_sourcing_lines(db: Session, business_id: int, event_id: int, payload: Dict[str, Any], user_id: int) -> Dict[str, Any]:
	event = _event(db, business_id, event_id)
	_reject_closed_event(event)
	if event.status not in {"draft", "open"}:
		raise ApiError("EVENT_CLOSED", "این رویداد بسته است.", http_status=400)
	if event.requisition_id:
		raise ApiError("REQUISITION_LINES_LOCKED", "اقلام استعلامِ درخواست را نمی‌توان عوض کرد.", http_status=400)
	invite_ids = [row.id for row in db.query(ProcSourcingInvite).filter(ProcSourcingInvite.event_id == event.id).all()]
	if invite_ids and db.query(ProcSourcingBid).filter(ProcSourcingBid.invite_id.in_(invite_ids)).first():
		raise ApiError("BIDS_LOCKED", "بعد از ثبت پیشنهاد، قلم تازه به استعلام اضافه نمی‌شود.", http_status=400)
	items = _parse_item_rows(db, business_id, payload.get("lines"))
	_insert_sourcing_lines(db, event.id, items)
	db.flush()
	_audit(db, user_id, business_id, "add_line", "proc_sourcing", event.id, f"قلم به رویداد {event.code} اضافه شد")
	return get_sourcing(db, business_id, event.id, reveal=True)


def _reject_closed_event(event: ProcSourcingEvent) -> None:
	if event.status == "cancelled":
		raise ApiError("EVENT_CLOSED", "این رویداد لغو شده است.", http_status=400)
	if event.status == "awarded" or event.awarded_invite_id:
		raise ApiError("ALREADY_AWARDED", "این رویداد قبلاً برنده دارد.", http_status=400)


def cancel_sourcing(db: Session, business_id: int, event_id: int, user_id: int, reason: Optional[str] = None) -> Dict[str, Any]:
	event = _event(db, business_id, event_id)
	if event.status == "awarded" or event.awarded_invite_id:
		raise ApiError("EVENT_AWARDED", "رویداد برنده‌دار لغو نمی‌شود.", http_status=400)
	if event.status != "cancelled":
		event.status = "cancelled"
		db.flush()
		note = str(reason or "").strip()
		_audit(db, user_id, business_id, "cancel", "proc_sourcing", event.id, f"رویداد {event.code} لغو شد", {"reason": note} if note else None)
	return get_sourcing(db, business_id, event.id)


def _assert_bid_money(payload: Dict[str, Any], prices: Dict[int, Any], lines: Sequence[Any]) -> None:
	if any(D(price) < 0 for price in prices.values()):
		raise ApiError("INVALID_PRICE", "قیمت قلم پیشنهاد نمی‌تواند منفی باشد.", http_status=400)
	freight = D(payload.get("freight") or 0)
	tax = D(payload.get("tax") or 0)
	discount = D(payload.get("discount") or 0)
	if freight < 0 or tax < 0 or discount < 0:
		raise ApiError("INVALID_AMOUNT", "کرایه، مالیات و تخفیف پیشنهاد نمی‌تواند منفی باشد.", http_status=400)
	if int(payload.get("delivery_days") or 0) < 0 or int(payload.get("payment_days") or 0) < 0:
		raise ApiError("INVALID_DAYS", "روز تحویل و روز پرداخت نمی‌تواند منفی باشد.", http_status=400)
	merchandise = sum((D(line.qty) * D(prices[line.id]) for line in lines), D(0))
	if discount - merchandise > MONEY_EPS():
		raise ApiError("DISCOUNT_EXCEEDS_BID", "تخفیف از مبلغ اقلام پیشنهاد بیشتر است.", http_status=400)


def _reject_early_envelope(event: ProcSourcingEvent) -> None:
	if event.deadline_at and event.deadline_at > datetime.utcnow():
		raise ApiError("ENVELOPE_BEFORE_DEADLINE", "پاکت پیش از پایان مهلت باز نمی‌شود.", http_status=400)


def open_technical(db: Session, business_id: int, event_id: int, user_id: int) -> Dict[str, Any]:
	event = _event(db, business_id, event_id)
	_reject_closed_event(event)
	_reject_early_envelope(event)
	if event.event_type != "tender":
		raise ApiError("NOT_A_TENDER", "بازگشایی فنی فقط برای مناقصه است.", http_status=400)
	event.technical_opened_at = datetime.utcnow()
	db.flush()
	_audit(db, user_id, business_id, "open_technical", "proc_sourcing", event.id, f"پاکت فنی {event.code} باز شد")
	return get_sourcing(db, business_id, event.id)


def score_technical(db: Session, business_id: int, event_id: int, payload: Dict[str, Any], user_id: int) -> Dict[str, Any]:
	event = _event(db, business_id, event_id)
	_reject_closed_event(event)
	if event.event_type == "tender" and not event.technical_opened_at:
		raise ApiError("TECHNICAL_SEALED", "اول پاکت فنی را باز کنید.", http_status=400)
	for raw in payload.get("scores") or []:
		invite = db.query(ProcSourcingInvite).filter(ProcSourcingInvite.id == int(raw["invite_id"]), ProcSourcingInvite.event_id == event.id).first()
		bid = db.query(ProcSourcingBid).filter(ProcSourcingBid.invite_id == invite.id).first() if invite else None
		if not bid:
			raise ApiError("BID_NOT_FOUND", "پیشنهاد برای امتیاز فنی پیدا نشد.", http_status=404)
		score = D(raw.get("technical_score") or 0)
		if score < 0 or score > 100:
			raise ApiError("TECHNICAL_SCORE_INVALID", "امتیاز فنی باید بین ۰ و ۱۰۰ باشد.", http_status=400)
		bid.technical_score = score
	db.flush()
	_audit(db, user_id, business_id, "score", "proc_sourcing", event.id, "امتیاز فنی ثبت شد")
	return get_sourcing(db, business_id, event.id)


def open_financial(db: Session, business_id: int, event_id: int, user_id: int) -> Dict[str, Any]:
	event = _event(db, business_id, event_id)
	_reject_closed_event(event)
	_reject_early_envelope(event)
	if event.event_type == "tender" and not event.technical_opened_at:
		raise ApiError("TECHNICAL_FIRST", "پاکت مالی بعد از پاکت فنی باز می‌شود.", http_status=400)
	if event.event_type == "tender":
		responded = db.query(ProcSourcingInvite).filter(ProcSourcingInvite.event_id == event.id, ProcSourcingInvite.status == "responded").all()
		if not responded:
			raise ApiError("TECHNICAL_SCORE_REQUIRED", "مناقصه بدون پیشنهاد امتیازداده‌شده پاکت مالی ندارد.", http_status=400)
		for invite in responded:
			bid = db.query(ProcSourcingBid).filter(ProcSourcingBid.invite_id == invite.id).first()
			if not bid or bid.technical_score is None:
				raise ApiError("TECHNICAL_SCORE_REQUIRED", "پاکت مالی بعد از امتیاز فنی همه پیشنهادها باز می‌شود.", http_status=400)
	event.financial_opened_at = datetime.utcnow()
	db.flush()
	_audit(db, user_id, business_id, "open_financial", "proc_sourcing", event.id, f"پاکت مالی {event.code} باز شد")
	return get_sourcing(db, business_id, event.id, reveal=True)


def record_minutes(db: Session, business_id: int, event_id: int, minutes: str, user_id: int) -> Dict[str, Any]:
	event = _event(db, business_id, event_id)
	_reject_closed_event(event)
	text = str(minutes or "").strip()
	if not text:
		raise ApiError("MINUTES_REQUIRED", "صورت‌جلسه خالی است.", http_status=400)
	event.minutes = text
	db.flush()
	_audit(db, user_id, business_id, "minutes", "proc_sourcing", event.id, "صورت‌جلسه ثبت شد")
	return get_sourcing(db, business_id, event.id, reveal=True)


def award_sourcing(db: Session, business_id: int, event_id: int, payload: Dict[str, Any], user_id: int) -> Dict[str, Any]:
	event = _event(db, business_id, event_id)
	if event.status == "cancelled":
		raise ApiError("EVENT_CLOSED", "رویداد لغوشده برنده ندارد.", http_status=400)
	if event.status == "awarded" or event.awarded_invite_id:
		raise ApiError("ALREADY_AWARDED", "این رویداد قبلاً برنده دارد.", http_status=400)
	reason = str(payload.get("reason") or "").strip()
	if not reason:
		raise ApiError("AWARD_REASON_REQUIRED", "دلیل انتخاب برنده لازم است.", http_status=400)
	if event.event_type == "tender":
		if not event.financial_opened_at:
			raise ApiError("FINANCIAL_SEALED", "قبل از انتخاب برنده پاکت مالی را باز کنید.", http_status=400)
		if not str(event.minutes or "").strip() and not str(payload.get("minutes") or "").strip():
			raise ApiError("MINUTES_REQUIRED", "مناقصه بدون صورت‌جلسه برنده ندارد.", http_status=400)
		if payload.get("minutes"):
			event.minutes = str(payload["minutes"])
	invite = db.query(ProcSourcingInvite).filter(ProcSourcingInvite.id == int(payload["invite_id"]), ProcSourcingInvite.event_id == event.id).first()
	if not invite or invite.status != "responded":
		raise ApiError("WINNER_NOT_RESPONDED", "برنده باید پیشنهاد ثبت‌شده داشته باشد.", http_status=400)
	bid = db.query(ProcSourcingBid).filter(ProcSourcingBid.invite_id == invite.id).first()
	lines = db.query(ProcSourcingLine).filter(ProcSourcingLine.event_id == event.id).all()
	prices = {row.sourcing_line_id: row.unit_price for row in db.query(ProcSourcingBidLine).filter(ProcSourcingBidLine.bid_id == bid.id).all()}
	if any(line.id not in prices for line in lines):
		raise ApiError("BID_INCOMPLETE", "پیشنهاد برنده همه اقلام را قیمت ندارد.", http_status=400)
	extended = [D(line.qty) * D(prices[line.id]) for line in lines]
	base = sum(extended, D(0))
	tax_total = D(bid.tax)
	allocated = D(0)
	items = []
	for index, line in enumerate(lines):
		if index == len(lines) - 1:
			tax = money(tax_total - allocated)
		elif base <= 0:
			tax = D(0)
		else:
			tax = money(tax_total * extended[index] / base)
			allocated += tax
		items.append(
			{
				"product_id": line.product_id,
				"description": line.description,
				"item_kind": line.item_kind,
				"qty": D(line.qty),
				"uom": line.uom,
				"unit_price": D(prices[line.id]),
				"discount": D(0),
				"tax": tax,
				"warehouse_id": line.warehouse_id,
				"sort_order": index,
			}
		)
	req = _require_req(db, business_id, event.requisition_id) if event.requisition_id else None
	order_body = {
		"sourcing_event_id": event.id,
		"requisition_id": event.requisition_id,
		"currency_id": payload.get("currency_id"),
		"budget_id": payload.get("budget_id"),
		"project_id": payload.get("project_id"),
		"cost_center_id": payload.get("cost_center_id"),
		"delivery_date": payload.get("delivery_date"),
		"freight": D(bid.freight),
		"header_discount": D(bid.discount),
		"payment_terms": bid.payment_terms,
		"warranty": bid.warranty,
	}
	if req:
		if order_body["currency_id"] is None:
			order_body["currency_id"] = req.currency_id
		if order_body["project_id"] is None:
			order_body["project_id"] = req.project_id
		if order_body["cost_center_id"] is None:
			order_body["cost_center_id"] = req.cost_center_id
		if order_body["delivery_date"] is None and req.needed_by:
			order_body["delivery_date"] = req.needed_by
	order = _new_order(db, business_id, user_id, invite.person_id, order_body)
	_add_order_lines(db, order, items, [line.requisition_line_id for line in lines])
	for other in db.query(ProcSourcingInvite).filter(ProcSourcingInvite.event_id == event.id).all():
		if other.id == invite.id:
			other.status = "awarded"
		elif other.status != "declined":
			other.status = "rejected"
			other.reject_reason = payload.get("reject_reason") or reason
	event.status = "awarded"
	event.award_reason = reason
	event.awarded_invite_id = invite.id
	if event.requisition_id:
		req = _require_req(db, business_id, event.requisition_id)
		if req.status == "approved":
			req.status = "converted"
	db.flush()
	_audit(db, user_id, business_id, "award", "proc_sourcing", event.id, f"برنده {event.code} انتخاب شد", {"reason": reason, "order_id": order.id})
	return {"event": get_sourcing(db, business_id, event.id, reveal=True), "order": get_order(db, business_id, order.id)}


def create_budget(db: Session, business_id: int, payload: Dict[str, Any], user_id: int) -> Dict[str, Any]:
	amount = D(payload.get("amount") or 0)
	if amount < 0:
		raise ApiError("INVALID_AMOUNT", "مبلغ بودجه نامعتبر است.", http_status=400)
	period_key = str(payload.get("period_key") or _today().strftime("%Y-%m"))
	_period_bounds(period_key)
	raw_warn = payload.get("warn_percent")
	warn_percent = 80 if raw_warn is None or raw_warn == "" else int(raw_warn)
	if warn_percent < 1 or warn_percent > 100:
		raise ApiError("INVALID_WARN_PERCENT", "درصد هشدار بودجه باید بین ۱ و ۱۰۰ باشد.", http_status=400)
	if payload.get("fiscal_year_id"):
		from adapters.db.models.fiscal_year import FiscalYear

		year = db.query(FiscalYear).filter(FiscalYear.id == int(payload["fiscal_year_id"]), FiscalYear.business_id == int(business_id)).first()
		if not year:
			raise ApiError("FISCAL_YEAR_NOT_FOUND", "سال مالی در این کسب‌وکار پیدا نشد.", http_status=404)
	_require_money_refs(db, business_id, payload)
	row = ProcBudget(
		business_id=int(business_id),
		period_key=period_key,
		name=str(payload.get("name") or "بودجه خرید"),
		amount=amount,
		org_unit_name=payload.get("org_unit_name"),
		project_id=payload.get("project_id"),
		cost_center_id=payload.get("cost_center_id"),
		fiscal_year_id=payload.get("fiscal_year_id"),
		warn_percent=warn_percent,
	)
	db.add(row)
	db.flush()
	_audit(db, user_id, business_id, "create", "proc_budget", row.id, "ردیف بودجه ایجاد شد")
	return _budget_figures(db, row)


def list_budgets(db: Session, business_id: int) -> Dict[str, Any]:
	rows = db.query(ProcBudget).filter(ProcBudget.business_id == int(business_id)).order_by(ProcBudget.id.desc()).all()
	return {"items": [_budget_figures(db, row) for row in rows]}


def list_pending_budget_movements(db: Session, business_id: int) -> Dict[str, Any]:
	rows = (
		db.query(ProcBudgetMovement)
		.filter(
			ProcBudgetMovement.business_id == int(business_id),
			ProcBudgetMovement.status.in_(("pending", "returned")),
			ProcBudgetMovement.kind.in_(("increase", "transfer_out")),
		)
		.order_by(ProcBudgetMovement.id.desc())
		.all()
	)
	names = {row.id: row.name for row in db.query(ProcBudget).filter(ProcBudget.business_id == int(business_id)).all()}
	return {
		"items": [
			{
				"id": row.id,
				"budget_id": row.budget_id,
				"budget_name": names.get(row.budget_id),
				"counter_budget_id": row.counter_budget_id,
				"counter_budget_name": names.get(row.counter_budget_id) if row.counter_budget_id else None,
				"kind": row.kind,
				"amount": _num(row.amount),
				"status": row.status,
				"reason": row.reason,
			}
			for row in rows
		]
	}


def request_budget_increase(db: Session, business_id: int, budget_id: int, payload: Dict[str, Any], user_id: int) -> Dict[str, Any]:
	budget = db.query(ProcBudget).filter(ProcBudget.id == int(budget_id), ProcBudget.business_id == int(business_id)).first()
	if not budget:
		raise ApiError("BUDGET_NOT_FOUND", "ردیف بودجه پیدا نشد.", http_status=404)
	amount = D(payload.get("amount") or 0)
	if amount <= 0:
		raise ApiError("INVALID_AMOUNT", "مبلغ افزایش باید مثبت باشد.", http_status=400)
	movement = ProcBudgetMovement(
		business_id=int(business_id),
		budget_id=budget.id,
		kind="increase",
		amount=amount,
		reason=payload.get("reason"),
		created_by_user_id=int(user_id),
	)
	db.add(movement)
	db.flush()
	_replace_approvals(db, business_id, "budget_movement", movement.id, payload.get("approver_user_ids") or [], None)
	_audit(db, user_id, business_id, "request", "proc_budget_movement", movement.id, "درخواست افزایش بودجه ثبت شد")
	return {"id": movement.id, "status": movement.status}


def request_budget_transfer(db: Session, business_id: int, payload: Dict[str, Any], user_id: int) -> Dict[str, Any]:
	amount = D(payload.get("amount") or 0)
	if amount <= 0:
		raise ApiError("INVALID_AMOUNT", "مبلغ انتقال باید مثبت باشد.", http_status=400)
	source = db.query(ProcBudget).filter(ProcBudget.id == int(payload["from_budget_id"]), ProcBudget.business_id == int(business_id)).first()
	target = db.query(ProcBudget).filter(ProcBudget.id == int(payload["to_budget_id"]), ProcBudget.business_id == int(business_id)).first()
	if not source or not target:
		raise ApiError("BUDGET_NOT_FOUND", "ردیف بودجه مبدأ یا مقصد پیدا نشد.", http_status=404)
	if int(source.id) == int(target.id):
		raise ApiError("TRANSFER_SAME_BUDGET", "مبدأ و مقصد انتقال نمی‌تواند یکی باشد.", http_status=400)
	if D(_budget_figures(db, source)["available"]) + QTY < amount:
		raise ApiError("BUDGET_EXCEEDED", "مانده مبدأ برای انتقال کافی نیست.", http_status=400)
	outgoing = ProcBudgetMovement(business_id=int(business_id), budget_id=source.id, counter_budget_id=target.id, kind="transfer_out", amount=amount, reason=payload.get("reason"), created_by_user_id=int(user_id))
	incoming = ProcBudgetMovement(business_id=int(business_id), budget_id=target.id, counter_budget_id=source.id, kind="transfer_in", amount=amount, reason=payload.get("reason"), created_by_user_id=int(user_id))
	db.add(outgoing)
	db.add(incoming)
	db.flush()
	_replace_approvals(db, business_id, "budget_movement", outgoing.id, payload.get("approver_user_ids") or [], None)
	return {"transfer_out_id": outgoing.id, "transfer_in_id": incoming.id, "status": "pending"}


def resubmit_budget_movement(db: Session, business_id: int, movement_id: int, payload: Dict[str, Any], user_id: int) -> Dict[str, Any]:
	movement = _require_movement(db, business_id, movement_id)
	if movement.status != "returned" or movement.kind not in {"increase", "transfer_out"}:
		raise ApiError("MOVEMENT_NOT_RESUBMITTABLE", "فقط افزایش یا انتقال برگشتی دوباره ارسال می‌شود.", http_status=400)
	amount = D(payload.get("amount") if payload.get("amount") is not None else movement.amount)
	if amount <= 0:
		raise ApiError("INVALID_AMOUNT", "مبلغ باید مثبت باشد.", http_status=400)
	if movement.kind == "transfer_out":
		source = db.query(ProcBudget).filter(ProcBudget.id == int(movement.budget_id), ProcBudget.business_id == int(business_id)).first()
		if not source:
			raise ApiError("BUDGET_NOT_FOUND", "ردیف بودجه مبدأ پیدا نشد.", http_status=404)
		if D(_budget_figures(db, source)["available"]) + QTY < amount:
			raise ApiError("BUDGET_EXCEEDED", "مانده مبدأ برای انتقال کافی نیست.", http_status=400)
		pair = _movement_pair(db, business_id, movement, "returned")
		if not pair:
			raise ApiError("MOVEMENT_NOT_RESUBMITTABLE", "نیمهٔ ورودی انتقال برگشتی پیدا نشد.", http_status=400)
		pair.amount = money(amount)
		pair.status = "pending"
		pair.acted_by_user_id = None
		if "reason" in payload:
			pair.reason = payload.get("reason")
	movement.amount = money(amount)
	if "reason" in payload:
		movement.reason = payload.get("reason")
	movement.status = "pending"
	movement.acted_by_user_id = None
	_replace_approvals(db, business_id, "budget_movement", movement.id, payload.get("approver_user_ids") or [], None)
	db.flush()
	_audit(db, user_id, business_id, "resubmit", "proc_budget_movement", movement.id, "حرکت بودجهٔ برگشتی دوباره ارسال شد")
	return {"id": movement.id, "status": movement.status}


def _contract_discount_percent(raw: Any, fallback: Any) -> Decimal:
	source = raw.get("discount_percent") if isinstance(raw, dict) and raw.get("discount_percent") is not None else fallback
	percent = D(source or 0)
	if percent < 0 or percent - D(100) > MONEY_EPS():
		raise ApiError("DISCOUNT_EXCEEDS_LINE", "درصد تخفیف قلم باید بین صفر و ۱۰۰ باشد.", http_status=400)
	return percent


def _contract_net(unit_price: Any, quantity: Any, percent: Any) -> Decimal:
	gross = D(unit_price) * D(quantity)
	return money(gross - gross * D(percent or 0) / D(100))


def _released_contract_amount(lines: Sequence[Any]) -> Decimal:
	return sum((_contract_net(line.unit_price, line.released_qty, line.discount_percent) for line in lines), D(0))


def create_contract(db: Session, business_id: int, payload: Dict[str, Any], user_id: int) -> Dict[str, Any]:
	person_id = int(payload["person_id"])
	_load_person(db, business_id, person_id)
	items = _parse_item_rows(db, business_id, payload.get("lines"))
	start_date = _parse_date(payload.get("start_date"))
	end_date = _parse_date(payload.get("end_date"))
	if start_date and end_date and end_date < start_date:
		raise ApiError("CONTRACT_DATES_INVALID", "پایان قرارداد نمی‌تواند پیش از شروع باشد.", http_status=400)
	if payload.get("ceiling_amount") not in (None, "") and D(payload.get("ceiling_amount")) < 0:
		raise ApiError("INVALID_AMOUNT", "سقف ریالی قرارداد نمی‌تواند منفی باشد.", http_status=400)
	row = ProcContract(
		business_id=int(business_id),
		code=_code(db, business_id, "proc_contract"),
		person_id=person_id,
		title=str(payload.get("title") or "قرارداد تأمین"),
		kind=str(payload.get("kind") or "blanket") if payload.get("kind") in {"fixed", "blanket", "volume", "recurring"} else "blanket",
		start_date=start_date,
		end_date=end_date,
		currency_id=payload.get("currency_id"),
		ceiling_amount=payload.get("ceiling_amount"),
		payment_terms=payload.get("payment_terms"),
		penalty_note=payload.get("penalty_note"),
		oa_letter_id=payload.get("oa_letter_id"),
		file_id=_owned_file_id(db, business_id, payload.get("file_id")),
		created_by_user_id=int(user_id),
	)
	db.add(row)
	db.flush()
	for item, raw in zip(items, payload.get("lines") or []):
		db.add(
			ProcContractLine(
				contract_id=row.id,
				product_id=item["product_id"],
				description=item["description"],
				unit_price=item["unit_price"],
				qty_commitment=item["qty"],
				discount_percent=_contract_discount_percent(raw, payload.get("discount_percent")),
				warehouse_id=item["warehouse_id"],
			)
		)
	db.flush()
	_audit(db, user_id, business_id, "create", "proc_contract", row.id, f"قرارداد {row.code} ثبت شد")
	return get_contract(db, business_id, row.id)


def _contract(db: Session, business_id: int, contract_id: int) -> ProcContract:
	row = db.query(ProcContract).filter(ProcContract.id == int(contract_id), ProcContract.business_id == int(business_id)).first()
	if not row:
		raise ApiError("CONTRACT_NOT_FOUND", "قرارداد پیدا نشد.", http_status=404)
	return row


def get_contract(db: Session, business_id: int, contract_id: int) -> Dict[str, Any]:
	row = _contract(db, business_id, contract_id)
	lines = db.query(ProcContractLine).filter(ProcContractLine.contract_id == row.id).all()
	guarantees = db.query(ProcGuarantee).filter(ProcGuarantee.business_id == int(business_id), ProcGuarantee.contract_id == row.id).all()
	return {
		"id": row.id,
		"code": row.code,
		"person_id": row.person_id,
		"title": row.title,
		"kind": row.kind,
		"status": row.status,
		"start_date": _iso(row.start_date),
		"end_date": _iso(row.end_date),
		"currency_id": row.currency_id,
		"ceiling_amount": _num(row.ceiling_amount),
		"released_amount": _num(_released_contract_amount(lines)),
		"payment_terms": row.payment_terms,
		"penalty_note": row.penalty_note,
		"oa_letter_id": row.oa_letter_id,
		"file_id": row.file_id,
		"lines": [
			{
				"id": line.id,
				"product_id": line.product_id,
				"description": line.description,
				"unit_price": _num(line.unit_price),
				"item_kind": _kind_from_product(db, business_id, line.product_id),
				"discount_percent": _num(line.discount_percent),
				"warehouse_id": line.warehouse_id,
				"qty_commitment": _num(line.qty_commitment),
				"released_qty": _num(line.released_qty),
			}
			for line in lines
		],
		"guarantees": [{"id": item.id, "kind": item.kind, "amount": _num(item.amount), "due_date": _iso(item.due_date)} for item in guarantees],
	}


def list_contracts(db: Session, business_id: int) -> Dict[str, Any]:
	rows = db.query(ProcContract).filter(ProcContract.business_id == int(business_id)).order_by(ProcContract.id.desc()).all()
	return {"items": [get_contract(db, business_id, row.id) for row in rows]}


def activate_contract(db: Session, business_id: int, contract_id: int, user_id: int) -> Dict[str, Any]:
	row = _contract(db, business_id, contract_id)
	if row.status != "draft":
		raise ApiError("CONTRACT_NOT_DRAFT", "فقط پیش‌نویس فعال می‌شود.", http_status=400)
	if row.end_date and row.end_date < _today():
		raise ApiError("CONTRACT_EXPIRED", "قرارداد منقضی شده است.", http_status=400)
	row.status = "active"
	db.flush()
	_audit(db, user_id, business_id, "activate", "proc_contract", row.id, f"قرارداد {row.code} فعال شد")
	return get_contract(db, business_id, row.id)


def add_guarantee(db: Session, business_id: int, payload: Dict[str, Any], user_id: int) -> Dict[str, Any]:
	contract_id = payload.get("contract_id")
	order_id = payload.get("order_id")
	if not contract_id and not order_id:
		raise ApiError("GUARANTEE_TARGET_REQUIRED", "ضمانت‌نامه به قرارداد یا سفارش وصل می‌شود.", http_status=400)
	if contract_id:
		_contract(db, business_id, int(contract_id))
	order = _require_order(db, business_id, int(order_id)) if order_id else None
	if order and contract_id and (not order.contract_id or int(order.contract_id) != int(contract_id)):
		raise ApiError("GUARANTEE_TARGET_MISMATCH", "سفارش به این قرارداد وصل نیست.", http_status=400)
	row = ProcGuarantee(
		business_id=int(business_id),
		contract_id=int(contract_id) if contract_id else None,
		order_id=order.id if order else None,
		kind=str(payload.get("kind") or "performance"),
		amount=D(payload.get("amount") or 0),
		due_date=_parse_date(payload.get("due_date")),
		file_id=_owned_file_id(db, business_id, payload.get("file_id")),
		note=payload.get("note"),
	)
	if D(row.amount) <= 0:
		raise ApiError("INVALID_AMOUNT", "مبلغ ضمانت باید مثبت باشد.", http_status=400)
	db.add(row)
	db.flush()
	_audit(db, user_id, business_id, "create", "proc_guarantee", row.id, "ضمانت‌نامه ثبت شد")
	return {"id": row.id, "amount": _num(row.amount), "due_date": _iso(row.due_date)}


def release_contract_order(db: Session, business_id: int, contract_id: int, payload: Dict[str, Any], user_id: int) -> Dict[str, Any]:
	contract = _contract(db, business_id, contract_id)
	if contract.status != "active":
		raise ApiError("CONTRACT_INACTIVE", "سفارش فقط از قرارداد فعال آزاد می‌شود.", http_status=400)
	if contract.start_date and contract.start_date > _today():
		raise ApiError("CONTRACT_NOT_STARTED", "آزادسازی پیش از شروع قرارداد ممکن نیست.", http_status=400)
	if contract.end_date and contract.end_date < _today():
		contract.status = "expired"
		db.flush()
		raise ApiError("CONTRACT_EXPIRED", "قرارداد منقضی شده است.", http_status=400)
	lines = {line.id: line for line in db.query(ProcContractLine).filter(ProcContractLine.contract_id == contract.id).all()}
	items = []
	contract_ids = []
	planned = []
	release_value = D(0)
	for index, raw in enumerate(payload.get("lines") or []):
		line = lines.get(int(raw["contract_line_id"]))
		if not line:
			raise ApiError("CONTRACT_LINE_NOT_FOUND", "قلم قرارداد پیدا نشد.", http_status=404)
		quantity = D(raw.get("qty") or 0)
		if quantity <= 0:
			raise ApiError("INVALID_QTY", "مقدار آزادسازی باید مثبت باشد.", http_status=400)
		if line.qty_commitment is not None and D(line.released_qty) + quantity - D(line.qty_commitment) > QTY:
			raise ApiError("CONTRACT_QTY_EXCEEDED", "مقدار از سقف قرارداد بیشتر است.", http_status=400)
		chosen = raw.get("warehouse_id") or line.warehouse_id
		if chosen:
			_require_warehouse(db, business_id, int(chosen))
		planned.append((line, quantity, index, int(chosen) if chosen else None))
		release_value += _contract_net(line.unit_price, quantity, line.discount_percent)
	if not planned:
		raise ApiError("LINES_REQUIRED", "قلم آزادسازی لازم است.", http_status=400)
	if contract.ceiling_amount is not None:
		already = _released_contract_amount(lines.values())
		if already + release_value - D(contract.ceiling_amount) > MONEY_EPS():
			raise ApiError("CONTRACT_CEILING_EXCEEDED", "مبلغ از سقف ریالی قرارداد بیشتر است.", http_status=400)
	for line, quantity, index, warehouse_id in planned:
		line.released_qty = D(line.released_qty) + quantity
		items.append(
			{
				"product_id": line.product_id,
				"description": line.description,
				"item_kind": _kind_from_product(db, business_id, line.product_id),
				"qty": quantity,
				"uom": None,
				"unit_price": D(line.unit_price),
				"discount": money(D(line.unit_price) * quantity * D(line.discount_percent) / D(100)),
				"tax": D(0),
				"warehouse_id": warehouse_id,
				"sort_order": index,
			}
		)
		contract_ids.append(line.id)
	order = _new_order(
		db,
		business_id,
		user_id,
		contract.person_id,
		{
			"contract_id": contract.id,
			"currency_id": contract.currency_id or payload.get("currency_id"),
			"budget_id": payload.get("budget_id"),
			"payment_terms": contract.payment_terms,
		},
	)
	_add_order_lines(db, order, items, contract_line_ids=contract_ids)
	_audit(db, user_id, business_id, "release", "proc_order", order.id, f"سفارش {order.code} از قرارداد {contract.code} آزاد شد")
	return get_order(db, business_id, order.id)


def _period_bounds(period_key: str) -> tuple:
	text = str(period_key or "").strip()
	try:
		year_text, month_text = text.split("-")
		year, month = int(year_text), int(month_text)
		start = date(year, month, 1)
	except Exception as exc:
		raise ApiError("INVALID_PERIOD", "دوره باید به شکل سال-ماه باشد.", http_status=400) from exc
	if month == 12:
		end = date(year + 1, 1, 1)
	else:
		end = date(year, month + 1, 1)
	return start, end


def recompute_score(db: Session, business_id: int, person_id: int, period_key: str, user_id: int) -> Dict[str, Any]:
	_load_person(db, business_id, person_id)
	start, end = _period_bounds(period_key)
	orders = db.query(ProcOrder).filter(ProcOrder.business_id == int(business_id), ProcOrder.person_id == int(person_id)).all()
	order_ids = [order.id for order in orders]
	received = D(0)
	rejected = D(0)
	late = 0
	receipts = 0
	links = []
	if order_ids:
		order_by_id = {order.id: order for order in orders}
		period_receipts = [
			receipt
			for receipt in db.query(ProcReceipt).filter(ProcReceipt.order_id.in_(order_ids)).all()
			if receipt.received_on and start <= receipt.received_on < end
		]
		receipt_ids = [receipt.id for receipt in period_receipts]
		if receipt_ids:
			for line in db.query(ProcReceiptLine).filter(ProcReceiptLine.receipt_id.in_(receipt_ids)).all():
				received += D(line.qty) + D(line.rejected_qty)
				rejected += D(line.rejected_qty)
		for receipt in period_receipts:
			if receipt.note == "supplier_return":
				continue
			receipts += 1
			order = order_by_id.get(receipt.order_id)
			if order and order.delivery_date and receipt.received_on > order.delivery_date:
				late += 1
		links = [
			link
			for link in db.query(ProcInvoiceLink).filter(ProcInvoiceLink.order_id.in_(order_ids)).all()
			if link.created_at and start <= link.created_at.date() < end
		]
	quality = None if received <= 0 else float(money((D(1) - (rejected / received)) * D(100)))
	delivery = None if receipts <= 0 else float(money((D(1) - (D(late) / D(receipts))) * D(100)))
	price = None
	if links:
		bad = len([link for link in links if link.price_variance_accepted or link.match_status == "exception"])
		price = float(money((D(1) - (D(bad) / D(len(links)))) * D(100)))
	profile = _profile(db, business_id, person_id)
	risk = None if not profile or profile.risk_score is None else float(money(D(100) - D(profile.risk_score)))
	metrics = {"price": price, "quality": quality, "delivery": delivery, "risk": risk}
	scored = supplier_score(metrics, _settings(db, business_id).weights)
	safe_weights = _json_safe(scored["weights"])
	row = db.query(ProcScore).filter(ProcScore.business_id == int(business_id), ProcScore.person_id == int(person_id), ProcScore.period_key == period_key).first()
	if not row:
		row = ProcScore(business_id=int(business_id), person_id=int(person_id), period_key=period_key, metrics=metrics, weights=safe_weights, total=scored["total"], grade=scored["grade"])
		db.add(row)
	else:
		row.metrics = metrics
		row.weights = safe_weights
		row.total = scored["total"]
		row.grade = scored["grade"]
	db.flush()
	_audit(db, user_id, business_id, "score", "proc_score", row.id, "امتیاز تأمین‌کننده محاسبه شد", {"total": _num(row.total), "grade": row.grade})
	return {"person_id": person_id, "period_key": period_key, "metrics": metrics, "total": _num(row.total), "grade": row.grade, "weights": safe_weights}


def refresh_reorder(db: Session, business_id: int, user_id: int) -> Dict[str, Any]:
	products = (
		db.query(Product)
		.filter(Product.business_id == int(business_id), Product.track_inventory.is_(True), Product.reorder_point.isnot(None))
		.all()
	)
	created = 0
	for product in products:
		on_hand = D(_stock(db, business_id, int(product.id)))
		open_qty = D(_open_product_qty(db, business_id, int(product.id)))
		suggested = suggested_buy_qty(on_hand=on_hand, open_qty=open_qty, reorder_point=product.reorder_point or 0, min_order_qty=product.min_order_qty or 0)
		existing = (
			db.query(ProcReorderSuggestion)
			.filter(ProcReorderSuggestion.business_id == int(business_id), ProcReorderSuggestion.product_id == product.id, ProcReorderSuggestion.status == "open")
			.first()
		)
		if suggested <= 0:
			if existing:
				existing.status = "dismissed"
			continue
		if not existing:
			existing = ProcReorderSuggestion(business_id=int(business_id), product_id=product.id, suggested_qty=suggested, on_hand=on_hand, open_qty=open_qty)
			db.add(existing)
			created += 1
		else:
			existing.suggested_qty = suggested
			existing.on_hand = on_hand
			existing.open_qty = open_qty
	db.flush()
	_audit(db, user_id, business_id, "refresh", "proc_reorder", business_id, "پیشنهاد خرید از نقطه سفارش به‌روز شد")
	return list_reorder(db, business_id) | {"created": created}


def _last_order_price(db: Session, business_id: int, product_id: int, person_id: int) -> Any:
	found = (
		db.query(ProcOrderLine.unit_price)
		.join(ProcOrder, ProcOrder.id == ProcOrderLine.order_id)
		.filter(
			ProcOrder.business_id == int(business_id),
			ProcOrder.person_id == int(person_id),
			ProcOrderLine.product_id == int(product_id),
		)
		.order_by(ProcOrderLine.id.desc())
		.first()
	)
	return _num(found[0]) if found else None


def _catalog_for_products(db: Session, business_id: int, product_ids: Sequence[int]) -> Dict[int, Dict[str, Any]]:
	if not product_ids:
		return {}
	rows = (
		db.query(ProductSupplier)
		.filter(ProductSupplier.business_id == int(business_id), ProductSupplier.product_id.in_(list(product_ids)))
		.order_by(ProductSupplier.is_preferred.desc(), ProductSupplier.sort_order, ProductSupplier.id)
		.all()
	)
	grouped: Dict[int, List[ProductSupplier]] = {}
	for row in rows:
		grouped.setdefault(int(row.product_id), []).append(row)
	catalog: Dict[int, Dict[str, Any]] = {}
	for product_id, sources in grouped.items():
		chosen = next((row for row in sources if row.is_preferred and row.person_id), None)
		if chosen is None:
			chosen = next((row for row in sources if row.person_id), None)
		if chosen is None:
			chosen = sources[0]
		catalog[product_id] = {
			"source_person_id": chosen.person_id,
			"source_name": chosen.name,
			"source_is_preferred": bool(chosen.is_preferred),
			"last_price": _last_order_price(db, business_id, product_id, int(chosen.person_id)) if chosen.person_id else None,
			"source_count": len(sources),
		}
	return catalog


def list_reorder(db: Session, business_id: int) -> Dict[str, Any]:
	rows = db.query(ProcReorderSuggestion).filter(ProcReorderSuggestion.business_id == int(business_id), ProcReorderSuggestion.status == "open").all()
	products = {}
	catalog: Dict[int, Dict[str, Any]] = {}
	if rows:
		ids = [row.product_id for row in rows]
		for product in db.query(Product).filter(Product.id.in_(ids), Product.business_id == int(business_id)).all():
			products[product.id] = product
		catalog = _catalog_for_products(db, business_id, ids)
	return {
		"items": [
			{
				"id": row.id,
				"product_id": row.product_id,
				"name": products[row.product_id].name if row.product_id in products else None,
				"suggested_qty": _num(row.suggested_qty),
				"on_hand": _num(row.on_hand),
				"open_qty": _num(row.open_qty),
				"lead_time_days": products[row.product_id].lead_time_days if row.product_id in products else None,
				"min_order_qty": products[row.product_id].min_order_qty if row.product_id in products else None,
				"reorder_scope": "product",
				**catalog.get(row.product_id, {"source_person_id": None, "source_name": None, "source_is_preferred": False, "last_price": None, "source_count": 0}),
			}
			for row in rows
		]
	}


def convert_reorder(db: Session, business_id: int, suggestion_id: int, user_id: int) -> Dict[str, Any]:
	row = db.query(ProcReorderSuggestion).filter(ProcReorderSuggestion.id == int(suggestion_id), ProcReorderSuggestion.business_id == int(business_id), ProcReorderSuggestion.status == "open").first()
	if not row:
		raise ApiError("SUGGESTION_NOT_FOUND", "پیشنهاد خرید باز پیدا نشد.", http_status=404)
	product = db.query(Product).filter(Product.id == row.product_id, Product.business_id == int(business_id)).first()
	source = _catalog_for_products(db, business_id, [row.product_id]).get(row.product_id, {})
	reason = "رسیدن به نقطه سفارش"
	if source.get("source_name"):
		reason = f"{reason} — منبع {source['source_name']}"
	line = {
		"product_id": row.product_id,
		"description": product.name if product else "کالا",
		"item_kind": "goods",
		"qty": _num(row.suggested_qty),
	}
	if source.get("last_price") is not None:
		line["unit_price"] = source["last_price"]
	req = create_requisition(
		db,
		business_id,
		{"source": "reorder", "reason": reason, "acknowledge_duplicate": True, "lines": [line]},
		user_id,
	)
	row.status = "converted"
	row.requisition_id = req["id"]
	db.flush()
	return req


def product_sources(db: Session, business_id: int, product_id: int) -> Dict[str, Any]:
	rows = (
		db.query(ProductSupplier)
		.filter(ProductSupplier.business_id == int(business_id), ProductSupplier.product_id == int(product_id))
		.order_by(ProductSupplier.is_preferred.desc(), ProductSupplier.sort_order)
		.all()
	)
	items = []
	for row in rows:
		last = None
		if row.person_id:
			last = _last_order_price(db, business_id, int(product_id), int(row.person_id))
		items.append({"id": row.id, "person_id": row.person_id, "name": row.name, "is_preferred": bool(row.is_preferred), "last_price": last})
	return {"items": items}


def _token_hash(raw: str) -> str:
	return hashlib.sha256(raw.encode("utf-8")).hexdigest()


def create_share_link(db: Session, business_id: int, payload: Dict[str, Any], user_id: int) -> Dict[str, Any]:
	kind = str(payload.get("kind") or "")
	if kind not in {"rfq", "order", "invoice"}:
		raise ApiError("INVALID_SHARE_KIND", "نوع لینک نامعتبر است.", http_status=400)
	person_id = int(payload["person_id"])
	entity_id = int(payload["entity_id"])
	if kind == "rfq":
		invite = (
			db.query(ProcSourcingInvite)
			.filter(
				ProcSourcingInvite.id == entity_id,
				ProcSourcingInvite.business_id == int(business_id),
				ProcSourcingInvite.person_id == person_id,
			)
			.first()
		)
		if not invite:
			raise ApiError("INVITE_NOT_FOUND", "دعوت این تأمین‌کننده پیدا نشد.", http_status=404)
		event = _event(db, business_id, invite.event_id)
		if event.status not in {"draft", "open"}:
			raise ApiError("EVENT_CLOSED", "مهلت پیشنهاد بسته است.", http_status=400)
		if event.deadline_at and event.deadline_at < datetime.utcnow():
			raise ApiError("DEADLINE_PASSED", "مهلت پاسخ گذشته است.", http_status=400)
	else:
		order = _require_order(db, business_id, entity_id)
		if order.person_id != person_id:
			raise ApiError("SHARE_LINK_INVALID", "لینک با تأمین‌کننده سفارش هم‌خوان نیست.", http_status=400)
		if kind == "order" and order.status not in {"sent", "partial", "received", "invoiced"}:
			raise ApiError("ORDER_NOT_SENT", "سفارش هنوز برای تأیید تأمین‌کننده ارسال نشده است.", http_status=400)
		if kind == "invoice" and order.status in {"draft", "pending_approval", "cancelled"}:
			raise ApiError("ORDER_NOT_OPEN", "این سفارش برای اعلام فاکتور باز نیست.", http_status=400)
	limit = datetime.utcnow() + timedelta(days=14)
	requested = _parse_dt(payload.get("expires_at"))
	if requested is not None and requested <= datetime.utcnow():
		raise ApiError("SHARE_EXPIRY_INVALID", "تاریخ انقضای لینک باید در آینده باشد.", http_status=400)
	expires_at = limit if requested is None or requested > limit else requested
	raw = secrets.token_urlsafe(32)
	row = ProcShareLink(
		business_id=int(business_id),
		token_hash=_token_hash(raw),
		kind=kind,
		entity_id=entity_id,
		person_id=person_id,
		expires_at=expires_at,
		created_by_user_id=int(user_id),
	)
	db.add(row)
	db.flush()
	_audit(db, user_id, business_id, "share", "proc_share_link", row.id, "لینک تأمین‌کننده صادر شد")
	return {"id": row.id, "token": raw, "expires_at": _iso(row.expires_at), "kind": kind}


def revoke_share_link(db: Session, business_id: int, link_id: int, user_id: int) -> Dict[str, Any]:
	row = db.query(ProcShareLink).filter(ProcShareLink.id == int(link_id), ProcShareLink.business_id == int(business_id)).first()
	if not row:
		raise ApiError("SHARE_LINK_NOT_FOUND", "لینک تأمین‌کننده پیدا نشد.", http_status=404)
	if row.revoked_at is None:
		row.revoked_at = datetime.utcnow()
		db.flush()
		_audit(db, user_id, business_id, "revoke", "proc_share_link", row.id, "لینک تأمین‌کننده باطل شد")
	return {"id": row.id, "revoked": True}


def _share(db: Session, token: str) -> ProcShareLink:
	row = db.query(ProcShareLink).filter(ProcShareLink.token_hash == _token_hash(token)).first()
	if not row or row.revoked_at is not None or (row.expires_at and row.expires_at < datetime.utcnow()):
		raise ApiError("SHARE_LINK_INVALID", "لینک منقضی یا نامعتبر است.", http_status=404)
	return row


def portal_view(db: Session, token: str) -> Dict[str, Any]:
	link = _share(db, token)
	if link.kind == "rfq":
		invite = db.query(ProcSourcingInvite).filter(ProcSourcingInvite.id == link.entity_id, ProcSourcingInvite.person_id == link.person_id).first()
		if not invite:
			raise ApiError("INVITE_NOT_FOUND", "دعوت پیدا نشد.", http_status=404)
		event = _event(db, link.business_id, invite.event_id)
		if event.status not in {"draft", "open"}:
			raise ApiError("EVENT_CLOSED", "مهلت پیشنهاد بسته است.", http_status=400)
		lines = db.query(ProcSourcingLine).filter(ProcSourcingLine.event_id == event.id).all()
		return {"kind": "rfq", "event_code": event.code, "title": event.title, "deadline_at": _iso(event.deadline_at), "lines": [{"id": line.id, "description": line.description, "qty": _num(line.qty)} for line in lines]}
	if link.kind == "order":
		order = _require_order(db, link.business_id, link.entity_id)
		if order.person_id != link.person_id:
			raise ApiError("SHARE_LINK_INVALID", "لینک با سفارش هم‌خوان نیست.", http_status=404)
		data = get_order(db, link.business_id, order.id)
		return {
			"kind": "order",
			"code": data["code"],
			"status": data["status"],
			"delivery_date": data["delivery_date"],
			"lines": data["lines"],
			"acknowledged_at": data["supplier_acknowledged_at"],
		}
	order = _require_order(db, link.business_id, link.entity_id)
	if order.person_id != link.person_id:
		raise ApiError("SHARE_LINK_INVALID", "لینک با سفارش هم‌خوان نیست.", http_status=404)
	data = get_order(db, link.business_id, order.id)
	return {
		"kind": "invoice",
		"code": data["code"],
		"status": data["status"],
		"lines": [{"description": line["description"], "qty": line["qty"], "unit_price": line["unit_price"]} for line in data["lines"]],
	}


def portal_bid(db: Session, token: str, payload: Dict[str, Any]) -> Dict[str, Any]:
	link = _share(db, token)
	if link.kind != "rfq":
		raise ApiError("WRONG_LINK", "این لینک برای پیشنهاد قیمت نیست.", http_status=400)
	public_payload = dict(payload)
	public_payload.pop("file_id", None)
	return submit_bid(db, link.business_id, link.entity_id, public_payload, None)


def portal_ack(db: Session, token: str) -> Dict[str, Any]:
	link = _share(db, token)
	if link.kind != "order":
		raise ApiError("WRONG_LINK", "این لینک برای تأیید سفارش نیست.", http_status=400)
	order = _require_order(db, link.business_id, link.entity_id)
	if order.person_id != link.person_id:
		raise ApiError("SHARE_LINK_INVALID", "لینک با سفارش هم‌خوان نیست.", http_status=404)
	if order.status not in {"sent", "partial", "received", "invoiced"}:
		raise ApiError("ORDER_NOT_SENT", "سفارش هنوز برای تأیید تأمین‌کننده ارسال نشده است.", http_status=400)
	order.supplier_acknowledged_at = datetime.utcnow()
	db.flush()
	return {"acknowledged_at": _iso(order.supplier_acknowledged_at), "code": order.code}


def portal_invoice_notice(db: Session, token: str, payload: Dict[str, Any]) -> Dict[str, Any]:
	link = _share(db, token)
	if link.kind != "invoice":
		raise ApiError("WRONG_LINK", "این لینک برای اعلام فاکتور نیست.", http_status=400)
	order = _require_order(db, link.business_id, link.entity_id)
	if order.person_id != link.person_id:
		raise ApiError("SHARE_LINK_INVALID", "لینک با سفارش هم‌خوان نیست.", http_status=404)
	if order.status in {"draft", "pending_approval", "cancelled"}:
		raise ApiError("ORDER_NOT_OPEN", "این سفارش برای اعلام فاکتور باز نیست.", http_status=400)
	reference = str(payload.get("reference") or "").strip()
	amount = D(payload.get("amount") or 0)
	if not reference or amount <= 0:
		raise ApiError("INVOICE_NOTICE_INVALID", "شماره و مبلغ فاکتور لازم است.", http_status=400)
	row = ProcPortalInvoice(
		business_id=link.business_id,
		order_id=order.id,
		person_id=link.person_id,
		reference=reference,
		amount=amount,
		note=payload.get("note"),
		file_id=None,
	)
	db.add(row)
	db.flush()
	return {"id": row.id, "reference": row.reference, "amount": _num(row.amount)}


def dashboard(db: Session, business_id: int, user_id: int) -> Dict[str, Any]:
	pending_req = db.query(ProcRequisition).filter(ProcRequisition.business_id == int(business_id), ProcRequisition.status == "pending_approval").count()
	open_orders = db.query(ProcOrder).filter(ProcOrder.business_id == int(business_id), ProcOrder.status.in_(_OPEN_ORDER)).count()
	exceptions = db.query(ProcInvoiceLink).filter(ProcInvoiceLink.business_id == int(business_id), ProcInvoiceLink.match_status == "exception").count()
	today = _today()
	horizon = today + timedelta(days=30)
	expiring = (
		db.query(ProcContract)
		.filter(ProcContract.business_id == int(business_id), ProcContract.status == "active", ProcContract.end_date.isnot(None), ProcContract.end_date <= horizon)
		.all()
	)
	for contract in expiring:
		if contract.last_expiry_notified_on != today:
			_emit(db, business_id, user_id, "procurement.contract.expiring", {"id": contract.id, "code": contract.code, "end_date": _iso(contract.end_date)})
			contract.last_expiry_notified_on = today
	db.flush()
	budgets = list_budgets(db, business_id)["items"]
	return {
		"pending_requisitions": pending_req,
		"open_orders": open_orders,
		"invoice_exceptions": exceptions,
		"expiring_contracts": [{"id": row.id, "code": row.code, "end_date": _iso(row.end_date), "title": row.title} for row in expiring],
		"budget_warnings": [row for row in budgets if row["warn"]],
		"reorder_open": len(list_reorder(db, business_id)["items"]),
	}
