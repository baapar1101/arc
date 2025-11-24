from __future__ import annotations

from typing import Any, Dict, Optional, Literal
from fastapi import APIRouter, Depends, Request, Body, HTTPException, Query
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.permissions import require_app_permission
from app.core.responses import success_response
from adapters.db.repositories.notification_repo import NotificationTemplateRepository


router = APIRouter(prefix="/admin/notification-templates", tags=["admin.notification_templates"])


class TemplatePayload(BaseModel):
	event_key: str = Field(..., max_length=100)
	channel: str = Field(..., max_length=32)
	locale: Optional[str] = Field(default=None, max_length=10)
	subject: Optional[str] = Field(default=None, max_length=200)
	body: str
	is_active: bool = True

	@staticmethod
	def validate_channel(ch: str) -> str:
		allowed = {"telegram", "email", "sms", "inapp"}
		if ch not in allowed:
			raise HTTPException(status_code=400, detail=f"کانال نامعتبر است. مقادیر مجاز: {', '.join(sorted(allowed))}")
		return ch

	@staticmethod
	def validate_locale(loc: str | None) -> str | None:
		if loc is None:
			return None
		allowed = {"fa", "en", "ar", "tr"}
		loc_lower = loc.lower().strip()
		if loc_lower not in allowed:
			raise HTTPException(status_code=400, detail=f"زبان نامعتبر است. مقادیر مجاز: {', '.join(sorted(allowed))}")
		return loc_lower

	def model_post_init(self, __context: Any) -> None:  # type: ignore[override]
		self.channel = self.validate_channel(self.channel)
		self.locale = self.validate_locale(self.locale)


@router.get("", summary="لیست قالب‌ها")
@require_app_permission("system_settings")
def list_templates(
	request: Request,
	event_key: Optional[str] = Query(None, description="فیلتر بر اساس event_key"),
	channel: Optional[str] = Query(None, description="فیلتر بر اساس channel"),
	is_active: Optional[bool] = Query(None, description="فیلتر بر اساس وضعیت فعال/غیرفعال"),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
	repo = NotificationTemplateRepository(db)
	items = repo.list(event_key=event_key, channel=channel, is_active=is_active)
	data = [
		{
			"id": t.id,
			"event_key": t.event_key,
			"channel": t.channel,
			"locale": t.locale,
			"subject": t.subject,
			"body": t.body,
			"is_active": t.is_active,
			"created_at": t.created_at,
			"updated_at": t.updated_at,
		}
		for t in items
	]
	return success_response({"items": data}, request)


@router.post("/list", summary="لیست قالب‌ها با QueryInfo")
@require_app_permission("system_settings")
def list_templates_with_query(
	request: Request,
	query_info: Dict[str, Any] = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
	from adapters.api.v1.schemas import QueryInfo as QueryInfoSchema
	from sqlalchemy import or_, and_
	
	repo = NotificationTemplateRepository(db)
	
	# تبدیل QueryInfo به فیلترها
	query = QueryInfoSchema(**query_info)
	
	# استخراج فیلترها
	event_key = None
	channel = None
	is_active = None
	
	if query.filters:
		for f in query.filters:
			if f.property == "event_key" and f.operator == "=":
				event_key = f.value
			elif f.property == "channel" and f.operator == "=":
				channel = f.value
			elif f.property == "is_active" and f.operator == "=":
				is_active = f.value
	
	# جستجو در event_key, channel, subject, body
	items = repo.list(event_key=event_key, channel=channel, is_active=is_active)
	
	# اعمال جستجو
	if query.search:
		search_lower = query.search.lower()
		items = [
			t for t in items
			if (
				(search_lower in (t.event_key or "").lower()) or
				(search_lower in (t.channel or "").lower()) or
				(search_lower in (t.subject or "").lower() if t.subject else False) or
				(search_lower in (t.body or "").lower())
			)
		]
	
	# مرتب‌سازی
	if query.sort_by:
		reverse = query.sort_desc
		if query.sort_by == "event_key":
			items.sort(key=lambda x: x.event_key or "", reverse=reverse)
		elif query.sort_by == "channel":
			items.sort(key=lambda x: x.channel or "", reverse=reverse)
		elif query.sort_by == "created_at":
			items.sort(key=lambda x: x.created_at, reverse=reverse)
		elif query.sort_by == "updated_at":
			items.sort(key=lambda x: x.updated_at, reverse=reverse)
	
	# صفحه‌بندی
	total = len(items)
	skip = query.skip or 0
	take = query.take or 20
	items = items[skip:skip + take]
	
	data = [
		{
			"id": t.id,
			"event_key": t.event_key,
			"channel": t.channel,
			"locale": t.locale,
			"subject": t.subject,
			"body": t.body,
			"is_active": t.is_active,
			"created_at": t.created_at,
			"updated_at": t.updated_at,
		}
		for t in items
	]
	
	# محاسبه pagination
	page = (skip // take) + 1
	total_pages = (total + take - 1) // take
	
	return success_response({
		"items": data,
		"pagination": {
			"total": total,
			"page": page,
			"per_page": take,
			"total_pages": total_pages,
			"has_next": page < total_pages,
			"has_prev": page > 1,
		}
	}, request)


@router.post("", summary="ایجاد قالب")
@require_app_permission("system_settings")
def create_template(
	request: Request,
	payload: TemplatePayload = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
	repo = NotificationTemplateRepository(db)
	# بررسی duplicate
	if repo.exists(event_key=payload.event_key, channel=payload.channel, locale=payload.locale):
		raise HTTPException(
			status_code=400,
			detail=f"قالب با event_key='{payload.event_key}', channel='{payload.channel}', locale='{payload.locale or 'None'}' قبلاً وجود دارد"
		)
	obj = repo.create(
		event_key=payload.event_key,
		channel=payload.channel,
		locale=payload.locale,
		subject=payload.subject,
		body=payload.body,
		is_active=payload.is_active,
	)
	return success_response({"id": obj.id}, request)


@router.put("/{template_id}", summary="ویرایش قالب")
@require_app_permission("system_settings")
def update_template(
	request: Request,
	template_id: int,
	payload: TemplatePayload = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
	repo = NotificationTemplateRepository(db)
	obj = repo.get_by_id(template_id)
	if not obj:
		raise HTTPException(status_code=404, detail="قالب یافت نشد")
	# بررسی duplicate (به جز خود قالب فعلی)
	if repo.exists(event_key=payload.event_key, channel=payload.channel, locale=payload.locale, exclude_id=template_id):
		raise HTTPException(
			status_code=400,
			detail=f"قالب با event_key='{payload.event_key}', channel='{payload.channel}', locale='{payload.locale or 'None'}' قبلاً وجود دارد"
		)
	obj = repo.update(
		obj,
		event_key=payload.event_key,
		channel=payload.channel,
		locale=payload.locale,
		subject=payload.subject,
		body=payload.body,
		is_active=payload.is_active,
	)
	return success_response({"ok": True}, request)


@router.delete("/{template_id}", summary="حذف قالب")
@require_app_permission("system_settings")
def delete_template(
	template_id: int,
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
	repo = NotificationTemplateRepository(db)
	obj = repo.get_by_id(template_id)
	if not obj:
		raise HTTPException(status_code=404, detail="قالب یافت نشد")
	repo.delete(obj)
	return success_response({"ok": True}, request)


@router.post("/preview", summary="پیش‌نمایش رندر قالب نوتیفیکیشن")
@require_app_permission("system_settings")
def preview_template(
	request: Request,
	body: Dict[str, Any] = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
	from jinja2.sandbox import SandboxedEnvironment
	from jinja2 import StrictUndefined, BaseLoader, TemplateSyntaxError, UndefinedError
	channel = str((body or {}).get("channel") or "")
	subject = (body or {}).get("subject") or ""
	text = (body or {}).get("body") or ""
	context = (body or {}).get("context") or {}
	# اعتبارسنجی کانال
	TemplatePayload.validate_channel(channel)
	try:
		env = SandboxedEnvironment(loader=BaseLoader(), autoescape=True, undefined=StrictUndefined, enable_async=False)
		subj = ""
		if subject:
			subj = env.from_string(str(subject)).render(**context)
		out = env.from_string(str(text)).render(**context)
		return success_response({"channel": channel, "subject": subj, "body": out}, request)
	except (TemplateSyntaxError, UndefinedError) as e:
		raise HTTPException(status_code=400, detail=f"خطا در قالب: {e}")
	except Exception as e:
		raise HTTPException(status_code=400, detail=f"خطا در رندر: {e}")

