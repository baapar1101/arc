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
        from app.services.workflow.dry_run import dry_run_skip
        from app.services.workflow.workflow_engine import WorkflowEngine

        sk = dry_run_skip(context, "ارسال ایمیل")
        if sk is not None:
            return sk

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
        from app.services.workflow.dry_run import dry_run_skip

        sk = dry_run_skip(context, "ارسال تلگرام")
        if sk is not None:
            return sk

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


class SendBaleAction(ActionHandler):
    """ارسال پیام به پیام‌رسان بله"""

    def get_metadata(self) -> Dict[str, Any]:
        return {
            "name": "ارسال پیام به بله",
            "description": "ارسال متن و/یا فایل (مثلاً خروجی نود پشتیبان) به کاربر متصل به ربات بله",
            "config_schema": {
                "user_id": {
                    "type": "string",
                    "description": "شناسه کاربر عضو کسب و کار که به ربات بله متصل است (می‌تواند از نودهای قبلی باشد: $node_id.user_id)",
                    "required": True,
                    "ui_type": "bale_user_selector",
                    "ui_config": {
                        "filter": "bale_connected",
                        "business_scoped": True
                    }
                },
                "send_file_attachment": {
                    "type": "boolean",
                    "description": "ارسال فایل از فایل‌سرور (مثلاً فایل پشتیبان نود قبلی)",
                    "default": False,
                    "required": False,
                },
                "attachment_file_id": {
                    "type": "string",
                    "description": "شناسه فایل ذخیره‌شده؛ معمولاً $شناسه_نود_پشتیبان.file_id",
                    "required": False,
                },
                "message": {
                    "type": "string",
                    "description": "متن پیام یا زیرنویس فایل (caption). اگر فقط فایل می‌فرستید می‌توانید خالی بگذارید یا توضیح کوتاه بنویسید",
                    "required": False,
                    "ui_type": "textarea",
                    "maxLength": 8000,
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
        from app.services.providers.bale_provider import BaleProvider
        from app.services.system_settings_service import get_effective_notifications_settings
        from app.services.workflow.utils import execute_with_retry, get_retry_config_from_action_config
        from adapters.db.models.user import User
        from adapters.db.repositories.business_permission_repo import BusinessPermissionRepository
        from app.services.workflow.dry_run import dry_run_skip

        sk = dry_run_skip(context, "ارسال بله")
        if sk is not None:
            return sk

        db = context.get("db")
        if not db:
            db = get_db_session().__enter__()

        business_id = context.get("business_id")
        if not business_id:
            return {
                "success": False,
                "error": "business_id در context موجود نیست"
            }

        user_id_raw = config.get("user_id")
        if not user_id_raw:
            return {
                "success": False,
                "error": "user_id مشخص نشده است"
            }

        user_id_resolved = WorkflowEngine._resolve_value_static(user_id_raw, context, node_results)
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

        permission_repo = BusinessPermissionRepository(db)
        is_owner = False
        is_member = False
        from adapters.db.models.business import Business
        business = db.get(Business, business_id)
        if business and business.owner_id == user_id:
            is_owner = True
        else:
            permission = permission_repo.get_by_user_and_business(user_id, business_id)
            if permission:
                is_member = True

        if not is_owner and not is_member:
            return {
                "success": False,
                "error": f"کاربر {user_id} عضو کسب و کار {business_id} نیست"
            }

        user = db.get(User, user_id)
        if not user:
            return {
                "success": False,
                "error": f"کاربر {user_id} یافت نشد"
            }

        bale_chat_id = getattr(user, "bale_chat_id", None)
        if not bale_chat_id:
            return {
                "success": False,
                "error": f"کاربر {user_id} به ربات بله متصل نیست"
            }

        notify_cfg = get_effective_notifications_settings(db)
        bale = BaleProvider(bot_token=notify_cfg.get("bale_bot_token"))

        if not bale.is_configured():
            return {
                "success": False,
                "error": "ربات بله پیکربندی نشده است"
            }

        _sf = WorkflowEngine._resolve_value_static(
            config.get("send_file_attachment"), context, node_results
        )
        if isinstance(_sf, str):
            send_file = _sf.strip().lower() in ("1", "true", "yes", "on")
        else:
            send_file = bool(_sf)

        raw_message = config.get("message")
        message_template = raw_message if isinstance(raw_message, str) else ("" if raw_message is None else str(raw_message))
        message = WorkflowEngine._resolve_value_static(message_template, context, node_results)
        if message is None:
            message = ""
        message = str(message).strip() if isinstance(message, str) else str(message)

        parse_mode = config.get("parse_mode", "None")
        if parse_mode == "None":
            parse_mode = None

        if send_file:
            att_raw = config.get("attachment_file_id")
            if att_raw is None or (isinstance(att_raw, str) and not att_raw.strip()):
                return {
                    "success": False,
                    "error": "برای ارسال فایل، attachment_file_id الزامی است (مثلاً $node_id.file_id)",
                    "user_id": user_id,
                    "bale_chat_id": bale_chat_id,
                }
            fid_resolved = WorkflowEngine._resolve_value_static(att_raw, context, node_results)
            if fid_resolved is None or str(fid_resolved).strip() == "":
                return {
                    "success": False,
                    "error": "شناسه فایل نامعتبر است",
                    "user_id": user_id,
                    "bale_chat_id": bale_chat_id,
                }
            from uuid import UUID

            try:
                fid = UUID(str(fid_resolved).strip())
            except ValueError:
                return {
                    "success": False,
                    "error": f"attachment_file_id نامعتبر: {fid_resolved}",
                    "user_id": user_id,
                    "bale_chat_id": bale_chat_id,
                }

            from adapters.db.session import get_db_session
            from app.services.async_isolated import run_coroutine_isolated
            from app.services.file_storage_service import FileStorageService

            async def _dl():
                with get_db_session() as thread_db:
                    svc = FileStorageService(thread_db)
                    return await svc.download_file(fid)

            try:
                blob = run_coroutine_isolated(lambda: _dl())
            except Exception as e:
                logger.error("bale workflow download attachment: %s", e, exc_info=True)
                return {
                    "success": False,
                    "error": f"دانلود فایل برای ارسال: {e}",
                    "user_id": user_id,
                    "bale_chat_id": bale_chat_id,
                }

            content = blob.get("content") or b""
            fname = (blob.get("filename") or "attachment.bin").strip() or "attachment.bin"
            caption = message if message else None

            def _send_bale_doc():
                return bale.send_document(
                    chat_id=int(bale_chat_id),
                    file_bytes=bytes(content),
                    filename=fname,
                    caption=caption,
                )

            retry_on_failure = config.get("retry_on_failure", True)
            try:
                if retry_on_failure:
                    retry_config = get_retry_config_from_action_config(config)
                    success = execute_with_retry(_send_bale_doc, **retry_config)
                else:
                    success = _send_bale_doc()
            except Exception as e:
                logger.error(f"Error sending bale document: {e}", exc_info=True)
                return {
                    "success": False,
                    "error": str(e),
                    "user_id": user_id,
                    "bale_chat_id": bale_chat_id,
                }

            return {
                "success": success,
                "user_id": user_id,
                "bale_chat_id": bale_chat_id,
                "message": message,
                "send_file_attachment": True,
                "attachment_file_id": str(fid),
                "filename": fname,
            }

        if not message:
            return {
                "success": False,
                "error": "متن پیام مشخص نشده است (یا send_file_attachment را فعال کنید)",
            }

        def _send_bale():
            return bale.send_text(
                chat_id=int(bale_chat_id),
                text=str(message).strip(),
                parse_mode=parse_mode
            )

        retry_on_failure = config.get("retry_on_failure", True)
        try:
            if retry_on_failure:
                retry_config = get_retry_config_from_action_config(config)
                success = execute_with_retry(_send_bale, **retry_config)
            else:
                success = _send_bale()
        except Exception as e:
            logger.error(f"Error sending bale message: {e}", exc_info=True)
            return {
                "success": False,
                "error": str(e),
                "user_id": user_id,
                "bale_chat_id": bale_chat_id
            }

        return {
            "success": success,
            "user_id": user_id,
            "bale_chat_id": bale_chat_id,
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
                    "ui_type": "notification_event_type_selector",
                    "description": "کلید رویداد (از لیست سیستم، مقدار دستی یا ارجاع به نود قبلی مانند $node_id.field)",
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
        from app.services.workflow.dry_run import dry_run_skip

        sk = dry_run_skip(context, "اعلان (نوتیفیکیشن)")
        if sk is not None:
            return sk
        
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


class SendBusinessSmsAction(ActionHandler):
    """ارسال پیامک با قالب نوتیفیکیشن تاییدشدهٔ همان کسب‌وکار (کسر کیف پول و سند حسابداری طبق سرویس موجود)."""

    def get_metadata(self) -> Dict[str, Any]:
        return {
            "name": "ارسال پیامک (قالب تاییدشده)",
            "description": "ارسال پیامک با یکی از قالب‌های SMS تاییدشده؛ پارامترهای قالب از ترکیب trigger، متغیرها و template_context پر می‌شود",
            "config_schema": {
                "template_id": {
                    "type": "integer",
                    "ui_type": "sms_template_selector",
                    "description": "قالب SMS تاییدشده در همین کسب‌وکار (از لیست انتخاب کنید یا مرجع نود قبلی)",
                    "required": True,
                },
                "person_id": {
                    "type": "integer",
                    "ui_type": "person_selector",
                    "description": "شناسه شخص (مشتری/طرف حساب) در همین کسب‌وکار",
                    "required": True,
                },
                "recipient_mobile": {
                    "type": "string",
                    "description": "اختیاری؛ خالی = استفاده از موبایل پرونده شخص. می‌توان شماره ثابت یا مرجع نود قبلی گذاشت",
                    "required": False,
                },
                "template_context": {
                    "type": "object",
                    "ui_type": "json_editor",
                    "description": "متغیرهای قالب Jinja؛ مقادیر ثابت یا ارجاع مانند $node_id.field",
                    "required": False,
                },
                "stop_workflow_on_send_failure": {
                    "type": "boolean",
                    "description": "اگر فعال باشد، در خطای ارسال از طرف پیام‌رسان (غیر از کمبود موجودی) ورک‌فلو متوقف می‌شود",
                    "default": False,
                    "required": False,
                },
            },
        }

    @log_action_execution
    def execute(
        self,
        context: Dict[str, Any],
        config: Dict[str, Any],
        node_results: Dict[str, Any],
    ) -> Dict[str, Any]:
        from adapters.db.models.workflow import WorkflowLog, WorkflowLogLevel
        from app.services.business_notification_service import BusinessNotificationService
        from app.services.workflow.dry_run import dry_run_skip
        from app.core.responses import ApiError

        sk = dry_run_skip(context, "ارسال پیامک (قالب کسب‌وکار)")
        if sk is not None:
            return sk

        db = context.get("db")
        business_id = context.get("business_id")
        execution_id = context.get("execution_id")
        user_id = context.get("user_id")

        if db is None or business_id is None:
            raise ApiError(
                "WORKFLOW_CONTEXT_INVALID",
                "زمینه اجرای workflow ناقص است",
                http_status=500,
            )

        raw_tid = WorkflowEngine._resolve_value_static(
            config.get("template_id"), context, node_results
        )
        raw_pid = WorkflowEngine._resolve_value_static(
            config.get("person_id"), context, node_results
        )
        if raw_tid is None or raw_pid is None:
            raise ApiError(
                "WORKFLOW_SMS_CONFIG",
                "template_id و person_id الزامی هستند",
                http_status=400,
            )
        try:
            template_id = int(raw_tid)
            person_id = int(raw_pid)
        except (TypeError, ValueError):
            raise ApiError(
                "WORKFLOW_SMS_CONFIG",
                "template_id و person_id باید عدد صحیح باشند",
                http_status=400,
            )

        recipient_raw = config.get("recipient_mobile")
        recipient_mobile = None
        if recipient_raw is not None and str(recipient_raw).strip():
            recipient_mobile = WorkflowEngine._resolve_value_static(
                recipient_raw, context, node_results
            )
            if recipient_mobile is not None:
                recipient_mobile = str(recipient_mobile).strip() or None

        merged: Dict[str, Any] = {}
        td = context.get("trigger_data")
        if isinstance(td, dict):
            merged.update(td)
        variables = context.get("variables")
        if isinstance(variables, dict):
            merged.update(variables)

        tc = config.get("template_context")
        if isinstance(tc, dict):
            for key, val in tc.items():
                merged[str(key)] = WorkflowEngine._resolve_value_static(
                    val, context, node_results
                )

        svc = BusinessNotificationService(db)
        result = svc.send_sms_by_template(
            business_id=int(business_id),
            template_id=template_id,
            context=merged,
            person_id=person_id,
            recipient_mobile_override=recipient_mobile,
            triggered_by_user_id=int(user_id) if user_id is not None else None,
        )

        def _append_workflow_log(level: WorkflowLogLevel, msg: str, data: Dict[str, Any]) -> None:
            try:
                wl = WorkflowLog(
                    execution_id=execution_id,
                    level=level,
                    message=msg,
                    data=data,
                )
                db.add(wl)
                db.commit()
            except Exception:
                logger.exception("workflow sms log failed")

        ok = bool(result.get("success"))
        err_code = (result.get("error") or "UNKNOWN") if not ok else ""
        payload = {
            "template_id": result.get("template_id"),
            "log_id": result.get("log_id"),
            "event_type": result.get("event_type"),
            "cost": result.get("cost"),
            "recipient": result.get("recipient"),
        }
        if ok:
            _append_workflow_log(
                WorkflowLogLevel.INFO,
                "پیامک با قالب کسب‌وکار با موفقیت ارسال شد",
                {**payload, "success": True},
            )
        else:
            _append_workflow_log(
                WorkflowLogLevel.ERROR,
                f"ارسال پیامک ناموفق: {err_code} — {result.get('message') or result.get('error_message')}",
                {**payload, "success": False, "error": err_code},
            )

        if not ok and err_code == "INSUFFICIENT_FUNDS":
            raise ApiError(
                "INSUFFICIENT_FUNDS",
                result.get("error_message") or "موجودی کیف پول کافی نیست",
                http_status=400,
            )

        raw_stop = WorkflowEngine._resolve_value_static(
            config.get("stop_workflow_on_send_failure"), context, node_results
        )
        stop_on_fail = raw_stop in (True, "true", "1", 1, "True", "yes", "on")
        if not ok and stop_on_fail and err_code != "INSUFFICIENT_FUNDS":
            msg = result.get("message") or result.get("error_message") or "ارسال پیامک ناموفق بود"
            raise ApiError(
                "SMS_SEND_FAILED",
                msg,
                http_status=502,
            )

        out = dict(result)
        out["success"] = ok
        return out

