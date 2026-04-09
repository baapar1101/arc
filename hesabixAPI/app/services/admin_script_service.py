from __future__ import annotations

import threading
from datetime import datetime
from typing import Any, Dict, List, Optional

from sqlalchemy import and_, or_
from sqlalchemy.orm import Session

from adapters.db.models.admin_script_run import AdminScriptRun, AdminScriptRunLog
from adapters.db.models.document import Document
from adapters.db.models.document_line import DocumentLine
from adapters.db.models.bank_account import BankAccount
from adapters.db.models.cash_register import CashRegister
from adapters.db.models.petty_cash import PettyCash
from adapters.db.models.check import Check
from adapters.db.models.person import Person
from adapters.db.models.account import Account
from adapters.db.session import get_db_session
from app.core.responses import ApiError


SCRIPT_DEFINITIONS: List[Dict[str, Any]] = [
	{
		"key": "fix_expense_income_document_lines_refs",
		"title": "رفع لینک خطوط سند هزینه/درآمد",
		"description": "تکمیل شناسه‌های مرجع خطوط اسناد قدیمی هزینه/درآمد بر اساس extra_info",
		"supports_dry_run": True,
		"default_params": {
			"business_id": None,
			"limit": None,
		},
	}
]


def list_scripts() -> List[Dict[str, Any]]:
	return SCRIPT_DEFINITIONS


def _serialize_run(run: AdminScriptRun) -> Dict[str, Any]:
	return {
		"id": run.id,
		"script_key": run.script_key,
		"status": run.status,
		"dry_run": bool(run.dry_run),
		"params": run.params_json or {},
		"result": run.result_json or {},
		"error_text": run.error_text,
		"scanned_count": int(run.scanned_count or 0),
		"updated_count": int(run.updated_count or 0),
		"skipped_count": int(run.skipped_count or 0),
		"error_count": int(run.error_count or 0),
		"created_by_user_id": run.created_by_user_id,
		"started_at": run.started_at.isoformat() if run.started_at else None,
		"finished_at": run.finished_at.isoformat() if run.finished_at else None,
		"created_at": run.created_at.isoformat() if run.created_at else None,
		"updated_at": run.updated_at.isoformat() if run.updated_at else None,
	}


def _append_log(db: Session, run_id: int, level: str, message: str) -> None:
	db.add(AdminScriptRunLog(run_id=run_id, level=level, message=message))


def create_script_run(db: Session, user_id: int, script_key: str, params: Dict[str, Any], dry_run: bool) -> Dict[str, Any]:
	defn = next((s for s in SCRIPT_DEFINITIONS if s["key"] == script_key), None)
	if not defn:
		raise ApiError("SCRIPT_NOT_FOUND", "Script not found", http_status=404)

	run = AdminScriptRun(
		script_key=script_key,
		status="queued",
		dry_run=bool(dry_run),
		params_json=params or {},
		created_by_user_id=user_id,
	)
	db.add(run)
	db.flush()
	_append_log(db, run.id, "info", f"Script queued: {script_key}")
	db.commit()
	db.refresh(run)

	thread = threading.Thread(target=_execute_script_run, args=(run.id,), daemon=True)
	thread.start()
	return _serialize_run(run)


def list_script_runs(db: Session, script_key: Optional[str], status: Optional[str], take: int = 50, skip: int = 0) -> Dict[str, Any]:
	q = db.query(AdminScriptRun)
	if script_key:
		q = q.filter(AdminScriptRun.script_key == script_key)
	if status:
		q = q.filter(AdminScriptRun.status == status)
	q = q.order_by(AdminScriptRun.id.desc())
	total = q.count()
	items = q.offset(skip).limit(take).all()
	return {
		"items": [_serialize_run(x) for x in items],
		"pagination": {
			"total": total,
			"skip": skip,
			"take": take,
		},
	}


def get_script_run_details(db: Session, run_id: int) -> Dict[str, Any]:
	run = db.query(AdminScriptRun).filter(AdminScriptRun.id == run_id).first()
	if not run:
		raise ApiError("RUN_NOT_FOUND", "Run not found", http_status=404)
	logs = (
		db.query(AdminScriptRunLog)
		.filter(AdminScriptRunLog.run_id == run_id)
		.order_by(AdminScriptRunLog.id.asc())
		.all()
	)
	return {
		"run": _serialize_run(run),
		"logs": [
			{
				"id": log.id,
				"level": log.level,
				"message": log.message,
				"created_at": log.created_at.isoformat() if log.created_at else None,
			}
			for log in logs
		],
	}


def cancel_script_run(db: Session, run_id: int) -> Dict[str, Any]:
	run = db.query(AdminScriptRun).filter(AdminScriptRun.id == run_id).first()
	if not run:
		raise ApiError("RUN_NOT_FOUND", "Run not found", http_status=404)
	if run.status in ("completed", "failed", "cancelled"):
		return _serialize_run(run)
	run.status = "cancelled"
	run.finished_at = datetime.utcnow()
	_append_log(db, run_id, "warning", "Run cancelled by user")
	db.commit()
	db.refresh(run)
	return _serialize_run(run)


def _execute_script_run(run_id: int) -> None:
	with get_db_session() as db:
		run = db.query(AdminScriptRun).filter(AdminScriptRun.id == run_id).first()
		if not run:
			return
		if run.status != "queued":
			return

		run.status = "running"
		run.started_at = datetime.utcnow()
		_append_log(db, run_id, "info", "Run started")
		db.commit()

	try:
		with get_db_session() as db:
			run = db.query(AdminScriptRun).filter(AdminScriptRun.id == run_id).first()
			if not run:
				return
			if run.script_key == "fix_expense_income_document_lines_refs":
				stats = _run_fix_expense_income_refs(db, run)
			else:
				raise ApiError("SCRIPT_NOT_IMPLEMENTED", "Script implementation not found", http_status=500)

			run.status = "completed"
			run.result_json = stats
			run.scanned_count = int(stats.get("scanned", 0))
			run.updated_count = int(stats.get("updated_lines", 0))
			run.skipped_count = int(stats.get("skipped_invalid_ref", 0))
			run.error_count = int(stats.get("errors", 0))
			run.finished_at = datetime.utcnow()
			_append_log(db, run_id, "info", "Run completed")
			db.commit()
	except Exception as exc:
		with get_db_session() as db:
			run = db.query(AdminScriptRun).filter(AdminScriptRun.id == run_id).first()
			if not run:
				return
			run.status = "failed"
			run.error_text = str(exc)
			run.finished_at = datetime.utcnow()
			_append_log(db, run_id, "error", f"Run failed: {exc}")
			db.commit()


def _to_int(value: Any) -> Optional[int]:
	if value is None:
		return None
	try:
		v = int(str(value).strip())
		return v if v > 0 else None
	except Exception:
		return None


def _run_fix_expense_income_refs(db: Session, run: AdminScriptRun) -> Dict[str, Any]:
	params = run.params_json or {}
	business_id = _to_int(params.get("business_id"))
	limit = _to_int(params.get("limit"))
	dry_run = bool(run.dry_run)

	stats = {
		"scanned": 0,
		"candidates": 0,
		"updated_fields": 0,
		"updated_lines": 0,
		"skipped_invalid_ref": 0,
		"errors": 0,
	}

	q = (
		db.query(DocumentLine, Document)
		.join(Document, Document.id == DocumentLine.document_id)
		.filter(Document.document_type.in_(["expense", "income"]))
		.filter(DocumentLine.extra_info.isnot(None))
		.order_by(DocumentLine.id.asc())
	)
	if business_id is not None:
		q = q.filter(Document.business_id == business_id)
	if limit is not None:
		q = q.limit(limit)
	rows = q.all()
	stats["scanned"] = len(rows)
	_append_log(db, run.id, "info", f"Scanned rows: {stats['scanned']}")
	db.commit()

	for line, doc in rows:
		# stop if cancelled
		current = db.query(AdminScriptRun).filter(AdminScriptRun.id == run.id).first()
		if current and current.status == "cancelled":
			_append_log(db, run.id, "warning", "Run stopped due to cancellation")
			db.commit()
			return stats

		try:
			extra = line.extra_info or {}
			tx_type = str(extra.get("transaction_type") or "").strip().lower()
			if not tx_type:
				continue

			updates: Dict[str, int] = {}
			if tx_type == "bank" and line.bank_account_id is None:
				bank_id = _to_int(extra.get("bank_account_id")) or _to_int(extra.get("bank_id"))
				if bank_id is not None:
					exists = db.query(BankAccount.id).filter(
						and_(BankAccount.id == bank_id, BankAccount.business_id == doc.business_id)
					).first()
					if exists:
						updates["bank_account_id"] = bank_id
					else:
						stats["skipped_invalid_ref"] += 1

			elif tx_type == "cash_register" and line.cash_register_id is None:
				item_id = _to_int(extra.get("cash_register_id"))
				if item_id is not None:
					exists = db.query(CashRegister.id).filter(
						and_(CashRegister.id == item_id, CashRegister.business_id == doc.business_id)
					).first()
					if exists:
						updates["cash_register_id"] = item_id
					else:
						stats["skipped_invalid_ref"] += 1

			elif tx_type == "petty_cash" and line.petty_cash_id is None:
				item_id = _to_int(extra.get("petty_cash_id"))
				if item_id is not None:
					exists = db.query(PettyCash.id).filter(
						and_(PettyCash.id == item_id, PettyCash.business_id == doc.business_id)
					).first()
					if exists:
						updates["petty_cash_id"] = item_id
					else:
						stats["skipped_invalid_ref"] += 1

			elif tx_type in ("check", "check_expense") and line.check_id is None:
				item_id = _to_int(extra.get("check_id"))
				if item_id is not None:
					exists = db.query(Check.id).filter(and_(Check.id == item_id, Check.business_id == doc.business_id)).first()
					if exists:
						updates["check_id"] = item_id
					else:
						stats["skipped_invalid_ref"] += 1

			elif tx_type == "person" and line.person_id is None:
				item_id = _to_int(extra.get("person_id"))
				if item_id is not None:
					exists = db.query(Person.id).filter(and_(Person.id == item_id, Person.business_id == doc.business_id)).first()
					if exists:
						updates["person_id"] = item_id
					else:
						stats["skipped_invalid_ref"] += 1

			elif tx_type == "account" and line.account_id is None:
				item_id = _to_int(extra.get("account_id"))
				if item_id is not None:
					exists = db.query(Account.id).filter(
						and_(Account.id == item_id, or_(Account.business_id == doc.business_id, Account.business_id == None))  # noqa: E711
					).first()
					if exists:
						updates["account_id"] = item_id
					else:
						stats["skipped_invalid_ref"] += 1

			if not updates:
				continue

			stats["candidates"] += 1
			stats["updated_fields"] += len(updates)
			if not dry_run:
				for k, v in updates.items():
					setattr(line, k, v)
				stats["updated_lines"] += 1

			if stats["candidates"] % 200 == 0:
				_append_log(
					db,
					run.id,
					"info",
					f"Progress: candidates={stats['candidates']} updated_lines={stats['updated_lines']}",
				)
				db.commit()

		except Exception as exc:
			stats["errors"] += 1
			_append_log(db, run.id, "error", f"line_id={line.id}: {exc}")
			db.commit()

	if not dry_run:
		db.commit()
	_append_log(
		db,
		run.id,
		"info",
		f"Finished. candidates={stats['candidates']} updated_lines={stats['updated_lines']} dry_run={dry_run}",
	)
	db.commit()
	return stats

