# noqa: D100
"""تریگرهای ورک‌فلو برای چت وب CRM."""
from __future__ import annotations

from typing import Any, Dict

from app.services.workflow.triggers.base_trigger import BaseTrigger


class ChatConversationStartedTrigger(BaseTrigger):
	def get_metadata(self) -> Dict[str, Any]:
		return {
			"name": "شروع مکالمه چت وب",
			"description": "اولین ثبت مکالمه پس از تکمیل فرم بازدیدکننده (نام، ایمیل، تلفن)",
			"config_schema": {
				"enabled": {"type": "boolean", "description": "فعال/غیرفعال", "default": True, "required": False},
				"widget_id_filter": {
					"type": "integer",
					"description": "فقط برای این ویجت (خالی = همه)",
					"required": False,
				},
				"cooldown_seconds": {"type": "integer", "default": 0, "required": False},
			},
		}

	def execute(self, context: Dict[str, Any], config: Dict[str, Any]) -> Dict[str, Any]:
		td = context.get("trigger_data", {})
		if config.get("widget_id_filter") is not None:
			if td.get("widget_id") != config.get("widget_id_filter"):
				return {}
		return super().execute(context, config)


class ChatMessageReceivedTrigger(BaseTrigger):
	def get_metadata(self) -> Dict[str, Any]:
		return {
			"name": "پیام جدید از بازدیدکننده (چت وب)",
			"description": "زمانی که بازدیدکننده سایت پیام متنی بفرستد",
			"config_schema": {
				"enabled": {"type": "boolean", "default": True, "required": False},
				"widget_id_filter": {"type": "integer", "required": False},
				"cooldown_seconds": {"type": "integer", "default": 0, "required": False},
			},
		}

	def execute(self, context: Dict[str, Any], config: Dict[str, Any]) -> Dict[str, Any]:
		td = context.get("trigger_data", {})
		if config.get("widget_id_filter") is not None:
			if td.get("widget_id") != config.get("widget_id_filter"):
				return {}
		return super().execute(context, config)


class ChatMessageSentTrigger(BaseTrigger):
	def get_metadata(self) -> Dict[str, Any]:
		return {
			"name": "پاسخ عامل در چت وب",
			"description": "زمانی که کاربر CRM پیام بفرستد",
			"config_schema": {
				"enabled": {"type": "boolean", "default": True, "required": False},
				"widget_id_filter": {"type": "integer", "required": False},
				"cooldown_seconds": {"type": "integer", "default": 0, "required": False},
			},
		}

	def execute(self, context: Dict[str, Any], config: Dict[str, Any]) -> Dict[str, Any]:
		td = context.get("trigger_data", {})
		if config.get("widget_id_filter") is not None:
			if td.get("widget_id") != config.get("widget_id_filter"):
				return {}
		return super().execute(context, config)


class ChatConversationAssignedTrigger(BaseTrigger):
	def execute(self, context: Dict[str, Any], config: Dict[str, Any]) -> Dict[str, Any]:
		td = context.get("trigger_data", {})
		if config.get("widget_id_filter") is not None:
			if td.get("widget_id") != config.get("widget_id_filter"):
				return {}
		if config.get("new_assigned_to_user_id_filter") is not None:
			if td.get("new_assigned_to_user_id") != config.get("new_assigned_to_user_id_filter"):
				return {}
		return super().execute(context, config)

	def get_metadata(self) -> Dict[str, Any]:
		return {
			"name": "تخصیص مکالمه چت وب",
			"description": "تغییر کاربر مسئول مکالمه",
			"config_schema": {
				"enabled": {"type": "boolean", "default": True, "required": False},
				"widget_id_filter": {
					"type": "integer",
					"description": "فقط برای این ویجت چت (خالی = همه)",
					"required": False,
				},
				"new_assigned_to_user_id_filter": {"type": "integer", "required": False},
				"cooldown_seconds": {"type": "integer", "default": 0, "required": False},
			},
		}


class ChatConversationResolvedTrigger(BaseTrigger):
	def execute(self, context: Dict[str, Any], config: Dict[str, Any]) -> Dict[str, Any]:
		td = context.get("trigger_data", {})
		if config.get("widget_id_filter") is not None:
			if td.get("widget_id") != config.get("widget_id_filter"):
				return {}
		return super().execute(context, config)

	def get_metadata(self) -> Dict[str, Any]:
		return {
			"name": "حل‌شدن مکالمه چت وب",
			"description": "وضعیت مکالمه به resolved تغییر کرد",
			"config_schema": {
				"enabled": {"type": "boolean", "default": True, "required": False},
				"widget_id_filter": {
					"type": "integer",
					"description": "فقط برای این ویجت چت (خالی = همه)",
					"required": False,
				},
				"cooldown_seconds": {"type": "integer", "default": 0, "required": False},
			},
		}


class ChatConversationReopenedTrigger(BaseTrigger):
	def execute(self, context: Dict[str, Any], config: Dict[str, Any]) -> Dict[str, Any]:
		td = context.get("trigger_data", {})
		if config.get("widget_id_filter") is not None:
			if td.get("widget_id") != config.get("widget_id_filter"):
				return {}
		return super().execute(context, config)

	def get_metadata(self) -> Dict[str, Any]:
		return {
			"name": "بازگشایی مکالمه چت وب",
			"description": "خروج از وضعیت resolved یا تغییر وضعیت",
			"config_schema": {
				"enabled": {"type": "boolean", "default": True, "required": False},
				"widget_id_filter": {
					"type": "integer",
					"description": "فقط برای این ویجت چت (خالی = همه)",
					"required": False,
				},
				"cooldown_seconds": {"type": "integer", "default": 0, "required": False},
			},
		}
