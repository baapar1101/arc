# noqa: D100
"""هندلر فلو چت وب CRM در تلگرام/بله."""
from __future__ import annotations

import logging
from typing import Any, Callable, Dict, Optional

from sqlalchemy.orm import Session

from adapters.db.models.crm_chat import CrmChatConversation
from adapters.db.models.user import User
from app.services import crm_chat_service as chat_svc
from app.services.async_isolated import run_coroutine_isolated
from app.services.messenger_operator.crm_web_chat_access import (
	is_superadmin_user,
	iter_reply_allowed_businesses,
	user_can_reply_crm_web_chat,
)
from adapters.db.models.messenger_operator_session import MessengerOperatorSession
from app.services.messenger_operator.session_store import (
	FLOW_CRM_WEB_CHAT,
	MODE_BROWSING,
	MODE_IN_CONVERSATION,
	MODE_READY,
	MODE_SELECT_BUSINESS,
	MODE_IDLE,
	ctx_get,
	ctx_set,
	get_or_create_session,
	reset_session,
	touch_session,
)
logger = logging.getLogger(__name__)

LIST_PAGE_SIZE = 7
MESSAGES_CHUNK = 15
SEND_CHUNK = 3500


def _chunk_send(send: Callable[[str], Any], text: str) -> None:
	body = text or ""
	while body:
		part = body[:SEND_CHUNK]
		body = body[SEND_CHUNK:]
		send(part)


class CrmWebChatMessengerFlow:
	"""دستورات و حالت‌های گفت‌وگوی چت وب از پیام‌رسان."""

	flow_key = FLOW_CRM_WEB_CHAT

	def handle(
		self,
		db: Session,
		user: User,
		platform: str,
		text_raw: str,
		send: Callable[[str], Any],
		raw_message: Optional[Dict[str, Any]] = None,
	) -> bool:
		text = (text_raw or "").strip()
		sess = get_or_create_session(db, user.id, platform)
		if sess.flow_key != self.flow_key:
			sess.flow_key = self.flow_key
			touch_session(db, sess)

		if not text and raw_message and (raw_message.get("photo") or raw_message.get("document")):
			if sess.mode == MODE_IN_CONVERSATION:
				send("فعلاً فقط ارسال متن به‌عنوان پاسخ پشتیبانی می‌شود.")
				return True
			return False

		if text.startswith("/"):
			return self._handle_command(db, user, sess, text, send)

		if sess.mode == MODE_IN_CONVERSATION and sess.business_id and sess.active_conversation_id:
			return self._send_agent_reply(db, user, sess, text, send)

		return False

	def _handle_command(
		self,
		db: Session,
		user: User,
		sess: MessengerOperatorSession,
		text: str,
		send: Callable[[str], Any],
	) -> bool:
		parts = text.split(maxsplit=1)
		cmd = parts[0].lower()
		arg = parts[1].strip() if len(parts) > 1 else ""

		if cmd in ("/crmhelp", "/چت_وب", "/crm_chat_help"):
			self._help(send)
			return True
		if cmd == "/crmchat":
			self._cmd_crmchat(db, user, sess, send)
			return True
		if cmd == "/biz":
			self._cmd_biz(db, user, sess, arg, send)
			return True
		if cmd == "/list":
			self._cmd_list(db, user, sess, send, reset_offset=True)
			return True
		if cmd == "/more":
			self._cmd_list(db, user, sess, send, reset_offset=False)
			return True
		if cmd == "/open":
			self._cmd_open(db, user, sess, arg, send)
			return True
		if cmd == "/history":
			self._cmd_history(db, user, sess, send)
			return True
		if cmd == "/cancel":
			self._cmd_cancel(db, sess, send)
			return True
		if cmd == "/exit":
			reset_session(db, sess, full=True)
			send("نشست پاک شد. برای شروع دوباره: /crmchat")
			return True
		if cmd == "/status":
			self._cmd_status(sess, send)
			return True

		if sess.mode == MODE_IN_CONVERSATION:
			send("دستور ناشناخته. برای پاسخ به بازدیدکننده فقط متن بفرستید (بدون /). /cancel خروج از مکالمه.")
			return True
		return False

	def _help(self, send: Callable[[str], Any]) -> None:
		msg = (
			"🖥 چت وب CRM (اپراتور)\n\n"
			"/crmchat — شروع و انتخاب کسب‌وکار\n"
			"/biz شناسه — انتخاب کسب‌وکار (برای مدیر ارشد)\n"
			"/list — فهرست مکالمه‌ها\n"
			"/more — صفحه بعد فهرست\n"
			"/open شناسه — باز کردن مکالمه و تاریخچه\n"
			"/history — بارگذاری پیام‌های قدیمی‌تر\n"
			"/status — وضعیت فعلی\n"
			"/cancel — خروج از مکالمه فعال\n"
			"/exit — پاک کردن کامل نشست\n"
			"/crmhelp — این راهنما"
		)
		_chunk_send(send, msg)

	def _cmd_crmchat(self, db: Session, user: User, sess: MessengerOperatorSession, send: Callable[[str], Any]) -> None:
		biz_list = iter_reply_allowed_businesses(db, user)

		if is_superadmin_user(user):
			sess.mode = MODE_SELECT_BUSINESS
			sess.business_id = None
			sess.active_conversation_id = None
			ctx_set(db, sess, {"list_offset": 0})
			send(
				"شما مدیر ارشد هستید. با دستور زیر کسب‌وکار را مشخص کنید:\n"
				"/biz شناسه_کسب‌وکار\n"
				"سپس /list و /open را بزنید."
			)
			return

		if not biz_list:
			send("هیچ کسب‌وکاری با مجوز پاسخ‌گویی چت وب برای شما نیست.")
			return

		if len(biz_list) == 1:
			bid, name = biz_list[0]
			sess.business_id = bid
			sess.mode = MODE_READY
			sess.active_conversation_id = None
			ctx_set(db, sess, {"list_offset": 0})
			send(f"کسب‌وکار: {name} (#{bid})\n/list فهرست مکالمه‌ها\n/open شناسه مکالمه")
			return

		lines = ["چند کسب‌وکار دارید؛ با یکی از دستورها انتخاب کنید:\n"]
		for bid, name in biz_list[:25]:
			lines.append(f"/biz {bid} — {name}")
		sess.mode = MODE_SELECT_BUSINESS
		sess.business_id = None
		ctx_set(db, sess, {"list_offset": 0})
		_chunk_send(send, "\n".join(lines))

	def _cmd_biz(
		self,
		db: Session,
		user: User,
		sess: MessengerOperatorSession,
		arg: str,
		send: Callable[[str], Any],
	) -> None:
		if not arg.isdigit():
			send("فرمت: /biz شناسه_کسب‌وکار")
			return
		bid = int(arg)
		if not user_can_reply_crm_web_chat(db, user, bid):
			send("دسترسی پاسخ چت وب برای این کسب‌وکار ندارید.")
			return
		sess.business_id = bid
		sess.mode = MODE_READY
		sess.active_conversation_id = None
		ctx_set(db, sess, {"list_offset": 0})
		send(f"کسب‌وکار #{bid} انتخاب شد.\n/list فهرست مکالمه‌ها — /open شناسه")

	def _cmd_list(
		self,
		db: Session,
		user: User,
		sess: MessengerOperatorSession,
		send: Callable[[str], Any],
		*,
		reset_offset: bool,
	) -> None:
		if not sess.business_id:
			send("ابتدا /crmchat یا /biz را بزنید.")
			return
		if not user_can_reply_crm_web_chat(db, user, int(sess.business_id)):
			send("دسترسی ندارید.")
			return
		ctx = ctx_get(sess)
		offset = 0 if reset_offset else int(ctx.get("list_offset", 0))
		items, has_more = chat_svc.list_conversations_agent(
			db,
			int(sess.business_id),
			limit=LIST_PAGE_SIZE,
			offset=offset,
			search=None,
		)
		if not items:
			send("مکالمه‌ای نیست.")
			sess.mode = MODE_BROWSING
			touch_session(db, sess)
			return
		lines = [f"مکالمه‌ها (از #{offset + 1})، /open شناسه:\n"]
		for c in items:
			fn = (c.get("visitor_first_name") or "").strip()
			ln = (c.get("visitor_last_name") or "").strip()
			name = (fn + " " + ln).strip() or "—"
			st = c.get("status") or ""
			cid = c.get("id")
			lines.append(f"#{cid} — {name} — {st}")
		if has_more:
			lines.append("\nصفحه بعد: /more")
			ctx["list_offset"] = offset + LIST_PAGE_SIZE
		else:
			ctx["list_offset"] = 0
			lines.append("\nپایان فهرست. /list از اول")
		sess.mode = MODE_BROWSING
		ctx_set(db, sess, ctx)
		_chunk_send(send, "\n".join(lines))

	def _cmd_open(
		self,
		db: Session,
		user: User,
		sess: MessengerOperatorSession,
		arg: str,
		send: Callable[[str], Any],
	) -> None:
		if not sess.business_id:
			send("ابتدا کسب‌وکار را انتخاب کنید.")
			return
		if not arg.isdigit():
			send("فرمت: /open شناسه_مکالمه")
			return
		cid = int(arg)
		c = db.get(CrmChatConversation, cid)
		if not c or int(c.business_id) != int(sess.business_id):
			send("مکالمه پیدا نشد.")
			return
		if not user_can_reply_crm_web_chat(db, user, int(sess.business_id)):
			send("دسترسی ندارید.")
			return
		sess.active_conversation_id = cid
		sess.mode = MODE_IN_CONVERSATION
		ctx = ctx_get(sess)
		ctx["history_before_id"] = None
		ctx_set(db, sess, ctx)
		items, _ = chat_svc.list_messages_agent(db, int(sess.business_id), cid, limit=MESSAGES_CHUNK, before_message_id=None)
		self._format_and_send_messages(send, items, title=f"مکالمه #{cid}")
		if items:
			ids = [int(m["id"]) for m in items if m.get("id") is not None]
			if ids:
				ctx = ctx_get(sess)
				ctx["history_before_id"] = min(ids)
				ctx_set(db, sess, ctx)
		send("برای پاسخ، متن بفرستید (بدون /). /history پیام‌های قدیمی‌تر — /cancel خروج")

	def _cmd_history(self, db: Session, user: User, sess: MessengerOperatorSession, send: Callable[[str], Any]) -> None:
		if sess.mode != MODE_IN_CONVERSATION or not sess.business_id or not sess.active_conversation_id:
			send("ابتدا با /open مکالمه را باز کنید.")
			return
		ctx = ctx_get(sess)
		before_id = ctx.get("history_before_id")
		if not before_id:
			send("تاریخچه‌ای برای ادامه نیست.")
			return
		items, has_more = chat_svc.list_messages_agent(
			db,
			int(sess.business_id),
			int(sess.active_conversation_id),
			limit=MESSAGES_CHUNK,
			before_message_id=int(before_id),
		)
		if not items:
			send("پیام قدیمی‌تری نیست.")
			return
		self._format_and_send_messages(send, items, title="قدیمی‌تر ↓")
		ids = [int(m["id"]) for m in items if m.get("id") is not None]
		if ids:
			ctx["history_before_id"] = min(ids)
			ctx_set(db, sess, ctx)
		if not has_more:
			send("به ابتدای مکالمه رسیدید.")

	def _format_and_send_messages(self, send: Callable[[str], Any], items: list, *, title: str) -> None:
		lines = [title, ""]
		for m in items:
			role = m.get("sender_role") or "?"
			label = "بازدیدکننده" if role == "visitor" else "عامل"
			body = (m.get("body") or "").replace("\n", " ")
			if len(body) > 500:
				body = body[:497] + "..."
			mid = m.get("id")
			lines.append(f"[{label}] (#{mid}) {body}")
		_chunk_send(send, "\n".join(lines))

	def _cmd_cancel(self, db: Session, sess: MessengerOperatorSession, send: Callable[[str], Any]) -> None:
		sess.active_conversation_id = None
		sess.mode = MODE_READY if sess.business_id else MODE_IDLE
		ctx = ctx_get(sess)
		ctx.pop("history_before_id", None)
		ctx_set(db, sess, ctx)
		send("از مکالمه خارج شدید. /list یا /open")

	def _cmd_status(self, sess: MessengerOperatorSession, send: Callable[[str], Any]) -> None:
		msg = (
			f"flow={sess.flow_key}\n"
			f"mode={sess.mode}\n"
			f"business_id={sess.business_id}\n"
			f"conversation_id={sess.active_conversation_id}\n"
		)
		send(msg)

	def _send_agent_reply(
		self,
		db: Session,
		user: User,
		sess: MessengerOperatorSession,
		body: str,
		send: Callable[[str], Any],
	) -> bool:
		if not body.strip():
			send("متن پاسخ خالی است.")
			return True
		bid = int(sess.business_id) if sess.business_id else None
		cid = int(sess.active_conversation_id) if sess.active_conversation_id else None
		if not bid or not cid:
			return False
		if not user_can_reply_crm_web_chat(db, user, bid):
			send("دسترسی ندارید.")
			return True

		async def _run():
			return await chat_svc.post_agent_message(
				db,
				business_id=bid,
				conversation_id=cid,
				body=body.strip(),
				user_id=int(user.id),
				file_storage_id=None,
				fire_workflow_trigger_message_sent=True,
				automation_context={"operator_relay": True, "operator_relay_channel": sess.platform},
			)

		try:
			run_coroutine_isolated(lambda: _run())
		except Exception as e:
			logger.exception("crm web chat relay reply failed")
			send(f"ارسال پاسخ ناموفق: {e}")
			return True
		send("✅ پاسخ در چت وب ثبت شد.")
		return True
