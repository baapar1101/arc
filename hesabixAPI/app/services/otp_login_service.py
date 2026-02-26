from __future__ import annotations

import hashlib
import random
from datetime import datetime, timedelta
from typing import Optional, Tuple

from sqlalchemy.orm import Session

from adapters.db.models.user import User
from adapters.db.repositories.user_repo import UserRepository
from adapters.db.repositories.otp_login_repo import OtpLoginRepository
from app.services.providers.sms_provider import SmsProvider
from app.services.providers.email_provider import EmailProvider
from app.services.providers.telegram_provider import TelegramProvider
from app.services.providers.bale_provider import BaleProvider
from app.services.system_settings_service import get_effective_notifications_settings
from app.services.notification_service import NotificationService
from app.core.responses import ApiError
from app.utils.phone_utils import normalize_phone_number
from app.core.settings import get_settings
from app.core.security import generate_api_key
from adapters.db.repositories.api_key_repo import ApiKeyRepository


def _hash_otp(otp: str) -> str:
	"""Hash کردن OTP برای ذخیره امن"""
	settings = get_settings()
	return hashlib.sha256(f"{settings.captcha_secret}:{otp}".encode("utf-8")).hexdigest()


def generate_otp() -> str:
	"""تولید کد OTP 6 رقمی"""
	return str(random.randint(100000, 999999))


class OtpLoginService:
	"""
	Service برای مدیریت ورود با OTP از طریق SMS، Email یا Telegram
	"""
	def __init__(self, db: Session):
		self.db = db
		self.user_repo = UserRepository(db)
		self.otp_login_repo = OtpLoginRepository(db)
		
		# استفاده از NotificationService برای ارسال با قالب‌های قابل تنظیم
		self.notification_service = NotificationService(db)
		
		# نگه داشتن Providers برای مواردی که نیاز به fallback باشد
		notify_cfg = get_effective_notifications_settings(db)
		self.sms_provider = SmsProvider(
			provider_name=notify_cfg.get("sms_provider_name"),
			api_key=notify_cfg.get("sms_api_key"),
			sender=notify_cfg.get("sms_sender"),
			username=notify_cfg.get("sms_provider_username"),
			password=notify_cfg.get("sms_provider_password"),
			is_flash=notify_cfg.get("sms_is_flash", False),
		)
		self.email_provider = EmailProvider(db)
		self.telegram_provider = TelegramProvider(
			bot_token=notify_cfg.get("telegram_bot_token"),
			proxy_config=notify_cfg.get("telegram_proxy"),
		)
		self.bale_provider = BaleProvider(bot_token=notify_cfg.get("bale_bot_token"))
	
	def get_available_channels(self, identifier: str) -> dict:
		"""
		دریافت کانال‌های در دسترس برای یک identifier
		
		Args:
			identifier: ایمیل یا شماره موبایل
		
		Returns:
			dict با کلیدهای available_channels و user_info
		"""
		from app.services.auth_service import _detect_identifier
		import structlog
		logger = structlog.get_logger()
		
		kind, email, mobile = _detect_identifier(identifier)
		logger.info(f"get_available_channels - identifier: {identifier}, kind: {kind}, email: {email}, mobile: {mobile}")
		
		# اگر _detect_identifier شماره را تشخیص نداد یا mobile None است، سعی می‌کنیم با normalize_phone_number
		# این برای مواردی است که phonenumbers کتابخانه مشکل دارد یا تنظیمات درست نیست
		# اما فقط اگر identifier به نظر می‌رسد شماره تلفن باشد (حداقل 10 کاراکتر و شامل اعداد)
		if (kind == "invalid" or (kind == "mobile" and mobile is None)) and "@" not in identifier:
			# بررسی اولیه: اگر identifier خیلی کوتاه است یا فقط اعداد نیست، skip کن
			identifier_clean = identifier.strip().replace(' ', '').replace('-', '').replace('(', '').replace(')', '')
			if len(identifier_clean) >= 10 and any(c.isdigit() for c in identifier_clean):
				try:
					normalized_fallback = normalize_phone_number(identifier)
					mobile = normalized_fallback
					kind = "mobile"
					logger.info(f"get_available_channels - fallback to normalize_phone_number: {normalized_fallback}")
				except ValueError as e:
					# فقط در سطح debug لاگ کن، نه warning - چون این یک fallback است
					logger.debug(f"get_available_channels - normalize_phone_number failed (expected for invalid input): {e}")
					# return نکن، بگذار به بررسی بعدی برود
			else:
				# identifier خیلی کوتاه است یا فرمت نامعتبر - skip fallback
				logger.debug(f"get_available_channels - identifier too short or invalid format, skipping normalize_phone_number fallback")
		
		if kind == "invalid" or (kind == "mobile" and mobile is None):
			logger.warning(f"get_available_channels - invalid identifier: {identifier}")
			return {"available_channels": [], "user_info": None}
		
		# دریافت کاربر (برای بررسی telegram_chat_id)
		# توجه: mobile ممکن است در فرمت E164 باشد (+989...) یا در فرمت 09183282405
		user = None
		if email:
			user = self.user_repo.get_by_email(email)
			logger.info(f"get_available_channels - searched user by email {email}, found: {user is not None}")
		elif mobile:
			# لیست فرمت‌های ممکن برای جستجو
			search_formats = [mobile]  # فرمت اصلی
			
			# اگر در فرمت E164 است، فرمت نرمال‌سازی شده را هم اضافه کن
			if mobile.startswith('+'):
				try:
					normalized_for_search = normalize_phone_number(mobile)
					search_formats.append(normalized_for_search)
				except ValueError:
					pass
			# اگر در فرمت 0918... است، فرمت E164 را هم اضافه کن
			else:
				try:
					from app.services.auth_service import _normalize_mobile
					e164_mobile = _normalize_mobile(mobile)
					if e164_mobile:
						search_formats.append(e164_mobile)
				except Exception:
					pass
			
			# جستجو با همه فرمت‌های ممکن
			for search_format in search_formats:
				user = self.user_repo.get_by_mobile(search_format)
				if user:
					logger.info(f"get_available_channels - found user with format {search_format}, user_id: {user.id}, telegram_chat_id: {user.telegram_chat_id}")
					break
			
			if not user:
				logger.warning(f"get_available_channels - user not found with any format. Tried: {search_formats}")
		
		available_channels = []
		
		# بررسی SMS - اگر mobile وجود دارد (حتی اگر user پیدا نشده باشد)
		# چون ممکن است کاربر جدید باشد و بخواهد ثبت‌نام کند
		sms_configured = self.sms_provider.is_configured()
		logger.info(f"get_available_channels - SMS provider configured: {sms_configured}")
		if (mobile or (identifier and not email)) and sms_configured:
			available_channels.append("sms")
			logger.info(f"get_available_channels - SMS channel added")
		
		# بررسی Email - هم برای شناسهٔ ایمیل هم برای شناسهٔ موبایل (اگر کاربر در پروفایل ایمیل داشته باشد)
		email_configured = self.email_provider.is_configured()
		if user and getattr(user, "email", None) and email_configured:
			available_channels.append("email")
			logger.info(f"get_available_channels - Email channel added for user_id: {user.id}")
		
		# بررسی Telegram
		telegram_configured = self.telegram_provider.is_configured()
		logger.info(f"get_available_channels - Telegram provider configured: {telegram_configured}")
		if user:
			logger.info(f"get_available_channels - user found: id={user.id}, telegram_chat_id={user.telegram_chat_id}")
			if user.telegram_chat_id:
				if telegram_configured:
					available_channels.append("telegram")
					logger.info(f"get_available_channels - Telegram channel added for user_id: {user.id}, chat_id: {user.telegram_chat_id}")
				else:
					logger.warning(f"get_available_channels - user has telegram_chat_id but telegram_provider not configured")
			else:
				logger.warning(f"get_available_channels - user found but no telegram_chat_id - user_id: {user.id}")
		else:
			logger.warning(f"get_available_channels - user not found, cannot add telegram channel")
		
		# بررسی بله
		bale_configured = self.bale_provider.is_configured()
		if user and getattr(user, "bale_chat_id", None) and bale_configured:
			available_channels.append("bale")
			logger.info(f"get_available_channels - Bale channel added for user_id: {user.id}")
		
		return {
			"available_channels": available_channels,
			"user_info": {
				"has_telegram": bool(user and user.telegram_chat_id),
				"has_bale": bool(user and getattr(user, "bale_chat_id", None)),
				"has_email": bool(user and user.email),
				"has_mobile": bool(user and user.mobile),
			} if user else None
		}
	
	def send_login_otp(
		self,
		identifier: str,
		channel: str,
		ip_address: Optional[str] = None,
		user_agent: Optional[str] = None,
		session_id: Optional[str] = None  # برای تغییر کانال
	) -> Tuple[bool, Optional[str], Optional[str], Optional[dict]]:
		"""
		ارسال OTP برای ورود
		
		Args:
			identifier: ایمیل یا شماره موبایل کاربر
			channel: کانال ارسال (sms, email, telegram)
			ip_address: آدرس IP کاربر (اختیاری)
			user_agent: User Agent کاربر (اختیاری)
			session_id: شناسه session موجود (برای تغییر کانال)
		
		Returns:
			(success: bool, session_id: Optional[str], available_channels: Optional[dict])
		
		Raises:
			ApiError: در صورت خطا
		"""
		from app.services.auth_service import _detect_identifier
		import structlog
		logger = structlog.get_logger()
		
		# تشخیص نوع identifier
		kind, email, mobile = _detect_identifier(identifier)
		logger.info(f"send_login_otp - identifier: {identifier}, kind: {kind}, email: {email}, mobile: {mobile}")
		
		# اگر _detect_identifier شماره را تشخیص نداد یا mobile None است، سعی می‌کنیم با normalize_phone_number
		if (kind == "invalid" or (kind == "mobile" and mobile is None)) and "@" not in identifier:
			try:
				normalized_fallback = normalize_phone_number(identifier)
				mobile = normalized_fallback
				kind = "mobile"
				logger.info(f"send_login_otp - fallback to normalize_phone_number: {normalized_fallback}")
			except ValueError as e:
				logger.warning(f"send_login_otp - normalize_phone_number failed: {e}")
				raise ApiError("INVALID_IDENTIFIER", "شناسه باید یک ایمیل یا شماره موبایل معتبر باشد", http_status=400)
		
		if kind == "invalid" or (kind == "mobile" and mobile is None):
			raise ApiError("INVALID_IDENTIFIER", "شناسه باید یک ایمیل یا شماره موبایل معتبر باشد", http_status=400)
		
		# دریافت کاربر (برای بررسی telegram_chat_id و email)
		# توجه: mobile ممکن است در فرمت E164 باشد (+989...) یا در فرمت 09183282405
		user = None
		if email:
			user = self.user_repo.get_by_email(email)
			logger.info(f"send_login_otp - searched user by email {email}, found: {user is not None}")
		elif mobile:
			# لیست فرمت‌های ممکن برای جستجو
			search_formats = [mobile]  # فرمت اصلی
			
			# اگر در فرمت E164 است، فرمت نرمال‌سازی شده را هم اضافه کن
			if mobile.startswith('+'):
				try:
					normalized_for_search = normalize_phone_number(mobile)
					search_formats.append(normalized_for_search)
				except ValueError:
					pass
			# اگر در فرمت 0918... است، فرمت E164 را هم اضافه کن
			else:
				try:
					from app.services.auth_service import _normalize_mobile
					e164_mobile = _normalize_mobile(mobile)
					if e164_mobile:
						search_formats.append(e164_mobile)
				except Exception:
					pass
			
			# جستجو با همه فرمت‌های ممکن
			for search_format in search_formats:
				user = self.user_repo.get_by_mobile(search_format)
				if user:
					logger.info(f"send_login_otp - found user with format {search_format}, user_id: {user.id}, telegram_chat_id: {user.telegram_chat_id}")
					break
			
			if not user:
				logger.warning(f"send_login_otp - user not found with any format. Tried: {search_formats}")
		
		# نرمال‌سازی برای SMS و ذخیره در session
		# normalize_phone_number فرمت E164 را به 09183282405 تبدیل می‌کند
		# که برای ارسال SMS و ذخیره در session نیاز است
		normalized_mobile = None
		if mobile:
			try:
				normalized_mobile = normalize_phone_number(mobile)
			except ValueError as e:
				raise ApiError("INVALID_MOBILE", str(e), http_status=400)
		
		# بررسی Rate Limiting (حداکثر 3 بار در ساعت برای identifier)
		recent_count = self.otp_login_repo.count_recent_by_identifier(
			mobile=normalized_mobile,
			email=email,
			hours=1
		)
		if recent_count >= 3:
			raise ApiError("RATE_LIMIT_EXCEEDED", "حداکثر 3 درخواست ورود با OTP در ساعت امکان‌پذیر است. لطفاً بعداً تلاش کنید", http_status=429)
		
		# اگر session_id وجود دارد (تغییر کانال)، بررسی rate limiting برای تغییر کانال
		if session_id:
			session = self.otp_login_repo.get_by_session_id(session_id)
			if not session:
				raise ApiError("SESSION_NOT_FOUND", "Session یافت نشد یا منقضی شده است", http_status=404)
			
			# بررسی حداقل زمان بین ارسال‌ها (30 ثانیه)
			if session.last_otp_sent_at:
				time_since_last = (datetime.utcnow() - session.last_otp_sent_at).total_seconds()
				if time_since_last < 30:
					remaining = int(30 - time_since_last)
					raise ApiError("RATE_LIMIT_EXCEEDED", f"لطفاً {remaining} ثانیه صبر کنید قبل از ارسال مجدد", http_status=429)
		
		# بررسی کانال انتخابی
		available_channels_info = self.get_available_channels(identifier)
		if channel not in available_channels_info["available_channels"]:
			raise ApiError("CHANNEL_NOT_AVAILABLE", f"کانال {channel} برای این شناسه در دسترس نیست", http_status=400)
		
		# بررسی پیکربندی کانال
		if channel == "sms" and not self.sms_provider.is_configured():
			raise ApiError("SMS_NOT_CONFIGURED", "سرویس پیامک پیکربندی نشده است. لطفاً با مدیر سیستم تماس بگیرید", http_status=503)
		if channel == "email":
			if not user:
				# برای جلوگیری از user enumeration، همان خطای کانال را برمی‌گردانیم
				raise ApiError("CHANNEL_NOT_AVAILABLE", "کانال ایمیل برای این شناسه در دسترس نیست", http_status=400)
			if not self.email_provider.is_configured():
				raise ApiError("EMAIL_NOT_CONFIGURED", "سرویس ایمیل پیکربندی نشده است. لطفاً با مدیر سیستم تماس بگیرید", http_status=503)
		if channel == "telegram":
			logger.info(f"send_login_otp - checking telegram channel - user: {user is not None}, user_id: {user.id if user else None}, telegram_chat_id: {user.telegram_chat_id if user else None}")
			if not user:
				raise ApiError("CHANNEL_NOT_AVAILABLE", "کانال تلگرام برای این شناسه در دسترس نیست", http_status=400)
			if not user.telegram_chat_id:
				raise ApiError("CHANNEL_NOT_AVAILABLE", "کانال تلگرام برای این شناسه در دسترس نیست", http_status=400)
			if not self.telegram_provider.is_configured():
				raise ApiError("TELEGRAM_NOT_CONFIGURED", "سرویس تلگرام پیکربندی نشده است", http_status=503)
		if channel == "bale":
			if not user:
				raise ApiError("CHANNEL_NOT_AVAILABLE", "کانال بله برای این شناسه در دسترس نیست", http_status=400)
			if not getattr(user, "bale_chat_id", None):
				raise ApiError("CHANNEL_NOT_AVAILABLE", "کانال بله برای این شناسه در دسترس نیست", http_status=400)
			if not self.bale_provider.is_configured():
				raise ApiError("BALE_NOT_CONFIGURED", "سرویس بله پیکربندی نشده است", http_status=503)
		
		# تولید OTP
		otp_code = generate_otp()
		otp_hash = _hash_otp(otp_code)
		
		# زمان انقضا: 5 دقیقه
		expires_at = datetime.utcnow() + timedelta(minutes=5)
		
		# ایجاد یا به‌روزرسانی session
		if session_id:
			# تغییر کانال
			session = self.otp_login_repo.get_by_session_id(session_id)
			if not session:
				raise ApiError("SESSION_NOT_FOUND", "Session یافت نشد", http_status=404)
			self.otp_login_repo.update_channel(session, channel, otp_hash)
		else:
			# ایجاد session جدید
			session = self.otp_login_repo.create(
				mobile=normalized_mobile,
				email=email,
				channel=channel,
				otp_code_hash=otp_hash,
				expires_at=expires_at,
				ip_address=ip_address,
				user_agent=user_agent
			)
		
		# ارسال OTP از طریق کانال انتخابی با استفاده از NotificationService
		success = False
		
		# استفاده از NotificationService برای ارسال با قالب‌های قابل تنظیم
		if user:
			try:
				# آماده‌سازی context برای قالب
				context = {
					"code": otp_code,
					"expiry_minutes": 5,
				}
				
				# ارسال از طریق NotificationService
				success = self.notification_service.send(
					user_id=user.id,
					event_key="auth.otp_login",
					context=context,
					preferred_channels=[channel],
					locale="fa"  # یا می‌توانید از locale کاربر استفاده کنید
				)
			except Exception as e:
				logger.warning(f"خطا در ارسال از طریق NotificationService، استفاده از fallback: {e}")
				# Fallback به روش قدیمی
				success = False
		
		# Fallback: اگر NotificationService موفق نبود یا user وجود ندارد
		if not success:
			message = f"کد ورود شما: {otp_code}\nاین کد تا 5 دقیقه اعتبار دارد."
			
			if channel == "sms":
				success = self.sms_provider.send_text(to_phone=normalized_mobile, text=message)
				if not success:
					logger.error("sms_login_otp_send_failed", mobile=normalized_mobile)
			
			elif channel == "email":
				if user:
					success = self.email_provider.send(
						user_id=user.id,
						subject="کد ورود به حساب کاربری",
						body_text=message
					)
					if not success:
						logger.error("email_login_otp_send_failed", user_id=user.id, email=email)
			
			elif channel == "telegram":
				if not user or not user.telegram_chat_id:
					raise ApiError("TELEGRAM_NOT_CONNECTED", "حساب تلگرام شما به سیستم متصل نشده است", http_status=400)
				success = self.telegram_provider.send_text(
					chat_id=int(user.telegram_chat_id),
					text=message
				)
				if not success:
					logger.error("telegram_login_otp_send_failed", user_id=user.id, chat_id=user.telegram_chat_id)
			elif channel == "bale":
				if not user or not getattr(user, "bale_chat_id", None):
					raise ApiError("BALE_NOT_CONNECTED", "حساب بله شما به سیستم متصل نشده است", http_status=400)
				success = self.bale_provider.send_text(
					chat_id=int(user.bale_chat_id),
					text=message
				)
				if not success:
					logger.error("bale_login_otp_send_failed", user_id=user.id, chat_id=user.bale_chat_id)
		
		# به‌روزرسانی last_otp_sent_at (اگر session موجود است)
		if session:
			session.last_otp_sent_at = datetime.utcnow()
			self.db.add(session)
			self.db.commit()
		
		return success, session.session_id, available_channels_info
	
	def verify_login_otp(
		self,
		session_id: str,
		otp_code: str,
		device_id: Optional[str] = None,
		user_agent: Optional[str] = None,
		ip: Optional[str] = None
	) -> Tuple[bool, Optional[dict], Optional[str]]:
		"""
		تایید OTP و ورود کاربر
		
		Args:
			session_id: شناسه session
			otp_code: کد OTP وارد شده
			device_id: شناسه دستگاه (اختیاری)
			user_agent: User Agent (اختیاری)
			ip: آدرس IP (اختیاری)
		
		Returns:
			(success: bool, user_data: Optional[dict], api_key: Optional[str])
		
		Raises:
			ApiError: در صورت خطا
		"""
		if not otp_code or len(otp_code) != 6 or not otp_code.isdigit():
			raise ApiError("INVALID_OTP_FORMAT", "کد تایید باید 6 رقم باشد", http_status=400)
		
		# دریافت session
		session = self.otp_login_repo.get_by_session_id(session_id)
		if not session:
			raise ApiError("SESSION_NOT_FOUND", "Session یافت نشد یا منقضی شده است", http_status=404)
		
		# بررسی تعداد تلاش‌ها (حداکثر 5 تلاش)
		if session.attempts >= 5:
			raise ApiError("OTP_ATTEMPTS_EXCEEDED", "تعداد تلاش‌های مجاز به پایان رسیده است. لطفاً کد جدید دریافت کنید", http_status=429)
		
		# Hash کردن OTP و مقایسه
		otp_hash = _hash_otp(otp_code)
		if session.otp_code_hash != otp_hash:
			# افزایش تعداد تلاش‌های ناموفق
			self.otp_login_repo.increment_attempts(session)
			remaining = 5 - session.attempts - 1
			raise ApiError("INVALID_OTP", f"کد تایید اشتباه است. {remaining} تلاش باقی مانده است", http_status=400)
		
		# دریافت کاربر از identifier (mobile یا email)
		# توجه: session.mobile در فرمت 09183282405 ذخیره شده است
		# اما دیتابیس users شماره را در فرمت E164 (+989183282405) ذخیره می‌کند
		# پس باید آن را به E164 تبدیل کنیم
		user = None
		if session.mobile:
			from app.services.auth_service import _normalize_mobile
			# تبدیل فرمت 09183282405 به +989183282405
			mobile_e164 = _normalize_mobile(session.mobile)
			if mobile_e164:
				user = self.user_repo.get_by_mobile(mobile_e164)
		elif session.email:
			user = self.user_repo.get_by_email(session.email)
		
		if not user:
			raise ApiError("USER_NOT_FOUND", "کاربری با این شناسه یافت نشد", http_status=404)
		
		if not user.is_active:
			raise ApiError("ACCOUNT_DISABLED", "حساب کاربری شما غیرفعال شده است", http_status=403)
		
		# تایید موفق - ایجاد API Key
		api_key, key_hash = generate_api_key()
		
		# Session keys برای کاربران فرانت‌اند نامحدود هستند (expires_at=None)
		# فقط personal API keys می‌توانند expires_at داشته باشند
		api_repo = ApiKeyRepository(self.db)
		api_repo.create_session_key(
			user_id=user.id,
			key_hash=key_hash,
			device_id=device_id,
			user_agent=user_agent or session.user_agent,
			ip=ip or session.ip_address,
			expires_at=None
		)
		
		# علامت‌گذاری session به عنوان تایید شده
		self.otp_login_repo.mark_verified(session, user.id)
		
		# آماده‌سازی اطلاعات کاربر
		user_data = {
			"id": user.id,
			"first_name": user.first_name,
			"last_name": user.last_name,
			"email": user.email,
			"mobile": user.mobile,
			"referral_code": getattr(user, "referral_code", None),
			"email_verified": getattr(user, "email_verified", False),
			"mobile_verified": getattr(user, "mobile_verified", False),
		}
		
		return True, user_data, api_key

