from __future__ import annotations

from collections import defaultdict
from datetime import date
from typing import Any, Callable, Dict, List, Optional, Set, Tuple

from sqlalchemy import text
from sqlalchemy.orm import Session

from app.services.legacy_sql.mappers import (
	convert_amount,
	convert_persian_date_to_date,
	convert_timestamp_to_datetime,
	is_valid_mapped_id,
)
from app.services.legacy_sql.sql_dump_reader import LegacySqlData
from app.services.transfer_service import create_transfer

ProgressCb = Optional[Callable[[int, str], None]]


class LegacyTransferImporter:
	"""انتقال اسناد hesabdari_doc با type=transfer."""

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
				index[int(doc_id)].append(row)
			except (TypeError, ValueError):
				continue
		return dict(index)

	def _load_migrated_cache(self, business_id: int) -> None:
		rows = self.db.execute(
			text("""
				SELECT (extra_info->>'old_document_id')::int AS old_id
				FROM documents
				WHERE business_id = :bid
				  AND document_type = 'transfer'
				  AND extra_info->>'source' = 'legacy_sql'
				  AND extra_info->>'old_document_id' IS NOT NULL
			"""),
			{"bid": business_id},
		).fetchall()
		for r in rows:
			if r[0] is not None:
				self._migrated_old_ids.add(int(r[0]))

	def _resolve_side(
		self,
		row: Dict[str, Any],
		old_bid: int,
		*,
		bank_id_map: Dict[Tuple[int, int], int],
		cashdesk_id_map: Dict[Tuple[int, int], int],
		petty_id_map: Dict[Tuple[int, int], int],
	) -> Optional[Tuple[str, Dict[str, Any], float]]:
		debit = convert_amount(row.get("bs"))
		credit = convert_amount(row.get("bd"))
		if debit > 0 and credit > 0:
			return None
		amount = float(debit if debit > 0 else credit)
		if amount <= 0:
			return None
		side = "source" if debit > 0 else "destination"

		if row.get("bank_id") is not None:
			try:
				nb = bank_id_map.get((old_bid, int(row["bank_id"])))
			except (TypeError, ValueError):
				nb = None
			if is_valid_mapped_id(nb, dry_run=self.dry_run):
				return side, {"type": "bank", "id": nb}, amount
		if row.get("cashdesk_id") is not None:
			try:
				nc = cashdesk_id_map.get((old_bid, int(row["cashdesk_id"])))
			except (TypeError, ValueError):
				nc = None
			if is_valid_mapped_id(nc, dry_run=self.dry_run):
				return side, {"type": "cash_register", "id": nc}, amount
		if row.get("salary_id") is not None:
			try:
				np = petty_id_map.get((old_bid, int(row["salary_id"])))
			except (TypeError, ValueError):
				np = None
			if is_valid_mapped_id(np, dry_run=self.dry_run):
				return side, {"type": "petty_cash", "id": np}, amount
		return None

	def run(
		self,
		*,
		business_id_map: Dict[int, int],
		user_id_map: Dict[int, int],
		bank_id_map: Dict[Tuple[int, int], int],
		cashdesk_id_map: Dict[Tuple[int, int], int],
		petty_id_map: Dict[Tuple[int, int], int],
		currency_id_map: Dict[int, int],
		on_progress: ProgressCb = None,
	) -> Dict[str, Any]:
		self._rows_by_doc = self._build_rows_index()
		docs = [d for d in self.data.rows("hesabdari_doc") if str(d.get("type") or "") == "transfer"]
		docs.sort(key=lambda d: (str(d.get("date") or ""), int(d.get("id") or 0)))
		total = len(docs) or 1

		for i, doc in enumerate(docs):
			self.stats["processed"] += 1
			if on_progress and i % 5 == 0:
				pct = 92 + int(5 * i / total)
				on_progress(min(pct, 97), f"انتقال وجه {i + 1}/{total}")
			try:
				self._migrate_one(
					doc,
					business_id_map=business_id_map,
					user_id_map=user_id_map,
					bank_id_map=bank_id_map,
					cashdesk_id_map=cashdesk_id_map,
					petty_id_map=petty_id_map,
					currency_id_map=currency_id_map,
				)
			except Exception as exc:
				self.stats["errors"] += 1
				if len(self.stats["error_samples"]) < 20:
					self.stats["error_samples"].append({
						"old_doc_id": doc.get("id"),
						"error": str(exc),
					})
		return dict(self.stats)

	def _migrate_one(
		self,
		doc: Dict[str, Any],
		*,
		business_id_map: Dict[int, int],
		user_id_map: Dict[int, int],
		bank_id_map: Dict[Tuple[int, int], int],
		cashdesk_id_map: Dict[Tuple[int, int], int],
		petty_id_map: Dict[Tuple[int, int], int],
		currency_id_map: Dict[int, int],
	) -> None:
		old_doc_id = int(doc["id"])
		old_bid = int(doc["bid_id"])
		new_bid = business_id_map.get(old_bid)
		if not new_bid or new_bid < 0:
			self.stats["skipped"] += 1
			return

		if not self._migrated_old_ids and self.stats["processed"] == 1:
			self._load_migrated_cache(new_bid)
		if old_doc_id in self._migrated_old_ids:
			self.stats["skipped"] += 1
			return

		new_user_id = user_id_map.get(int(doc.get("submitter_id") or 0))
		if not new_user_id or new_user_id < 0:
			self.stats["skipped"] += 1
			return

		currency_id = currency_id_map.get(int(doc.get("money_id") or 1))
		if not currency_id:
			self.stats["skipped"] += 1
			return

		rows = self._rows_by_doc.get(old_doc_id, []) if self._rows_by_doc else []
		source: Optional[Dict[str, Any]] = None
		destination: Optional[Dict[str, Any]] = None
		amount: float = 0.0

		for row in rows:
			parsed = self._resolve_side(
				row,
				old_bid,
				bank_id_map=bank_id_map,
				cashdesk_id_map=cashdesk_id_map,
				petty_id_map=petty_id_map,
			)
			if not parsed:
				continue
			side, endpoint, amt = parsed
			if side == "source":
				source = endpoint
				if amt > 0:
					amount = amt
			else:
				destination = endpoint
				if amt > 0 and amount <= 0:
					amount = amt

		if not source or not destination or amount <= 0:
			doc_amount = convert_amount(doc.get("amount"))
			if doc_amount > 0:
				amount = float(doc_amount)
		if not source or not destination or amount <= 0:
			self.stats["skipped"] += 1
			return

		doc_date = convert_persian_date_to_date(doc.get("date"))
		if not doc_date:
			ts = convert_timestamp_to_datetime(doc.get("date_submit"))
			doc_date = ts.date() if ts else date.today()

		payload = {
			"document_date": doc_date.isoformat(),
			"currency_id": currency_id,
			"source": source,
			"destination": destination,
			"amount": amount,
			"description": doc.get("des") or "",
			"extra_info": {
				"source": "legacy_sql",
				"old_document_id": old_doc_id,
				"old_code": doc.get("code"),
			},
		}

		if self.dry_run:
			self.stats["migrated"] += 1
			return

		create_transfer(self.db, new_bid, new_user_id, payload, commit=False)
		self.db.commit()
		self._migrated_old_ids.add(old_doc_id)
		self.stats["migrated"] += 1
