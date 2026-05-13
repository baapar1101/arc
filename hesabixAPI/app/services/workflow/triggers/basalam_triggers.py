"""Workflow triggers for Basalam integration."""

from __future__ import annotations

from typing import Any, Dict

from app.services.workflow.triggers.base_trigger import BaseTrigger


class _BasalamBaseTrigger(BaseTrigger):
    def execute(self, context: Dict[str, Any], config: Dict[str, Any]) -> Dict[str, Any]:
        db = context.get("db")
        bid = context.get("business_id")
        if db is not None and bid is not None:
            from app.core.basalam_plugin_dependency import check_basalam_plugin_active

            try:
                bid_int = int(bid)
            except (TypeError, ValueError):
                bid_int = 0
            if bid_int and not check_basalam_plugin_active(db, bid_int):
                return {}
        td = context.get("trigger_data", {})
        wanted_event = str(config.get("event_type") or "").strip().lower()
        if wanted_event:
            got_event = str(td.get("event_type") or "").strip().lower()
            if got_event != wanted_event:
                return {}
        return super().execute(context, config)

    def _metadata(self, name: str, description: str) -> Dict[str, Any]:
        return {
            "name": name,
            "description": description,
            "config_schema": {
                "enabled": {"type": "boolean", "default": True, "required": False},
                "event_type": {
                    "type": "string",
                    "required": False,
                    "description": "Optional exact Basalam event type filter",
                },
                "cooldown_seconds": {"type": "integer", "default": 0, "required": False},
            },
        }


class BasalamWebhookReceivedTrigger(_BasalamBaseTrigger):
    def get_metadata(self) -> Dict[str, Any]:
        return self._metadata(
            name="رویداد وب‌هوک باسلام",
            description="هر رویداد دریافتی از وب‌هوک باسلام",
        )


class BasalamOrderCreatedTrigger(_BasalamBaseTrigger):
    def get_metadata(self) -> Dict[str, Any]:
        return self._metadata(
            name="سفارش جدید باسلام",
            description="وقتی سفارش جدید از باسلام دریافت می‌شود",
        )


class BasalamOrderUpdatedTrigger(_BasalamBaseTrigger):
    def get_metadata(self) -> Dict[str, Any]:
        return self._metadata(
            name="به‌روزرسانی سفارش باسلام",
            description="وقتی وضعیت یا جزئیات سفارش باسلام تغییر می‌کند",
        )


class BasalamOrderPaidTrigger(_BasalamBaseTrigger):
    def get_metadata(self) -> Dict[str, Any]:
        return self._metadata(
            name="پرداخت سفارش باسلام",
            description="وقتی سفارش باسلام به وضعیت پرداخت‌شده می‌رسد",
        )


class BasalamChatMessageReceivedTrigger(_BasalamBaseTrigger):
    def get_metadata(self) -> Dict[str, Any]:
        return self._metadata(
            name="پیام جدید چت باسلام",
            description="وقتی پیام جدید از چت باسلام دریافت می‌شود",
        )
