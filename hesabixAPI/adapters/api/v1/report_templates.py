from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Body, Depends, Request
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.permissions import require_business_access
from app.core.responses import ApiError, success_response
from app.services.report_template_service import ReportTemplateService

router = APIRouter(prefix="/report-templates", tags=["report-templates"])


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
	content_html = (body or {}).get("content_html") or ""
	content_css = (body or {}).get("content_css") or ""
	context = (body or {}).get("context") or {}
	temp = type("T", (), {"content_html": content_html, "content_css": content_css})()  # شیء موقت شبیه ReportTemplate
	html = ReportTemplateService.render_with_template(temp, context)
	pdf_bytes = HTML(string=html).write_pdf(font_config=FontConfiguration())
	return {
		"content_length": len(pdf_bytes),
		"ok": True,
	}


