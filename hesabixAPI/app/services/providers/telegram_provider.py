from __future__ import annotations

import json
from typing import Any, Dict, Optional
from urllib import request, parse
import structlog

from app.core.settings import get_settings

logger = structlog.get_logger()


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
			logger.warning("telegram_proxy_request_failed", reason="proxy_not_configured", method=method)
			return False, "proxy_not_configured"
		
		base_url = str(self.proxy_config.get("base_url")).rstrip("/")
		url = f"{base_url}/telegram/send"
		body = json.dumps({"method": method, "payload": payload}, ensure_ascii=False).encode("utf-8")
		
		logger.info("telegram_proxy_request_start", 
			method=method,
			proxy_url=url,
			payload_keys=list(payload.keys()) if isinstance(payload, dict) else None,
			has_api_key=bool(self.proxy_config.get("api_key"))
		)
		
		req = request.Request(url, data=body, method="POST")
		req.add_header("Content-Type", "application/json")
		api_key = self.proxy_config.get("api_key")
		if api_key:
			req.add_header("X-Proxy-Key", str(api_key))
		
		try:
			with request.urlopen(req, timeout=10) as resp:
				raw = resp.read().decode("utf-8")
				http_code = resp.getcode()
				
				try:
					j = json.loads(raw)
				except json.JSONDecodeError:
					logger.error("telegram_proxy_request_invalid_json", 
						method=method,
						http_code=http_code,
						response_preview=raw[:200] if raw else None
					)
					return False, "invalid_proxy_response"
				
				ok = bool(j.get("ok"))
				description = j.get("description")
				if not ok and not description:
					description = j.get("error")
				
				if ok:
					logger.info("telegram_proxy_request_success", 
						method=method,
						http_code=http_code,
						description=description
					)
				else:
					logger.error("telegram_proxy_request_failed", 
						method=method,
						http_code=http_code,
						error=description,
						response=j
					)
				
				return ok, description
				
		except Exception as exc:
			logger.error("telegram_proxy_request_exception", 
				method=method,
				proxy_url=url,
				exception_type=type(exc).__name__,
				exception_message=str(exc)
			)
			return False, str(exc)

	def set_my_commands(
		self,
		commands: list[dict[str, str]],
		language_code: str | None = None,
		scope: dict[str, Any] | None = None,
	) -> bool:
		"""ثبت دستورات منوی / در تلگرام (BotFather جایگزین نمی‌شود؛ همان Bot را آپدیت می‌کند)."""
		if not self.is_configured():
			return False
		payload: Dict[str, Any] = {"commands": commands}
		if language_code:
			payload["language_code"] = language_code
		if scope:
			payload["scope"] = scope
		if self._proxy_enabled():
			ok, _ = self._proxy_request("setMyCommands", payload)
			return ok
		token = self.bot_token
		assert token
		url = f"https://api.telegram.org/bot{token}/setMyCommands"
		body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
		req = request.Request(url, data=body, method="POST")
		req.add_header("Content-Type", "application/json")
		try:
			with request.urlopen(req, timeout=10) as resp:
				raw = resp.read().decode("utf-8")
				j = json.loads(raw)
				return bool(j.get("ok"))
		except Exception:
			return False

	def send_text(
		self,
		chat_id: int,
		text: str,
		parse_mode: str | None = "HTML",
		reply_markup: Dict[str, Any] | None = None
	) -> bool:
		"""ارسال پیام متنی با امکان اضافه کردن Inline Keyboard"""
		if not self.is_configured():
			return False
		if self._proxy_enabled():
			payload: Dict[str, Any] = {
				"chat_id": chat_id,
				"text": text,
			}
			if parse_mode:
				payload["parse_mode"] = parse_mode
			if reply_markup:
				payload["reply_markup"] = reply_markup
			ok, _ = self._proxy_request("sendMessage", payload)
			return ok
		token = self.bot_token
		assert token
		url = f"https://api.telegram.org/bot{token}/sendMessage"
		data: Dict[str, Any] = {
			"chat_id": chat_id,
			"text": text,
		}
		if parse_mode:
			data["parse_mode"] = parse_mode
		if reply_markup:
			# شیء تودرتو؛ json.dumps(data) یک بار کل بدنه را می‌سازد (نه رشتهٔ JSON دوبل)
			data["reply_markup"] = reply_markup

		body = json.dumps(data, ensure_ascii=False).encode("utf-8")
		req = request.Request(url, data=body, method="POST")
		req.add_header("Content-Type", "application/json")
		try:
			with request.urlopen(req, timeout=10) as resp:
				if resp.status != 200:
					return False
				raw = resp.read().decode("utf-8")
				j = json.loads(raw)
				return bool(j.get("ok"))
		except Exception:
			return False
	
	def edit_message_text(
		self,
		chat_id: int,
		message_id: int,
		text: str,
		parse_mode: str | None = "HTML",
		reply_markup: Dict[str, Any] | None = None
	) -> bool:
		"""ویرایش متن پیام با امکان تغییر Inline Keyboard"""
		if not self.is_configured():
			return False
		if self._proxy_enabled():
			payload: Dict[str, Any] = {
				"chat_id": chat_id,
				"message_id": message_id,
				"text": text,
			}
			if parse_mode:
				payload["parse_mode"] = parse_mode
			if reply_markup:
				payload["reply_markup"] = reply_markup
			ok, _ = self._proxy_request("editMessageText", payload)
			return ok
		token = self.bot_token
		assert token
		url = f"https://api.telegram.org/bot{token}/editMessageText"
		data: Dict[str, Any] = {
			"chat_id": chat_id,
			"message_id": message_id,
			"text": text,
		}
		if parse_mode:
			data["parse_mode"] = parse_mode
		if reply_markup:
			data["reply_markup"] = reply_markup

		body = json.dumps(data, ensure_ascii=False).encode("utf-8")
		req = request.Request(url, data=body, method="POST")
		req.add_header("Content-Type", "application/json")
		try:
			with request.urlopen(req, timeout=10) as resp:
				if resp.status != 200:
					return False
				raw = resp.read().decode("utf-8")
				j = json.loads(raw)
				return bool(j.get("ok"))
		except Exception:
			return False
	
	def edit_message_reply_markup(
		self,
		chat_id: int,
		message_id: int,
		reply_markup: Dict[str, Any] | None = None
	) -> bool:
		"""ویرایش فقط Inline Keyboard یک پیام"""
		if not self.is_configured():
			return False
		if self._proxy_enabled():
			payload: Dict[str, Any] = {
				"chat_id": chat_id,
				"message_id": message_id,
			}
			if reply_markup:
				payload["reply_markup"] = reply_markup
			ok, _ = self._proxy_request("editMessageReplyMarkup", payload)
			return ok
		token = self.bot_token
		assert token
		url = f"https://api.telegram.org/bot{token}/editMessageReplyMarkup"
		data: Dict[str, Any] = {
			"chat_id": chat_id,
			"message_id": message_id,
		}
		if reply_markup:
			data["reply_markup"] = reply_markup

		body = json.dumps(data, ensure_ascii=False).encode("utf-8")
		req = request.Request(url, data=body, method="POST")
		req.add_header("Content-Type", "application/json")
		try:
			with request.urlopen(req, timeout=10) as resp:
				if resp.status != 200:
					return False
				raw = resp.read().decode("utf-8")
				j = json.loads(raw)
				return bool(j.get("ok"))
		except Exception:
			return False
	
	def answer_callback_query(
		self,
		callback_query_id: str,
		text: str | None = None,
		show_alert: bool = False
	) -> bool:
		"""پاسخ به Callback Query (برای حذف loading)"""
		if not self.is_configured():
			return False
		if self._proxy_enabled():
			payload: Dict[str, Any] = {
				"callback_query_id": callback_query_id,
			}
			if text:
				payload["text"] = text
			if show_alert:
				payload["show_alert"] = True
			ok, _ = self._proxy_request("answerCallbackQuery", payload)
			return ok
		token = self.bot_token
		assert token
		url = f"https://api.telegram.org/bot{token}/answerCallbackQuery"
		data: Dict[str, Any] = {
			"callback_query_id": callback_query_id,
		}
		if text:
			data["text"] = text
		if show_alert:
			data["show_alert"] = True
		
		body = json.dumps(data, ensure_ascii=False).encode("utf-8")
		req = request.Request(url, data=body, method="POST")
		req.add_header("Content-Type", "application/json")
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
			logger.error("telegram_set_webhook_failed", reason="bot_not_configured")
			return False, "bot_not_configured"
		
		payload: dict[str, object] = {"url": url, "drop_pending_updates": drop_pending_updates}
		if secret_token:
			payload["secret_token"] = secret_token
		
		logger.info("telegram_set_webhook_start", 
			webhook_url=url,
			has_secret_token=bool(secret_token),
			drop_pending_updates=drop_pending_updates,
			proxy_enabled=self._proxy_enabled()
		)
		
		if self._proxy_enabled():
			logger.info("telegram_set_webhook_using_proxy")
			return self._proxy_request("setWebhook", payload)
		
		# استفاده مستقیم از Telegram API
		token = self.bot_token
		assert token
		telegram_url = f"https://api.telegram.org/bot{token}/setWebhook"
		
		logger.info("telegram_set_webhook_direct", telegram_url=telegram_url)
		
		data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
		req = request.Request(telegram_url, data=data, method="POST")
		req.add_header("Content-Type", "application/json")
		
		try:
			with request.urlopen(req, timeout=10) as resp:
				http_code = resp.getcode()
				raw = resp.read().decode("utf-8")
				
				try:
					j = json.loads(raw)
				except json.JSONDecodeError:
					logger.error("telegram_set_webhook_invalid_response", 
						http_code=http_code,
						response_preview=raw[:200] if raw else None
					)
					return False, "invalid_response"
				
				ok = bool(j.get("ok"))
				description = j.get("description")
				
				if ok:
					logger.info("telegram_set_webhook_success", 
						webhook_url=url,
						http_code=http_code,
						description=description
					)
				else:
					logger.error("telegram_set_webhook_failed", 
						webhook_url=url,
						http_code=http_code,
						error=description,
						response=j
					)
				
				return ok, description
				
		except Exception as exc:
			logger.error("telegram_set_webhook_exception", 
				webhook_url=url,
				telegram_url=telegram_url,
				exception_type=type(exc).__name__,
				exception_message=str(exc)
			)
			return False, str(exc)


