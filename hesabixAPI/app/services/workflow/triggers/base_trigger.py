"""
Base Trigger Handler
"""

import time
from typing import Any, Dict, Optional
from datetime import datetime, timedelta
from app.services.workflow.trigger_registry import TriggerHandler


class BaseTrigger(TriggerHandler):
    """Base class برای triggerهای ساده"""
    
    # کش برای cooldown (trigger_id -> last_trigger_time)
    _cooldown_cache: Dict[str, float] = {}
    
    def execute(self, context: Dict[str, Any], config: Dict[str, Any]) -> Dict[str, Any]:
        """
        اجرای trigger - در triggerهای ساده، داده‌ها از context می‌آیند
        """
        # بررسی enabled
        if config.get("enabled", True) is False:
            return {}
        
        # بررسی cooldown
        workflow_id = context.get("workflow_id")
        if workflow_id and not self._check_cooldown(str(workflow_id), config):
            return {}
        
        trigger_data = context.get("trigger_data", {})
        
        # اعمال فیلترها اگر وجود داشته باشند
        filters = config.get("filters", {})
        if filters:
            trigger_data = self._apply_filters(trigger_data, filters)
        
        # اگر فیلتر رد شد، داده خالی برگردان
        if not trigger_data:
            return {}
        
        # ثبت زمان آخرین trigger برای cooldown
        if workflow_id:
            self._update_cooldown(str(workflow_id))
        
        return trigger_data
    
    def _apply_filters(self, data: Dict[str, Any], filters: Dict[str, Any]) -> Dict[str, Any]:
        """
        اعمال فیلترها روی داده‌های trigger
        """
        if not filters:
            return data
        
        filtered_data = data.copy()
        
        for key, value in filters.items():
            if key not in filtered_data:
                # اگر فیلد در data نیست، بررسی می‌کنیم که آیا باید رد شود
                if isinstance(value, dict) and value.get("required", False):
                    return {}  # فیلد مورد نیاز نیست
                continue
            
            data_value = filtered_data[key]
            
            if isinstance(value, dict):
                # فیلتر پیچیده‌تر (مثل >, <, ==)
                operator = value.get("operator", "==")
                filter_value = value.get("value")
                
                if operator == "==":
                    if data_value != filter_value:
                        return {}
                elif operator == "!=":
                    if data_value == filter_value:
                        return {}
                elif operator == ">":
                    try:
                        if float(data_value) <= float(filter_value):
                            return {}
                    except (ValueError, TypeError):
                        return {}
                elif operator == "<":
                    try:
                        if float(data_value) >= float(filter_value):
                            return {}
                    except (ValueError, TypeError):
                        return {}
                elif operator == ">=":
                    try:
                        if float(data_value) < float(filter_value):
                            return {}
                    except (ValueError, TypeError):
                        return {}
                elif operator == "<=":
                    try:
                        if float(data_value) > float(filter_value):
                            return {}
                    except (ValueError, TypeError):
                        return {}
                elif operator == "contains":
                    if isinstance(data_value, str) and isinstance(filter_value, str):
                        if filter_value.lower() not in data_value.lower():
                            return {}
                    elif isinstance(data_value, list):
                        if filter_value not in data_value:
                            return {}
                    else:
                        return {}
                elif operator == "in":
                    if isinstance(filter_value, list):
                        if data_value not in filter_value:
                            return {}
                    else:
                        return {}
                elif operator == "not_in":
                    if isinstance(filter_value, list):
                        if data_value in filter_value:
                            return {}
                    else:
                        return {}
            else:
                # فیلتر ساده: مقایسه مستقیم
                if data_value != value:
                    return {}
        
        return filtered_data
    
    def _check_cooldown(self, trigger_key: str, config: Dict[str, Any]) -> bool:
        """
        بررسی cooldown - اگر هنوز در cooldown باشد، False برمی‌گرداند
        """
        cooldown_seconds = config.get("cooldown_seconds", 0)
        if cooldown_seconds <= 0:
            return True
        
        last_trigger_time = self._cooldown_cache.get(trigger_key, 0)
        current_time = time.time()
        
        if current_time - last_trigger_time < cooldown_seconds:
            return False
        
        return True
    
    def _update_cooldown(self, trigger_key: str):
        """
        به‌روزرسانی زمان آخرین trigger
        """
        self._cooldown_cache[trigger_key] = time.time()
    
    def get_metadata(self) -> Dict[str, Any]:
        """اطلاعات metadata برای trigger"""
        return {
            "name": self.__class__.__name__,
            "description": "Base trigger",
            "config_schema": {}
        }

