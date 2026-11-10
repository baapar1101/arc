"""تریگرهای جانبی تدارکات. تأیید انسانی در این موتور انجام نمی‌شود."""
from __future__ import annotations

from typing import Any, Dict

from app.services.workflow.triggers.base_trigger import BaseTrigger


class ProcurementEventTrigger(BaseTrigger):
	def __init__(self, name: str, description: str) -> None:
		self._name = name
		self._description = description

	def get_metadata(self) -> Dict[str, Any]:
		return {
			"name": self._name,
			"description": self._description,
			"config_schema": {},
		}

	def execute(self, context: Dict[str, Any], config: Dict[str, Any]) -> Dict[str, Any]:
		return super().execute(context, config)
