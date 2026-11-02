"""تریگرهای ورک‌فلو برای چرخه نامه اتوماسیون اداری."""
from typing import Any, Dict

from app.services.workflow.triggers.base_trigger import BaseTrigger


class OaLetterLifecycleTrigger(BaseTrigger):
	"""تریگر عمومی رویدادهای نامه با فیلتر نوع نامه و محرمانگی."""

	def __init__(self, name: str, description: str):
		self._name = name
		self._description = description

	def execute(self, context: Dict[str, Any], config: Dict[str, Any]) -> Dict[str, Any]:
		trigger_data = context.get("trigger_data") or {}
		kind_filter = str(config.get("letter_kind_filter") or "").strip()
		if kind_filter and (trigger_data.get("letter_kind") or "") != kind_filter:
			return {}
		conf_filter = str(config.get("confidentiality_filter") or "").strip()
		if conf_filter and (trigger_data.get("confidentiality") or "") != conf_filter:
			return {}
		return super().execute(context, config)

	def get_metadata(self) -> Dict[str, Any]:
		return {
			"name": self._name,
			"description": self._description,
			"config_schema": {
				"enabled": {"type": "boolean", "description": "فعال/غیرفعال", "default": True, "required": False},
				"letter_kind_filter": {
					"type": "string",
					"description": "فقط این نوع نامه: incoming | outgoing | internal (خالی = همه)",
					"required": False,
				},
				"confidentiality_filter": {
					"type": "string",
					"description": "فقط این سطح محرمانگی: normal | confidential | highly_confidential | secret",
					"required": False,
				},
				"cooldown_seconds": {"type": "integer", "default": 0, "required": False},
			},
		}


class OaLetterRegisteredTrigger(OaLetterLifecycleTrigger):
	def __init__(self):
		super().__init__("ثبت نامه در دبیرخانه", "پس از شماره‌گذاری و ثبت نامه")


class OaLetterReferredTrigger(OaLetterLifecycleTrigger):
	def __init__(self):
		super().__init__("ارجاع نامه", "پس از ارجاع نامه به کارتابل سمت")


class OaLetterArchivedTrigger(OaLetterLifecycleTrigger):
	def __init__(self):
		super().__init__("بایگانی نامه", "پس از بایگانی نامه در پرونده")


class OaLetterDispatchedTrigger(OaLetterLifecycleTrigger):
	def __init__(self):
		super().__init__("ابلاغ نامه", "پس از ابلاغ رسمی نامه به سمت مخاطب")


class OaLetterSignedTrigger(OaLetterLifecycleTrigger):
	def __init__(self):
		super().__init__("امضای نامه", "پس از امضای یک مرحله از مسیر تأیید")
