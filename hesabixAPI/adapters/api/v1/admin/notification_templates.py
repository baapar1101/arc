# Removed __future__ annotations to fix OpenAPI schema generation

from typing import Any, Dict, Optional, Literal
from fastapi import APIRouter, Depends, Request, Body, HTTPException
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
			raise HTTPException(status_code=400, detail=f"Invalid channel. Allowed: {', '.join(sorted(allowed))}")
		return ch

	def model_post_init(self, __context: Any) -> None:  # type: ignore[override]
		self.channel = self.validate_channel(self.channel)


@router.get("", summary="لیست قالب‌ها")
@require_app_permission("system_settings")
def list_templates(
	request: Request,
	event_key: Optional[str] = None,
	channel: Optional[str] = None,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
	repo = NotificationTemplateRepository(db)
	items = repo.list(event_key=event_key, channel=channel)
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


@router.post("", summary="ایجاد قالب")
@require_app_permission("system_settings")
def create_template(
	request: Request,
	payload: TemplatePayload = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
	repo = NotificationTemplateRepository(db)
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
		raise HTTPException(status_code=404, detail="Template not found")
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
		raise HTTPException(status_code=404, detail="Template not found")
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
		raise HTTPException(status_code=400, detail=f"Template error: {e}")
	except Exception as e:
		raise HTTPException(status_code=400, detail=f"Render error: {e}")

