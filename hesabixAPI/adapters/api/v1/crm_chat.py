# noqa: D100
"""API مدیریت چت وب CRM (ویجت، مکالمه، پاسخ عامل)."""
from __future__ import annotations

import logging
from typing import Any, Dict, Optional

from fastapi import APIRouter, Body, Depends, HTTPException, Path, Query, Request
from sqlalchemy.orm import Session

from adapters.api.v1.schema_models.crm_chat import (
	BusinessCrmSettingsUpdate,
	CrmChatWidgetCreate,
	CrmChatWidgetUpdate,
	CrmChatAgentMessageCreate,
	CrmChatAgentMessagePatch,
	CrmChatConversationPatch,
	CrmChatMarkReadBody,
)
from adapters.db.session import get_db
from app.core.auth_dependency import AuthContext, get_current_user
from app.core.permissions import require_business_access, require_business_permission_dep, require_crm_web_chat_dep
from app.core.responses import ApiError, format_datetime_fields, success_response
from app.services import basalam_integration_service as basalam_svc
from app.services import crm_chat_service as chat_svc

router = APIRouter(tags=["CRM — چت وب"])
logger = logging.getLogger(__name__)


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
		db,
		business_id,
		allow_web_chat_file_upload=body.allow_web_chat_file_upload,
		allow_web_chat_voice=body.allow_web_chat_voice,
	)
	return success_response(data=_fmt(request, chat_svc.business_crm_settings_to_dict(s)), request=request, message="CRM_CHAT_SETTINGS_SAVED")


@router.get("/businesses/{business_id}/chat/widgets")
@require_business_access("business_id")
async def list_chat_widgets(
	request: Request,
	business_id: int = Path(..., gt=0),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_crm_web_chat_dep("view")),
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
	_: None = Depends(require_crm_web_chat_dep("manage_widgets")),
) -> Dict[str, Any]:
	w = chat_svc.create_widget(
		db,
		business_id,
		body.name,
		body.allowed_origins,
		body.settings,
		body.is_active,
	)
	return success_response(data=_fmt(request, chat_svc.widget_to_dict(w)), request=request, message="CRM_CHAT_WIDGET_CREATED")


@router.patch("/businesses/{business_id}/chat/widgets/{widget_id}")
@require_business_access("business_id")
async def update_chat_widget(
	request: Request,
	business_id: int = Path(..., gt=0),
	widget_id: int = Path(..., gt=0),
	body: CrmChatWidgetUpdate = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_crm_web_chat_dep("manage_widgets")),
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
	return success_response(data=_fmt(request, chat_svc.widget_to_dict(w)), request=request, message="CRM_CHAT_WIDGET_UPDATED")


@router.get("/businesses/{business_id}/chat/conversations")
@require_business_access("business_id")
async def list_chat_conversations(
	request: Request,
	business_id: int = Path(..., gt=0),
	status: Optional[str] = Query(None),
	limit: int = Query(50, ge=1, le=200),
	offset: int = Query(0, ge=0),
	search: Optional[str] = Query(None, description="جستجو در نام، ایمیل، موبایل، URL صفه، یا شناسه مکالمه"),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_crm_web_chat_dep("view")),
) -> Dict[str, Any]:
	items, has_more = chat_svc.list_conversations_agent(
		db, business_id, status=status, limit=limit, offset=offset, search=search
	)
	return success_response(
		data={"items": [_fmt(request, x) for x in items], "has_more": has_more},
		request=request,
	)


@router.delete("/businesses/{business_id}/chat/conversations")
@require_business_access("business_id")
async def delete_chat_conversations_bulk(
	request: Request,
	business_id: int = Path(..., gt=0),
	status: Optional[str] = Query(
		None,
		description="اگر ارسال شود فقط مکالمات با این وضعیت (open|pending|resolved) حذف می‌شوند؛ در غیر این صورت همه",
	),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_crm_web_chat_dep("edit_conversations")),
) -> Dict[str, Any]:
	if status is not None and status not in ("open", "pending", "resolved"):
		raise HTTPException(status_code=422, detail="INVALID_STATUS")
	try:
		data = await chat_svc.delete_conversations_bulk_agent(db, business_id, status=status)
	except ApiError as exc:
		raise HTTPException(status_code=exc.status_code, detail=exc.detail) from exc
	return success_response(data=_fmt(request, data), request=request, message="CRM_CHAT_CONVERSATIONS_BULK_DELETED")


@router.delete("/businesses/{business_id}/chat/conversations/{conversation_id}")
@require_business_access("business_id")
async def delete_chat_conversation_one(
	request: Request,
	business_id: int = Path(..., gt=0),
	conversation_id: int = Path(..., gt=0),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_crm_web_chat_dep("edit_conversations")),
) -> Dict[str, Any]:
	try:
		data = await chat_svc.delete_conversation_agent(db, business_id, conversation_id)
	except ApiError as exc:
		raise HTTPException(status_code=exc.status_code, detail=exc.detail) from exc
	return success_response(data=_fmt(request, data), request=request, message="CRM_CHAT_CONVERSATION_DELETED")


@router.get("/businesses/{business_id}/chat/conversations/{conversation_id}/messages")
@require_business_access("business_id")
async def list_chat_messages_agent(
	request: Request,
	business_id: int = Path(..., gt=0),
	conversation_id: int = Path(..., gt=0),
	limit: int = Query(80, ge=1, le=1000),
	before_message_id: Optional[int] = Query(
		None, description="فقط پیام‌های با id کوچک‌تر (بارگذاری قدیمی‌تر)",
	),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_crm_web_chat_dep("view")),
) -> Dict[str, Any]:
	items, has_more_older = chat_svc.list_messages_agent(
		db, business_id, conversation_id, limit=limit, before_message_id=before_message_id
	)
	return success_response(
		data={"items": [_fmt(request, x) for x in items], "has_more_older": has_more_older},
		request=request,
	)


@router.post("/businesses/{business_id}/chat/conversations/{conversation_id}/read")
@require_business_access("business_id")
async def post_chat_conversation_read(
	request: Request,
	business_id: int = Path(..., gt=0),
	conversation_id: int = Path(..., gt=0),
	body: CrmChatMarkReadBody = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_crm_web_chat_dep("view")),
) -> Dict[str, Any]:
	try:
		data = await chat_svc.mark_messages_read_by_agent(
			db,
			business_id=business_id,
			conversation_id=conversation_id,
			up_to_message_id=body.up_to_message_id,
			reading_user=ctx.user,
		)
	except ApiError as exc:
		raise HTTPException(status_code=exc.status_code, detail=exc.detail) from exc
	return success_response(data=_fmt(request, data), request=request, message="")


@router.post("/businesses/{business_id}/chat/conversations/{conversation_id}/messages")
@require_business_access("business_id")
async def post_chat_message_agent(
	request: Request,
	business_id: int = Path(..., gt=0),
	conversation_id: int = Path(..., gt=0),
	body: CrmChatAgentMessageCreate = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_crm_web_chat_dep("reply")),
) -> Dict[str, Any]:
	msg = await chat_svc.post_agent_message(
		db,
		business_id=business_id,
		conversation_id=conversation_id,
		body=body.body,
		user_id=ctx.get_user_id(),
		file_storage_id=body.file_storage_id,
	)
	try:
		await basalam_svc.relay_agent_message_from_crm(
			db=db,
			business_id=business_id,
			conversation_id=conversation_id,
			user_id=ctx.get_user_id(),
			body=body.body,
			file_storage_id=body.file_storage_id,
		)
	except Exception:
		# ارسال پیام CRM نباید به دلیل خطای relay به باسلام fail شود.
		logger.exception(
			"crm basalam relay failed business_id=%s conversation_id=%s",
			business_id,
			conversation_id,
		)
	return success_response(data=_fmt(request, msg), request=request, message="CRM_CHAT_AGENT_MESSAGE_SENT")


@router.patch(
	"/businesses/{business_id}/chat/conversations/{conversation_id}/messages/{message_id}"
)
@require_business_access("business_id")
async def patch_chat_message_agent(
	request: Request,
	business_id: int = Path(..., gt=0),
	conversation_id: int = Path(..., gt=0),
	message_id: int = Path(..., gt=0),
	body: CrmChatAgentMessagePatch = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_crm_web_chat_dep("reply")),
) -> Dict[str, Any]:
	try:
		msg = await chat_svc.patch_agent_message(
			db,
			business_id=business_id,
			conversation_id=conversation_id,
			message_id=message_id,
			body=body.body,
		)
	except ApiError as exc:
		raise HTTPException(status_code=exc.status_code, detail=exc.detail) from exc
	return success_response(data=_fmt(request, msg), request=request, message="CRM_CHAT_AGENT_MESSAGE_UPDATED")


@router.delete(
	"/businesses/{business_id}/chat/conversations/{conversation_id}/messages/{message_id}"
)
@require_business_access("business_id")
async def delete_chat_message(
	request: Request,
	business_id: int = Path(..., gt=0),
	conversation_id: int = Path(..., gt=0),
	message_id: int = Path(..., gt=0),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_crm_web_chat_dep("delete_messages")),
) -> Dict[str, Any]:
	try:
		data = await chat_svc.delete_message_agent(db, business_id, conversation_id, message_id)
	except ApiError as exc:
		raise HTTPException(status_code=exc.status_code, detail=exc.detail) from exc
	return success_response(data=_fmt(request, data), request=request, message="CRM_CHAT_MESSAGE_DELETED")


@router.patch("/businesses/{business_id}/chat/conversations/{conversation_id}")
@require_business_access("business_id")
async def patch_chat_conversation(
	request: Request,
	business_id: int = Path(..., gt=0),
	conversation_id: int = Path(..., gt=0),
	body: CrmChatConversationPatch = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_crm_web_chat_dep("edit_conversations")),
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
	return success_response(data=_fmt(request, data), request=request, message="CRM_CHAT_CONVERSATION_UPDATED")
