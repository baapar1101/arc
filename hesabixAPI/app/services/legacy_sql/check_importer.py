from __future__ import annotations

from datetime import date
from typing import Any, Callable, Dict, List, Optional, Set, Tuple

from sqlalchemy import and_
from sqlalchemy.orm import Session

from adapters.db.models.check import Check
from app.services.check_service import create_check
from app.services.legacy_sql.check_operation_importer import LegacyCheckOperationImporter
from app.services.legacy_sql.mappers import (
	convert_amount,
	convert_persian_date_to_date,
	convert_timestamp_to_datetime,
)
from app.services.legacy_sql.sql_dump_reader import LegacySqlData

ProgressCb = Optional[Callable[[int, str], None]]


class LegacyCheckImporter:
	"""انتقال جدول cheque و اسناد عملیات چک (pass/transfer/modify)."""

	def __init__(self, db: Session, data: LegacySqlData, *, dry_run: bool = False):
		self.db = db
		self.data = data
		self.dry_run = dry_run
		self.stats: Dict[str, Any] = {
			"cheques_in_table": 0,
			"cheques_migrated": 0,
			"cheques_skipped": 0,
			"cheque_operations": {},
			"errors": 0,
			"error_samples": [],
		}
		self._cheque_id_map: Dict[Tuple[int, int], int] = {}
		self._migrated_old_check_ids: Set[int] = set()

	def _is_check_number_taken(self, business_id: int, check_number: str) -> bool:
		return (
			self.db.query(Check.id)
			.filter(
				and_(
					Check.business_id == business_id,
					Check.check_number == check_number,
				)
			)
			.first()
			is not None
		)

	def _link_existing_checks(self, old_bid: int, new_bid: int) -> None:
		for row in self.data.rows("cheque"):
			try:
				old_id = int(row["id"])
			except (TypeError, ValueError):
				continue
			num = str(row.get("number") or "").strip()
			if not num:
				continue
			ch = (
				self.db.query(Check)
				.filter(
					and_(Check.business_id == new_bid, Check.check_number == num)
				)
				.first()
			)
			if ch:
				self._cheque_id_map[(old_bid, old_id)] = int(ch.id)

	def run(
		self,
		*,
		business_id_map: Dict[int, int],
		user_id_map: Dict[int, int],
		person_id_map: Dict[Tuple[int, int], int],
		bank_id_map: Dict[Tuple[int, int], int],
		currency_id_map: Dict[int, int],
		on_progress: ProgressCb = None,
	) -> Dict[str, Any]:
		cheque_rows = self.data.rows("cheque")
		self.stats["cheques_in_table"] = len(cheque_rows)
		total = len(cheque_rows) or 1

		for old_bid, new_bid in business_id_map.items():
			if new_bid and new_bid > 0:
				self._link_existing_checks(old_bid, new_bid)

		for i, row in enumerate(cheque_rows):
			if on_progress and i % 10 == 0 and cheque_rows:
				on_progress(96, f"چک {i + 1}/{total}")
			try:
				self._migrate_cheque_row(
					row,
					business_id_map=business_id_map,
					user_id_map=user_id_map,
					person_id_map=person_id_map,
					currency_id_map=currency_id_map,
				)
			except Exception as exc:
				self.stats["errors"] += 1
				if len(self.stats["error_samples"]) < 20:
					self.stats["error_samples"].append({
						"old_cheque_id": row.get("id"),
						"error": str(exc),
					})

		op = LegacyCheckOperationImporter(
			self.db,
			self.data,
			self._cheque_id_map,
			dry_run=self.dry_run,
		)
		self.stats["cheque_operations"] = op.run(
			business_id_map=business_id_map,
			user_id_map=user_id_map,
			person_id_map=person_id_map,
			bank_id_map=bank_id_map,
			currency_id_map=currency_id_map,
			on_progress=on_progress,
		)
		self.stats["errors"] += int(self.stats["cheque_operations"].get("errors") or 0)

		return dict(self.stats)

	def _migrate_cheque_row(
		self,
		row: Dict[str, Any],
		*,
		business_id_map: Dict[int, int],
		user_id_map: Dict[int, int],
		person_id_map: Dict[Tuple[int, int], int],
		currency_id_map: Dict[int, int],
	) -> None:
		try:
			old_id = int(row["id"])
		except (TypeError, ValueError):
			self.stats["cheques_skipped"] += 1
			return

		old_bid = int(row.get("bid_id") or 0)
		new_bid = business_id_map.get(old_bid)
		if not new_bid or new_bid < 0:
			self.stats["cheques_skipped"] += 1
			return

		if (old_bid, old_id) in self._cheque_id_map:
			self.stats["cheques_skipped"] += 1
			return

		if old_id in self._migrated_old_check_ids:
			self.stats["cheques_skipped"] += 1
			return

		new_user_id = user_id_map.get(int(row.get("submitter_id") or 0))
		if not new_user_id or new_user_id < 0:
			self.stats["cheques_skipped"] += 1
			return

		old_type = str(row.get("type") or "").lower()
		check_type = "received" if old_type in ("input", "receive", "received", "in") else "transferred"

		currency_id = currency_id_map.get(int(row.get("money_id") or 1))
		if not currency_id:
			self.stats["cheques_skipped"] += 1
			return

		person_id = None
		if row.get("person_id") is not None:
			try:
				person_id = person_id_map.get((old_bid, int(row["person_id"])))
			except (TypeError, ValueError):
				person_id = None
		if check_type == "received" and (not person_id or person_id < 0):
			self.stats["cheques_skipped"] += 1
			return

		issue_date = (
			convert_persian_date_to_date(row.get("date"))
			or convert_persian_date_to_date(row.get("date_stamp"))
			or date.today()
		)
		due_date = convert_persian_date_to_date(row.get("pay_date")) or issue_date
		amount = convert_amount(row.get("amount"))
		if amount <= 0:
			self.stats["cheques_skipped"] += 1
			return

		check_number = str(row.get("number") or "").strip() or f"LEG-{old_id}"
		if self._is_check_number_taken(new_bid, check_number):
			existing = (
				self.db.query(Check)
				.filter(
					and_(Check.business_id == new_bid, Check.check_number == check_number)
				)
				.first()
			)
			if existing:
				self._cheque_id_map[(old_bid, old_id)] = int(existing.id)
			self.stats["cheques_skipped"] += 1
			return

		payload = {
			"type": check_type,
			"person_id": person_id,
			"issue_date": issue_date.isoformat(),
			"due_date": due_date.isoformat(),
			"check_number": check_number,
			"amount": float(amount),
			"currency_id": currency_id,
			"bank_name": row.get("bank_oncheque") or "",
			"sayad_code": row.get("sayad_num"),
			"document_date": issue_date.isoformat(),
			"document_description": row.get("des"),
		}

		if self.dry_run:
			self._cheque_id_map[(old_bid, old_id)] = -old_id
			self.stats["cheques_migrated"] += 1
			return

		result = create_check(self.db, new_bid, new_user_id, payload)
		self._cheque_id_map[(old_bid, old_id)] = int(result["id"])
		self.db.commit()
		self._migrated_old_check_ids.add(old_id)
		self.stats["cheques_migrated"] += 1
