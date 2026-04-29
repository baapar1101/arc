# noqa: D100
"""هندلر فلو چت وب CRM در تلگرام/بله."""
from __future__ import annotations

import logging
from typing import Any, Callable, Dict, List, Optional

from sqlalchemy.orm import Session

from adapters.db.models.crm_chat import CrmChatConversation
from adapters.db.models.user import User
from app.services import crm_chat_service as chat_svc
from app.services.async_isolated import run_coroutine_isolated
from app.services.messenger_operator.crm_web_chat_access import (
	iter_messenger_crm_business_page,
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
BIZ_PICK_PAGE = 10

# امضای send: (text: str, inline_keyboard: Optional[list[list[dict]]] = None)
MessengerSend = Callable[..., Any]


def _chunk_send(send: MessengerSend, text: str, inline_keyboard: Optional[List[List[Dict[str, str]]]] = None) -> None:
	body = text or ""
	if not body:
		if inline_keyboard:
			send("▫️", inline_keyboard=inline_keyboard)
		return
	while len(body) > SEND_CHUNK:
		part = body[:SEND_CHUNK]
		body = body[SEND_CHUNK:]
		send(part)
	send(body, inline_keyboard=inline_keyboard)


def _kb_nav_common() -> List[List[Dict[str, str]]]:
	return [
		[{"text": "📋 فهرست مکالمات", "callback_data": "crm:list"}, {"text": "▶️ شروع چت وب", "callback_data": "crm:start"}],
		[{"text": "❓ راهنما", "callback_data": "crm:help"}, {"text": "📌 وضعیت", "callback_data": "crm:stat"}],
	]


def _kb_in_conversation() -> List[List[Dict[str, str]]]:
	return [
		[{"text": "📜 تاریخچهٔ بیشتر", "callback_data": "crm:hist"}, {"text": "✖️ خروج از مکالمه", "callback_data": "crm:cancel"}],
		[{"text": "📋 فهرست مکالمات", "callback_data": "crm:list"}],
	]


def _kb_superadmin_hint() -> List[List[Dict[str, str]]]:
	return [
		[{"text": "🏢 انتخاب کسب‌وکار", "callback_data": "crm:pb:0"}],
		[{"text": "❓ راهنما", "callback_data": "crm:help"}, {"text": "📌 وضعیت", "callback_data": "crm:stat"}],
	]


def _truncate_btn_label(s: str, max_len: int = 28) -> str:
	t = (s or "").strip()
	if len(t) <= max_len:
		return t or "—"
	return t[: max_len - 1] + "…"


class CrmWebChatMessengerFlow:
	"""دستورات و حالت‌های گفت‌وگوی چت وب از پیام‌رسان."""

	flow_key = FLOW_CRM_WEB_CHAT

	def handle(
		self,
		db: Session,
		user: User,
		platform: str,
		text_raw: str,
		send: MessengerSend,
		raw_message: Optional[Dict[str, Any]] = None,
	) -> bool:
		text = (text_raw or "").strip()
		sess = get_or_create_session(db, user.id, platform)
		if sess.flow_key != self.flow_key:
			sess.flow_key = self.flow_key
			touch_session(db, sess)

		if not text and raw_message and (raw_message.get("photo") or raw_message.get("document")):
			if sess.mode == MODE_IN_CONVERSATION:
				_chunk_send(
					send,
					"فعلاً فقط ارسال متن به‌عنوان پاسخ پشتیبانی می‌شود.",
					inline_keyboard=_kb_in_conversation(),
				)
				return True
			return False

		# میانبر عددی: در حالت انتخاب کسب‌وکار = /biz؛ در آماده/مرور = /open
		if text and text.isdigit() and not text.startswith("/"):
			if sess.mode == MODE_SELECT_BUSINESS:
				return self._handle_command(db, user, sess, f"/biz {text}", send)
			if sess.mode in (MODE_READY, MODE_BROWSING) and sess.business_id:
				return self._handle_command(db, user, sess, f"/open {text}", send)

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
		send: MessengerSend,
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
		if cmd == "/bizpick":
			if not arg.isdigit():
				self._send_business_picker(db, user, sess, send, offset=0)
				return True
			self._send_business_picker(db, user, sess, send, offset=int(arg))
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
			_chunk_send(
				send,
				"نشست پاک شد. برای شروع دوباره از دکمهٔ «شروع چت وب» یا دستور /crmchat استفاده کنید.",
				inline_keyboard=_kb_nav_common(),
			)
			return True
		if cmd == "/status":
			self._cmd_status(sess, send)
			return True

		if sess.mode == MODE_IN_CONVERSATION:
			_chunk_send(
				send,
				"دستور ناشناخته. برای پاسخ به بازدیدکننده فقط متن بفرستید (بدون /).\n"
				"برای خروج از مکالمه از دکمه یا /cancel استفاده کنید.",
				inline_keyboard=_kb_in_conversation(),
			)
			return True
		return False

	def _help(self, send: MessengerSend) -> None:
		msg = (
			"🖥 چت وب CRM (اپراتور)\n\n"
			"با دکمه‌ها سریع‌تر پیش بروید؛ یا از دستورها استفاده کنید:\n\n"
			"/crmchat — شروع و انتخاب کسب‌وکار (دکمه)\n"
			"/bizpick — باز کردن دوبارهٔ فهرست انتخاب کسب‌وکار\n"
			"/biz شناسه — انتخاب دستی (در صورت نیاز)\n"
			"/list — فهرست مکالمه‌ها\n"
			"/more — صفحه بعد\n"
			"/open شناسه — باز کردن مکالمه\n"
			"/history — پیام‌های قدیمی‌تر\n"
			"/status — وضعیت فعلی\n"
			"/cancel — خروج از مکالمه\n"
			"/exit — پاک کردن نشست\n"
			"/crmhelp — این راهنما\n\n"
			"💡 در حالت آماده می‌توانید فقط شناسهٔ مکالمه (عدد) را بفرستید تا باز شود."
		)
		_chunk_send(send, msg, inline_keyboard=_kb_nav_common())

	def _send_business_picker(
		self,
		db: Session,
		user: User,
		sess: MessengerOperatorSession,
		send: MessengerSend,
		*,
		offset: int,
	) -> None:
		page_size = BIZ_PICK_PAGE
		items, has_more = iter_messenger_crm_business_page(db, user, offset=offset, limit=page_size)
		if not items:
			hint = "هیچ کسب‌وکاری برای انتخاب نیست." if offset == 0 else "صفحه‌ای در این بخش نیست؛ به ابتدا برگردید."
			kb = [[{"text": "🔄 از ابتدا", "callback_data": "crm:pb:0"}], [{"text": "❓ راهنما", "callback_data": "crm:help"}]]
			_chunk_send(send, hint, inline_keyboard=kb)
			return

		if len(items) == 1 and offset == 0:
			bid, name = items[0]
			sess.business_id = bid
			sess.mode = MODE_READY
			sess.active_conversation_id = None
			ctx_set(db, sess, {"list_offset": 0})
			kb = [
				[{"text": "📋 فهرست مکالمات", "callback_data": "crm:list"}],
				[{"text": "🏢 عوض کردن کسب‌وکار", "callback_data": "crm:pb:0"}],
				[{"text": "❓ راهنما", "callback_data": "crm:help"}, {"text": "📌 وضعیت", "callback_data": "crm:stat"}],
				[{"text": "🚪 پاک‌سازی نشست", "callback_data": "crm:exit"}],
			]
			_chunk_send(
				send,
				f"کسب‌وکار: {name} (#{bid})\nبرای دیدن مکالمه‌ها دکمهٔ زیر را بزنید.",
				inline_keyboard=kb,
			)
			return

		sess.mode = MODE_SELECT_BUSINESS
		sess.business_id = None
		sess.active_conversation_id = None
		ctx = ctx_get(sess)
		ctx["list_offset"] = 0
		ctx["biz_pick_offset"] = offset
		ctx_set(db, sess, ctx)

		header = "کسب‌وکارهایی که برای چت وب CRM به آن‌ها دسترسی دارید — یکی را بزنید:"
		lines = [header, ""]
		buttons: List[List[Dict[str, str]]] = []
		for bid, name in items:
			lines.append(f"#{bid} — {name}")
			buttons.append(
				[{"text": f"🏢 {_truncate_btn_label(name)} (#{bid})", "callback_data": f"crm:biz:{bid}"}]
			)
		nav_row: List[Dict[str, str]] = []
		if offset > 0:
			prev_off = max(0, offset - page_size)
			nav_row.append({"text": "⏮ قبلی", "callback_data": f"crm:pb:{prev_off}"})
		if has_more:
			nav_row.append({"text": "⏭ بعدی", "callback_data": f"crm:pb:{offset + page_size}"})
		if nav_row:
			buttons.append(nav_row)
		buttons.append(
			[{"text": "🔄 از اول", "callback_data": "crm:pb:0"}, {"text": "❓ راهنما", "callback_data": "crm:help"}]
		)
		_chunk_send(send, "\n".join(lines), inline_keyboard=buttons)

	def _cmd_crmchat(self, db: Session, user: User, sess: MessengerOperatorSession, send: MessengerSend) -> None:
		self._send_business_picker(db, user, sess, send, offset=0)

	def _cmd_biz(
		self,
		db: Session,
		user: User,
		sess: MessengerOperatorSession,
		arg: str,
		send: MessengerSend,
	) -> None:
		if not arg.isdigit():
			_chunk_send(
				send,
				"فرمت: /biz شناسه_کسب‌وکار — یا از دکمهٔ «انتخاب از فهرست» استفاده کنید.",
				inline_keyboard=[
					[{"text": "🏢 انتخاب از فهرست", "callback_data": "crm:pb:0"}],
					[{"text": "❓ راهنما", "callback_data": "crm:help"}],
				],
			)
			return
		bid = int(arg)
		if not user_can_reply_crm_web_chat(db, user, bid):
			_chunk_send(
				send,
				"دسترسی پاسخ چت وب برای این کسب‌وکار ندارید.",
				inline_keyboard=[
					[{"text": "🏢 انتخاب کسب‌وکار دیگر", "callback_data": "crm:pb:0"}],
					[{"text": "❓ راهنما", "callback_data": "crm:help"}],
				],
			)
			return
		sess.business_id = bid
		sess.mode = MODE_READY
		sess.active_conversation_id = None
		ctx_set(db, sess, {"list_offset": 0})
		kb = [
			[{"text": "📋 فهرست مکالمات", "callback_data": "crm:list"}],
			[{"text": "🏢 عوض کردن کسب‌وکار", "callback_data": "crm:pb:0"}],
			[{"text": "❓ راهنما", "callback_data": "crm:help"}, {"text": "📌 وضعیت", "callback_data": "crm:stat"}],
		]
		_chunk_send(
			send,
			f"کسب‌وکار #{bid} انتخاب شد.\nمکالمه‌ها را از دکمه ببینید یا /open شناسه بفرستید.",
			inline_keyboard=kb,
		)

	def _cmd_list(
		self,
		db: Session,
		user: User,
		sess: MessengerOperatorSession,
		send: MessengerSend,
		*,
		reset_offset: bool,
	) -> None:
		if not sess.business_id:
			_chunk_send(send, "ابتدا چت وب را شروع کنید (/crmchat) یا کسب‌وکار را انتخاب کنید.", inline_keyboard=_kb_nav_common())
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
			send("مکالمه‌ای نیست.", inline_keyboard=_kb_nav_common())
			sess.mode = MODE_BROWSING
			touch_session(db, sess)
			return
		lines = [f"مکالمه‌ها (از #{offset + 1}) — برای باز کردن دکمه بزنید یا /open شناسه:\n"]
		buttons: List[List[Dict[str, str]]] = []
		for c in items:
			fn = (c.get("visitor_first_name") or "").strip()
			ln = (c.get("visitor_last_name") or "").strip()
			name = (fn + " " + ln).strip() or "—"
			st = c.get("status") or ""
			cid = c.get("id")
			lines.append(f"#{cid} — {name} — {st}")
			btn_label = f"#{cid} {_truncate_btn_label(name, 22)}"
			buttons.append([{"text": btn_label, "callback_data": f"crm:open:{cid}"}])
		nav_row: List[Dict[str, str]] = []
		if has_more:
			lines.append("\nصفحه بعد با دکمه «بیشتر» یا /more")
			ctx["list_offset"] = offset + LIST_PAGE_SIZE
			nav_row.append({"text": "⏭ بیشتر", "callback_data": "crm:more"})
		else:
			ctx["list_offset"] = 0
			lines.append("\nپایان فهرست. /list از اول")
			nav_row.append({"text": "🔄 از اول", "callback_data": "crm:list"})
		buttons.append(nav_row)
		buttons.append([{"text": "📌 وضعیت", "callback_data": "crm:stat"}, {"text": "❓ راهنما", "callback_data": "crm:help"}])
		sess.mode = MODE_BROWSING
		ctx_set(db, sess, ctx)
		_chunk_send(send, "\n".join(lines), inline_keyboard=buttons)

	def _cmd_open(
		self,
		db: Session,
		user: User,
		sess: MessengerOperatorSession,
		arg: str,
		send: MessengerSend,
	) -> None:
		if not sess.business_id:
			_chunk_send(send, "ابتدا کسب‌وکار را انتخاب کنید.", inline_keyboard=_kb_nav_common())
			return
		if not arg.isdigit():
			_chunk_send(send, "فرمت: /open شناسه_مکالمه یا فقط عدد مکالمه را بفرستید.", inline_keyboard=_kb_nav_common())
			return
		cid = int(arg)
		c = db.get(CrmChatConversation, cid)
		if not c or int(c.business_id) != int(sess.business_id):
			send("مکالمه پیدا نشد.", inline_keyboard=_kb_nav_common())
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
		_chunk_send(
			send,
			"برای پاسخ، متن بفرستید (بدون /). میانبر: دکمه‌های زیر.",
			inline_keyboard=_kb_in_conversation(),
		)

	def _cmd_history(self, db: Session, user: User, sess: MessengerOperatorSession, send: MessengerSend) -> None:
		if sess.mode != MODE_IN_CONVERSATION or not sess.business_id or not sess.active_conversation_id:
			_chunk_send(send, "ابتدا مکالمه را باز کنید (/open یا دکمه).", inline_keyboard=_kb_nav_common())
			return
		ctx = ctx_get(sess)
		before_id = ctx.get("history_before_id")
		if not before_id:
			send("تاریخچه‌ای برای ادامه نیست.", inline_keyboard=_kb_in_conversation())
			return
		items, has_more = chat_svc.list_messages_agent(
			db,
			int(sess.business_id),
			int(sess.active_conversation_id),
			limit=MESSAGES_CHUNK,
			before_message_id=int(before_id),
		)
		if not items:
			send("پیام قدیمی‌تری نیست.", inline_keyboard=_kb_in_conversation())
			return
		self._format_and_send_messages(send, items, title="قدیمی‌تر ↓")
		ids = [int(m["id"]) for m in items if m.get("id") is not None]
		if ids:
			ctx["history_before_id"] = min(ids)
			ctx_set(db, sess, ctx)
		tail = "به ابتدای مکالمه رسیدید." if not has_more else "برای ادامهٔ تاریخچه دوباره «تاریخچه» را بزنید."
		_chunk_send(send, tail, inline_keyboard=_kb_in_conversation())

	def _format_and_send_messages(self, send: MessengerSend, items: list, *, title: str) -> None:
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

	def _cmd_cancel(self, db: Session, sess: MessengerOperatorSession, send: MessengerSend) -> None:
		sess.active_conversation_id = None
		sess.mode = MODE_READY if sess.business_id else MODE_IDLE
		ctx = ctx_get(sess)
		ctx.pop("history_before_id", None)
		ctx_set(db, sess, ctx)
		kb = _kb_nav_common() if sess.business_id else _kb_superadmin_hint()
		_chunk_send(
			send,
			"از مکالمه خارج شدید. می‌توانید فهرست را ببینید یا مکالمهٔ دیگری باز کنید.",
			inline_keyboard=kb,
		)

	def _cmd_status(self, sess: MessengerOperatorSession, send: MessengerSend) -> None:
		mode_fa = {
			MODE_IDLE: "آماده برای شروع",
			MODE_SELECT_BUSINESS: "انتظار برای انتخاب کسب‌وکار",
			MODE_READY: "کسب‌وکار انتخاب شده — آمادهٔ باز کردن مکالمه",
			MODE_BROWSING: "در حال مرور فهرست مکالمات",
			MODE_IN_CONVERSATION: "داخل مکالمه — هر متنی که بفرستید برای بازدیدکننده ارسال می‌شود",
		}.get(sess.mode or "", sess.mode or "—")
		lines = [
			"📌 وضعیت چت وب CRM",
			"",
			f"• حالت: {mode_fa}",
			f"• شناسهٔ کسب‌وکار: {sess.business_id or '(انتخاب نشده)'}",
			f"• مکالمهٔ باز: {sess.active_conversation_id or '(ندارد)'}",
			"",
			"برای ادامه از دکمه‌ها استفاده کنید.",
		]
		kb = _kb_in_conversation() if sess.mode == MODE_IN_CONVERSATION else _kb_nav_common()
		_chunk_send(send, "\n".join(lines), inline_keyboard=kb)

	def _send_agent_reply(
		self,
		db: Session,
		user: User,
		sess: MessengerOperatorSession,
		body: str,
		send: MessengerSend,
	) -> bool:
		if not body.strip():
			send("متن پاسخ خالی است.", inline_keyboard=_kb_in_conversation())
			return True
		bid = int(sess.business_id) if sess.business_id else None
		cid = int(sess.active_conversation_id) if sess.active_conversation_id else None
		if not bid or not cid:
			return False
		if not user_can_reply_crm_web_chat(db, user, bid):
			send("دسترسی ندارید.", inline_keyboard=_kb_in_conversation())
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
			send(f"ارسال پاسخ ناموفق: {e}", inline_keyboard=_kb_in_conversation())
			return True
		_chunk_send(send, "✅ پاسخ در چت وب ثبت شد. می‌توانید ادامه دهید یا از مکالمه خارج شوید.", inline_keyboard=_kb_in_conversation())
		return True
