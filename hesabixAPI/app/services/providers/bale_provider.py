from __future__ import annotations

import json
from typing import Any, Dict, Optional
from urllib import request

import httpx
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

	def send_document(
		self,
		chat_id: int,
		file_bytes: bytes,
		filename: str,
		caption: str | None = None,
	) -> bool:
		"""
		ارسال فایل (مستند) به چت؛ API مشابه تلگرام: sendDocument
		https://docs.bale.ai/ — multipart/form-data
		"""
		if not self.is_configured():
			return False
		token = self.bot_token
		assert token
		url = f"{BALE_API_BASE}/bot{token}/sendDocument"
		data: Dict[str, Any] = {"chat_id": str(int(chat_id))}
		if caption is not None and str(caption).strip():
			data["caption"] = str(caption).strip()[:1024]
		files = {
			"document": (filename or "file.bin", file_bytes, "application/octet-stream"),
		}
		try:
			with httpx.Client(timeout=120.0) as client:
				resp = client.post(url, data=data, files=files)
			if resp.status_code != 200:
				logger.warning(
					"bale_send_document_http",
					status=resp.status_code,
					body=resp.text[:500],
				)
				return False
			try:
				j = resp.json()
			except Exception:
				return False
			ok = j.get("ok") is True
			if not ok:
				logger.warning("bale_send_document_failed", response=j)
			return ok
		except Exception as exc:
			logger.error(
				"bale_send_document_exception",
				chat_id=chat_id,
				exception_type=type(exc).__name__,
				exception_message=str(exc),
			)
			return False

	def set_webhook(self, *, url: str, drop_pending_updates: bool = False) -> tuple[bool, str | None]:
		"""
		ثبت وب‌هوک ربات در بله. طبق مستندات: https://docs.bale.ai/
		پورت‌های مجاز: 443، 88
		"""
		if not self.is_configured():
			logger.warning("bale_set_webhook_failed", reason="bot_not_configured")
			return False, "bot_not_configured"

		token = self.bot_token
		assert token
		api_url = f"{BALE_API_BASE}/bot{token}/setWebhook"
		payload: Dict[str, Any] = {"url": url}
		if drop_pending_updates:
			payload["drop_pending_updates"] = True

		body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
		req = request.Request(api_url, data=body, method="POST")
		req.add_header("Content-Type", "application/json")
		try:
			with request.urlopen(req, timeout=10) as resp:
				raw = resp.read().decode("utf-8")
				j = json.loads(raw)
				ok = j.get("ok") is True
				description = j.get("description")
				if ok:
					logger.info("bale_set_webhook_success", webhook_url=url)
				else:
					logger.warning("bale_set_webhook_failed", webhook_url=url, response=j)
				return ok, description
		except Exception as exc:
			logger.error(
				"bale_set_webhook_exception",
				webhook_url=url,
				exception_type=type(exc).__name__,
				exception_message=str(exc),
			)
			return False, str(exc)
