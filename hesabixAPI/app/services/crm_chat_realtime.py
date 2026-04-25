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

	async def add_to_conversation(self, conversation_id: int, websocket: WebSocket) -> None:
		self._conversation_sockets.setdefault(conversation_id, set()).add(websocket)

	async def remove_from_conversation(self, conversation_id: int, websocket: WebSocket) -> None:
		s = self._conversation_sockets.get(conversation_id)
		if not s:
			return
		s.discard(websocket)
		if not s:
			self._conversation_sockets.pop(conversation_id, None)

	async def add_to_business(self, business_id: int, websocket: WebSocket) -> None:
		self._business_sockets.setdefault(business_id, set()).add(websocket)

	async def remove_from_business(self, business_id: int, websocket: WebSocket) -> None:
		s = self._business_sockets.get(business_id)
		if not s:
			return
		s.discard(websocket)
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
				if not socks:
					self._business_sockets.pop(bid, None)

	async def broadcast_conversation(self, conversation_id: int, payload: dict[str, Any]) -> None:
		socks = list(self._conversation_sockets.get(conversation_id, set()))
		for ws in socks:
			try:
				await ws.send_json(payload)
			except Exception as exc:
				logger.debug("crm chat ws send conv %s: %s", conversation_id, exc)
				await self.remove_from_conversation(conversation_id, ws)

	async def broadcast_business(self, business_id: int, payload: dict[str, Any]) -> None:
		socks = list(self._business_sockets.get(business_id, set()))
		for ws in socks:
			try:
				await ws.send_json(payload)
			except Exception as exc:
				logger.debug("crm chat ws send biz %s: %s", business_id, exc)
				await self.remove_from_business(business_id, ws)


crm_chat_realtime_manager = CrmChatRealtimeManager()
