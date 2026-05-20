"""API عمومی کاتالوگ کالا (شبکهٔ انتشار) — بدون احراز هویت Hesabix."""

from __future__ import annotations

import io
from typing import Optional

from fastapi import APIRouter, Body, Depends, HTTPException, Query, Request, status
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field, field_validator
from sqlalchemy.orm import Session

from adapters.db.models.file_storage import FileStorage
from adapters.db.session import get_db
from app.core.rate_limiter import get_client_ip, get_rate_limiter
from app.core.responses import ApiError, success_response
from app.services.captcha_service import validate_captcha
from app.services.file_storage_service import FileStorageService
from app.services.public_catalog_service import (
	create_public_catalog_contact_message,
	get_public_product_by_uuid,
	list_public_catalog_feed,
	resolve_public_catalog_product_image,
	search_public_catalog,
)
from app.services.public_catalog_utils import normalize_catalog_public_uuid

router = APIRouter(tags=["public-product-catalog"])


def _public_http_error(status: int, code: str, message: str) -> HTTPException:
	return HTTPException(
		status_code=status,
		detail={"success": False, "error": {"code": code, "message": message}},
	)


def _http_from_api_error(exc: ApiError) -> HTTPException:
	return HTTPException(status_code=exc.status_code, detail=exc.detail)


def _rate_or_raise(request: Request, *, bucket: str, max_requests: int, window_seconds: int) -> None:
	ip = get_client_ip(request) or "unknown"
	key = f"public_catalog:{bucket}:{ip}"
	limiter = get_rate_limiter()
	allowed, remaining, reset_after = limiter.check_rate_limit(key, max_requests, window_seconds)
	if not allowed:
		raise HTTPException(
			status_code=status.HTTP_429_TOO_MANY_REQUESTS,
			detail={
				"success": False,
				"error": {
					"code": "RATE_LIMIT_EXCEEDED",
					"message": "تعداد درخواست‌ها بیش از حد مجاز است؛ لطفاً بعداً تلاش کنید.",
				},
			},
			headers={
				"Retry-After": str(max(1, reset_after)),
				"X-RateLimit-Remaining": str(remaining),
			},
		)


class PublicCatalogContactBody(BaseModel):
	business_id: int = Field(..., gt=0)
	product_catalog_uuid: Optional[str] = Field(None, max_length=36)
	sender_name: str = Field(..., min_length=1, max_length=200)
	sender_contact: str = Field(..., min_length=3, max_length=200)
	message: str = Field(..., min_length=1, max_length=2000)
	captcha_id: str = Field(..., min_length=8, max_length=64)
	captcha_code: str = Field(..., min_length=3, max_length=16)

	@field_validator("product_catalog_uuid")
	@classmethod
	def _norm_uuid(cls, v: Optional[str]) -> Optional[str]:
		if v is None:
			return None
		s = str(v).strip()
		return s or None


@router.get("/api/v1/public/catalog/products")
async def public_catalog_list_products(
	request: Request,
	db: Session = Depends(get_db),
	search: Optional[str] = Query(None, max_length=500),
	business_id: Optional[int] = Query(None),
	category_id: Optional[int] = Query(None),
	province: Optional[str] = Query(None, max_length=100),
	city: Optional[str] = Query(None, max_length=100),
	skip: int = Query(0, ge=0, le=500000),
	take: int = Query(20, ge=1, le=100),
):
	_rate_or_raise(request, bucket="list", max_requests=120, window_seconds=60)
	data = search_public_catalog(
		db,
		search=search,
		business_id=business_id,
		category_id=category_id,
		province=province,
		city=city,
		skip=skip,
		take=take,
	)
	return success_response(data, request)


@router.get("/api/v1/public/catalog/products/{catalog_public_uuid}")
async def public_catalog_get_product(
	request: Request,
	catalog_public_uuid: str,
	db: Session = Depends(get_db),
):
	_rate_or_raise(request, bucket="detail", max_requests=90, window_seconds=60)
	try:
		normalize_catalog_public_uuid(catalog_public_uuid)
	except ValueError:
		raise _public_http_error(
			status.HTTP_422_UNPROCESSABLE_ENTITY,
			"INVALID_CATALOG_UUID",
			"شناسهٔ عمومی کالا نامعتبر است.",
		) from None
	item = get_public_product_by_uuid(db, catalog_public_uuid)
	if not item:
		raise _public_http_error(status.HTTP_404_NOT_FOUND, "NOT_FOUND", "کالا یافت نشد")
	return success_response({"item": item}, request)


@router.get("/api/v1/public/catalog/products/{catalog_public_uuid}/image")
async def public_catalog_get_product_image(
	request: Request,
	catalog_public_uuid: str,
	db: Session = Depends(get_db),
	size: str = Query("original", description="original | small | medium"),
):
	_rate_or_raise(request, bucket="image", max_requests=200, window_seconds=60)
	try:
		normalize_catalog_public_uuid(catalog_public_uuid)
	except ValueError:
		raise _public_http_error(
			status.HTTP_422_UNPROCESSABLE_ENTITY,
			"INVALID_CATALOG_UUID",
			"شناسهٔ عمومی کالا نامعتبر است.",
		) from None
	p, file_id = resolve_public_catalog_product_image(db, catalog_public_uuid)
	if not p or not file_id:
		raise _public_http_error(status.HTTP_404_NOT_FOUND, "NOT_FOUND", "تصویر در دسترس نیست")

	fs = (
		db.query(FileStorage)
		.filter(
			FileStorage.id == str(file_id),
			FileStorage.business_id == int(p.business_id),
			FileStorage.deleted_at.is_(None),
		)
		.first()
	)
	if not fs:
		raise _public_http_error(status.HTTP_404_NOT_FOUND, "NOT_FOUND", "تصویر در دسترس نیست")

	storage = FileStorageService(db)
	from uuid import UUID

	try:
		fid = UUID(str(file_id))
	except Exception:
		raise _public_http_error(status.HTTP_404_NOT_FOUND, "NOT_FOUND", "تصویر در دسترس نیست") from None

	size_l = (size or "original").strip().lower()
	if size_l in ("small", "thumb", "thumbnail"):
		file_data = await storage.download_image_thumbnail(fid, size="small")
	elif size_l == "medium":
		file_data = await storage.download_image_thumbnail(fid, size="medium")
	else:
		file_data = await storage.download_file(fid)

	filename = file_data.get("filename") or "image"
	mime = file_data.get("mime_type") or "application/octet-stream"
	content = file_data.get("content") or b""
	disp = "inline" if str(mime).lower().startswith("image/") else "attachment"
	return StreamingResponse(
		io.BytesIO(content),
		media_type=mime,
		headers={"Content-Disposition": f'{disp}; filename="{filename}"'},
	)


@router.get("/api/v1/public/catalog/feed.json")
async def public_catalog_feed_json(
	request: Request,
	db: Session = Depends(get_db),
	skip: int = Query(0, ge=0, le=500000),
	take: int = Query(50, ge=1, le=200),
):
	_rate_or_raise(request, bucket="feed", max_requests=60, window_seconds=60)
	data = list_public_catalog_feed(db, take=take, skip=skip)
	return success_response(data, request)


@router.post("/api/v1/public/catalog/contact-messages")
async def public_catalog_post_contact(
	request: Request,
	db: Session = Depends(get_db),
	body: PublicCatalogContactBody = Body(...),
):
	_rate_or_raise(request, bucket="contact", max_requests=10, window_seconds=3600)
	if not validate_captcha(db, body.captcha_id, body.captcha_code, client_ip=get_client_ip(request)):
		raise _public_http_error(
			status.HTTP_400_BAD_REQUEST,
			"INVALID_CAPTCHA",
			"کد امنیتی نادرست یا منقضی است.",
		)
	try:
		create_public_catalog_contact_message(
			db,
			business_id=body.business_id,
			product_catalog_uuid=body.product_catalog_uuid,
			sender_name=body.sender_name,
			sender_contact=body.sender_contact,
			message=body.message,
			client_ip=get_client_ip(request),
		)
	except ApiError as exc:
		raise _http_from_api_error(exc) from exc
	return success_response({"saved": True}, request)
