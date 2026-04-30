# noqa: D100
"""منطق چت وب CRM: ویجت، مکالمه، پیام، تریگر ورک‌فلو."""
from __future__ import annotations

import hashlib
import logging
import re
import secrets
from datetime import datetime
from typing import Any, Dict, List, Optional
from urllib.parse import urlparse
from uuid import UUID

from sqlalchemy import and_, delete, desc, func, or_, select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from fastapi import HTTPException, UploadFile

from adapters.db.models.business import Business
from adapters.db.models.business_crm_settings import BusinessCrmSettings
from adapters.db.models.crm_chat import CrmChatConversation, CrmChatMessage, CrmChatWidget
from adapters.db.models.messenger_operator_session import MessengerOperatorSession
from adapters.db.models.file_storage import FileStorage
from adapters.db.models.user import User
from app.core.responses import ApiError
from app.services.crm_chat_realtime import crm_chat_realtime_manager
from app.services.file_storage_service import FileStorageService
from app.services.workflow.workflow_trigger_enrichment import build_crm_chat_visitor_message_trigger_enrichment
from app.services.workflow.workflow_trigger_service import trigger_workflows

logger = logging.getLogger(__name__)

_EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
_MAX_BODY = 8000


def _hash_visitor_token(token: str) -> str:
	return hashlib.sha256(token.encode("utf-8")).hexdigest()


def agent_display_name(user: User) -> str:
	"""نام نمایشی عامل برای ویجت و رویدادهای بلادرنگ."""
	parts = [p for p in (user.first_name or "", user.last_name or "") if p]
	s = " ".join(parts).strip()
	if s:
		return s
	if user.email:
		return user.email.strip()
	if user.mobile:
		return user.mobile.strip()
	return "پشتیبان"


def _validate_email(email: str) -> None:
	if not _EMAIL_RE.match((email or "").strip()):
		raise ApiError("CRM_CHAT_INVALID_EMAIL", "Invalid email address", http_status=422)


def _normalize_host_from_origin(origin: Optional[str]) -> Optional[str]:
	if not origin:
		return None
	try:
		p = urlparse(origin.strip())
		return (p.hostname or "").lower() or None
	except Exception:
		return None


def origin_allowed(widget: CrmChatWidget, origin_header: Optional[str]) -> bool:
	raw = widget.allowed_origins
	if not raw or not isinstance(raw, list):
		return True
	hosts = [str(x).strip().lower() for x in raw if str(x).strip()]
	if not hosts:
		return True
	oh = _normalize_host_from_origin(origin_header)
	if not oh:
		return False
	return oh in hosts


def _fire(
	db: Session,
	business_id: int,
	trigger_type: str,
	trigger_data: Dict[str, Any],
	user_id: Optional[int] = None,
) -> None:
	try:
		trigger_workflows(db, business_id, trigger_type, trigger_data, user_id)
	except Exception:
		logger.exception("crm chat workflow trigger failed type=%s business_id=%s", trigger_type, business_id)


def _visitor_message_workflow_payload(
	db: Session,
	business_id: int,
	c: CrmChatConversation,
	msg: CrmChatMessage,
	text: str,
	file_storage_id: Optional[str] = None,
) -> Dict[str, Any]:
	payload: Dict[str, Any] = {
		"conversation_id": c.id,
		"widget_id": c.widget_id,
		"message_id": msg.id,
		"body": text,
		"sender_role": "visitor",
	}
	if file_storage_id:
		payload["file_storage_id"] = file_storage_id
	payload.update(build_crm_chat_visitor_message_trigger_enrichment(db, business_id, c.id))
	return payload


def widget_to_dict(w: CrmChatWidget) -> Dict[str, Any]:
	return {
		"id": w.id,
		"business_id": w.business_id,
		"name": w.name,
		"public_key": w.public_key,
		"allowed_origins": w.allowed_origins or [],
		"settings": w.settings or {},
		"is_active": bool(w.is_active),
		"created_at": w.created_at,
		"updated_at": w.updated_at,
	}


def visitor_file_upload_effective_for_widget(db: Session, w: CrmChatWidget) -> bool:
	"""
	ارسال فایل توسط بازدیدکننده: ابتدا تنظیم کسب‌وکار، سپس settings ویجت
	(allow_visitor_file_upload == False برای غیرفعال کردن فقط این ویجت).
	"""
	s = get_or_create_crm_settings(db, w.business_id)
	if not s.allow_web_chat_file_upload:
		return False
	st = w.settings or {}
	if st.get("allow_visitor_file_upload") is False:
		return False
	return True


def visitor_voice_effective_for_widget(db: Session, w: CrmChatWidget) -> bool:
	"""پس از فعال بودن سطح کسب‌وکار، می‌توان با settings ویجت قطع کرد."""
	s = get_or_create_crm_settings(db, w.business_id)
	if not bool(getattr(s, "allow_web_chat_voice", False)):
		return False
	st = w.settings or {}
	if st.get("allow_visitor_voice") is False:
		return False
	return True


def _upload_likely_audio(*, content_type: Optional[str], filename: Optional[str]) -> bool:
	ct = (content_type or "").strip().lower()
	if ct.startswith("audio/"):
		return True
	fn = (filename or "").lower()
	for ext in (".webm", ".weba", ".ogg", ".oga", ".opus", ".mp3", ".m4a", ".aac", ".wav", ".flac"):
		if fn.endswith(ext):
			return True
	return False


def conversation_to_dict(c: CrmChatConversation) -> Dict[str, Any]:
	return {
		"id": c.id,
		"business_id": c.business_id,
		"widget_id": c.widget_id,
		"status": c.status,
		"visitor_first_name": c.visitor_first_name,
		"visitor_last_name": c.visitor_last_name,
		"visitor_email": c.visitor_email,
		"visitor_phone": c.visitor_phone,
		"page_url": c.page_url,
		"lead_id": c.lead_id,
		"person_id": c.person_id,
		"assigned_to_user_id": c.assigned_to_user_id,
		"last_message_at": c.last_message_at,
		"created_at": c.created_at,
		"updated_at": c.updated_at,
	}


def message_to_dict(m: CrmChatMessage) -> Dict[str, Any]:
	is_del = m.deleted_at is not None
	return {
		"id": m.id,
		"conversation_id": m.conversation_id,
		"sender_role": m.sender_role,
		"body": "" if is_del else (m.body or ""),
		"user_id": m.user_id,
		"file_storage_id": None if is_del else m.file_storage_id,
		"created_at": m.created_at,
		"edited_at": m.edited_at,
		"read_at": m.read_at,
		"deleted_at": m.deleted_at,
		"is_deleted": is_del,
	}


def _message_to_dict_enriched(db: Session, m: CrmChatMessage) -> Dict[str, Any]:
	d = message_to_dict(m)
	if m.deleted_at is not None:
		d["file"] = None
		return d
	if m.file_storage_id:
		fs = db.get(FileStorage, m.file_storage_id)
		if fs:
			d["file"] = {
				"id": str(fs.id),
				"original_name": fs.original_name,
				"file_size": fs.file_size,
				"mime_type": fs.mime_type,
			}
		else:
			d["file"] = None
	else:
		d["file"] = None
	if m.sender_role == "agent" and m.user_id:
		u = db.get(User, m.user_id)
		if u:
			d["sender_name"] = agent_display_name(u)
	return d


def get_or_create_crm_settings(db: Session, business_id: int) -> BusinessCrmSettings:
	row = db.get(BusinessCrmSettings, business_id)
	if not row:
		row = BusinessCrmSettings(
			business_id=business_id,
			allow_web_chat_file_upload=False,
			allow_web_chat_voice=False,
		)
		db.add(row)
		db.commit()
		db.refresh(row)
	return row


def business_crm_settings_to_dict(s: BusinessCrmSettings) -> Dict[str, Any]:
	return {
		"business_id": s.business_id,
		"allow_web_chat_file_upload": bool(s.allow_web_chat_file_upload),
		"allow_web_chat_voice": bool(getattr(s, "allow_web_chat_voice", False)),
		"updated_at": s.updated_at,
	}


def update_crm_business_settings(
	db: Session,
	business_id: int,
	*,
	allow_web_chat_file_upload: Optional[bool] = None,
	allow_web_chat_voice: Optional[bool] = None,
) -> BusinessCrmSettings:
	row = get_or_create_crm_settings(db, business_id)
	if allow_web_chat_file_upload is not None:
		row.allow_web_chat_file_upload = allow_web_chat_file_upload
	if allow_web_chat_voice is not None:
		row.allow_web_chat_voice = allow_web_chat_voice
	row.updated_at = datetime.utcnow()
	db.commit()
	db.refresh(row)
	return row


def _notify_business_crm_storage(db: Session, business_id: int, *, title: str, message: str) -> None:
	b = db.get(Business, business_id)
	if not b or b.owner_id is None:
		return
	try:
		from app.services.notification_service import NotificationService

		NotificationService(db).send(
			user_id=int(b.owner_id),
			event_key="system.generic",
			context={"subject": title, "message": message},
			preferred_channels=["inapp", "email"],
		)
	except Exception:
		logger.exception("notify business %s for crm file storage failed", business_id)


def _assert_crm_file_for_conversation(
	db: Session, *, business_id: int, conversation_id: int, file_id: str
) -> FileStorage:
	fs = db.get(FileStorage, file_id)
	if not fs or fs.business_id != business_id:
		raise ApiError("CRM_CHAT_FILE_NOT_FOUND", "File not found", http_status=404)
	if (fs.module_context or "") != "crm_web_chat":
		raise ApiError("CRM_CHAT_FILE_NOT_FOR_CHAT", "This file is not used for chat", http_status=422)
	if str(fs.context_id or "") != str(conversation_id):
		raise ApiError("CRM_CHAT_FILE_WRONG_CONVERSATION", "The file does not belong to this conversation", http_status=422)
	return fs


def get_widget_by_public_key(db: Session, public_key: str) -> CrmChatWidget:
	w = db.scalar(select(CrmChatWidget).where(CrmChatWidget.public_key == public_key.strip()))
	if not w or not w.is_active:
		raise ApiError("CRM_CHAT_WIDGET_INACTIVE", "Chat widget not found or inactive", http_status=404)
	return w


def list_widgets(db: Session, business_id: int) -> List[CrmChatWidget]:
	return list(
		db.scalars(
			select(CrmChatWidget).where(CrmChatWidget.business_id == business_id).order_by(CrmChatWidget.id.desc())
		).all()
	)


def create_widget(
	db: Session,
	business_id: int,
	name: str,
	allowed_origins: Optional[List[str]],
	settings: Optional[dict],
	is_active: bool,
) -> CrmChatWidget:
	pk = secrets.token_urlsafe(24).replace("-", "")[:48]
	w = CrmChatWidget(
		business_id=business_id,
		name=name.strip(),
		public_key=pk,
		allowed_origins=allowed_origins,
		settings=settings,
		is_active=is_active,
	)
	db.add(w)
	db.commit()
	db.refresh(w)
	return w


def update_widget(
	db: Session,
	business_id: int,
	widget_id: int,
	*,
	name: Optional[str] = None,
	allowed_origins: Optional[List[str]] = None,
	settings: Optional[dict] = None,
	is_active: Optional[bool] = None,
) -> CrmChatWidget:
	w = db.get(CrmChatWidget, widget_id)
	if not w or w.business_id != business_id:
		raise ApiError("CRM_CHAT_WIDGET_NOT_FOUND", "Widget not found", http_status=404)
	if name is not None:
		w.name = name.strip()
	if allowed_origins is not None:
		w.allowed_origins = allowed_origins
	if settings is not None:
		w.settings = settings
	if is_active is not None:
		w.is_active = is_active
	w.updated_at = datetime.utcnow()
	db.commit()
	db.refresh(w)
	return w


async def start_conversation_public(
	db: Session,
	*,
	public_key: str,
	first_name: str,
	last_name: str,
	email: str,
	phone: str,
	page_url: Optional[str],
	origin_header: Optional[str],
) -> Dict[str, Any]:
	w = get_widget_by_public_key(db, public_key)
	if not origin_allowed(w, origin_header):
		raise ApiError("CRM_CHAT_ORIGIN_NOT_ALLOWED", "The request origin is not allowed for this widget", http_status=403)
	email_st = (email or "").strip().lower()
	if email_st:
		_validate_email(email_st)
	else:
		email_st = ""
	fn = first_name.strip()
	ln = last_name.strip()
	ph = phone.strip()
	if len(fn) < 1 or len(ln) < 1:
		raise ApiError("CRM_CHAT_VISITOR_NAME_REQUIRED", "First and last name are required", http_status=422)
	if len(ph) < 5:
		raise ApiError("CRM_CHAT_PHONE_INVALID", "Enter a valid phone number", http_status=422)

	visitor_token = secrets.token_urlsafe(32)
	th = _hash_visitor_token(visitor_token)

	c = CrmChatConversation(
		business_id=w.business_id,
		widget_id=w.id,
		status="open",
		visitor_first_name=fn,
		visitor_last_name=ln,
		visitor_email=email_st,
		visitor_phone=ph,
		visitor_token_hash=th,
		page_url=(page_url or None) if page_url else None,
		last_message_at=None,
	)
	db.add(c)
	db.commit()
	db.refresh(c)

	start_trigger_payload: Dict[str, Any] = {
		"conversation_id": c.id,
		"widget_id": w.id,
		"visitor_first_name": fn,
		"visitor_last_name": ln,
		"visitor_email": c.visitor_email,
		"visitor_phone": ph,
		"page_url": c.page_url,
	}
	start_trigger_payload.update(
		build_crm_chat_visitor_message_trigger_enrichment(db, w.business_id, c.id)
	)
	_fire(db, w.business_id, "crm.chat.conversation.started", start_trigger_payload)

	await crm_chat_realtime_manager.broadcast_business(
		w.business_id,
		{
			"type": "crm_chat.event",
			"event": "conversation.started",
			"conversation": conversation_to_dict(c),
		},
	)

	return {
		"conversation_id": c.id,
		"visitor_token": visitor_token,
		"widget_id": w.id,
	}


def _get_conversation_by_visitor(db: Session, visitor_token: str, conversation_id: int) -> CrmChatConversation:
	th = _hash_visitor_token(visitor_token)
	c = db.scalar(
		select(CrmChatConversation).where(
			CrmChatConversation.id == conversation_id,
			CrmChatConversation.visitor_token_hash == th,
		)
	)
	if not c:
		raise ApiError("CRM_CHAT_CONVERSATION_NOT_FOUND", "Conversation not found", http_status=404)
	return c


_MAX_PAGE_URL_LEN = 2048


async def update_visitor_current_page_url(
	db: Session,
	*,
	visitor_token: str,
	conversation_id: int,
	page_url: str,
	origin_header: Optional[str],
) -> Dict[str, Any]:
	"""نشانی فعلی صفحهٔ مرورگر بازدیدکننده؛ پس از ذخیره، رویداد conversation.updated منتشر می‌شود."""
	c = _get_conversation_by_visitor(db, visitor_token, conversation_id)
	_assert_widget_origin(db, c, origin_header)
	raw = (page_url or "").strip()
	if not raw:
		raise ApiError("CRM_CHAT_PAGE_URL_INVALID", "page_url is required", http_status=422)
	if len(raw) > _MAX_PAGE_URL_LEN:
		raw = raw[:_MAX_PAGE_URL_LEN]
	if c.page_url == raw:
		return conversation_to_dict(c)
	c.page_url = raw
	c.updated_at = datetime.utcnow()
	db.commit()
	db.refresh(c)

	ev = {
		"type": "crm_chat.event",
		"event": "conversation.updated",
		"conversation": conversation_to_dict(c),
	}
	await crm_chat_realtime_manager.broadcast_conversation(c.id, ev)
	await crm_chat_realtime_manager.broadcast_business(c.business_id, ev)

	return conversation_to_dict(c)


def _assert_widget_origin(db: Session, c: CrmChatConversation, origin_header: Optional[str]) -> None:
	"""مبدأ درخواست باید با allowed_origins ویجت سازگار باشد (مثل ارسال پیام)."""
	w = db.get(CrmChatWidget, c.widget_id)
	if not w:
		raise ApiError("CRM_CHAT_WIDGET_NOT_FOUND", "Widget not found", http_status=404)
	if not origin_allowed(w, origin_header):
		raise ApiError("CRM_CHAT_ORIGIN_NOT_ALLOWED", "The request origin is not allowed for this widget", http_status=403)


def _get_conversation_business(db: Session, business_id: int, conversation_id: int) -> CrmChatConversation:
	c = db.get(CrmChatConversation, conversation_id)
	if not c or c.business_id != business_id:
		raise ApiError("CRM_CHAT_CONVERSATION_NOT_FOUND", "Conversation not found", http_status=404)
	return c


async def post_visitor_message(
	db: Session,
	*,
	visitor_token: str,
	conversation_id: int,
	body: str,
	origin_header: Optional[str],
) -> Dict[str, Any]:
	c = _get_conversation_by_visitor(db, visitor_token, conversation_id)
	_assert_widget_origin(db, c, origin_header)
	text = (body or "").strip()
	if not text or len(text) > _MAX_BODY:
		raise ApiError("CRM_CHAT_MESSAGE_BODY_INVALID", "Invalid message text", http_status=422)

	msg = CrmChatMessage(conversation_id=c.id, sender_role="visitor", body=text, user_id=None, file_storage_id=None)
	db.add(msg)
	c.last_message_at = datetime.utcnow()
	c.updated_at = datetime.utcnow()
	db.commit()
	db.refresh(msg)

	payload = {"type": "crm_chat.event", "event": "message.created", "message": _message_to_dict_enriched(db, msg)}
	await crm_chat_realtime_manager.broadcast_conversation(c.id, payload)
	await crm_chat_realtime_manager.broadcast_business(c.business_id, {**payload, "conversation_id": c.id})

	_fire(
		db,
		c.business_id,
		"crm.chat.message.received",
		_visitor_message_workflow_payload(db, c.business_id, c, msg, text),
	)

	return _message_to_dict_enriched(db, msg)


async def post_visitor_file(
	db: Session,
	*,
	visitor_token: str,
	conversation_id: int,
	caption: Optional[str],
	upload: UploadFile,
	origin_header: Optional[str],
) -> Dict[str, Any]:
	c = _get_conversation_by_visitor(db, visitor_token, conversation_id)
	_assert_widget_origin(db, c, origin_header)

	wgt = db.get(CrmChatWidget, c.widget_id)
	if not wgt:
		raise ApiError("CRM_CHAT_WIDGET_NOT_FOUND", "Widget not found", http_status=404)
	is_aud = _upload_likely_audio(content_type=getattr(upload, "content_type", None), filename=upload.filename)
	if is_aud:
		if not visitor_voice_effective_for_widget(db, wgt):
			bsettings = get_or_create_crm_settings(db, c.business_id)
			if not bool(getattr(bsettings, "allow_web_chat_voice", False)):
				raise ApiError(
					"CRM_VOICE_UPLOAD_DISABLED",
					"Voice messages are not enabled for web chat for this business.",
					http_status=403,
				)
			raise ApiError(
				"WIDGET_VOICE_UPLOAD_DISABLED",
				"Voice messages by visitors are disabled for this widget.",
				http_status=403,
			)
	elif not visitor_file_upload_effective_for_widget(db, wgt):
		bsettings = get_or_create_crm_settings(db, c.business_id)
		if not bsettings.allow_web_chat_file_upload:
			raise ApiError(
				"CRM_FILE_UPLOAD_DISABLED",
				"File upload is not enabled for web chat for this business.",
				http_status=403,
			)
		raise ApiError(
			"WIDGET_FILE_UPLOAD_DISABLED",
			"File upload by visitors is disabled for this widget.",
			http_status=403,
		)

	biz = db.get(Business, c.business_id)
	if not biz or biz.owner_id is None:
		raise ApiError("CRM_CHAT_BUSINESS_NOT_FOUND", "Business not found", http_status=404)
	owner_id = int(biz.owner_id)

	storage = FileStorageService(db)
	try:
		saved = await storage.upload_file(
			file=upload,
			user_id=owner_id,
			module_context="crm_web_chat",
			context_id=str(c.id),
			developer_data={
				"business_id": c.business_id,
				"conversation_id": c.id,
				"widget_id": wgt.id,
				"visitor": True,
			},
			is_temporary=False,
			expires_in_days=3650,
			business_id=c.business_id,
			check_storage_limit=True,
		)
	except HTTPException as e:
		detail = e.detail
		err_code = detail.get("error") if isinstance(detail, dict) else None
		if err_code in ("NO_ACTIVE_STORAGE_PLAN", "STORAGE_LIMIT_EXCEEDED"):
			_notify_business_crm_storage(
				db,
				c.business_id,
				title="CRM web chat: storage limit",
				message=(
					"A visitor tried to upload a file but the storage plan or quota does not allow it. "
					"Please review or upgrade your storage package."
				),
			)
		# پاسخ قابل فهم به بازدیدکننده
		if err_code == "NO_ACTIVE_STORAGE_PLAN":
			raise ApiError(
				"CRM_CHAT_FILE_NOT_AVAILABLE_GENERIC",
				"File upload is not available right now. Please try again later.",
				http_status=400,
				details={"storage_error": "no_plan"},
			) from None
		if err_code == "STORAGE_LIMIT_EXCEEDED":
			raise ApiError(
				"CRM_CHAT_FILE_NOT_AVAILABLE_QUOTA",
				"Not enough storage space; file upload is not available right now.",
				http_status=400,
				details={"storage_error": "quota"},
			) from None
		if err_code == "FILE_SIZE_EXCEEDED":
			msg_s = str(detail.get("message") if isinstance(detail, dict) else "File size is not allowed")
			raise ApiError("CRM_FILE_TOO_LARGE", msg_s, http_status=400) from None
		raise ApiError("CRM_FILE_UPLOAD_FAILED", "File upload failed.", http_status=400) from None

	fid = str(saved.get("file_id", ""))
	orig_name = saved.get("original_name") or "file"
	cap = (caption or "").strip()
	text = cap if cap else f"📎 {orig_name}"
	if len(text) > _MAX_BODY:
		raise ApiError("CRM_CHAT_CAPTION_TOO_LONG", "Caption is too long", http_status=422)

	msg = CrmChatMessage(
		conversation_id=c.id,
		sender_role="visitor",
		body=text,
		user_id=None,
		file_storage_id=fid,
	)
	db.add(msg)
	c.last_message_at = datetime.utcnow()
	c.updated_at = datetime.utcnow()
	db.commit()
	db.refresh(msg)

	payload = {"type": "crm_chat.event", "event": "message.created", "message": _message_to_dict_enriched(db, msg)}
	await crm_chat_realtime_manager.broadcast_conversation(c.id, payload)
	await crm_chat_realtime_manager.broadcast_business(c.business_id, {**payload, "conversation_id": c.id})

	_fire(
		db,
		c.business_id,
		"crm.chat.message.received",
		_visitor_message_workflow_payload(db, c.business_id, c, msg, text, file_storage_id=fid),
	)

	return _message_to_dict_enriched(db, msg)


async def post_agent_message(
	db: Session,
	*,
	business_id: int,
	conversation_id: int,
	body: Optional[str],
	user_id: int,
	file_storage_id: Optional[str] = None,
	fire_workflow_trigger_message_sent: bool = True,
	automation_context: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
	c = _get_conversation_business(db, business_id, conversation_id)
	fid: Optional[str] = None
	text_combined: str
	if file_storage_id:
		fs = _assert_crm_file_for_conversation(
			db, business_id=business_id, conversation_id=conversation_id, file_id=str(file_storage_id).strip()
		)
		mime_ag = (fs.mime_type or "").strip().lower()
		if mime_ag.startswith("audio/"):
			sv = get_or_create_crm_settings(db, business_id)
			if not bool(getattr(sv, "allow_web_chat_voice", False)):
				raise ApiError(
					"CRM_VOICE_UPLOAD_DISABLED",
					"Voice messages are not enabled for web chat for this business.",
					http_status=403,
				)
		fid = str(fs.id)
		cap = (body or "").strip()
		bname = cap if cap else f"📎 {fs.original_name or 'file'}"
		if len(bname) > _MAX_BODY:
			raise ApiError("CRM_CHAT_MESSAGE_BODY_INVALID", "Invalid message text", http_status=422)
		text_combined = bname
	else:
		text = (body or "").strip()
		if not text or len(text) > _MAX_BODY:
			raise ApiError("CRM_CHAT_MESSAGE_BODY_INVALID", "Invalid message text", http_status=422)
		text_combined = text

	msg = CrmChatMessage(
		conversation_id=c.id,
		sender_role="agent",
		body=text_combined,
		user_id=user_id,
		file_storage_id=fid,
	)
	db.add(msg)
	c.last_message_at = datetime.utcnow()
	c.updated_at = datetime.utcnow()
	db.commit()
	db.refresh(msg)

	payload = {"type": "crm_chat.event", "event": "message.created", "message": _message_to_dict_enriched(db, msg)}
	await crm_chat_realtime_manager.broadcast_conversation(c.id, payload)
	await crm_chat_realtime_manager.broadcast_business(c.business_id, {**payload, "conversation_id": c.id})

	if fire_workflow_trigger_message_sent:
		sent_payload: Dict[str, Any] = {
			"conversation_id": c.id,
			"widget_id": c.widget_id,
			"message_id": msg.id,
			"body": text_combined,
			"sender_role": "agent",
			"agent_user_id": user_id,
		}
		if automation_context:
			sent_payload.update(automation_context)
		_fire(db, business_id, "crm.chat.message.sent", sent_payload, user_id)

	return _message_to_dict_enriched(db, msg)


async def download_visitor_crm_file(
	db: Session,
	*,
	visitor_token: str,
	conversation_id: int,
	file_id: str,
	origin_header: Optional[str] = None,
) -> Dict[str, Any]:
	c = _get_conversation_by_visitor(db, visitor_token, conversation_id)
	_assert_widget_origin(db, c, origin_header)
	m = db.scalar(
		select(CrmChatMessage)
		.where(
			CrmChatMessage.conversation_id == c.id,
			CrmChatMessage.file_storage_id == file_id,
		)
		.limit(1)
	)
	if m is None:
		raise ApiError("CRM_CHAT_FILE_NOT_IN_CONVERSATION", "File not found in this conversation", http_status=404)
	storage = FileStorageService(db)
	return await storage.download_file(UUID(str(file_id)))


def list_messages_public(
	db: Session,
	visitor_token: str,
	conversation_id: int,
	limit: int = 100,
	origin_header: Optional[str] = None,
	before_message_id: Optional[int] = None,
) -> List[Dict[str, Any]]:
	c = _get_conversation_by_visitor(db, visitor_token, conversation_id)
	_assert_widget_origin(db, c, origin_header)
	lim = min(max(limit, 1), 500)
	base = and_(
		CrmChatMessage.conversation_id == c.id,
		CrmChatMessage.deleted_at.is_(None),
	)
	if before_message_id is not None:
		base = and_(base, CrmChatMessage.id < before_message_id)
	q = (
		select(CrmChatMessage)
		.where(base)
		.order_by(CrmChatMessage.id.desc())
		.limit(lim)
	)
	rows = list(db.scalars(q).all())
	rows.reverse()
	return [_message_to_dict_enriched(db, m) for m in rows]


def list_messages_agent(
	db: Session,
	business_id: int,
	conversation_id: int,
	limit: int = 80,
	before_message_id: Optional[int] = None,
) -> tuple[List[Dict[str, Any]], bool]:
	"""آخرین پیام‌ها (نزدیک‌تر به حال)؛ با before_message_id بارگذاری قدیمی‌تر. has_more_older اگر پیام قدیمی‌تر وجود داشته باشد."""
	c = _get_conversation_business(db, business_id, conversation_id)
	lim = min(max(limit, 1), 1000)
	base = CrmChatMessage.conversation_id == c.id
	if before_message_id is not None:
		base = and_(base, CrmChatMessage.id < before_message_id)
	q = (
		select(CrmChatMessage)
		.where(base)
		.order_by(CrmChatMessage.id.desc())
		.limit(lim + 1)
	)
	rows = list(db.scalars(q).all())
	has_more_older = len(rows) > lim
	rows = rows[:lim]
	rows.reverse()
	return ([_message_to_dict_enriched(db, m) for m in rows], has_more_older)


def list_conversations_agent(
	db: Session,
	business_id: int,
	*,
	status: Optional[str] = None,
	limit: int = 50,
	offset: int = 0,
	search: Optional[str] = None,
) -> tuple[List[Dict[str, Any]], bool]:
	sort_ts = func.coalesce(CrmChatConversation.last_message_at, CrmChatConversation.created_at)
	lim = min(max(limit, 1), 200)
	q = select(CrmChatConversation).where(CrmChatConversation.business_id == business_id)
	if status:
		q = q.where(CrmChatConversation.status == status)
	term2 = (search or "").strip()
	if term2:
		pat2 = f"%{term2}%"
		id_m = int(term2) if term2.isdigit() else None
		conds: List[Any] = [
			CrmChatConversation.visitor_first_name.ilike(pat2),
			CrmChatConversation.visitor_last_name.ilike(pat2),
			CrmChatConversation.visitor_email.ilike(pat2),
			CrmChatConversation.visitor_phone.ilike(pat2),
			CrmChatConversation.page_url.ilike(pat2),
		]
		if id_m is not None:
			conds.append(CrmChatConversation.id == id_m)
		q = q.where(or_(*conds))
	q = q.order_by(desc(sort_ts), desc(CrmChatConversation.id)).limit(lim + 1).offset(max(offset, 0))
	rows = list(db.scalars(q).all())
	has_more = len(rows) > lim
	rows = rows[:lim]
	return ([conversation_to_dict(c) for c in rows], has_more)


async def delete_message_agent(
	db: Session,
	business_id: int,
	conversation_id: int,
	message_id: int,
) -> Dict[str, Any]:
	c = _get_conversation_business(db, business_id, conversation_id)
	m = db.get(CrmChatMessage, message_id)
	if not m or m.conversation_id != c.id:
		raise ApiError("CRM_CHAT_MESSAGE_NOT_FOUND", "Message not found", http_status=404)
	if m.deleted_at is not None:
		return {"id": m.id, "deleted": True}
	m.deleted_at = datetime.utcnow()
	m.body = ""
	m.file_storage_id = None
	db.commit()
	db.refresh(m)
	payload = {
		"type": "crm_chat.event",
		"event": "message.deleted",
		"conversation_id": c.id,
		"message_id": m.id,
	}
	await crm_chat_realtime_manager.broadcast_conversation(c.id, payload)
	await crm_chat_realtime_manager.broadcast_business(c.business_id, {**payload, "conversation_id": c.id})
	return {"id": m.id, "deleted": True}


async def patch_agent_message(
	db: Session,
	business_id: int,
	conversation_id: int,
	message_id: int,
	*,
	body: str,
) -> Dict[str, Any]:
	c = _get_conversation_business(db, business_id, conversation_id)
	m = db.get(CrmChatMessage, message_id)
	if not m or m.conversation_id != c.id:
		raise ApiError("CRM_CHAT_MESSAGE_NOT_FOUND", "Message not found", http_status=404)
	if m.deleted_at is not None:
		raise ApiError("CRM_CHAT_MESSAGE_NOT_FOUND", "Message not found", http_status=404)
	if m.sender_role != "agent":
		raise ApiError("CRM_CHAT_MESSAGE_EDIT_DENIED", "Only agent messages can be edited", http_status=422)
	text = (body or "").strip()
	if not text and not m.file_storage_id:
		raise ApiError("CRM_CHAT_MESSAGE_BODY_INVALID", "Invalid message text", http_status=422)
	if len(text) > _MAX_BODY:
		raise ApiError("CRM_CHAT_MESSAGE_BODY_INVALID", "Invalid message text", http_status=422)
	m.body = text
	m.edited_at = datetime.utcnow()
	db.commit()
	db.refresh(m)
	payload = {"type": "crm_chat.event", "event": "message.updated", "message": _message_to_dict_enriched(db, m)}
	await crm_chat_realtime_manager.broadcast_conversation(c.id, payload)
	await crm_chat_realtime_manager.broadcast_business(c.business_id, {**payload, "conversation_id": c.id})
	return _message_to_dict_enriched(db, m)


def _clear_messenger_sessions_for_conversation(db: Session, conversation_id: int) -> None:
	"""جلوگیری از خطای FK هنگام حذف مکالمه (دیتابیسهای بدون/ondelete ناسازگار)."""
	db.execute(
		update(MessengerOperatorSession)
		.where(MessengerOperatorSession.active_conversation_id == conversation_id)
		.values(active_conversation_id=None)
	)


async def delete_conversation_agent(
	db: Session,
	business_id: int,
	conversation_id: int,
) -> Dict[str, Any]:
	c = _get_conversation_business(db, business_id, conversation_id)
	cid = c.id
	bid = c.business_id
	_clear_messenger_sessions_for_conversation(db, cid)
	db.delete(c)
	try:
		db.commit()
	except IntegrityError:
		db.rollback()
		logger.exception(
			"crm chat delete conversation failed integrity business_id=%s conversation_id=%s",
			business_id,
			conversation_id,
		)
		raise ApiError(
			"CRM_CHAT_CONVERSATION_DELETE_FAILED",
			"Could not delete conversation due to database constraints.",
			http_status=409,
		) from None
	ev = {
		"type": "crm_chat.event",
		"event": "conversation.deleted",
		"conversation_id": cid,
		"business_id": bid,
	}
	await crm_chat_realtime_manager.broadcast_conversation(cid, ev)
	await crm_chat_realtime_manager.broadcast_business(bid, ev)
	return {"id": cid, "deleted": True}


async def delete_conversations_bulk_agent(
	db: Session,
	business_id: int,
	*,
	status: Optional[str] = None,
) -> Dict[str, Any]:
	"""حذف دسته‌جمعی مکالمه‌ها؛ در صورت ارسال status فقط همان وضعیت. پیام‌ها با CASCADE حذف می‌شوند."""
	if status is not None and status not in ("open", "pending", "resolved"):
		raise ApiError(
			"CRM_CHAT_CONVERSATION_STATUS_INVALID",
			"Invalid status",
			http_status=422,
		)
	filters = [CrmChatConversation.business_id == business_id]
	if status:
		filters.append(CrmChatConversation.status == status)
	base = and_(*filters)
	cnt_q = select(func.count()).select_from(CrmChatConversation).where(base)
	total = int(db.scalar(cnt_q) or 0)
	if total == 0:
		return {"deleted": 0}
	conv_ids_subq = select(CrmChatConversation.id).where(base)
	db.execute(
		update(MessengerOperatorSession)
		.where(MessengerOperatorSession.active_conversation_id.in_(conv_ids_subq))
		.values(active_conversation_id=None)
	)
	try:
		db.execute(delete(CrmChatConversation).where(base))
		db.commit()
	except IntegrityError:
		db.rollback()
		logger.exception(
			"crm chat bulk delete conversations failed integrity business_id=%s status=%s",
			business_id,
			status,
		)
		raise ApiError(
			"CRM_CHAT_CONVERSATIONS_BULK_DELETE_FAILED",
			"Could not delete conversations due to database constraints.",
			http_status=409,
		) from None
	ev = {
		"type": "crm_chat.event",
		"event": "conversations.bulk_deleted",
		"business_id": business_id,
		"count": total,
		"status_filter": status,
	}
	await crm_chat_realtime_manager.broadcast_business(business_id, ev)
	return {"deleted": total}


async def patch_conversation_agent(
	db: Session,
	business_id: int,
	conversation_id: int,
	*,
	status: Optional[str] = None,
	assigned_to_user_id: Optional[int] = None,
	lead_id: Optional[int] = None,
	person_id: Optional[int] = None,
	acting_user_id: Optional[int] = None,
) -> Dict[str, Any]:
	c = _get_conversation_business(db, business_id, conversation_id)
	old_assignee = c.assigned_to_user_id
	old_status = c.status

	if status is not None:
		if status not in ("open", "pending", "resolved"):
			raise ApiError("CRM_CHAT_CONVERSATION_STATUS_INVALID", "Invalid status", http_status=422)
		c.status = status
	if assigned_to_user_id is not None:
		c.assigned_to_user_id = assigned_to_user_id
	if lead_id is not None:
		c.lead_id = lead_id
	if person_id is not None:
		c.person_id = person_id
	c.updated_at = datetime.utcnow()
	db.commit()
	db.refresh(c)

	if assigned_to_user_id is not None and old_assignee != c.assigned_to_user_id:
		_fire(
			db,
			business_id,
			"crm.chat.conversation.assigned",
			{
				"conversation_id": c.id,
				"widget_id": c.widget_id,
				"old_assigned_to_user_id": old_assignee,
				"new_assigned_to_user_id": c.assigned_to_user_id,
			},
			acting_user_id,
		)
	if status is not None and old_status != c.status:
		if c.status == "resolved":
			_fire(
				db,
				business_id,
				"crm.chat.conversation.resolved",
				{"conversation_id": c.id, "widget_id": c.widget_id},
				acting_user_id,
			)
		elif old_status == "resolved" and c.status != "resolved":
			_fire(
				db,
				business_id,
				"crm.chat.conversation.reopened",
				{
					"conversation_id": c.id,
					"widget_id": c.widget_id,
					"old_status": old_status,
					"new_status": c.status,
				},
				acting_user_id,
			)

	ev = {
		"type": "crm_chat.event",
		"event": "conversation.updated",
		"conversation": conversation_to_dict(c),
	}
	await crm_chat_realtime_manager.broadcast_conversation(c.id, ev)
	await crm_chat_realtime_manager.broadcast_business(c.business_id, ev)

	return conversation_to_dict(c)


async def broadcast_typing(
	conversation_id: int,
	business_id: int,
	*,
	from_role: str,
	active: bool,
	actor_name: Optional[str] = None,
) -> None:
	payload: Dict[str, Any] = {
		"type": "crm_chat.event",
		"event": "typing",
		"conversation_id": conversation_id,
		"from_role": from_role,
		"active": bool(active),
	}
	if actor_name:
		payload["actor_name"] = actor_name
	await crm_chat_realtime_manager.broadcast_conversation(conversation_id, payload)
	await crm_chat_realtime_manager.broadcast_business(business_id, {**payload, "conversation_id": conversation_id})


async def broadcast_agent_joined(
	conversation_id: int,
	business_id: int,
	*,
	agent_user_id: int,
	agent_name: str,
) -> None:
	payload: Dict[str, Any] = {
		"type": "crm_chat.event",
		"event": "agent.joined",
		"conversation_id": conversation_id,
		"agent": {"id": agent_user_id, "name": agent_name},
	}
	await crm_chat_realtime_manager.broadcast_conversation(conversation_id, payload)
	await crm_chat_realtime_manager.broadcast_business(business_id, {**payload, "conversation_id": conversation_id})


async def _broadcast_messages_read(
	conversation_id: int,
	business_id: int,
	*,
	message_ids: List[int],
	read_at: datetime,
	reader_role: str,
) -> None:
	if not message_ids:
		return
	payload: Dict[str, Any] = {
		"type": "crm_chat.event",
		"event": "messages.read",
		"conversation_id": conversation_id,
		"message_ids": message_ids,
		"read_at": read_at,
		"reader_role": reader_role,
	}
	await crm_chat_realtime_manager.broadcast_conversation(conversation_id, payload)
	await crm_chat_realtime_manager.broadcast_business(
		business_id, {**payload, "conversation_id": conversation_id}
	)


async def mark_messages_read_by_visitor(
	db: Session,
	*,
	visitor_token: str,
	conversation_id: int,
	up_to_message_id: int,
	origin_header: Optional[str],
) -> Dict[str, Any]:
	"""بازدیدکننده پیام‌های عامل را تا شناسه داده‌شده «خوانده» علامت می‌زند."""
	c = _get_conversation_by_visitor(db, visitor_token, conversation_id)
	_assert_widget_origin(db, c, origin_header)
	if up_to_message_id < 1:
		raise ApiError("VALIDATION_ERROR", "Invalid message id", http_status=422)
	msg_ids = list(
		db.scalars(
			select(CrmChatMessage.id)
			.where(
				CrmChatMessage.conversation_id == c.id,
				CrmChatMessage.id <= up_to_message_id,
				CrmChatMessage.sender_role == "agent",
				CrmChatMessage.read_at.is_(None),
			)
		)
		.all()
	)
	if not msg_ids:
		return {"updated": 0, "message_ids": [], "read_at": None}
	now = datetime.utcnow()
	db.execute(update(CrmChatMessage).where(CrmChatMessage.id.in_(msg_ids)).values(read_at=now))
	db.commit()
	await _broadcast_messages_read(
		c.id, c.business_id, message_ids=msg_ids, read_at=now, reader_role="visitor"
	)
	return {"updated": len(msg_ids), "message_ids": msg_ids, "read_at": now}


async def mark_messages_read_by_agent(
	db: Session,
	*,
	business_id: int,
	conversation_id: int,
	up_to_message_id: int,
) -> Dict[str, Any]:
	"""عامل CRM پیام‌های بازدیدکننده را تا شناسه داده‌شده «خوانده» علامت می‌زند."""
	c = _get_conversation_business(db, business_id, conversation_id)
	if up_to_message_id < 1:
		raise ApiError("VALIDATION_ERROR", "Invalid message id", http_status=422)
	msg_ids = list(
		db.scalars(
			select(CrmChatMessage.id)
			.where(
				CrmChatMessage.conversation_id == c.id,
				CrmChatMessage.id <= up_to_message_id,
				CrmChatMessage.sender_role == "visitor",
				CrmChatMessage.read_at.is_(None),
			)
		)
		.all()
	)
	if not msg_ids:
		return {"updated": 0, "message_ids": [], "read_at": None}
	now = datetime.utcnow()
	db.execute(update(CrmChatMessage).where(CrmChatMessage.id.in_(msg_ids)).values(read_at=now))
	db.commit()
	await _broadcast_messages_read(
		c.id, c.business_id, message_ids=msg_ids, read_at=now, reader_role="agent"
	)
	return {"updated": len(msg_ids), "message_ids": msg_ids, "read_at": now}
