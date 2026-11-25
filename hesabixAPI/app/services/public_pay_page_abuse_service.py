"""گزارش تخلف صفحه واریز عمومی برای بررسی در تنظیمات سیستم."""
from __future__ import annotations

from datetime import datetime, timedelta
from typing import Any, Dict

from sqlalchemy.orm import Session

from adapters.db.models.business_pay_page import PublicPayPageAbuseReport
from app.core.responses import ApiError
from app.services.business_pay_page_service import (
	find_pay_page_by_username,
	normalize_username,
	validate_payer_mobile,
	validate_payer_name,
)

ABUSE_REASONS = {
	"phishing": "فیشینگ / صفحه جعلی",
	"wrong_business": "کسب‌وکار مورد نظر من نیست",
	"impersonation": "سوءاستفاده از نام کسب‌وکار",
	"fraud": "کلاهبرداری",
	"other": "سایر",
}
ABUSE_STATUSES = {"new", "reviewed", "dismissed"}
DETAILS_MIN = 20
DETAILS_MAX = 2000
RATE_LIMIT_PER_HOUR = 3


def submit_pay_page_abuse_report(
	db: Session,
	*,
	username: str,
	reason: str,
	details: str,
	reporter_name: str | None = None,
	reporter_mobile: str | None = None,
	page_url: str | None = None,
	ip_address: str | None = None,
	user_agent: str | None = None,
) -> Dict[str, Any]:
	handle = normalize_username(username)
	if not handle:
		raise ApiError("PAY_PAGE_NOT_FOUND", "صفحه پرداخت یافت نشد", http_status=404)
	page, _redirect = find_pay_page_by_username(db, handle)
	if not page:
		raise ApiError("PAY_PAGE_NOT_FOUND", "صفحه پرداخت یافت نشد", http_status=404)

	code = (reason or "").strip().lower()
	if code not in ABUSE_REASONS:
		raise ApiError("INVALID_REASON", "نوع گزارش نامعتبر است", http_status=400)
	note = (details or "").strip()
	if len(note) < DETAILS_MIN:
		raise ApiError("DETAILS_TOO_SHORT", "توضیح گزارش باید حداقل ۲۰ نویسه باشد", http_status=400)
	if len(note) > DETAILS_MAX:
		note = note[:DETAILS_MAX]
	name = validate_payer_name(reporter_name)
	mobile = validate_payer_mobile(reporter_mobile)

	since = datetime.utcnow() - timedelta(hours=1)
	q = db.query(PublicPayPageAbuseReport).filter(
		PublicPayPageAbuseReport.username == (page.username or handle),
		PublicPayPageAbuseReport.created_at >= since,
	)
	if ip_address:
		q = q.filter(PublicPayPageAbuseReport.ip_address == ip_address)
	if q.count() >= RATE_LIMIT_PER_HOUR:
		raise ApiError("REPORT_RATE_LIMIT", "تعداد گزارش‌های شما برای این صفحه زیاد است. کمی بعد دوباره تلاش کنید", http_status=429)

	row = PublicPayPageAbuseReport(
		business_id=int(page.business_id),
		username=str(page.username or handle),
		reason=code,
		details=note,
		reporter_name=name,
		reporter_mobile=mobile,
		page_url=(page_url or "")[:500] or None,
		ip_address=(ip_address or "")[:64] or None,
		user_agent=(user_agent or "")[:400] or None,
		status="new",
	)
	db.add(row)
	db.commit()
	db.refresh(row)
	return _serialize_report(row)


def list_pay_page_abuse_reports(
	db: Session,
	*,
	status: str | None = None,
	take: int = 30,
	skip: int = 0,
) -> Dict[str, Any]:
	take = max(1, min(int(take or 30), 100))
	skip = max(0, int(skip or 0))
	q = db.query(PublicPayPageAbuseReport)
	if status and status in ABUSE_STATUSES:
		q = q.filter(PublicPayPageAbuseReport.status == status)
	total = q.count()
	rows = (
		q.order_by(PublicPayPageAbuseReport.created_at.desc())
		.offset(skip)
		.limit(take)
		.all()
	)
	return {
		"items": [_serialize_report(r) for r in rows],
		"total": total,
		"take": take,
		"skip": skip,
		"reasons": ABUSE_REASONS,
	}


def update_pay_page_abuse_report(
	db: Session,
	report_id: int,
	*,
	status: str | None = None,
	admin_note: str | None = None,
	reviewed_by: int | None = None,
) -> Dict[str, Any]:
	row = db.query(PublicPayPageAbuseReport).filter(PublicPayPageAbuseReport.id == int(report_id)).first()
	if not row:
		raise ApiError("REPORT_NOT_FOUND", "گزارش یافت نشد", http_status=404)
	if status:
		if status not in ABUSE_STATUSES:
			raise ApiError("INVALID_STATUS", "وضعیت نامعتبر است", http_status=400)
		row.status = status
		if status in ("reviewed", "dismissed"):
			row.reviewed_at = datetime.utcnow()
			row.reviewed_by = reviewed_by
	if admin_note is not None:
		row.admin_note = (admin_note or "").strip()[:2000] or None
	db.commit()
	db.refresh(row)
	return _serialize_report(row)


def _serialize_report(row: PublicPayPageAbuseReport) -> Dict[str, Any]:
	return {
		"id": int(row.id),
		"business_id": int(row.business_id) if row.business_id else None,
		"username": row.username,
		"reason": row.reason,
		"reason_label": ABUSE_REASONS.get(row.reason, row.reason),
		"details": row.details,
		"reporter_name": row.reporter_name,
		"reporter_mobile": row.reporter_mobile,
		"page_url": row.page_url,
		"ip_address": row.ip_address,
		"status": row.status,
		"admin_note": row.admin_note,
		"created_at": row.created_at.isoformat() if row.created_at else None,
		"reviewed_at": row.reviewed_at.isoformat() if row.reviewed_at else None,
	}
