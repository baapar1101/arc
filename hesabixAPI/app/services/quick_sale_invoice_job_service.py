from __future__ import annotations

import asyncio
import logging
from datetime import datetime, timedelta
from typing import Any, Optional

from sqlalchemy import and_, or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from adapters.db.models.document import Document
from adapters.db.models.quick_sale_invoice_job import QuickSaleInvoiceJob
from app.core.responses import ApiError
from app.core.transaction_lock import acquire_transaction_lock

logger = logging.getLogger(__name__)

MAX_ATTEMPTS = 5
JOB_LEASE = timedelta(minutes=10)


def find_quick_sale_invoice(db: Session, business_id: int, request_id: str) -> Optional[Document]:
	return (
		db.query(Document)
		.filter(
			Document.business_id == int(business_id),
			Document.document_type == "invoice_sales",
			Document.extra_info["quick_sale"].as_string() == "true",
			Document.extra_info["quick_sale_request_id"].as_string() == request_id,
		)
		.first()
	)


def serialize_quick_sale_job(job: QuickSaleInvoiceJob) -> dict[str, Any]:
	return {
		"job_id": int(job.id),
		"request_id": job.request_id,
		"status": job.status,
		"invoice_id": int(job.invoice_id) if job.invoice_id is not None else None,
		"invoice_code": job.invoice_code,
		"error_code": job.error_code,
		"error_message": job.error_message,
		"attempt_count": int(job.attempt_count or 0),
		"created_at": job.created_at.isoformat() if job.created_at else None,
		"finished_at": job.finished_at.isoformat() if job.finished_at else None,
	}


def enqueue_quick_sale_invoice(
	db: Session,
	*,
	business_id: int,
	user_id: int,
	request_id: str,
	payload: dict[str, Any],
	user_can_select_fx_rate: bool,
	user_can_change_invoice_unit_price: bool,
) -> QuickSaleInvoiceJob:
	"""Insert the request into the durable DB outbox, idempotently."""
	acquire_transaction_lock(db, f"quick_sale_invoice:{business_id}:{request_id}")
	existing_invoice = find_quick_sale_invoice(db, business_id, request_id)
	if existing_invoice is not None:
		job = (
			db.query(QuickSaleInvoiceJob)
			.filter(
				QuickSaleInvoiceJob.business_id == business_id,
				QuickSaleInvoiceJob.request_id == request_id,
			)
			.first()
		)
		if job is not None and int(job.user_id) != int(user_id):
			raise ApiError(
				"QUICK_SALE_REQUEST_ID_CONFLICT",
				"شناسهٔ این درخواست قبلاً برای کاربر دیگری استفاده شده است.",
				http_status=409,
			)
		if int(existing_invoice.created_by_user_id or 0) != int(user_id):
			raise ApiError(
				"QUICK_SALE_REQUEST_ID_CONFLICT",
				"شناسهٔ این درخواست قبلاً برای کاربر دیگری استفاده شده است.",
				http_status=409,
			)
		if job is None:
			job = QuickSaleInvoiceJob(
				business_id=business_id,
				user_id=user_id,
				request_id=request_id,
				payload=payload,
				status="completed",
				invoice_id=int(existing_invoice.id),
				invoice_code=existing_invoice.code,
				finished_at=datetime.utcnow(),
			)
			db.add(job)
			db.flush()
		return job

	job = (
		db.query(QuickSaleInvoiceJob)
		.filter(
			QuickSaleInvoiceJob.business_id == business_id,
			QuickSaleInvoiceJob.request_id == request_id,
		)
		.first()
	)
	if job is not None:
		if int(job.user_id) != int(user_id):
			raise ApiError(
				"QUICK_SALE_REQUEST_ID_CONFLICT",
				"شناسهٔ این درخواست قبلاً برای کاربر دیگری استفاده شده است.",
				http_status=409,
			)
		return job

	job = QuickSaleInvoiceJob(
		business_id=business_id,
		user_id=user_id,
		request_id=request_id,
		payload=payload,
		user_can_select_fx_rate=bool(user_can_select_fx_rate),
		user_can_change_invoice_unit_price=bool(user_can_change_invoice_unit_price),
		status="queued",
		attempt_count=0,
		available_at=datetime.utcnow(),
	)
	db.add(job)
	try:
		with db.begin_nested():
			db.flush()
	except IntegrityError:
		job = (
			db.query(QuickSaleInvoiceJob)
			.filter(
				QuickSaleInvoiceJob.business_id == business_id,
				QuickSaleInvoiceJob.request_id == request_id,
			)
			.first()
		)
		if job is None:
			raise
	if int(job.user_id) != int(user_id):
		raise ApiError(
			"QUICK_SALE_REQUEST_ID_CONFLICT",
			"شناسهٔ این درخواست قبلاً برای کاربر دیگری استفاده شده است.",
			http_status=409,
		)
	return job


def get_quick_sale_invoice_job(
	db: Session,
	*,
	business_id: int,
	user_id: int,
	request_id: str,
) -> Optional[QuickSaleInvoiceJob]:
	return (
		db.query(QuickSaleInvoiceJob)
		.filter(
			QuickSaleInvoiceJob.business_id == int(business_id),
			QuickSaleInvoiceJob.user_id == int(user_id),
			QuickSaleInvoiceJob.request_id == request_id,
		)
		.first()
	)


def list_quick_sale_invoice_jobs(
	db: Session,
	*,
	business_id: int,
	user_id: int,
	limit: int = 20,
) -> list[QuickSaleInvoiceJob]:
	now = datetime.utcnow()
	active_stmt = (
		select(QuickSaleInvoiceJob)
		.where(
			QuickSaleInvoiceJob.business_id == int(business_id),
			QuickSaleInvoiceJob.user_id == int(user_id),
			QuickSaleInvoiceJob.status.in_(("queued", "processing", "failed")),
		)
		.order_by(QuickSaleInvoiceJob.created_at.desc(), QuickSaleInvoiceJob.id.desc())
		.limit(max(1, min(int(limit), 50)))
	)
	completed_stmt = (
		select(QuickSaleInvoiceJob)
		.where(
			QuickSaleInvoiceJob.business_id == int(business_id),
			QuickSaleInvoiceJob.user_id == int(user_id),
			QuickSaleInvoiceJob.status == "completed",
			QuickSaleInvoiceJob.created_at >= now - timedelta(days=1),
		)
		.order_by(QuickSaleInvoiceJob.created_at.desc(), QuickSaleInvoiceJob.id.desc())
		.limit(max(1, min(int(limit), 50)))
	)
	jobs = [
		*db.execute(active_stmt).scalars().all(),
		*db.execute(completed_stmt).scalars().all(),
	]
	return sorted(jobs, key=lambda job: (job.created_at, job.id), reverse=True)


def _claim_one_job() -> Optional[int]:
	from adapters.db.session import get_db_session

	now = datetime.utcnow()
	with get_db_session() as db:
		stmt = (
			select(QuickSaleInvoiceJob)
			.where(
				or_(
					and_(
						QuickSaleInvoiceJob.status == "queued",
						QuickSaleInvoiceJob.available_at <= now,
					),
					and_(
						QuickSaleInvoiceJob.status == "processing",
						QuickSaleInvoiceJob.locked_until.is_not(None),
						QuickSaleInvoiceJob.locked_until <= now,
					),
				)
			)
			.order_by(QuickSaleInvoiceJob.created_at.asc(), QuickSaleInvoiceJob.id.asc())
			.limit(1)
			.with_for_update(skip_locked=True)
		)
		job = db.execute(stmt).scalars().first()
		if job is None:
			return None
		if int(job.attempt_count or 0) >= MAX_ATTEMPTS:
			job.status = "failed"
			job.error_code = "QUICK_SALE_WORKER_RETRIES_EXHAUSTED"
			job.error_message = "پردازش فروش پس از چند تلاش ناموفق متوقف شد."
			job.locked_until = None
			job.finished_at = now
			db.commit()
			return None
		job.status = "processing"
		job.attempt_count = int(job.attempt_count or 0) + 1
		job.locked_until = now + JOB_LEASE
		job.error_code = None
		job.error_message = None
		db.commit()
		return int(job.id)


def _error_data(exc: Exception) -> tuple[str, str, bool]:
	if isinstance(exc, ApiError):
		code = str(getattr(exc, "code", "QUICK_SALE_INVOICE_FAILED"))
		message = str(getattr(exc, "message", None) or getattr(exc, "detail", None) or code)
		status_code = int(getattr(exc, "status_code", 400) or 400)
		return code[:100], message[:4000], status_code >= 500
	return (
		"QUICK_SALE_INVOICE_FAILED",
		"پردازش فروش به دلیل خطای داخلی ناموفق شد. لطفاً دوباره تلاش کنید.",
		True,
	)


def _process_job(job_id: int) -> None:
	from adapters.db.session import get_db_session
	from app.services.invoice_service import create_invoice

	with get_db_session() as db:
		job = db.query(QuickSaleInvoiceJob).filter(QuickSaleInvoiceJob.id == int(job_id)).first()
		if job is None or job.status != "processing":
			return
		business_id = int(job.business_id)
		request_id = str(job.request_id)
		acquire_transaction_lock(db, f"quick_sale_invoice:{business_id}:{request_id}")
		invoice = find_quick_sale_invoice(db, business_id, request_id)
		if invoice is None:
			payload = dict(job.payload or {})
			result = create_invoice(
				db=db,
				business_id=business_id,
				user_id=int(job.user_id),
				data=payload,
				user_can_select_fx_rate=bool(job.user_can_select_fx_rate),
				user_can_change_invoice_unit_price=bool(job.user_can_change_invoice_unit_price),
				lightweight_response=True,
			)
			data = result.get("data") if isinstance(result, dict) else None
			if isinstance(data, dict):
				invoice_id = data.get("id")
				invoice_code = data.get("code")
			else:
				invoice_id = result.get("id") if isinstance(result, dict) else None
				invoice_code = result.get("code") if isinstance(result, dict) else None
		else:
			invoice_id = invoice.id
			invoice_code = invoice.code

		job = db.query(QuickSaleInvoiceJob).filter(QuickSaleInvoiceJob.id == int(job_id)).first()
		if job is None:
			return
		job.status = "completed"
		job.invoice_id = int(invoice_id) if invoice_id is not None else None
		job.invoice_code = str(invoice_code) if invoice_code is not None else None
		job.error_code = None
		job.error_message = None
		job.locked_until = None
		job.finished_at = datetime.utcnow()
		db.commit()


def process_quick_sale_invoice_jobs_once() -> bool:
	job_id = _claim_one_job()
	if job_id is None:
		return False
	try:
		_process_job(job_id)
	except Exception as exc:
		code, message, transient = _error_data(exc)
		logger.exception("quick_sale_invoice_job_failed job_id=%s code=%s", job_id, code)
		from adapters.db.session import get_db_session
		with get_db_session() as db:
			job = db.query(QuickSaleInvoiceJob).filter(QuickSaleInvoiceJob.id == int(job_id)).first()
			if job is None:
				return True
			job.error_code = code
			job.error_message = message
			job.locked_until = None
			if transient and int(job.attempt_count or 0) < MAX_ATTEMPTS:
				delay_seconds = min(30 * (2 ** max(0, int(job.attempt_count or 1) - 1)), 300)
				job.status = "queued"
				job.available_at = datetime.utcnow() + timedelta(seconds=delay_seconds)
			else:
				job.status = "failed"
				job.finished_at = datetime.utcnow()
			db.commit()
	return True


async def quick_sale_invoice_outbox_loop(interval_seconds: float = 0.5) -> None:
	while True:
		try:
			processed = await asyncio.to_thread(process_quick_sale_invoice_jobs_once)
			if processed:
				continue
		except Exception:
			logger.exception("quick_sale_invoice_outbox_loop_failed")
			await asyncio.sleep(max(5.0, interval_seconds))
			continue
		await asyncio.sleep(interval_seconds)
