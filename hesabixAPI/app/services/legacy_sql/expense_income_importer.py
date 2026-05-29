from __future__ import annotations

from collections import defaultdict
from datetime import date
from typing import Any, Callable, Dict, List, Optional, Set, Tuple

from sqlalchemy import text
from sqlalchemy.orm import Session

from app.services.expense_income_service import create_expense_income
from app.services.legacy_sql.legacy_account_resolver import (
	build_ref_id_index,
	resolve_account_id_for_ref,
)
from app.services.legacy_sql.mappers import (
	convert_amount,
	convert_persian_date_to_date,
	convert_timestamp_to_datetime,
)
from app.services.legacy_sql.sql_dump_reader import LegacySqlData

ProgressCb = Optional[Callable[[int, str], None]]

EXPENSE_INCOME_TYPES = {
	"cost": "expense",
	"income": "income",
}

# ref_idهای شناخته‌شده طرف حساب / کالا — سطر هزینه/درآمد حساب calc/person نیست
_SKIP_REF_IDS = frozenset({3, 5, 8, 121, 122, 123, 124, 125, 137})


class LegacyExpenseIncomeImporter:
	def __init__(self, db: Session, data: LegacySqlData, *, dry_run: bool = False):
		self.db = db
		self.data = data
		self.dry_run = dry_run
		self.ref_index = build_ref_id_index(data)
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
				pass
		return dict(index)

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
			if str(d.get("type") or "") in EXPENSE_INCOME_TYPES
		]
		docs.sort(key=lambda d: (str(d.get("date") or ""), int(d.get("id") or 0)))
		total = len(docs) or 1

		for i, doc in enumerate(docs):
			self.stats["processed"] += 1
			if on_progress and i % 5 == 0:
				on_progress(93 + int(4 * i / total), f"هزینه/درآمد {i + 1}/{total}")
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
				if len(self.stats["error_samples"]) < 15:
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

		if old_doc_id in self._migrated_old_ids:
			self.stats["skipped"] += 1
			return

		old_type = str(doc.get("type") or "")
		document_type = EXPENSE_INCOME_TYPES.get(old_type)
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

		rows = self._rows_by_doc.get(old_doc_id, [])
		if not rows:
			self.stats["skipped"] += 1
			return

		item_lines: List[Dict[str, Any]] = []
		counterparty_lines: List[Dict[str, Any]] = []

		for row in rows:
			d = convert_amount(row.get("bs"))
			c = convert_amount(row.get("bd"))
			amount = float(d if d > 0 else c)
			if amount <= 0:
				continue
			try:
				ref_id = int(row.get("ref_id") or 0)
			except (TypeError, ValueError):
				ref_id = 0

			if row.get("person_id") and ref_id in (3, 8):
				pid = person_id_map.get((old_bid, int(row["person_id"])))
				if pid and pid > 0:
					counterparty_lines.append({
						"transaction_type": "person",
						"amount": amount,
						"person_id": pid,
						"description": row.get("des"),
					})
				continue

			if row.get("bank_id"):
				nb = bank_id_map.get((old_bid, int(row["bank_id"])))
				if nb and nb > 0:
					counterparty_lines.append({
						"transaction_type": "bank",
						"amount": amount,
						"bank_id": nb,
						"description": row.get("des"),
					})
				continue

			if row.get("cashdesk_id"):
				nc = cashdesk_id_map.get((old_bid, int(row["cashdesk_id"])))
				if nc and nc > 0:
					counterparty_lines.append({
						"transaction_type": "cash_register",
						"amount": amount,
						"cash_register_id": nc,
						"description": row.get("des"),
					})
				continue

			if row.get("salary_id"):
				ns = petty_id_map.get((old_bid, int(row["salary_id"])))
				if ns and ns > 0:
					counterparty_lines.append({
						"transaction_type": "petty_cash",
						"amount": amount,
						"petty_cash_id": ns,
						"description": row.get("des"),
					})
				continue

			if ref_id in _SKIP_REF_IDS or row.get("commodity_id"):
				continue

			account_id = resolve_account_id_for_ref(
				self.db, ref_id, self.ref_index, fallback_expense=True
			)
			if account_id:
				item_lines.append({
					"account_id": account_id,
					"amount": amount,
					"description": row.get("des"),
				})

		if not item_lines or not counterparty_lines:
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
			"item_lines": item_lines,
			"counterparty_lines": counterparty_lines,
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

		create_expense_income(self.db, new_bid, new_user_id, payload)
		self.db.commit()
		self._migrated_old_ids.add(old_doc_id)
		self.stats["migrated"] += 1
