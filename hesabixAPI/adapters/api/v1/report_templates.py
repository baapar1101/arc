from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Body, Depends, Request
from sqlalchemy.orm import Session
from sqlalchemy import func, desc, asc
from datetime import datetime

from adapters.db.session import get_db
from adapters.db.models.user import User
from adapters.db.models.report_template_status_event import ReportTemplateStatusEvent
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.permissions import require_business_access
from app.core.responses import ApiError, success_response
from app.services.report_template_service import ReportTemplateService
from app.services.report_template_scope_registry import (
	catalog as scope_catalog,
	get_scope_meta,
	is_known_scope,
)

router = APIRouter(prefix="/report-templates", tags=["قالب‌های گزارش", "گزارش‌ها"])


def _actor_display(db: Session, user_id: Optional[int]) -> Optional[str]:
	if not user_id:
		return None
	u = db.query(User).filter(User.id == int(user_id)).first()
	if not u:
		return None
	full = f"{(u.first_name or '').strip()} {(u.last_name or '').strip()}".strip()
	if full:
		return full
	return (u.email or u.mobile or f"User#{u.id}")


@router.get(
	"/business/{business_id}/scope-catalog",
	summary="کاتالوگ scopeهای معتبر قالب",
	description="لیست scopeهای مجاز برای اتصال قالب به نوع سند.",
)
@require_business_access("business_id")
async def report_template_scope_catalog(
	request: Request,
	business_id: int,
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
):
	# دسترسی خواندن برای اعضای کسب‌وکار کافی است.
	return {"items": scope_catalog()}


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
		latest_event = ReportTemplateService.latest_status_event(db, int(t.id), int(business_id))
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
			"last_status_event": (
				{
					"from_status": latest_event.from_status,
					"to_status": latest_event.to_status,
					"reason": latest_event.reason,
					"actor_user_id": latest_event.actor_user_id,
					"actor_display": _actor_display(db, latest_event.actor_user_id),
					"created_at": latest_event.created_at.isoformat() if latest_event.created_at else None,
				}
				if latest_event
				else None
			),
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
	summary="انتشار/بازگشت به پیش‌نویس (سازگاری با نسخه قبل)",
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
	if is_published:
		if not ctx.can_approve_section("report_templates"):
			raise ApiError("FORBIDDEN", "Missing permission: report_templates.approve", http_status=403)
		entity_check = ReportTemplateService.get_template(db=db, template_id=template_id, business_id=business_id)
		if not entity_check:
			raise ApiError("NOT_FOUND", "Template not found", http_status=404)
		if (entity_check.engine or "").lower() == "builder":
			assets = entity_check.assets or {}
			design = (assets.get("builder_design") or assets.get("design") or {}) if isinstance(assets, dict) else {}
			validation = ReportTemplateService.validate_builder_design_scope(
				entity_check.module_key,
				entity_check.subtype,
				design if isinstance(design, dict) else {},
			)
			if validation.get("errors"):
				raise ApiError(
					"VALIDATION_ERROR",
					"Cannot publish builder template: " + "; ".join(validation["errors"]),
					http_status=400,
				)
		if (entity_check.status or "").lower() != "approved":
			raise ApiError("VALIDATION_ERROR", "Template must be approved before publishing", http_status=400)
	entity = ReportTemplateService.publish_template(db=db, template_id=template_id, business_id=business_id, is_published=is_published)
	return {"id": entity.id, "status": entity.status}


@router.post(
	"/{template_id}/business/{business_id}/transition",
	summary="تغییر وضعیت lifecycle قالب",
	description="تغییر وضعیت کنترل‌شده: draft/in_review/approved/published/deprecated",
)
@require_business_access("business_id")
async def transition_report_template_status(
	request: Request,
	template_id: int,
	business_id: int,
	body: Dict[str, Any] = Body(...),
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
):
	to_status = str((body or {}).get("to_status") or "").strip().lower()
	reason = str((body or {}).get("reason") or "").strip() or None
	if not to_status:
		raise ApiError("VALIDATION_ERROR", "to_status is required", http_status=400)
	entity = ReportTemplateService.get_template(db=db, template_id=template_id, business_id=business_id)
	if not entity:
		raise ApiError("NOT_FOUND", "Template not found", http_status=404)
	# نقش‌ها:
	# - reviewer/publisher: approve
	# - designer: write
	if to_status == "in_review" and not ctx.can_write_section("report_templates"):
		raise ApiError("FORBIDDEN", "Missing permission: report_templates.write", http_status=403)
	if to_status in ("approved", "published") and not ctx.can_approve_section("report_templates"):
		raise ApiError("FORBIDDEN", "Missing permission: report_templates.approve", http_status=403)
	if to_status == "deprecated" and not ctx.can_approve_section("report_templates"):
		raise ApiError("FORBIDDEN", "Missing permission: report_templates.approve", http_status=403)
	if to_status == "draft":
		cur = (entity.status or "").lower()
		if cur in ("approved", "published", "deprecated") and not ctx.can_approve_section("report_templates"):
			raise ApiError("FORBIDDEN", "Missing permission: report_templates.approve", http_status=403)
		if not (ctx.can_write_section("report_templates") or ctx.can_approve_section("report_templates")):
			raise ApiError("FORBIDDEN", "Missing permission: report_templates.write|approve", http_status=403)
	if to_status in ("deprecated", "draft") and not reason:
		raise ApiError("VALIDATION_ERROR", "reason is required for this transition", http_status=400)
	if to_status == "published":
		# نشر فقط برای قالب approved و بدون خطای validation
		if (entity.status or "").lower() != "approved":
			raise ApiError("VALIDATION_ERROR", "Template must be approved before publishing", http_status=400)
		if (entity.engine or "").lower() == "builder":
			assets = entity.assets or {}
			design = (assets.get("builder_design") or assets.get("design") or {}) if isinstance(assets, dict) else {}
			validation = ReportTemplateService.validate_builder_design_scope(
				entity.module_key,
				entity.subtype,
				design if isinstance(design, dict) else {},
			)
			if validation.get("errors"):
				raise ApiError(
					"VALIDATION_ERROR",
					"Cannot publish builder template: " + "; ".join(validation["errors"]),
					http_status=400,
				)
	entity = ReportTemplateService.transition_status(
		db=db,
		template_id=template_id,
		business_id=business_id,
		to_status=to_status,
		reason=reason,
		actor_user_id=ctx.get_user_id(),
	)
	return {"id": entity.id, "status": entity.status}


@router.get(
	"/{template_id}/business/{business_id}/status-events",
	summary="تاریخچه تغییر وضعیت قالب",
	description="نمایش timeline تغییر وضعیت‌ها با دلیل و کاربر انجام‌دهنده.",
)
@require_business_access("business_id")
async def report_template_status_events(
	request: Request,
	template_id: int,
	business_id: int,
	limit: int = 50,
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
):
	if not ctx.can_read_section("report_templates"):
		raise ApiError("FORBIDDEN", "Missing permission: report_templates.read", http_status=403)
	entity = ReportTemplateService.get_template(db=db, template_id=template_id, business_id=business_id)
	if not entity:
		raise ApiError("NOT_FOUND", "Template not found", http_status=404)
	events = ReportTemplateService.list_status_events(
		db=db,
		template_id=template_id,
		business_id=business_id,
		limit=limit,
	)
	items: List[Dict[str, Any]] = []
	for e in events:
		items.append(
			{
				"id": e.id,
				"report_template_id": e.report_template_id,
				"from_status": e.from_status,
				"to_status": e.to_status,
				"reason": e.reason,
				"actor_user_id": e.actor_user_id,
				"actor_display": _actor_display(db, e.actor_user_id),
				"created_at": e.created_at.isoformat() if e.created_at else None,
			}
		)
	return {"items": items}


@router.get(
	"/business/{business_id}/status-events",
	summary="گزارش مدیریتی تغییر وضعیت قالب‌ها",
	description="گزارش تجمیعی/فیلترپذیر برای audit تغییر وضعیت قالب‌ها.",
)
@require_business_access("business_id")
async def report_templates_status_events_report(
	request: Request,
	business_id: int,
	status: Optional[str] = None,
	actor_user_id: Optional[int] = None,
	from_date: Optional[str] = None,
	to_date: Optional[str] = None,
	limit: int = 100,
	offset: int = 0,
	sort_by: str = "created_at",
	sort_order: str = "desc",
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
):
	if not (ctx.can_approve_section("report_templates") or ctx.can_export_section("report_templates")):
		raise ApiError("FORBIDDEN", "Missing permission: report_templates.approve|export", http_status=403)
	lim = max(1, min(int(limit or 100), 500))
	off = max(0, int(offset or 0))
	q = db.query(ReportTemplateStatusEvent).filter(
		ReportTemplateStatusEvent.business_id == int(business_id),
	)
	if status:
		q = q.filter(ReportTemplateStatusEvent.to_status == str(status).strip().lower())
	if actor_user_id is not None:
		q = q.filter(ReportTemplateStatusEvent.actor_user_id == int(actor_user_id))
	try:
		if from_date:
			dt_from = datetime.fromisoformat(str(from_date).replace("Z", "+00:00"))
			q = q.filter(ReportTemplateStatusEvent.created_at >= dt_from)
		if to_date:
			dt_to = datetime.fromisoformat(str(to_date).replace("Z", "+00:00"))
			q = q.filter(ReportTemplateStatusEvent.created_at <= dt_to)
	except Exception:
		raise ApiError("VALIDATION_ERROR", "Invalid date filter format (use ISO date/time)", http_status=400)
	total_count = q.count()
	order_field = ReportTemplateStatusEvent.created_at
	if str(sort_by).strip().lower() == "to_status":
		order_field = ReportTemplateStatusEvent.to_status
	elif str(sort_by).strip().lower() == "actor_user_id":
		order_field = ReportTemplateStatusEvent.actor_user_id
	order_dir_desc = str(sort_order).strip().lower() != "asc"
	order_expr = desc(order_field) if order_dir_desc else asc(order_field)
	events = q.order_by(order_expr).offset(off).limit(lim).all()
	items: List[Dict[str, Any]] = []
	for e in events:
		items.append(
			{
				"id": e.id,
				"report_template_id": e.report_template_id,
				"from_status": e.from_status,
				"to_status": e.to_status,
				"reason": e.reason,
				"actor_user_id": e.actor_user_id,
				"actor_display": _actor_display(db, e.actor_user_id),
				"created_at": e.created_at.isoformat() if e.created_at else None,
			}
		)
	# KPI summary (روی دیتای فیلتر شده)
	base_q = db.query(ReportTemplateStatusEvent).filter(
		ReportTemplateStatusEvent.business_id == int(business_id),
	)
	if status:
		base_q = base_q.filter(ReportTemplateStatusEvent.to_status == str(status).strip().lower())
	if actor_user_id is not None:
		base_q = base_q.filter(ReportTemplateStatusEvent.actor_user_id == int(actor_user_id))
	if from_date:
		dt_from = datetime.fromisoformat(str(from_date).replace("Z", "+00:00"))
		base_q = base_q.filter(ReportTemplateStatusEvent.created_at >= dt_from)
	if to_date:
		dt_to = datetime.fromisoformat(str(to_date).replace("Z", "+00:00"))
		base_q = base_q.filter(ReportTemplateStatusEvent.created_at <= dt_to)
	publish_count = base_q.filter(ReportTemplateStatusEvent.to_status == "published").count()
	reject_count = base_q.filter(ReportTemplateStatusEvent.to_status == "draft").count()
	top_actor_rows = (
		base_q.with_entities(
			ReportTemplateStatusEvent.actor_user_id,
			func.count(ReportTemplateStatusEvent.id).label("cnt"),
		)
		.group_by(ReportTemplateStatusEvent.actor_user_id)
		.order_by(desc("cnt"))
		.limit(5)
		.all()
	)
	top_actors: List[Dict[str, Any]] = []
	for uid, cnt in top_actor_rows:
		top_actors.append(
			{
				"actor_user_id": uid,
				"actor_display": _actor_display(db, uid),
				"count": int(cnt or 0),
			}
		)
	top_reason_rows = (
		base_q.with_entities(
			ReportTemplateStatusEvent.reason,
			func.count(ReportTemplateStatusEvent.id).label("cnt"),
		)
		.filter(ReportTemplateStatusEvent.reason.isnot(None))
		.group_by(ReportTemplateStatusEvent.reason)
		.order_by(desc("cnt"))
		.limit(5)
		.all()
	)
	top_reasons = [
		{"reason": (r or "").strip(), "count": int(c or 0)}
		for r, c in top_reason_rows
		if (r or "").strip()
	]
	return {
		"items": items,
		"total_count": total_count,
		"limit": lim,
		"offset": off,
		"sort_by": str(sort_by).strip().lower(),
		"sort_order": "desc" if order_dir_desc else "asc",
		"summary": {
			"publish_count": publish_count,
			"reject_count": reject_count,
			"top_actors": top_actors,
			"top_reasons": top_reasons,
		},
	}


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
	if not is_known_scope(module_key, str(subtype) if subtype is not None else None):
		raise ApiError("VALIDATION_ERROR", "Unknown report template scope", http_status=400)
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
	if not is_known_scope(module_key, subtype):
		raise ApiError("VALIDATION_ERROR", "Unknown report template scope", http_status=400)
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
	meta = get_scope_meta(module_key, subtype)
	data["scope"] = {
		"module_key": module_key,
		"subtype": subtype,
		"label_fa": meta.label_fa if meta else module_key,
		"label_en": meta.label_en if meta else module_key,
	}
	return data


@router.post(
	"/business/{business_id}/validate-builder-design",
	summary="اعتبارسنجی طراحی Builder برای scope",
	description="بررسی سازگاری بلوک‌ها با نوع سند و ارائه errors/warnings.",
)
@require_business_access("business_id")
async def validate_builder_design(
	request: Request,
	business_id: int,
	body: Dict[str, Any] = Body(...),
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
):
	if not ctx.can_write_section("report_templates"):
		raise ApiError("FORBIDDEN", "Missing permission: report_templates.write", http_status=403)
	module_key = str((body or {}).get("module_key") or "")
	subtype_raw = (body or {}).get("subtype")
	subtype = str(subtype_raw) if subtype_raw not in (None, "") else None
	design = (body or {}).get("design") or {}
	if not isinstance(design, dict):
		raise ApiError("VALIDATION_ERROR", "design must be an object", http_status=400)
	out = ReportTemplateService.validate_builder_design_scope(module_key, subtype, design)
	return out


