from __future__ import annotations

import os
import tempfile
from typing import List, Optional, Tuple

from fastapi import APIRouter, BackgroundTasks, Depends, File, Query, Request, UploadFile

from adapters.db.session import get_db_session
from app.core.auth_dependency import AuthContext, get_current_user
from app.core.responses import ApiError, success_response
from app.services.job_manager import JobManager
from app.services.legacy_sql.hs60_loader import LegacyImportFileError, materialize_legacy_sql_path
from app.services.legacy_sql.legacy_sql_import_service import (
	LEGACY_REWRITE_CONFIRMATION_EN,
	LEGACY_REWRITE_CONFIRMATION_FA,
	LegacyImportOptions,
	LegacySqlImportService,
)

router = APIRouter(prefix="/admin/legacy-import", tags=["مدیریت سیستم - ایمپورت دیتابیس قدیمی"])

_ALLOWED_EXTENSIONS = (".sql", ".sql.gz", ".gz", ".hs60", ".zip")


def _require_superadmin(ctx: AuthContext) -> None:
	if not ctx.has_any_permission("superadmin"):
		raise ApiError("FORBIDDEN", "فقط superadmin مجاز است.", http_status=403)


def _is_allowed_legacy_filename(filename: str) -> bool:
	name = (filename or "").strip().lower()
	return any(name.endswith(ext) for ext in _ALLOWED_EXTENSIONS)


async def _read_upload_to_temp(file: UploadFile) -> Tuple[str, List[str]]:
	filename = (file.filename or "").strip().lower()
	if not _is_allowed_legacy_filename(filename):
		raise ApiError(
			"INVALID_FILE_TYPE",
			"فرمت فایل باید .sql، .sql.gz، .zip یا .hs60 باشد.",
			http_status=400,
		)
	try:
		content = await file.read()
	except Exception as exc:
		raise ApiError("FILE_READ_ERROR", f"خواندن فایل ناموفق بود: {exc}", http_status=400) from exc
	if len(content) < 50:
		raise ApiError("INVALID_FILE", "فایل خیلی کوچک یا نامعتبر است.", http_status=400)

	if filename.endswith(".gz"):
		suffix = ".sql.gz"
	elif filename.endswith(".zip"):
		suffix = ".zip"
	elif filename.endswith(".hs60"):
		suffix = ".hs60"
	else:
		suffix = ".sql"

	fd, temp_path = tempfile.mkstemp(suffix=suffix)
	try:
		os.write(fd, content)
	finally:
		os.close(fd)

	try:
		sql_path, cleanup_paths = materialize_legacy_sql_path(temp_path)
	except LegacyImportFileError as exc:
		try:
			os.unlink(temp_path)
		except OSError:
			pass
		raise ApiError("INVALID_FILE", str(exc), http_status=400) from exc

	# فایل اصلی آپلود + هر فایل استخراج‌شده
	all_paths = list(dict.fromkeys([temp_path, sql_path, *cleanup_paths]))
	return sql_path, all_paths


def _unlink_paths(paths: List[str]) -> None:
	for p in paths:
		try:
			os.unlink(p)
		except OSError:
			pass


@router.post(
	"/analyze",
	summary="تحلیل فایل دیتابیس قدیمی",
	description="خواندن دامپ MySQL (.sql / .sql.gz / .zip / .hs60) و گزارش آمار بدون تغییر در دیتابیس.",
)
async def analyze_legacy_sql(
	request: Request,
	file: UploadFile = File(...),
	ctx: AuthContext = Depends(get_current_user),
):
	_require_superadmin(ctx)
	sql_path, cleanup_paths = await _read_upload_to_temp(file)
	try:
		with get_db_session() as db:
			report = LegacySqlImportService(db).analyze_file(sql_path)
		return success_response(report, request, message="LEGACY_SQL_ANALYZED")
	finally:
		_unlink_paths(cleanup_paths)


@router.post(
	"/run",
	summary="اجرای ایمپورت دیتابیس قدیمی",
	description="ایمپورت داده از دامپ MySQL در پس‌زمینه. وضعیت از job_id پیگیری می‌شود.",
)
async def run_legacy_sql_import(
	request: Request,
	background_tasks: BackgroundTasks,
	file: UploadFile = File(...),
	import_mode: str = Query("new_business"),
	target_business_id: Optional[int] = Query(None),
	owner_user_id: Optional[int] = Query(None),
	dry_run: bool = Query(False),
	import_users: bool = Query(True),
	import_master_data: bool = Query(True),
	import_invoices: bool = Query(True),
	import_receipts_payments: bool = Query(True),
	import_expense_income: bool = Query(True),
	import_warehouses: bool = Query(True),
	import_transfers: bool = Query(True),
	import_opening_balance: bool = Query(True),
	import_checks: bool = Query(True),
	rewrite_confirmation: Optional[str] = Query(None),
	conflict_policy: str = Query("skip"),
	ctx: AuthContext = Depends(get_current_user),
):
	_require_superadmin(ctx)
	valid_modes = ("new_business", "merge_into_business", "rewrite_business")
	if import_mode not in valid_modes:
		raise ApiError("INVALID_IMPORT_MODE", "import_mode نامعتبر است.", http_status=400)
	if import_mode in ("merge_into_business", "rewrite_business") and not target_business_id:
		raise ApiError(
			"TARGET_BUSINESS_REQUIRED",
			"برای merge/rewrite باید target_business_id مشخص شود.",
			http_status=400,
		)
	if import_mode == "rewrite_business":
		conf = (rewrite_confirmation or "").strip()
		if conf not in (LEGACY_REWRITE_CONFIRMATION_FA, LEGACY_REWRITE_CONFIRMATION_EN):
			raise ApiError(
				"CONFIRMATION_REQUIRED",
				f"برای بازنویسی عبارت '{LEGACY_REWRITE_CONFIRMATION_FA}' یا '{LEGACY_REWRITE_CONFIRMATION_EN}' را وارد کنید.",
				http_status=400,
			)

	sql_path, cleanup_paths = await _read_upload_to_temp(file)
	options = LegacyImportOptions(
		import_mode=import_mode,
		target_business_id=target_business_id,
		owner_user_id=owner_user_id,
		dry_run=dry_run,
		import_users=import_users,
		import_master_data=import_master_data,
		import_invoices=import_invoices,
		import_receipts_payments=import_receipts_payments,
		import_expense_income=import_expense_income,
		import_warehouses=import_warehouses,
		import_transfers=import_transfers,
		import_opening_balance=import_opening_balance,
		import_checks=import_checks,
		rewrite_confirmation=rewrite_confirmation,
		conflict_policy=conflict_policy,
	)

	jm = JobManager.instance()
	job_id = jm.create("ایمپورت دیتابیس قدیمی (MySQL)")

	def task():
		try:
			jm.start(job_id, "شروع ایمپورت")

			def on_progress(pct: int, message: str):
				jm.update(job_id, pct, message)

			with get_db_session() as db:
				service = LegacySqlImportService(db, on_progress=on_progress)
				result = service.run(sql_path, options)
			if result.ok:
				jm.succeed(job_id, {
					"dry_run": result.dry_run,
					"stats": result.stats,
					"mappings": result.mappings,
				})
			else:
				jm.fail(job_id, "; ".join(result.errors) or "ایمپورت ناموفق")
		except Exception as exc:
			jm.fail(job_id, str(exc))
		finally:
			_unlink_paths(cleanup_paths)

	background_tasks.add_task(task)
	return success_response(
		{"job_id": job_id, "dry_run": dry_run},
		request,
		message="LEGACY_SQL_IMPORT_STARTED",
	)
