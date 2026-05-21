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
from app.services.invoice_service import SUPPORTED_INVOICE_TYPES, _cleanup_dead_receipt_payment_links
from app.services.receipt_payment_service import delete_receipt_payment


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
	},
	{
		"key": "cleanup_orphan_backup_businesses",
		"title": "پاک‌سازی کسب‌وکارهای یتیم import بکاپ",
		"description": (
			"حذف کسب‌وکارهایی که از import/restore بکاپ نیمه‌کاره مانده‌اند "
			"(ثبت‌نشده در business_backup_import_logs یا داده tenant بسیار کم + الگوی نام). "
			"پیش‌فرض dry_run؛ برای حذف واقعی dry_run=false."
		),
		"supports_dry_run": True,
		"default_params": {
			"business_id": None,
			"owner_id": None,
			"min_age_hours": 1,
			"limit": None,
			"require_not_in_import_log": True,
			"require_backup_name_marker": True,
			"include_empty_shell": True,
			"name_substring": "بازیابی شده",
			"max_documents": 0,
			"max_persons": 0,
			"max_products": 0,
		},
	},
	{
		"key": "remove_orphan_invoice_receipt_payment_documents",
		"title": "اصلاح اسناد دریافت/پرداخت رها شدهٔ فاکتور",
		"description": (
			"حذف اسناد دریافت/پرداختی که از فاکتور منبع دیگر در لینک فاکتور نیستند (پس از باگ قدیمی ویرایش)، "
			"و پاک‌سازی لینک‌های مردهٔ receipt_payment روی فاکتورها. business_id خالی = همهٔ کسب‌وکارها."
		),
		"supports_dry_run": True,
		"default_params": {
			"business_id": None,
			"limit": None,
			"require_invoice_source": True,
		},
	},
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

	merged_params: Dict[str, Any] = dict(defn.get("default_params") or {})
	merged_params.update(params or {})

	run = AdminScriptRun(
		script_key=script_key,
		status="queued",
		dry_run=bool(dry_run),
		params_json=merged_params,
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
			elif run.script_key == "remove_orphan_invoice_receipt_payment_documents":
				stats = _run_remove_orphan_invoice_receipt_payments(db, run)
			elif run.script_key == "cleanup_orphan_backup_businesses":
				stats = _run_cleanup_orphan_backup_businesses(db, run)
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


def _to_bool_param(value: Any, default: bool = True) -> bool:
	if value is None:
		return default
	if isinstance(value, bool):
		return value
	s = str(value).strip().lower()
	if s in ("0", "false", "no", "off", ""):
		return False
	if s in ("1", "true", "yes", "on"):
		return True
	return default


def _extract_rp_invoice_id_for_cleanup(
	extra: Any, *, require_invoice_source: bool
) -> Optional[int]:
	"""شناسه فاکتور مرجع روی سند دریافت/پرداخت؛ در حالت سخت‌گیرانه فقط source=invoice."""
	if not isinstance(extra, dict):
		return None
	src = str(extra.get("source") or "").strip().lower()
	if require_invoice_source and src != "invoice":
		return None
	raw = extra.get("invoice_id")
	if raw is None:
		return None
	try:
		iid = int(raw)
		return iid if iid > 0 else None
	except (TypeError, ValueError):
		return None


def _invoice_receipt_payment_link_ids(invoice: Document) -> List[int]:
	extra = invoice.extra_info or {}
	links = extra.get("links") or {}
	raw = links.get("receipt_payment_document_ids") or []
	out: List[int] = []
	for x in raw:
		try:
			out.append(int(x))
		except (TypeError, ValueError):
			continue
	return out


def _run_remove_orphan_invoice_receipt_payments(db: Session, run: AdminScriptRun) -> Dict[str, Any]:
	params = run.params_json or {}
	business_id = _to_int(params.get("business_id"))
	limit = _to_int(params.get("limit"))
	dry_run = bool(run.dry_run)
	require_invoice_source = _to_bool_param(params.get("require_invoice_source"), default=True)

	stats: Dict[str, Any] = {
		"scanned": 0,
		"updated_lines": 0,
		"skipped_invalid_ref": 0,
		"errors": 0,
		"phase_rp": {
			"scanned_documents": 0,
			"orphan_candidates": 0,
			"deleted": 0,
			"delete_failed": 0,
			"skipped_no_invoice_id": 0,
			"skipped_invoice_missing_or_not_invoice": 0,
			"skipped_still_linked": 0,
		},
		"phase_invoices": {
			"scanned_invoices": 0,
			"links_cleaned": 0,
		},
	}

	# --- فاز ۱: اسناد دریافت/پرداخت یتیم (invoice_id در سند هست ولی در لینک فاکتور نیست)
	rp_q = db.query(Document).filter(Document.document_type.in_(["receipt", "payment"]))
	if business_id is not None:
		rp_q = rp_q.filter(Document.business_id == business_id)
	rp_q = rp_q.order_by(Document.id.asc())
	if limit is not None:
		rp_q = rp_q.limit(limit)
	rp_rows = rp_q.all()
	stats["phase_rp"]["scanned_documents"] = len(rp_rows)
	_append_log(db, run.id, "info", f"اسکن اسناد دریافت/پرداخت: {len(rp_rows)}")
	db.commit()

	for rp in rp_rows:
		current = db.query(AdminScriptRun).filter(AdminScriptRun.id == run.id).first()
		if current and current.status == "cancelled":
			_append_log(db, run.id, "warning", "اجرای متوقف شد (لغو توسط کاربر)")
			db.commit()
			break

		inv_id = _extract_rp_invoice_id_for_cleanup(rp.extra_info, require_invoice_source=require_invoice_source)
		if inv_id is None:
			stats["phase_rp"]["skipped_no_invoice_id"] += 1
			continue

		inv = db.query(Document).filter(Document.id == inv_id).first()
		if not inv or inv.document_type not in SUPPORTED_INVOICE_TYPES:
			stats["phase_rp"]["skipped_invoice_missing_or_not_invoice"] += 1
			stats["skipped_invalid_ref"] += 1
			continue

		linked = _invoice_receipt_payment_link_ids(inv)
		if int(rp.id) in linked:
			stats["phase_rp"]["skipped_still_linked"] += 1
			continue

		stats["phase_rp"]["orphan_candidates"] += 1
		if dry_run:
			stats["phase_rp"]["deleted"] += 1
			stats["updated_lines"] += 1
			continue

		try:
			delete_receipt_payment(db, int(rp.id), commit=True)
			stats["phase_rp"]["deleted"] += 1
			stats["updated_lines"] += 1
		except ApiError as exc:
			stats["phase_rp"]["delete_failed"] += 1
			stats["errors"] += 1
			detail = getattr(exc, "detail", None)
			msg = str(detail) if detail is not None else str(exc)
			_append_log(db, run.id, "error", f"حذف سند دریافت/پرداخت {rp.id}: {msg}")
			db.commit()
		except Exception as exc:
			stats["phase_rp"]["delete_failed"] += 1
			stats["errors"] += 1
			_append_log(db, run.id, "error", f"حذف سند دریافت/پرداخت {rp.id}: {exc}")
			db.commit()

		if stats["phase_rp"]["orphan_candidates"] > 0 and stats["phase_rp"]["orphan_candidates"] % 100 == 0:
			_append_log(
				db,
				run.id,
				"info",
				f"پیشرفت فاز دریافت/پرداخت: orphan={stats['phase_rp']['orphan_candidates']} حذف‌شده={stats['phase_rp']['deleted']}",
			)
			db.commit()

	# --- فاز ۲: لینک‌های مرده روی فاکتورها (ارجاع به سند حذف‌شده)
	inv_q = db.query(Document).filter(Document.document_type.in_(tuple(SUPPORTED_INVOICE_TYPES)))
	if business_id is not None:
		inv_q = inv_q.filter(Document.business_id == business_id)
	inv_q = inv_q.order_by(Document.id.asc())
	if limit is not None:
		inv_q = inv_q.limit(limit)
	inv_rows = inv_q.all()
	stats["phase_invoices"]["scanned_invoices"] = len(inv_rows)
	stats["scanned"] = int(stats["phase_rp"]["scanned_documents"]) + len(inv_rows)
	_append_log(db, run.id, "info", f"اسکن فاکتورها برای لینک مرده: {len(inv_rows)}")
	db.commit()

	for inv in inv_rows:
		current = db.query(AdminScriptRun).filter(AdminScriptRun.id == run.id).first()
		if current and current.status == "cancelled":
			_append_log(db, run.id, "warning", "اجرای متوقف شد (لغو توسط کاربر)")
			db.commit()
			break

		try:
			if dry_run:
				extra_info = inv.extra_info or {}
				links = extra_info.get("links", {})
				receipt_payment_ids = links.get("receipt_payment_document_ids", []) or []
				if not receipt_payment_ids:
					continue
				valid_ids: List[int] = []
				for doc_id in receipt_payment_ids:
					try:
						doc_id_int = int(doc_id)
						doc = db.query(Document).filter(
							Document.id == doc_id_int,
							Document.document_type.in_(["receipt", "payment"]),
						).first()
						if doc:
							valid_ids.append(doc_id_int)
					except (ValueError, TypeError):
						continue
				if len(valid_ids) != len(receipt_payment_ids):
					stats["phase_invoices"]["links_cleaned"] += 1
					stats["updated_lines"] += 1
				continue

			if _cleanup_dead_receipt_payment_links(db, inv):
				stats["phase_invoices"]["links_cleaned"] += 1
				stats["updated_lines"] += 1
				db.commit()
		except Exception as exc:
			stats["errors"] += 1
			_append_log(db, run.id, "error", f"فاکتور {inv.id}: {exc}")
			db.commit()

	_append_log(
		db,
		run.id,
		"info",
		(
			f"پایان. یتیم={stats['phase_rp']['orphan_candidates']} "
			f"حذف/شبیه‌سازی={stats['phase_rp']['deleted']} "
			f"پاک‌سازی لینک فاکتور={stats['phase_invoices']['links_cleaned']} dry_run={dry_run}"
		),
	)
	db.commit()
	return stats


def _run_cleanup_orphan_backup_businesses(db: Session, run: AdminScriptRun) -> Dict[str, Any]:
	from app.services.business_backup_orphan_cleanup_service import run_orphan_backup_business_cleanup

	params = run.params_json or {}
	dry_run = bool(run.dry_run)

	def log_fn(level: str, message: str) -> None:
		_append_log(db, run.id, level, message)
		db.flush()

	_append_log(db, run.id, "info", f"شروع پاک‌سازی کسب‌وکار یتیم بکاپ (dry_run={dry_run})")
	db.flush()

	current = db.query(AdminScriptRun).filter(AdminScriptRun.id == run.id).first()
	if current and current.status == "cancelled":
		return {"scanned": 0, "updated_lines": 0, "errors": 0, "cancelled": True}

	stats = run_orphan_backup_business_cleanup(db, params, dry_run=dry_run, log_fn=log_fn)
	if not dry_run:
		db.commit()
	stats["scanned"] = int(stats.get("scanned", 0))
	_append_log(
		db,
		run.id,
		"info",
		f"پایان: کاندید={stats.get('scanned')} حذف/شبیه‌سازی={stats.get('deleted_count', 0)} خطا={stats.get('errors', 0)}",
	)
	db.flush()
	return stats

