from __future__ import annotations

import io
from decimal import Decimal
from typing import Any, Optional
from urllib.parse import quote

from fastapi import APIRouter, Body, Depends, Form, HTTPException, Request
from fastapi.responses import FileResponse, RedirectResponse, Response, StreamingResponse
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.payment_response import (
	pay_page_font_path,
	render_public_business_pay_page,
	resolve_payment_display_name,
)
from app.core.responses import ApiError, format_datetime_fields, success_response
from app.services.business_pay_page_service import get_public_pay_page, public_business_contact_rows
from app.services.file_storage_service import FileStorageService
from app.services.public_pay_page_abuse_service import submit_pay_page_abuse_report
from app.services.public_pay_page_payment_service import (
	business_logo_file_id_for_pay_page,
	get_public_pay_receipt,
	render_public_pay_receipt_pdf,
	start_public_pay_page_payment,
)

router = APIRouter(tags=["public-pay-page"])

_FONT_MEDIA_TYPES = {
	".woff2": "font/woff2",
	".ttf": "font/ttf",
}


@router.get("/api/v1/public/pay-fonts/{font_name}", include_in_schema=False)
def public_pay_page_font(font_name: str):
	path = pay_page_font_path(font_name)
	if path is None:
		raise HTTPException(status_code=404, detail="فونت یافت نشد")
	return FileResponse(
		path,
		media_type=_FONT_MEDIA_TYPES.get(path.suffix.lower(), "application/octet-stream"),
		headers={"Cache-Control": "public, max-age=31536000, immutable"},
	)


class PublicPayStartBody(BaseModel):
	amount: Decimal = Field(..., gt=0)
	name: Optional[str] = Field(default=None, max_length=30)
	mobile: Optional[str] = Field(default=None, max_length=20)
	note: Optional[str] = Field(default=None, max_length=1000)


def _api_error_text(exc: ApiError) -> str:
	return (getattr(exc, "message", None) or "خطا در پرداخت").strip() or "خطا در پرداخت"


def _canonical_username(payload: dict[str, Any], fallback: str) -> str:
	return str(payload.get("redirect_to") or payload.get("username") or fallback).strip()


def _pay_page_html_context(
	*,
	db: Session,
	request: Request,
	username: str,
	payload: dict[str, Any] | None,
	not_found: bool = False,
	error_message: str | None = None,
	form_amount: str = "",
	form_name: str = "",
	form_mobile: str = "",
	form_note: str = "",
	report_submitted: bool = False,
	report_open: bool = False,
	report_error: str = "",
	report_details: str = "",
	report_name: str = "",
	report_mobile: str = "",
) -> dict[str, Any]:
	app_name = resolve_payment_display_name(db)
	data = payload or {}
	page_proto, page_host, page_origin = _public_origin(request)
	expected_page_url = f"{page_origin}/u/{username}" if page_host else ""
	title = str(data.get("display_title") or data.get("business_name") or username or app_name)
	currency = str(
		data.get("currency_title") or data.get("currency_code") or data.get("currency_symbol") or ""
	).strip()
	min_amount = data.get("min_amount")
	try:
		min_fmt = f"{int(Decimal(str(min_amount))):,}" if min_amount is not None else "۵۰,۰۰۰"
	except Exception:
		min_fmt = "۵۰,۰۰۰"
	payment_status = (request.query_params.get("payment_status") or "").strip().lower()
	if payment_status not in ("success", "failed"):
		payment_status = ""
	show_logo = bool(data.get("show_logo")) and not not_found
	identity = {
		"business_name": data.get("business_name") or title if not not_found else None,
		"business_type": data.get("business_type"),
		"phone": data.get("phone"),
		"mobile": data.get("mobile"),
		"postal_code": data.get("postal_code"),
		"address": data.get("address"),
		"national_id": data.get("national_id"),
		"economic_id": data.get("economic_id"),
		"registration_number": data.get("registration_number"),
	}
	return {
		"app_name": app_name,
		"username": username,
		"page_title": title if not not_found else "صفحه پرداخت",
		"heading": f"پرداخت به {title}" if not not_found else "صفحه پرداخت",
		"display_title": title,
		"intro_text": (data.get("intro_text") or "") if not not_found else "",
		"show_logo": show_logo,
		"logo_url": f"/api/v1/public/pay/{quote(username, safe='')}/logo" if show_logo else "",
		"is_enabled": bool(data.get("is_enabled")),
		"not_found": not_found,
		"not_found_message": "این صفحه پرداخت یافت نشد",
		"disabled_message": "دریافت آنلاین فعلاً غیرفعال است",
		"error_message": error_message or "",
		"payment_status": payment_status,
		"receipt_title": "رسید پرداخت",
		"receipt_success": "پرداخت با موفقیت انجام شد",
		"receipt_failed": "پرداخت ناموفق بود یا توسط بانک تأیید نشد",
		"tracking_label": "شماره پیگیری",
		"receipt_ref": (request.query_params.get("ref") or "").strip(),
		"receipt_tx": (request.query_params.get("tx_id") or "").strip(),
		"amount_label": "مبلغ",
		"name_label": "نام (اختیاری)",
		"mobile_label": "موبایل (اختیاری)",
		"note_label": "توضیح کوتاه (اختیاری)",
		"pay_button": "پرداخت",
		"currency_hint": f"مبلغ به {currency} است" if currency else "",
		"min_amount_hint": f"حداقل {min_fmt}",
		"form_amount": form_amount,
		"form_name": form_name,
		"form_mobile": form_mobile,
		"form_note": form_note,
		"business_rows": public_business_contact_rows(identity) if not not_found else [],
		"expected_host": page_host,
		"expected_page_url": expected_page_url,
		"page_is_https": page_proto == "https",
		"report_submitted": report_submitted,
		"report_open": report_open,
		"report_error": report_error,
		"report_details": report_details,
		"report_name": report_name,
		"report_mobile": report_mobile,
	}


def _canonical_redirect(request: Request, canonical: str) -> RedirectResponse | None:
	current = (request.path_params.get("username") or "").strip()
	if not canonical or canonical == current:
		return None
	target = f"/u/{quote(canonical, safe='')}"
	qs = str(request.url.query or "").strip()
	if qs:
		target = f"{target}?{qs}"
	return RedirectResponse(url=target, status_code=302)


@router.get("/u/{username}", include_in_schema=False)
def public_pay_page_html(username: str, request: Request, db: Session = Depends(get_db)):
	try:
		payload = get_public_pay_page(db, username)
	except ApiError as exc:
		if getattr(exc, "status_code", 404) == 404:
			return render_public_business_pay_page(
				_pay_page_html_context(db=db, request=request, username=username, payload=None, not_found=True),
				status_code=404,
			)
		raise HTTPException(status_code=exc.status_code, detail=exc.detail) from exc
	canonical = _canonical_username(payload, username)
	redir = _canonical_redirect(request, canonical)
	if redir is not None:
		return redir
	return render_public_business_pay_page(
		_pay_page_html_context(db=db, request=request, username=canonical, payload=payload),
	)


@router.post("/u/{username}", include_in_schema=False)
def public_pay_page_html_submit(
	username: str,
	request: Request,
	db: Session = Depends(get_db),
	amount: str = Form(""),
	name: str = Form(""),
	mobile: str = Form(""),
	note: str = Form(""),
	confirm_business: str = Form(""),
):
	try:
		payload = get_public_pay_page(db, username)
	except ApiError as exc:
		if getattr(exc, "status_code", 404) == 404:
			return render_public_business_pay_page(
				_pay_page_html_context(db=db, request=request, username=username, payload=None, not_found=True),
				status_code=404,
			)
		raise HTTPException(status_code=exc.status_code, detail=exc.detail) from exc
	canonical = _canonical_username(payload, username)
	redir = _canonical_redirect(request, canonical)
	if redir is not None:
		return redir
	if confirm_business != "1":
		return render_public_business_pay_page(
			_pay_page_html_context(
				db=db,
				request=request,
				username=canonical,
				payload=payload,
				error_message="برای ادامه، تأیید کنید که کسب‌وکار را بررسی کرده‌اید.",
				form_amount=amount,
				form_name=name,
				form_mobile=mobile,
				form_note=note,
			),
			status_code=400,
		)
	if not payload.get("is_enabled"):
		return render_public_business_pay_page(
			_pay_page_html_context(
				db=db,
				request=request,
				username=canonical,
				payload=payload,
				error_message="دریافت آنلاین فعلاً غیرفعال است",
				form_amount=amount,
				form_name=name,
				form_mobile=mobile,
				form_note=note,
			),
			status_code=400,
		)
	try:
		data = start_public_pay_page_payment(
			db,
			username=canonical,
			amount=amount,
			payer_name=name or None,
			payer_mobile=mobile or None,
			payer_note=note or None,
		)
	except ApiError as exc:
		return render_public_business_pay_page(
			_pay_page_html_context(
				db=db,
				request=request,
				username=canonical,
				payload=payload,
				error_message=_api_error_text(exc),
				form_amount=amount,
				form_name=name,
				form_mobile=mobile,
				form_note=note,
			),
			status_code=exc.status_code if 400 <= int(exc.status_code) < 500 else 400,
		)
	payment_url = (data.get("payment_url") or "").strip()
	if not payment_url:
		return render_public_business_pay_page(
			_pay_page_html_context(
				db=db,
				request=request,
				username=canonical,
				payload=payload,
				error_message="خطا در ایجاد لینک پرداخت",
				form_amount=amount,
				form_name=name,
				form_mobile=mobile,
				form_note=note,
			),
			status_code=502,
		)
	return RedirectResponse(url=payment_url, status_code=303)


def _request_ip(request: Request) -> str | None:
	forwarded = (request.headers.get("x-forwarded-for") or "").split(",")[0].strip()
	if forwarded:
		return forwarded
	return request.client.host if request.client else None


def _request_base(request: Request) -> str:
	return _public_origin(request)[2]


def _public_origin(request: Request) -> tuple[str, str, str]:
	proto = (
		(request.headers.get("x-forwarded-proto") or request.url.scheme or "https")
		.split(",")[0]
		.strip()
		.lower()
	)
	if proto not in ("http", "https"):
		proto = "https"
	host = (
		request.headers.get("x-forwarded-host")
		or request.headers.get("host")
		or request.url.netloc
		or ""
	).split(",")[0].strip()
	return proto, host, f"{proto}://{host}".rstrip("/") if host else ""


@router.post("/u/{username}/report", include_in_schema=False)
def public_pay_page_report(
	username: str,
	request: Request,
	db: Session = Depends(get_db),
	reason: str = Form(""),
	details: str = Form(""),
	reporter_name: str = Form(""),
	reporter_mobile: str = Form(""),
):
	try:
		payload = get_public_pay_page(db, username)
	except ApiError as exc:
		if getattr(exc, "status_code", 404) == 404:
			return render_public_business_pay_page(
				_pay_page_html_context(db=db, request=request, username=username, payload=None, not_found=True),
				status_code=404,
			)
		raise HTTPException(status_code=exc.status_code, detail=exc.detail) from exc
	canonical = _canonical_username(payload, username)
	try:
		submit_pay_page_abuse_report(
			db,
			username=canonical,
			reason=reason,
			details=details,
			reporter_name=reporter_name or None,
			reporter_mobile=reporter_mobile or None,
			page_url=str(request.url.replace(path=f"/u/{canonical}")),
			ip_address=_request_ip(request),
			user_agent=(request.headers.get("user-agent") or "")[:400],
		)
	except ApiError as exc:
		return render_public_business_pay_page(
			_pay_page_html_context(
				db=db,
				request=request,
				username=canonical,
				payload=payload,
				report_error=_api_error_text(exc),
				report_open=True,
				report_details=details,
				report_name=reporter_name,
				report_mobile=reporter_mobile,
			),
			status_code=exc.status_code if 400 <= int(exc.status_code) < 500 else 400,
		)
	return render_public_business_pay_page(
		_pay_page_html_context(
			db=db,
			request=request,
			username=canonical,
			payload=payload,
			report_submitted=True,
		)
	)


def _receipt_html_context(db, request: Request, username: str, data: dict[str, Any]) -> dict[str, Any]:
	return {
		"app_name": resolve_payment_display_name(db),
		"username": username,
		"display_title": data.get("display_title") or data.get("business_name") or username,
		"show_logo": bool(data.get("show_logo")),
		"logo_url": f"/api/v1/public/pay/{quote(username, safe='')}/logo" if data.get("show_logo") else "",
		**data,
	}


@router.get("/u/{username}/r/{token}/pdf", include_in_schema=False)
def public_pay_receipt_pdf(username: str, token: str, request: Request, db: Session = Depends(get_db)):
	try:
		data = get_public_pay_receipt(db, username, token, request_base=_request_base(request))
	except ApiError as exc:
		raise HTTPException(status_code=exc.status_code, detail=exc.detail) from exc
	ctx = _receipt_html_context(db, request, data.get("username") or username, data)
	try:
		pdf = render_public_pay_receipt_pdf(ctx)
	except Exception as exc:
		raise HTTPException(status_code=502, detail="ساخت PDF رسید انجام نشد") from exc
	return Response(
		content=pdf,
		media_type="application/pdf",
		headers={"Content-Disposition": 'inline; filename="pay-receipt.pdf"'},
	)


@router.get("/u/{username}/r/{token}", include_in_schema=False)
def public_pay_receipt_html(username: str, token: str, request: Request, db: Session = Depends(get_db)):
	try:
		data = get_public_pay_receipt(db, username, token, request_base=_request_base(request))
	except ApiError as exc:
		if getattr(exc, "status_code", 404) == 404:
			return render_public_business_pay_page(
				_pay_page_html_context(db=db, request=request, username=username, payload=None, not_found=True),
				status_code=404,
			)
		raise HTTPException(status_code=exc.status_code, detail=exc.detail) from exc
	return render_public_business_pay_page(
		_receipt_html_context(db, request, data.get("username") or username, data),
		template_name="public/pay_receipt.html",
	)


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
