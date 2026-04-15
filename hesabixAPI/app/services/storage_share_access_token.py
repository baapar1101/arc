"""توکن دسترسی کوتاه‌عمر برای دانلود/پخش فایل وقتی لینک اشتراک رمز دارد."""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
import time
from typing import Any

from app.core.settings import get_settings


def _b64url_encode(raw: bytes) -> str:
	return base64.urlsafe_b64encode(raw).decode("ascii").rstrip("=")


def _b64url_decode(data: str) -> bytes:
	padding = "=" * ((4 - len(data) % 4) % 4)
	return base64.urlsafe_b64decode(data + padding)


def _signing_secret() -> str:
	return (get_settings().share_link_secret or "change_me_share_link").strip()


def create_storage_share_access_token(share_id: int, ttl_seconds: int = 6 * 3600) -> str:
	exp = int(time.time()) + int(ttl_seconds)
	payload = json.dumps({"sid": share_id, "exp": exp}, separators=(",", ":")).encode("utf-8")
	body = _b64url_encode(payload)
	sig = hmac.new(_signing_secret().encode("utf-8"), body.encode("ascii"), hashlib.sha256).digest()
	return f"{body}.{_b64url_encode(sig)}"


def verify_storage_share_access_token(token: str) -> dict[str, Any] | None:
	try:
		parts = token.split(".")
		if len(parts) != 2:
			return None
		body, sig_b64 = parts
		expected_sig = hmac.new(_signing_secret().encode("utf-8"), body.encode("ascii"), hashlib.sha256).digest()
		if not hmac.compare_digest(_b64url_encode(expected_sig), sig_b64):
			return None
		data = json.loads(_b64url_decode(body).decode("utf-8"))
		sid = data.get("sid")
		exp = data.get("exp")
		if not isinstance(sid, int) or not isinstance(exp, int):
			return None
		if int(time.time()) > exp:
			return None
		return {"share_id": sid, "exp": exp}
	except Exception:
		return None
