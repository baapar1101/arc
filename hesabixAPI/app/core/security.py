from __future__ import annotations

import hashlib
import hmac
import os
import secrets
from datetime import datetime, timedelta

from argon2 import PasswordHasher
import bcrypt

from app.core.settings import get_settings

# محدودیت طول رمز برای bcrypt (بایت)
BCRYPT_MAX_PASSWORD_BYTES = 72

_ph = PasswordHasher()


def hash_password(password: str) -> str:
	return _ph.hash(password)


def _truncate_password_for_bcrypt(password: str) -> bytes:
	"""رمز را برای استفاده در bcrypt به حداکثر ۷۲ بایت محدود می‌کند (محدودیت bcrypt)."""
	password_bytes = password.encode("utf-8")
	if len(password_bytes) > BCRYPT_MAX_PASSWORD_BYTES:
		password_bytes = password_bytes[:BCRYPT_MAX_PASSWORD_BYTES]
	return password_bytes


def verify_password(password: str, password_hash: str) -> bool:
	"""
	بررسی رمز عبور با پشتیبانی از Argon2 و bcrypt (شامل فرمت $2y$).
	ابتدا Argon2، سپس bcrypt با نرمال‌سازی $2y$ به $2b$ و محدودیت ۷۲ بایت.
	"""
	# ابتدا سعی می‌کنیم با Argon2 verify کنیم
	try:
		_ph.verify(password_hash, password)
		return True
	except Exception:
		pass

	# اگر Argon2 کار نکرد، با bcrypt (بدون passlib برای جلوگیری از خطای __about__)
	try:
		if password_hash.startswith("$2y$") or password_hash.startswith("$2a$") or password_hash.startswith("$2b$"):
			normalized_hash = password_hash
			if password_hash.startswith("$2y$"):
				normalized_hash = "$2b$" + password_hash[4:]
			password_bytes = _truncate_password_for_bcrypt(password)
			return bcrypt.checkpw(password_bytes, normalized_hash.encode("utf-8"))
	except Exception:
		pass

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


