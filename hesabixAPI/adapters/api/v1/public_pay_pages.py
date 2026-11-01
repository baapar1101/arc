from __future__ import annotations

import io
from decimal import Decimal
from typing import Optional

from fastapi import APIRouter, Body, Depends, HTTPException, Request
from fastapi.responses import RedirectResponse, StreamingResponse
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.responses import ApiError, format_datetime_fields, success_response
from app.services.business_pay_page_service import get_public_pay_page
from app.services.file_storage_service import FileStorageService
from app.services.public_pay_page_payment_service import (
	business_logo_file_id_for_pay_page,
	start_public_pay_page_payment,
)
from app.services.system_settings_service import resolve_public_app_base_url_for_public_links

router = APIRouter(tags=["public-pay-page"])


class PublicPayStartBody(BaseModel):
	amount: Decimal = Field(..., gt=0)
	name: Optional[str] = Field(default=None, max_length=30)
	mobile: Optional[str] = Field(default=None, max_length=20)
	note: Optional[str] = Field(default=None, max_length=1000)


@router.get("/u/{username}", include_in_schema=False)
def short_pay_page_redirect(username: str, request: Request, db: Session = Depends(get_db)):
	try:
		payload = get_public_pay_page(db, username)
	except ApiError as exc:
		raise HTTPException(status_code=exc.status_code, detail=exc.detail) from exc
	canonical = payload.get("redirect_to") or payload.get("username") or username
	base = (resolve_public_app_base_url_for_public_links(db) or "").strip().rstrip("/")
	if not base:
		same_origin = f"{request.url.scheme}://{request.url.netloc}".rstrip("/")
		base = same_origin
	return RedirectResponse(url=f"{base}/public/pay/{canonical}", status_code=307)


@router.get(
	"/api/v1/public/pay/{username}",
	summary="مشخصات عمومی صفحه واریز کسب‌وکار",
)
def public_pay_page_get(
	username: str,
	request: Request,
	db: Session = Depends(get_db),
):
	try:
		payload = get_public_pay_page(db, username)
	except ApiError as exc:
		raise HTTPException(status_code=exc.status_code, detail=exc.detail) from exc
	return success_response(format_datetime_fields(payload, request), request)


@router.get(
	"/api/v1/public/pay/{username}/logo",
	summary="لوگوی کسب‌وکار برای صفحه واریز عمومی",
)
async def public_pay_page_logo(username: str, db: Session = Depends(get_db)):
	file_uuid = business_logo_file_id_for_pay_page(db, username)
	if not file_uuid:
		raise HTTPException(status_code=404, detail="لوگو یافت نشد")
	storage = FileStorageService(db)
	try:
		file_data = await storage.download_file(file_uuid)
	except Exception:
		raise HTTPException(status_code=404, detail="لوگو یافت نشد")
	content = file_data.get("content") or b""
	if not content:
		raise HTTPException(status_code=404, detail="لوگو یافت نشد")
	filename = file_data.get("filename") or "logo"
	return StreamingResponse(
		io.BytesIO(content),
		media_type=file_data.get("mime_type") or "image/png",
		headers={"Content-Disposition": f'inline; filename="{filename}"'},
	)


@router.post(
	"/api/v1/public/pay/{username}/start",
	summary="شروع پرداخت از لینک واریز عمومی",
)
def public_pay_page_start(
	username: str,
	request: Request,
	payload: PublicPayStartBody = Body(...),
	db: Session = Depends(get_db),
):
	try:
		data = start_public_pay_page_payment(
			db,
			username=username,
			amount=payload.amount,
			payer_name=payload.name,
			payer_mobile=payload.mobile,
			payer_note=payload.note,
		)
	except ApiError as exc:
		raise HTTPException(status_code=exc.status_code, detail=exc.detail) from exc
	return success_response(data, request)
