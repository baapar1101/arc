from __future__ import annotations

from typing import Optional, Tuple
from app.core.settings import get_settings
from app.services.providers.behin_sms_provider import BehinSmsProvider
from app.utils.phone_utils import normalize_phone_number


class SmsProvider:
	def __init__(
		self,
		*,
		provider_name: str | None = None,
		api_key: str | None = None,
		sender: str | None = None,
		username: str | None = None,
		password: str | None = None,
		is_flash: bool = False
	) -> None:
		env = get_settings()
		self.provider_name = provider_name or env.sms_provider_name
		self.api_key = api_key or env.sms_api_key
		self.sender = sender or env.sms_sender
		self.username = username
		self.password = password
		self.is_flash = is_flash
		
		# مقداردهی Provider واقعی
		self._provider: Optional[BehinSmsProvider] = None
		if self.provider_name == "behinsms" or self.provider_name == "behin_sms":
			if self.username and self.password and self.sender:
				try:
					self._provider = BehinSmsProvider(
						username=self.username,
						password=self.password,
						sender=self.sender
					)
				except Exception as e:
					# Log error but don't fail initialization
					import structlog
					logger = structlog.get_logger()
					logger.error("failed_to_init_behinsms", error=str(e))

	def is_configured(self) -> bool:
		if self.provider_name in ("behinsms", "behin_sms"):
			return bool(self.username and self.password and self.sender)
		return bool(self.provider_name and self.api_key and self.sender)

	def send_text(self, *, to_phone: str, text: str) -> bool:
		"""
		ارسال پیامک (متد قدیمی برای سازگاری با کد موجود)
		
		Args:
			to_phone: شماره گیرنده
			text: متن پیامک
		
		Returns:
			True اگر ارسال موفق باشد
		"""
		success, _ = self.send_text_with_error(to_phone=to_phone, text=text)
		return success
	
	def send_text_with_error(self, *, to_phone: str, text: str) -> Tuple[bool, Optional[str]]:
		"""
		ارسال پیامک با برگرداندن پیام خطا
		
		Args:
			to_phone: شماره گیرنده
			text: متن پیامک
		
		Returns:
			(success: bool, error_message: Optional[str])
		"""
		success, _, error_msg = self.send_text_with_details(to_phone=to_phone, text=text)
		return success, error_msg
	
	def send_text_with_details(self, *, to_phone: str, text: str) -> Tuple[bool, Optional[str], Optional[str]]:
		"""
		ارسال پیامک با برگرداندن جزئیات کامل (message_id و error)
		
		Args:
			to_phone: شماره گیرنده
			text: متن پیامک
		
		Returns:
			(success: bool, message_id: Optional[str], error_message: Optional[str])
		"""
		if not self.is_configured():
			return False, None, "SMS Provider پیکربندی نشده است"
		
		# نرمال‌سازی شماره موبایل
		try:
			normalized_phone = normalize_phone_number(to_phone)
		except ValueError as e:
			return False, None, f"فرمت شماره موبایل نامعتبر: {str(e)}"
		
		# بررسی متن پیامک
		if not text or not text.strip():
			return False, None, "متن پیامک خالی است"
		
		# استفاده از BehinSmsProvider
		if self._provider:
			try:
				success, message_id, error_msg = self._provider.send_text(
					to_phone=normalized_phone,
					text=text,
					is_flash=self.is_flash
				)
				if not success and error_msg:
					import structlog
					logger = structlog.get_logger()
					logger.error("sms_send_failed", error=error_msg, phone=normalized_phone)
				return success, message_id, error_msg
			except Exception as e:
				import structlog
				logger = structlog.get_logger()
				logger.error("sms_send_exception", error=str(e), phone=normalized_phone, exc_info=True)
				return False, None, f"خطای غیرمنتظره در ارسال SMS: {str(e)}"
		
		# Fallback: اگر provider دیگری بود (برای آینده)
		return False, None, "Provider پشتیبانی نمی‌شود"
	
	def get_credit(self) -> tuple[bool, Optional[float], Optional[str]]:
		"""
		دریافت اعتبار باقیمانده
		
		Returns:
			(success, credit_amount, error_message)
		"""
		if not self.is_configured():
			return False, None, "SMS Provider پیکربندی نشده است"
		
		if self._provider:
			return self._provider.get_credit()
		
		return False, None, "Provider پشتیبانی نمی‌شود"


