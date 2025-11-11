from __future__ import annotations

import json
from typing import Optional
from urllib import request, parse

from app.core.settings import get_settings


class TelegramProvider:
	def __init__(self) -> None:
		self.settings = get_settings()

	def is_configured(self) -> bool:
		return bool(self.settings.telegram_bot_token)

	def send_text(self, chat_id: int, text: str, parse_mode: str | None = "HTML") -> bool:
		if not self.is_configured():
			return False
		token = self.settings.telegram_bot_token
		assert token
		url = f"https://api.telegram.org/bot{token}/sendMessage"
		data = {
			"chat_id": chat_id,
			"text": text,
		}
		if parse_mode:
			data["parse_mode"] = parse_mode
		body = parse.urlencode(data).encode("utf-8")
		req = request.Request(url, data=body, method="POST")
		req.add_header("Content-Type", "application/x-www-form-urlencoded")
		try:
			with request.urlopen(req, timeout=10) as resp:
				if resp.status != 200:
					return False
				raw = resp.read().decode("utf-8")
				j = json.loads(raw)
				return bool(j.get("ok"))
		except Exception:
			return False


