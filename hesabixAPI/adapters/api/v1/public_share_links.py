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
from app.services.document_share_link_service import (
    resolve_public_payload_by_code as resolve_invoice_document_share_by_code,
)
from app.services.system_settings_service import get_share_link_settings


router = APIRouter(tags=["public-share-links"])


def _strip_trailing_public_segment(url: str) -> str:
	"""حذف پسوند /public از پایهٔ URL تا مسیر نهایی دوبل نشود (/public/public/...)."""
	u = (url or "").strip().rstrip("/")
	if u.lower().endswith("/public"):
		u = u[: -len("/public")].rstrip("/")
	return u


def _flutter_public_page_url(request: Request, settings_public_app: str, env_public_app: str, subpath: str) -> str:
	"""
	URL کامل صفحهٔ عمومی Flutter (مثلاً /public/invoice-link/{code}).

	اولویت با همان scheme+host درخواست است تا لینک کوتاه روی hsxn به arc نپرد
	(مگر اینکه واقعاً فقط روی دامنهٔ دیگری UI سرو شود — آن زمان باید nginx همان دامنه /public را داشته باشد
	یا لینک کوتاه روی دامنهٔ UI صادر شود).
	"""
	same_origin = f"{request.url.scheme}://{request.url.netloc}".rstrip("/")
	configured = _strip_trailing_public_segment(settings_public_app)
	env_base = _strip_trailing_public_segment(env_public_app)
	base = same_origin or configured or env_base
	base = base.rstrip("/")
	return f"{base}/public/{subpath.lstrip('/')}"


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
	request: Request,
	db: Session = Depends(get_db),
):
	settings = get_share_link_settings(db)
	configured = (settings.get("public_app_url") or "").strip()
	env_app = (get_settings().share_link_public_app_url or "").strip()
	target_url = _flutter_public_page_url(request, configured, env_app, f"person-link/{code}")
	return RedirectResponse(url=target_url, status_code=307)


@router.get(
	"/api/v1/public/invoice-links/{code}",
	summary="نمایش عمومی فاکتور از طریق کد لینک (بدون احراز هویت)",
)
async def get_public_invoice_document_link(
	code: str,
	request: Request,
	db: Session = Depends(get_db),
):
	try:
		payload = resolve_invoice_document_share_by_code(db, code)
	except ApiError as exc:
		raise HTTPException(status_code=exc.status_code, detail=exc.detail)
	return success_response(
		data=payload,
		request=request,
		message="اطلاعات فاکتور دریافت شد",
	)


@router.get(
	"/i/{code}",
	summary="انتقال به صفحهٔ عمومی فاکتور در Flutter",
)
async def redirect_public_invoice_link(
	code: str,
	request: Request,
	db: Session = Depends(get_db),
):
	settings = get_share_link_settings(db)
	configured = (settings.get("public_app_url") or "").strip()
	env_app = (get_settings().share_link_public_app_url or "").strip()
	target_url = _flutter_public_page_url(request, configured, env_app, f"invoice-link/{code}")
	return RedirectResponse(url=target_url, status_code=307)


from adapters.api.v1.public.crm_chat_public import router as _crm_chat_public_router  # noqa: E402

router.include_router(_crm_chat_public_router)

