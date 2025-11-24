from __future__ import annotations

import json
from typing import Any, Dict, Optional
from urllib import request, parse

from app.core.settings import get_settings


class TelegramProvider:
	def __init__(self, *, bot_token: str | None = None, proxy_config: Dict[str, Any] | None = None) -> None:
		"""
		`bot_token` در صورت ارسال، جایگزین مقدار موجود در تنظیمات محیطی می‌شود.
		"""
		self._env_settings = get_settings()
		self.bot_token = bot_token or self._env_settings.telegram_bot_token
		self.proxy_config = proxy_config or {}

	def is_configured(self) -> bool:
		return bool(self.bot_token)

	def _proxy_enabled(self) -> bool:
		return bool(self.proxy_config.get("enabled") and self.proxy_config.get("base_url"))

	def _proxy_request(self, method: str, payload: Dict[str, Any]) -> tuple[bool, str | None]:
		if not self._proxy_enabled():
			return False, "proxy_not_configured"
		base_url = str(self.proxy_config.get("base_url")).rstrip("/")
		url = f"{base_url}/telegram/send"
		body = json.dumps({"method": method, "payload": payload}, ensure_ascii=False).encode("utf-8")
		req = request.Request(url, data=body, method="POST")
		req.add_header("Content-Type", "application/json")
		api_key = self.proxy_config.get("api_key")
		if api_key:
			req.add_header("X-Proxy-Key", str(api_key))
		try:
			with request.urlopen(req, timeout=10) as resp:
				raw = resp.read().decode("utf-8")
				try:
					j = json.loads(raw)
				except json.JSONDecodeError:
					return False, "invalid_proxy_response"
				ok = bool(j.get("ok"))
				description = j.get("description")
				if not ok and not description:
					description = j.get("error")
				return ok, description
		except Exception as exc:
			return False, str(exc)

	def send_text(self, chat_id: int, text: str, parse_mode: str | None = "HTML") -> bool:
		if not self.is_configured():
			return False
		if self._proxy_enabled():
			payload: Dict[str, Any] = {
				"chat_id": chat_id,
				"text": text,
			}
			if parse_mode:
				payload["parse_mode"] = parse_mode
			ok, _ = self._proxy_request("sendMessage", payload)
			return ok
		token = self.bot_token
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

	def set_webhook(self, *, url: str, secret_token: str | None = None, drop_pending_updates: bool = False) -> tuple[bool, str | None]:
		"""
		وب‌هوک ربات را در تلگرام ثبت می‌کند و نتیجه را برمی‌گرداند.
		"""
		if not self.is_configured():
			return False, "bot_not_configured"
		payload: dict[str, object] = {"url": url, "drop_pending_updates": drop_pending_updates}
		if secret_token:
			payload["secret_token"] = secret_token
		if self._proxy_enabled():
			return self._proxy_request("setWebhook", payload)
		token = self.bot_token
		assert token
		data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
		req = request.Request(
			f"https://api.telegram.org/bot{token}/setWebhook",
			data=data,
			method="POST",
		)
		req.add_header("Content-Type", "application/json")
		try:
			with request.urlopen(req, timeout=10) as resp:
				raw = resp.read().decode("utf-8")
				try:
					j = json.loads(raw)
				except json.JSONDecodeError:
					return False, "invalid_response"
				return bool(j.get("ok")), j.get("description")
		except Exception as exc:
			return False, str(exc)


