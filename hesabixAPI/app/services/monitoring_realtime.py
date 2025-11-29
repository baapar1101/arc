from __future__ import annotations

from typing import Dict, Set
import asyncio
import json
from datetime import datetime

from fastapi import WebSocket


class MonitoringRealtimeManager:
	"""مدیریت اتصالات WebSocket برای مانیتورینگ"""
	
	def __init__(self) -> None:
		self._connections: Set[WebSocket] = set()
		self._lock = asyncio.Lock()
	
	async def connect(self, websocket: WebSocket) -> None:
		"""اتصال یک WebSocket جدید"""
		await websocket.accept()
		async with self._lock:
			self._connections.add(websocket)
	
	async def disconnect(self, websocket: WebSocket) -> None:
		"""قطع اتصال یک WebSocket"""
		async with self._lock:
			if websocket in self._connections:
				self._connections.remove(websocket)
	
	async def broadcast_hardware_metrics(self, metrics: Dict) -> None:
		"""ارسال metrics سخت‌افزاری به همه اتصالات"""
		message = {
			"channel": "hardware:metrics",
			"timestamp": datetime.utcnow().isoformat(),
			"data": metrics,
		}
		await self._broadcast(message)
	
	async def broadcast_service_status(self, services: Dict) -> None:
		"""ارسال وضعیت سرویس‌ها به همه اتصالات"""
		message = {
			"channel": "services:status",
			"timestamp": datetime.utcnow().isoformat(),
			"data": services,
		}
		await self._broadcast(message)
	
	async def broadcast_alert(self, alert: Dict) -> None:
		"""ارسال هشدار جدید به همه اتصالات"""
		message = {
			"channel": "alerts:new",
			"timestamp": datetime.utcnow().isoformat(),
			"data": alert,
		}
		await self._broadcast(message)
	
	async def _broadcast(self, message: Dict) -> None:
		"""ارسال پیام به همه اتصالات"""
		async with self._lock:
			connections = list(self._connections)
		
		# ارسال به همه اتصالات
		disconnected = []
		for ws in connections:
			try:
				await ws.send_json(message)
			except Exception:
				# اتصال قطع شده
				disconnected.append(ws)
		
		# حذف اتصالات قطع شده
		if disconnected:
			async with self._lock:
				for ws in disconnected:
					self._connections.discard(ws)
	
	def get_connection_count(self) -> int:
		"""دریافت تعداد اتصالات فعال"""
		return len(self._connections)


# Singleton instance
monitoring_realtime_manager = MonitoringRealtimeManager()

