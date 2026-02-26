from __future__ import annotations

import json
from typing import Any, Dict, Optional
from urllib import request

import structlog

from app.core.settings import get_settings

logger = structlog.get_logger()

BALE_API_BASE = "https://tapi.bale.ai"


class BaleProvider:
	def __init__(self, *, bot_token: str | None = None) -> None:
		self._env_settings = get_settings()
		self.bot_token = bot_token or getattr(self._env_settings, "bale_bot_token", None)

	def is_configured(self) -> bool:
		return bool(self.bot_token)

	def send_text(
		self,
		chat_id: int,
		text: str,
		parse_mode: str | None = None,
	) -> bool:
		"""ارسال پیام متنی به چت بله. API: https://tapi.bale.ai"""
		if not self.is_configured():
			return False
		token = self.bot_token
		assert token
		url = f"{BALE_API_BASE}/bot{token}/sendMessage"
		data: Dict[str, Any] = {
			"chat_id": chat_id,
			"text": text,
		}
		if parse_mode:
			data["parse_mode"] = parse_mode
		body = json.dumps(data, ensure_ascii=False).encode("utf-8")
		req = request.Request(url, data=body, method="POST")
		req.add_header("Content-Type", "application/json")
		try:
			with request.urlopen(req, timeout=10) as resp:
				if resp.status != 200:
					return False
				raw = resp.read().decode("utf-8")
				j = json.loads(raw)
				ok = j.get("ok") is True
				if not ok:
					logger.warning("bale_send_failed", chat_id=chat_id, response=j)
				return ok
		except Exception as exc:
			logger.error(
				"bale_send_exception",
				chat_id=chat_id,
				exception_type=type(exc).__name__,
				exception_message=str(exc),
			)
			return False
