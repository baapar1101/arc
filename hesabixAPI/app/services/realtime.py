from __future__ import annotations

from typing import Dict, Set
import asyncio

from fastapi import WebSocket


class RealtimeManager:
	def __init__(self) -> None:
		self._user_sockets: Dict[int, Set[WebSocket]] = {}
		self._lock = asyncio.Lock()

	async def connect(self, user_id: int, websocket: WebSocket) -> None:
		await websocket.accept()
		async with self._lock:
			if user_id not in self._user_sockets:
				self._user_sockets[user_id] = set()
			self._user_sockets[user_id].add(websocket)

	async def disconnect(self, user_id: int, websocket: WebSocket) -> None:
		async with self._lock:
			sockets = self._user_sockets.get(user_id)
			if sockets and websocket in sockets:
				sockets.remove(websocket)
				if not sockets:
					self._user_sockets.pop(user_id, None)

	async def send_to_user(self, user_id: int, message: dict) -> None:
		async with self._lock:
			sockets = list(self._user_sockets.get(user_id, set()))
		for ws in sockets:
			try:
				await ws.send_json(message)
			except Exception:
				try:
					await ws.close()
				except Exception:
					pass
				await self.disconnect(user_id, ws)


# singleton
realtime_manager = RealtimeManager()


