"""Triggerهای افزونه پخش مویرگی."""

from typing import Any, Dict

from app.services.workflow.triggers.base_trigger import BaseTrigger


class DistributionVisitCompletedTrigger(BaseTrigger):
	"""پایان ویزیت میدانی با نتیجه ثبت‌شده."""

	def execute(self, context: Dict[str, Any], config: Dict[str, Any]) -> Dict[str, Any]:
		trigger_data = context.get("trigger_data") or {}
		if config.get("outcome_filter"):
			want = str(config["outcome_filter"]).strip().lower()
			got = (trigger_data.get("outcome") or "").strip().lower()
			if got != want:
				return {}
		return super().execute(context, config)

	def get_metadata(self) -> Dict[str, Any]:
		return {
			"name": "تکمیل ویزیت میدانی (پخش مویرگی)",
			"description": "پس از ثبت نتیجه ویزیت توسط ویزیتور",
			"config_schema": {
				"enabled": {"type": "boolean", "description": "فعال/غیرفعال", "default": True, "required": False},
				"outcome_filter": {
					"type": "string",
					"description": "فقط اگر نتیجه برابر باشد: order | no_order | cancelled (خالی = همه)",
					"required": False,
				},
				"cooldown_seconds": {"type": "integer", "default": 0, "required": False},
			},
		}
