from __future__ import annotations

from typing import Dict, Any, List, Optional, AsyncGenerator
from decimal import Decimal
from datetime import datetime
from sqlalchemy.orm import Session
import json
import logging
import asyncio
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
    
    def get_system_prompt(self, session_business_id: Optional[int] = None) -> str:
        """دریافت system prompt مناسب با business_id"""
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
            return base_prompt + business_info
        
        return base_prompt
    
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
    
    async def chat_completion(
        self,
        messages: List[Dict[str, Any]],
        tools: Optional[List[Dict[str, Any]]] = None,
        use_function_calling: bool = True,
        max_tokens_override: Optional[int] = None,
        session_business_id: Optional[int] = None
    ) -> Dict[str, Any]:
        """
        ارسال درخواست به AI (async version برای جلوگیری از blocking)
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
        
        # اضافه کردن system prompt با business_id از session
        system_prompt = self.get_system_prompt(session_business_id=session_business_id)
        full_messages = [
            {"role": "system", "content": system_prompt},
            *messages
        ]
        
        # دریافت function definitions
        if use_function_calling and tools is None:
            tools = self.get_available_functions(session_business_id=session_business_id)
        
        # ارسال به AI provider در thread pool برای جلوگیری از blocking
        try:
            loop = asyncio.get_event_loop()
            response = await loop.run_in_executor(
                _executor,
                lambda: provider.chat_completion(
                    messages=full_messages,
                    model=self.config.model_name,
                    max_tokens=max_tokens_override or self.config.max_tokens,
                    temperature=float(self.config.temperature),
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
        
        # پردازش function calls اگر وجود دارد
        if response["message"].get("function_calls"):
            function_results = await self.handle_function_calls_async(response["message"]["function_calls"], session_business_id=session_business_id)
            
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
                loop = asyncio.get_event_loop()
                response = await loop.run_in_executor(
                    _executor,
                    lambda: provider.chat_completion(
                        messages=full_messages,
                        model=self.config.model_name,
                        max_tokens=max_tokens_override or self.config.max_tokens,
                        temperature=float(self.config.temperature),
                        tools=None  # دیگر نیازی به tools نیست
                    )
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
    
    async def chat_completion_stream(
        self,
        messages: List[Dict[str, Any]],
        tools: Optional[List[Dict[str, Any]]] = None,
        use_function_calling: bool = True,
        max_tokens_override: Optional[int] = None,
        session_business_id: Optional[int] = None
    ) -> AsyncGenerator[Dict[str, Any], None]:
        """
        ارسال درخواست به AI به صورت streaming
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
        
        # اضافه کردن system prompt با business_id از session
        system_prompt = self.get_system_prompt(session_business_id=session_business_id)
        full_messages = [
            {"role": "system", "content": system_prompt},
            *messages
        ]
        
        # دریافت function definitions
        if use_function_calling and tools is None:
            tools = self.get_available_functions(session_business_id=session_business_id)
        
        # ارسال به AI provider (streaming)
        try:
            accumulated_content = ""
            accumulated_chunks = []
            final_usage = None
            function_calls = None
            
            async for chunk in provider.chat_completion_stream(
                messages=full_messages,
                model=self.config.model_name,
                max_tokens=max_tokens_override or self.config.max_tokens,
                temperature=float(self.config.temperature),
                tools=tools if tools else None
            ):
                accumulated_chunks.append(chunk)
                
                # جمع‌آوری محتوا
                delta = chunk.get("delta", {})
                content_chunk = delta.get("content", "")
                if content_chunk:
                    accumulated_content += content_chunk
                
                # بررسی usage
                if chunk.get("usage"):
                    final_usage = chunk["usage"]
                
                # بررسی function_calls (در chunk نهایی)
                if chunk.get("function_calls"):
                    function_calls = chunk["function_calls"]
                
                # بررسی done
                if chunk.get("done", False):
                    # chunk نهایی را yield نکنیم، چون ممکن است function calls داشته باشد
                    break
                
                # ارسال chunk به client (فقط chunks میانی)
                yield chunk
            
            # بررسی function calls (اگر وجود داشته باشد)
            if function_calls and use_function_calling:
                # پردازش function calls به صورت async
                function_results = await self.handle_function_calls_async(function_calls, session_business_id=session_business_id)
                
                # اضافه کردن نتایج function calls به messages
                function_messages = []
                for call in function_calls:
                    function_name = call.get("name")
                    result = function_results.get(function_name, {})
                    function_messages.append({
                        "role": "tool",
                        "name": function_name,
                        "content": json.dumps(result) if isinstance(result, (dict, list)) else str(result)
                    })
                
                # اضافه کردن پیام function call به messages
                full_messages.append({
                    "role": "assistant",
                    "content": accumulated_content,
                    "function_calls": function_calls
                })
                full_messages.extend(function_messages)
                
                # ارسال مجدد به AI (بدون tools، چون دیگر نیازی نیست)
                # در این مرحله از non-streaming استفاده می‌کنیم برای پاسخ نهایی
                try:
                    loop = asyncio.get_event_loop()
                    response = await loop.run_in_executor(
                        _executor,
                        lambda: provider.chat_completion(
                            messages=full_messages,
                            model=self.config.model_name,
                            max_tokens=max_tokens_override or self.config.max_tokens,
                            temperature=float(self.config.temperature),
                            tools=None  # دیگر نیازی به tools نیست
                        )
                    )
                    
                    # ارسال پاسخ نهایی به صورت streaming (شبیه‌سازی)
                    final_content = response["message"]["content"]
                    if final_content:
                        # ارسال به صورت تدریجی برای تجربه بهتر
                        chunk_size = 50
                        for i in range(0, len(final_content), chunk_size):
                            chunk = final_content[i:i + chunk_size]
                            await asyncio.sleep(0.01)  # کمی تأخیر برای شبیه‌سازی streaming
                            yield {
                                "delta": {
                                    "content": chunk
                                },
                                "usage": None,
                                "done": False
                            }
                    
                    # به‌روزرسانی usage و accumulated_content
                    if response.get("usage"):
                        final_usage = response["usage"]
                    accumulated_content = final_content
                    
                except ApiError:
                    raise
                except Exception as e:
                    logger.error(f"Error in function call retry (streaming): {e}", exc_info=True)
                    raise ApiError(
                        "AI_SERVICE_ERROR",
                        f"خطا در سرویس AI: {str(e)}",
                        http_status=500
                    )
            
            # ارسال chunk نهایی با usage
            yield {
                "delta": {
                    "content": ""
                },
                "usage": final_usage,
                "done": True
            }
            
        except ApiError:
            # خطاهای ApiError را مستقیماً propagate کنیم
            raise
        except Exception as e:
            # خطاهای دیگر را به ApiError تبدیل کنیم
            logger.error(f"Unexpected error in AI streaming service: {e}", exc_info=True)
            raise ApiError(
                "AI_SERVICE_ERROR",
                f"خطا در سرویس AI: {str(e)}",
                http_status=500
            )
    
    def handle_function_calls(
        self,
        function_calls: List[Dict[str, Any]],
        session_business_id: Optional[int] = None
    ) -> Dict[str, Any]:
        """پردازش function calling و برگرداندن نتایج به صورت dictionary (sync version برای backward compatibility)"""
        results = {}
        # استفاده از business_id از session (اولویت) یا از context
        effective_business_id = session_business_id or self.business_id
        context = {
            "db": self.db,
            "user_context": self.ctx,
            "business_id": effective_business_id,
            "session_business_id": session_business_id  # برای validation در handler
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
    
    async def handle_function_calls_async(
        self,
        function_calls: List[Dict[str, Any]],
        session_business_id: Optional[int] = None
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
            arguments = call.get("arguments", {})
            
            try:
                loop = asyncio.get_event_loop()
                result = await loop.run_in_executor(
                    _executor,
                    lambda: registry.call_function(function_name, arguments, context)
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

