from __future__ import annotations

import hashlib
import hmac
import os
import secrets
from datetime import datetime, timedelta

from argon2 import PasswordHasher
import bcrypt

from app.core.settings import get_settings

# تلاش برای استفاده از passlib برای پشتیبانی از فرمت $2y$
# استفاده از lazy loading برای جلوگیری از خطا در initialization
_PASSLIB_AVAILABLE = None
_pwd_context = None

def _get_passlib_context():
	"""Lazy loading برای passlib context"""
	global _PASSLIB_AVAILABLE, _pwd_context
	if _PASSLIB_AVAILABLE is None:
		try:
			from passlib.context import CryptContext
			_pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
			_PASSLIB_AVAILABLE = True
		except Exception:
			_PASSLIB_AVAILABLE = False
			_pwd_context = None
	return _pwd_context if _PASSLIB_AVAILABLE else None

_ph = PasswordHasher()


def hash_password(password: str) -> str:
	return _ph.hash(password)


def verify_password(password: str, password_hash: str) -> bool:
	"""
	بررسی رمز عبور با پشتیبانی از Argon2 و bcrypt (شامل فرمت $2y$)
	ابتدا سعی می‌کند با Argon2 verify کند، سپس با bcrypt
	برای فرمت $2y$ از passlib استفاده می‌کند (اگر در دسترس باشد)
	"""
	# ابتدا سعی می‌کنیم با Argon2 verify کنیم
	try:
		_ph.verify(password_hash, password)
		return True
	except Exception:
		pass
	
	# اگر Argon2 کار نکرد، سعی می‌کنیم با bcrypt verify کنیم
	try:
		# بررسی فرمت bcrypt
		if password_hash.startswith('$2y$') or password_hash.startswith('$2a$') or password_hash.startswith('$2b$'):
			# برای فرمت $2y$ از passlib استفاده می‌کنیم (اگر در دسترس باشد)
			if password_hash.startswith('$2y$'):
				pwd_ctx = _get_passlib_context()
				if pwd_ctx:
					try:
						# استفاده از passlib برای verify کردن $2y$
						# passlib می‌تواند $2y$ را handle کند
						return pwd_ctx.verify(password, password_hash)
					except (ValueError, TypeError) as e:
						# اگر خطای مربوط به طول رمز یا نوع داده بود، به fallback برویم
						# اما خطاهای دیگر را ignore می‌کنیم
						if "longer than 72 bytes" in str(e) or "truncate" in str(e):
							# اگر رمز خیلی طولانی است، آن را truncate کنیم
							password_truncated = password[:72]
							try:
								return pwd_ctx.verify(password_truncated, password_hash)
							except Exception:
								pass
					except Exception:
						# اگر passlib کار نکرد، به روش fallback برویم
						pass
			
			# برای $2a$ و $2b$ از bcrypt مستقیم استفاده می‌کنیم
			# برای $2y$ اگر passlib در دسترس نبود یا کار نکرد، سعی می‌کنیم تبدیل کنیم
			normalized_hash = password_hash
			if password_hash.startswith('$2y$'):
				# تبدیل $2y$ به $2b$ - این ممکن است کار نکند چون الگوریتم‌ها متفاوت هستند
				# اما برای fallback امتحان می‌کنیم
				normalized_hash = '$2b$' + password_hash[4:]
			
			# استفاده از bcrypt برای verify
			password_bytes = password.encode('utf-8')
			# اگر رمز خیلی طولانی است، آن را truncate کنیم (bcrypt فقط تا 72 بایت پشتیبانی می‌کند)
			if len(password_bytes) > 72:
				password_bytes = password_bytes[:72]
			return bcrypt.checkpw(password_bytes, normalized_hash.encode('utf-8'))
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


