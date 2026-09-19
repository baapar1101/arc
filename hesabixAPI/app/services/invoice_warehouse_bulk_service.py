"""
عملیات گروهی حواله انبار برای فاکتورها: ایجاد پیش‌نویس، صدور (قطعی)، حذف امن.
هر فاکتور در تراکنش جداگانه پردازش می‌شود تا خطای یکی بر بقیه اثر نگذارد.
"""
from __future__ import annotations

from datetime import date
from typing import Any, Dict, List, Tuple

from sqlalchemy import and_
from sqlalchemy.orm import Session

from adapters.db.models.document import Document
from adapters.db.models.warehouse_document import WarehouseDocument
from app.core.responses import ApiError
from app.services.invoice_service import (
	INVOICE_DIRECT_CONSUMPTION,
	INVOICE_PRODUCTION,
	INVOICE_PURCHASE,
	INVOICE_PURCHASE_RETURN,
	INVOICE_SALES,
	INVOICE_SALES_RETURN,
	INVOICE_WASTE,
	SUPPORTED_INVOICE_TYPES,
)
from app.services.warehouse_service import (
	cancel_warehouse_document,
	create_from_invoice,
	delete_warehouse_document,
	invoice_lines_have_trackable_inventory_products,
	post_warehouse_document,
	remaining_invoice_lines_for_warehouse,
)


def create_draft_warehouse_documents_for_invoice_bulk(
	db: Session,
	business_id: int,
	invoice_id: int,
	user_id: int,
) -> Dict[str, Any]:
	"""
	ایجاد حواله(های) پیش‌نویس از فاکتور (بدون پست خودکار)، مشابه منطق _create_warehouse_documents_for_invoice
	اما بدون وابستگی به post_inventory روی سند.
	"""
	inv = db.query(Document).filter(Document.id == invoice_id).first()
	if not inv or int(inv.business_id) != int(business_id):
		return {"ok": False, "code": "INVOICE_NOT_FOUND", "message": "فاکتور یافت نشد"}
	if inv.document_type not in SUPPORTED_INVOICE_TYPES:
		return {"ok": False, "code": "INVALID_INVOICE_TYPE", "message": "نوع سند فاکتور معتبر نیست"}
	if bool(getattr(inv, "is_proforma", False)):
		return {"ok": False, "code": "PROFORMA", "message": "برای پیش‌فاکتور حواله انبار ثبت نمی‌شود"}

	lines_input = remaining_invoice_lines_for_warehouse(db, business_id, inv)
	if not lines_input:
		return {"ok": False, "code": "NOTHING_TO_CREATE", "message": "موجودی قابل ثبت در حواله برای این فاکتور باقی نمانده است"}

	created_ids: List[int] = []

	try:
		if inv.document_type == INVOICE_PRODUCTION:
			out_lines = [ln for ln in lines_input if (ln.get("extra_info") or {}).get("movement") == "out"]
			in_lines = [ln for ln in lines_input if (ln.get("extra_info") or {}).get("movement") == "in"]
			if out_lines and invoice_lines_have_trackable_inventory_products(db, business_id, out_lines):
				wh_issue = create_from_invoice(db, business_id, inv, out_lines, "issue", user_id)
				created_ids.append(int(wh_issue.id))
			if in_lines and invoice_lines_have_trackable_inventory_products(db, business_id, in_lines):
				wh_receipt = create_from_invoice(db, business_id, inv, in_lines, "receipt", user_id)
				created_ids.append(int(wh_receipt.id))
		elif invoice_lines_have_trackable_inventory_products(db, business_id, lines_input):
			if inv.document_type in {INVOICE_SALES, INVOICE_PURCHASE_RETURN, INVOICE_WASTE, INVOICE_DIRECT_CONSUMPTION}:
				wh_type = "issue"
			elif inv.document_type in {INVOICE_PURCHASE, INVOICE_SALES_RETURN}:
				wh_type = "receipt"
			else:
				wh_type = "issue"
			wh = create_from_invoice(db, business_id, inv, lines_input, wh_type, user_id)
			created_ids.append(int(wh.id))
		else:
			return {"ok": False, "code": "NO_TRACKABLE_LINES", "message": "کالای قابل رهگیری انبار در خطوط فاکتور نیست"}
	except ApiError as e:
		return {"ok": False, "code": "CREATE_FAILED", "message": str(e)}

	if not created_ids:
		return {"ok": False, "code": "NOTHING_CREATED", "message": "حواله‌ای ایجاد نشد"}

	return {"ok": True, "created_warehouse_document_ids": created_ids}


def remove_all_invoice_linked_warehouse_documents(
	db: Session,
	business_id: int,
	invoice_id: int,
	user_id: int,
) -> Dict[str, Any]:
	"""
	حذف پیش‌نویس‌ها؛ برای posted لغو + پست معکوس به ترتیب از جدید به قدیم.
	در صورت خطا در هر مرحله، تراکنش برگشت می‌خورد (هیچ تغییری برای این فاکتور باقی نمی‌ماند).
	"""
	inv = db.query(Document).filter(Document.id == invoice_id).first()
	if not inv or int(inv.business_id) != int(business_id):
		return {"ok": False, "code": "INVOICE_NOT_FOUND", "message": "فاکتور یافت نشد"}

	docs = (
		db.query(WarehouseDocument)
		.filter(
			and_(
				WarehouseDocument.business_id == business_id,
				WarehouseDocument.source_type == "invoice",
				WarehouseDocument.source_document_id == invoice_id,
			)
		)
		.all()
	)

	if not docs:
		return {"ok": True, "removed_warehouse_document_ids": [], "message": "حواله مرتبطی با این فاکتور ثبت نشده است"}

	drafts: List[WarehouseDocument] = []
	posted: List[WarehouseDocument] = []
	for wh in docs:
		st = (wh.status or "").strip().lower()
		if st == "cancelled":
			continue
		if st == "draft":
			drafts.append(wh)
		elif st == "posted":
			posted.append(wh)
		else:
			return {
				"ok": False,
				"code": "UNKNOWN_STATUS",
				"message": f"وضعیت حواله {wh.code} پشتیبانی نمی‌شود: {wh.status}",
				"blocking_warehouse_code": wh.code,
			}

	if not drafts and not posted:
		return {
			"ok": True,
			"removed_warehouse_document_ids": [],
			"message": "هیچ حوالهٔ پیش‌نویس یا قطعی قابل حذف برای این فاکتور نیست؛ فقط حوالهٔ لغوشده ثبت شده است.",
		}

	# جدیدترین حوالهٔ قطعی اول لغو می‌شود (مثلاً انتقال بعد از ورود)
	posted.sort(
		key=lambda w: (w.document_date or date.min, w.id or 0),
		reverse=True,
	)

	removed_ids: List[int] = []
	reverse_pairs: List[Dict[str, int]] = []

	try:
		for wh in posted:
			try:
				cancel_wh = cancel_warehouse_document(db, business_id, int(wh.id), user_id)
				post_warehouse_document(db, int(cancel_wh.id))
				removed_ids.append(int(wh.id))
				reverse_pairs.append({"original_id": int(wh.id), "reverse_posted_id": int(cancel_wh.id)})
			except ApiError as e:
				return {
					"ok": False,
					"code": "REVERSE_OR_CANCEL_FAILED",
					"message": str(e),
					"blocking_warehouse_code": wh.code,
					"hint": "احتمالاً حواله‌های بعدی (مثلاً انتقال) از موجودی ایجادشده توسط این حواله استفاده کرده‌اند؛ ابتدا آن حواله‌ها را لغو یا اصلاح کنید.",
				}

		for wh in drafts:
			delete_warehouse_document(db, business_id, int(wh.id))
			removed_ids.append(int(wh.id))

		db.flush()
	except ApiError as e:
		return {
			"ok": False,
			"code": "REMOVE_FAILED",
			"message": str(e),
		}

	return {
		"ok": True,
		"removed_warehouse_document_ids": removed_ids,
		"cancel_reverse_pairs": reverse_pairs,
	}


def _draft_post_sort_key(wh: WarehouseDocument) -> Tuple[int, int]:
	"""خروج/مصرف قبل از ورود (مثلاً تولید: issue سپس receipt)."""
	dt = (wh.doc_type or "").lower()
	if dt in ("issue", "production_out"):
		pri = 0
	elif dt in ("receipt", "production_in"):
		pri = 1
	else:
		pri = 2
	return (pri, int(wh.id or 0))


def post_draft_warehouse_documents_for_invoice_bulk(
	db: Session,
	business_id: int,
	invoice_id: int,
) -> Dict[str, Any]:
	"""قطعی کردن همهٔ پیش‌نویس‌های مرتبط با فاکتور."""
	drafts = (
		db.query(WarehouseDocument)
		.filter(
			and_(
				WarehouseDocument.business_id == business_id,
				WarehouseDocument.source_type == "invoice",
				WarehouseDocument.source_document_id == invoice_id,
			)
		)
		.all()
	)
	drafts = [w for w in drafts if (w.status or "").strip().lower() == "draft"]
	if not drafts:
		return {"ok": False, "code": "NO_DRAFT_TO_POST", "message": "پیش‌نویس حواله‌ای برای صدور وجود ندارد."}

	posted_ids: List[int] = []
	try:
		for wh in sorted(drafts, key=_draft_post_sort_key):
			post_warehouse_document(db, int(wh.id))
			posted_ids.append(int(wh.id))
	except ApiError as e:
		return {
			"ok": False,
			"code": "POST_FAILED",
			"message": str(e),
			"posted_warehouse_document_ids_partial": posted_ids,
		}

	return {"ok": True, "posted_warehouse_document_ids": posted_ids}


def process_post_drafts_with_policy(
	db: Session,
	business_id: int,
	invoice_id: int,
	user_id: int,
	policy: str,
) -> Dict[str, Any]:
	"""
	صدور پیش‌نویس‌ها با سیاست نسبت به حواله‌های قبلاً قطعی‌شده.

	policy:
	- skip: اگر هر حوالهٔ posted مرتبط وجود دارد، این فاکتور رد می‌شود.
	- post_drafts_only: فقط پیش‌نویس‌ها قطعی می‌شود (posted قبلی دست نمی‌خورد).
	- remove_all_then_create_and_post: ابتدا همان منطق حذف امن همه حواله‌های مرتبط، سپس ایجاد پیش‌نویس و صدور.
	"""
	policy = (policy or "skip").strip().lower()
	if policy not in ("skip", "post_drafts_only", "remove_all_then_create_and_post"):
		policy = "skip"

	all_docs = (
		db.query(WarehouseDocument)
		.filter(
			and_(
				WarehouseDocument.business_id == business_id,
				WarehouseDocument.source_type == "invoice",
				WarehouseDocument.source_document_id == invoice_id,
			)
		)
		.all()
	)
	has_posted = any((d.status or "").strip().lower() == "posted" for d in all_docs)
	draft_count = sum(1 for d in all_docs if (d.status or "").strip().lower() == "draft")

	if policy == "skip" and has_posted:
		return {
			"ok": False,
			"code": "HAS_POSTED_SKIPPED",
			"message": "این فاکتور حواله قطعی ثبت‌شده دارد؛ طبق گزینهٔ «رد در صورت وجود قطعی» این فاکتور نادیده گرفته شد.",
			"has_posted_warehouse": True,
		}

	if policy == "remove_all_then_create_and_post":
		rem = remove_all_invoice_linked_warehouse_documents(db, business_id, invoice_id, user_id)
		if not rem.get("ok"):
			return rem
		cr = create_draft_warehouse_documents_for_invoice_bulk(db, business_id, invoice_id, user_id)
		if not cr.get("ok"):
			return cr
		return post_draft_warehouse_documents_for_invoice_bulk(db, business_id, invoice_id)

	if draft_count == 0:
		return {
			"ok": False,
			"code": "NO_DRAFT_TO_POST",
			"message": "پیش‌نویس حواله‌ای برای صدور وجود ندارد.",
		}
	return post_draft_warehouse_documents_for_invoice_bulk(db, business_id, invoice_id)


def run_bulk_warehouse_invoice_operation(
	db: Session,
	business_id: int,
	invoice_id: int,
	operation: str,
	user_id: int,
	*,
	existing_posted_policy: str = "skip",
) -> Dict[str, Any]:
	"""یک فاکتور؛ در صورت موفقیت باید commit شود، در غیر این صورت rollback."""
	op = (operation or "").strip().lower()
	if op == "remove_linked":
		return remove_all_invoice_linked_warehouse_documents(db, business_id, invoice_id, user_id)
	if op == "create_draft":
		return create_draft_warehouse_documents_for_invoice_bulk(db, business_id, invoice_id, user_id)
	if op == "post_drafts":
		return process_post_drafts_with_policy(
			db, business_id, invoice_id, user_id, existing_posted_policy
		)
	return {"ok": False, "code": "INVALID_OPERATION", "message": "عملیات نامعتبر است"}
