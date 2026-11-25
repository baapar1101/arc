# noqa: D100
"""اتصالات WebSocket برای چت وب CRM (اتاق مکالمه و اتاق کسب‌وکار)."""
from __future__ import annotations

import logging
from typing import Any, Dict, Set

from fastapi import WebSocket

logger = logging.getLogger(__name__)


class CrmChatRealtimeManager:
	def __init__(self) -> None:
		self._conversation_sockets: Dict[int, Set[WebSocket]] = {}
		self._business_sockets: Dict[int, Set[WebSocket]] = {}
		self._agent_user_ids: Dict[int, int] = {}

	async def add_to_conversation(self, conversation_id: int, websocket: WebSocket) -> None:
		self._conversation_sockets.setdefault(conversation_id, set()).add(websocket)

	async def remove_from_conversation(self, conversation_id: int, websocket: WebSocket) -> None:
		s = self._conversation_sockets.get(conversation_id)
		if not s:
			return
		s.discard(websocket)
		if not s:
			self._conversation_sockets.pop(conversation_id, None)

	async def add_to_business(self, business_id: int, websocket: WebSocket, *, user_id: int) -> None:
		self._business_sockets.setdefault(business_id, set()).add(websocket)
		self._agent_user_ids[id(websocket)] = int(user_id)

	async def remove_from_business(self, business_id: int, websocket: WebSocket) -> None:
		s = self._business_sockets.get(business_id)
		if not s:
			return
		s.discard(websocket)
		self._agent_user_ids.pop(id(websocket), None)
		if not s:
			self._business_sockets.pop(business_id, None)

	async def disconnect_all(self, websocket: WebSocket) -> None:
		for cid, socks in list(self._conversation_sockets.items()):
			if websocket in socks:
				socks.discard(websocket)
				if not socks:
					self._conversation_sockets.pop(cid, None)
		for bid, socks in list(self._business_sockets.items()):
			if websocket in socks:
				socks.discard(websocket)
				self._agent_user_ids.pop(id(websocket), None)
				if not socks:
					self._business_sockets.pop(bid, None)

	async def deliver_conversation(self, conversation_id: int, payload: dict[str, Any]) -> None:
		"""فقط سوکت‌های ثبت‌شده روی همین فرایند worker."""
		socks = list(self._conversation_sockets.get(conversation_id, set()))
		for ws in socks:
			try:
				await ws.send_json(payload)
			except Exception as exc:
				logger.debug("crm chat ws send conv %s: %s", conversation_id, exc)
				await self.remove_from_conversation(conversation_id, ws)

	async def deliver_business(self, business_id: int, payload: dict[str, Any]) -> None:
		socks = list(self._business_sockets.get(business_id, set()))
		conversation = payload.get("conversation") if isinstance(payload, dict) else None
		needs_acl = isinstance(conversation, dict) and conversation.get("lead_id")
		db = None
		if needs_acl:
			from adapters.db.session import SessionLocal

			db = SessionLocal()
		try:
			for ws in socks:
				body = payload
				if needs_acl and db is not None:
					from app.services.crm_chat_service import conversation_event_for_agent

					body = conversation_event_for_agent(
						db, business_id, self._agent_user_ids.get(id(ws)), payload
					)
				try:
					await ws.send_json(body)
				except Exception as exc:
					logger.debug("crm chat ws send biz %s: %s", business_id, exc)
					await self.remove_from_business(business_id, ws)
		finally:
			if db is not None:
				db.close()

	async def broadcast_conversation(self, conversation_id: int, payload: dict[str, Any]) -> None:
		from app.services.crm_chat_realtime_fanout import broadcast_conversation_cross_worker

		await broadcast_conversation_cross_worker(conversation_id, payload)

	async def broadcast_business(self, business_id: int, payload: dict[str, Any]) -> None:
		from app.services.crm_chat_realtime_fanout import broadcast_business_cross_worker

		await broadcast_business_cross_worker(business_id, payload)


crm_chat_realtime_manager = CrmChatRealtimeManager()
