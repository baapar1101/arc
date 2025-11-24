from __future__ import annotations

from app.core.settings import get_settings


class SmsProvider:
	def __init__(self, *, provider_name: str | None = None, api_key: str | None = None, sender: str | None = None) -> None:
		env = get_settings()
		self.provider_name = provider_name or env.sms_provider_name
		self.api_key = api_key or env.sms_api_key
		self.sender = sender or env.sms_sender

	def is_configured(self) -> bool:
		return bool(self.provider_name and self.api_key and self.sender)

	def send_text(self, *, to_phone: str, text: str) -> bool:
		# Minimal stub; integrate real provider later.
		if not self.is_configured():
			return False
		# Place-holder success
		return True


