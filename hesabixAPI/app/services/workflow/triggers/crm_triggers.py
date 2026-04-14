"""
Triggerهای مربوط به CRM (سرنخ، فرصت فروش)
"""

from typing import Any, Dict
from app.services.workflow.triggers.base_trigger import BaseTrigger


class LeadCreatedTrigger(BaseTrigger):
    """Trigger برای ایجاد سرنخ"""

    def execute(self, context: Dict[str, Any], config: Dict[str, Any]) -> Dict[str, Any]:
        trigger_data = context.get("trigger_data", {})
        if config.get("process_definition_id_filter") is not None:
            if trigger_data.get("process_definition_id") != config.get("process_definition_id_filter"):
                return {}
        return super().execute(context, config)

    def get_metadata(self) -> Dict[str, Any]:
        return {
            "name": "ایجاد سرنخ",
            "description": "زمانی که یک سرنخ جدید ایجاد می‌شود",
            "config_schema": {
                "enabled": {"type": "boolean", "description": "فعال/غیرفعال", "default": True, "required": False},
                "process_definition_id_filter": {
                    "type": "integer",
                    "description": "فیلتر بر اساس فانل سرنخ (خالی = همه)",
                    "required": False,
                },
                "cooldown_seconds": {"type": "integer", "description": "مدت انتظار بین trigger (ثانیه)", "default": 0, "required": False},
            },
        }


class LeadStageChangedTrigger(BaseTrigger):
    """Trigger برای تغییر مرحله سرنخ"""

    def execute(self, context: Dict[str, Any], config: Dict[str, Any]) -> Dict[str, Any]:
        trigger_data = context.get("trigger_data", {})
        if config.get("stage_id_filter") is not None:
            if trigger_data.get("new_stage_id") != config.get("stage_id_filter"):
                return {}
        return super().execute(context, config)

    def get_metadata(self) -> Dict[str, Any]:
        return {
            "name": "تغییر مرحله سرنخ",
            "description": "زمانی که مرحله یک سرنخ تغییر می‌کند",
            "config_schema": {
                "enabled": {"type": "boolean", "description": "فعال/غیرفعال", "default": True, "required": False},
                "stage_id_filter": {"type": "integer", "description": "فقط وقتی به این مرحله رفت (خالی = همه)", "required": False},
                "cooldown_seconds": {"type": "integer", "default": 0, "required": False},
            },
        }


class LeadConvertedTrigger(BaseTrigger):
    """Trigger برای تبدیل سرنخ به مشتری"""

    def get_metadata(self) -> Dict[str, Any]:
        return {
            "name": "تبدیل سرنخ به مشتری",
            "description": "زمانی که یک سرنخ به مشتری تبدیل می‌شود",
            "config_schema": {
                "enabled": {"type": "boolean", "description": "فعال/غیرفعال", "default": True, "required": False},
                "cooldown_seconds": {"type": "integer", "default": 0, "required": False},
            },
        }


class DealCreatedTrigger(BaseTrigger):
    """Trigger برای ایجاد فرصت فروش"""

    def execute(self, context: Dict[str, Any], config: Dict[str, Any]) -> Dict[str, Any]:
        trigger_data = context.get("trigger_data", {})
        if config.get("process_definition_id_filter") is not None:
            if trigger_data.get("process_definition_id") != config.get("process_definition_id_filter"):
                return {}
        return super().execute(context, config)

    def get_metadata(self) -> Dict[str, Any]:
        return {
            "name": "ایجاد فرصت فروش",
            "description": "زمانی که یک فرصت فروش جدید ایجاد می‌شود",
            "config_schema": {
                "enabled": {"type": "boolean", "description": "فعال/غیرفعال", "default": True, "required": False},
                "process_definition_id_filter": {"type": "integer", "description": "فیلتر پایپلاین (خالی = همه)", "required": False},
                "cooldown_seconds": {"type": "integer", "default": 0, "required": False},
            },
        }


class DealStageChangedTrigger(BaseTrigger):
    """Trigger برای تغییر مرحله فرصت فروش"""

    def execute(self, context: Dict[str, Any], config: Dict[str, Any]) -> Dict[str, Any]:
        trigger_data = context.get("trigger_data", {})
        if config.get("stage_id_filter") is not None:
            if trigger_data.get("new_stage_id") != config.get("stage_id_filter"):
                return {}
        return super().execute(context, config)

    def get_metadata(self) -> Dict[str, Any]:
        return {
            "name": "تغییر مرحله فرصت فروش",
            "description": "زمانی که مرحله یک فرصت فروش تغییر می‌کند",
            "config_schema": {
                "enabled": {"type": "boolean", "description": "فعال/غیرفعال", "default": True, "required": False},
                "stage_id_filter": {"type": "integer", "description": "فقط وقتی به این مرحله رفت (خالی = همه)", "required": False},
                "cooldown_seconds": {"type": "integer", "default": 0, "required": False},
            },
        }


class DealClosedTrigger(BaseTrigger):
    """Trigger برای بستن معامله"""

    def execute(self, context: Dict[str, Any], config: Dict[str, Any]) -> Dict[str, Any]:
        if config.get("won_only") and not context.get("trigger_data", {}).get("is_win"):
            return {}
        return super().execute(context, config)

    def get_metadata(self) -> Dict[str, Any]:
        return {
            "name": "بستن معامله",
            "description": "زمانی که یک فرصت فروش بسته می‌شود (برنده یا بازنده)",
            "config_schema": {
                "enabled": {"type": "boolean", "description": "فعال/غیرفعال", "default": True, "required": False},
                "won_only": {"type": "boolean", "description": "فقط معاملات برنده (مرحله is_win)", "default": False, "required": False},
                "cooldown_seconds": {"type": "integer", "default": 0, "required": False},
            },
        }
