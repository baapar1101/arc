# noqa: D100
"""API مدیریت چت وب CRM (ویجت، مکالمه، پاسخ عامل)."""
from __future__ import annotations

from typing import Any, Dict, Optional

from fastapi import APIRouter, Body, Depends, Path, Query, Request
from sqlalchemy.orm import Session

from adapters.api.v1.schema_models.crm_chat import (
	BusinessCrmSettingsUpdate,
	CrmChatWidgetCreate,
	CrmChatWidgetUpdate,
	CrmChatAgentMessageCreate,
	CrmChatConversationPatch,
)
from adapters.db.session import get_db
from app.core.auth_dependency import AuthContext, get_current_user
from app.core.permissions import require_business_access, require_business_permission_dep
from app.core.responses import format_datetime_fields, success_response
from app.services import crm_chat_service as chat_svc

router = APIRouter(tags=["CRM — چت وب"])


def _fmt(request: Request, data: Any) -> Any:
	return format_datetime_fields(data, request)


@router.get("/businesses/{business_id}/chat/crm-settings")
@require_business_access("business_id")
async def get_crm_business_settings(
	request: Request,
	business_id: int = Path(..., gt=0),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_business_permission_dep("crm", "view")),
) -> Dict[str, Any]:
	s = chat_svc.get_or_create_crm_settings(db, business_id)
	return success_response(data=_fmt(request, chat_svc.business_crm_settings_to_dict(s)), request=request)


@router.patch("/businesses/{business_id}/chat/crm-settings")
@require_business_access("business_id")
async def patch_crm_business_settings(
	request: Request,
	business_id: int = Path(..., gt=0),
	body: BusinessCrmSettingsUpdate = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_business_permission_dep("crm", "write")),
) -> Dict[str, Any]:
	s = chat_svc.update_crm_business_settings(
		db, business_id, allow_web_chat_file_upload=body.allow_web_chat_file_upload
	)
	return success_response(data=_fmt(request, chat_svc.business_crm_settings_to_dict(s)), request=request, message="تنظیمات ذخیره شد")


@router.get("/businesses/{business_id}/chat/widgets")
@require_business_access("business_id")
async def list_chat_widgets(
	request: Request,
	business_id: int = Path(..., gt=0),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_business_permission_dep("crm", "view")),
) -> Dict[str, Any]:
	rows = chat_svc.list_widgets(db, business_id)
	return success_response(data={"items": [_fmt(request, chat_svc.widget_to_dict(w)) for w in rows]}, request=request)


@router.post("/businesses/{business_id}/chat/widgets")
@require_business_access("business_id")
async def create_chat_widget(
	request: Request,
	business_id: int = Path(..., gt=0),
	body: CrmChatWidgetCreate = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_business_permission_dep("crm", "write")),
) -> Dict[str, Any]:
	w = chat_svc.create_widget(
		db,
		business_id,
		body.name,
		body.allowed_origins,
		body.settings,
		body.is_active,
	)
	return success_response(data=_fmt(request, chat_svc.widget_to_dict(w)), request=request, message="ویجت ایجاد شد")


@router.patch("/businesses/{business_id}/chat/widgets/{widget_id}")
@require_business_access("business_id")
async def update_chat_widget(
	request: Request,
	business_id: int = Path(..., gt=0),
	widget_id: int = Path(..., gt=0),
	body: CrmChatWidgetUpdate = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_business_permission_dep("crm", "write")),
) -> Dict[str, Any]:
	w = chat_svc.update_widget(
		db,
		business_id,
		widget_id,
		name=body.name,
		allowed_origins=body.allowed_origins,
		settings=body.settings,
		is_active=body.is_active,
	)
	return success_response(data=_fmt(request, chat_svc.widget_to_dict(w)), request=request, message="ویجت به‌روز شد")


@router.get("/businesses/{business_id}/chat/conversations")
@require_business_access("business_id")
async def list_chat_conversations(
	request: Request,
	business_id: int = Path(..., gt=0),
	status: Optional[str] = Query(None),
	limit: int = Query(50, ge=1, le=200),
	offset: int = Query(0, ge=0),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_business_permission_dep("crm", "view")),
) -> Dict[str, Any]:
	items = chat_svc.list_conversations_agent(db, business_id, status=status, limit=limit, offset=offset)
	return success_response(data={"items": [_fmt(request, x) for x in items]}, request=request)


@router.get("/businesses/{business_id}/chat/conversations/{conversation_id}/messages")
@require_business_access("business_id")
async def list_chat_messages_agent(
	request: Request,
	business_id: int = Path(..., gt=0),
	conversation_id: int = Path(..., gt=0),
	limit: int = Query(500, ge=1, le=1000),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_business_permission_dep("crm", "view")),
) -> Dict[str, Any]:
	items = chat_svc.list_messages_agent(db, business_id, conversation_id, limit=limit)
	return success_response(data={"items": [_fmt(request, x) for x in items]}, request=request)


@router.post("/businesses/{business_id}/chat/conversations/{conversation_id}/messages")
@require_business_access("business_id")
async def post_chat_message_agent(
	request: Request,
	business_id: int = Path(..., gt=0),
	conversation_id: int = Path(..., gt=0),
	body: CrmChatAgentMessageCreate = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_business_permission_dep("crm", "write")),
) -> Dict[str, Any]:
	msg = await chat_svc.post_agent_message(
		db,
		business_id=business_id,
		conversation_id=conversation_id,
		body=body.body,
		user_id=ctx.get_user_id(),
		file_storage_id=body.file_storage_id,
	)
	return success_response(data=_fmt(request, msg), request=request, message="پیام ارسال شد")


@router.patch("/businesses/{business_id}/chat/conversations/{conversation_id}")
@require_business_access("business_id")
async def patch_chat_conversation(
	request: Request,
	business_id: int = Path(..., gt=0),
	conversation_id: int = Path(..., gt=0),
	body: CrmChatConversationPatch = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_business_permission_dep("crm", "write")),
) -> Dict[str, Any]:
	data = await chat_svc.patch_conversation_agent(
		db,
		business_id,
		conversation_id,
		status=body.status,
		assigned_to_user_id=body.assigned_to_user_id,
		lead_id=body.lead_id,
		person_id=body.person_id,
		acting_user_id=ctx.get_user_id(),
	)
	return success_response(data=_fmt(request, data), request=request, message="مکالمه به‌روز شد")
