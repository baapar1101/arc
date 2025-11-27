from __future__ import annotations

import hashlib
import random
from datetime import datetime, timedelta
from typing import Optional

from sqlalchemy.orm import Session

from adapters.db.models.user import User
from adapters.db.repositories.user_repo import UserRepository
from adapters.db.repositories.password_reset_repo import PasswordResetRepository
from app.services.providers.sms_provider import SmsProvider
from app.services.system_settings_service import get_effective_notifications_settings
from app.core.responses import ApiError
from app.utils.phone_utils import normalize_phone_number
from app.core.settings import get_settings
from app.core.security import hash_password, hash_api_key


def _hash_otp(otp: str) -> str:
	"""Hash کردن OTP برای ذخیره امن"""
	settings = get_settings()
	return hashlib.sha256(f"{settings.captcha_secret}:{otp}".encode("utf-8")).hexdigest()


def generate_otp() -> str:
	"""تولید کد OTP 6 رقمی"""
	return str(random.randint(100000, 999999))


class PasswordResetOtpService:
	"""
	Service برای مدیریت بازیابی کلمه عبور با استفاده از OTP از طریق SMS
	"""
	def __init__(self, db: Session):
		self.db = db
		self.user_repo = UserRepository(db)
		self.password_reset_repo = PasswordResetRepository(db)
		
		# تنظیم SMS Provider
		notify_cfg = get_effective_notifications_settings(db)
		self.sms_provider = SmsProvider(
			provider_name=notify_cfg.get("sms_provider_name"),
			api_key=notify_cfg.get("sms_api_key"),
			sender=notify_cfg.get("sms_sender"),
			username=notify_cfg.get("sms_provider_username"),
			password=notify_cfg.get("sms_provider_password"),
			is_flash=notify_cfg.get("sms_is_flash", False),
		)
	
	def send_reset_otp(self, identifier: str) -> str:
		"""
		ارسال OTP برای بازیابی کلمه عبور
		
		Args:
			identifier: ایمیل یا شماره موبایل کاربر
		
		Returns:
			OTP code (فقط برای تست، در production نباید برگردانده شود)
		
		Raises:
			ApiError: در صورت خطا
		"""
		from app.services.auth_service import _detect_identifier
		
		# تشخیص نوع identifier (email یا mobile)
		kind, email, mobile = _detect_identifier(identifier)
		if kind == "invalid":
			raise ApiError("INVALID_IDENTIFIER", "شناسه باید یک ایمیل یا شماره موبایل معتبر باشد", http_status=400)
		
		# دریافت کاربر
		user = self.user_repo.get_by_email(email) if email else self.user_repo.get_by_mobile(mobile)  # type: ignore[arg-type]
		
		# Always respond OK to avoid user enumeration
		if not user:
			# اگر کاربر پیدا نشد، برای امنیت همان response موفق برمی‌گردانیم
			return ""
		
		# بررسی اینکه کاربر شماره موبایل داشته باشد
		if not mobile:
			# اگر فقط ایمیل دارد، نمی‌توانیم OTP ارسال کنیم
			# در این حالت باید از روش ایمیل استفاده شود
			raise ApiError("NO_MOBILE", "کاربر شماره موبایل ثبت نکرده است. لطفاً از روش ایمیل استفاده کنید", http_status=400)
		
		# نرمال‌سازی شماره موبایل
		try:
			normalized_mobile = normalize_phone_number(mobile)
		except ValueError as e:
			raise ApiError("INVALID_MOBILE", str(e), http_status=400)
		
		# بررسی Rate Limiting (حداکثر 3 بار در 24 ساعت)
		recent_resets = self.password_reset_repo.count_recent_by_user(user.id, hours=24)
		if recent_resets >= 3:
			raise ApiError("RATE_LIMIT_EXCEEDED", "حداکثر 3 درخواست بازیابی رمز عبور در 24 ساعت امکان‌پذیر است. لطفاً بعداً تلاش کنید", http_status=429)
		
		# بررسی اینکه SMS Provider پیکربندی شده باشد
		if not self.sms_provider.is_configured():
			raise ApiError("SMS_NOT_CONFIGURED", "سرویس پیامک پیکربندی نشده است. لطفاً با مدیر سیستم تماس بگیرید", http_status=503)
		
		# تولید OTP
		otp_code = generate_otp()
		otp_hash = _hash_otp(otp_code)
		
		# ایجاد token برای reset password (با OTP hash به جای token معمولی)
		settings = get_settings()
		expires_at = datetime.utcnow() + timedelta(minutes=15)  # 15 دقیقه برای OTP
		
		# استفاده از PasswordResetRepository برای ذخیره
		# اما token_hash را با OTP hash پر می‌کنیم
		self.password_reset_repo.create(
			user_id=user.id,
			token_hash=otp_hash,
			expires_at=expires_at
		)
		
		# ارسال پیامک
		message = f"کد بازیابی کلمه عبور شما: {otp_code}\nاین کد تا 15 دقیقه اعتبار دارد."
		success = self.sms_provider.send_text(to_phone=normalized_mobile, text=message)
		
		if not success:
			import structlog
			logger = structlog.get_logger()
			logger.error("sms_reset_password_send_failed", user_id=user.id, mobile=normalized_mobile)
			# در صورت خطا، همچنان OTP را برمی‌گردانیم (برای تست)
		
		return otp_code  # فقط برای تست
	
	def verify_reset_otp(self, identifier: str, otp_code: str) -> tuple[bool, Optional[str]]:
		"""
		تایید OTP بازیابی کلمه عبور
		
		Args:
			identifier: ایمیل یا شماره موبایل کاربر
			otp_code: کد OTP وارد شده
		
		Returns:
			(success: bool, reset_token: Optional[str])
			- در صورت موفقیت، یک reset_token برمی‌گرداند که می‌تواند برای reset password استفاده شود
		
		Raises:
			ApiError: در صورت خطا
		"""
		from app.services.auth_service import _detect_identifier
		from secrets import token_urlsafe
		
		if not otp_code or len(otp_code) != 6 or not otp_code.isdigit():
			raise ApiError("INVALID_OTP_FORMAT", "کد تایید باید 6 رقم باشد", http_status=400)
		
		# تشخیص نوع identifier
		kind, email, mobile = _detect_identifier(identifier)
		if kind == "invalid":
			raise ApiError("INVALID_IDENTIFIER", "شناسه باید یک ایمیل یا شماره موبایل معتبر باشد", http_status=400)
		
		# دریافت کاربر
		user = self.user_repo.get_by_email(email) if email else self.user_repo.get_by_mobile(mobile)  # type: ignore[arg-type]
		if not user:
			# برای امنیت، همان خطا را می‌دهیم
			raise ApiError("INVALID_OTP", "کد تایید نامعتبر است", http_status=400)
		
		# Hash کردن OTP
		otp_hash = _hash_otp(otp_code)
		
		# دریافت آخرین token reset برای کاربر
		pr = self.password_reset_repo.get_by_user_and_hash(user.id, otp_hash)
		if not pr:
			raise ApiError("INVALID_OTP", "کد تایید نامعتبر است", http_status=400)
		
		# بررسی انقضا
		if pr.expires_at < datetime.utcnow():
			raise ApiError("OTP_EXPIRED", "کد تایید منقضی شده است. لطفاً کد جدید دریافت کنید", http_status=400)
		
		# بررسی استفاده شده
		if pr.used_at is not None:
			raise ApiError("OTP_ALREADY_USED", "این کد قبلاً استفاده شده است. لطفاً کد جدید دریافت کنید", http_status=400)
		
		# تایید موفق - ایجاد یک reset token جدید برای استفاده در reset_password
		# این token برای امنیت بیشتر است
		new_token = token_urlsafe(32)
		settings = get_settings()
		new_token_hash = hashlib.sha256(f"{settings.captcha_secret}:{new_token}".encode("utf-8")).hexdigest()
		
		# به‌روزرسانی token موجود
		pr.token_hash = new_token_hash
		pr.expires_at = datetime.utcnow() + timedelta(minutes=30)  # 30 دقیقه برای reset password
		self.db.add(pr)
		self.db.commit()
		
		return True, new_token

