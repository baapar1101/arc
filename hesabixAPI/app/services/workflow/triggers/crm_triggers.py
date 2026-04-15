"""
Triggerهای مربوط به CRM (سرنخ، فرصت فروش، فعالیت)
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
        if config.get("source_code_filter") not in (None, ""):
            if (trigger_data.get("source_code") or "") != str(config.get("source_code_filter")):
                return {}
        if config.get("assigned_to_user_id_filter") is not None:
            if trigger_data.get("assigned_to_user_id") != config.get("assigned_to_user_id_filter"):
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
                "source_code_filter": {
                    "type": "string",
                    "description": "فقط اگر منبع سرنخ برابر این مقدار باشد (خالی = همه)",
                    "required": False,
                },
                "assigned_to_user_id_filter": {
                    "type": "integer",
                    "description": "فقط اگر سرنخ به این کاربر تخصیص داده شده باشد (خالی = همه)",
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
        if config.get("old_stage_id_filter") is not None:
            if trigger_data.get("old_stage_id") != config.get("old_stage_id_filter"):
                return {}
        return super().execute(context, config)

    def get_metadata(self) -> Dict[str, Any]:
        return {
            "name": "تغییر مرحله سرنخ",
            "description": "زمانی که مرحله یک سرنخ تغییر می‌کند",
            "config_schema": {
                "enabled": {"type": "boolean", "description": "فعال/غیرفعال", "default": True, "required": False},
                "stage_id_filter": {"type": "integer", "description": "فقط وقتی به این مرحله رفت (خالی = همه)", "required": False},
                "old_stage_id_filter": {"type": "integer", "description": "فقط وقتی از این مرحله خارج شد (خالی = همه)", "required": False},
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


class LeadAssignedTrigger(BaseTrigger):
    """تغییر کاربر مسئول سرنخ"""

    def execute(self, context: Dict[str, Any], config: Dict[str, Any]) -> Dict[str, Any]:
        trigger_data = context.get("trigger_data", {})
        if config.get("new_assigned_to_user_id_filter") is not None:
            if trigger_data.get("new_assigned_to_user_id") != config.get("new_assigned_to_user_id_filter"):
                return {}
        return super().execute(context, config)

    def get_metadata(self) -> Dict[str, Any]:
        return {
            "name": "تخصیص سرنخ",
            "description": "زمانی که مسئول سرنخ تغییر کند",
            "config_schema": {
                "enabled": {"type": "boolean", "description": "فعال/غیرفعال", "default": True, "required": False},
                "new_assigned_to_user_id_filter": {
                    "type": "integer",
                    "description": "فقط وقتی مسئول جدید این کاربر باشد (خالی = همه)",
                    "required": False,
                },
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
        if config.get("assigned_to_user_id_filter") is not None:
            if trigger_data.get("assigned_to_user_id") != config.get("assigned_to_user_id_filter"):
                return {}
        if config.get("min_amount") is not None:
            try:
                if float(trigger_data.get("amount") or 0) < float(config.get("min_amount")):
                    return {}
            except (TypeError, ValueError):
                return {}
        return super().execute(context, config)

    def get_metadata(self) -> Dict[str, Any]:
        return {
            "name": "ایجاد فرصت فروش",
            "description": "زمانی که یک فرصت فروش جدید ایجاد می‌شود",
            "config_schema": {
                "enabled": {"type": "boolean", "description": "فعال/غیرفعال", "default": True, "required": False},
                "process_definition_id_filter": {"type": "integer", "description": "فیلتر پایپلاین (خالی = همه)", "required": False},
                "assigned_to_user_id_filter": {
                    "type": "integer",
                    "description": "فقط اگر به این کاربر تخصیص داده شده باشد (خالی = همه)",
                    "required": False,
                },
                "min_amount": {"type": "number", "description": "حداقل مبلغ فرصت (خالی = بدون حد)", "required": False},
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
        if config.get("old_stage_id_filter") is not None:
            if trigger_data.get("old_stage_id") != config.get("old_stage_id_filter"):
                return {}
        return super().execute(context, config)

    def get_metadata(self) -> Dict[str, Any]:
        return {
            "name": "تغییر مرحله فرصت فروش",
            "description": "زمانی که مرحله یک فرصت فروش تغییر می‌کند",
            "config_schema": {
                "enabled": {"type": "boolean", "description": "فعال/غیرفعال", "default": True, "required": False},
                "stage_id_filter": {"type": "integer", "description": "فقط وقتی به این مرحله رفت (خالی = همه)", "required": False},
                "old_stage_id_filter": {"type": "integer", "description": "فقط وقتی از این مرحله خارج شد (خالی = همه)", "required": False},
                "cooldown_seconds": {"type": "integer", "default": 0, "required": False},
            },
        }


class DealClosedTrigger(BaseTrigger):
    """Trigger برای بستن معامله"""

    def execute(self, context: Dict[str, Any], config: Dict[str, Any]) -> Dict[str, Any]:
        td = context.get("trigger_data", {})
        if config.get("won_only") and not td.get("is_win"):
            return {}
        if config.get("lost_only") and not td.get("is_lost"):
            return {}
        return super().execute(context, config)

    def get_metadata(self) -> Dict[str, Any]:
        return {
            "name": "بستن معامله",
            "description": "زمانی که یک فرصت فروش بسته می‌شود (برنده یا بازنده)",
            "config_schema": {
                "enabled": {"type": "boolean", "description": "فعال/غیرفعال", "default": True, "required": False},
                "won_only": {"type": "boolean", "description": "فقط معاملات برنده (مرحله is_win)", "default": False, "required": False},
                "lost_only": {"type": "boolean", "description": "فقط معاملات بازنده (مرحله is_lost)", "default": False, "required": False},
                "cooldown_seconds": {"type": "integer", "default": 0, "required": False},
            },
        }


class DealAssignedTrigger(BaseTrigger):
    """تغییر کاربر مسئول فرصت فروش"""

    def execute(self, context: Dict[str, Any], config: Dict[str, Any]) -> Dict[str, Any]:
        trigger_data = context.get("trigger_data", {})
        if config.get("new_assigned_to_user_id_filter") is not None:
            if trigger_data.get("new_assigned_to_user_id") != config.get("new_assigned_to_user_id_filter"):
                return {}
        return super().execute(context, config)

    def get_metadata(self) -> Dict[str, Any]:
        return {
            "name": "تخصیص فرصت فروش",
            "description": "زمانی که مسئول فرصت فروش تغییر کند",
            "config_schema": {
                "enabled": {"type": "boolean", "description": "فعال/غیرفعال", "default": True, "required": False},
                "new_assigned_to_user_id_filter": {
                    "type": "integer",
                    "description": "فقط وقتی مسئول جدید این کاربر باشد (خالی = همه)",
                    "required": False,
                },
                "cooldown_seconds": {"type": "integer", "default": 0, "required": False},
            },
        }


class ActivityCreatedTrigger(BaseTrigger):
    """ثبت فعالیت CRM"""

    def execute(self, context: Dict[str, Any], config: Dict[str, Any]) -> Dict[str, Any]:
        trigger_data = context.get("trigger_data", {})
        if config.get("activity_type_filter") not in (None, ""):
            if (trigger_data.get("activity_type") or "") != str(config.get("activity_type_filter")):
                return {}
        return super().execute(context, config)

    def get_metadata(self) -> Dict[str, Any]:
        return {
            "name": "ثبت فعالیت CRM",
            "description": "زمانی که یک فعالیت CRM ثبت می‌شود",
            "config_schema": {
                "enabled": {"type": "boolean", "description": "فعال/غیرفعال", "default": True, "required": False},
                "activity_type_filter": {
                    "type": "string",
                    "description": "call | email | meeting | note — خالی = همه",
                    "required": False,
                },
                "cooldown_seconds": {"type": "integer", "default": 0, "required": False},
            },
        }
