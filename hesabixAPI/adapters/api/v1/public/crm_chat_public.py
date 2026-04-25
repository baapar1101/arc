# noqa: D100
"""API عمومی چت وب CRM (بدون ورود Hesabix؛ فقط با public_key ویجت و توکن بازدیدکننده)."""
from __future__ import annotations

from typing import Any, Dict, Optional

from fastapi import APIRouter, Body, Depends, HTTPException, Query, Request
from sqlalchemy.orm import Session

from adapters.api.v1.schema_models.crm_chat import (
	CrmChatConversationStartPublic,
	CrmChatVisitorMessageCreate,
)
from adapters.db.session import get_db
from app.core.responses import ApiError, format_datetime_fields, success_response
from app.services import crm_chat_service as chat_svc

router = APIRouter(tags=["عمومی — چت وب CRM"])


def _origin(request: Request) -> Optional[str]:
	return request.headers.get("Origin") or request.headers.get("Referer")


@router.post("/api/v1/public/crm-chat/conversations/start")
async def public_start_conversation(
	request: Request,
	body: CrmChatConversationStartPublic = Body(...),
	db: Session = Depends(get_db),
) -> Dict[str, Any]:
	try:
		data = await chat_svc.start_conversation_public(
			db,
			public_key=body.public_key,
			first_name=body.first_name,
			last_name=body.last_name,
			email=body.email,
			phone=body.phone,
			page_url=body.page_url,
			origin_header=_origin(request),
		)
	except ApiError as exc:
		raise HTTPException(status_code=exc.status_code, detail=exc.detail) from exc
	return success_response(
		data=format_datetime_fields(data, request),
		request=request,
		message="مکالمه آغاز شد؛ اکنون می‌توانید پیام بفرستید",
	)


@router.post("/api/v1/public/crm-chat/messages")
async def public_post_message(
	request: Request,
	body: CrmChatVisitorMessageCreate = Body(...),
	db: Session = Depends(get_db),
) -> Dict[str, Any]:
	try:
		msg = await chat_svc.post_visitor_message(
			db,
			visitor_token=body.visitor_token,
			conversation_id=body.conversation_id,
			body=body.body,
			origin_header=_origin(request),
		)
	except ApiError as exc:
		raise HTTPException(status_code=exc.status_code, detail=exc.detail) from exc
	return success_response(data=format_datetime_fields(msg, request), request=request, message="پیام ثبت شد")


@router.get("/api/v1/public/crm-chat/conversations/{conversation_id}/messages")
async def public_list_messages(
	request: Request,
	conversation_id: int,
	visitor_token: str = Query(..., min_length=16),
	limit: int = Query(100, ge=1, le=500),
	db: Session = Depends(get_db),
) -> Dict[str, Any]:
	try:
		items = chat_svc.list_messages_public(db, visitor_token, conversation_id, limit=limit)
	except ApiError as exc:
		raise HTTPException(status_code=exc.status_code, detail=exc.detail) from exc
	return success_response(
		data={"items": [format_datetime_fields(x, request) for x in items]},
		request=request,
	)
