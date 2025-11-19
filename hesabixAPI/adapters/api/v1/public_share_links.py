from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import RedirectResponse
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.responses import ApiError, success_response
from app.core.settings import get_settings
from app.services.person_share_link_service import (
    get_share_link_by_code,
    get_public_invoice_details,
    resolve_public_payload_by_code,
)
from app.services.system_settings_service import get_share_link_settings


router = APIRouter(tags=["public-share-links"])


@router.get(
	"/api/v1/public/person-links/{code}",
	summary="دریافت اطلاعات عمومی کارت حساب بدون احراز هویت",
)
async def get_public_person_link(
	code: str,
	request: Request,
	db: Session = Depends(get_db),
):
	try:
		payload = resolve_public_payload_by_code(db, code)
	except ApiError as exc:
		raise HTTPException(status_code=exc.status_code, detail=exc.detail)
	return success_response(
		data=payload,
		request=request,
		message="اطلاعات کارت حساب دریافت شد",
	)


@router.get(
	"/api/v1/public/person-links/{code}/invoices/{document_id}",
	summary="دریافت جزئیات فاکتور از طریق لینک اشتراک",
)
async def get_public_invoice_details_endpoint(
	code: str,
	document_id: int,
	request: Request,
	db: Session = Depends(get_db),
):
	try:
		details = get_public_invoice_details(db, code, document_id)
	except ApiError as exc:
		raise HTTPException(status_code=exc.status_code, detail=exc.detail)
	return success_response(
		data=details,
		request=request,
		message="جزئیات فاکتور دریافت شد",
	)


@router.get(
	"/p/{code}",
	summary="انتقال به صفحه عمومی Flutter",
)
async def redirect_public_person_link(
	code: str,
	db: Session = Depends(get_db),
):
	settings = get_share_link_settings(db)
	configured_base = (settings.get("public_app_url") or "").strip()
	default_base = (get_settings().share_link_public_app_url or "").strip()
	if default_base.lower().endswith("/public"):
		default_base = default_base[:-len("/public")].rstrip("/")
	base_url = configured_base or default_base
	target_base = (base_url.rstrip("/") or "/public") + "/public"
	target_url = f"{target_base}/person-link/{code}"
	return RedirectResponse(url=target_url, status_code=307)

