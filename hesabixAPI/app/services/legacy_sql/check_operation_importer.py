from __future__ import annotations

from collections import defaultdict
from datetime import date
from typing import Any, Callable, Dict, List, Optional, Set, Tuple

from sqlalchemy import and_, text
from sqlalchemy.orm import Session

from adapters.db.models.check import Check, CheckStatus, CheckType
from adapters.db.models.document import Document
from app.services.check_service import clear_check, create_check, endorse_check
from app.services.legacy_sql.mappers import (
	convert_amount,
	convert_persian_date_to_date,
	convert_timestamp_to_datetime,
)
from app.services.legacy_sql.sql_dump_reader import LegacySqlData

ProgressCb = Optional[Callable[[int, str], None]]

CHECK_DOC_TYPES = (
	"modify_cheque",
	"modify_cheque_output",
	"pass_cheque",
	"transfer_cheque",
)


class LegacyCheckOperationImporter:
	"""عملیات چک روی اسناد hesabdari_doc (پس از انتقال جدول cheque)."""

	def __init__(
		self,
		db: Session,
		data: LegacySqlData,
		cheque_id_map: Dict[Tuple[int, int], int],
		*,
		dry_run: bool = False,
	):
		self.db = db
		self.data = data
		self.cheque_id_map = cheque_id_map
		self.dry_run = dry_run
		self.stats = {
			"processed": 0,
			"migrated": 0,
			"skipped": 0,
			"errors": 0,
			"error_samples": [],
		}
		self._rows_by_doc: Dict[int, List[Dict[str, Any]]] | None = None
		self._migrated_doc_ids: Set[int] = set()

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

	def _load_migrated_doc_cache(self, business_id: int) -> None:
		rows = self.db.execute(
			text("""
				SELECT (extra_info->>'old_document_id')::int AS old_id
				FROM documents
				WHERE business_id = :bid
				  AND extra_info->>'source' = 'legacy_sql'
				  AND extra_info->>'legacy_check_action' IS NOT NULL
				  AND extra_info->>'old_document_id' IS NOT NULL
			"""),
			{"bid": business_id},
		).fetchall()
		for r in rows:
			if r[0] is not None:
				self._migrated_doc_ids.add(int(r[0]))

	def _resolve_check_id(
		self,
		old_bid: int,
		rows: List[Dict[str, Any]],
	) -> Optional[int]:
		for row in rows:
			cid = row.get("cheque_id")
			if cid is None:
				continue
			try:
				mapped = self.cheque_id_map.get((old_bid, int(cid)))
			except (TypeError, ValueError):
				mapped = None
			if mapped and mapped > 0:
				return mapped
		return None

	def _doc_date(self, doc: Dict[str, Any]) -> date:
		doc_date = convert_persian_date_to_date(doc.get("date"))
		if doc_date:
			return doc_date
		ts = convert_timestamp_to_datetime(doc.get("date_submit"))
		return ts.date() if ts else date.today()

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
		self._rows_by_doc = self._build_rows_index()
		docs = [
			d for d in self.data.rows("hesabdari_doc")
			if str(d.get("type") or "") in CHECK_DOC_TYPES
		]
		docs.sort(key=lambda d: (str(d.get("date") or ""), int(d.get("id") or 0)))
		total = len(docs) or 1

		for i, doc in enumerate(docs):
			self.stats["processed"] += 1
			if on_progress and i % 10 == 0:
				on_progress(97, f"عملیات چک {i + 1}/{total}")
			try:
				self._migrate_doc(
					doc,
					business_id_map=business_id_map,
					user_id_map=user_id_map,
					person_id_map=person_id_map,
					bank_id_map=bank_id_map,
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

	def _migrate_doc(
		self,
		doc: Dict[str, Any],
		*,
		business_id_map: Dict[int, int],
		user_id_map: Dict[int, int],
		person_id_map: Dict[Tuple[int, int], int],
		bank_id_map: Dict[Tuple[int, int], int],
		currency_id_map: Dict[int, int],
	) -> None:
		old_doc_id = int(doc["id"])
		old_bid = int(doc["bid_id"])
		new_bid = business_id_map.get(old_bid)
		if not new_bid or new_bid < 0:
			self.stats["skipped"] += 1
			return

		if not self._migrated_doc_ids and self.stats["processed"] == 1:
			self._load_migrated_doc_cache(new_bid)
		if old_doc_id in self._migrated_doc_ids:
			self.stats["skipped"] += 1
			return

		new_user_id = user_id_map.get(int(doc.get("submitter_id") or 0))
		if not new_user_id or new_user_id < 0:
			self.stats["skipped"] += 1
			return

		old_type = str(doc.get("type") or "")
		rows = self._rows_by_doc.get(old_doc_id, []) if self._rows_by_doc else []
		doc_date = self._doc_date(doc)

		if old_type in ("modify_cheque", "modify_cheque_output"):
			# اگر چک از جدول cheque قبلاً منتقل شده، سند modify را رد می‌کنیم
			if self._resolve_check_id(old_bid, rows):
				self.stats["skipped"] += 1
				return
			self._create_check_from_doc(
				doc,
				old_bid=old_bid,
				new_bid=new_bid,
				new_user_id=new_user_id,
				rows=rows,
				check_type="transferred" if old_type == "modify_cheque_output" else "received",
				person_id_map=person_id_map,
				currency_id_map=currency_id_map,
				doc_date=doc_date,
				old_doc_id=old_doc_id,
			)
			return

		check_id = self._resolve_check_id(old_bid, rows)
		if not check_id:
			self.stats["skipped"] += 1
			return

		ch = self.db.get(Check, check_id)
		if not ch or int(ch.business_id) != int(new_bid):
			self.stats["skipped"] += 1
			return

		if old_type == "pass_cheque":
			if ch.status == CheckStatus.CLEARED:
				self.stats["skipped"] += 1
				return
			bank_id = None
			for row in rows:
				if row.get("bank_id") is not None:
					try:
						bank_id = bank_id_map.get((old_bid, int(row["bank_id"])))
					except (TypeError, ValueError):
						bank_id = None
					if bank_id and bank_id > 0:
						break
			if not bank_id:
				self.stats["skipped"] += 1
				return
			if self.dry_run:
				self.stats["migrated"] += 1
				return
			clear_check(
				self.db,
				check_id,
				new_user_id,
				{
					"document_date": doc_date.isoformat(),
					"bank_account_id": bank_id,
					"description": doc.get("des"),
				},
			)
			self._tag_action_document(new_bid, old_doc_id, "pass_cheque")
			self.db.commit()
			self._migrated_doc_ids.add(old_doc_id)
			self.stats["migrated"] += 1
			return

		if old_type == "transfer_cheque":
			if ch.status == CheckStatus.ENDORSED:
				self.stats["skipped"] += 1
				return
			if ch.type != CheckType.RECEIVED:
				self.stats["skipped"] += 1
				return
			target_person = None
			for row in rows:
				if row.get("person_id") is not None:
					try:
						target_person = person_id_map.get((old_bid, int(row["person_id"])))
					except (TypeError, ValueError):
						target_person = None
					if target_person and target_person > 0:
						break
			if not target_person:
				self.stats["skipped"] += 1
				return
			if self.dry_run:
				self.stats["migrated"] += 1
				return
			endorse_check(
				self.db,
				check_id,
				new_user_id,
				{
					"document_date": doc_date.isoformat(),
					"target_person_id": target_person,
					"description": doc.get("des"),
				},
			)
			self._tag_action_document(new_bid, old_doc_id, "transfer_cheque")
			self.db.commit()
			self._migrated_doc_ids.add(old_doc_id)
			self.stats["migrated"] += 1
			return

		self.stats["skipped"] += 1

	def _create_check_from_doc(
		self,
		doc: Dict[str, Any],
		*,
		old_bid: int,
		new_bid: int,
		new_user_id: int,
		rows: List[Dict[str, Any]],
		check_type: str,
		person_id_map: Dict[Tuple[int, int], int],
		currency_id_map: Dict[int, int],
		doc_date: date,
		old_doc_id: int,
	) -> None:
		currency_id = currency_id_map.get(int(doc.get("money_id") or 1))
		if not currency_id:
			self.stats["skipped"] += 1
			return

		amount = convert_amount(doc.get("amount"))
		if amount <= 0:
			for row in rows:
				a = convert_amount(row.get("bs")) + convert_amount(row.get("bd"))
				if a > 0:
					amount = a
					break
		if amount <= 0:
			self.stats["skipped"] += 1
			return

		person_id = None
		for row in rows:
			if row.get("person_id") is not None:
				try:
					person_id = person_id_map.get((old_bid, int(row["person_id"])))
				except (TypeError, ValueError):
					person_id = None
				if person_id and person_id > 0:
					break

		if check_type == "received" and (not person_id or person_id < 0):
			self.stats["skipped"] += 1
			return

		check_number = str(doc.get("code") or "").strip() or f"LEG-DOC-{old_doc_id}"
		existing = (
			self.db.query(Check.id)
			.filter(
				and_(Check.business_id == new_bid, Check.check_number == check_number)
			)
			.first()
		)
		if existing:
			self.stats["skipped"] += 1
			return

		if self.dry_run:
			self.stats["migrated"] += 1
			return

		result = create_check(
			self.db,
			new_bid,
			new_user_id,
			{
				"type": check_type,
				"person_id": person_id,
				"issue_date": doc_date.isoformat(),
				"due_date": doc_date.isoformat(),
				"check_number": check_number,
				"amount": float(amount),
				"currency_id": currency_id,
				"bank_name": "",
				"document_date": doc_date.isoformat(),
				"document_description": doc.get("des"),
			},
		)
		new_check_id = int(result["id"])
		old_cheque_id = None
		for row in rows:
			if row.get("cheque_id") is not None:
				try:
					old_cheque_id = int(row["cheque_id"])
					break
				except (TypeError, ValueError):
					pass
		if old_cheque_id is not None:
			self.cheque_id_map[(old_bid, old_cheque_id)] = new_check_id

		self._tag_action_document(new_bid, old_doc_id, str(doc.get("type") or "modify_cheque"))
		self.db.commit()
		self._migrated_doc_ids.add(old_doc_id)
		self.stats["migrated"] += 1

	def _tag_action_document(self, business_id: int, old_doc_id: int, action: str) -> None:
		"""برچسب idempotency روی آخرین سند ایجادشده برای این عملیات."""
		doc = (
			self.db.query(Document)
			.filter(Document.business_id == business_id)
			.order_by(Document.id.desc())
			.first()
		)
		if not doc:
			return
		extra = dict(doc.extra_info or {})
		extra["source"] = "legacy_sql"
		extra["old_document_id"] = old_doc_id
		extra["legacy_check_action"] = action
		doc.extra_info = extra
		self.db.flush()
