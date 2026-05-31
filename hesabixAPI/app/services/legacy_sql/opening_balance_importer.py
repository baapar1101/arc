from __future__ import annotations

from collections import defaultdict
from datetime import date
from typing import Any, Callable, Dict, List, Optional, Set, Tuple

from sqlalchemy import text
from sqlalchemy.orm import Session

from app.services.expense_income_service import _get_fixed_account_by_code
from app.services.legacy_sql.legacy_account_resolver import (
	LegacySqlAccountResolver,
	build_ref_id_index,
)
from app.services.legacy_sql.mappers import (
	convert_amount,
	convert_persian_date_to_date,
	convert_timestamp_to_datetime,
	is_valid_mapped_id,
)
from app.services.legacy_sql.sql_dump_reader import LegacySqlData
from app.services.opening_balance_service import upsert_opening_balance

ProgressCb = Optional[Callable[[int, str], None]]


class LegacyOpeningBalanceImporter:
	"""انتقال hesabdari_doc با type=open_balance به سند تراز افتتاحیه."""

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
		self._migrated_fiscal_years: Set[Tuple[int, int]] = set()

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
				SELECT fiscal_year_id
				FROM documents
				WHERE business_id = :bid
				  AND document_type = 'opening_balance'
				  AND extra_info->>'source' = 'legacy_sql'
			"""),
			{"bid": business_id},
		).fetchall()
		for r in rows:
			if r[0] is not None:
				self._migrated_fiscal_years.add((business_id, int(r[0])))

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
		fiscal_year_map: Dict[Tuple[int, int], int],
		on_progress: ProgressCb = None,
	) -> Dict[str, Any]:
		self._rows_by_doc = self._build_rows_index()
		ref_index = build_ref_id_index(self.data.rows("hesabdari_table"))
		docs = [d for d in self.data.rows("hesabdari_doc") if str(d.get("type") or "") == "open_balance"]
		total = len(docs) or 1

		for i, doc in enumerate(docs):
			self.stats["processed"] += 1
			if on_progress:
				on_progress(98, f"تراز افتتاحیه {i + 1}/{total}")
			try:
				self._migrate_one(
					doc,
					ref_index=ref_index,
					business_id_map=business_id_map,
					user_id_map=user_id_map,
					person_id_map=person_id_map,
					bank_id_map=bank_id_map,
					cashdesk_id_map=cashdesk_id_map,
					petty_id_map=petty_id_map,
					currency_id_map=currency_id_map,
					fiscal_year_map=fiscal_year_map,
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
		ref_index: Dict[int, Dict[str, Any]],
		business_id_map: Dict[int, int],
		user_id_map: Dict[int, int],
		person_id_map: Dict[Tuple[int, int], int],
		bank_id_map: Dict[Tuple[int, int], int],
		cashdesk_id_map: Dict[Tuple[int, int], int],
		petty_id_map: Dict[Tuple[int, int], int],
		currency_id_map: Dict[int, int],
		fiscal_year_map: Dict[Tuple[int, int], int],
	) -> None:
		old_bid = int(doc["bid_id"])
		new_bid = business_id_map.get(old_bid)
		if not new_bid or new_bid < 0:
			self.stats["skipped"] += 1
			return

		new_user_id = user_id_map.get(int(doc.get("submitter_id") or 0))
		if not new_user_id or new_user_id < 0:
			self.stats["skipped"] += 1
			return

		old_year = int(doc.get("year_id") or 0)
		fiscal_year_id = fiscal_year_map.get((old_bid, old_year))
		if not fiscal_year_id:
			self.stats["skipped"] += 1
			return

		if not self._migrated_fiscal_years and self.stats["processed"] == 1:
			self._load_migrated_cache(new_bid)
		if (new_bid, fiscal_year_id) in self._migrated_fiscal_years:
			self.stats["skipped"] += 1
			return

		currency_id = currency_id_map.get(int(doc.get("money_id") or 1))
		if not currency_id:
			self.stats["skipped"] += 1
			return

		old_doc_id = int(doc["id"])
		rows = self._rows_by_doc.get(old_doc_id, []) if self._rows_by_doc else []
		account_lines: List[Dict[str, Any]] = []
		equity_account = _get_fixed_account_by_code(self.db, "30101")

		for row in rows:
			debit = convert_amount(row.get("bs"))
			credit = convert_amount(row.get("bd"))
			if debit <= 0 and credit <= 0:
				continue

			plugin = str(row.get("plugin") or row.get("ref_data") or "").lower()
			if plugin == "shareholder" or "shareholder" in plugin:
				account_lines.append({
					"account_id": equity_account.id,
					"debit": float(debit),
					"credit": float(credit),
					"description": row.get("des"),
				})
				continue

			if row.get("bank_id") is not None:
				try:
					nb = bank_id_map.get((old_bid, int(row["bank_id"])))
				except (TypeError, ValueError):
					nb = None
				if is_valid_mapped_id(nb, dry_run=self.dry_run):
					account_lines.append({
						"bank_account_id": nb,
						"debit": float(debit),
						"credit": float(credit),
						"description": row.get("des"),
					})
					continue

			if row.get("cashdesk_id") is not None:
				try:
					nc = cashdesk_id_map.get((old_bid, int(row["cashdesk_id"])))
				except (TypeError, ValueError):
					nc = None
				if is_valid_mapped_id(nc, dry_run=self.dry_run):
					account_lines.append({
						"cash_register_id": nc,
						"debit": float(debit),
						"credit": float(credit),
						"description": row.get("des"),
					})
					continue

			if row.get("salary_id") is not None:
				try:
					np = petty_id_map.get((old_bid, int(row["salary_id"])))
				except (TypeError, ValueError):
					np = None
				if is_valid_mapped_id(np, dry_run=self.dry_run):
					account_lines.append({
						"petty_cash_id": np,
						"debit": float(debit),
						"credit": float(credit),
						"description": row.get("des"),
					})
					continue

			if row.get("person_id") is not None:
				try:
					pp = person_id_map.get((old_bid, int(row["person_id"])))
				except (TypeError, ValueError):
					pp = None
				if is_valid_mapped_id(pp, dry_run=self.dry_run):
					account_lines.append({
						"person_id": pp,
						"debit": float(debit),
						"credit": float(credit),
						"description": row.get("des"),
					})
					continue

			ref_id = row.get("ref_id")
			account_resolver = LegacySqlAccountResolver(self.db, new_bid, ref_index)
			acc_id = account_resolver.resolve_account_id_for_ref(ref_id)
			if acc_id:
				account_lines.append({
					"account_id": acc_id,
					"debit": float(debit),
					"credit": float(credit),
					"description": row.get("des"),
				})

		if not account_lines:
			self.stats["skipped"] += 1
			return

		doc_date = convert_persian_date_to_date(doc.get("date"))
		if not doc_date:
			ts = convert_timestamp_to_datetime(doc.get("date_submit"))
			doc_date = ts.date() if ts else date.today()

		payload = {
			"fiscal_year_id": fiscal_year_id,
			"document_date": doc_date.isoformat(),
			"currency_id": currency_id,
			"account_lines": account_lines,
			"inventory_lines": [],
			"auto_balance_to_equity": False,
			"description": doc.get("des") or "تراز افتتاحیه",
			"extra_info": {
				"source": "legacy_sql",
				"old_document_id": old_doc_id,
				"old_code": doc.get("code"),
			},
		}

		if self.dry_run:
			self.stats["migrated"] += 1
			return

		upsert_opening_balance(self.db, new_bid, new_user_id, payload)
		self.db.commit()
		self._migrated_fiscal_years.add((new_bid, fiscal_year_id))
		self.stats["migrated"] += 1
