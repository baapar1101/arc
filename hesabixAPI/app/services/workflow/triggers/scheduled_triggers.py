"""
Triggerهای زمان‌بندی شده
"""

import logging
from typing import Any, Dict
from datetime import datetime
from app.services.workflow.trigger_registry import TriggerHandler

logger = logging.getLogger(__name__)


class ScheduledTrigger(TriggerHandler):
    """Trigger زمان‌بندی شده (cron-like)"""
    
    def get_metadata(self) -> Dict[str, Any]:
        return {
            "name": "زمان‌بندی شده",
            "description": "اجرای workflow در زمان مشخص (cron)",
            "config_schema": {
                "schedule": {
                    "type": "string",
                    "description": "زمان‌بندی cron (مثل: 0 8 * * * برای هر روز ساعت 8)",
                    "required": True
                },
                "timezone": {
                    "type": "string",
                    "description": "Timezone",
                    "default": "Asia/Tehran",
                    "required": False
                },
                "business_hours_only": {
                    "type": "boolean",
                    "description": "اجرا فقط در ساعات کاری",
                    "default": False,
                    "required": False
                },
                "business_hours_start": {
                    "type": "string",
                    "description": "شروع ساعت کاری (HH:mm)",
                    "default": "09:00",
                    "required": False
                },
                "business_hours_end": {
                    "type": "string",
                    "description": "پایان ساعت کاری (HH:mm)",
                    "default": "17:00",
                    "required": False
                },
                "exclude_holidays": {
                    "type": "boolean",
                    "description": "حذف تعطیلات",
                    "default": False,
                    "required": False
                },
                "max_execution_time": {
                    "type": "integer",
                    "description": "حداکثر زمان اجرا (ثانیه)",
                    "default": 300,
                    "required": False
                },
                "retry_on_failure": {
                    "type": "boolean",
                    "description": "تلاش مجدد در صورت خطا",
                    "default": False,
                    "required": False
                },
                "retry_attempts": {
                    "type": "integer",
                    "description": "تعداد تلاش‌های مجدد",
                    "default": 3,
                    "required": False
                }
            }
        }
    
    def execute(self, context: Dict[str, Any], config: Dict[str, Any]) -> Dict[str, Any]:
        """
        برای triggerهای زمان‌بندی شده، داده‌ها از زمان اجرا می‌آیند
        """
        from datetime import datetime
        import pytz
        
        # بررسی business hours
        business_hours_only = config.get("business_hours_only", False)
        if business_hours_only:
            timezone_str = config.get("timezone", "Asia/Tehran")
            try:
                tz = pytz.timezone(timezone_str)
                current_time = datetime.now(tz)
                current_hour = current_time.hour
                current_minute = current_time.minute
                
                start_time = config.get("business_hours_start", "09:00")
                end_time = config.get("business_hours_end", "17:00")
                
                start_hour, start_min = map(int, start_time.split(":"))
                end_hour, end_min = map(int, end_time.split(":"))
                
                current_total_minutes = current_hour * 60 + current_minute
                start_total_minutes = start_hour * 60 + start_min
                end_total_minutes = end_hour * 60 + end_min
                
                if not (start_total_minutes <= current_total_minutes <= end_total_minutes):
                    return {}  # خارج از ساعات کاری
            except Exception as e:
                logger.warning(f"Error checking business hours: {e}")
        
        return {
            "triggered_at": datetime.utcnow().isoformat(),
            "schedule": config.get("schedule"),
            "business_id": context.get("business_id"),
            "timezone": config.get("timezone", "Asia/Tehran")
        }

