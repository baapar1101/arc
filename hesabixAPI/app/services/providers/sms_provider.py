from __future__ import annotations

from typing import Optional
from app.core.settings import get_settings
from app.services.providers.behin_sms_provider import BehinSmsProvider


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
		ارسال پیامک
		
		Args:
			to_phone: شماره گیرنده
			text: متن پیامک
		
		Returns:
			True اگر ارسال موفق باشد
		"""
		if not self.is_configured():
			return False
		
		# استفاده از BehinSmsProvider
		if self._provider:
			success, _, error_msg = self._provider.send_text(
				to_phone=to_phone,
				text=text,
				is_flash=self.is_flash
			)
			if not success and error_msg:
				import structlog
				logger = structlog.get_logger()
				logger.error("sms_send_failed", error=error_msg, phone=to_phone)
			return success
		
		# Fallback: اگر provider دیگری بود (برای آینده)
		return False
	
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


