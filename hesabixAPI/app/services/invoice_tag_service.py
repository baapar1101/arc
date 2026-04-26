from __future__ import annotations

import logging
from typing import Any, Dict, List, Optional, Set

from sqlalchemy import and_, exists, func, select
from sqlalchemy.orm import Session

from app.core.responses import ApiError
from adapters.db.models.document import Document
from adapters.db.models.document_invoice_tag import DocumentInvoiceTag, DocumentInvoiceTagLink

logger = logging.getLogger(__name__)

# برچسب‌های پیش‌فرض (هر کسب‌وکار در اولین درخواست لیست تگ ساخته می‌شوند)
DEFAULT_INVOICE_TAG_NAMES: List[str] = [
	"فروش سایت",
	"دیجیکالا",
	"باسلام",
	"اسنپ‌شاپ",
	"اسنپ‌فود",
	"فروش حضوری",
	"آگهی دیوار",
	"سایر",
]


def _tag_to_dict(t: DocumentInvoiceTag) -> Dict[str, Any]:
	return {
		"id": t.id,
		"name": t.name,
		"color": t.color,
		"is_system": bool(t.is_system),
		"is_active": bool(t.is_active),
		"sort_order": int(t.sort_order or 0),
	}


def ensure_default_invoice_tags_for_business(db: Session, business_id: int) -> None:
	"""در صورت خالی بودن، برچسب‌های پیش‌فرض را در همان تراکنش session اضافه می‌کند."""
	cnt = (
		db.query(func.count())
		.select_from(DocumentInvoiceTag)
		.filter(DocumentInvoiceTag.business_id == business_id)
		.scalar()
	)
	if cnt and int(cnt) > 0:
		return
	for i, name in enumerate(DEFAULT_INVOICE_TAG_NAMES):
		db.add(
			DocumentInvoiceTag(
				business_id=business_id,
				name=name,
				color=None,
				is_system=True,
				is_active=True,
				sort_order=i,
			)
		)
	db.flush()


def list_invoice_tags(db: Session, business_id: int, include_inactive: bool = False) -> List[Dict[str, Any]]:
	ensure_default_invoice_tags_for_business(db, business_id)
	q = db.query(DocumentInvoiceTag).filter(DocumentInvoiceTag.business_id == business_id)
	if not include_inactive:
		q = q.filter(DocumentInvoiceTag.is_active == True)  # noqa: E711
	rows = q.order_by(DocumentInvoiceTag.sort_order.asc(), DocumentInvoiceTag.id.asc()).all()
	return [_tag_to_dict(t) for t in rows]


def create_invoice_tag(
	db: Session, business_id: int, name: str, color: Optional[str] = None
) -> Dict[str, Any]:
	name = (name or "").strip()
	if not name:
		raise ApiError("INVALID_NAME", "نام برچسب الزامی است", http_status=400)
	if len(name) > 120:
		raise ApiError("INVALID_NAME", "نام برچسب بیش‌از حد طولانی است", http_status=400)
	dup = (
		db.query(DocumentInvoiceTag)
		.filter(
			and_(
				DocumentInvoiceTag.business_id == business_id,
				DocumentInvoiceTag.name == name,
			)
		)
		.first()
	)
	if dup is not None:
		raise ApiError("TAG_NAME_DUPLICATE", "برچسبی با این نام از قبل وجود دارد", http_status=400)
	mx = (
		db.query(func.max(DocumentInvoiceTag.sort_order))
		.filter(DocumentInvoiceTag.business_id == business_id)
		.scalar()
	)
	so = int(mx or 0) + 1
	t = DocumentInvoiceTag(
		business_id=business_id,
		name=name,
		color=(color or None) and str(color)[:32],
		is_system=False,
		is_active=True,
		sort_order=so,
	)
	db.add(t)
	db.commit()
	db.refresh(t)
	return _tag_to_dict(t)


def update_invoice_tag(
	db: Session, business_id: int, tag_id: int, data: Dict[str, Any]
) -> Dict[str, Any]:
	t = (
		db.query(DocumentInvoiceTag)
		.filter(DocumentInvoiceTag.id == tag_id, DocumentInvoiceTag.business_id == business_id)
		.first()
	)
	if t is None:
		raise ApiError("TAG_NOT_FOUND", "برچسب یافت نشد", http_status=404)
	if "name" in data and data["name"] is not None:
		new_name = str(data["name"]).strip()
		if not new_name:
			raise ApiError("INVALID_NAME", "نام برچسب نامعتبر است", http_status=400)
		od = (
			db.query(DocumentInvoiceTag)
			.filter(
				and_(
					DocumentInvoiceTag.business_id == business_id,
					DocumentInvoiceTag.name == new_name,
					DocumentInvoiceTag.id != tag_id,
				)
			)
			.first()
		)
		if od is not None:
			raise ApiError("TAG_NAME_DUPLICATE", "برچسبی با این نام از قبل وجود دارد", http_status=400)
		t.name = new_name
	if "color" in data:
		t.color = (str(data["color"])[:32] if data["color"] is not None else None) or None
	if "is_active" in data and data["is_active"] is not None:
		t.is_active = bool(data["is_active"])
	if "sort_order" in data and data["sort_order"] is not None:
		t.sort_order = int(data["sort_order"])
	db.commit()
	db.refresh(t)
	return _tag_to_dict(t)


def replace_document_invoice_tags(
	db: Session, business_id: int, document_id: int, tag_ids: Optional[List[Any]]
) -> None:
	"""جایگزینی کامل برچسب‌های سند. اگر tag_ids == [] لینک‌ها حذف می‌شوند. None = بدون تغییر."""
	if tag_ids is None:
		return
	ids: List[int] = []
	seen: Set[int] = set()
	for x in tag_ids:
		try:
			v = int(x)
		except (TypeError, ValueError):
			raise ApiError("INVALID_TAG_IDS", "شناسه برچسب نامعتبر است", http_status=400)
		if v not in seen:
			seen.add(v)
			ids.append(v)
	if ids:
		ensure_default_invoice_tags_for_business(db, business_id)
	db.query(DocumentInvoiceTagLink).filter(DocumentInvoiceTagLink.document_id == document_id).delete(
		synchronize_session=False
	)
	if not ids:
		return
	q = (
		db.query(DocumentInvoiceTag)
		.filter(
			and_(
				DocumentInvoiceTag.business_id == business_id,
				DocumentInvoiceTag.id.in_(ids),
				DocumentInvoiceTag.is_active == True,  # noqa: E711
			)
		)
		.all()
	)
	if len(q) != len(set(ids)):
		raise ApiError("INVALID_TAG_IDS", "یک یا چند برچسب نامعتبر یا غیرفعال است", http_status=400)
	for tid in ids:
		db.add(DocumentInvoiceTagLink(document_id=document_id, tag_id=tid))
	db.flush()


def get_tags_map_for_document_ids(
	db: Session, business_id: int, document_ids: List[int]
) -> Dict[int, List[Dict[str, Any]]]:
	if not document_ids:
		return {}
	rows = (
		db.query(DocumentInvoiceTagLink, DocumentInvoiceTag)
		.join(DocumentInvoiceTag, DocumentInvoiceTag.id == DocumentInvoiceTagLink.tag_id)
		.filter(
			DocumentInvoiceTagLink.document_id.in_(document_ids),
			DocumentInvoiceTag.business_id == business_id,
			DocumentInvoiceTag.is_active == True,  # noqa: E711
		)
		.order_by(
			DocumentInvoiceTagLink.document_id.asc(),
			DocumentInvoiceTag.sort_order.asc(),
			DocumentInvoiceTag.id.asc(),
		)
		.all()
	)
	out: Dict[int, List[Dict[str, Any]]] = {i: [] for i in document_ids}
	for _link, tag in rows:
		did = int(_link.document_id)
		if did not in out:
			continue
		out[did].append(
			{
				"id": tag.id,
				"name": tag.name,
				"color": tag.color,
			}
		)
	return out


def tags_for_single_document(
	db: Session, business_id: int, document_id: int
) -> tuple[List[Dict[str, Any]], str]:
	m = get_tags_map_for_document_ids(db, business_id, [document_id])
	lst = m.get(document_id, [])
	return lst, "، ".join(t.get("name", "") for t in lst) if lst else ""


def attach_tags_to_invoice_items(
	db: Session, business_id: int, items: List[Dict[str, Any]]
) -> None:
	if not items:
		return
	ids: List[int] = []
	for it in items:
		try:
			ids.append(int(it["id"]))
		except Exception:
			continue
	m = get_tags_map_for_document_ids(db, business_id, ids)
	for it in items:
		try:
			iid = int(it["id"])
		except Exception:
			continue
		tags = m.get(iid, [])
		it["tags"] = tags
		it["tags_display"] = "، ".join(t.get("name", "") for t in tags) if tags else ""


def apply_invoice_tag_filters_to_query(q, body: Dict[str, Any]):  # returns same query type
	"""body: tag_ids (list), tag_match: any | all"""
	raw = body.get("tag_ids")
	if raw is None:
		return q
	ids: List[int] = []
	if isinstance(raw, (list, tuple, set)):
		for x in raw:
			try:
				ids.append(int(x))
			except (TypeError, ValueError):
				continue
	elif isinstance(raw, (int, str)) and str(raw).strip():
		try:
			ids.append(int(raw))
		except (TypeError, ValueError):
			pass
	if not ids:
		return q
	match = (body.get("tag_match") or "any").strip().lower()
	if match not in ("any", "all"):
		match = "any"

	Link = DocumentInvoiceTagLink
	Tag = DocumentInvoiceTag

	if match == "any":
		sub = (
			select(1)
			.select_from(Link)
			.join(Tag, Tag.id == Link.tag_id)
			.where(
				and_(
					Link.document_id == Document.id,
					Link.tag_id.in_(ids),
					Tag.is_active == True,  # noqa: E711
				)
			)
		)
		return q.filter(exists(sub))
	# all: باید به ازای هر tag_id حداقل یک لینک وجود داشته باشد
	for tid in ids:
		sub = (
			select(1)
			.select_from(Link)
			.join(Tag, Tag.id == Link.tag_id)
			.where(
				and_(
					Link.document_id == Document.id,
					Link.tag_id == int(tid),
					Tag.is_active == True,  # noqa: E711
				)
			)
		)
		q = q.filter(exists(sub))
	return q
