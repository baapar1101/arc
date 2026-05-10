import base64
import io
import re
from datetime import datetime
from typing import Optional
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import RedirectResponse
from fastapi.responses import Response, StreamingResponse
from sqlalchemy.orm import Session

from adapters.db.models.person import Person
from adapters.db.session import get_db
from app.core.responses import ApiError, success_response
from app.core.settings import get_settings
from app.core.calendar import CalendarConverter
from app.services.pdf.template_renderer import render_template
from app.services.person_share_link_service import (
    get_public_invoice_details,
    resolve_public_payload_by_code,
)
from app.services.document_share_link_service import (
    resolve_public_payload_by_code as resolve_invoice_document_share_by_code,
)
from app.services.file_storage_service import FileStorageService
from app.services.share_link_logo_service import (
	business_logo_file_id_for_invoice_share,
	business_logo_file_id_for_person_share,
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
	"/api/v1/public/person-links/{code}/business-logo",
	summary="لوگوی کسب‌وکار برای لینک اشتراک کارت حساب (بدون شمارش بازدید)",
)
async def get_public_person_share_business_logo(
	code: str,
	db: Session = Depends(get_db),
):
	file_uuid = business_logo_file_id_for_person_share(db, code)
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
	"/api/v1/public/invoice-links/{code}/business-logo",
	summary="لوگوی کسب‌وکار برای لینک اشتراک فاکتور (بدون شمارش بازدید)",
)
async def get_public_invoice_share_business_logo(
	code: str,
	db: Session = Depends(get_db),
):
	file_uuid = business_logo_file_id_for_invoice_share(db, code)
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


@router.get(
	"/api/v1/public/invoice-links/{code}/pdf",
	summary="خروجی PDF عمومی فاکتور از طریق کد لینک (بدون احراز هویت)",
)
async def get_public_invoice_document_pdf(
	code: str,
	request: Request,
	db: Session = Depends(get_db),
):
	try:
		payload = resolve_invoice_document_share_by_code(db, code)
	except ApiError as exc:
		raise HTTPException(status_code=exc.status_code, detail=exc.detail)

	invoice = (payload or {}).get("invoice") or {}
	business = (payload or {}).get("business") or {}
	installments = (payload or {}).get("installments") or {}
	lines = invoice.get("product_lines") or []
	extra = invoice.get("extra_info") or {}
	totals = extra.get("totals") if isinstance(extra, dict) else {}
	totals = totals if isinstance(totals, dict) else {}

	def _num(v) -> float:
		try:
			return float(v or 0)
		except Exception:
			return 0.0

	def _line_unit_display(row: dict) -> str:
		unit = str(row.get("product_main_unit") or "").strip()
		if unit:
			return unit
		return "-"

	is_fa = str(request.headers.get("Accept-Language") or "").lower().startswith("fa")
	calendar_header = (request.headers.get("X-Calendar-Type") or "").strip().lower()
	calendar_type = calendar_header if calendar_header in {"jalali", "gregorian"} else ("jalali" if is_fa else "gregorian")

	def _fmt_date(raw_value):
		if raw_value is None:
			return "-"
		try:
			dt = datetime.fromisoformat(str(raw_value).replace("Z", "+00:00"))
			fd = CalendarConverter.format_datetime(dt, calendar_type)
			return fd.get("date_only") or fd.get("formatted") or str(raw_value)
		except Exception:
			return str(raw_value)

	def _status_label(v: str) -> str:
		status = str(v or "").strip().lower()
		if is_fa:
			return {
				"paid": "پرداخت‌شده",
				"partial": "پرداخت ناقص",
				"overdue": "سررسید گذشته",
				"pending": "در انتظار",
			}.get(status, status or "در انتظار")
		return {
			"paid": "Paid",
			"partial": "Partial",
			"overdue": "Overdue",
			"pending": "Pending",
		}.get(status, status or "Pending")

	def _invoice_type_label(doc_type: str) -> str:
		key = str(doc_type or "").strip().lower()
		if is_fa:
			return {
				"invoice_sales": "فروش",
				"invoice_sales_return": "برگشت از فروش",
				"invoice_purchase": "خرید",
				"invoice_purchase_return": "برگشت از خرید",
				"invoice_direct_consumption": "مصرف مستقیم",
				"invoice_production": "تولید",
				"invoice_waste": "ضایعات",
			}.get(key, doc_type or "-")
		return {
			"invoice_sales": "Sales",
			"invoice_sales_return": "Sales Return",
			"invoice_purchase": "Purchase",
			"invoice_purchase_return": "Purchase Return",
			"invoice_direct_consumption": "Direct Consumption",
			"invoice_production": "Production",
			"invoice_waste": "Waste",
		}.get(key, doc_type or "-")

	def _normalize_line(row: dict) -> dict:
		q = _num(row.get("quantity"))
		return {
			"product_code": row.get("product_code"),
			"product_name": row.get("product_name"),
			"description": row.get("description"),
			"quantity": q,
			"quantity_display": str(int(q)) if float(q).is_integer() else f"{q:.3f}".rstrip("0").rstrip("."),
			"unit_display": _line_unit_display(row),
			"unit_price": _num(row.get("unit_price")),
			"discount": _num(row.get("line_discount")),
			"tax_amount": _num(row.get("tax_amount")),
			"line_total": _num(row.get("line_total")),
			"attributes_display": "",
		}

	normalized_lines = [_normalize_line(row) for row in lines if isinstance(row, dict)]
	has_line_discount = any((_num(x.get("discount")) != 0) for x in normalized_lines)
	has_line_tax = any((_num(x.get("tax_amount")) != 0) for x in normalized_lines)

	person_info = {}
	try:
		person_id = (extra or {}).get("person_id")
		if person_id is not None:
			person = (
				db.query(Person)
				.filter(
					Person.id == int(person_id),
					Person.business_id == int(invoice.get("business_id") or business.get("id") or 0),
				)
				.first()
			)
			if person is not None:
				display_name = None
				try:
					first = (getattr(person, "first_name", None) or "").strip()
					last = (getattr(person, "last_name", None) or "").strip()
					full_name = f"{first} {last}".strip()
					display_name = (
						full_name
						or getattr(person, "company_name", None)
						or getattr(person, "alias_name", None)
						or "-"
					)
				except Exception:
					display_name = getattr(person, "alias_name", None) or "-"
				le_type = getattr(person, "legal_entity_type", None) or "natural"
				person_info = {
					"id": getattr(person, "id", None),
					"name": display_name,
					"name_prefix": getattr(person, "name_prefix", None),
					"legal_entity_type": le_type,
					"legal_entity_type_label": "حقوقی" if le_type == "legal" else "حقیقی",
					"national_id": getattr(person, "national_id", None),
					"registration_number": getattr(person, "registration_number", None),
					"economic_id": getattr(person, "economic_id", None),
					"address": getattr(person, "address", None),
					"postal_code": getattr(person, "postal_code", None),
					"mobile": getattr(person, "mobile", None),
					"phone": getattr(person, "phone", None),
				}
	except Exception:
		person_info = {}

	doc_type = str(invoice.get("document_type") or "")
	if doc_type in ("invoice_purchase", "invoice_purchase_return"):
		seller_info = person_info or {
			"name": business.get("name"),
			"address": business.get("address"),
			"phone": business.get("phone"),
			"mobile": business.get("mobile"),
		}
		buyer_info = {
			"name": business.get("name"),
			"address": business.get("address"),
			"phone": business.get("phone"),
			"mobile": business.get("mobile"),
		}
	else:
		seller_info = {
			"name": business.get("name"),
			"address": business.get("address"),
			"phone": business.get("phone"),
			"mobile": business.get("mobile"),
		}
		buyer_info = person_info

	invoice_view = dict(invoice)
	invoice_view["title"] = "فاکتور" if is_fa else "Invoice"
	invoice_view["issue_date"] = _fmt_date(invoice.get("document_date"))
	invoice_view["invoice_type_name"] = _invoice_type_label(str(invoice.get("document_type") or ""))
	invoice_view["subtotal"] = _num(totals.get("gross"))
	invoice_view["discount_total"] = _num(totals.get("discount"))
	invoice_view["tax_total"] = _num(totals.get("tax"))
	invoice_view["payable_total"] = _num(totals.get("net"))
	invoice_view["amount_before_discount_and_tax"] = _num(totals.get("gross"))
	invoice_view["amount_without_tax"] = _num(totals.get("gross")) - _num(totals.get("discount"))

	invoice_adjustments_rows: list = []
	adjustments_net_signed = 0.0
	adjustments_tax_signed = 0.0
	adjustments_additions_total = 0.0
	adjustments_deductions_total = 0.0
	final_payable_total = invoice_view["payable_total"]
	try:
		raw_adjustments = extra.get("invoice_adjustments") if isinstance(extra, dict) else None
		if isinstance(raw_adjustments, list) and raw_adjustments:
			from adapters.db.models.account import Account as _Account

			acc_ids: list = []
			for row in raw_adjustments:
				if isinstance(row, dict) and row.get("account_id") is not None:
					try:
						acc_ids.append(int(row["account_id"]))
					except Exception:
						continue
			acc_name_map: dict = {}
			acc_code_map: dict = {}
			if acc_ids:
				try:
					for acc in db.query(_Account).filter(_Account.id.in_(set(acc_ids))).all():
						acc_name_map[int(acc.id)] = acc.name or ""
						acc_code_map[int(acc.id)] = getattr(acc, "code", None)
				except Exception:
					pass

			for row in raw_adjustments:
				if not isinstance(row, dict):
					continue
				kind = str(row.get("kind") or "").strip().lower()
				if kind not in ("addition", "deduction"):
					continue
				amt = _num(row.get("amount"))
				tr = _num(row.get("tax_rate"))
				tax_amt = _num(row.get("tax_amount"))
				total = _num(row.get("total")) if row.get("total") is not None else (amt + tax_amt)
				acc_id_int = None
				try:
					if row.get("account_id") is not None:
						acc_id_int = int(row["account_id"])
				except Exception:
					acc_id_int = None
				# اگر payload عمومی already enrich شده باشد، نام/کد حساب همراه ردیف می‌آید.
				acc_name = (
					row.get("account_name")
					or (acc_name_map.get(acc_id_int) if acc_id_int is not None else None)
				)
				acc_code = (
					row.get("account_code")
					or (acc_code_map.get(acc_id_int) if acc_id_int is not None else None)
				)
				kind_label = (
					("اضافه" if is_fa else "Addition")
					if kind == "addition"
					else ("کسر" if is_fa else "Deduction")
				)
				sign = 1 if kind == "addition" else -1
				adjustments_net_signed += amt * sign
				adjustments_tax_signed += tax_amt * sign
				if kind == "addition":
					adjustments_additions_total += total
				else:
					adjustments_deductions_total += total
				desc_val = row.get("description")
				desc_str = desc_val.strip() if isinstance(desc_val, str) else (desc_val or "")
				invoice_adjustments_rows.append({
					"kind": kind,
					"kind_label": kind_label,
					"amount": amt,
					"tax_rate": tr,
					"tax_amount": tax_amt,
					"total": total,
					"signed_amount": amt * sign,
					"signed_tax": tax_amt * sign,
					"signed_total": total * sign,
					"account_id": acc_id_int,
					"account_name": acc_name,
					"account_code": acc_code,
					"description": desc_str,
				})
		else:
			adjustments_net_signed = _num((totals or {}).get("adjustments_net"))
			adjustments_tax_signed = _num((totals or {}).get("adjustments_tax"))

		adjustments_net_signed = round(adjustments_net_signed, 2)
		adjustments_tax_signed = round(adjustments_tax_signed, 2)
		adjustments_additions_total = round(adjustments_additions_total, 2)
		adjustments_deductions_total = round(adjustments_deductions_total, 2)
		final_payable_total = round(
			float(invoice_view.get("payable_total") or 0)
			+ adjustments_net_signed
			+ adjustments_tax_signed,
			2,
		)
	except Exception:
		invoice_adjustments_rows = []
		adjustments_net_signed = 0.0
		adjustments_tax_signed = 0.0
		adjustments_additions_total = 0.0
		adjustments_deductions_total = 0.0
		final_payable_total = invoice_view.get("payable_total")

	invoice_view["invoice_adjustments"] = invoice_adjustments_rows
	invoice_view["adjustments_net"] = adjustments_net_signed
	invoice_view["adjustments_tax"] = adjustments_tax_signed
	invoice_view["adjustments_additions_total"] = adjustments_additions_total
	invoice_view["adjustments_deductions_total"] = adjustments_deductions_total
	invoice_view["final_payable_total"] = final_payable_total

	storage = FileStorageService(db)

	async def _load_logo_data_uri(logo_uuid: Optional[UUID]) -> Optional[str]:
		if not logo_uuid:
			return None
		try:
			file_data = await storage.download_file(logo_uuid)
		except Exception:
			return None
		content_bytes = file_data.get("content") or b""
		if not content_bytes:
			return None
		mime = file_data.get("mime_type") or "image/png"
		b64 = base64.b64encode(content_bytes).decode("ascii")
		return f"data:{mime};base64,{b64}"

	logo_uuid = business_logo_file_id_for_invoice_share(db, code)
	business_logo_data_uri = await _load_logo_data_uri(logo_uuid)

	installment_plan = None
	if installments.get("has_installments"):
		installment_plan = {
			"meta": {
				"invoice_code": invoice.get("code"),
			},
			"data": {
				"schedule": [
					{
						**it,
						"due_date_display": _fmt_date(it.get("due_date")),
						"status": _status_label(str(it.get("status") or "")),
					}
					for it in (installments.get("schedule") or [])
					if isinstance(it, dict)
				],
			},
		}

	template_context = {
		"title_text": "فاکتور" if is_fa else "Invoice",
		"is_fa": is_fa,
		"generated_at": datetime.utcnow(),
		"business_name": business.get("name") or "",
		"business": {
			"name": business.get("name"),
			"address": business.get("address"),
			"phone": business.get("phone"),
			"mobile": business.get("mobile"),
		},
		"seller": seller_info,
		"buyer": buyer_info,
		"invoice": invoice_view,
		"lines": normalized_lines,
		"has_line_discount": has_line_discount,
		"has_line_tax": has_line_tax,
		"payments": [],
		"installment_plan": installment_plan,
		"business_logo_data_uri": business_logo_data_uri,
		"business_stamp_data_uri": None,
		"owner_signature_data_uri": None,
		"show_invoice_verify_qr": False,
		"invoice_verify_qr_data_uri": None,
		"show_footer_print_time": True,
		"show_footer_preparer": False,
		"invoice_footer_note": None,
		"customer_balance_info": {},
		"show_seller_signature_area": True,
		"show_buyer_signature_area": True,
		"paper_size": None,
		"orientation": "landscape",
		"footer_text": "",
	}

	html_content = render_template("pdf/invoices/detail.html", template_context)

	from weasyprint import HTML
	from weasyprint.text.fonts import FontConfiguration

	pdf_bytes = HTML(string=html_content).write_pdf(font_config=FontConfiguration())
	def _slugify(text: str) -> str:
		return re.sub(r"[^A-Za-z0-9_-]+", "_", (text or "")).strip("_") or "invoice"

	filename = f"public_invoice_{_slugify(str(invoice.get('code') or code))}.pdf"
	return Response(
		content=pdf_bytes,
		media_type="application/pdf",
		headers={
			"Content-Disposition": f"attachment; filename={filename}",
			"Content-Length": str(len(pdf_bytes)),
			"Access-Control-Expose-Headers": "Content-Disposition",
		},
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

