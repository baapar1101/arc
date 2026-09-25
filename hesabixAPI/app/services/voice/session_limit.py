"""سقف اتصال همزمان جلسهٔ صوت per user (VOI-02)."""

from __future__ import annotations

import asyncio
from collections import defaultdict

from app.core.responses import ApiError
from app.core.settings import get_settings

_lock = asyncio.Lock()
_active: dict[int, int] = defaultdict(int)


class VoiceSessionGuard:
	def __init__(self, user_id: int) -> None:
		self.user_id = int(user_id)
		self._acquired = False

	async def acquire(self) -> None:
		settings = get_settings()
		limit = max(1, int(getattr(settings, "voice_max_concurrent_sessions_per_user", 2) or 2))
		async with _lock:
			current = _active[self.user_id]
			if current >= limit:
				raise ApiError(
					"VOICE_SESSION_LIMIT",
					"تعداد جلسات صوتی همزمان شما به سقف رسیده است",
					http_status=429,
				)
			_active[self.user_id] = current + 1
			self._acquired = True

	async def release(self) -> None:
		if not self._acquired:
			return
		async with _lock:
			current = _active.get(self.user_id, 0)
			if current <= 1:
				_active.pop(self.user_id, None)
			else:
				_active[self.user_id] = current - 1
			self._acquired = False

	async def __aenter__(self) -> "VoiceSessionGuard":
		await self.acquire()
		return self

	async def __aexit__(self, exc_type, exc, tb) -> None:
		await self.release()


def reset_voice_session_limits_for_tests() -> None:
	_active.clear()
