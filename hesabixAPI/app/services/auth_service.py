from __future__ import annotations

from datetime import datetime, timedelta
from typing import Optional

import phonenumbers
from sqlalchemy.orm import Session

from adapters.db.repositories.user_repo import UserRepository
from adapters.db.repositories.api_key_repo import ApiKeyRepository
from app.core.security import hash_password, verify_password, generate_api_key, consteq
from app.core.settings import get_settings
from app.services.captcha_service import validate_captcha
from adapters.db.repositories.password_reset_repo import PasswordResetRepository
import hashlib


def _normalize_email(email: str | None) -> str | None:
	return email.lower().strip() if email else None


def _normalize_mobile(mobile: str | None) -> str | None:
	if not mobile:
		return None
	# Clean input: keep digits and leading plus
	raw = mobile.strip()
	raw = ''.join(ch for ch in raw if ch.isdigit() or ch == '+')
	try:
		from app.core.settings import get_settings
		settings = get_settings()
		region = None if raw.startswith('+') else settings.default_phone_region
		num = phonenumbers.parse(raw, region)
		if not phonenumbers.is_valid_number(num):
			return None
		return phonenumbers.format_number(num, phonenumbers.PhoneNumberFormat.E164)
	except Exception:
		return None


def _detect_identifier(identifier: str) -> tuple[str, str | None, str | None]:
	identifier = identifier.strip()
	if "@" in identifier:
		return "email", _normalize_email(identifier), None
	mobile = _normalize_mobile(identifier)
	return ("mobile", None, mobile) if mobile else ("invalid", None, None)


def register_user(*, db: Session, first_name: str | None, last_name: str | None, email: str | None, mobile: str | None, password: str, captcha_id: str, captcha_code: str) -> int:
	if not validate_captcha(db, captcha_id, captcha_code):
		from app.core.responses import ApiError
		raise ApiError("INVALID_CAPTCHA", "Invalid captcha code")

	email_n = _normalize_email(email)
	mobile_n = _normalize_mobile(mobile)
	if not email_n and not mobile_n:
		from app.core.responses import ApiError
		# اگر کاربر موبایل وارد کرده اما نامعتبر بوده، پیام دقیق‌تر بدهیم
		if mobile and mobile.strip():
			raise ApiError("INVALID_MOBILE", "Invalid mobile number")
		# در غیر این صورت، هیچ شناسهٔ معتبری ارائه نشده است
		raise ApiError("IDENTIFIER_REQUIRED", "Email or mobile is required")

	repo = UserRepository(db)
	if email_n and repo.get_by_email(email_n):
		from app.core.responses import ApiError
		raise ApiError("EMAIL_IN_USE", "Email is already in use")
	if mobile_n and repo.get_by_mobile(mobile_n):
		from app.core.responses import ApiError
		raise ApiError("MOBILE_IN_USE", "Mobile is already in use")

	pwd_hash = hash_password(password)
	user = repo.create(email=email_n, mobile=mobile_n, password_hash=pwd_hash, first_name=first_name, last_name=last_name)
	return user.id


def login_user(*, db: Session, identifier: str, password: str, captcha_id: str, captcha_code: str, device_id: str | None, user_agent: str | None, ip: str | None) -> tuple[str, datetime | None, dict]:
	if not validate_captcha(db, captcha_id, captcha_code):
		from app.core.responses import ApiError
		raise ApiError("INVALID_CAPTCHA", "Invalid captcha code")

	kind, email, mobile = _detect_identifier(identifier)
	if kind == "invalid":
		from app.core.responses import ApiError
		raise ApiError("INVALID_IDENTIFIER", "Identifier must be a valid email or mobile number")

	repo = UserRepository(db)
	user = repo.get_by_email(email) if email else repo.get_by_mobile(mobile)  # type: ignore[arg-type]
	if not user or not verify_password(password, user.password_hash):
		from app.core.responses import ApiError
		raise ApiError("INVALID_CREDENTIALS", "Invalid credentials")
	if not user.is_active:
		from app.core.responses import ApiError
		raise ApiError("ACCOUNT_DISABLED", "Your account is disabled")

	settings = get_settings()
	api_key, key_hash = generate_api_key()
	expires_at = None  # could be set from settings later
	api_repo = ApiKeyRepository(db)
	api_repo.create_session_key(user_id=user.id, key_hash=key_hash, device_id=device_id, user_agent=user_agent, ip=ip, expires_at=expires_at)

	user_data = {
		"id": user.id,
		"first_name": user.first_name,
		"last_name": user.last_name,
		"email": user.email,
		"mobile": user.mobile,
	}
	return api_key, expires_at, user_data


def _hash_reset_token(token: str) -> str:
	settings = get_settings()
	return hashlib.sha256(f"{settings.captcha_secret}:{token}".encode("utf-8")).hexdigest()


def create_password_reset(*, db: Session, identifier: str, captcha_id: str, captcha_code: str) -> str:
	if not validate_captcha(db, captcha_id, captcha_code):
		from app.core.responses import ApiError
		raise ApiError("INVALID_CAPTCHA", "Invalid captcha code")

	kind, email, mobile = _detect_identifier(identifier)
	if kind == "invalid":
		from app.core.responses import ApiError
		raise ApiError("INVALID_IDENTIFIER", "Identifier must be a valid email or mobile number")

	repo = UserRepository(db)
	user = repo.get_by_email(email) if email else repo.get_by_mobile(mobile)  # type: ignore[arg-type]
	# Always respond OK to avoid user enumeration; but skip creation if user not found
	if not user:
		return ""

	settings = get_settings()
	from secrets import token_urlsafe
	token = token_urlsafe(32)
	token_hash = _hash_reset_token(token)
	expires_at = datetime.utcnow() + timedelta(seconds=settings.reset_password_ttl_seconds)
	pr_repo = PasswordResetRepository(db)
	pr_repo.create(user_id=user.id, token_hash=token_hash, expires_at=expires_at)
	return token


def reset_password(*, db: Session, token: str, new_password: str, captcha_id: str, captcha_code: str) -> None:
	if not validate_captcha(db, captcha_id, captcha_code):
		from app.core.responses import ApiError
		raise ApiError("INVALID_CAPTCHA", "Invalid captcha code")

	pr_repo = PasswordResetRepository(db)
	token_hash = _hash_reset_token(token)
	pr = pr_repo.get_by_hash(token_hash)
	if not pr or pr.expires_at < datetime.utcnow() or pr.used_at is not None:
		from app.core.responses import ApiError
		raise ApiError("RESET_TOKEN_INVALID_OR_EXPIRED", "Reset token is invalid or expired")

	# Update user password
	user_repo = UserRepository(db)
	user = user_repo.db.get(type(user_repo).db.registry.mapped_classes['User'], pr.user_id)  # not ideal, fallback to direct get
	# Safer: direct session get
	from adapters.db.models.user import User
	user = user_repo.db.get(User, pr.user_id)
	if not user:
		from app.core.responses import ApiError
		raise ApiError("RESET_TOKEN_INVALID_OR_EXPIRED", "Reset token is invalid or expired")
	user.password_hash = hash_password(new_password)
	user_repo.db.add(user)
	user_repo.db.commit()

	pr_repo.mark_used(pr)



