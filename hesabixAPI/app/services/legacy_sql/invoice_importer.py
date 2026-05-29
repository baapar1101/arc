from __future__ import annotations

from collections import defaultdict
from datetime import date
from decimal import Decimal
from typing import Any, Callable, Dict, List, Optional, Set, Tuple

from sqlalchemy import text
from sqlalchemy.orm import Session

from app.services.invoice_service import create_invoice
from app.services.legacy_sql.mappers import (
	INVOICE_TYPE_MAP,
	convert_amount,
	convert_persian_date_to_date,
	convert_timestamp_to_datetime,
)
from app.services.legacy_sql.sql_dump_reader import LegacySqlData


ProgressCb = Optional[Callable[[int, str], None]]


class LegacyInvoiceImporter:
	"""انتقال فاکتورهای buy/sell/rfbuy/rfsell از دامپ SQL با invoice_service."""

	INVOICE_DOC_TYPES = frozenset(INVOICE_TYPE_MAP.keys())

	def __init__(self, db: Session, data: LegacySqlData, *, dry_run: bool = False):
		self.db = db
		self.data = data
		self.dry_run = dry_run
		self.stats = {
			"processed": 0,
			"migrated": 0,
			"skipped": 0,
			"errors": 0,
			"error_samples": [],
		}
		self._rows_by_doc: Dict[int, List[Dict[str, Any]]] | None = None
		self._migrated_old_ids: Set[int] = set()

	def _build_rows_index(self) -> Dict[int, List[Dict[str, Any]]]:
		index: Dict[int, List[Dict[str, Any]]] = defaultdict(list)
		for row in self.data.rows("hesabdari_row"):
			doc_id = row.get("doc_id")
			if doc_id is None:
				continue
			try:
				did = int(doc_id)
			except (TypeError, ValueError):
				continue
			index[did].append({
				"ref_id": row.get("ref_id"),
				"person_id": row.get("person_id"),
				"commodity_id": row.get("commodity_id"),
				"debit": row.get("bs"),
				"credit": row.get("bd"),
				"description": row.get("des"),
				"quantity": row.get("commdity_count"),
				"discount": row.get("discount"),
				"tax": row.get("tax"),
			})
		return dict(index)

	def _load_migrated_cache(self, business_id: int) -> None:
		rows = self.db.execute(
			text("""
				SELECT (extra_info->>'old_document_id')::int AS old_id
				FROM documents
				WHERE business_id = :bid
				  AND extra_info->>'source' = 'legacy_sql'
				  AND extra_info->>'old_document_id' IS NOT NULL
			"""),
			{"bid": business_id},
		).fetchall()
		for r in rows:
			if r[0] is not None:
				self._migrated_old_ids.add(int(r[0]))

	def run(
		self,
		*,
		business_id_map: Dict[int, int],
		user_id_map: Dict[int, int],
		person_id_map: Dict[Tuple[int, int], int],
		product_id_map: Dict[Tuple[int, int], int],
		currency_id_map: Dict[int, int],
		fiscal_year_map: Dict[Tuple[int, int], int],
		on_progress: ProgressCb = None,
	) -> Dict[str, Any]:
		self._rows_by_doc = self._build_rows_index()
		docs = [
			d for d in self.data.rows("hesabdari_doc")
			if str(d.get("type") or "") in self.INVOICE_DOC_TYPES
		]
		docs.sort(key=lambda d: (str(d.get("date") or ""), int(d.get("id") or 0)))
		total = len(docs) or 1

		for i, doc in enumerate(docs):
			self.stats["processed"] += 1
			if on_progress and i % 10 == 0:
				pct = 70 + int(25 * i / total)
				on_progress(min(pct, 95), f"فاکتور {i + 1}/{total}")
			try:
				self._migrate_one(
					doc,
					business_id_map=business_id_map,
					user_id_map=user_id_map,
					person_id_map=person_id_map,
					product_id_map=product_id_map,
					currency_id_map=currency_id_map,
					fiscal_year_map=fiscal_year_map,
				)
			except Exception as exc:
				self.stats["errors"] += 1
				if len(self.stats["error_samples"]) < 20:
					self.stats["error_samples"].append({
						"old_doc_id": doc.get("id"),
						"code": doc.get("code"),
						"type": doc.get("type"),
						"error": str(exc),
					})

		return dict(self.stats)

	def _migrate_one(
		self,
		doc: Dict[str, Any],
		*,
		business_id_map: Dict[int, int],
		user_id_map: Dict[int, int],
		person_id_map: Dict[Tuple[int, int], int],
		product_id_map: Dict[Tuple[int, int], int],
		currency_id_map: Dict[int, int],
		fiscal_year_map: Dict[Tuple[int, int], int],
	) -> None:
		old_doc_id = int(doc["id"])
		old_bid = int(doc["bid_id"])
		new_bid = business_id_map.get(old_bid)
		if not new_bid:
			self.stats["skipped"] += 1
			return

		if not self._migrated_old_ids and self.stats["processed"] == 1:
			self._load_migrated_cache(new_bid)

		if old_doc_id in self._migrated_old_ids:
			self.stats["skipped"] += 1
			return

		old_type = str(doc.get("type") or "")
		invoice_type = INVOICE_TYPE_MAP.get(old_type)
		if not invoice_type:
			self.stats["skipped"] += 1
			return

		new_user_id = user_id_map.get(int(doc.get("submitter_id") or 0))
		if not new_user_id:
			self.stats["skipped"] += 1
			return

		old_money = int(doc.get("money_id") or 1)
		currency_id = currency_id_map.get(old_money)
		if not currency_id:
			from adapters.db.models.business import Business

			biz = self.db.get(Business, new_bid)
			currency_id = biz.default_currency_id if biz else None
		if not currency_id:
			self.stats["skipped"] += 1
			return

		old_year = int(doc.get("year_id") or 0)
		fiscal_year_id = fiscal_year_map.get((old_bid, old_year))
		if not fiscal_year_id:
			from adapters.db.repositories.fiscal_year_repo import FiscalYearRepository

			fy = FiscalYearRepository(self.db).get_current_for_business(new_bid)
			fiscal_year_id = fy.id if fy else None
		if not fiscal_year_id:
			self.stats["skipped"] += 1
			return

		doc_date = convert_persian_date_to_date(doc.get("date"))
		if not doc_date:
			ts = convert_timestamp_to_datetime(doc.get("date_submit"))
			doc_date = ts.date() if ts else date.today()

		rows = self._rows_by_doc.get(old_doc_id, []) if self._rows_by_doc else []
		if not rows:
			self.stats["skipped"] += 1
			return

		person_id = None
		for row in rows:
			pid = row.get("person_id")
			if pid is None:
				continue
			try:
				mapped = person_id_map.get((old_bid, int(pid)))
			except (TypeError, ValueError):
				mapped = None
			if mapped:
				person_id = mapped
				break
		if not person_id:
			self.stats["skipped"] += 1
			return

		lines: List[Dict[str, Any]] = []
		for row in rows:
			cid = row.get("commodity_id")
			if not cid:
				continue
			try:
				product_id = product_id_map.get((old_bid, int(cid)))
			except (TypeError, ValueError):
				product_id = None
			if not product_id:
				continue
			debit = convert_amount(row.get("debit"))
			credit = convert_amount(row.get("credit"))
			qty = convert_amount(row.get("quantity") or 1)
			if qty <= 0:
				qty = Decimal(1)
			unit_price = (debit + credit) / qty
			discount_amt = convert_amount(row.get("discount") or 0)
			tax_amt = convert_amount(row.get("tax") or 0)
			taxable = (qty * unit_price) - discount_amt
			tax_percent = float((tax_amt / taxable) * 100) if taxable > 0 and tax_amt > 0 else 0.0
			lines.append({
				"product_id": product_id,
				"quantity": float(qty),
				"extra_info": {
					"unit_price": float(unit_price),
					"line_discount": float(discount_amt),
					"tax_amount": float(tax_amt),
					"tax_rate": tax_percent,
				},
				"description": row.get("description"),
			})

		if not lines:
			self.stats["skipped"] += 1
			return

		payload = {
			"invoice_type": invoice_type,
			"document_date": doc_date.isoformat(),
			"currency_id": currency_id,
			"fiscal_year_id": fiscal_year_id,
			"person_id": person_id,
			"lines": lines,
			"description": doc.get("des") or "",
			"extra_info": {
				"source": "legacy_sql",
				"old_document_id": old_doc_id,
				"old_code": doc.get("code"),
				"old_type": old_type,
			},
		}

		if self.dry_run:
			self.stats["migrated"] += 1
			return

		create_invoice(
			db=self.db,
			business_id=new_bid,
			user_id=new_user_id,
			data=payload,
		)
		self.db.commit()
		self._migrated_old_ids.add(old_doc_id)
		self.stats["migrated"] += 1
