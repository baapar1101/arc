"""سرویس CRUD و اجرای گزارش‌های HScript."""

from __future__ import annotations

import re
import time
from typing import Any, Optional

from sqlalchemy.orm import Session

from adapters.db.models.hscript_report import HScriptReport, HScriptReportRun, HScriptReportVersion
from app.core.datetime_utils import utc_now_aware
from app.core.responses import ApiError
from app.services.hscript import HSCRIPT_LANGUAGE_VERSION, run_script, source_hash, validate_script
from app.services.hscript.plan_limits import resolve_hscript_entitlement


_SLUG_RE = re.compile(r"^[a-z0-9][a-z0-9_-]{1,78}$")


def _slugify(title: str) -> str:
	base = re.sub(r"[^a-zA-Z0-9_-]+", "-", title.strip().lower()).strip("-")
	base = re.sub(r"-{2,}", "-", base)
	if not base:
		base = "report"
	return base[:78]


def _serialize_report(row: HScriptReport, *, include_source: bool = True) -> dict[str, Any]:
	data: dict[str, Any] = {
		"id": row.id,
		"business_id": row.business_id,
		"slug": row.slug,
		"title": row.title,
		"description": row.description,
		"status": row.status,
		"source_hash": row.source_hash,
		"language_version": row.language_version,
		"default_params": row.default_params or {},
		"created_by_user_id": row.created_by_user_id,
		"updated_by_user_id": row.updated_by_user_id,
		"published_at": row.published_at.isoformat() if row.published_at else None,
		"created_at": row.created_at.isoformat() if row.created_at else None,
		"updated_at": row.updated_at.isoformat() if row.updated_at else None,
	}
	if include_source:
		data["source_code"] = row.source_code
	return data


def _get_report(db: Session, business_id: int, report_id: int) -> HScriptReport:
	row = (
		db.query(HScriptReport)
		.filter(
			HScriptReport.id == report_id,
			HScriptReport.business_id == business_id,
			HScriptReport.is_deleted.is_(False),
		)
		.first()
	)
	if not row:
		raise ApiError("HSCRIPT_REPORT_NOT_FOUND", "گزارش یافت نشد", http_status=404)
	return row


def list_reports(db: Session, business_id: int, *, status: Optional[str] = None) -> dict[str, Any]:
	q = db.query(HScriptReport).filter(
		HScriptReport.business_id == business_id,
		HScriptReport.is_deleted.is_(False),
	)
	if status:
		q = q.filter(HScriptReport.status == status)
	rows = q.order_by(HScriptReport.updated_at.desc()).limit(200).all()
	return {"items": [_serialize_report(r, include_source=False) for r in rows], "total": len(rows)}


def get_plan_status(db: Session, business_id: int) -> dict[str, Any]:
	ent = resolve_hscript_entitlement(db, business_id)
	data = ent.to_public_dict()
	data["saved_reports_count"] = count_saved_reports(db, business_id)
	from app.services.hscript_schedule_service import count_schedules

	data["schedules_count"] = count_schedules(db, business_id)
	return data


def get_report(db: Session, business_id: int, report_id: int) -> dict[str, Any]:
	row = _get_report(db, business_id, report_id)
	data = _serialize_report(row)
	from app.services.hscript.param_schema import infer_param_schema

	data["param_schema"] = infer_param_schema(
		source_code=row.source_code,
		default_params=row.default_params or {},
	)
	return data


def infer_report_param_schema(
	*,
	source_code: str | None = None,
	default_params: dict[str, Any] | None = None,
	params: dict[str, Any] | None = None,
) -> dict[str, Any]:
	from app.services.hscript.param_schema import infer_param_schema

	return infer_param_schema(
		source_code=source_code,
		default_params=default_params,
		runtime_params=params,
	)


def get_catalog() -> dict[str, Any]:
	from app.services.hscript.catalog import build_catalog

	return build_catalog()


def list_recipes() -> dict[str, Any]:
	from app.services.hscript.catalog import list_recipes as _list

	items = _list()
	return {"items": items, "total": len(items)}


def count_saved_reports(db: Session, business_id: int) -> int:
	return (
		db.query(HScriptReport.id)
		.filter(
			HScriptReport.business_id == business_id,
			HScriptReport.is_deleted.is_(False),
		)
		.count()
	)


def create_report(
	db: Session,
	business_id: int,
	*,
	user_id: int,
	title: str,
	source_code: str,
	slug: Optional[str] = None,
	description: Optional[str] = None,
	default_params: Optional[dict[str, Any]] = None,
) -> dict[str, Any]:
	title_s = (title or "").strip()
	if not title_s:
		raise ApiError("INVALID_TITLE", "عنوان الزامی است", http_status=400)
	code = source_code or ""
	validation = validate_script(code)
	if not validation.get("ok"):
		raise ApiError("HSCRIPT_SYNTAX_ERROR", "خطای نحوی در اسکریپت", http_status=400, details=validation.get("error"))

	ent = resolve_hscript_entitlement(db, business_id)
	current_count = count_saved_reports(db, business_id)
	if current_count >= ent.max_saved_reports:
		raise ApiError(
			"HSCRIPT_REPORT_LIMIT",
			f"سقف تعداد گزارش ذخیره‌شده ({ent.max_saved_reports}) برای پلن فعلی پر شده است.",
			http_status=403,
			details=ent.to_public_dict(),
		)

	slug_s = (slug or _slugify(title_s)).lower()
	if not _SLUG_RE.match(slug_s):
		raise ApiError("INVALID_SLUG", "slug نامعتبر است", http_status=400)

	exists = (
		db.query(HScriptReport.id)
		.filter(HScriptReport.business_id == business_id, HScriptReport.slug == slug_s, HScriptReport.is_deleted.is_(False))
		.first()
	)
	if exists:
		raise ApiError("SLUG_EXISTS", "این slug قبلاً استفاده شده", http_status=409)

	now = utc_now_aware()
	row = HScriptReport(
		business_id=business_id,
		slug=slug_s,
		title=title_s,
		description=description,
		status="draft",
		source_code=code,
		source_hash=source_hash(code),
		language_version=HSCRIPT_LANGUAGE_VERSION,
		default_params=default_params or {},
		created_by_user_id=user_id,
		updated_by_user_id=user_id,
		created_at=now,
		updated_at=now,
	)
	db.add(row)
	db.flush()

	ver = HScriptReportVersion(
		report_id=row.id,
		business_id=business_id,
		version_no=1,
		source_code=code,
		source_hash=row.source_hash or source_hash(code),
		language_version=HSCRIPT_LANGUAGE_VERSION,
		changelog="initial",
		created_by_user_id=user_id,
		created_at=now,
	)
	db.add(ver)
	db.commit()
	db.refresh(row)
	return _serialize_report(row)


def update_report(
	db: Session,
	business_id: int,
	report_id: int,
	*,
	user_id: int,
	title: Optional[str] = None,
	description: Optional[str] = None,
	source_code: Optional[str] = None,
	default_params: Optional[dict[str, Any]] = None,
	changelog: Optional[str] = None,
) -> dict[str, Any]:
	row = _get_report(db, business_id, report_id)
	if title is not None:
		title_s = title.strip()
		if not title_s:
			raise ApiError("INVALID_TITLE", "عنوان الزامی است", http_status=400)
		row.title = title_s
	if description is not None:
		row.description = description
	if default_params is not None:
		row.default_params = default_params

	if source_code is not None:
		validation = validate_script(source_code)
		if not validation.get("ok"):
			raise ApiError("HSCRIPT_SYNTAX_ERROR", "خطای نحوی در اسکریپت", http_status=400, details=validation.get("error"))
		row.source_code = source_code
		row.source_hash = source_hash(source_code)
		row.language_version = HSCRIPT_LANGUAGE_VERSION
		last_ver = (
			db.query(HScriptReportVersion)
			.filter(HScriptReportVersion.report_id == row.id, HScriptReportVersion.business_id == business_id)
			.order_by(HScriptReportVersion.version_no.desc())
			.first()
		)
		next_no = (last_ver.version_no + 1) if last_ver else 1
		db.add(
			HScriptReportVersion(
				report_id=row.id,
				business_id=business_id,
				version_no=next_no,
				source_code=source_code,
				source_hash=row.source_hash,
				language_version=HSCRIPT_LANGUAGE_VERSION,
				changelog=changelog or f"v{next_no}",
				created_by_user_id=user_id,
				created_at=utc_now_aware(),
			)
		)
		# ویرایش سورس گزارش published را به draft برمی‌گرداند تا دوباره publish شود
		if row.status == "published":
			row.status = "draft"

	row.updated_by_user_id = user_id
	row.updated_at = utc_now_aware()
	db.commit()
	db.refresh(row)
	return _serialize_report(row)


def publish_report(db: Session, business_id: int, report_id: int, *, user_id: int) -> dict[str, Any]:
	row = _get_report(db, business_id, report_id)
	validation = validate_script(row.source_code or "")
	if not validation.get("ok"):
		raise ApiError("HSCRIPT_SYNTAX_ERROR", "اسکریپت نامعتبر است", http_status=400, details=validation.get("error"))
	row.status = "published"
	row.published_at = utc_now_aware()
	row.updated_by_user_id = user_id
	row.updated_at = utc_now_aware()
	db.commit()
	db.refresh(row)
	return _serialize_report(row)


def archive_report(db: Session, business_id: int, report_id: int, *, user_id: int) -> dict[str, Any]:
	row = _get_report(db, business_id, report_id)
	row.status = "archived"
	row.updated_by_user_id = user_id
	row.updated_at = utc_now_aware()
	db.commit()
	db.refresh(row)
	return _serialize_report(row)


def delete_report(db: Session, business_id: int, report_id: int, *, user_id: int) -> dict[str, Any]:
	row = _get_report(db, business_id, report_id)
	row.is_deleted = True
	row.updated_by_user_id = user_id
	row.updated_at = utc_now_aware()
	db.commit()
	return {"deleted": True, "id": report_id}


def list_versions(db: Session, business_id: int, report_id: int) -> dict[str, Any]:
	_get_report(db, business_id, report_id)
	rows = (
		db.query(HScriptReportVersion)
		.filter(HScriptReportVersion.report_id == report_id, HScriptReportVersion.business_id == business_id)
		.order_by(HScriptReportVersion.version_no.desc())
		.limit(100)
		.all()
	)
	items = [
		{
			"id": v.id,
			"version_no": v.version_no,
			"source_hash": v.source_hash,
			"language_version": v.language_version,
			"changelog": v.changelog,
			"created_by_user_id": v.created_by_user_id,
			"created_at": v.created_at.isoformat() if v.created_at else None,
			"source_preview": (v.source_code or "")[:240],
			"source_lines": (v.source_code or "").count("\n") + (1 if v.source_code else 0),
		}
		for v in rows
	]
	return {"items": items, "total": len(items)}


def get_version(db: Session, business_id: int, report_id: int, version_id: int) -> dict[str, Any]:
	_get_report(db, business_id, report_id)
	v = (
		db.query(HScriptReportVersion)
		.filter(
			HScriptReportVersion.id == version_id,
			HScriptReportVersion.report_id == report_id,
			HScriptReportVersion.business_id == business_id,
		)
		.first()
	)
	if not v:
		raise ApiError("HSCRIPT_VERSION_NOT_FOUND", "نسخه یافت نشد", http_status=404)
	return {
		"id": v.id,
		"report_id": v.report_id,
		"version_no": v.version_no,
		"source_code": v.source_code,
		"source_hash": v.source_hash,
		"language_version": v.language_version,
		"changelog": v.changelog,
		"created_by_user_id": v.created_by_user_id,
		"created_at": v.created_at.isoformat() if v.created_at else None,
	}


def restore_version(
	db: Session,
	business_id: int,
	report_id: int,
	version_id: int,
	*,
	user_id: int,
	changelog: Optional[str] = None,
) -> dict[str, Any]:
	"""بازگردانی محتوای یک نسخهٔ قبلی به‌عنوان نسخهٔ جدید (immutable history حفظ می‌شود)."""
	row = _get_report(db, business_id, report_id)
	ver = (
		db.query(HScriptReportVersion)
		.filter(
			HScriptReportVersion.id == version_id,
			HScriptReportVersion.report_id == report_id,
			HScriptReportVersion.business_id == business_id,
		)
		.first()
	)
	if not ver:
		raise ApiError("HSCRIPT_VERSION_NOT_FOUND", "نسخه یافت نشد", http_status=404)

	code = ver.source_code or ""
	sh = source_hash(code)
	last = (
		db.query(HScriptReportVersion)
		.filter(HScriptReportVersion.report_id == row.id, HScriptReportVersion.business_id == business_id)
		.order_by(HScriptReportVersion.version_no.desc())
		.first()
	)
	next_no = (last.version_no + 1) if last else 1
	note = changelog or f"بازگردانی از نسخه {ver.version_no}"
	new_ver = HScriptReportVersion(
		report_id=row.id,
		business_id=business_id,
		version_no=next_no,
		source_code=code,
		source_hash=sh,
		language_version=HSCRIPT_LANGUAGE_VERSION,
		changelog=note,
		created_by_user_id=user_id,
		created_at=utc_now_aware(),
	)
	row.source_code = code
	row.source_hash = sh
	row.language_version = HSCRIPT_LANGUAGE_VERSION
	row.updated_by_user_id = user_id
	row.updated_at = utc_now_aware()
	if row.status == "published":
		row.status = "draft"
		row.published_at = None
	db.add(new_ver)
	db.commit()
	db.refresh(row)
	data = _serialize_report(row)
	data["restored_from_version_id"] = ver.id
	data["restored_from_version_no"] = ver.version_no
	data["new_version_no"] = next_no
	return data


def list_runs(
	db: Session,
	business_id: int,
	report_id: int,
	*,
	limit: int = 30,
) -> dict[str, Any]:
	_get_report(db, business_id, report_id)
	take = max(1, min(int(limit), 100))
	rows = (
		db.query(HScriptReportRun)
		.filter(
			HScriptReportRun.business_id == business_id,
			HScriptReportRun.report_id == report_id,
		)
		.order_by(HScriptReportRun.id.desc())
		.limit(take)
		.all()
	)
	items = []
	for r in rows:
		err = r.error if isinstance(r.error, dict) else None
		items.append(
			{
				"id": r.id,
				"status": r.status,
				"is_preview": r.is_preview,
				"source_hash": r.source_hash,
				"duration_ms": r.duration_ms,
				"ran_by_user_id": r.ran_by_user_id,
				"created_at": r.created_at.isoformat() if r.created_at else None,
				"error_code": (err or {}).get("code"),
				"error_message": (err or {}).get("message"),
				"stats": {
					"steps": (r.stats or {}).get("steps") if isinstance(r.stats, dict) else None,
					"gateway_calls": (r.stats or {}).get("gateway_calls") if isinstance(r.stats, dict) else None,
					"blocks": (r.stats or {}).get("blocks") if isinstance(r.stats, dict) else None,
				},
			}
		)
	return {"items": items, "total": len(items)}


def run_report(
	db: Session,
	business_id: int,
	*,
	user_id: int,
	report_id: Optional[int] = None,
	source_code: Optional[str] = None,
	params: Optional[dict[str, Any]] = None,
	fiscal_year_id: Optional[int] = None,
	preview: bool = False,
	persist: bool = True,
	use_worker_limits: bool = False,
	calendar_type: Optional[str] = None,
) -> dict[str, Any]:
	"""اجرای گزارش ذخیره‌شده یا اسکریپت موقت (preview)."""
	version_id = None
	rid = report_id
	code = source_code
	merged_params: dict[str, Any] = {}

	if report_id is not None:
		row = _get_report(db, business_id, report_id)
		code = row.source_code
		merged_params.update(row.default_params or {})
		last_ver = (
			db.query(HScriptReportVersion)
			.filter(HScriptReportVersion.report_id == row.id, HScriptReportVersion.business_id == business_id)
			.order_by(HScriptReportVersion.version_no.desc())
			.first()
		)
		version_id = last_ver.id if last_ver else None
	if source_code is not None and report_id is None:
		code = source_code
	if not code:
		raise ApiError("EMPTY_SCRIPT", "اسکریپت خالی است", http_status=400)

	merged_params.update(params or {})
	# حذف کلیدهای ممنوع حتی اگر در default_params باشند
	for banned in ("business_id", "user_id", "db", "session", "settings", "token", "api_key", "__worker__"):
		merged_params.pop(banned, None)

	if use_worker_limits:
		from app.services.hscript.hardening import worker_limits

		limits = worker_limits(preview=preview)
	else:
		ent = resolve_hscript_entitlement(db, business_id)
		limits = ent.resource_for(preview=preview)
	started = time.monotonic()
	result = run_script(
		code,
		db=db,
		business_id=business_id,
		user_id=user_id,
		fiscal_year_id=fiscal_year_id,
		params=merged_params,
		limits=limits,
		preview=preview,
		calendar_type=calendar_type,
	)
	duration_ms = int((time.monotonic() - started) * 1000)

	payload: dict[str, Any] = {
		"ok": result.ok,
		"spec": result.spec,
		"error": result.error,
		"stats": {**(result.stats or {}), "duration_ms": duration_ms},
		"source_hash": result.source_hash,
		"preview": preview,
	}

	if persist:
		run_row = HScriptReportRun(
			report_id=rid,
			business_id=business_id,
			version_id=version_id,
			ran_by_user_id=user_id,
			status="success" if result.ok else "error",
			is_preview=preview,
			source_hash=result.source_hash,
			params=merged_params,
			result_spec=result.spec if result.ok else None,
			error=result.error,
			stats=payload["stats"],
			duration_ms=duration_ms,
			created_at=utc_now_aware(),
		)
		db.add(run_row)
		db.commit()
		db.refresh(run_row)
		payload["run_id"] = run_row.id

	return payload


def validate_only(source_code: str) -> dict[str, Any]:
	return validate_script(source_code or "")


def count_recent_runs(db: Session, business_id: int, *, seconds: int = 60) -> int:
	"""تعداد اجرای اخیر برای محدود کردن همزمانی."""
	from datetime import timedelta

	cutoff = utc_now_aware() - timedelta(seconds=seconds)
	return (
		db.query(HScriptReportRun.id)
		.filter(
			HScriptReportRun.business_id == business_id,
			HScriptReportRun.created_at >= cutoff,
		)
		.count()
	)


def enqueue_run_report(
	*,
	business_id: int,
	user_id: int,
	report_id: Optional[int] = None,
	source_code: Optional[str] = None,
	params: Optional[dict[str, Any]] = None,
	fiscal_year_id: Optional[int] = None,
	preview: bool = False,
	persist: bool = True,
	calendar_type: Optional[str] = None,
) -> Optional[dict[str, Any]]:
	"""
	صف‌بندی اجرا روی QUEUE_REPORTS.
	اگر Redis/queue در دسترس نباشد None برمی‌گرداند تا caller به sync برگردد.
	"""
	from app.core.queue import QUEUE_REPORTS, get_queue_service
	from app.services.jobs.hscript_job import run_hscript_report_job

	queue_service = get_queue_service()
	if not queue_service or not queue_service.enabled:
		return None

	job = queue_service.enqueue(
		run_hscript_report_job,
		int(business_id),
		int(user_id),
		source_code=source_code,
		report_id=report_id,
		params=params or {},
		fiscal_year_id=fiscal_year_id,
		preview=bool(preview),
		persist=bool(persist),
		calendar_type=calendar_type,
		queue_name=QUEUE_REPORTS,
		timeout=600 if preview else 1800,
		result_ttl=86400,
	)
	if job is None:
		return None

	try:
		job.meta.update(
			{
				"user_id": int(user_id),
				"business_id": int(business_id),
				"kind": "hscript_run",
				"report_id": report_id,
				"preview": bool(preview),
			}
		)
		job.save_meta()
	except Exception:
		pass

	return {
		"async": True,
		"job_id": job.id,
		"queue": QUEUE_REPORTS,
		"preview": bool(preview),
	}


def build_assist_context(query: str, *, source_code: Optional[str] = None, limit: int = 5) -> dict[str, Any]:
	"""بازیابی مستندات مرتبط برای دستیار AI / Studio."""
	from app.services.hscript.docs_catalog import retrieve_docs_for_rag

	docs = retrieve_docs_for_rag(query, limit=max(1, min(int(limit), 8)))

	guide = (
		"تو دستیار گزارش‌نویسی HScript حسابیکس هستی. "
		"فقط اسکریپت HScript امن تولید کن (بدون import/SQL/فایل/شبکه). "
		"از ماژول‌های invoices/customers/persons/products/payments/banks/warehouses/debtors/creditors "
		"و جدول‌های HTable (where/join/pivot/distinct) و report.* استفاده کن. "
		"در صورت نیاز پارامترها را با کامنت # @param تعریف کن. "
		"اسکریپت نهایی را داخل بلوک ```hscript قرار بده."
	)
	return {
		"system_guide": guide,
		"query": query,
		"docs": docs,
		"current_source_excerpt": (source_code or "")[:4000] or None,
		"language_version": HSCRIPT_LANGUAGE_VERSION,
	}


def export_pdf(
	db: Session,
	business_id: int,
	*,
	user_id: int,
	report_id: Optional[int] = None,
	source_code: Optional[str] = None,
	spec: Optional[dict[str, Any]] = None,
	params: Optional[dict[str, Any]] = None,
	fiscal_year_id: Optional[int] = None,
) -> tuple[bytes, str]:
	"""اجرا (در صورت نیاز) و تولید PDF. برمی‌گرداند (pdf_bytes, filename)."""
	ent = resolve_hscript_entitlement(db, business_id)
	if not ent.pdf_allowed:
		raise ApiError(
			"HSCRIPT_PDF_NOT_ALLOWED",
			"خروجی PDF در پلن فعلی مجاز نیست.",
			http_status=403,
			details=ent.to_public_dict(),
		)
	from adapters.db.models.business import Business
	from app.services.hscript.pdf_renderer import render_spec_pdf

	resolved_spec = spec
	title = "hscript-report"
	if resolved_spec is None:
		run = run_report(
			db,
			business_id,
			user_id=user_id,
			report_id=report_id,
			source_code=source_code,
			params=params,
			fiscal_year_id=fiscal_year_id,
			preview=False,
			persist=True,
		)
		if not run.get("ok"):
			raise ApiError("HSCRIPT_RUN_FAILED", "اجرای اسکریپت برای PDF ناموفق بود", http_status=400, details=run.get("error"))
		resolved_spec = run.get("spec") or {}
		title = (resolved_spec.get("title") if isinstance(resolved_spec, dict) else None) or title
	elif not isinstance(resolved_spec, dict):
		raise ApiError("INVALID_SPEC", "spec نامعتبر است", http_status=400)

	if report_id is not None:
		row = _get_report(db, business_id, report_id)
		title = row.title or title

	biz = db.query(Business).filter(Business.id == business_id).first()
	business_name = getattr(biz, "name", None) if biz else None
	pdf_bytes = render_spec_pdf(resolved_spec, business_name=business_name)
	safe_name = re.sub(r"[^\w\-]+", "-", str(title), flags=re.UNICODE).strip("-") or "hscript-report"
	filename = f"{safe_name[:80]}.pdf"
	return pdf_bytes, filename


def export_excel(
	db: Session,
	business_id: int,
	*,
	user_id: int,
	report_id: Optional[int] = None,
	source_code: Optional[str] = None,
	spec: Optional[dict[str, Any]] = None,
	params: Optional[dict[str, Any]] = None,
	fiscal_year_id: Optional[int] = None,
) -> tuple[bytes, str]:
	"""اجرا (در صورت نیاز) و تولید Excel از Spec."""
	ent = resolve_hscript_entitlement(db, business_id)
	if not ent.excel_allowed:
		raise ApiError(
			"HSCRIPT_EXCEL_NOT_ALLOWED",
			"خروجی Excel در پلن فعلی مجاز نیست.",
			http_status=403,
			details=ent.to_public_dict(),
		)
	from adapters.db.models.business import Business
	from app.services.hscript.excel_renderer import spec_to_excel_bytes

	resolved_spec = spec
	title = "hscript-report"
	if resolved_spec is None:
		run = run_report(
			db,
			business_id,
			user_id=user_id,
			report_id=report_id,
			source_code=source_code,
			params=params,
			fiscal_year_id=fiscal_year_id,
			preview=False,
			persist=True,
		)
		if not run.get("ok"):
			raise ApiError(
				"HSCRIPT_RUN_FAILED",
				"اجرای اسکریپت برای Excel ناموفق بود",
				http_status=400,
				details=run.get("error"),
			)
		resolved_spec = run.get("spec") or {}
		title = (resolved_spec.get("title") if isinstance(resolved_spec, dict) else None) or title
	elif not isinstance(resolved_spec, dict):
		raise ApiError("INVALID_SPEC", "spec نامعتبر است", http_status=400)

	if report_id is not None:
		row = _get_report(db, business_id, report_id)
		title = row.title or title

	biz = db.query(Business).filter(Business.id == business_id).first()
	business_name = getattr(biz, "name", None) if biz else None
	xlsx = spec_to_excel_bytes(resolved_spec, business_name=business_name)
	safe_name = re.sub(r"[^\w\-]+", "-", str(title), flags=re.UNICODE).strip("-") or "hscript-report"
	filename = f"{safe_name[:80]}.xlsx"
	return xlsx, filename


def list_runs_admin(
	db: Session,
	*,
	business_id: Optional[int] = None,
	status: Optional[str] = None,
	skip: int = 0,
	take: int = 50,
) -> dict[str, Any]:
	"""لیست اجرای HScript برای ادمین (بدون result_spec حجیم)."""
	q = db.query(HScriptReportRun)
	if business_id is not None:
		q = q.filter(HScriptReportRun.business_id == int(business_id))
	if status:
		q = q.filter(HScriptReportRun.status == status)
	total = q.count()
	rows = (
		q.order_by(HScriptReportRun.created_at.desc())
		.offset(max(0, skip))
		.limit(min(max(1, take), 200))
		.all()
	)
	items = []
	for r in rows:
		items.append(
			{
				"id": r.id,
				"business_id": r.business_id,
				"report_id": r.report_id,
				"version_id": r.version_id,
				"ran_by_user_id": r.ran_by_user_id,
				"status": r.status,
				"is_preview": r.is_preview,
				"source_hash": r.source_hash,
				"error_code": (r.error or {}).get("code") if isinstance(r.error, dict) else None,
				"error_message": (r.error or {}).get("message") if isinstance(r.error, dict) else None,
				"duration_ms": r.duration_ms,
				"created_at": r.created_at.isoformat() if r.created_at else None,
			}
		)
	return {"items": items, "total": total, "skip": skip, "take": take}
