from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Body, Depends, Request
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.permissions import require_business_access
from app.core.responses import ApiError, success_response
from app.services.report_template_service import ReportTemplateService

router = APIRouter(prefix="/report-templates", tags=["قالب‌های گزارش", "گزارش‌ها"])


@router.get(
	"/business/{business_id}",
	summary="لیست قالب‌های گزارش",
	description="لیست قالب‌ها با امکان فیلتر بر اساس ماژول و زیرنوع. کاربران عادی فقط Published را می‌بینند.",
)
@require_business_access("business_id")
async def list_report_templates(
	request: Request,
	business_id: int,
	module_key: Optional[str] = None,
	subtype: Optional[str] = None,
	status: Optional[str] = None,
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
):
	only_published = True
	# فقط کسانی که write در report_templates دارند، می‌توانند پیش‌نویس‌ها را ببینند
	if ctx.can_write_section("report_templates"):
		only_published = False
	templates = ReportTemplateService.list_templates(
		db=db,
		business_id=business_id,
		module_key=module_key,
		subtype=subtype,
		status=status,
		only_published=only_published,
	)
	data: List[Dict[str, Any]] = []
	for t in templates:
		data.append({
			"id": t.id,
			"business_id": t.business_id,
			"module_key": t.module_key,
			"subtype": t.subtype,
			"name": t.name,
			"description": t.description,
			"status": t.status,
			"is_default": t.is_default,
			"version": t.version,
			"paper_size": t.paper_size,
			"orientation": t.orientation,
			"margins": t.margins,
			"updated_at": t.updated_at.isoformat() if t.updated_at else None,
		})
	return {"items": data}


@router.get(
	"/{template_id}/business/{business_id}",
	summary="جزئیات یک قالب گزارش (فقط سازندگان)",
	description="اطلاعات کامل قالب شامل محتوا برای ویرایشگر",
)
@require_business_access("business_id")
async def get_report_template(
	request: Request,
	template_id: int,
	business_id: int,
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
):
	if not ctx.can_write_section("report_templates"):
		raise ApiError("FORBIDDEN", "Missing permission: report_templates.write", http_status=403)
	entity = ReportTemplateService.get_template(db=db, template_id=template_id, business_id=business_id)
	if not entity:
		raise ApiError("NOT_FOUND", "Template not found", http_status=404)
	return {
		"id": entity.id,
		"business_id": entity.business_id,
		"module_key": entity.module_key,
		"subtype": entity.subtype,
		"name": entity.name,
		"description": entity.description,
		"engine": entity.engine,
		"status": entity.status,
		"is_default": entity.is_default,
		"version": entity.version,
		"content_html": entity.content_html,
		"content_css": entity.content_css,
		"header_html": entity.header_html,
		"footer_html": entity.footer_html,
		"paper_size": entity.paper_size,
		"orientation": entity.orientation,
		"margins": entity.margins,
		"assets": entity.assets,
		"created_by": entity.created_by,
		"created_at": entity.created_at.isoformat() if entity.created_at else None,
		"updated_at": entity.updated_at.isoformat() if entity.updated_at else None,
	}


@router.post(
	"/business/{business_id}",
	summary="ایجاد قالب جدید (فقط سازندگان)",
)
@require_business_access("business_id")
async def create_report_template(
	request: Request,
	business_id: int,
	body: Dict[str, Any] = Body(...),
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
):
	if not ctx.can_write_section("report_templates"):
		raise ApiError("FORBIDDEN", "Missing permission: report_templates.write", http_status=403)
	body = dict(body or {})
	body["business_id"] = business_id
	entity = ReportTemplateService.create_template(db=db, data=body, user_id=ctx.get_user_id())
	return {"id": entity.id}


@router.put(
	"/{template_id}/business/{business_id}",
	summary="ویرایش قالب (فقط سازندگان)",
)
@require_business_access("business_id")
async def update_report_template(
	request: Request,
	template_id: int,
	business_id: int,
	body: Dict[str, Any] = Body(...),
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
):
	if not ctx.can_write_section("report_templates"):
		raise ApiError("FORBIDDEN", "Missing permission: report_templates.write", http_status=403)
	entity = ReportTemplateService.update_template(db=db, template_id=template_id, data=body or {}, business_id=business_id)
	return {"id": entity.id, "version": entity.version}


@router.delete(
	"/{template_id}/business/{business_id}",
	summary="حذف قالب (فقط سازندگان)",
)
@require_business_access("business_id")
async def delete_report_template(
	request: Request,
	template_id: int,
	business_id: int,
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
):
	if not ctx.can_write_section("report_templates"):
		raise ApiError("FORBIDDEN", "Missing permission: report_templates.write", http_status=403)
	ReportTemplateService.delete_template(db=db, template_id=template_id, business_id=business_id)
	return success_response(data={"deleted": True}, request=request, message="Deleted")


@router.post(
	"/{template_id}/business/{business_id}/publish",
	summary="انتشار/بازگشت به پیش‌نویس (فقط سازندگان)",
)
@require_business_access("business_id")
async def publish_report_template(
	request: Request,
	template_id: int,
	business_id: int,
	body: Dict[str, Any] = Body(...),
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
):
	if not ctx.can_write_section("report_templates"):
		raise ApiError("FORBIDDEN", "Missing permission: report_templates.write", http_status=403)
	is_published = bool((body or {}).get("published", True))
	entity = ReportTemplateService.publish_template(db=db, template_id=template_id, business_id=business_id, is_published=is_published)
	return {"id": entity.id, "status": entity.status}


@router.post(
	"/business/{business_id}/set-default",
	summary="تنظیم قالب پیش‌فرض یک ماژول/زیرنوع (فقط سازندگان)",
)
@require_business_access("business_id")
async def set_default_template(
	request: Request,
	business_id: int,
	body: Dict[str, Any] = Body(...),
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
):
	if not ctx.can_write_section("report_templates"):
		raise ApiError("FORBIDDEN", "Missing permission: report_templates.write", http_status=403)
	module_key = str((body or {}).get("module_key") or "")
	if not module_key:
		raise ApiError("VALIDATION_ERROR", "module_key is required", http_status=400)
	subtype = (body or {}).get("subtype")
	template_id = int((body or {}).get("template_id") or 0)
	if template_id <= 0:
		raise ApiError("VALIDATION_ERROR", "template_id is required", http_status=400)
	# فقط اجازه پیش‌فرض کردن قالب منتشرشده
	entity_check = ReportTemplateService.get_template(db=db, template_id=template_id, business_id=business_id)
	if not entity_check or entity_check.status != "published":
		raise ApiError("VALIDATION_ERROR", "Only published templates can be set as default", http_status=400)
	entity = ReportTemplateService.set_default(
		db=db,
		business_id=business_id,
		module_key=module_key,
		subtype=(str(subtype) if subtype is not None else None),
		template_id=template_id,
	)
	return {"id": entity.id, "is_default": entity.is_default}


@router.post(
	"/business/{business_id}/preview",
	summary="پیش‌نمایش قالب (فقط سازندگان)",
	description="بدون ذخیره‌سازی؛ HTML/CSS ارسالی با داده نمونه رندر و به PDF تبدیل می‌شود.",
)
@require_business_access("business_id")
async def preview_report_template(
	request: Request,
	business_id: int,
	body: Dict[str, Any] = Body(...),
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
):
	from weasyprint import HTML
	from weasyprint.text.fonts import FontConfiguration
	if not ctx.can_write_section("report_templates"):
		raise ApiError("FORBIDDEN", "Missing permission: report_templates.write", http_status=403)
	engine = str((body or {}).get("engine") or "").lower() or "jinja2"
	content_html = (body or {}).get("content_html") or ""
	content_css = (body or {}).get("content_css") or ""
	context = (body or {}).get("context") or {}
	# محدودیت ساده روی اندازه ورودی‌ها
	max_len = 1_000_000  # 1MB
	if len(content_html) > max_len or len(content_css) > max_len:
		raise ApiError("PAYLOAD_TOO_LARGE", "HTML/CSS too large for preview", http_status=413)
	temp = type("T", (), {
		"engine": engine,
		"content_html": content_html,
		"content_css": content_css,
		"header_html": (body or {}).get("header_html") or "",
		"footer_html": (body or {}).get("footer_html") or "",
		"paper_size": None,
		"orientation": None,
		"margins": None,
		"assets": (body or {}).get("assets") or ({"builder_design": (body or {}).get("design")} if engine == "builder" else None),
	})()  # شیء موقت شبیه ReportTemplate
	try:
		html = ReportTemplateService.render_with_template(temp, context)
	except Exception as e:
		raise ApiError("TEMPLATE_ERROR", f"Render error: {e}", http_status=400)
	try:
		pdf_bytes = HTML(string=html).write_pdf(font_config=FontConfiguration())
		return {
			"content_length": len(pdf_bytes),
			"ok": True,
			"html": html,
		}
	except Exception as e:
		raise ApiError("PDF_ERROR", f"PDF generation error: {e}", http_status=400)


@router.post(
	"/business/{business_id}/preview-pdf",
	summary="پیش‌نمایش PDF قالب (فقط سازندگان)",
	description="بدون ذخیره‌سازی؛ HTML/CSS ارسالی با داده نمونه رندر و به PDF تبدیل می‌شود. فایل PDF به صورت bytes برگردانده می‌شود.",
)
@require_business_access("business_id")
async def preview_report_template_pdf(
	request: Request,
	business_id: int,
	body: Dict[str, Any] = Body(...),
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
):
	from weasyprint import HTML
	from weasyprint.text.fonts import FontConfiguration
	from fastapi.responses import Response
	if not ctx.can_write_section("report_templates"):
		raise ApiError("FORBIDDEN", "Missing permission: report_templates.write", http_status=403)
	engine = str((body or {}).get("engine") or "").lower() or "jinja2"
	content_html = (body or {}).get("content_html") or ""
	content_css = (body or {}).get("content_css") or ""
	context = (body or {}).get("context") or {}
	# محدودیت ساده روی اندازه ورودی‌ها
	max_len = 1_000_000  # 1MB
	if len(content_html) > max_len or len(content_css) > max_len:
		raise ApiError("PAYLOAD_TOO_LARGE", "HTML/CSS too large for preview", http_status=413)
	temp = type("T", (), {
		"engine": engine,
		"content_html": content_html,
		"content_css": content_css,
		"header_html": (body or {}).get("header_html") or "",
		"footer_html": (body or {}).get("footer_html") or "",
		"paper_size": (body or {}).get("paper_size") or None,
		"orientation": (body or {}).get("orientation") or None,
		"margins": (body or {}).get("margins") or None,
		"assets": (body or {}).get("assets") or ({"builder_design": (body or {}).get("design")} if engine == "builder" else None),
	})()  # شیء موقت شبیه ReportTemplate
	try:
		html = ReportTemplateService.render_with_template(temp, context)
	except Exception as e:
		raise ApiError("TEMPLATE_ERROR", f"Render error: {e}", http_status=400)
	try:
		pdf_bytes = HTML(string=html).write_pdf(font_config=FontConfiguration())
		return Response(
			content=pdf_bytes,
			media_type="application/pdf",
			headers={
				"Content-Disposition": "inline; filename=preview.pdf",
				"Content-Length": str(len(pdf_bytes)),
				"Access-Control-Expose-Headers": "Content-Disposition",
			},
		)
	except Exception as e:
		raise ApiError("PDF_ERROR", f"PDF generation error: {e}", http_status=400)

@router.get(
	"/business/{business_id}/schema",
	summary="Schema متغیرهای قابل‌استفاده در قالب برای ماژول/زیرنوع",
	description="لیست کلیدها/توضیحات و نمونه context برای کمک به سازندگان قالب",
)
@require_business_access("business_id")
async def report_template_schema(
	request: Request,
	business_id: int,
	module_key: str,
	subtype: Optional[str] = None,
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
):
	# نمونه ساده بر اساس ماژول‌های رایج
	def base():
		return {
			"keys": [
				{"name": "title_text", "desc": "عنوان گزارش"},
				{"name": "date_now", "desc": "تاریخ/زمان فعلی"},
			],
			"sample_context": {
				"title_text": "گزارش نمونه",
				"date_now": "1403/01/01 12:00",
			},
		}
	data = base()
	if module_key == "invoices" and (subtype or "") == "list":
		data["keys"] += [
			{"name": "items", "desc": "لیست فاکتورها"},
			{"name": "table_headers_html", "desc": "HTML آماده هدر جدول"},
			{"name": "table_rows_html", "desc": "HTML آماده ردیف‌های جدول"},
		]
	elif module_key == "invoices" and (subtype or "") == "detail":
		data["keys"] += [
			{"name": "invoice", "desc": "شیء فاکتور"},
			{"name": "items", "desc": "آیتم‌های فاکتور"},
		]
	elif module_key == "transfers" and (subtype or "") == "detail":
		data["keys"] += [
			{"name": "document", "desc": "شیء کامل سند انتقال"},
			{"name": "code", "desc": "کد سند"},
			{"name": "document_date", "desc": "تاریخ سند (فرمت شده)"},
			{"name": "total_amount", "desc": "مبلغ کل انتقال"},
			{"name": "commission", "desc": "کارمزد (در صورت وجود)"},
			{"name": "description", "desc": "توضیحات سند"},
			{"name": "source_type", "desc": "نوع مبدأ (bank/cash_register/petty_cash)"},
			{"name": "source_type_name", "desc": "نام فارسی نوع مبدأ"},
			{"name": "source_name", "desc": "نام مبدأ"},
			{"name": "destination_type", "desc": "نوع مقصد (bank/cash_register/petty_cash)"},
			{"name": "destination_type_name", "desc": "نام فارسی نوع مقصد"},
			{"name": "destination_name", "desc": "نام مقصد"},
			{"name": "account_lines", "desc": "لیست خطوط حساب‌ها (شامل مبدأ، مقصد و کارمزد)"},
			{"name": "business_name", "desc": "نام کسب‌وکار"},
			{"name": "business_logo_data_uri", "desc": "لوگوی کسب‌وکار (data URI)"},
			{"name": "business_stamp_data_uri", "desc": "مهر کسب‌وکار (data URI)"},
			{"name": "owner_signature_data_uri", "desc": "امضای مالک (data URI)"},
			{"name": "generated_at", "desc": "تاریخ/زمان تولید PDF"},
			{"name": "is_fa", "desc": "آیا زبان فارسی است (boolean)"},
		]
		data["sample_context"]["document"] = {
			"id": 1,
			"code": "TR-20240101-0001",
			"total_amount": 1000000,
			"commission": 5000,
			"source_type": "bank",
			"source_type_name": "حساب بانکی",
			"source_name": "بانک ملی",
			"destination_type": "cash_register",
			"destination_type_name": "صندوق",
			"destination_name": "صندوق اصلی",
		}
		data["sample_context"]["account_lines"] = [
			{
				"account_name": "صندوق",
				"account_code": "10202",
				"side": "destination",
				"amount": 1000000,
			},
			{
				"account_name": "حساب بانکی",
				"account_code": "10203",
				"side": "source",
				"amount": 1000000,
			},
		]
	elif module_key in ("documents", "receipts_payments", "expense_income"):
		data["keys"] += [
			{"name": "items", "desc": "لیست رکوردها"},
			{"name": "table_headers_html", "desc": "HTML هدر جدول"},
			{"name": "table_rows_html", "desc": "HTML ردیف‌های جدول"},
		]
	elif module_key == "transfers" and (subtype or "") == "list":
		data["keys"] += [
			{"name": "items", "desc": "لیست اسناد انتقال"},
			{"name": "table_headers_html", "desc": "HTML هدر جدول"},
			{"name": "table_rows_html", "desc": "HTML ردیف‌های جدول"},
		]
	elif module_key == "warehouse_documents" and (subtype or "") == "postal_label":
		from app.services.warehouse_postal_label_service import sample_postal_label_context
		sc = sample_postal_label_context()
		data["keys"] += [
			{"name": "business", "desc": "اطلاعات کسب‌وکار"},
			{"name": "sender", "desc": "فرستنده (name, phone, address, postal_code, city)"},
			{"name": "receiver", "desc": "گیرنده (name, phone, address, postal_code, city, warehouse_name)"},
			{"name": "sender_caption", "desc": "عنوان بلوک فرستنده"},
			{"name": "receiver_caption", "desc": "عنوان بلوک گیرنده"},
			{"name": "document", "desc": "شیء حواله انبار (code, doc_type, delivery_method_display, …)"},
			{"name": "direction", "desc": "in | out | other"},
			{"name": "direction_label", "desc": "برچسب خوانای جهت حواله"},
			{"name": "label_title", "desc": "عنوان برگه"},
			{"name": "document_date_display", "desc": "تاریخ سند (نمایشی)"},
			{"name": "lines_summary", "desc": "خلاصهٔ خطوط کالا"},
			{"name": "paper_size", "desc": "سایز کاغذ درخواستی"},
			{"name": "orientation", "desc": "portrait | landscape"},
			{"name": "page_size_css", "desc": "مقدار ترکیبی برای CSS @page size"},
			{"name": "show_sender", "desc": "bool — نمایش فرستنده"},
			{"name": "show_receiver", "desc": "bool — نمایش گیرنده"},
			{"name": "show_warehouse", "desc": "bool — نمایش انبار"},
			{"name": "show_lines", "desc": "bool — نمایش خلاصه کالا"},
			{"name": "show_delivery", "desc": "bool — روش ارسال و حمل"},
			{"name": "show_tracking", "desc": "bool — شماره پیگیری"},
			{"name": "show_source", "desc": "bool — سند مبدأ"},
			{"name": "business_logo_data_uri", "desc": "لوگوی کسب‌وکار (data URI)"},
			{"name": "fa_font_url_regular", "desc": "فونت فارسی (data URI)"},
			{"name": "is_fa", "desc": "زبان فارسی"},
		]
		data["sample_context"] = {**data["sample_context"], **sc}
	return data


