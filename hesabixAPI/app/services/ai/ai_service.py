from __future__ import annotations

from typing import Dict, Any, List, Optional, AsyncGenerator
from decimal import Decimal
from datetime import datetime, date
from sqlalchemy.orm import Session
import json
import logging
import asyncio
import time
from concurrent.futures import ThreadPoolExecutor

from app.core.auth_dependency import AuthContext
from app.core.responses import ApiError
from app.services.ai.function_registry import registry, AIRole
from adapters.db.repositories.ai_config_repository import AIConfigRepository
from adapters.db.repositories.ai_subscription_repository import AISubscriptionRepository
from adapters.db.repositories.ai_usage_log_repository import AIUsageLogRepository
from adapters.db.models.ai_usage_log import AIUsageLog, PaymentMethod
from adapters.db.models.ai_subscription import UserAISubscription
from app.services.wallet_service import charge_wallet_for_service
from app.services.ai.prompt_service import get_prompt, PromptRole
from app.services.ai.ai_write_guard import (
    is_write_function,
    build_approval_required_result,
    WRITE_FUNCTION_LABELS_FA,
)
from app.services.ai.ai_tool_keys import (
    status_event,
    tool_label_fa,
    tool_l10n_key,
)
from app.services.ai.ai_trace import (
    context_trace,
    format_planned_tools,
    summarize_tool_result,
    trace_record_from_event,
    trace_step,
)

logger = logging.getLogger(__name__)

# Thread pool executor برای اجرای عملیات blocking
_executor = ThreadPoolExecutor(max_workers=10, thread_name_prefix="ai_service")


class AIService:
    """سرویس اصلی AI با یکپارچه‌سازی کیف پول"""
    
    def __init__(
        self,
        db: Session,
        user_context: AuthContext,
        business_id: Optional[int] = None
    ):
        self.db = db
        self.ctx = user_context
        self.business_id = business_id or user_context.business_id
        self.subscription = self._get_active_subscription()
        self.config = self._get_ai_config()
    
    def _get_active_subscription(self) -> Optional[UserAISubscription]:
        """دریافت اشتراک فعال کاربر"""
        # اگر دسترسی سیستمی ندارد، business_id الزامی است
        # چون کیف پول‌ها فقط business-specific هستند
        if not self.business_id:
            if not (self.ctx.can_access_support_operator() or self.ctx.is_superadmin()):
                logger.warning(
                    f"AIService initialized without business_id for regular user {self.ctx.get_user_id()}. "
                    f"This may cause issues with wallet charging."
                )
            return None
        
        repo = AISubscriptionRepository(self.db)
        return repo.get_active_subscription(
            user_id=self.ctx.get_user_id(),
            business_id=self.business_id
        )
    
    def _get_ai_config(self):
        """دریافت تنظیمات AI"""
        repo = AIConfigRepository(self.db)
        return repo.get_active_config()

    def _use_tools_for_request(self, use_function_calling: bool) -> bool:
        """
        اگر در تنظیمات سراسری function_calling_enabled=False باشد،
        tools به provider ارسال نمی‌شود (مثال: vLLM بدون --enable-auto-tool-choice).
        """
        if not use_function_calling:
            return False
        cfg = self.config
        if cfg is not None and getattr(cfg, "function_calling_enabled", True) is False:
            return False
        return True
    
    def check_availability(
        self,
        estimated_tokens: int = 1000
    ) -> Dict[str, Any]:
        """
        بررسی اینکه آیا کاربر می‌تواند از AI استفاده کند
        (بدون ارسال واقعی پیام - برای چک پیشگیرانه)
        
        Returns:
            {
                "can_use": bool,
                "reason": str | None,
                "details": {
                    "subscription": {...},
                    "wallet": {...},
                    "suggestions": [...]
                }
            }
        """
        # دسترسی‌های سیستمی (اپراتور/سوپرادمین) بدون نیاز به اشتراک
        if self.ctx.can_access_support_operator() or self.ctx.is_superadmin():
            fce = bool(getattr(self.config, "function_calling_enabled", True)) if self.config else True
            return {
                "can_use": True,
                "reason": None,
                "details": {
                    "subscription": {
                        "plan_name": "دسترسی سیستمی",
                        "plan_type": "system",
                        "is_unlimited": True
                    },
                    "function_calling_enabled": fce,
                    "suggestions": []
                }
            }
        
        # بررسی تنظیمات AI
        if not self.config or not self.config.is_active:
            return {
                "can_use": False,
                "reason": "AI_NOT_CONFIGURED",
                "details": {
                    "message": "تنظیمات AI فعال نیست",
                    "suggestions": ["لطفاً با مدیر سیستم تماس بگیرید"]
                }
            }
        
        # بررسی اشتراک
        if not self.subscription:
            from adapters.db.repositories.ai_plan_repository import AIPlanRepository
            plan_repo = AIPlanRepository(self.db)
            available_plans = plan_repo.get_active_plans()
            
            return {
                "can_use": False,
                "reason": "NO_ACTIVE_SUBSCRIPTION",
                "details": {
                    "message": "اشتراک فعالی وجود ندارد",
                    "available_plans": [
                        {
                            "id": p.id,
                            "name": p.name,
                            "plan_type": p.plan_type,
                            "description": p.description
                        }
                        for p in available_plans[:3]  # نمایش ۳ پلن اول
                    ],
                    "suggestions": [
                        "برای استفاده از هوش مصنوعی، ابتدا یک پلن را انتخاب کنید",
                        "پلن رایگان با ۵۰۰۰ توکن در دسترس است"
                    ]
                }
            }
        
        if not self.subscription.is_active:
            return {
                "can_use": False,
                "reason": "SUBSCRIPTION_INACTIVE",
                "details": {
                    "message": "اشتراک غیرفعال است",
                    "subscription": {
                        "plan_name": self.subscription.plan.name if self.subscription.plan else "نامشخص",
                        "expired_at": self.subscription.expires_at.isoformat() if self.subscription.expires_at else None
                    },
                    "suggestions": [
                        "اشتراک شما منقضی شده است",
                        "لطفاً اشتراک خود را تمدید کنید"
                    ]
                }
            }
        
        plan = self.subscription.plan
        if not plan:
            return {
                "can_use": False,
                "reason": "PLAN_NOT_FOUND",
                "details": {
                    "message": "پلن اشتراک یافت نشد",
                    "suggestions": ["لطفاً با پشتیبانی تماس بگیرید"]
                }
            }
        
        # بررسی سهمیه و موجودی
        tokens_used = self.subscription.tokens_used or 0
        tokens_limit = self.subscription.tokens_limit or 0
        tokens_remaining = tokens_limit - tokens_used
        
        subscription_info = {
            "plan_name": plan.name,
            "plan_type": plan.plan_type,
            "tokens_used": tokens_used,
            "tokens_limit": tokens_limit,
            "tokens_remaining": tokens_remaining,
            "usage_percentage": round((tokens_used / tokens_limit * 100) if tokens_limit > 0 else 0, 1)
        }
        
        suggestions = []
        wallet_info = None  # فقط برای pay_as_go / hybrid مقداردهی می‌شود
        
        # بررسی بر اساس نوع پلن
        if plan.plan_type == "free":
            if tokens_remaining < estimated_tokens:
                return {
                    "can_use": False,
                    "reason": "QUOTA_EXCEEDED",
                    "details": {
                        "message": f"سهمیه رایگان تمام شده است. باقیمانده: {tokens_remaining} توکن",
                        "subscription": subscription_info,
                        "suggestions": [
                            f"شما {tokens_used:,} از {tokens_limit:,} توکن رایگان خود را استفاده کرده‌اید",
                            "برای استفاده بیشتر، به پلن پولی ارتقا دهید"
                        ]
                    }
                }
            
            # هشدار اگر کمتر از 20% باقی مانده
            if tokens_remaining < tokens_limit * 0.2:
                suggestions.append(f"⚠️ تنها {tokens_remaining:,} توکن رایگان باقی مانده است")
                suggestions.append("پیشنهاد می‌کنیم به پلن بالاتر ارتقا دهید")
        
        elif plan.plan_type == "subscription":
            if tokens_remaining < estimated_tokens:
                return {
                    "can_use": False,
                    "reason": "QUOTA_EXCEEDED",
                    "details": {
                        "message": f"سهمیه اشتراک تمام شده است. باقیمانده: {tokens_remaining:,} توکن",
                        "subscription": subscription_info,
                        "suggestions": [
                            f"شما {tokens_used:,} از {tokens_limit:,} توکن ماهانه خود را استفاده کرده‌اید",
                            "منتظر تمدید ماهانه بمانید یا به پلن بالاتر ارتقا دهید"
                        ]
                    }
                }
            
            if tokens_remaining < tokens_limit * 0.2:
                suggestions.append(f"⚠️ {tokens_remaining:,} توکن از سهمیه ماهانه شما باقی مانده")
        
        elif plan.plan_type in ["pay_as_go", "hybrid"]:
            # بررسی الزامی بودن business_id چون کیف پول‌ها business-specific هستند
            if not self.business_id:
                return {
                    "can_use": False,
                    "reason": "BUSINESS_REQUIRED",
                    "details": {
                        "message": "برای استفاده از پلن پرداختی، انتخاب کسب‌وکار الزامی است",
                        "suggestions": [
                            "لطفاً ابتدا یک کسب‌وکار را انتخاب کنید",
                            "کیف پول‌ها مختص به هر کسب‌وکار هستند"
                        ]
                    }
                }
            
            # محاسبه هزینه تخمینی
            import json
            pricing_config = json.loads(plan.pricing_config or "{}")
            pay_as_go_config = pricing_config.get("pay_as_go", {})
            
            input_price = Decimal(str(pay_as_go_config.get("price_per_1k_input_tokens", 0))) / 1000
            output_price = Decimal(str(pay_as_go_config.get("price_per_1k_output_tokens", 0))) / 1000
            
            # تخمین: نیمی input و نیمی output
            estimated_cost = (Decimal(estimated_tokens) / 2 * input_price) + \
                           (Decimal(estimated_tokens) / 2 * output_price)
            
            # بررسی موجودی کیف پول
            from app.services.wallet_service import get_wallet_overview
            try:
                wallet = get_wallet_overview(self.db, self.business_id)
                available_balance = Decimal(str(wallet.get("available_balance", 0)))
                
                wallet_info = {
                    "balance": float(available_balance),
                    "estimated_cost": float(estimated_cost),
                    "sufficient": available_balance >= estimated_cost
                }
                
                cur_label = (
                    wallet.get("base_currency_symbol")
                    or wallet.get("base_currency_title")
                    or wallet.get("base_currency_code")
                    or ""
                ).strip()
                cur_suffix = f" {cur_label}" if cur_label else ""

                if available_balance < estimated_cost:
                    return {
                        "can_use": False,
                        "reason": "INSUFFICIENT_FUNDS",
                        "details": {
                            "message": "موجودی کیف پول کافی نیست",
                            "wallet": wallet_info,
                            "subscription": subscription_info,
                            "suggestions": [
                                f"موجودی فعلی: {available_balance:,.0f}{cur_suffix}",
                                f"هزینه تخمینی: {estimated_cost:,.0f}{cur_suffix}",
                                "لطفاً کیف پول خود را شارژ کنید"
                            ]
                        }
                    }
                
                if available_balance < estimated_cost * 10:  # هشدار اگر کمتر از 10 بار استفاده باقی مانده
                    suggestions.append(f"💰 موجودی کیف پول: {available_balance:,.0f}{cur_suffix}")
                    suggestions.append("پیشنهاد می‌کنیم کیف پول خود را شارژ کنید")
                
            except Exception as e:
                logger.warning(f"Error checking wallet balance: {e}")
                # در صورت خطا در دریافت موجودی، اجازه استفاده بده
                wallet_info = {
                    "balance": 0,
                    "estimated_cost": float(estimated_cost),
                    "sufficient": True,  # فرض می‌کنیم کافی است
                    "error": "خطا در دریافت موجودی"
                }
        
        # همه چیز OK است
        fce = bool(getattr(self.config, "function_calling_enabled", True)) if self.config else True
        return {
            "can_use": True,
            "reason": None,
            "details": {
                "subscription": subscription_info,
                "wallet": wallet_info if plan.plan_type in ["pay_as_go", "hybrid"] else None,
                "function_calling_enabled": fce,
                "suggestions": suggestions
            }
        }
    
    @staticmethod
    def _last_user_query(messages: List[Dict[str, Any]]) -> Optional[str]:
        for m in reversed(messages):
            if m.get("role") == "user":
                content = m.get("content")
                if isinstance(content, str) and content.strip():
                    return content.strip()
        return None

    def get_system_prompt(
        self,
        session_business_id: Optional[int] = None,
        session_id: Optional[int] = None,
        user_query: Optional[str] = None,
    ) -> str:
        """دریافت system prompt مناسب با business_id، حافظه، پیوست‌ها و دانشنامه"""
        # تشخیص role کاربر
        if self.ctx.is_superadmin():
            role = PromptRole.ADMIN
        elif self.ctx.can_access_support_operator():
            role = PromptRole.OPERATOR
        else:
            role = PromptRole.USER
        
        # دریافت prompt پایه
        base_prompt = get_prompt(
            db=self.db,
            role=role,
            user_id=self.ctx.get_user_id()
        )
        
        # اضافه کردن business_id به prompt (اگر موجود باشد)
        business_id = session_business_id or self.business_id
        if business_id:
            business_info = f"\n\nکسب‌وکار فعلی: شناسه {business_id}"
            business_info += "\nنکته مهم: شما در حال کار با این کسب‌وکار هستید و نیازی به پرسیدن شناسه کسب‌وکار ندارید."
            business_info += " تمام function calls به صورت خودکار با شناسه کسب‌وکار فعلی انجام می‌شوند."
            insight_text = ""
            try:
                from app.services.ai.ai_insight_service import (
                    get_business_insights,
                    format_insights_for_prompt,
                )

                insights = get_business_insights(self.db, int(business_id), self.ctx)
                insight_text = format_insights_for_prompt(insights)
            except Exception as exc:
                logger.warning("Failed to load AI insights for prompt: %s", exc)

            memory_text = ""
            try:
                from app.services.ai.ai_memory_service import format_memory_for_prompt

                memory_text = format_memory_for_prompt(
                    self.db, int(business_id), self.ctx.get_user_id()
                )
            except Exception as exc:
                logger.warning("Failed to load AI memory for prompt: %s", exc)

            attachment_text = ""
            if session_id:
                try:
                    from app.services.ai.ai_attachment_service import format_attachments_for_prompt

                    attachment_text = format_attachments_for_prompt(self.db, session_id)
                except Exception as exc:
                    logger.warning("Failed to load AI attachments for prompt: %s", exc)

            knowledge_text = ""
            if user_query:
                try:
                    from app.services.ai.ai_knowledge_service import format_knowledge_for_prompt

                    knowledge_text = format_knowledge_for_prompt(
                        self.db, int(business_id), user_query
                    )
                except Exception as exc:
                    logger.warning("Failed to load AI knowledge for prompt: %s", exc)

            connector_text = ""
            try:
                from app.services.ai.ai_connector_service import format_connectors_for_prompt

                connector_text = format_connectors_for_prompt(self.db, int(business_id))
            except Exception as exc:
                logger.warning("Failed to load AI connectors for prompt: %s", exc)

            return (
                base_prompt
                + business_info
                + insight_text
                + memory_text
                + attachment_text
                + knowledge_text
                + connector_text
            )
        
        return base_prompt

    async def build_system_prompt_stream(
        self,
        session_business_id: Optional[int] = None,
        session_id: Optional[int] = None,
        user_query: Optional[str] = None,
    ) -> AsyncGenerator[Dict[str, Any], None]:
        """ساخت system prompt — هر مرحله ابتدا trace فعال، سپس پس از اتمام trace انجام‌شده."""
        loop = asyncio.get_running_loop()

        if self.ctx.is_superadmin():
            role = PromptRole.ADMIN
        elif self.ctx.can_access_support_operator():
            role = PromptRole.OPERATOR
        else:
            role = PromptRole.USER

        yield context_trace("loading_prompt", "active")
        await asyncio.sleep(0)
        base_prompt = await loop.run_in_executor(
            _executor,
            lambda: get_prompt(
                db=self.db,
                role=role,
                user_id=self.ctx.get_user_id(),
            ),
        )
        yield context_trace("loading_prompt", "done")
        await asyncio.sleep(0)

        business_id = session_business_id or self.business_id
        if not business_id:
            yield {"event": "prompt_ready", "prompt": base_prompt}
            return

        business_info = (
            f"\n\nکسب‌وکار فعلی: شناسه {business_id}"
            "\nنکته مهم: شما در حال کار با این کسب‌وکار هستید و نیازی به پرسیدن شناسه کسب‌وکار ندارید."
            " تمام function calls به صورت خودکار با شناسه کسب‌وکار فعلی انجام می‌شوند."
        )

        yield context_trace("loading_insights", "active")
        await asyncio.sleep(0)

        def _load_insights() -> str:
            try:
                from app.services.ai.ai_insight_service import (
                    get_business_insights,
                    format_insights_for_prompt,
                )

                insights = get_business_insights(self.db, int(business_id), self.ctx)
                return format_insights_for_prompt(insights)
            except Exception as exc:
                logger.warning("Failed to load AI insights for prompt: %s", exc)
                return ""

        insight_text = await loop.run_in_executor(_executor, _load_insights)
        yield context_trace("loading_insights", "done")

        yield context_trace("loading_memory", "active")
        await asyncio.sleep(0)

        def _load_memory() -> str:
            try:
                from app.services.ai.ai_memory_service import format_memory_for_prompt

                return format_memory_for_prompt(
                    self.db, int(business_id), self.ctx.get_user_id()
                )
            except Exception as exc:
                logger.warning("Failed to load AI memory for prompt: %s", exc)
                return ""

        memory_text = await loop.run_in_executor(_executor, _load_memory)
        yield context_trace("loading_memory", "done")

        attachment_text = ""
        if session_id:
            yield context_trace("loading_attachments", "active")
            await asyncio.sleep(0)

            def _load_attachments() -> str:
                try:
                    from app.services.ai.ai_attachment_service import (
                        format_attachments_for_prompt,
                    )

                    return format_attachments_for_prompt(self.db, session_id)
                except Exception as exc:
                    logger.warning("Failed to load AI attachments for prompt: %s", exc)
                    return ""

            attachment_text = await loop.run_in_executor(_executor, _load_attachments)
            yield context_trace("loading_attachments", "done")

        knowledge_text = ""
        if user_query:
            yield context_trace("loading_knowledge", "active")
            await asyncio.sleep(0)

            def _load_knowledge() -> str:
                try:
                    from app.services.ai.ai_knowledge_service import format_knowledge_for_prompt

                    return format_knowledge_for_prompt(
                        self.db, int(business_id), user_query
                    )
                except Exception as exc:
                    logger.warning("Failed to load AI knowledge for prompt: %s", exc)
                    return ""

            knowledge_text = await loop.run_in_executor(_executor, _load_knowledge)
            yield context_trace("loading_knowledge", "done")

        yield context_trace("loading_connectors", "active")
        await asyncio.sleep(0)

        def _load_connectors() -> str:
            try:
                from app.services.ai.ai_connector_service import format_connectors_for_prompt

                return format_connectors_for_prompt(self.db, int(business_id))
            except Exception as exc:
                logger.warning("Failed to load AI connectors for prompt: %s", exc)
                return ""

        connector_text = await loop.run_in_executor(_executor, _load_connectors)
        yield context_trace("loading_connectors", "done")

        final_prompt = (
            base_prompt
            + business_info
            + insight_text
            + memory_text
            + attachment_text
            + knowledge_text
            + connector_text
        )
        yield {"event": "prompt_ready", "prompt": final_prompt}
    
    def get_available_functions(self, category: Optional[str] = None, session_business_id: Optional[int] = None) -> List[Dict[str, Any]]:
        """دریافت function های قابل استفاده بر اساس نقش کاربر"""
        # استفاده از business_id از session (اولویت) یا از context
        effective_business_id = session_business_id or self.business_id
        context = {
            "db": self.db,
            "user_context": self.ctx,
            "business_id": effective_business_id,
            "session_business_id": session_business_id  # برای validation در handler
        }
        return registry.get_function_definitions(context, filter_by_category=category)
    
    def check_quota_and_charge(
        self,
        input_tokens: int,
        output_tokens: int
    ) -> Dict[str, Any]:
        """
        بررسی سهمیه و شارژ:
        1. بررسی نوع پلن
        2. محاسبه هزینه
        3. بررسی سهمیه/موجودی
        4. کسر از سهمیه یا کیف پول
        5. ایجاد سند حسابداری (در صورت نیاز)
        """
        # Validation
        if input_tokens < 0 or output_tokens < 0:
            raise ApiError("INVALID_TOKEN_COUNT", "تعداد توکن نمی‌تواند منفی باشد", http_status=400)
        
        # دسترسی‌های سیستمی (اپراتور/سوپرادمین) بدون نیاز به اشتراک
        if self.ctx.can_access_support_operator() or self.ctx.is_superadmin():
            return {
                "payment_method": "free",
                "cost": 0,
                "wallet_transaction_id": None,
                "document_id": None
            }
        
        if not self.subscription:
            from adapters.db.repositories.ai_plan_repository import AIPlanRepository
            plan_repo = AIPlanRepository(self.db)
            available_plans = plan_repo.get_active_plans()
            
            raise ApiError(
                "NO_ACTIVE_SUBSCRIPTION",
                "اشتراک فعالی وجود ندارد. لطفاً یک پلن را انتخاب کنید.",
                http_status=400,
                extra_data={
                    "available_plans": [
                        {"id": p.id, "name": p.name, "plan_type": p.plan_type}
                        for p in available_plans[:3]
                    ],
                    "suggestion": "برای استفاده از هوش مصنوعی، ابتدا یک پلن را از بخش اشتراک انتخاب کنید"
                }
            )
        
        if not self.subscription.is_active:
            raise ApiError(
                "SUBSCRIPTION_INACTIVE",
                "اشتراک شما منقضی شده است. لطفاً اشتراک خود را تمدید کنید.",
                http_status=400,
                extra_data={
                    "expired_at": self.subscription.expires_at.isoformat() if self.subscription.expires_at else None,
                    "plan_name": self.subscription.plan.name if self.subscription.plan else "نامشخص"
                }
            )
        
        plan = self.subscription.plan
        if not plan:
            raise ApiError("PLAN_NOT_FOUND", "پلن اشتراک یافت نشد", http_status=404)
        
        total_tokens = input_tokens + output_tokens
        
        if total_tokens == 0:
            return {"payment_method": "free", "cost": 0, "wallet_transaction_id": None, "document_id": None}
        
        if plan.plan_type == "free":
            # بررسی سهمیه رایگان
            tokens_used = self.subscription.tokens_used or 0
            tokens_limit = self.subscription.tokens_limit or 0
            tokens_remaining = tokens_limit - tokens_used
            
            if tokens_used + total_tokens > tokens_limit:
                raise ApiError(
                    "QUOTA_EXCEEDED",
                    f"سهمیه رایگان تمام شده است. باقیمانده: {tokens_remaining:,} توکن",
                    http_status=400,
                    extra_data={
                        "tokens_used": tokens_used,
                        "tokens_limit": tokens_limit,
                        "tokens_remaining": tokens_remaining,
                        "tokens_required": total_tokens,
                        "suggestion": "برای استفاده بیشتر، به پلن پولی ارتقا دهید"
                    }
                )
            
            # به‌روزرسانی استفاده
            self.subscription.tokens_used += total_tokens
            self.db.commit()
            return {"payment_method": "free", "cost": 0, "wallet_transaction_id": None, "document_id": None}
        
        elif plan.plan_type == "subscription":
            # بررسی سهمیه اشتراک
            tokens_used = self.subscription.tokens_used or 0
            tokens_limit = self.subscription.tokens_limit or 0
            remaining = tokens_limit - tokens_used
            needed = total_tokens
            
            if needed <= remaining:
                # استفاده از سهمیه اشتراک
                self.subscription.tokens_used += needed
                self.db.commit()
                return {"payment_method": "subscription", "cost": 0, "wallet_transaction_id": None, "document_id": None}
            else:
                raise ApiError(
                    "QUOTA_EXCEEDED",
                    f"سهمیه اشتراک تمام شده است. باقیمانده: {remaining:,} توکن",
                    http_status=400,
                    extra_data={
                        "tokens_used": tokens_used,
                        "tokens_limit": tokens_limit,
                        "tokens_remaining": remaining,
                        "tokens_required": needed,
                        "suggestion": "منتظر تمدید ماهانه بمانید یا به پلن بالاتر ارتقا دهید",
                        "renewal_date": self.subscription.expires_at.isoformat() if self.subscription.expires_at else None
                    }
                )
        
        elif plan.plan_type == "pay_as_go":
            # بررسی الزامی بودن business_id چون کیف پول‌ها business-specific هستند
            if not self.business_id:
                raise ApiError(
                    "BUSINESS_REQUIRED",
                    "برای استفاده از پلن پرداخت به ازای مصرف، انتخاب کسب‌وکار الزامی است",
                    http_status=400
                )
            
            # محاسبه هزینه و کسر از کیف پول
            cost = self._calculate_cost(plan, input_tokens, output_tokens)
            return self._charge_from_wallet(cost, input_tokens, output_tokens)
        
        elif plan.plan_type == "hybrid":
            # بررسی الزامی بودن business_id چون کیف پول‌ها business-specific هستند
            if not self.business_id:
                raise ApiError(
                    "BUSINESS_REQUIRED",
                    "برای استفاده از پلن ترکیبی، انتخاب کسب‌وکار الزامی است",
                    http_status=400
                )
            
            # ترکیبی: ابتدا از سهمیه، سپس از کیف پول
            tokens_used = self.subscription.tokens_used or 0
            tokens_limit = self.subscription.tokens_limit or 0
            remaining = tokens_limit - tokens_used
            needed = total_tokens
            
            if needed <= remaining:
                self.subscription.tokens_used += needed
                self.db.commit()
                return {"payment_method": "subscription", "cost": 0, "wallet_transaction_id": None, "document_id": None}
            else:
                # استفاده از سهمیه + پرداخت اضافی
                self.subscription.tokens_used = tokens_limit
                extra_tokens = needed - remaining
                cost = self._calculate_cost(plan, input_tokens, output_tokens, extra_tokens)
                result = self._charge_from_wallet(cost, input_tokens, output_tokens)
                self.db.commit()
                return result
        
        raise ApiError("INVALID_PLAN_TYPE", "نوع پلن نامعتبر است", http_status=400)
    
    def _calculate_cost(
        self,
        plan,
        input_tokens: int,
        output_tokens: int,
        extra_tokens: Optional[int] = None
    ) -> Decimal:
        """محاسبه هزینه بر اساس پلن"""
        import json
        pricing_config = json.loads(plan.pricing_config or "{}")
        pay_as_go_config = pricing_config.get("pay_as_go", {})
        
        input_price = Decimal(str(pay_as_go_config.get("price_per_1k_input_tokens", 0))) / 1000
        output_price = Decimal(str(pay_as_go_config.get("price_per_1k_output_tokens", 0))) / 1000
        
        if extra_tokens:
            # برای hybrid: فقط توکن‌های اضافی محاسبه می‌شود
            return Decimal(extra_tokens) * input_price
        else:
            return (Decimal(input_tokens) * input_price) + (Decimal(output_tokens) * output_price)
    
    def _charge_from_wallet(
        self,
        cost: Decimal,
        input_tokens: int,
        output_tokens: int
    ) -> Dict[str, Any]:
        """کسر از کیف پول و ایجاد سند حسابداری"""
        from app.services.ai.ai_invoice_service import _create_ai_usage_document
        
        # کسر از کیف پول
        wallet_result = charge_wallet_for_service(
            db=self.db,
            business_id=self.business_id,
            amount=cost,
            description=f"هزینه استفاده از AI - {input_tokens} ورودی + {output_tokens} خروجی",
            tx_type="ai_usage",
            allow_negative_balance=False
        )
        
        # ایجاد سند حسابداری
        doc_id = None
        try:
            doc_id = _create_ai_usage_document(
                db=self.db,
                business_id=self.business_id,
                user_id=self.ctx.get_user_id(),
                amount=cost,
                input_tokens=input_tokens,
                output_tokens=output_tokens
            )
            
            # لینک سند به تراکنش کیف پول
            from adapters.db.models.wallet import WalletTransaction
            tx = self.db.query(WalletTransaction).filter(
                WalletTransaction.id == wallet_result["transaction_id"]
            ).first()
            if tx:
                tx.document_id = doc_id
                self.db.flush()
        except Exception as e:
            logger.warning(f"Failed to create accounting document: {e}")
        
        return {
            "payment_method": "wallet",
            "cost": float(cost),
            "wallet_transaction_id": wallet_result["transaction_id"],
            "document_id": doc_id
        }
    
    def log_usage(
        self,
        provider: str,
        model: str,
        input_tokens: int,
        output_tokens: int,
        cost: Decimal,
        payment_method: str,
        wallet_transaction_id: Optional[int] = None,
        document_id: Optional[int] = None,
        context: Optional[Dict[str, Any]] = None
    ):
        """ثبت لاگ استفاده"""
        usage_log = AIUsageLog(
            user_id=self.ctx.get_user_id(),
            business_id=self.business_id,
            subscription_id=self.subscription.id if self.subscription else None,
            provider=provider,
            model=model,
            input_tokens=input_tokens,
            output_tokens=output_tokens,
            cost=float(cost),
            payment_method=PaymentMethod(payment_method),
            wallet_transaction_id=wallet_transaction_id,
            document_id=document_id,
            context=json.dumps(context) if context else None
        )
        self.db.add(usage_log)
        self.db.commit()
        return usage_log

    @staticmethod
    def _validate_messages(messages: List[Dict[str, Any]]) -> None:
        """اعتبارسنجی پیام‌ها — پشتیبانی از tool و assistant با tool_calls."""
        if not messages:
            raise ApiError("MESSAGES_REQUIRED", "حداقل یک پیام الزامی است", http_status=400)
        if not isinstance(messages, list):
            raise ApiError("INVALID_MESSAGES", "messages باید یک لیست باشد", http_status=400)

        for idx, msg in enumerate(messages):
            if not isinstance(msg, dict):
                raise ApiError(
                    "INVALID_MESSAGE_FORMAT",
                    f"پیام {idx} باید یک dictionary باشد",
                    http_status=400,
                )
            if "role" not in msg:
                raise ApiError(
                    "INVALID_MESSAGE_FORMAT",
                    f"پیام {idx} باید role داشته باشد",
                    http_status=400,
                )
            role = msg.get("role")
            if role == "tool":
                if not msg.get("tool_call_id"):
                    raise ApiError(
                        "INVALID_MESSAGE_FORMAT",
                        f"پیام tool {idx} باید tool_call_id داشته باشد",
                        http_status=400,
                    )
                continue
            if role == "assistant" and msg.get("tool_calls"):
                continue
            if "content" not in msg:
                raise ApiError(
                    "INVALID_MESSAGE_FORMAT",
                    f"پیام {idx} باید content داشته باشد",
                    http_status=400,
                )
    
    async def chat_completion(
        self,
        messages: List[Dict[str, Any]],
        tools: Optional[List[Dict[str, Any]]] = None,
        use_function_calling: bool = True,
        max_tokens_override: Optional[int] = None,
        temperature_override: Optional[float] = None,
        session_business_id: Optional[int] = None,
        session_id: Optional[int] = None,
        max_iterations: int = 10,
        approve_writes: bool = False,
        user_query: Optional[str] = None,
    ) -> Dict[str, Any]:
        """
        ارسال درخواست به AI (async version برای جلوگیری از blocking)
        """
        self._validate_messages(messages)
        effective_user_query = user_query or self._last_user_query(messages)

        accumulated_function_calls: List[Dict[str, Any]] = []
        accumulated_function_results: Dict[str, Any] = {}
        
        if not self.config or not self.config.is_active:
            raise ApiError("AI_NOT_CONFIGURED", "تنظیمات AI فعال نیست", http_status=400)
        
        # رمزگشایی API Key
        from app.services.ai.encryption import decrypt_api_key
        api_key = decrypt_api_key(self.config.api_key) if self.config.api_key else None
        
        if not api_key:
            raise ApiError("API_KEY_NOT_SET", "API Key تنظیم نشده است", http_status=400)
        
        # ایجاد provider
        from app.services.ai.ai_provider import create_provider
        provider = create_provider(
            provider_type=self.config.provider,
            api_key=api_key,
            api_base_url=self.config.api_base_url
        )
        
        # اضافه کردن system prompt با business_id از session
        system_prompt = self.get_system_prompt(
            session_business_id=session_business_id,
            session_id=session_id,
            user_query=effective_user_query,
        )
        full_messages = [
            {"role": "system", "content": system_prompt},
            *messages
        ]
        
        eff_tools = self._use_tools_for_request(use_function_calling)
        if eff_tools and tools is None:
            tools = self.get_available_functions(session_business_id=session_business_id)
        elif not eff_tools:
            tools = None
        
        try:
            loop = asyncio.get_event_loop()
            response = await loop.run_in_executor(
                _executor,
                lambda: provider.chat_completion(
                messages=full_messages,
                model=self.config.model_name,
                max_tokens=max_tokens_override or self.config.max_tokens,
                temperature=float(temperature_override if temperature_override is not None else self.config.temperature),
                tools=tools if tools else None
                )
            )
        except ApiError:
            # خطاهای ApiError را مستقیماً propagate کنیم
            raise
        except Exception as e:
            # خطاهای دیگر را به ApiError تبدیل کنیم
            logger.error(f"Unexpected error in AI service: {e}", exc_info=True)
            raise ApiError(
                "AI_SERVICE_ERROR",
                f"خطا در سرویس AI: {str(e)}",
                http_status=500
            )
        
        # پردازش function calls در یک حلقه (multi-round agent)
        iteration = 0
        while eff_tools and response["message"].get("function_calls") and iteration < max_iterations:
            iteration += 1
            current_calls = response["message"]["function_calls"]
            accumulated_function_calls.extend(current_calls)

            function_results = await self.handle_function_calls_async(
                current_calls,
                session_business_id=session_business_id,
                approve_writes=approve_writes,
            )
            accumulated_function_results.update(function_results)
            
            # ایجاد assistant message با tool_calls برای OpenAI API
            assistant_msg = {
                "role": "assistant",
                "content": response["message"].get("content", None),
                "tool_calls": []
            }
            
            # ساخت tool_calls به فرمت OpenAI
            tool_call_ids = {}
            for idx, call in enumerate(response["message"]["function_calls"]):
                tool_call_id = call.get("id") or f"call_{iteration}_{idx}_{call.get('name', 'unknown')}"
                tool_call_ids[call.get("name")] = tool_call_id
                assistant_msg["tool_calls"].append({
                    "id": tool_call_id,
                    "type": "function",
                    "function": {
                        "name": call.get("name"),
                        "arguments": json.dumps(call.get("arguments", {}), ensure_ascii=False)
                    }
                })
            
            if assistant_msg["content"] is None:
                del assistant_msg["content"]
            
            full_messages.append(assistant_msg)
            
            function_messages = []
            for call in response["message"]["function_calls"]:
                function_name = call.get("name")
                result = function_results.get(function_name, {})
                serialized_result = self._serialize_for_json(result)
                tool_call_id = call.get("id") or tool_call_ids.get(function_name, f"call_{function_name}")
                function_messages.append({
                    "role": "tool",
                    "tool_call_id": tool_call_id,
                    "content": json.dumps(serialized_result, ensure_ascii=False) if isinstance(serialized_result, (dict, list)) else str(serialized_result)
                })
            
            full_messages.extend(function_messages)
            try:
                loop = asyncio.get_event_loop()
                response = await loop.run_in_executor(
                    _executor,
                    lambda msgs=full_messages, t=tools: provider.chat_completion(
                        messages=msgs,
                        model=self.config.model_name,
                        max_tokens=max_tokens_override or self.config.max_tokens,
                        temperature=float(temperature_override if temperature_override is not None else self.config.temperature),
                        tools=t if eff_tools else None,
                    ),
                )
            except ApiError:
                raise
            except Exception as e:
                logger.error(f"Unexpected error in AI service (function call iteration {iteration}): {e}", exc_info=True)
                raise ApiError(
                    "AI_SERVICE_ERROR",
                    f"خطا در سرویس AI: {str(e)}",
                    http_status=500
                )

        if accumulated_function_calls:
            response["_function_calls"] = accumulated_function_calls
            response["_function_results"] = accumulated_function_results
        
        return response
    
    def chat_completion_sync(
        self,
        messages: List[Dict[str, Any]],
        tools: Optional[List[Dict[str, Any]]] = None,
        use_function_calling: bool = True,
        max_tokens_override: Optional[int] = None,
        temperature_override: Optional[float] = None,
        session_business_id: Optional[int] = None,
        max_iterations: int = 10
    ) -> Dict[str, Any]:
        """
        نسخه sync برای استفاده در workflow engine
        از asyncio.run برای اجرای chat_completion استفاده می‌کند
        """
        def _run():
            return asyncio.run(
                self.chat_completion(
                    messages=messages,
                    tools=tools,
                    use_function_calling=use_function_calling,
                    max_tokens_override=max_tokens_override,
                    temperature_override=temperature_override,
                    session_business_id=session_business_id,
                    max_iterations=max_iterations
                )
            )

        try:
            asyncio.get_running_loop()
            # در context async هستیم - اجرا در thread جدید
            import concurrent.futures
            with concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
                return pool.submit(_run).result()
        except RuntimeError:
            return _run()
    
    async def chat_completion_stream(
        self,
        messages: List[Dict[str, Any]],
        tools: Optional[List[Dict[str, Any]]] = None,
        use_function_calling: bool = True,
        max_tokens_override: Optional[int] = None,
        session_business_id: Optional[int] = None,
        session_id: Optional[int] = None,
        approve_writes: bool = False,
        max_iterations: int = 8,
        user_query: Optional[str] = None,
    ) -> AsyncGenerator[Dict[str, Any], None]:
        """ارسال streaming با چند نوبت tool calling (مثل chat_completion)."""
        self._validate_messages(messages)
        effective_user_query = user_query or self._last_user_query(messages)

        accumulated_function_calls: List[Dict[str, Any]] = []
        accumulated_function_results: Dict[str, Any] = {}

        if not self.config or not self.config.is_active:
            raise ApiError("AI_NOT_CONFIGURED", "تنظیمات AI فعال نیست", http_status=400)

        from app.services.ai.encryption import decrypt_api_key

        api_key = decrypt_api_key(self.config.api_key) if self.config.api_key else None
        if not api_key:
            raise ApiError("API_KEY_NOT_SET", "API Key تنظیم نشده است", http_status=400)

        from app.services.ai.ai_provider import create_provider

        provider = create_provider(
            provider_type=self.config.provider,
            api_key=api_key,
            api_base_url=self.config.api_base_url,
        )

        try:
            accumulated_content = ""
            final_usage = None
            iteration = 0
            trace_steps: List[Dict[str, Any]] = []
            trace_step_counter = 0

            def _ingest_trace_event(event: Dict[str, Any]) -> Dict[str, Any]:
                record = trace_record_from_event(event)
                sid = record.get("step_id")
                if sid:
                    for i, existing in enumerate(trace_steps):
                        if existing.get("step_id") == sid:
                            trace_steps[i] = record
                            break
                    else:
                        trace_steps.append(record)
                return event

            def _emit_trace(*, step_id: Optional[str] = None, **kwargs: Any) -> Dict[str, Any]:
                nonlocal trace_step_counter
                if step_id is None:
                    trace_step_counter += 1
                    sid = str(trace_step_counter)
                else:
                    sid = step_id
                kind = kwargs.pop("kind")
                state = kwargs.pop("state", "done")
                return _ingest_trace_event(trace_step(sid, kind, state, **kwargs))

            yield status_event("thinking")
            yield _emit_trace(
                step_id="ctx_thinking",
                kind="context",
                state="active",
                title_key="aiStatusThinking",
            )

            system_prompt = ""
            async for build_item in self.build_system_prompt_stream(
                session_business_id=session_business_id,
                session_id=session_id,
                user_query=effective_user_query,
            ):
                if build_item.get("event") == "prompt_ready":
                    system_prompt = build_item.get("prompt") or ""
                    continue
                if build_item.get("event") == "trace_step":
                    yield _ingest_trace_event(build_item)
                    await asyncio.sleep(0)
                    continue
                yield build_item

            yield _emit_trace(
                step_id="ctx_thinking",
                kind="context",
                state="done",
                title_key="aiStatusThinking",
            )

            full_messages: List[Dict[str, Any]] = [
                {"role": "system", "content": system_prompt},
                *messages,
            ]

            eff_tools = self._use_tools_for_request(use_function_calling)
            if eff_tools and tools is None:
                tools = self.get_available_functions(
                    session_business_id=session_business_id
                )
            elif not eff_tools:
                tools = None

            while iteration < max_iterations:
                iteration += 1
                function_calls = None
                tool_call_id_map: Dict[str, str] = {}
                round_text = ""
                use_tools = bool(eff_tools and tools)
                writing_status_sent = False

                if iteration > 1:
                    yield _emit_trace(
                        step_id=f"plan_next_{iteration}",
                        kind="plan_next",
                        state="active",
                        title_key="aiTracePlanningNext",
                        iteration=iteration,
                    )

                llm_step_id = f"llm_{iteration}"
                yield _emit_trace(
                    step_id=llm_step_id,
                    kind="context",
                    state="active",
                    title_key="aiStatusThinking",
                    iteration=iteration,
                )
                narrative_step_id = f"narrative_{iteration}"
                narrative_started = False
                last_narrative_emit = 0.0

                async for chunk in provider.chat_completion_stream(
                    messages=full_messages,
                    model=self.config.model_name,
                    max_tokens=max_tokens_override or self.config.max_tokens,
                    temperature=float(self.config.temperature),
                    tools=tools if use_tools else None,
                ):
                    if chunk.get("usage"):
                        final_usage = chunk["usage"]
                    if chunk.get("function_calls"):
                        function_calls = chunk["function_calls"]
                        tool_call_id_map = chunk.get("tool_call_id_map", {}) or {}

                    delta = chunk.get("delta", {})
                    content_chunk = delta.get("content", "")
                    if content_chunk:
                        round_text += content_chunk
                        if not function_calls:
                            if not writing_status_sent:
                                writing_status_sent = True
                                yield status_event("writing")
                                yield _emit_trace(
                                    step_id=llm_step_id,
                                    kind="context",
                                    state="done",
                                    title_key="aiStatusThinking",
                                    iteration=iteration,
                                )
                            if round_text.strip():
                                if not narrative_started:
                                    narrative_started = True
                                now_mono = time.monotonic()
                                if (
                                    now_mono - last_narrative_emit >= 0.06
                                    or len(content_chunk) > 80
                                ):
                                    last_narrative_emit = now_mono
                                    yield _emit_trace(
                                        step_id=narrative_step_id,
                                        kind="narrative",
                                        state="active",
                                        body_markdown=round_text,
                                        iteration=iteration,
                                    )
                                    await asyncio.sleep(0)
                            yield {
                                "delta": {"content": content_chunk},
                                "usage": None,
                                "done": False,
                            }

                    if chunk.get("done", False):
                        break

                if narrative_started and round_text.strip():
                    yield _emit_trace(
                        step_id=narrative_step_id,
                        kind="narrative",
                        state="done",
                        body_markdown=round_text.strip(),
                        iteration=iteration,
                    )
                elif not narrative_started:
                    yield _emit_trace(
                        step_id=llm_step_id,
                        kind="context",
                        state="done",
                        title_key="aiStatusThinking",
                        iteration=iteration,
                    )

                if iteration > 1:
                    yield _emit_trace(
                        step_id=f"plan_next_{iteration}",
                        kind="plan_next",
                        state="done",
                        title_key="aiTracePlanningNext",
                        iteration=iteration,
                    )

                if function_calls and use_tools:
                    accumulated_function_calls.extend(function_calls)
                    yield status_event("planning_tools")

                    if narrative_started:
                        yield _emit_trace(
                            step_id=narrative_step_id,
                            kind="narrative",
                            state="done",
                            body_markdown=round_text.strip(),
                            iteration=iteration,
                        )
                    elif round_text.strip():
                        yield _emit_trace(
                            step_id=f"narrative_{iteration}",
                            kind="narrative",
                            state="done",
                            body_markdown=round_text.strip(),
                            iteration=iteration,
                        )
                    else:
                        yield _emit_trace(
                            step_id=f"plan_{iteration}",
                            kind="plan",
                            state="done",
                            title_key="aiTracePlanningAction",
                            body_markdown=format_planned_tools(function_calls),
                            iteration=iteration,
                        )

                    for call in function_calls:
                        fname = call.get("name", "unknown")
                        label = tool_label_fa(fname)
                        tool_step_id = f"tool_{iteration}_{fname}"
                        yield _emit_trace(
                            step_id=tool_step_id,
                            kind="tool",
                            state="active",
                            title_key="aiTraceRunningTool",
                            title_params={"toolName": label},
                            tool=fname,
                            tool_key=tool_l10n_key(fname),
                            iteration=iteration,
                        )
                        yield {
                            "event": "tool_start",
                            "tool": fname,
                            "tool_key": tool_l10n_key(fname),
                            "label": label,
                        }

                    function_results = await self.handle_function_calls_async(
                        function_calls,
                        session_business_id=session_business_id,
                        approve_writes=approve_writes,
                    )
                    accumulated_function_results.update(function_results)

                    for call in function_calls:
                        fname = call.get("name", "unknown")
                        tool_step_id = f"tool_{iteration}_{fname}"
                        result = function_results.get(fname, {})
                        needs_approval = (
                            isinstance(result, dict)
                            and result.get("error") == "APPROVAL_REQUIRED"
                        )
                        success = not (
                            isinstance(result, dict) and result.get("error")
                        )
                        yield {
                            "event": "tool_end",
                            "tool": fname,
                            "tool_key": tool_l10n_key(fname),
                            "label": tool_label_fa(fname),
                            "success": success,
                            "approval_required": needs_approval,
                        }
                        yield _emit_trace(
                            step_id=tool_step_id,
                            kind="tool",
                            state="done" if success else "error",
                            title_key="aiTraceRunningTool",
                            title_params={"toolName": tool_label_fa(fname)},
                            tool=fname,
                            tool_key=tool_l10n_key(fname),
                            iteration=iteration,
                        )
                        yield _emit_trace(
                            step_id=f"obs_{iteration}_{fname}",
                            kind="observation",
                            state="done" if success else "error",
                            title_key="aiTraceObservation",
                            title_params={"toolName": tool_label_fa(fname)},
                            body_markdown=summarize_tool_result(fname, result),
                            tool=fname,
                            tool_key=tool_l10n_key(fname),
                            iteration=iteration,
                        )

                    assistant_msg: Dict[str, Any] = {
                        "role": "assistant",
                        "tool_calls": [],
                    }
                    if round_text:
                        assistant_msg["content"] = round_text

                    for call in function_calls:
                        tc_id = call.get("id") or f"call_{call.get('name', 'unknown')}"
                        assistant_msg["tool_calls"].append(
                            {
                                "id": tc_id,
                                "type": "function",
                                "function": {
                                    "name": call.get("name"),
                                    "arguments": json.dumps(
                                        call.get("arguments", {}),
                                        ensure_ascii=False,
                                    ),
                                },
                            }
                        )
                    if not assistant_msg.get("content"):
                        assistant_msg.pop("content", None)

                    full_messages.append(assistant_msg)

                    for call in function_calls:
                        function_name = call.get("name")
                        result = function_results.get(function_name, {})
                        serialized = self._serialize_for_json(result)
                        tc_id = (
                            call.get("id")
                            or tool_call_id_map.get(function_name, f"call_{function_name}")
                        )
                        full_messages.append(
                            {
                                "role": "tool",
                                "tool_call_id": tc_id,
                                "content": (
                                    json.dumps(serialized, ensure_ascii=False)
                                    if isinstance(serialized, (dict, list))
                                    else str(serialized)
                                ),
                            }
                        )
                    continue

                if round_text.strip():
                    yield _emit_trace(
                        kind="answer",
                        state="done",
                        title_key="aiTraceComposingAnswer",
                        body_markdown=round_text.strip()
                        if len(round_text.strip()) < 400
                        else None,
                        iteration=iteration,
                    )
                accumulated_content = round_text
                break

            yield {
                "delta": {"content": ""},
                "usage": final_usage,
                "done": True,
                "function_calls": accumulated_function_calls or None,
                "function_results": accumulated_function_results or None,
                "agent_trace": trace_steps or None,
            }

        except ApiError:
            raise
        except Exception as e:
            logger.error(f"Unexpected error in AI streaming service: {e}", exc_info=True)
            raise ApiError(
                "AI_SERVICE_ERROR",
                f"خطا در سرویس AI: {str(e)}",
                http_status=500,
            )
    
    def handle_function_calls(
        self,
        function_calls: List[Dict[str, Any]],
        session_business_id: Optional[int] = None,
        approve_writes: bool = False,
    ) -> Dict[str, Any]:
        """پردازش function calling (sync — سازگاری با گذشته)"""
        results = {}
        effective_business_id = session_business_id or self.business_id
        context = {
            "db": self.db,
            "user_context": self.ctx,
            "business_id": effective_business_id,
            "session_business_id": session_business_id,
        }

        for call in function_calls:
            function_name = call.get("name")
            arguments = call.get("arguments", {}) or {}

            if is_write_function(function_name) and not approve_writes:
                results[function_name] = build_approval_required_result(
                    function_name, arguments
                )
                continue

            try:
                result = registry.call_function(function_name, arguments, context)
                results[function_name] = result
            except Exception as e:
                logger.error(f"Error calling function {function_name}: {e}", exc_info=True)
                results[function_name] = {"error": str(e)}

        return results

    async def handle_function_calls_async(
        self,
        function_calls: List[Dict[str, Any]],
        session_business_id: Optional[int] = None,
        approve_writes: bool = False,
    ) -> Dict[str, Any]:
        """پردازش function calling به صورت async برای جلوگیری از blocking"""
        # استفاده از business_id از session (اولویت) یا از context
        effective_business_id = session_business_id or self.business_id
        context = {
            "db": self.db,
            "user_context": self.ctx,
            "business_id": effective_business_id,
            "session_business_id": session_business_id  # برای validation در handler
        }
        
        # اجرای function calls در thread pool برای جلوگیری از blocking
        async def call_single_function(call: Dict[str, Any]) -> tuple[str, Any]:
            function_name = call.get("name")
            arguments = call.get("arguments", {}) or {}

            if is_write_function(function_name) and not approve_writes:
                return function_name, build_approval_required_result(function_name, arguments)
            
            try:
                loop = asyncio.get_event_loop()
                result = await loop.run_in_executor(
                    _executor,
                    lambda fn=function_name, args=arguments: registry.call_function(fn, args, context),
                )
                return function_name, result
            except Exception as e:
                logger.error(f"Error calling function {function_name}: {e}", exc_info=True)
                return function_name, {"error": str(e)}
        
        # اجرای تمام function calls به صورت concurrent (اگر ممکن باشد)
        tasks = [call_single_function(call) for call in function_calls]
        results_list = await asyncio.gather(*tasks)
        
        # تبدیل به dictionary
        results = {name: result for name, result in results_list}
        return results
    
    def _serialize_for_json(self, obj: Any) -> Any:
        """تبدیل datetime, date و سایر objects به JSON-serializable format"""
        if isinstance(obj, dict):
            return {key: self._serialize_for_json(value) for key, value in obj.items()}
        elif isinstance(obj, list):
            return [self._serialize_for_json(item) for item in obj]
        elif isinstance(obj, datetime):
            return obj.isoformat()
        elif isinstance(obj, date):
            return obj.isoformat()
        elif isinstance(obj, Decimal):
            # تبدیل Decimal به float برای JSON serialization
            return float(obj)
        elif hasattr(obj, '__dict__'):
            # برای objects دیگر، تلاش می‌کنیم attributes را تبدیل کنیم
            try:
                return self._serialize_for_json(obj.__dict__)
            except:
                return str(obj)
        else:
            return obj
    
    async def generate_chat_title(self, user_message: str) -> Optional[str]:
        """
        تولید عنوان کوتاه و هوشمند برای گفت‌وگو بر اساس اولین پیام کاربر (async version)
        """
        try:
            response = await self.chat_completion(
                messages=[
                    {
                        "role": "system",
                        "content": (
                            "شما باید برای گفت‌وگو یک عنوان بسیار کوتاه (حداکثر 5 کلمه) "
                            "و شفاف انتخاب کنید. از علائم نگارشی اضافه و گیومه استفاده نکنید."
                        )
                    },
                    {
                        "role": "user",
                        "content": f"درخواست کاربر: {user_message}\nفقط عنوان کوتاه تولید کن."
                    },
                ],
                tools=None,
                use_function_calling=False,
                max_tokens_override=48,
            )
            title = response["message"]["content"].strip()
            if len(title) > 80:
                title = title[:80]
            return title
        except Exception as exc:
            logger.warning(f"Failed to generate chat title: {exc}")
            return None

