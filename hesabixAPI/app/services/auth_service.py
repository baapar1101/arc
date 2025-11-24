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


def _generate_referral_code(db: Session) -> str:
	from secrets import token_urlsafe
	repo = UserRepository(db)
	# try a few times to ensure uniqueness
	for _ in range(10):
		code = token_urlsafe(8).replace('-', '').replace('_', '')[:10]
		if not repo.get_by_referral_code(code):
			return code
	# fallback longer code
	return token_urlsafe(12).replace('-', '').replace('_', '')[:12]


def register_user(*, db: Session, first_name: str | None, last_name: str | None, email: str | None, mobile: str | None, password: str, captcha_id: str, captcha_code: str, referrer_code: str | None = None, base_url: str | None = None) -> int:
	from app.core.responses import ApiError
	from app.services.system_settings_service import is_registration_enabled, get_max_users
	
	# بررسی فعال بودن ثبت‌نام
	if not is_registration_enabled(db):
		raise ApiError("REGISTRATION_DISABLED", "ثبت‌نام در حال حاضر غیرفعال است", http_status=403)
	
	# بررسی محدودیت تعداد کاربران
	max_users = get_max_users(db)
	if max_users > 0:  # 0 به معنی نامحدود است
		repo = UserRepository(db)
		current_user_count = repo.count_all()
		if current_user_count >= max_users:
			raise ApiError("MAX_USERS_REACHED", f"حداکثر تعداد کاربران ({max_users}) رسیده است", http_status=403)
	
	if not validate_captcha(db, captcha_id, captcha_code):
		raise ApiError("INVALID_CAPTCHA", "Invalid captcha code")

	email_n = _normalize_email(email)
	mobile_n = _normalize_mobile(mobile)
	if not email_n and not mobile_n:
		# اگر کاربر موبایل وارد کرده اما نامعتبر بوده، پیام دقیق‌تر بدهیم
		if mobile and mobile.strip():
			raise ApiError("INVALID_MOBILE", "Invalid mobile number")
		# در غیر این صورت، هیچ شناسهٔ معتبری ارائه نشده است
		raise ApiError("IDENTIFIER_REQUIRED", "Email or mobile is required")

	repo = UserRepository(db)
	if email_n and repo.get_by_email(email_n):
		raise ApiError("EMAIL_IN_USE", "Email is already in use")
	if mobile_n and repo.get_by_mobile(mobile_n):
		raise ApiError("MOBILE_IN_USE", "Mobile is already in use")

	pwd_hash = hash_password(password)
	referred_by_user_id = None
	if referrer_code:
		ref_user = repo.get_by_referral_code(referrer_code)
		if ref_user:
			# prevent self-referral at signup theoretically not applicable; rule kept for safety
			referred_by_user_id = ref_user.id
	referral_code = _generate_referral_code(db)
	
	# تنظیم email_verified بر اساس enable_email_verification
	from app.services.system_settings_service import is_email_verification_enabled
	email_verified = not is_email_verification_enabled(db)  # اگر verification فعال باشد، false است
	
	user = repo.create(
		email=email_n,
		mobile=mobile_n,
		password_hash=pwd_hash,
		first_name=first_name,
		last_name=last_name,
		referral_code=referral_code,
		referred_by_user_id=referred_by_user_id,
		email_verified=email_verified
	)
	
	# اگر email verification فعال باشد و کاربر ایمیل دارد، token ایجاد و ایمیل ارسال کن
	if is_email_verification_enabled(db) and email_n:
		try:
			from app.services.email_verification_service import create_email_verification_token
			create_email_verification_token(db, user.id, email_n, base_url=base_url)
		except Exception as e:
			# در صورت خطا در ارسال ایمیل، ثبت‌نام ادامه می‌یابد اما log می‌کنیم
			import logging
			logger = logging.getLogger(__name__)
			logger.error(f"Failed to send verification email for user {user.id}: {e}")
	
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

	from app.services.system_settings_service import get_session_timeout
	from datetime import timedelta
	
	settings = get_settings()
	api_key, key_hash = generate_api_key()
	
	# تنظیم زمان انقضای نشست
	session_timeout = get_session_timeout(db)
	expires_at = None
	if session_timeout > 0:  # 0 به معنی نامحدود است
		expires_at = datetime.utcnow() + timedelta(minutes=session_timeout)
	
	api_repo = ApiKeyRepository(db)
	api_repo.create_session_key(user_id=user.id, key_hash=key_hash, device_id=device_id, user_agent=user_agent, ip=ip, expires_at=expires_at)

	user_data = {
		"id": user.id,
		"first_name": user.first_name,
		"last_name": user.last_name,
		"email": user.email,
		"mobile": user.mobile,
		"referral_code": getattr(user, "referral_code", None),
		"email_verified": getattr(user, "email_verified", False),
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
	from adapters.db.models.user import User
	user = db.get(User, pr.user_id)
	if not user:
		from app.core.responses import ApiError
		raise ApiError("RESET_TOKEN_INVALID_OR_EXPIRED", "Reset token is invalid or expired")
	user.password_hash = hash_password(new_password)
	db.add(user)
	db.commit()

	pr_repo.mark_used(pr)




def change_password(*, db: Session, user_id: int, current_password: str, new_password: str, confirm_password: str, translator=None) -> None:
	"""
	تغییر کلمه عبور کاربر
	"""
	# بررسی تطبیق کلمه عبور جدید و تکرار آن
	if new_password != confirm_password:
		from app.core.responses import ApiError
		raise ApiError("PASSWORDS_DO_NOT_MATCH", "New password and confirm password do not match", translator=translator)
	
	# بررسی اینکه کلمه عبور جدید با کلمه عبور فعلی متفاوت باشد
	if current_password == new_password:
		from app.core.responses import ApiError
		raise ApiError("SAME_PASSWORD", "New password must be different from current password", translator=translator)
	
	# دریافت کاربر
	from adapters.db.models.user import User
	user = db.get(User, user_id)
	if not user:
		from app.core.responses import ApiError
		raise ApiError("USER_NOT_FOUND", "User not found", translator=translator)
	
	# بررسی کلمه عبور فعلی
	if not verify_password(current_password, user.password_hash):
		from app.core.responses import ApiError
		raise ApiError("INVALID_CURRENT_PASSWORD", "Current password is incorrect", translator=translator)
	
	# بررسی اینکه کاربر فعال باشد
	if not user.is_active:
		from app.core.responses import ApiError
		raise ApiError("ACCOUNT_DISABLED", "Your account is disabled", translator=translator)
	
	# تغییر کلمه عبور
	user.password_hash = hash_password(new_password)
	db.add(user)
	db.commit()


def referral_stats(*, db: Session, user_id: int, start: datetime | None = None, end: datetime | None = None) -> dict:
	from adapters.db.repositories.user_repo import UserRepository
	repo = UserRepository(db)
	# totals
	total = repo.count_referred(user_id)
	# month
	now = datetime.utcnow()
	month_start = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
	next_month = (month_start.replace(day=28) + timedelta(days=4)).replace(day=1)
	month_count = repo.count_referred_between(user_id, month_start, next_month)
	# today
	today_start = now.replace(hour=0, minute=0, second=0, microsecond=0)
	tomorrow = today_start + timedelta(days=1)
	today_count = repo.count_referred_between(user_id, today_start, tomorrow)
	# custom range
	custom = None
	if start and end:
		custom = repo.count_referred_between(user_id, start, end)
	return {
		"total": total,
		"this_month": month_count,
		"today": today_count,
		"range": custom,
	}


def referral_list(*, db: Session, user_id: int, start: datetime | None = None, end: datetime | None = None, search: str | None = None, page: int = 1, limit: int = 20) -> dict:
	from adapters.db.repositories.user_repo import UserRepository
	repo = UserRepository(db)
	page = max(1, page)
	limit = max(1, min(100, limit))
	offset = (page - 1) * limit
	items = repo.list_referred(user_id, start_dt=start, end_dt=end, search=search, offset=offset, limit=limit)
	total = repo.count_referred_filtered(user_id, start_dt=start, end_dt=end, search=search)
	def mask_email(email: str | None) -> str | None:
		if not email:
			return None
		try:
			local, _, domain = email.partition('@')
			if len(local) <= 2:
				masked_local = local[0] + "*"
			else:
				masked_local = local[0] + "*" * (len(local) - 2) + local[-1]
			return masked_local + "@" + domain
		except Exception:
			return email
	result = []
	for u in items:
		result.append({
			"id": u.id,
			"first_name": u.first_name,
			"last_name": u.last_name,
			"email": mask_email(u.email),
			"created_at": u.created_at.isoformat(),
		})
	return {"items": result, "total": total, "page": page, "limit": limit}