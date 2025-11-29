"""
Triggerهای مربوط به اشخاص
"""

from typing import Any, Dict
from app.services.workflow.triggers.base_trigger import BaseTrigger


class PersonCreatedTrigger(BaseTrigger):
    """Trigger برای ایجاد شخص"""
    
    def get_metadata(self) -> Dict[str, Any]:
        return {
            "name": "ایجاد شخص",
            "description": "زمانی که یک شخص (مشتری/تامین‌کننده) ایجاد می‌شود",
            "config_schema": {
                "person_type": {
                    "type": "string",
                    "description": "نوع شخص (customer/supplier/etc)",
                    "required": False
                }
            }
        }
    
    def execute(self, context: Dict[str, Any], config: Dict[str, Any]) -> Dict[str, Any]:
        data = super().execute(context, config)
        
        # فیلتر بر اساس نوع شخص
        person_type = config.get("person_type")
        if person_type:
            person_types = data.get("person_types", [])
            if person_type not in person_types:
                return {}
        
        return data

