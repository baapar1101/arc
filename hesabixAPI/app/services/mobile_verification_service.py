from __future__ import annotations

import hashlib
import random
from datetime import datetime, timedelta
from typing import Optional

from sqlalchemy.orm import Session

from adapters.db.models.user import User
from adapters.db.repositories.user_repo import UserRepository
from adapters.db.repositories.mobile_verification_repo import MobileVerificationRepository
from app.services.providers.sms_provider import SmsProvider
from app.services.system_settings_service import get_effective_notifications_settings
from app.core.responses import ApiError
from app.utils.phone_utils import normalize_phone_number
from app.core.settings import get_settings


def _hash_otp(otp: str) -> str:
	"""Hash کردن OTP برای ذخیره امن"""
	settings = get_settings()
	return hashlib.sha256(f"{settings.captcha_secret}:{otp}".encode("utf-8")).hexdigest()


def generate_otp() -> str:
	"""تولید کد OTP 6 رقمی"""
	return str(random.randint(100000, 999999))


class MobileVerificationService:
	def __init__(self, db: Session):
		self.db = db
		self.repo = MobileVerificationRepository(db)
		self.user_repo = UserRepository(db)
		
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
	
	def create_mobile_verification(self, user_id: int, mobile: str) -> str:
		"""
		ایجاد کد OTP و ارسال پیامک
		
		Args:
			user_id: شناسه کاربر
			mobile: شماره موبایل برای تایید
		
		Returns:
			OTP code (فقط برای تست، در production نباید برگردانده شود)
		
		Raises:
			ApiError: در صورت خطا
		"""
		# بررسی Rate Limiting (حداکثر 3 بار در ساعت)
		recent_count = self.repo.count_recent_by_user(user_id, hours=1)
		if recent_count >= 3:
			raise ApiError("RATE_LIMIT_EXCEEDED", "حداکثر 3 درخواست در ساعت امکان‌پذیر است. لطفاً بعداً تلاش کنید", http_status=429)
		
		# بررسی وجود کاربر
		user = self.user_repo.get_by_id(user_id)
		if not user:
			raise ApiError("USER_NOT_FOUND", "کاربر یافت نشد", http_status=404)
		
		# نرمال‌سازی شماره موبایل
		try:
			normalized_mobile = normalize_phone_number(mobile)
		except ValueError as e:
			raise ApiError("INVALID_MOBILE", str(e), http_status=400)
		
		# بررسی اینکه SMS Provider پیکربندی شده باشد
		if not self.sms_provider.is_configured():
			raise ApiError("SMS_NOT_CONFIGURED", "سرویس پیامک پیکربندی نشده است. لطفاً با مدیر سیستم تماس بگیرید", http_status=503)
		
		# تولید OTP
		otp_code = generate_otp()
		otp_hash = _hash_otp(otp_code)
		
		# زمان انقضا: 10 دقیقه
		expires_at = datetime.utcnow() + timedelta(minutes=10)
		
		# ذخیره در دیتابیس
		self.repo.create(
			user_id=user_id,
			mobile=normalized_mobile,
			otp_code_hash=otp_hash,
			expires_at=expires_at
		)
		
		# ارسال پیامک
		message = f"کد تایید شماره موبایل شما: {otp_code}\nاین کد تا 10 دقیقه اعتبار دارد."
		success = self.sms_provider.send_text(to_phone=normalized_mobile, text=message)
		
		if not success:
			# در صورت خطا در ارسال، log می‌کنیم اما خطا نمی‌دهیم
			# چون OTP در دیتابیس ذخیره شده و کاربر می‌تواند درخواست مجدد کند
			import structlog
			logger = structlog.get_logger()
			logger.error("sms_send_failed", user_id=user_id, mobile=normalized_mobile)
		
		return otp_code  # فقط برای تست
	
	def verify_mobile_otp(self, user_id: int, otp_code: str) -> bool:
		"""
		تایید کد OTP
		
		Args:
			user_id: شناسه کاربر
			otp_code: کد OTP وارد شده
		
		Returns:
			True اگر تایید موفق باشد
		
		Raises:
			ApiError: در صورت خطا
		"""
		if not otp_code or len(otp_code) != 6 or not otp_code.isdigit():
			raise ApiError("INVALID_OTP_FORMAT", "کد تایید باید 6 رقم باشد", http_status=400)
		
		# دریافت آخرین token فعال
		token = self.repo.get_active_by_user(user_id)
		if not token:
			raise ApiError("OTP_NOT_FOUND", "کد تایید یافت نشد یا منقضی شده است. لطفاً کد جدید دریافت کنید", http_status=404)
		
		# بررسی تعداد تلاش‌ها (حداکثر 5 تلاش)
		if token.attempts >= 5:
			raise ApiError("OTP_ATTEMPTS_EXCEEDED", "تعداد تلاش‌های مجاز به پایان رسیده است. لطفاً کد جدید دریافت کنید", http_status=429)
		
		# Hash کردن OTP و مقایسه
		otp_hash = _hash_otp(otp_code)
		if token.otp_code_hash != otp_hash:
			# افزایش تعداد تلاش‌های ناموفق
			self.repo.increment_attempts(token)
			remaining = 5 - token.attempts - 1
			raise ApiError("INVALID_OTP", f"کد تایید اشتباه است. {remaining} تلاش باقی مانده است", http_status=400)
		
		# تایید موفق
		self.repo.mark_verified(token)
		
		# به‌روزرسانی mobile_verified در User
		user = self.user_repo.get_by_id(user_id)
		if user:
			# بررسی اینکه شماره موبایل کاربر با شماره تایید شده یکسان باشد
			user_mobile = getattr(user, 'mobile', None)
			if user_mobile:
				try:
					normalized_user_mobile = normalize_phone_number(user_mobile)
					if normalized_user_mobile == token.mobile:
						user.mobile_verified = True
						self.db.add(user)
						self.db.commit()
				except ValueError:
					pass  # اگر شماره معتبر نباشد، فقط verified می‌کنیم
		
		return True
	
	def resend_otp(self, user_id: int) -> str:
		"""
		ارسال مجدد OTP
		
		Args:
			user_id: شناسه کاربر
		
		Returns:
			OTP code (فقط برای تست)
		
		Raises:
			ApiError: در صورت خطا
		"""
		user = self.user_repo.get_by_id(user_id)
		if not user:
			raise ApiError("USER_NOT_FOUND", "کاربر یافت نشد", http_status=404)
		
		mobile = getattr(user, 'mobile', None)
		if not mobile:
			raise ApiError("NO_MOBILE", "کاربر شماره موبایل ثبت نکرده است", http_status=400)
		
		return self.create_mobile_verification(user_id, mobile)

