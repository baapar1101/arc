from __future__ import annotations

import logging
from datetime import datetime, timezone
from typing import Any

from fastapi import APIRouter, BackgroundTasks, Depends, Request
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from adapters.db.models.business_ftp_backup_setting import BusinessFtpBackupSetting
from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.permissions import require_business_permission_dep
from app.core.responses import success_response, ApiError
from app.services.business_ftp_access import user_can_manage_ftp_backup
from app.services.business_ftp_service import (
	FtpConnectionParams,
	load_decrypted_params,
	row_to_public_dict,
	scan_usage,
	test_connection,
	upload_bytes,
)
from app.services.encryption_service import get_encryption_service
from app.services.job_manager import JobManager

logger = logging.getLogger(__name__)

router = APIRouter(
	prefix="/businesses/{business_id}/ftp-backup",
	tags=["FTP بکاپ"],
	dependencies=[Depends(require_business_permission_dep("settings", "manage_ftp"))],
)


class FtpBackupSettingsSave(BaseModel):
	host: str = Field(..., min_length=1, max_length=255)
	port: int = Field(default=21, ge=1, le=65535)
	username: str = Field(..., min_length=1, max_length=255)
	password: str | None = Field(default=None, description="خالی یعنی حفظ رمز قبلی")
	remote_path: str = Field(default="/", max_length=1024)
	passive: bool = True
	use_ftps: bool = False


class FtpConnectionTestRequest(BaseModel):
	use_saved: bool = Field(default=False, description="تست با تنظیمات ذخیره‌شده")
	host: str | None = Field(default=None, max_length=255)
	port: int = Field(default=21, ge=1, le=65535)
	username: str | None = Field(default=None, max_length=255)
	password: str | None = Field(default=None, description="برای تست بدون ذخیره")
	remote_path: str = Field(default="/", max_length=1024)
	passive: bool = True
	use_ftps: bool = False


def _params_from_saved(db: Session, business_id: int) -> FtpConnectionParams:
	p = load_decrypted_params(db, business_id)
	if not p:
		raise ApiError("FTP_NOT_CONFIGURED", "تنظیمات FTP ذخیره نشده یا رمز نامعتبر است", http_status=400)
	return p


def _params_from_test_request(db: Session, business_id: int, body: FtpConnectionTestRequest) -> FtpConnectionParams:
	if body.use_saved:
		return _params_from_saved(db, business_id)
	if not body.host or not body.username or not body.password:
		raise ApiError("FTP_TEST_INVALID", "برای تست بدون ذخیره، میزبان، نام کاربری و رمز لازم است", http_status=400)
	return FtpConnectionParams(
		host=body.host.strip(),
		port=body.port,
		username=body.username.strip(),
		password=body.password,
		remote_path=body.remote_path or "/",
		passive=body.passive,
		use_ftps=body.use_ftps,
	)


def _ftp_test_background(job_id: str, business_id: int, body_dict: dict[str, Any]) -> None:
	jm = JobManager.instance()
	from adapters.db.session import get_db_session

	try:
		jm.start(job_id, "FTP test starting")
		jm.update(job_id, 20, "Connecting to FTP")
		body = FtpConnectionTestRequest.model_validate(body_dict)
		with get_db_session() as db:
			params = _params_from_test_request(db, business_id, body)
		jm.update(job_id, 60, "Running FTP checks")
		result = test_connection(params)
		jm.succeed(job_id, result, "FTP test completed")
	except Exception as e:
		logger.exception("FTP test job failed")
		jm.fail(job_id, str(e), "FTP test failed")


def _ftp_usage_background(job_id: str, business_id: int) -> None:
	jm = JobManager.instance()
	from adapters.db.session import get_db_session

	try:
		jm.start(job_id, "Scanning FTP usage")
		jm.update(job_id, 15, "Connecting to FTP")
		with get_db_session() as db:
			params = _params_from_saved(db, business_id)
		jm.update(job_id, 40, "Scanning remote folders")
		result = scan_usage(params)
		result["scanned_at"] = datetime.now(timezone.utc).isoformat()
		jm.succeed(job_id, result, "FTP usage scan completed")
	except Exception as e:
		logger.exception("FTP usage job failed")
		jm.fail(job_id, str(e), "FTP usage scan failed")


@router.get("/settings")
async def get_ftp_settings(
	request: Request,
	business_id: int,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
):
	_ = ctx
	row = db.query(BusinessFtpBackupSetting).filter(BusinessFtpBackupSetting.business_id == business_id).first()
	return success_response(row_to_public_dict(row), request=request)


@router.put("/settings")
async def save_ftp_settings(
	request: Request,
	business_id: int,
	body: FtpBackupSettingsSave,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
):
	_ = ctx
	row = db.query(BusinessFtpBackupSetting).filter(BusinessFtpBackupSetting.business_id == business_id).first()
	enc = get_encryption_service()
	password_encrypted: str | None
	if body.password and body.password.strip():
		password_encrypted = enc.encrypt(body.password.strip())
	elif row and row.password_encrypted:
		password_encrypted = row.password_encrypted
	else:
		raise ApiError("FTP_PASSWORD_REQUIRED", "برای اولین ذخیره، رمز عبور FTP لازم است", http_status=400)

	if row is None:
		row = BusinessFtpBackupSetting(
			business_id=business_id,
			host=body.host.strip(),
			port=body.port,
			username=body.username.strip(),
			password_encrypted=password_encrypted,
			remote_path=body.remote_path.strip() or "/",
			passive=body.passive,
			use_ftps=body.use_ftps,
		)
		db.add(row)
	else:
		row.host = body.host.strip()
		row.port = body.port
		row.username = body.username.strip()
		row.password_encrypted = password_encrypted
		row.remote_path = body.remote_path.strip() or "/"
		row.passive = body.passive
		row.use_ftps = body.use_ftps
	db.commit()
	db.refresh(row)
	return success_response(row_to_public_dict(row), request=request, message="FTP settings saved")


@router.delete("/settings")
async def delete_ftp_settings(
	request: Request,
	business_id: int,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
):
	_ = ctx
	row = db.query(BusinessFtpBackupSetting).filter(BusinessFtpBackupSetting.business_id == business_id).first()
	if row:
		db.delete(row)
		db.commit()
	return success_response({"deleted": True}, request=request)


@router.post("/test")
async def start_ftp_test_job(
	request: Request,
	business_id: int,
	background: BackgroundTasks,
	body: FtpConnectionTestRequest,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
):
	_ = ctx
	if body.use_saved:
		_params_from_saved(db, business_id)
	jm = JobManager.instance()
	job_id = jm.create("FTP test queued")
	background.add_task(_ftp_test_background, job_id, business_id, body.model_dump())
	return success_response({"job_id": job_id}, request=request, message="FTP test started")


@router.post("/usage-scan")
async def start_ftp_usage_job(
	request: Request,
	business_id: int,
	background: BackgroundTasks,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
):
	_ = ctx
	_params_from_saved(db, business_id)
	jm = JobManager.instance()
	job_id = jm.create("FTP usage scan queued")
	background.add_task(_ftp_usage_background, job_id, business_id)
	return success_response({"job_id": job_id}, request=request, message="FTP usage scan started")


def upload_saved_backup_to_ftp(db: Session, business_id: int, filename: str, data: bytes) -> dict[str, Any] | None:
	"""اگر تنظیمات FTP ذخیره شده باشد، آپلود می‌کند. در غیر این صورت None."""
	params = load_decrypted_params(db, business_id)
	if not params:
		return None
	return upload_bytes(params, filename, data)


def assert_can_use_ftp_on_backup(db: Session, ctx: AuthContext, business_id: int) -> None:
	if not user_can_manage_ftp_backup(db, ctx, business_id):
		raise ApiError("FORBIDDEN", "دسترسی ارسال بکاپ به FTP را ندارید", http_status=403)
