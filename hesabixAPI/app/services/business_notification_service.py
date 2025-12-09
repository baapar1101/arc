"""
سرویس جامع مدیریت و ارسال نوتیفیکیشن برای کسب‌وکارها

این سرویس شامل:
- رندر قالب‌ها با جایگزینی متغیرها (Jinja2 Template Engine)
- بررسی محدودیت‌های ارسال (Rate Limiting)
- ارسال SMS/Email با استفاده از قالب‌ها
- ثبت لاگ کامل
- به‌روزرسانی آمار
"""
from __future__ import annotations

import logging
from datetime import datetime, date
from typing import Any, Dict, List, Optional
from decimal import Decimal

from sqlalchemy.orm import Session
from jinja2.sandbox import SandboxedEnvironment
from jinja2 import BaseLoader, TemplateSyntaxError, UndefinedError

from adapters.db.models.business_notification import (
    NotificationEventType,
    BusinessNotificationTemplate,
    NotificationSendLog
)
from adapters.db.models.person import Person
from adapters.db.models.business import Business
from adapters.db.repositories.business_notification_repo import (
    NotificationEventTypeRepository,
    BusinessNotificationTemplateRepository,
    NotificationSendLogRepository,
    NotificationDailyStatRepository
)
from app.services.providers.sms_provider import SmsProvider
from app.services.providers.email_provider import EmailProvider
from app.services.email_service import EmailService
from app.services.system_settings_service import get_effective_notifications_settings
from app.utils.phone_utils import normalize_phone_number
from app.core.responses import ApiError

logger = logging.getLogger(__name__)


class TemplateRenderService:
    """
    سرویس رندر قالب‌ها با Jinja2
    
    قابلیت‌ها:
    - جایگزینی متغیرها با مقادیر واقعی
    - فیلترهای سفارشی (مثلاً فرمت تاریخ، فرمت عدد)
    - Sandbox محیط برای امنیت
    """
    
    def __init__(self):
        self.env = SandboxedEnvironment(
            loader=BaseLoader(),
            autoescape=True,
            enable_async=False
        )
        
        # اضافه کردن فیلترهای سفارشی
        self.env.filters['format_number'] = self._format_number
        self.env.filters['format_date'] = self._format_date
        self.env.filters['format_currency'] = self._format_currency
    
    def _format_number(self, value: Any) -> str:
        """فرمت کردن عدد با جداکننده هزارگان"""
        try:
            return f"{float(value):,.0f}".replace(',', '،')
        except (ValueError, TypeError):
            return str(value)
    
    def _format_date(self, value: Any, format: str = '%Y/%m/%d') -> str:
        """فرمت کردن تاریخ"""
        try:
            if isinstance(value, str):
                # تلاش برای parse کردن
                dt = datetime.fromisoformat(value.replace('Z', '+00:00'))
            elif isinstance(value, datetime):
                dt = value
            elif isinstance(value, date):
                dt = datetime.combine(value, datetime.min.time())
            else:
                return str(value)
            
            return dt.strftime(format)
        except (ValueError, AttributeError):
            return str(value)
    
    def _format_currency(self, value: Any, currency: str = 'تومان') -> str:
        """فرمت کردن مبلغ با واحد ارز"""
        formatted_number = self._format_number(value)
        return f"{formatted_number} {currency}"
    
    def render(self, template_text: str, context: Dict[str, Any]) -> str:
        """
        رندر یک قالب با context داده شده
        
        Args:
            template_text: متن قالب (مثلاً "سلام {{ customer_name }}")
            context: دیکشنری متغیرها
        
        Returns:
            متن رندر شده
        
        Raises:
            TemplateSyntaxError: خطای Syntax در قالب
            UndefinedError: متغیر استفاده شده تعریف نشده
        """
        if not template_text:
            return ""
        
        try:
            template = self.env.from_string(template_text)
            return template.render(**context)
        except TemplateSyntaxError as e:
            logger.error(f"Template syntax error: {e}")
            raise ApiError(
                "TEMPLATE_SYNTAX_ERROR",
                f"خطای Syntax در قالب: {str(e)}",
                http_status=400
            )
        except UndefinedError as e:
            logger.error(f"Undefined variable in template: {e}")
            raise ApiError(
                "TEMPLATE_UNDEFINED_VARIABLE",
                f"متغیر تعریف نشده در قالب: {str(e)}",
                http_status=400
            )
        except Exception as e:
            logger.error(f"Unexpected error rendering template: {e}", exc_info=True)
            # در صورت خطای غیرمنتظره، متن خام برمی‌گردانیم
            return template_text
    
    def validate_template(self, template_text: str, required_vars: List[str]) -> Dict[str, Any]:
        """
        اعتبارسنجی یک قالب
        
        بررسی:
        - Syntax قالب صحیح باشد
        - متغیرهای لازم استفاده شده باشند
        
        Returns:
            دیکشنری با نتیجه validation
        """
        result = {
            "is_valid": True,
            "errors": [],
            "warnings": [],
            "used_variables": []
        }
        
        try:
            # بررسی Syntax
            template = self.env.from_string(template_text)
            
            # استخراج متغیرهای استفاده شده
            from jinja2 import meta
            ast = self.env.parse(template_text)
            used_vars = meta.find_undeclared_variables(ast)
            result["used_variables"] = list(used_vars)
            
            # بررسی متغیرهای لازم
            for var in required_vars:
                if var not in used_vars:
                    result["warnings"].append(f"متغیر '{var}' استفاده نشده است")
            
        except TemplateSyntaxError as e:
            result["is_valid"] = False
            result["errors"].append(f"خطای Syntax: {str(e)}")
        except Exception as e:
            result["is_valid"] = False
            result["errors"].append(f"خطای غیرمنتظره: {str(e)}")
        
        return result


class BusinessNotificationService:
    """
    سرویس اصلی مدیریت و ارسال نوتیفیکیشن کسب‌وکارها
    """
    
    def __init__(self, db: Session):
        self.db = db
        self.template_renderer = TemplateRenderService()
        
        # Repositories
        self.event_type_repo = NotificationEventTypeRepository(db)
        self.template_repo = BusinessNotificationTemplateRepository(db)
        self.log_repo = NotificationSendLogRepository(db)
        self.stat_repo = NotificationDailyStatRepository(db)
        
        # Providers
        notify_cfg = get_effective_notifications_settings(db)
        self.sms_provider = SmsProvider(
            provider_name=notify_cfg.get("sms_provider_name"),
            api_key=notify_cfg.get("sms_api_key"),
            sender=notify_cfg.get("sms_sender"),
            username=notify_cfg.get("sms_provider_username"),
            password=notify_cfg.get("sms_provider_password"),
            is_flash=notify_cfg.get("sms_is_flash", False),
        )
        self.email_provider = EmailProvider(db)
        self.email_service = EmailService(db)  # برای ارسال مستقیم به Person
    
    def send_to_person(
        self,
        business_id: int,
        person_id: int,
        event_type: str,
        context: Dict[str, Any],
        channel: Optional[str] = None,
        triggered_by_user_id: Optional[int] = None
    ) -> Dict[str, Any]:
        """
        ارسال نوتیفیکیشن به یک Person (مشتری، تامین‌کننده، و...)
        
        Args:
            business_id: شناسه کسب‌وکار
            person_id: شناسه Person
            event_type: نوع رویداد (مثلاً "invoice.created")
            context: داده‌های متغیرها
            channel: کانال ارسال (None = همه کانال‌های فعال)
            triggered_by_user_id: کاربری که این ارسال را trigger کرده
        
        Returns:
            دیکشنری نتیجه ارسال
        """
        # دریافت Person
        person = self.db.query(Person).filter(Person.id == person_id).first()
        if not person:
            raise ApiError("PERSON_NOT_FOUND", "شخص یافت نشد", http_status=404)
        
        # دریافت کسب‌وکار برای اضافه کردن به context
        business = self.db.query(Business).filter(Business.id == business_id).first()
        if business:
            context.setdefault("business_name", business.name)
            context.setdefault("business_phone", business.phone or "")
        
        # تعیین کانال‌های ارسال
        channels_to_send = []
        if channel:
            channels_to_send = [channel]
        else:
            # ارسال به همه کانال‌هایی که قالب فعال دارند
            if person.mobile:
                channels_to_send.append('sms')
            if person.email:
                channels_to_send.append('email')
        
        results = {}
        
        for ch in channels_to_send:
            try:
                # پیدا کردن قالب فعال
                template = self.template_repo.find_active_template(
                    business_id=business_id,
                    event_type=event_type,
                    channel=ch
                )
                
                if not template:
                    logger.warning(
                        f"No active template found for business={business_id}, "
                        f"event={event_type}, channel={ch}"
                    )
                    results[ch] = {
                        "success": False,
                        "error": "قالب فعالی یافت نشد"
                    }
                    continue
                
                # بررسی محدودیت روزانه
                if not self._check_daily_limit(business_id, template.id, ch):
                    results[ch] = {
                        "success": False,
                        "error": "محدودیت ارسال روزانه"
                    }
                    continue
                
                # رندر قالب
                rendered_body = self.template_renderer.render(template.body, context)
                rendered_subject = None
                if template.subject and ch == 'email':
                    rendered_subject = self.template_renderer.render(template.subject, context)
                
                # ارسال
                send_result = self._send_message(
                    channel=ch,
                    recipient=person,
                    subject=rendered_subject,
                    body=rendered_body
                )
                
                # ثبت لاگ
                log = self._create_log(
                    business_id=business_id,
                    template_id=template.id,
                    recipient_type='person',
                    recipient_id=person_id,
                    recipient_identifier=person.mobile if ch == 'sms' else person.email,
                    channel=ch,
                    subject=rendered_subject,
                    body=rendered_body,
                    context_data=context,
                    event_type=event_type,
                    triggered_by_user_id=triggered_by_user_id,
                    send_result=send_result
                )
                
                # به‌روزرسانی آمار
                if send_result['success']:
                    self.stat_repo.increment_sent(
                        business_id=business_id,
                        template_id=template.id,
                        target_date=date.today(),
                        channel=ch,
                        cost=send_result.get('cost', Decimal('0'))
                    )
                else:
                    self.stat_repo.increment_failed(
                        business_id=business_id,
                        template_id=template.id,
                        target_date=date.today(),
                        channel=ch
                    )
                
                results[ch] = {
                    "success": send_result['success'],
                    "log_id": log.id,
                    "message": "ارسال با موفقیت انجام شد" if send_result['success'] else send_result.get('error')
                }
                
            except Exception as e:
                logger.error(f"Error sending notification via {ch}: {e}", exc_info=True)
                results[ch] = {
                    "success": False,
                    "error": str(e)
                }
        
        self.db.commit()
        
        return {
            "event_type": event_type,
            "recipient": {
                "type": "person",
                "id": person_id,
                "name": person.name
            },
            "results": results
        }
    
    def _check_daily_limit(
        self,
        business_id: int,
        template_id: int,
        channel: str
    ) -> bool:
        """بررسی محدودیت ارسال روزانه"""
        template = self.template_repo.get_by_id(template_id, business_id)
        if not template:
            return False
        
        today_count = self.log_repo.get_daily_count(
            business_id=business_id,
            template_id=template_id,
            channel=channel,
            target_date=date.today()
        )
        
        return today_count < template.daily_limit
    
    def _send_message(
        self,
        channel: str,
        recipient: Person,
        subject: Optional[str],
        body: str
    ) -> Dict[str, Any]:
        """ارسال پیام از طریق کانال مشخص"""
        result = {
            "success": False,
            "error": None,
            "provider_message_id": None,
            "cost": Decimal('0')
        }
        
        try:
            if channel == 'sms':
                if not recipient.mobile:
                    result["error"] = "شماره موبایل یافت نشد"
                    return result
                
                mobile = normalize_phone_number(recipient.mobile)
                success, message_id, error_msg = self.sms_provider.send_text_with_details(
                    to_phone=mobile,
                    text=body
                )
                
                result["success"] = success
                result["error"] = error_msg
                result["provider_message_id"] = message_id
                # TODO: دریافت cost از provider (نیاز به API provider دارد)
                
            elif channel == 'email':
                if not recipient.email:
                    result["error"] = "ایمیل یافت نشد"
                    return result
                
                # ارسال ایمیل به Person با استفاده از EmailService
                try:
                    success = self.email_service.send_email(
                        to=recipient.email,
                        subject=subject or "نوتیفیکیشن",
                        body=body,
                        html_body=None  # می‌توان در آینده HTML body اضافه کرد
                    )
                    
                    if success:
                        result["success"] = True
                        # TODO: دریافت message_id از email service (اگر در آینده اضافه شود)
                    else:
                        result["error"] = "خطا در ارسال ایمیل"
                        logger.warning(f"Failed to send email to {recipient.email}")
                except Exception as email_error:
                    logger.error(f"Error sending email to Person {recipient.id}: {email_error}", exc_info=True)
                    result["error"] = f"خطا در ارسال ایمیل: {str(email_error)}"
                
        except Exception as e:
            logger.error(f"Error in _send_message: {e}", exc_info=True)
            result["error"] = str(e)
        
        return result
    
    def _create_log(
        self,
        business_id: int,
        template_id: int,
        recipient_type: str,
        recipient_id: int,
        recipient_identifier: Optional[str],
        channel: str,
        subject: Optional[str],
        body: str,
        context_data: Dict[str, Any],
        event_type: str,
        triggered_by_user_id: Optional[int],
        send_result: Dict[str, Any]
    ) -> NotificationSendLog:
        """ثبت لاگ ارسال"""
        log_data = {
            "business_id": business_id,
            "template_id": template_id,
            "recipient_type": recipient_type,
            "recipient_id": recipient_id,
            "recipient_identifier": recipient_identifier,
            "channel": channel,
            "subject": subject,
            "body": body,
            "context_data": context_data,
            "event_type": event_type,
            "triggered_by_user_id": triggered_by_user_id,
            "status": "sent" if send_result['success'] else "failed",
            "provider_name": "kavenegar" if channel == 'sms' else "smtp",
            "provider_message_id": send_result.get('provider_message_id'),
            "cost": send_result.get('cost', Decimal('0'))
        }
        
        if send_result['success']:
            log_data["sent_at"] = datetime.utcnow()
        else:
            log_data["failed_at"] = datetime.utcnow()
            log_data["failure_reason"] = send_result.get('error')
        
        return self.log_repo.create(log_data)
    
    def preview_template(
        self,
        business_id: int,
        template_id: int,
        sample_context: Dict[str, Any]
    ) -> Dict[str, Any]:
        """
        پیش‌نمایش یک قالب با context نمونه
        
        برای نمایش به کاربر قبل از ارسال واقعی
        """
        template = self.template_repo.get_by_id(template_id, business_id)
        if not template:
            raise ApiError("TEMPLATE_NOT_FOUND", "قالب یافت نشد", http_status=404)
        
        try:
            rendered_body = self.template_renderer.render(template.body, sample_context)
            rendered_subject = None
            if template.subject:
                rendered_subject = self.template_renderer.render(template.subject, sample_context)
            
            return {
                "template_id": template.id,
                "template_name": template.name,
                "channel": template.channel,
                "original": {
                    "subject": template.subject,
                    "body": template.body
                },
                "rendered": {
                    "subject": rendered_subject,
                    "body": rendered_body
                },
                "context_used": sample_context
            }
        except ApiError:
            raise
        except Exception as e:
            logger.error(f"Error previewing template: {e}", exc_info=True)
            raise ApiError(
                "PREVIEW_ERROR",
                f"خطا در پیش‌نمایش قالب: {str(e)}",
                http_status=500
            )


