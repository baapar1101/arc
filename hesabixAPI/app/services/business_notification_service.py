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
import json
from datetime import datetime, date
from typing import Any, Dict, List, Optional
from decimal import Decimal

from sqlalchemy import and_
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
from app.services.system_settings_service import (
    get_effective_notifications_settings,
    get_notification_sms_pricing,
    get_wallet_settings
)
from app.services.wallet_service import (
    charge_wallet_for_notification,
    _get_wallet_account_for_update
)
from app.services.notification_service import NotificationService
from app.utils.phone_utils import normalize_phone_number
from app.core.responses import ApiError

logger = logging.getLogger(__name__)


def calculate_sms_count(text: str) -> int:
    """
    محاسبه تعداد پیامک بر اساس طول متن
    
    استاندارد SMS:
    - 1-70 کاراکتر = 1 پیامک
    - 71-134 کاراکتر = 2 پیامک
    - 135-201 کاراکتر = 3 پیامک
    - و الی آخر (هر 67 کاراکتر بعدی = 1 پیامک اضافی)
    
    Args:
        text: متن پیامک
        
    Returns:
        تعداد پیامک مورد نیاز
    """
    length = len(text)
    if length <= 70:
        return 1
    # هر 67 کاراکتر بعدی = 1 پیامک اضافی
    return 1 + ((length - 70 + 66) // 67)


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
    
    def _calculate_sms_cost(
        self,
        sms_count: int,
        event_type: str
    ) -> Decimal:
        """
        محاسبه هزینه ارسال پیامک
        
        Args:
            sms_count: تعداد پیامک
            event_type: نوع رویداد
            
        Returns:
            هزینه کل (بر اساس ارز کیف پول)
            
        Raises:
            ApiError: در صورت خطا در محاسبه هزینه
        """
        try:
            if sms_count <= 0:
                raise ApiError(
                    "INVALID_SMS_COUNT",
                    "تعداد پیامک باید بزرگتر از صفر باشد",
                    http_status=400
                )
            
            pricing = get_notification_sms_pricing(self.db)
            
            # بررسی قیمت خاص برای event_type
            event_prices = pricing.get("event_type_prices", {})
            price_per_sms = event_prices.get(event_type)
            
            # اگر قیمت خاصی تعریف نشده، از قیمت پیش‌فرض استفاده می‌کنیم
            if price_per_sms is None:
                price_per_sms = pricing.get("price_per_sms", 500.0)
            
            # اعتبارسنجی نهایی قیمت
            try:
                price_per_sms = float(price_per_sms)
                if price_per_sms <= 0:
                    logger.warning(
                        f"قیمت پیامک نامعتبر است ({price_per_sms}). استفاده از مقدار پیش‌فرض 500"
                    )
                    price_per_sms = 500.0
            except (ValueError, TypeError):
                logger.warning(
                    f"خطا در تبدیل قیمت پیامک. استفاده از مقدار پیش‌فرض 500"
                )
                price_per_sms = 500.0
            
            total_cost = Decimal(str(price_per_sms)) * Decimal(str(sms_count))
            
            if total_cost <= 0:
                raise ApiError(
                    "INVALID_COST",
                    "هزینه محاسبه شده نامعتبر است",
                    http_status=500
                )
            
            return total_cost
            
        except ApiError:
            raise
        except Exception as e:
            logger.error(f"خطا در محاسبه هزینه پیامک: {e}", exc_info=True)
            raise ApiError(
                "COST_CALCULATION_ERROR",
                f"خطا در محاسبه هزینه: {str(e)}",
                http_status=500
            )

    def estimate_sms_template_cost(
        self,
        business_id: int,
        template_id: int,
    ) -> Dict[str, Any]:
        """
        برآورد هزینه ارسال بر اساس طول متن خام قالب و قیمت‌گذاری اعلامی در تنظیمات ادمین.
        پس از رندر قالب متن نهایی ممکن است متفاوت باشد؛ هزینه واقعی همان لحظه ارسال محاسبه می‌شود.
        """
        template = self.template_repo.get_by_id(template_id, business_id)
        if not template:
            raise ApiError("TEMPLATE_NOT_FOUND", "قالب یافت نشد", http_status=404)
        if template.channel != "sms":
            raise ApiError(
                "TEMPLATE_NOT_SMS",
                "قالب انتخاب‌شده برای پیامک نیست",
                http_status=400,
            )

        body = template.body or ""
        sms_count = calculate_sms_count(body)
        total_cost = self._calculate_sms_cost(sms_count, template.event_type)
        unit_cost = self._calculate_sms_cost(1, template.event_type)
        price_per_sms = float(unit_cost)

        return {
            "template_id": template.id,
            "template_name": template.name,
            "event_type": template.event_type,
            "body_char_count": len(body),
            "sms_segments": sms_count,
            "price_per_sms": price_per_sms,
            "estimated_total": float(total_cost),
            "disclaimer": "estimate_based_on_raw_template",
        }

    def send_sms_by_template(
        self,
        business_id: int,
        template_id: int,
        context: Dict[str, Any],
        person_id: int,
        recipient_mobile_override: Optional[str] = None,
        triggered_by_user_id: Optional[int] = None,
    ) -> Dict[str, Any]:
        """
        ارسال پیامک با یک قالب مشخص (برای ورک‌فلو و اتوماسیون).

        قالب باید متعلق به همان business، کانال sms، وضعیت approved و فعال باشد.
        هزینه و کیف پول مطابق تنظیمات قیمت‌گذاری پیامک و الگوی send_to_person.
        """
        template = self.template_repo.get_by_id(template_id, business_id)
        if not template:
            raise ApiError("TEMPLATE_NOT_FOUND", "قالب یافت نشد", http_status=404)
        if template.channel != "sms":
            raise ApiError(
                "TEMPLATE_NOT_SMS",
                "قالب انتخاب‌شده برای پیامک نیست",
                http_status=400,
            )
        if template.status != "approved" or not template.is_active:
            raise ApiError(
                "TEMPLATE_NOT_APPROVED",
                "قالب تایید نشده یا غیرفعال است",
                http_status=400,
            )

        person = (
            self.db.query(Person)
            .filter(and_(Person.id == person_id, Person.business_id == business_id))
            .first()
        )
        if not person:
            raise ApiError("PERSON_NOT_FOUND", "شخص یافت نشد", http_status=404)

        sms_destination: Optional[str] = None
        if recipient_mobile_override and str(recipient_mobile_override).strip():
            try:
                sms_destination = normalize_phone_number(str(recipient_mobile_override).strip())
            except Exception as e:
                raise ApiError(
                    "INVALID_RECIPIENT_MOBILE",
                    f"شماره موبایل مقصد معتبر نیست: {e}",
                    http_status=400,
                )
        elif person.mobile:
            try:
                sms_destination = normalize_phone_number(person.mobile)
            except Exception:
                sms_destination = None

        if not sms_destination:
            raise ApiError(
                "NO_SMS_RECIPIENT",
                "شماره موبایل در پرونده شخص ثبت نشده و شماره مقصد هم ارسال نشده است.",
                http_status=400,
            )

        business = self.db.query(Business).filter(Business.id == business_id).first()
        if business:
            context.setdefault("business_name", business.name)
            context.setdefault("business_phone", business.phone or "")

        event_type = template.event_type
        ch = "sms"

        try:
            if not self._check_daily_limit(business_id, template.id, ch):
                result = {
                    "success": False,
                    "error": "DAILY_LIMIT",
                    "error_message": "محدودیت ارسال روزانه",
                }
                self.db.commit()
                return result

            rendered_body = self.template_renderer.render(template.body, context)

            wallet_charge_result = None
            total_cost: Decimal = Decimal("0")

            try:
                sms_count = calculate_sms_count(rendered_body)
                if sms_count <= 0:
                    self.db.commit()
                    return {
                        "success": False,
                        "error": "INVALID_SMS_COUNT",
                        "error_message": "تعداد پیامک محاسبه شده نامعتبر است",
                    }

                total_cost = self._calculate_sms_cost(sms_count, event_type)
            except ApiError as cost_error:
                logger.error(f"خطا در محاسبه هزینه: {cost_error}")
                self.db.commit()
                return {
                    "success": False,
                    "error": cost_error.code or "COST_ERROR",
                    "error_message": cost_error.message or "خطا در محاسبه هزینه پیامک",
                }

            try:
                account = _get_wallet_account_for_update(self.db, business_id)
                available_balance = Decimal(str(account.available_balance or 0))

                if available_balance < total_cost:
                    ins = self._handle_insufficient_funds(
                        business_id=business_id,
                        user_id=triggered_by_user_id,
                        required_amount=total_cost,
                        available_amount=available_balance,
                        template_name=template.name,
                        event_type=event_type,
                        template_id=template.id,
                        person_id=person_id,
                        person=person,
                        channel=ch,
                        rendered_body=rendered_body,
                        context=context,
                    )
                    self.db.commit()
                    return ins

                wallet_charge_result = charge_wallet_for_notification(
                    db=self.db,
                    business_id=business_id,
                    user_id=triggered_by_user_id or 0,
                    amount=total_cost,
                    sms_count=sms_count,
                    event_type=event_type,
                    template_id=template.id,
                    template_name=template.name,
                )
            except ApiError as e:
                if e.code == "INSUFFICIENT_FUNDS":
                    ins = self._handle_insufficient_funds(
                        business_id=business_id,
                        user_id=triggered_by_user_id,
                        required_amount=total_cost,
                        available_amount=Decimal("0"),
                        template_name=template.name,
                        event_type=event_type,
                        template_id=template.id,
                        person_id=person_id,
                        person=person,
                        channel=ch,
                        rendered_body=rendered_body,
                        context=context,
                    )
                    self.db.commit()
                    return ins
                raise

            to_phone = sms_destination
            send_result = self._send_message(
                channel=ch,
                recipient=person,
                subject=None,
                body=rendered_body,
                to_phone_override=to_phone,
            )

            if wallet_charge_result:
                try:
                    total_cost = self._calculate_sms_cost(
                        calculate_sms_count(rendered_body),
                        event_type,
                    )
                    send_result["cost"] = total_cost
                except Exception as cost_error:
                    logger.warning(f"خطا در محاسبه مجدد هزینه: {cost_error}")

            if not send_result["success"] and wallet_charge_result:
                try:
                    account = _get_wallet_account_for_update(self.db, business_id)
                    account.available_balance += total_cost
                    self.db.flush()

                    from adapters.db.models.wallet import WalletTransaction

                    reversal_tx = WalletTransaction(
                        business_id=int(business_id),
                        type="notification_sms_reversal",
                        status="succeeded",
                        amount=total_cost,
                        fee_amount=Decimal("0"),
                        description=f"بازگشت مبلغ - خطا در ارسال پیامک: {send_result.get('error', 'خطای نامشخص')}",
                        document_id=wallet_charge_result.get("document_id"),
                        extra_info=json.dumps(
                            {
                                "source": "business_notification",
                                "original_transaction_id": wallet_charge_result.get(
                                    "wallet_transaction_id"
                                ),
                                "reason": "send_failed",
                                "error": send_result.get("error"),
                            },
                            ensure_ascii=False,
                        ),
                    )
                    self.db.add(reversal_tx)
                    self.db.flush()
                except Exception as reversal_error:
                    logger.error(
                        f"خطا در بازگشت مبلغ به کیف پول: {reversal_error}",
                        exc_info=True,
                    )

            recipient_identifier = sms_destination or person.mobile
            log = self._create_log(
                business_id=business_id,
                template_id=template.id,
                recipient_type="person",
                recipient_id=person_id,
                recipient_identifier=recipient_identifier,
                channel=ch,
                subject=None,
                body=rendered_body,
                context_data=context,
                event_type=event_type,
                triggered_by_user_id=triggered_by_user_id,
                send_result=send_result,
            )

            if send_result["success"]:
                self.stat_repo.increment_sent(
                    business_id=business_id,
                    template_id=template.id,
                    target_date=date.today(),
                    channel=ch,
                    cost=send_result.get("cost", Decimal("0")),
                )
            else:
                self.stat_repo.increment_failed(
                    business_id=business_id,
                    template_id=template.id,
                    target_date=date.today(),
                    channel=ch,
                )

            self.db.commit()

            display_name = ""
            if person.first_name or person.last_name:
                display_name = " ".join(
                    filter(None, [person.first_name, person.last_name])
                ).strip()
            if not display_name:
                display_name = person.alias_name or ""

            return {
                "success": send_result["success"],
                "template_id": template.id,
                "event_type": event_type,
                "log_id": log.id,
                "message": (
                    "ارسال با موفقیت انجام شد"
                    if send_result["success"]
                    else (send_result.get("error") or "خطا در ارسال")
                ),
                "error": None if send_result["success"] else (send_result.get("error") or "SEND_FAILED"),
                "recipient": {
                    "type": "person",
                    "id": person_id,
                    "name": display_name,
                },
                "cost": float(total_cost) if wallet_charge_result else 0.0,
            }

        except ApiError:
            self.db.rollback()
            raise
        except Exception as e:
            logger.error(f"send_sms_by_template failed: {e}", exc_info=True)
            self.db.rollback()
            raise

    def send_to_person(
        self,
        business_id: int,
        person_id: int,
        event_type: str,
        context: Dict[str, Any],
        channel: Optional[str] = None,
        recipient_mobile_override: Optional[str] = None,
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
            recipient_mobile_override: شماره موبایل مقصد (اختیاری؛ برای SMS به این شماره ارسال می‌شود)
            triggered_by_user_id: کاربری که این ارسال را trigger کرده
        
        Returns:
            دیکشنری نتیجه ارسال
        """
        # دریافت Person
        person = self.db.query(Person).filter(Person.id == person_id).first()
        if not person:
            raise ApiError("PERSON_NOT_FOUND", "شخص یافت نشد", http_status=404)
        
        # نرمال‌سازی شماره override در صورت ارسال
        sms_destination = None
        if recipient_mobile_override and recipient_mobile_override.strip():
            try:
                sms_destination = normalize_phone_number(recipient_mobile_override.strip())
            except Exception as e:
                raise ApiError(
                    "INVALID_RECIPIENT_MOBILE",
                    f"شماره موبایل مقصد معتبر نیست: {e}",
                    http_status=400
                )
        elif person.mobile:
            try:
                sms_destination = normalize_phone_number(person.mobile)
            except Exception:
                sms_destination = None
        
        # دریافت کسب‌وکار برای اضافه کردن به context
        business = self.db.query(Business).filter(Business.id == business_id).first()
        if business:
            context.setdefault("business_name", business.name)
            context.setdefault("business_phone", business.phone or "")
        
        # تعیین کانال‌های ارسال
        channels_to_send = []
        if channel:
            if channel == "sms" and not sms_destination:
                raise ApiError(
                    "NO_SMS_RECIPIENT",
                    "شماره موبایل در پرونده شخص ثبت نشده و شماره مقصد هم ارسال نشده است.",
                    http_status=400
                )
            channels_to_send = [channel]
        else:
            # ارسال به همه کانال‌هایی که قالب فعال دارند
            if sms_destination:
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
                
                # محاسبه هزینه و بررسی موجودی (فقط برای SMS)
                wallet_charge_result = None
                if ch == 'sms':
                    try:
                        # محاسبه تعداد پیامک
                        sms_count = calculate_sms_count(rendered_body)
                        
                        if sms_count <= 0:
                            results[ch] = {
                                "success": False,
                                "error": "تعداد پیامک محاسبه شده نامعتبر است"
                            }
                            continue
                        
                        # محاسبه هزینه
                        total_cost = self._calculate_sms_cost(sms_count, event_type)
                    except ApiError as cost_error:
                        logger.error(f"خطا در محاسبه هزینه: {cost_error}")
                        results[ch] = {
                            "success": False,
                            "error": cost_error.message or "خطا در محاسبه هزینه پیامک"
                        }
                        continue
                    except Exception as cost_error:
                        logger.error(f"خطای غیرمنتظره در محاسبه هزینه: {cost_error}", exc_info=True)
                        results[ch] = {
                            "success": False,
                            "error": "خطای غیرمنتظره در محاسبه هزینه پیامک"
                        }
                        continue
                    
                    # بررسی موجودی کیف پول
                    try:
                        from app.services.wallet_service import _get_wallet_account_for_update
                        account = _get_wallet_account_for_update(self.db, business_id)
                        available_balance = Decimal(str(account.available_balance or 0))
                        
                        if available_balance < total_cost:
                            # موجودی کافی نیست - ارسال نشود و هشدار بده
                            results[ch] = self._handle_insufficient_funds(
                                business_id=business_id,
                                user_id=triggered_by_user_id,
                                required_amount=total_cost,
                                available_amount=available_balance,
                                template_name=template.name,
                                event_type=event_type,
                                template_id=template.id,
                                person_id=person_id,
                                person=person,
                                channel=ch,
                                rendered_body=rendered_body,
                                context=context
                            )
                            continue
                        
                        # کسر از کیف پول قبل از ارسال
                        wallet_charge_result = charge_wallet_for_notification(
                            db=self.db,
                            business_id=business_id,
                            user_id=triggered_by_user_id or 0,
                            amount=total_cost,
                            sms_count=sms_count,
                            event_type=event_type,
                            template_id=template.id,
                            template_name=template.name
                        )
                    except ApiError as e:
                        if e.code == "INSUFFICIENT_FUNDS":
                            results[ch] = self._handle_insufficient_funds(
                                business_id=business_id,
                                user_id=triggered_by_user_id,
                                required_amount=total_cost,
                                available_amount=Decimal('0'),
                                template_name=template.name,
                                event_type=event_type,
                                template_id=template.id,
                                person_id=person_id,
                                person=person,
                                channel=ch,
                                rendered_body=rendered_body,
                                context=context
                            )
                            continue
                        raise
                
                # ارسال
                to_phone = sms_destination if ch == 'sms' else None
                send_result = self._send_message(
                    channel=ch,
                    recipient=person,
                    subject=rendered_subject,
                    body=rendered_body,
                    to_phone_override=to_phone
                )
                
                # اگر SMS بود و هزینه محاسبه شده، cost را تنظیم کن
                if ch == 'sms' and wallet_charge_result:
                    try:
                        total_cost = self._calculate_sms_cost(
                            calculate_sms_count(rendered_body),
                            event_type
                        )
                        send_result['cost'] = total_cost
                    except Exception as cost_error:
                        # اگر خطا در محاسبه مجدد هزینه رخ داد، از مقدار قبلی استفاده می‌کنیم
                        logger.warning(f"خطا در محاسبه مجدد هزینه: {cost_error}")
                        # cost قبلاً در wallet_charge_result ذخیره شده است
                
                # در صورت خطای ارسال و کسر شده بودن، مبلغ را برگردان
                if not send_result['success'] and wallet_charge_result and ch == 'sms':
                    try:
                        # بازگشت مبلغ به کیف پول
                        account = _get_wallet_account_for_update(self.db, business_id)
                        account.available_balance += total_cost
                        self.db.flush()
                        
                        # ثبت تراکنش reversal
                        from adapters.db.models.wallet import WalletTransaction
                        reversal_tx = WalletTransaction(
                            business_id=int(business_id),
                            type="notification_sms_reversal",
                            status="succeeded",
                            amount=total_cost,
                            fee_amount=Decimal("0"),
                            description=f"بازگشت مبلغ - خطا در ارسال پیامک: {send_result.get('error', 'خطای نامشخص')}",
                            document_id=wallet_charge_result.get('document_id'),
                            extra_info=json.dumps({
                                "source": "business_notification",
                                "original_transaction_id": wallet_charge_result.get('wallet_transaction_id'),
                                "reason": "send_failed",
                                "error": send_result.get('error')
                            }, ensure_ascii=False)
                        )
                        self.db.add(reversal_tx)
                        self.db.flush()
                        
                        logger.warning(
                            f"مبلغ {total_cost} به کیف پول کسب‌وکار {business_id} برگردانده شد "
                            f"به دلیل خطا در ارسال پیامک"
                        )
                    except Exception as reversal_error:
                        logger.error(
                            f"خطا در بازگشت مبلغ به کیف پول: {reversal_error}",
                            exc_info=True
                        )
                
                # ثبت لاگ (شماره/ایمیل واقعی که به آن ارسال شد)
                recipient_identifier = (sms_destination if ch == 'sms' else None) or (person.mobile if ch == 'sms' else person.email)
                log = self._create_log(
                    business_id=business_id,
                    template_id=template.id,
                    recipient_type='person',
                    recipient_id=person_id,
                    recipient_identifier=recipient_identifier,
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
                
            except ApiError as api_error:
                # خطاهای API را با پیام مناسب برمی‌گردانیم
                logger.error(f"API Error sending notification via {ch}: {api_error}")
                results[ch] = {
                    "success": False,
                    "error": api_error.message or str(api_error),
                    "error_code": api_error.code
                }
            except Exception as e:
                # خطاهای غیرمنتظره را لاگ می‌کنیم و پیام عمومی نمایش می‌دهیم
                logger.error(f"Error sending notification via {ch}: {e}", exc_info=True)
                results[ch] = {
                    "success": False,
                    "error": "خطا در ارسال ناتیفیکیشن. لطفاً با پشتیبانی تماس بگیرید."
                }
        
        self.db.commit()
        
        # نام نمایشی شخص (first_name + last_name یا alias_name)
        display_name = ""
        if person.first_name or person.last_name:
            display_name = " ".join(filter(None, [person.first_name, person.last_name])).strip()
        if not display_name:
            display_name = person.alias_name or ""

        return {
            "event_type": event_type,
            "recipient": {
                "type": "person",
                "id": person_id,
                "name": display_name
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
        body: str,
        to_phone_override: Optional[str] = None
    ) -> Dict[str, Any]:
        """ارسال پیام از طریق کانال مشخص. برای SMS در صورت ارسال to_phone_override از آن استفاده می‌شود."""
        result = {
            "success": False,
            "error": None,
            "provider_message_id": None,
            "cost": Decimal('0')
        }
        
        try:
            if channel == 'sms':
                mobile = to_phone_override
                if not mobile and recipient.mobile:
                    mobile = normalize_phone_number(recipient.mobile)
                if not mobile:
                    result["error"] = "شماره موبایل یافت نشد"
                    return result
                
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
    
    def _handle_insufficient_funds(
        self,
        business_id: int,
        user_id: Optional[int],
        required_amount: Decimal,
        available_amount: Decimal,
        template_name: str,
        event_type: str,
        template_id: int,
        person_id: int,
        person: Person,
        channel: str,
        rendered_body: str,
        context: Dict[str, Any]
    ) -> Dict[str, Any]:
        """
        مدیریت موجودی ناکافی:
        1. ارسال هشدار به کاربر
        2. ثبت لاگ
        3. برگرداندن خطا
        """
        if not user_id:
            user_id = 0
        
        # دریافت اطلاعات ارز کیف پول
        wallet_settings = get_wallet_settings(self.db)
        currency_code = wallet_settings.get("wallet_base_currency_code", "IRR")
        currency_symbol = wallet_settings.get("wallet_base_currency_symbol", currency_code)
        
        # محاسبه کسری
        shortfall = float(required_amount - available_amount)
        
        # آماده‌سازی پیام هشدار
        warning_title = "موجودی کیف پول کافی نیست"
        warning_message = (
            f"برای ارسال ناتیفیکیشن '{template_name}' موجودی کیف پول کافی نیست.\n\n"
            f"موجودی فعلی: {available_amount:,.0f} {currency_symbol}\n"
            f"مبلغ مورد نیاز: {required_amount:,.0f} {currency_symbol}\n"
            f"کسری: {shortfall:,.0f} {currency_symbol}\n\n"
            f"لطفاً کیف پول خود را شارژ کنید."
        )
        
        # ارسال هشدار به کاربر از طریق In-App Notification
        if user_id and user_id > 0:
            try:
                notification_service = NotificationService(self.db)
                notification_service.send(
                    user_id=user_id,
                    event_key="wallet.insufficient_funds_notification",
                    context={
                        "subject": warning_title,
                        "message": warning_message,
                        "required_amount": float(required_amount),
                        "available_amount": float(available_amount),
                        "shortfall": shortfall,
                        "currency_code": currency_code,
                        "currency_symbol": currency_symbol,
                        "template_name": template_name,
                        "event_type": event_type
                    },
                    preferred_channels=["inapp", "email"]  # اول In-App، سپس Email
                )
            except Exception as e:
                logger.error(f"خطا در ارسال هشدار به کاربر {user_id}: {e}", exc_info=True)
        
        # ثبت لاگ در NotificationSendLog با وضعیت "rejected"
        log = self._create_log(
            business_id=business_id,
            template_id=template_id,
            recipient_type='person',
            recipient_id=person_id,
            recipient_identifier=person.mobile if channel == 'sms' else person.email,
            channel=channel,
            subject=None,
            body=rendered_body,
            context_data=context,
            event_type=event_type,
            triggered_by_user_id=user_id,
            send_result={
                "success": False,
                "error": "INSUFFICIENT_FUNDS",
                "cost": float(required_amount)
            }
        )
        log.status = "rejected"
        log.failure_reason = f"موجودی کافی نیست. مورد نیاز: {required_amount}, موجود: {available_amount}"
        self.db.flush()
        
        # برگرداندن خطا
        return {
            "success": False,
            "error": "INSUFFICIENT_FUNDS",
            "error_message": "موجودی کیف پول کافی نیست",
            "log_id": log.id,
            "details": {
                "required_amount": float(required_amount),
                "available_amount": float(available_amount),
                "shortfall": shortfall,
                "currency_code": currency_code,
                "currency_symbol": currency_symbol,
                "warning_sent": user_id and user_id > 0
            }
        }


