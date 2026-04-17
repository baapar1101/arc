"""
Triggerهای زمان‌بندی شده
"""

import logging
from typing import Any, Dict

from app.services.workflow.schedule_cron_resolution import resolve_schedule_config_to_cron
from app.services.workflow.trigger_registry import TriggerHandler

logger = logging.getLogger(__name__)


class ScheduledTrigger(TriggerHandler):
    """Trigger زمان‌بندی شده (کرون دستی یا زمان‌بندی ساده)"""

    def get_metadata(self) -> Dict[str, Any]:
        return {
            "name": "زمان‌بندی شده",
            "description": "اجرای ورک‌فلو در زمان مشخص (کرون پیشرفته یا حالت ساده)",
            "config_schema": {
                "schedule_mode": {
                    "type": "string",
                    "description": "نوع تنظیم زمان",
                    "required": False,
                    "default": "cron",
                    "enum": ["cron", "simple"],
                    "ui_config": {
                        "labels": {
                            "cron": "کرون پیشرفته (دستی)",
                            "simple": "زمان‌بندی ساده",
                        }
                    },
                },
                "schedule": {
                    "type": "string",
                    "description": "عبارت کرون ۵ بخشی (فقط در حالت کرون پیشرفته؛ مثال: 0 8 * * * = هر روز ۸:۰۰)",
                    "required": False,
                },
                "simple_repeat": {
                    "type": "string",
                    "description": "تکرار در حالت ساده",
                    "required": False,
                    "default": "daily",
                    "enum": ["daily", "weekly", "every_minutes", "every_hours"],
                    "ui_config": {
                        "labels": {
                            "daily": "هر روز",
                            "weekly": "هفتگی",
                            "every_minutes": "هر چند دقیقه",
                            "every_hours": "هر چند ساعت",
                        }
                    },
                },
                "simple_time": {
                    "type": "string",
                    "description": "ساعت اجرا (HH:mm) برای روزانه/هفتگی",
                    "required": False,
                    "default": "08:00",
                },
                "simple_weekday": {
                    "type": "integer",
                    "description": "روز هفته برای هفتگی (۰=یکشنبه … ۶=شنبه، مطابق کرون)",
                    "required": False,
                    "default": 6,
                },
                "simple_interval": {
                    "type": "integer",
                    "description": "عدد N برای «هر N دقیقه» یا «هر N ساعت»",
                    "required": False,
                    "default": 15,
                },
                "timezone": {
                    "type": "string",
                    "description": "منطقهٔ زمانی ارزیابی کرون",
                    "default": "Asia/Tehran",
                    "enum": ["Asia/Tehran", "UTC", "Asia/Dubai", "Europe/London", "America/New_York"],
                    "ui_config": {
                        "labels": {
                            "Asia/Tehran": "🇮🇷 تهران (ایران)",
                            "UTC": "🌍 UTC (جهانی)",
                            "Asia/Dubai": "🇦🇪 دبی",
                            "Europe/London": "🇬🇧 لندن",
                            "America/New_York": "🇺🇸 نیویورک",
                        }
                    },
                    "required": False,
                },
                "business_hours_only": {
                    "type": "boolean",
                    "description": "اجرا فقط در بازهٔ ساعات کاری (بعد از تطبیق زمان کرون)",
                    "default": False,
                    "required": False,
                },
                "business_hours_start": {
                    "type": "string",
                    "description": "شروع ساعت کاری (HH:mm)",
                    "default": "09:00",
                    "required": False,
                },
                "business_hours_end": {
                    "type": "string",
                    "description": "پایان ساعت کاری (HH:mm)",
                    "default": "17:00",
                    "required": False,
                },
                "exclude_holidays": {
                    "type": "boolean",
                    "description": "حذف تعطیلات (رزرو برای توسعهٔ آینده)",
                    "default": False,
                    "required": False,
                },
                "max_execution_time": {
                    "type": "integer",
                    "description": "حداکثر زمان اجرای پیشنهادی (ثانیه) — اطلاعاتی برای UI",
                    "default": 300,
                    "required": False,
                },
                "retry_on_failure": {
                    "type": "boolean",
                    "description": "تلاش مجدد در صورت خطا (رزرو)",
                    "default": False,
                    "required": False,
                },
                "retry_attempts": {
                    "type": "integer",
                    "description": "تعداد تلاش مجدد (رزرو)",
                    "default": 3,
                    "required": False,
                },
            },
        }

    def execute(self, context: Dict[str, Any], config: Dict[str, Any]) -> Dict[str, Any]:
        """
        برای triggerهای زمان‌بندی شده، داده‌ها از زمان اجرا می‌آیند
        """
        from datetime import datetime

        import pytz

        trigger_data = context.get("trigger_data") or {}

        resolved_cron = resolve_schedule_config_to_cron(config)

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
                    return {}
            except Exception as e:
                logger.warning("Error checking business hours: %s", e)

        triggered_at = trigger_data.get("scheduled_at") or datetime.utcnow().isoformat()
        raw_schedule = config.get("schedule")
        return {
            "triggered_at": triggered_at,
            "schedule": raw_schedule,
            "schedule_cron_resolved": resolved_cron,
            "schedule_mode": config.get("schedule_mode") or "cron",
            "business_id": context.get("business_id"),
            "timezone": config.get("timezone", "Asia/Tehran"),
        }
