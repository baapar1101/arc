from __future__ import annotations

import hashlib
import hmac
import os
import secrets
from datetime import datetime, timedelta

from argon2 import PasswordHasher

from app.core.settings import get_settings


_ph = PasswordHasher()


def hash_password(password: str) -> str:
	return _ph.hash(password)


def verify_password(password: str, password_hash: str) -> bool:
	try:
		_ph.verify(password_hash, password)
		return True
	except Exception:
		return False


def generate_api_key(prefix: str = "ak_live_", length: int = 32) -> tuple[str, str]:
	"""Return (public_key, key_hash). Store only key_hash in DB."""
	secret = secrets.token_urlsafe(length)
	api_key = f"{prefix}{secret}"
	settings = get_settings()
	key_hash = hashlib.sha256(f"{settings.captcha_secret}:{api_key}".encode("utf-8")).hexdigest()
	return api_key, key_hash


def consteq(a: str, b: str) -> bool:
	return hmac.compare_digest(a, b)


def hash_api_key(api_key: str) -> str:
	settings = get_settings()
	return hashlib.sha256(f"{settings.captcha_secret}:{api_key}".encode("utf-8")).hexdigest()


