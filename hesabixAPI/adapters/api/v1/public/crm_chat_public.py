# noqa: D100
"""API عمومی چت وب CRM (بدون ورود Hesabix؛ فقط با public_key ویجت و توکن بازدیدکننده)."""
from __future__ import annotations

import io
from typing import Any, Dict, Optional

from fastapi import APIRouter, Body, Depends, File, Form, HTTPException, Header, Query, Request, UploadFile, status
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session

from adapters.api.v1.schema_models.crm_chat import (
	CrmChatConversationStartPublic,
	CrmChatMarkReadBody,
	CrmChatVisitorMessageCreate,
	CrmChatVisitorPageUrlPatch,
)
from adapters.db.session import get_db
from app.core.i18n import get_request_translator
from app.core.responses import ApiError, format_datetime_fields, success_response
from app.services import crm_chat_service as chat_svc

router = APIRouter(tags=["عمومی — چت وب CRM"])


def _origin(request: Request) -> Optional[str]:
	return request.headers.get("Origin") or request.headers.get("Referer")


def _resolve_public_visitor_token(
	request: Request,
	authorization: Optional[str],
	x_visitor_token: Optional[str],
	visitor_token_query: Optional[str],
) -> str:
	"""
	الویت: X-Visitor-Token، سپس Authorization: Bearer، سپس ?visitor_token (سازگاری قدیمی).
	"""
	if x_visitor_token:
		t = x_visitor_token.strip()
		if len(t) >= 16:
			return t
	if authorization:
		low = authorization.strip()
		if low.lower().startswith("bearer "):
			t = low[7:].strip()
			if len(t) >= 16:
				return t
	if visitor_token_query:
		tq = visitor_token_query.strip()
		if len(tq) >= 16:
			return tq
	tr = get_request_translator(request)
	raise HTTPException(
		status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
		detail={
			"success": False,
			"error": {
				"code": "CRM_CHAT_PUBLIC_VISITOR_TOKEN_REQUIRED",
				"message": tr.t(
					"CRM_CHAT_PUBLIC_VISITOR_TOKEN_REQUIRED",
					default=(
						"Visitor token is required. Send X-Visitor-Token or Authorization: Bearer, "
						"or the legacy visitor_token query parameter."
					),
				),
			},
		},
	)


@router.get("/api/v1/public/crm-chat/widget-options")
async def public_widget_options(
	request: Request,
	public_key: str = Query(..., min_length=8, max_length=64),
	db: Session = Depends(get_db),
) -> Dict[str, Any]:
	"""گزینه‌های نمایشی ویجت برای کلاینت بدون لاگین (هم‌راستا با تنظیمات CRM کسب‌وکار)."""
	try:
		w = chat_svc.get_widget_by_public_key(db, public_key.strip())
	except ApiError as exc:
		raise HTTPException(status_code=exc.status_code, detail=exc.detail) from exc
	allow = chat_svc.visitor_file_upload_effective_for_widget(db, w)
	return success_response(
		data={"allow_file_upload": allow},
		request=request,
		message="",
	)


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
		message="CRM_CHAT_PUBLIC_CONVERSATION_STARTED",
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
	return success_response(data=format_datetime_fields(msg, request), request=request, message="CRM_CHAT_PUBLIC_MESSAGE_RECORDED")


@router.get("/api/v1/public/crm-chat/conversations/{conversation_id}/messages")
async def public_list_messages(
	request: Request,
	conversation_id: int,
	authorization: Optional[str] = Header(default=None),
	x_visitor_token: Optional[str] = Header(default=None, alias="X-Visitor-Token", convert_underscores=False),
	visitor_token: Optional[str] = Query(
		default=None,
		description="(قدیمی) اگر هدر ارسال نمی‌کنید",
	),
	limit: int = Query(100, ge=1, le=500),
	before_message_id: Optional[int] = Query(
		None,
		description="بارگذاری پیام‌های قدیمی‌تر (id کوچک‌تر از این مقدار)",
	),
	db: Session = Depends(get_db),
) -> Dict[str, Any]:
	tok = _resolve_public_visitor_token(request, authorization, x_visitor_token, visitor_token)
	try:
		items = chat_svc.list_messages_public(
			db,
			tok,
			conversation_id,
			limit=limit,
			origin_header=_origin(request),
			before_message_id=before_message_id,
		)
	except ApiError as exc:
		raise HTTPException(status_code=exc.status_code, detail=exc.detail) from exc
	return success_response(
		data={"items": [format_datetime_fields(x, request) for x in items]},
		request=request,
	)


@router.patch("/api/v1/public/crm-chat/conversations/{conversation_id}/current-page")
async def public_patch_visitor_current_page(
	request: Request,
	conversation_id: int,
	body: CrmChatVisitorPageUrlPatch = Body(...),
	authorization: Optional[str] = Header(default=None),
	x_visitor_token: Optional[str] = Header(default=None, alias="X-Visitor-Token", convert_underscores=False),
	visitor_token: Optional[str] = Query(
		default=None,
		description="(قدیمی) اگر هدر ارسال نمی‌کنید",
	),
	db: Session = Depends(get_db),
) -> Dict[str, Any]:
	"""به‌روزرسانی URL صفحهٔ فعلی بازدیدکننده (ویجت وب؛ برای نمایش زنده نزد اپراتور)."""
	tok = _resolve_public_visitor_token(request, authorization, x_visitor_token, visitor_token)
	try:
		data = await chat_svc.update_visitor_current_page_url(
			db,
			visitor_token=tok,
			conversation_id=conversation_id,
			page_url=body.page_url,
			origin_header=_origin(request),
		)
	except ApiError as exc:
		raise HTTPException(status_code=exc.status_code, detail=exc.detail) from exc
	return success_response(
		data=format_datetime_fields(data, request),
		request=request,
		message="CRM_CHAT_PUBLIC_PAGE_URL_UPDATED",
	)


@router.post("/api/v1/public/crm-chat/conversations/{conversation_id}/read")
async def public_mark_messages_read(
	request: Request,
	conversation_id: int,
	body: CrmChatMarkReadBody = Body(...),
	authorization: Optional[str] = Header(default=None),
	x_visitor_token: Optional[str] = Header(default=None, alias="X-Visitor-Token", convert_underscores=False),
	visitor_token: Optional[str] = Query(
		default=None,
		description="(قدیمی) اگر هدر ارسال نمی‌کنید",
	),
	db: Session = Depends(get_db),
) -> Dict[str, Any]:
	tok = _resolve_public_visitor_token(request, authorization, x_visitor_token, visitor_token)
	try:
		data = await chat_svc.mark_messages_read_by_visitor(
			db,
			visitor_token=tok,
			conversation_id=conversation_id,
			up_to_message_id=body.up_to_message_id,
			origin_header=_origin(request),
		)
	except ApiError as exc:
		raise HTTPException(status_code=exc.status_code, detail=exc.detail) from exc
	return success_response(
		data=format_datetime_fields(data, request),
		request=request,
		message="",
	)


@router.post("/api/v1/public/crm-chat/messages/file")
async def public_post_message_file(
	request: Request,
	visitor_token: str = Form(..., min_length=16),
	conversation_id: int = Form(..., gt=0),
	caption: str = Form(""),
	file: UploadFile = File(...),
	db: Session = Depends(get_db),
) -> Dict[str, Any]:
	"""ارسال فایل توسط بازدیدکننده (پس از فعال‌سازی در تنظیمات CRM کسب‌وکار)."""
	try:
		msg = await chat_svc.post_visitor_file(
			db,
			visitor_token=visitor_token,
			conversation_id=conversation_id,
			caption=(caption or "").strip() or None,
			upload=file,
			origin_header=_origin(request),
		)
	except ApiError as exc:
		raise HTTPException(status_code=exc.status_code, detail=exc.detail) from exc
	return success_response(data=format_datetime_fields(msg, request), request=request, message="CRM_CHAT_PUBLIC_FILE_RECORDED")


@router.get("/api/v1/public/crm-chat/conversations/{conversation_id}/files/{file_id}/download")
async def public_download_crm_file(
	request: Request,
	conversation_id: int,
	file_id: str,
	authorization: Optional[str] = Header(default=None),
	x_visitor_token: Optional[str] = Header(default=None, alias="X-Visitor-Token", convert_underscores=False),
	visitor_token: Optional[str] = Query(
		default=None,
		description="(قدیمی) اگر هدر ارسال نمی‌کنید",
	),
	db: Session = Depends(get_db),
):
	"""دانلود فایل ضمیمه برای بازدیدکننده (همان مکالمه)."""
	tok = _resolve_public_visitor_token(request, authorization, x_visitor_token, visitor_token)
	try:
		data = await chat_svc.download_visitor_crm_file(
			db,
			visitor_token=tok,
			conversation_id=conversation_id,
			file_id=file_id,
			origin_header=_origin(request),
		)
	except ApiError as exc:
		raise HTTPException(status_code=exc.status_code, detail=exc.detail) from exc
	filename = data.get("filename") or "file"
	return StreamingResponse(
		io.BytesIO(data["content"]),
		media_type=data.get("mime_type") or "application/octet-stream",
		headers={"Content-Disposition": f'attachment; filename="{filename}"'},
	)
