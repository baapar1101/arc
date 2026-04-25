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

from sqlalchemy import desc, func, select
from sqlalchemy.orm import Session

from fastapi import HTTPException, UploadFile

from adapters.db.models.business import Business
from adapters.db.models.business_crm_settings import BusinessCrmSettings
from adapters.db.models.crm_chat import CrmChatConversation, CrmChatMessage, CrmChatWidget
from adapters.db.models.file_storage import FileStorage
from app.core.responses import ApiError
from app.services.crm_chat_realtime import crm_chat_realtime_manager
from app.services.file_storage_service import FileStorageService
from app.services.workflow.workflow_trigger_service import trigger_workflows

logger = logging.getLogger(__name__)

_EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
_MAX_BODY = 8000


def _hash_visitor_token(token: str) -> str:
	return hashlib.sha256(token.encode("utf-8")).hexdigest()


def _validate_email(email: str) -> None:
	if not _EMAIL_RE.match((email or "").strip()):
		raise ApiError("VALIDATION_ERROR", "ایمیل معتبر نیست", http_status=422)


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
	return {
		"id": m.id,
		"conversation_id": m.conversation_id,
		"sender_role": m.sender_role,
		"body": m.body,
		"user_id": m.user_id,
		"file_storage_id": m.file_storage_id,
		"created_at": m.created_at,
	}


def _message_to_dict_enriched(db: Session, m: CrmChatMessage) -> Dict[str, Any]:
	d = message_to_dict(m)
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
	return d


def get_or_create_crm_settings(db: Session, business_id: int) -> BusinessCrmSettings:
	row = db.get(BusinessCrmSettings, business_id)
	if not row:
		row = BusinessCrmSettings(business_id=business_id, allow_web_chat_file_upload=False)
		db.add(row)
		db.commit()
		db.refresh(row)
	return row


def business_crm_settings_to_dict(s: BusinessCrmSettings) -> Dict[str, Any]:
	return {
		"business_id": s.business_id,
		"allow_web_chat_file_upload": bool(s.allow_web_chat_file_upload),
		"updated_at": s.updated_at,
	}


def update_crm_business_settings(
	db: Session, business_id: int, *, allow_web_chat_file_upload: bool
) -> BusinessCrmSettings:
	row = get_or_create_crm_settings(db, business_id)
	row.allow_web_chat_file_upload = allow_web_chat_file_upload
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
		raise ApiError("NOT_FOUND", "فایل یافت نشد", http_status=404)
	if (fs.module_context or "") != "crm_web_chat":
		raise ApiError("VALIDATION_ERROR", "این فایل برای چت استفاده نمی‌شود", http_status=422)
	if str(fs.context_id or "") != str(conversation_id):
		raise ApiError("VALIDATION_ERROR", "فایل متعلق به این مکالمه نیست", http_status=422)
	return fs


def get_widget_by_public_key(db: Session, public_key: str) -> CrmChatWidget:
	w = db.scalar(select(CrmChatWidget).where(CrmChatWidget.public_key == public_key.strip()))
	if not w or not w.is_active:
		raise ApiError("NOT_FOUND", "ویجت چت یافت نشد یا غیرفعال است", http_status=404)
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
		raise ApiError("NOT_FOUND", "ویجت یافت نشد", http_status=404)
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
		raise ApiError("FORBIDDEN", "مبدأ درخواست برای این ویجت مجاز نیست", http_status=403)
	_validate_email(email)
	fn = first_name.strip()
	ln = last_name.strip()
	ph = phone.strip()
	if len(fn) < 1 or len(ln) < 1:
		raise ApiError("VALIDATION_ERROR", "نام و نام خانوادگی الزامی است", http_status=422)
	if len(ph) < 5:
		raise ApiError("VALIDATION_ERROR", "شماره تماس معتبر وارد کنید", http_status=422)

	visitor_token = secrets.token_urlsafe(32)
	th = _hash_visitor_token(visitor_token)

	c = CrmChatConversation(
		business_id=w.business_id,
		widget_id=w.id,
		status="open",
		visitor_first_name=fn,
		visitor_last_name=ln,
		visitor_email=email.strip().lower(),
		visitor_phone=ph,
		visitor_token_hash=th,
		page_url=(page_url or None) if page_url else None,
		last_message_at=None,
	)
	db.add(c)
	db.commit()
	db.refresh(c)

	_fire(
		db,
		w.business_id,
		"crm.chat.conversation.started",
		{
			"conversation_id": c.id,
			"widget_id": w.id,
			"visitor_first_name": fn,
			"visitor_last_name": ln,
			"visitor_email": c.visitor_email,
			"visitor_phone": ph,
			"page_url": c.page_url,
		},
	)

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
		raise ApiError("NOT_FOUND", "مکالمه یافت نشد", http_status=404)
	return c


def _get_conversation_business(db: Session, business_id: int, conversation_id: int) -> CrmChatConversation:
	c = db.get(CrmChatConversation, conversation_id)
	if not c or c.business_id != business_id:
		raise ApiError("NOT_FOUND", "مکالمه یافت نشد", http_status=404)
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
	w = db.get(CrmChatWidget, c.widget_id)
	if not w:
		raise ApiError("NOT_FOUND", "ویجت یافت نشد", http_status=404)
	if not origin_allowed(w, origin_header):
		raise ApiError("FORBIDDEN", "مبدأ درخواست برای این ویجت مجاز نیست", http_status=403)
	text = (body or "").strip()
	if not text or len(text) > _MAX_BODY:
		raise ApiError("VALIDATION_ERROR", "متن پیام نامعتبر است", http_status=422)

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
		{
			"conversation_id": c.id,
			"widget_id": c.widget_id,
			"message_id": msg.id,
			"body": text,
			"sender_role": "visitor",
		},
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
	w = db.get(CrmChatWidget, c.widget_id)
	if not w:
		raise ApiError("NOT_FOUND", "ویجت یافت نشد", http_status=404)
	if not origin_allowed(w, origin_header):
		raise ApiError("FORBIDDEN", "مبدأ درخواست برای این ویجت مجاز نیست", http_status=403)

	bsettings = get_or_create_crm_settings(db, c.business_id)
	if not bsettings.allow_web_chat_file_upload:
		raise ApiError(
			"CRM_FILE_UPLOAD_DISABLED",
			"فعلاً ارسال فایل در این چت توسط کسب‌وکار فعال نشده است.",
			http_status=403,
		)

	biz = db.get(Business, c.business_id)
	if not biz or biz.owner_id is None:
		raise ApiError("NOT_FOUND", "کسب‌وکار یافت نشد", http_status=404)
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
				"widget_id": w.id,
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
				title="چت وب CRM — محدودیت فضا",
				message=(
					"یک بازدیدکننده تلاش به ارسال فایل داشت اما پلن/فضای ذخیره‌سازی اجازه نداد. "
					"لطفاً پکیج ذخیره‌سازی را بررسی یا ارتقا دهید."
				),
			)
		# پاسخ قابل فهم به بازدیدکننده
		if err_code == "NO_ACTIVE_STORAGE_PLAN":
			raise ApiError(
				"CRM_FILE_NOT_AVAILABLE",
				"فعلاً ارسال فایل ممکن نیست. لطفاً بعداً دوباره تلاش کنید.",
				http_status=400,
				details={"storage_error": "no_plan"},
			) from None
		if err_code == "STORAGE_LIMIT_EXCEEDED":
			raise ApiError(
				"CRM_FILE_NOT_AVAILABLE",
				"فضای ذخیره‌سازی کافی نیست؛ فعلاً ارسال فایل ممکن نیست.",
				http_status=400,
				details={"storage_error": "quota"},
			) from None
		if err_code == "FILE_SIZE_EXCEEDED":
			msg_s = str(detail.get("message") if isinstance(detail, dict) else "حجم فایل مجاز نیست")
			raise ApiError("CRM_FILE_TOO_LARGE", msg_s, http_status=400) from None
		raise ApiError("CRM_FILE_UPLOAD_FAILED", "ارسال فایل انجام نشد.", http_status=400) from None

	fid = str(saved.get("file_id", ""))
	orig_name = saved.get("original_name") or "file"
	cap = (caption or "").strip()
	text = cap if cap else f"📎 {orig_name}"
	if len(text) > _MAX_BODY:
		raise ApiError("VALIDATION_ERROR", "شرح خیلی طولانی است", http_status=422)

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
		{
			"conversation_id": c.id,
			"widget_id": c.widget_id,
			"message_id": msg.id,
			"body": text,
			"sender_role": "visitor",
			"file_storage_id": fid,
		},
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
) -> Dict[str, Any]:
	c = _get_conversation_business(db, business_id, conversation_id)
	fid: Optional[str] = None
	text_combined: str
	if file_storage_id:
		fs = _assert_crm_file_for_conversation(
			db, business_id=business_id, conversation_id=conversation_id, file_id=str(file_storage_id).strip()
		)
		fid = str(fs.id)
		cap = (body or "").strip()
		bname = cap if cap else f"📎 {fs.original_name or 'فایل'}"
		if len(bname) > _MAX_BODY:
			raise ApiError("VALIDATION_ERROR", "متن پیام نامعتبر است", http_status=422)
		text_combined = bname
	else:
		text = (body or "").strip()
		if not text or len(text) > _MAX_BODY:
			raise ApiError("VALIDATION_ERROR", "متن پیام نامعتبر است", http_status=422)
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

	_fire(
		db,
		business_id,
		"crm.chat.message.sent",
		{
			"conversation_id": c.id,
			"widget_id": c.widget_id,
			"message_id": msg.id,
			"body": text_combined,
			"sender_role": "agent",
			"agent_user_id": user_id,
		},
		user_id,
	)

	return _message_to_dict_enriched(db, msg)


async def download_visitor_crm_file(
	db: Session,
	*,
	visitor_token: str,
	conversation_id: int,
	file_id: str,
) -> Dict[str, Any]:
	c = _get_conversation_by_visitor(db, visitor_token, conversation_id)
	m = db.scalar(
		select(CrmChatMessage)
		.where(
			CrmChatMessage.conversation_id == c.id,
			CrmChatMessage.file_storage_id == file_id,
		)
		.limit(1)
	)
	if m is None:
		raise ApiError("NOT_FOUND", "فایل در این مکالمه یافت نشد", http_status=404)
	storage = FileStorageService(db)
	return await storage.download_file(UUID(str(file_id)))


def list_messages_public(db: Session, visitor_token: str, conversation_id: int, limit: int = 100) -> List[Dict[str, Any]]:
	c = _get_conversation_by_visitor(db, visitor_token, conversation_id)
	q = (
		select(CrmChatMessage)
		.where(CrmChatMessage.conversation_id == c.id)
		.order_by(CrmChatMessage.created_at.asc())
		.limit(min(max(limit, 1), 500))
	)
	rows = list(db.scalars(q).all())
	return [_message_to_dict_enriched(db, m) for m in rows]


def list_messages_agent(db: Session, business_id: int, conversation_id: int, limit: int = 500) -> List[Dict[str, Any]]:
	c = _get_conversation_business(db, business_id, conversation_id)
	q = (
		select(CrmChatMessage)
		.where(CrmChatMessage.conversation_id == c.id)
		.order_by(CrmChatMessage.created_at.asc())
		.limit(min(max(limit, 1), 1000))
	)
	rows = list(db.scalars(q).all())
	return [_message_to_dict_enriched(db, m) for m in rows]


def list_conversations_agent(
	db: Session,
	business_id: int,
	*,
	status: Optional[str] = None,
	limit: int = 50,
	offset: int = 0,
) -> List[Dict[str, Any]]:
	q = select(CrmChatConversation).where(CrmChatConversation.business_id == business_id)
	if status:
		q = q.where(CrmChatConversation.status == status)
	sort_ts = func.coalesce(CrmChatConversation.last_message_at, CrmChatConversation.created_at)
	q = q.order_by(desc(sort_ts), desc(CrmChatConversation.id)).limit(min(limit, 200)).offset(max(offset, 0))
	rows = list(db.scalars(q).all())
	return [conversation_to_dict(c) for c in rows]


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
			raise ApiError("VALIDATION_ERROR", "وضعیت نامعتبر است", http_status=422)
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
