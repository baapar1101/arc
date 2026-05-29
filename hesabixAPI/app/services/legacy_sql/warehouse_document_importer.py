from __future__ import annotations

from collections import defaultdict
from datetime import date
from typing import Any, Callable, Dict, List, Optional, Set, Tuple

from sqlalchemy import and_, select, text
from sqlalchemy.orm import Session

from adapters.db.models.warehouse_document import WarehouseDocument
from app.services.legacy_sql.mappers import (
	INVOICE_TYPE_MAP,
	convert_line_quantity,
	convert_persian_date_to_date,
	convert_timestamp_to_datetime,
	convert_warehouse_doc_type,
)
from app.services.legacy_sql.sql_dump_reader import LegacySqlData
from app.services.warehouse_service import (
	create_manual_warehouse_document,
	post_warehouse_document,
)

ProgressCb = Optional[Callable[[int, str], None]]

INVOICE_OLD_TYPES = frozenset(INVOICE_TYPE_MAP.keys())


class LegacyWarehouseDocumentImporter:
	"""انتقال storeroom_ticket و storeroom_item به حواله انبار."""

	def __init__(self, db: Session, data: LegacySqlData, *, dry_run: bool = False):
		self.db = db
		self.data = data
		self.dry_run = dry_run
		self.stats = {
			"tickets_processed": 0,
			"tickets_migrated": 0,
			"tickets_skipped": 0,
			"lines_skipped": 0,
			"errors": 0,
			"error_samples": [],
		}
		self._items_by_ticket: Dict[int, List[Dict[str, Any]]] | None = None
		self._migrated_ticket_ids: Set[int] = set()
		self._old_doc_to_new: Dict[int, int] = {}
		self._old_doc_types: Dict[int, str] = {}

	def _build_items_index(self) -> Dict[int, List[Dict[str, Any]]]:
		index: Dict[int, List[Dict[str, Any]]] = defaultdict(list)
		for row in self.data.rows("storeroom_item"):
			tid = row.get("ticket_id")
			if tid is None:
				continue
			try:
				index[int(tid)].append(row)
			except (TypeError, ValueError):
				continue
		return dict(index)

	def _build_old_doc_index(self) -> None:
		for doc in self.data.rows("hesabdari_doc"):
			try:
				did = int(doc["id"])
			except (TypeError, ValueError):
				continue
			self._old_doc_types[did] = str(doc.get("type") or "")

	def _load_caches(self, business_id: int) -> None:
		rows = self.db.execute(
			text("""
				SELECT (extra_info->>'old_ticket_id')::int AS tid
				FROM warehouse_documents
				WHERE business_id = :bid
				  AND extra_info->>'source' = 'legacy_sql'
				  AND extra_info->>'old_ticket_id' IS NOT NULL
			"""),
			{"bid": business_id},
		).fetchall()
		for r in rows:
			if r[0] is not None:
				self._migrated_ticket_ids.add(int(r[0]))

		doc_rows = self.db.execute(
			text("""
				SELECT (extra_info->>'old_document_id')::int AS old_id, id
				FROM documents
				WHERE business_id = :bid
				  AND extra_info->>'source' = 'legacy_sql'
				  AND extra_info->>'old_document_id' IS NOT NULL
			"""),
			{"bid": business_id},
		).fetchall()
		for r in doc_rows:
			if r[0] is not None and r[1] is not None:
				self._old_doc_to_new[int(r[0])] = int(r[1])

	def _invoice_wh_exists(self, business_id: int, source_document_id: int) -> bool:
		row = self.db.execute(
			select(WarehouseDocument.id).where(
				and_(
					WarehouseDocument.business_id == business_id,
					WarehouseDocument.source_type == "invoice",
					WarehouseDocument.source_document_id == source_document_id,
				)
			)
		).first()
		return row is not None

	def run(
		self,
		*,
		business_id_map: Dict[int, int],
		user_id_map: Dict[int, int],
		product_id_map: Dict[Tuple[int, int], int],
		warehouse_id_map: Dict[Tuple[int, int], int],
		on_progress: ProgressCb = None,
	) -> Dict[str, Any]:
		self._items_by_ticket = self._build_items_index()
		self._build_old_doc_index()
		tickets = list(self.data.rows("storeroom_ticket"))
		tickets.sort(key=lambda t: (str(t.get("date") or ""), int(t.get("id") or 0)))
		total = len(tickets) or 1

		for i, ticket in enumerate(tickets):
			self.stats["tickets_processed"] += 1
			if on_progress and i % 20 == 0:
				pct = 68 + int(12 * i / total)
				on_progress(min(pct, 80), f"حواله انبار {i + 1}/{total}")
			try:
				self._migrate_ticket(
					ticket,
					business_id_map=business_id_map,
					user_id_map=user_id_map,
					product_id_map=product_id_map,
					warehouse_id_map=warehouse_id_map,
				)
			except Exception as exc:
				self.stats["errors"] += 1
				if len(self.stats["error_samples"]) < 20:
					self.stats["error_samples"].append({
						"old_ticket_id": ticket.get("id"),
						"error": str(exc),
					})

		return dict(self.stats)

	def _migrate_ticket(
		self,
		ticket: Dict[str, Any],
		*,
		business_id_map: Dict[int, int],
		user_id_map: Dict[int, int],
		product_id_map: Dict[Tuple[int, int], int],
		warehouse_id_map: Dict[Tuple[int, int], int],
	) -> None:
		try:
			old_ticket_id = int(ticket["id"])
		except (TypeError, ValueError):
			self.stats["tickets_skipped"] += 1
			return

		old_bid = int(ticket.get("bid_id") or 0)
		new_bid = business_id_map.get(old_bid)
		if not new_bid or new_bid < 0:
			self.stats["tickets_skipped"] += 1
			return

		if not self._migrated_ticket_ids and self.stats["tickets_processed"] == 1:
			self._load_caches(new_bid)
		if old_ticket_id in self._migrated_ticket_ids:
			self.stats["tickets_skipped"] += 1
			return

		new_user_id = user_id_map.get(int(ticket.get("submitter_id") or 0))
		if not new_user_id or new_user_id < 0:
			self.stats["tickets_skipped"] += 1
			return

		old_storeroom_id = int(ticket.get("storeroom_id") or 0)
		new_wh_id = warehouse_id_map.get((old_bid, old_storeroom_id))
		if not new_wh_id or new_wh_id < 0:
			self.stats["tickets_skipped"] += 1
			return

		doc_type = convert_warehouse_doc_type(
			str(ticket.get("type") or ""),
			ticket.get("type_string"),
		)

		items = self._items_by_ticket.get(old_ticket_id, []) if self._items_by_ticket else []
		lines: List[Dict[str, Any]] = []
		for item in items:
			try:
				old_cid = int(item["commodity_id"])
			except (TypeError, ValueError):
				self.stats["lines_skipped"] += 1
				continue
			product_id = product_id_map.get((old_bid, old_cid))
			if not product_id or product_id < 0:
				self.stats["lines_skipped"] += 1
				continue
			qty = convert_line_quantity(item.get("count"))
			if qty <= 0:
				self.stats["lines_skipped"] += 1
				continue
			line: Dict[str, Any] = {
				"product_id": product_id,
				"quantity": float(qty),
				"description": item.get("des"),
			}
			if doc_type == "transfer":
				line["warehouse_id_from"] = new_wh_id
				line["warehouse_id_to"] = new_wh_id
			elif doc_type in ("issue", "production_out"):
				line["warehouse_id"] = new_wh_id
			else:
				line["warehouse_id"] = new_wh_id
			lines.append(line)

		if not lines:
			self.stats["tickets_skipped"] += 1
			return

		doc_date = convert_persian_date_to_date(ticket.get("date"))
		if not doc_date:
			ts = convert_timestamp_to_datetime(ticket.get("date_submit"))
			doc_date = ts.date() if ts else date.today()

		old_doc_id = ticket.get("doc_id")
		source_type = "manual"
		source_document_id: Optional[int] = None
		if old_doc_id is not None:
			try:
				old_did = int(old_doc_id)
				new_src = self._old_doc_to_new.get(old_did)
				old_dtype = self._old_doc_types.get(old_did, "")
				if new_src and old_dtype in INVOICE_OLD_TYPES:
					if self._invoice_wh_exists(new_bid, new_src):
						self.stats["tickets_skipped"] += 1
						return
					source_type = "invoice"
					source_document_id = new_src
			except (TypeError, ValueError):
				pass

		warehouse_id_from = None
		warehouse_id_to = None
		if doc_type == "transfer":
			warehouse_id_from = new_wh_id
			warehouse_id_to = new_wh_id
		elif doc_type in ("issue", "production_out"):
			warehouse_id_from = new_wh_id
		elif doc_type in ("receipt", "production_in"):
			warehouse_id_to = new_wh_id
		else:
			warehouse_id_to = new_wh_id

		payload = {
			"doc_type": doc_type,
			"document_date": doc_date.isoformat(),
			"warehouse_id_from": warehouse_id_from,
			"warehouse_id_to": warehouse_id_to,
			"lines": lines,
			"description": ticket.get("des") or ticket.get("type_string"),
			"extra_info": {
				"source": "legacy_sql",
				"old_ticket_id": old_ticket_id,
				"old_code": ticket.get("code"),
				"type_string": ticket.get("type_string"),
			},
		}

		if self.dry_run:
			self.stats["tickets_migrated"] += 1
			return

		wh = create_manual_warehouse_document(
			self.db, new_bid, new_user_id, payload
		)
		if source_document_id is not None:
			wh.source_type = source_type
			wh.source_document_id = source_document_id
			self.db.flush()

		try:
			post_warehouse_document(
				self.db,
				wh.id,
				stock_exclude_warehouse_document_ids=[wh.id],
			)
		except Exception:
			# حواله به‌صورت پیش‌نویس می‌ماند
			pass

		self.db.commit()
		self._migrated_ticket_ids.add(old_ticket_id)
		self.stats["tickets_migrated"] += 1
