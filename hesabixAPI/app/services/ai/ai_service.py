from __future__ import annotations

from typing import Dict, Any, List, Optional
from decimal import Decimal
from datetime import datetime
from sqlalchemy.orm import Session
import json
import logging

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

logger = logging.getLogger(__name__)


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
        if not self.business_id:
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
    
    def get_system_prompt(self) -> str:
        """دریافت system prompt مناسب"""
        # تشخیص role کاربر
        if self.ctx.is_superadmin():
            role = PromptRole.ADMIN
        elif self.ctx.can_access_support_operator():
            role = PromptRole.OPERATOR
        else:
            role = PromptRole.USER
        
        # دریافت prompt
        return get_prompt(
            db=self.db,
            role=role,
            user_id=self.ctx.get_user_id()
        )
    
    def get_available_functions(self, category: Optional[str] = None) -> List[Dict[str, Any]]:
        """دریافت function های قابل استفاده بر اساس نقش کاربر"""
        context = {
            "db": self.db,
            "user_context": self.ctx,
            "business_id": self.business_id
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
            raise ApiError("NO_ACTIVE_SUBSCRIPTION", "اشتراک فعالی وجود ندارد", http_status=400)
        
        if not self.subscription.is_active:
            raise ApiError("SUBSCRIPTION_INACTIVE", "اشتراک غیرفعال است", http_status=400)
        
        plan = self.subscription.plan
        if not plan:
            raise ApiError("PLAN_NOT_FOUND", "پلن اشتراک یافت نشد", http_status=404)
        
        total_tokens = input_tokens + output_tokens
        
        if total_tokens == 0:
            return {"payment_method": "free", "cost": 0, "wallet_transaction_id": None, "document_id": None}
        
        if plan.plan_type == "free":
            # بررسی سهمیه رایگان
            if self.subscription.tokens_used + total_tokens > (self.subscription.tokens_limit or 0):
                raise ApiError("QUOTA_EXCEEDED", "سهمیه رایگان تمام شده است", http_status=400)
            
            # به‌روزرسانی استفاده
            self.subscription.tokens_used += total_tokens
            self.db.commit()
            return {"payment_method": "free", "cost": 0, "wallet_transaction_id": None, "document_id": None}
        
        elif plan.plan_type == "subscription":
            # بررسی سهمیه اشتراک
            remaining = (self.subscription.tokens_limit or 0) - self.subscription.tokens_used
            needed = total_tokens
            
            if needed <= remaining:
                # استفاده از سهمیه اشتراک
                self.subscription.tokens_used += needed
                self.db.commit()
                return {"payment_method": "subscription", "cost": 0, "wallet_transaction_id": None, "document_id": None}
            else:
                # اگر hybrid و از سهمیه بیشتر استفاده شد
                if plan.plan_type == "hybrid":
                    extra_tokens = needed - remaining
                    cost = self._calculate_cost(plan, input_tokens, output_tokens, extra_tokens)
                    return self._charge_from_wallet(cost, input_tokens, output_tokens)
                else:
                    raise ApiError("QUOTA_EXCEEDED", "سهمیه اشتراک تمام شده است", http_status=400)
        
        elif plan.plan_type == "pay_as_go":
            # محاسبه هزینه و کسر از کیف پول
            cost = self._calculate_cost(plan, input_tokens, output_tokens)
            return self._charge_from_wallet(cost, input_tokens, output_tokens)
        
        elif plan.plan_type == "hybrid":
            # ترکیبی: ابتدا از سهمیه، سپس از کیف پول
            remaining = (self.subscription.tokens_limit or 0) - self.subscription.tokens_used
            needed = total_tokens
            
            if needed <= remaining:
                self.subscription.tokens_used += needed
                self.db.commit()
                return {"payment_method": "subscription", "cost": 0, "wallet_transaction_id": None, "document_id": None}
            else:
                # استفاده از سهمیه + پرداخت اضافی
                self.subscription.tokens_used = self.subscription.tokens_limit or 0
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
    
    def chat_completion(
        self,
        messages: List[Dict[str, Any]],
        tools: Optional[List[Dict[str, Any]]] = None,
        use_function_calling: bool = True
    ) -> Dict[str, Any]:
        """
        ارسال درخواست به AI
        """
        # Validation
        if not messages:
            raise ApiError("MESSAGES_REQUIRED", "حداقل یک پیام الزامی است", http_status=400)
        
        if not isinstance(messages, list):
            raise ApiError("INVALID_MESSAGES", "messages باید یک لیست باشد", http_status=400)
        
        # بررسی ساختار messages
        for idx, msg in enumerate(messages):
            if not isinstance(msg, dict):
                raise ApiError("INVALID_MESSAGE_FORMAT", f"پیام {idx} باید یک dictionary باشد", http_status=400)
            if "role" not in msg or "content" not in msg:
                raise ApiError("INVALID_MESSAGE_FORMAT", f"پیام {idx} باید role و content داشته باشد", http_status=400)
        
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
        
        # اضافه کردن system prompt
        system_prompt = self.get_system_prompt()
        full_messages = [
            {"role": "system", "content": system_prompt},
            *messages
        ]
        
        # دریافت function definitions
        if use_function_calling and tools is None:
            tools = self.get_available_functions()
        
        # ارسال به AI provider
        try:
            response = provider.chat_completion(
                messages=full_messages,
                model=self.config.model_name,
                max_tokens=self.config.max_tokens,
                temperature=float(self.config.temperature),
                tools=tools if tools else None
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
        
        # پردازش function calls اگر وجود دارد
        if response["message"].get("function_calls"):
            function_results = self.handle_function_calls(response["message"]["function_calls"])
            
            # اضافه کردن نتایج function calls به messages و ارسال مجدد
            function_messages = []
            for call in response["message"]["function_calls"]:
                function_name = call.get("name")
                result = function_results.get(function_name, {})
                function_messages.append({
                    "role": "tool",
                    "name": function_name,
                    "content": json.dumps(result) if isinstance(result, (dict, list)) else str(result)
                })
            
            # ارسال مجدد با نتایج function calls
            full_messages.extend(function_messages)
            try:
                response = provider.chat_completion(
                    messages=full_messages,
                    model=self.config.model_name,
                    max_tokens=self.config.max_tokens,
                    temperature=float(self.config.temperature),
                    tools=None  # دیگر نیازی به tools نیست
                )
            except ApiError:
                raise
            except Exception as e:
                logger.error(f"Unexpected error in AI service (function call retry): {e}", exc_info=True)
                raise ApiError(
                    "AI_SERVICE_ERROR",
                    f"خطا در سرویس AI: {str(e)}",
                    http_status=500
                )
        
        return response
    
    def handle_function_calls(
        self,
        function_calls: List[Dict[str, Any]]
    ) -> Dict[str, Any]:
        """پردازش function calling و برگرداندن نتایج به صورت dictionary"""
        results = {}
        context = {
            "db": self.db,
            "user_context": self.ctx,
            "business_id": self.business_id
        }
        
        for call in function_calls:
            function_name = call.get("name")
            arguments = call.get("arguments", {})
            
            try:
                result = registry.call_function(function_name, arguments, context)
                results[function_name] = result
            except Exception as e:
                logger.error(f"Error calling function {function_name}: {e}", exc_info=True)
                results[function_name] = {"error": str(e)}
        
        return results

