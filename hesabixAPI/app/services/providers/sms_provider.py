from __future__ import annotations

from app.core.settings import get_settings


class SmsProvider:
	def __init__(self) -> None:
		self.settings = get_settings()

	def is_configured(self) -> bool:
		return bool(self.settings.sms_provider_name and self.settings.sms_api_key and self.settings.sms_sender)

	def send_text(self, *, to_phone: str, text: str) -> bool:
		# Minimal stub; integrate real provider later.
		if not self.is_configured():
			return False
		# Place-holder success
		return True


