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
from app.services.receipt_payment_service import create_receipt_payment

ProgressCb = Optional[Callable[[int, str], None]]

RECEIPT_PAYMENT_DOC_TYPES: Dict[str, str] = {
	"person_receive": "receipt",
	"person_send": "payment",
	"sell_receive": "receipt",
	"buy_send": "payment",
}


class LegacyReceiptPaymentImporter:
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
			index[did].append(row)
		return dict(index)

	def _load_migrated_cache(self, business_id: int) -> None:
		rows = self.db.execute(
			text("""
				SELECT (extra_info->>'old_document_id')::int AS old_id
				FROM documents
				WHERE business_id = :bid
				  AND extra_info->>'source' = 'legacy_sql'
				  AND document_type IN ('receipt', 'payment')
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
		bank_id_map: Dict[Tuple[int, int], int],
		cashdesk_id_map: Dict[Tuple[int, int], int],
		petty_id_map: Dict[Tuple[int, int], int],
		currency_id_map: Dict[int, int],
		on_progress: ProgressCb = None,
	) -> Dict[str, Any]:
		self._rows_by_doc = self._build_rows_index()
		docs = [
			d for d in self.data.rows("hesabdari_doc")
			if str(d.get("type") or "") in RECEIPT_PAYMENT_DOC_TYPES
		]
		docs.sort(key=lambda d: (str(d.get("date") or ""), int(d.get("id") or 0)))
		total = len(docs) or 1

		for i, doc in enumerate(docs):
			self.stats["processed"] += 1
			if on_progress and i % 10 == 0:
				pct = 82 + int(10 * i / total)
				on_progress(min(pct, 92), f"دریافت/پرداخت {i + 1}/{total}")
			try:
				self._migrate_one(
					doc,
					business_id_map=business_id_map,
					user_id_map=user_id_map,
					person_id_map=person_id_map,
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
						"type": doc.get("type"),
						"error": str(exc),
					})
		return dict(self.stats)

	def _line_amount(self, row: Dict[str, Any]) -> float:
		d = convert_amount(row.get("bs"))
		c = convert_amount(row.get("bd"))
		return float(d if d > 0 else c)

	def _detect_transaction(self, row: Dict[str, Any]) -> Tuple[Optional[str], Dict[str, Any]]:
		if row.get("cheque_id"):
			return "check", {"check_id": int(row["cheque_id"])}
		if row.get("bank_id"):
			return "bank", {"bank_id": int(row["bank_id"])}
		if row.get("cashdesk_id"):
			return "cash_register", {"cash_register_id": int(row["cashdesk_id"])}
		if row.get("salary_id"):
			return "petty_cash", {"petty_cash_id": int(row["salary_id"])}
		return None, {}

	def _migrate_one(
		self,
		doc: Dict[str, Any],
		*,
		business_id_map: Dict[int, int],
		user_id_map: Dict[int, int],
		person_id_map: Dict[Tuple[int, int], int],
		bank_id_map: Dict[int, int],
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

		old_type = str(doc.get("type") or "")
		document_type = RECEIPT_PAYMENT_DOC_TYPES.get(old_type)
		if not document_type:
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
		if not rows:
			self.stats["skipped"] += 1
			return

		person_lines: List[Dict[str, Any]] = []
		account_lines: List[Dict[str, Any]] = []

		for row in rows:
			amount = self._line_amount(row)
			if amount <= 0:
				continue
			pid = row.get("person_id")
			if pid is not None:
				try:
					new_pid = person_id_map.get((old_bid, int(pid)))
				except (TypeError, ValueError):
					new_pid = None
				if is_valid_mapped_id(new_pid, dry_run=self.dry_run):
					person_lines.append({
						"person_id": new_pid,
						"amount": amount,
						"description": row.get("des"),
					})

			tx_type, tx_extra = self._detect_transaction(row)
			if tx_type:
				acc_amount = amount
				acc_line: Dict[str, Any] = {
					"amount": acc_amount,
					"transaction_type": tx_type,
					"description": row.get("des"),
				}
				if tx_type == "bank":
					ob = row.get("bank_id")
					nb = bank_id_map.get((old_bid, int(ob))) if ob is not None else None
					if not is_valid_mapped_id(nb, dry_run=self.dry_run):
						continue
					acc_line["bank_id"] = nb
				elif tx_type == "cash_register":
					oc = row.get("cashdesk_id")
					nc = cashdesk_id_map.get((old_bid, int(oc))) if oc is not None else None
					if not is_valid_mapped_id(nc, dry_run=self.dry_run):
						continue
					acc_line["cash_register_id"] = nc
				elif tx_type == "petty_cash":
					os = row.get("salary_id")
					ns = petty_id_map.get((old_bid, int(os))) if os is not None else None
					if not is_valid_mapped_id(ns, dry_run=self.dry_run):
						continue
					acc_line["petty_cash_id"] = ns
				else:
					acc_line.update(tx_extra)
				account_lines.append(acc_line)

		if not person_lines or not account_lines:
			self.stats["skipped"] += 1
			return

		doc_date = convert_persian_date_to_date(doc.get("date"))
		if not doc_date:
			ts = convert_timestamp_to_datetime(doc.get("date_submit"))
			doc_date = ts.date() if ts else date.today()

		payload = {
			"document_type": document_type,
			"document_date": doc_date.isoformat(),
			"currency_id": currency_id,
			"person_lines": person_lines,
			"account_lines": account_lines,
			"description": doc.get("des") or "",
			"extra_info": {
				"source": "legacy_sql",
				"old_document_id": old_doc_id,
				"old_type": old_type,
			},
		}

		if self.dry_run:
			self.stats["migrated"] += 1
			return

		create_receipt_payment(
			self.db,
			new_bid,
			new_user_id,
			payload,
		)
		self.db.commit()
		self._migrated_old_ids.add(old_doc_id)
		self.stats["migrated"] += 1
