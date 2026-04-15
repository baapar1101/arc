"""دسترسی عمومی به فایل از طریق لینک اشتراک (بدون ApiKey)."""

from __future__ import annotations

import io
from typing import Optional
from uuid import UUID

from fastapi import APIRouter, Body, Depends, HTTPException, Query, Request
from fastapi.responses import FileResponse, RedirectResponse, StreamingResponse
from sqlalchemy.orm import Session

from adapters.db.models.file_storage import FileStorage
from adapters.db.session import get_db
from app.core.responses import ApiError, success_response
from app.services.file_storage_service import FileStorageService
from app.services.system_settings_service import resolve_public_app_base_url_for_public_links
from app.services.file_storage_share_service import (
	assert_share_usable,
	get_share_by_public_token,
	touch_share_access,
	unlock_share,
)
from app.services.storage_share_access_token import verify_storage_share_access_token


router = APIRouter(tags=["public-storage-file-shares"])


def _http_from_api_error(exc: ApiError) -> HTTPException:
	return HTTPException(status_code=exc.status_code, detail=exc.detail)


def _content_disposition_type(mime: str) -> str:
	m = (mime or "").lower()
	if m.startswith("image/") or m.startswith("video/") or m == "application/pdf":
		return "inline"
	return "attachment"


def _access_from_request(request: Request, access_token: Optional[str]) -> Optional[str]:
	if access_token:
		return access_token
	auth = request.headers.get("authorization") or request.headers.get("Authorization")
	if auth and auth.lower().startswith("bearer "):
		return auth[7:].strip()
	return None


@router.get(
	"/api/v1/public/storage/shares/{token}/info",
	summary="اطلاعات فایل اشتراکی (بدون احراز هویت)",
)
async def public_storage_share_info(
	token: str,
	request: Request,
	db: Session = Depends(get_db),
):
	try:
		share = get_share_by_public_token(db, token)
		if not share:
			raise ApiError("NOT_FOUND", "لینک نامعتبر است", http_status=404)
		assert_share_usable(share)
		f = db.query(FileStorage).filter(FileStorage.id == share.file_storage_id).first()
		if not f or f.deleted_at is not None:
			raise ApiError("FILE_NOT_FOUND", "فایل دیگر در دسترس نیست", http_status=404)
		return success_response(
			{
				"original_name": f.original_name,
				"mime_type": f.mime_type,
				"file_size": f.file_size,
				"requires_password": bool(share.password_hash),
			},
			request,
		)
	except ApiError as exc:
		raise _http_from_api_error(exc) from exc


@router.post(
	"/api/v1/public/storage/shares/{token}/unlock",
	summary="باز کردن لینک دارای رمز",
)
async def public_storage_share_unlock(
	token: str,
	request: Request,
	db: Session = Depends(get_db),
	payload: dict = Body(...),
):
	try:
		password = payload.get("password")
		if password is not None and not isinstance(password, str):
			password = str(password)
		data = unlock_share(db, token, password)
		return success_response(data, request)
	except ApiError as exc:
		raise _http_from_api_error(exc) from exc


@router.get(
	"/api/v1/public/storage/shares/{token}/file",
	summary="دانلود یا نمایش فایل اشتراکی",
)
async def public_storage_share_file(
	token: str,
	request: Request,
	db: Session = Depends(get_db),
	access_token: Optional[str] = Query(None, description="توکن کوتاه‌عمر پس از unlock (برای لینک‌های رمزدار)"),
):
	try:
		share = get_share_by_public_token(db, token)
		if not share:
			raise ApiError("NOT_FOUND", "لینک نامعتبر است", http_status=404)
		assert_share_usable(share)
		f = db.query(FileStorage).filter(FileStorage.id == share.file_storage_id).first()
		if not f or f.deleted_at is not None:
			raise ApiError("FILE_NOT_FOUND", "فایل دیگر در دسترس نیست", http_status=404)

		access_raw = _access_from_request(request, access_token)
		if share.password_hash:
			if not access_raw:
				raise ApiError("PASSWORD_REQUIRED", "برای دسترسی به این فایل رمز لازم است", http_status=401)
			claims = verify_storage_share_access_token(access_raw)
			if not claims or claims.get("share_id") != share.id:
				raise ApiError("INVALID_ACCESS_TOKEN", "توکن دسترسی نامعتبر یا منقضی است", http_status=401)
		else:
			if access_raw:
				claims = verify_storage_share_access_token(access_raw)
				if claims and claims.get("share_id") == share.id:
					pass

		touch_share_access(db, share)

		storage = FileStorageService(db)
		local_path = await storage.resolve_local_disk_path_for_file(UUID(str(f.id)))
		disp = _content_disposition_type(f.mime_type or "")
		filename = f.original_name or "file"

		if local_path:
			return FileResponse(
				local_path,
				media_type=f.mime_type or "application/octet-stream",
				filename=filename,
				content_disposition_type=disp,
			)

		file_data = await storage.download_file(UUID(str(f.id)))
		return StreamingResponse(
			io.BytesIO(file_data["content"]),
			media_type=file_data.get("mime_type") or "application/octet-stream",
			headers={
				"Content-Disposition": f'{disp}; filename="{filename}"',
			},
		)
	except ApiError as exc:
		raise _http_from_api_error(exc) from exc


@router.get(
	"/api/v1/public/storage/s/{token}",
	summary="هدایت به صفحهٔ وب اشتراک فایل",
)
async def redirect_public_storage_share(
	token: str,
	request: Request,
	db: Session = Depends(get_db),
):
	configured = resolve_public_app_base_url_for_public_links(db).strip().rstrip("/")
	same_origin = f"{request.url.scheme}://{request.url.netloc}".rstrip("/")
	base = configured or same_origin
	target = f"{base.rstrip('/')}/public/storage-file/{token}"
	return RedirectResponse(url=target, status_code=307)
