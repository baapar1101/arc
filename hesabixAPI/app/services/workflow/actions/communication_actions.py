"""
Actionهای مربوط به ارتباطات (ایمیل، تلگرام، notification)
"""

import logging
from typing import Any, Dict, Optional
from app.services.workflow.action_registry import ActionHandler
from app.services.workflow.workflow_engine import WorkflowEngine
from app.services.workflow.utils import execute_with_retry, get_retry_config_from_action_config
from app.services.workflow.logging_decorators import log_action_execution

logger = logging.getLogger(__name__)


class SendEmailAction(ActionHandler):
    """ارسال ایمیل"""
    
    def get_metadata(self) -> Dict[str, Any]:
        return {
            "name": "ارسال ایمیل",
            "description": "ارسال ایمیل به آدرس مشخص",
            "config_schema": {
                "to": {
                    "type": "string",
                    "description": "آدرس ایمیل گیرنده (می‌تواند از nodeهای قبلی باشد: $node_id.email)",
                    "required": True
                },
                "cc": {
                    "type": "array",
                    "description": "CC (آرایه‌ای از آدرس‌های ایمیل)",
                    "items": {"type": "string"},
                    "required": False
                },
                "bcc": {
                    "type": "array",
                    "description": "BCC (آرایه‌ای از آدرس‌های ایمیل)",
                    "items": {"type": "string"},
                    "required": False
                },
                "subject": {
                    "type": "string",
                    "description": "موضوع ایمیل",
                    "required": True
                },
                "body": {
                    "type": "string",
                    "description": "متن ایمیل",
                    "required": True
                },
                "html_body": {
                    "type": "string",
                    "description": "متن HTML ایمیل (اختیاری)",
                    "required": False
                },
                "template_id": {
                    "type": "integer",
                    "description": "شناسه قالب ایمیل (در صورت استفاده از template)",
                    "required": False
                },
                "priority": {
                    "type": "string",
                    "description": "اولویت ارسال",
                    "enum": ["low", "normal", "high"],
                    "default": "normal",
                    "ui_config": {
                        "labels": {
                            "low": "🔽 کم - Low",
                            "normal": "➖ عادی - Normal",
                            "high": "🔼 بالا - High"
                        }
                    },
                    "required": False
                },
                "retry_on_failure": {
                    "type": "boolean",
                    "description": "تلاش مجدد در صورت خطا",
                    "default": True,
                    "required": False
                },
                "retry_attempts": {
                    "type": "integer",
                    "description": "تعداد تلاش‌های مجدد",
                    "default": 3,
                    "required": False
                },
                "retry_delay_seconds": {
                    "type": "integer",
                    "description": "تاخیر بین تلاش‌ها (ثانیه)",
                    "default": 60,
                    "required": False
                },
                "timeout_seconds": {
                    "type": "integer",
                    "description": "Timeout برای ارسال (ثانیه)",
                    "default": 30,
                    "required": False
                },
                "exponential_backoff": {
                    "type": "boolean",
                    "description": "استفاده از exponential backoff برای retry",
                    "default": True,
                    "required": False
                }
            }
        }
    
    @log_action_execution
    def execute(
        self,
        context: Dict[str, Any],
        config: Dict[str, Any],
        node_results: Dict[str, Any]
    ) -> Dict[str, Any]:
        from adapters.db.session import get_db_session
        from app.services.email_service import EmailService
        from app.services.workflow.workflow_engine import WorkflowEngine
        
        # حل کردن مقادیر
        to_email = WorkflowEngine._resolve_value_static(config.get("to"), context, node_results)
        cc = config.get("cc", [])
        bcc = config.get("bcc", [])
        subject = WorkflowEngine._resolve_value_static(config.get("subject"), context, node_results)
        body = WorkflowEngine._resolve_value_static(config.get("body"), context, node_results)
        html_body = WorkflowEngine._resolve_value_static(config.get("html_body", ""), context, node_results) or None
        
        # حل کردن CC و BCC اگر از nodeهای قبلی باشند
        if isinstance(cc, list):
            cc = [WorkflowEngine._resolve_value_static(item, context, node_results) for item in cc]
        if isinstance(bcc, list):
            bcc = [WorkflowEngine._resolve_value_static(item, context, node_results) for item in bcc]
        
        def _send_email():
            db = context.get("db")
            if not db:
                with get_db_session() as db_session:
                    email_service = EmailService(db_session)
                    return email_service.send_email(
                        to=str(to_email),
                        subject=str(subject),
                        body=str(body),
                        html_body=str(html_body) if html_body else None,
                        cc=[str(e) for e in cc] if cc else None,
                        bcc=[str(e) for e in bcc] if bcc else None,
                    )
            else:
                email_service = EmailService(db)
                return email_service.send_email(
                    to=str(to_email),
                    subject=str(subject),
                    body=str(body),
                    html_body=str(html_body) if html_body else None,
                    cc=[str(e) for e in cc] if cc else None,
                    bcc=[str(e) for e in bcc] if bcc else None,
                )
        
        # ارسال با retry mechanism
        retry_on_failure = config.get("retry_on_failure", True)
        
        if retry_on_failure:
            retry_config = get_retry_config_from_action_config(config)
            try:
                success = execute_with_retry(
                    _send_email,
                    **retry_config
                )
            except Exception as e:
                return {
                    "success": False,
                    "error": str(e),
                    "to": to_email,
                    "subject": subject
                }
        else:
            try:
                success = _send_email()
            except Exception as e:
                return {
                    "success": False,
                    "error": str(e),
                    "to": to_email,
                    "subject": subject
                }
        
        return {
            "success": success,
            "to": to_email,
            "subject": subject
        }


class SendTelegramAction(ActionHandler):
    """ارسال پیام تلگرام"""
    
    def get_metadata(self) -> Dict[str, Any]:
        return {
            "name": "ارسال پیام تلگرام",
            "description": "ارسال پیام به کاربر عضو کسب و کار از طریق تلگرام (فقط کاربران متصل به ربات)",
            "config_schema": {
                "user_id": {
                    "type": "string",
                    "description": "شناسه کاربر عضو کسب و کار که به ربات تلگرام متصل است (می‌تواند از نودهای قبلی باشد: $node_id.user_id)",
                    "required": True,
                    "ui_type": "telegram_user_selector",
                    "ui_config": {
                        "filter": "telegram_connected",
                        "business_scoped": True
                    }
                },
                "message": {
                    "type": "string",
                    "description": "متن پیام",
                    "required": True
                },
                "parse_mode": {
                    "type": "string",
                    "description": "حالت پارس متن",
                    "enum": ["None", "HTML", "Markdown"],
                    "default": "None",
                    "ui_config": {
                        "labels": {
                            "None": "متن ساده",
                            "HTML": "HTML - با فرمت HTML",
                            "Markdown": "Markdown - با فرمت مارک‌داون"
                        }
                    },
                    "required": False
                },
                "disable_web_page_preview": {
                    "type": "boolean",
                    "description": "غیرفعال کردن پیش‌نمایش لینک",
                    "default": False,
                    "required": False
                },
                "retry_on_failure": {
                    "type": "boolean",
                    "description": "تلاش مجدد در صورت خطا",
                    "default": True,
                    "required": False
                },
                "retry_attempts": {
                    "type": "integer",
                    "description": "تعداد تلاش‌های مجدد",
                    "default": 3,
                    "required": False
                },
                "retry_delay_seconds": {
                    "type": "integer",
                    "description": "تاخیر بین تلاش‌ها (ثانیه)",
                    "default": 60,
                    "required": False
                }
            }
        }
    
    @log_action_execution
    def execute(
        self,
        context: Dict[str, Any],
        config: Dict[str, Any],
        node_results: Dict[str, Any]
    ) -> Dict[str, Any]:
        from adapters.db.session import get_db_session
        from app.services.providers.telegram_provider import TelegramProvider
        from app.services.system_settings_service import get_effective_notifications_settings
        from app.services.workflow.utils import execute_with_retry, get_retry_config_from_action_config
        from adapters.db.models.user import User
        from adapters.db.repositories.business_permission_repo import BusinessPermissionRepository
        
        db = context.get("db")
        if not db:
            db = get_db_session().__enter__()
        
        business_id = context.get("business_id")
        if not business_id:
            return {
                "success": False,
                "error": "business_id در context موجود نیست"
            }
        
        # حل کردن user_id (ممکن است از نودهای قبلی باشد)
        user_id_raw = config.get("user_id")
        if not user_id_raw:
            return {
                "success": False,
                "error": "user_id مشخص نشده است"
            }
        
        # حل کردن reference اگر باشد
        user_id_resolved = WorkflowEngine._resolve_value_static(user_id_raw, context, node_results)
        
        # تبدیل به integer
        try:
            user_id = int(user_id_resolved) if user_id_resolved else None
        except (ValueError, TypeError):
            return {
                "success": False,
                "error": f"user_id نامعتبر: {user_id_resolved}"
            }
        
        if not user_id:
            return {
                "success": False,
                "error": "user_id مشخص نشده است"
            }
        
        # بررسی اینکه کاربر عضو کسب و کار است
        permission_repo = BusinessPermissionRepository(db)
        is_owner = False
        is_member = False
        
        # بررسی owner
        from adapters.db.models.business import Business
        business = db.get(Business, business_id)
        if business and business.owner_id == user_id:
            is_owner = True
        else:
            # بررسی member
            permission = permission_repo.get_by_user_and_business(user_id, business_id)
            if permission:
                is_member = True
        
        if not is_owner and not is_member:
            return {
                "success": False,
                "error": f"کاربر {user_id} عضو کسب و کار {business_id} نیست"
            }
        
        # دریافت کاربر و بررسی اتصال به تلگرام
        user = db.get(User, user_id)
        if not user:
            return {
                "success": False,
                "error": f"کاربر {user_id} یافت نشد"
            }
        
        if not user.telegram_chat_id:
            return {
                "success": False,
                "error": f"کاربر {user_id} به ربات تلگرام متصل نیست"
            }
        
        # دریافت تنظیمات تلگرام
        notify_cfg = get_effective_notifications_settings(db)
        telegram = TelegramProvider(
            bot_token=notify_cfg.get("telegram_bot_token"),
            proxy_config=notify_cfg.get("telegram_proxy"),
        )
        
        if not telegram.is_configured():
            return {
                "success": False,
                "error": "ربات تلگرام پیکربندی نشده است"
            }
        
        # حل کردن متن پیام
        message = WorkflowEngine._resolve_value_static(config.get("message"), context, node_results)
        if not message:
            return {
                "success": False,
                "error": "متن پیام مشخص نشده است"
            }
        
        parse_mode = config.get("parse_mode", "None")
        if parse_mode == "None":
            parse_mode = None
        
        def _send_telegram():
            # استفاده از send_text با telegram_chat_id
            return telegram.send_text(
                chat_id=int(user.telegram_chat_id),
                text=str(message),
                parse_mode=parse_mode
            )
        
        # ارسال با retry mechanism
        retry_on_failure = config.get("retry_on_failure", True)
        
        try:
            if retry_on_failure:
                retry_config = get_retry_config_from_action_config(config)
                success = execute_with_retry(_send_telegram, **retry_config)
            else:
                success = _send_telegram()
        except Exception as e:
            logger.error(f"Error sending telegram message: {e}", exc_info=True)
            return {
                "success": False,
                "error": str(e),
                "user_id": user_id,
                "telegram_chat_id": user.telegram_chat_id
            }
        
        return {
            "success": success,
            "user_id": user_id,
            "telegram_chat_id": user.telegram_chat_id,
            "message": message
        }


class CreateNotificationAction(ActionHandler):
    """ایجاد notification در سیستم"""
    
    def get_metadata(self) -> Dict[str, Any]:
        return {
            "name": "ایجاد Notification",
            "description": "ایجاد یک notification برای کاربر",
            "config_schema": {
                "user_id": {
                    "type": "integer",
                    "description": "شناسه کاربر (اختیاری)",
                    "required": False
                },
                "event_key": {
                    "type": "string",
                    "description": "کلید رویداد",
                    "required": True
                },
                "title": {
                    "type": "string",
                    "description": "عنوان notification",
                    "required": True
                },
                "message": {
                    "type": "string",
                    "description": "متن notification",
                    "required": True
                },
                "channels": {
                    "type": "array",
                    "description": "کانال‌های ارسال",
                    "items": {"type": "string", "enum": ["inapp", "email", "sms", "push"]},
                    "default": ["inapp"],
                    "required": False
                },
                "priority": {
                    "type": "string",
                    "description": "اولویت (low/normal/high/urgent)",
                    "enum": ["low", "normal", "high", "urgent"],
                    "default": "normal",
                    "required": False
                },
                "category": {
                    "type": "string",
                    "description": "دسته‌بندی",
                    "required": False
                }
            }
        }
    
    @log_action_execution
    def execute(
        self,
        context: Dict[str, Any],
        config: Dict[str, Any],
        node_results: Dict[str, Any]
    ) -> Dict[str, Any]:
        from adapters.db.session import get_db_session
        from app.services.notification_service import NotificationService
        
        db = context.get("db")
        if not db:
            db = get_db_session().__enter__()
        
        notification_service = NotificationService(db)
        
        # حل کردن مقادیر
        user_id = config.get("user_id") or context.get("user_id")
        event_key = WorkflowEngine._resolve_value_static(config.get("event_key"), context, node_results)
        title = WorkflowEngine._resolve_value_static(config.get("title"), context, node_results)
        message = WorkflowEngine._resolve_value_static(config.get("message"), context, node_results)
        channels = config.get("channels", ["inapp"])
        priority = config.get("priority", "normal")
        category = config.get("category")
        
        # ایجاد notification
        notification_service.send(
            user_id=user_id,
            event_key=str(event_key),
            context={
                "subject": str(title),
                "message": str(message),
                "priority": priority,
                "category": category
            },
            preferred_channels=channels
        )
        
        return {
            "success": True,
            "user_id": user_id,
            "event_key": event_key,
            "channels": channels
        }

