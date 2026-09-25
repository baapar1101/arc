"""شارژ سهمیه و ثبت مصرف — استخراج تدریجی از AIService (ARC-01)."""
from __future__ import annotations

import json
import logging
from decimal import Decimal
from typing import Any, Dict, Optional

from adapters.db.models.ai_usage_log import AIUsageLog, PaymentMethod
from app.core.responses import ApiError
from app.services.ai.ai_ops_metrics import log_ai_event
from app.services.wallet_service import charge_wallet_for_service

logger = logging.getLogger(__name__)


class AIUsageMeterMixin:
    """متدهای quota/charge/log روی AIService می‌مانند؛ بدنه اینجاست."""

    def _lock_subscription_for_update(self) -> None:
        """قفل ردیف اشتراک برای به‌روزرسانی اتمی tokens_used."""
        if not self.subscription or not self.subscription.id:
            return
        from adapters.db.repositories.ai_subscription_repository import AISubscriptionRepository

        repo = AISubscriptionRepository(self.db)
        locked = repo.get_by_id_for_update(int(self.subscription.id))
        if locked is not None:
            self.subscription = locked

    def _charge_and_log_usage(
        self,
        *,
        input_tokens: int,
        output_tokens: int,
        usage: Optional[Dict[str, Any]] = None,
        model_code: Optional[str] = None,
    ) -> Dict[str, Any]:
        """شارژ سهمیه/کیف پول و ثبت لاگ استفاده در یک فراخوانی."""
        effective_model = model_code or self.get_effective_model_code()
        charge_result = self.check_quota_and_charge(
            input_tokens,
            output_tokens,
            model_code=effective_model,
        )
        try:
            provider_name = self.get_effective_provider_type()
        except Exception:
            provider_name = self.config.provider if self.config else "openai"
        self.log_usage(
            provider=provider_name,
            model=effective_model,
            input_tokens=input_tokens,
            output_tokens=output_tokens,
            cost=charge_result.get("cost", 0),
            payment_method=charge_result.get("payment_method", "free"),
            wallet_transaction_id=charge_result.get("wallet_transaction_id"),
            document_id=charge_result.get("document_id"),
            context=None if usage is None else {
                "source": "aux_metered_call",
                **{k: v for k, v in (usage or {}).items() if isinstance(v, (int, float, str))},
            },
        )
        return charge_result

    def check_quota_and_charge(
        self,
        input_tokens: int,
        output_tokens: int,
        model_code: Optional[str] = None,
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
                details={
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
                details={
                    "expired_at": self.subscription.expires_at.isoformat() if self.subscription.expires_at else None,
                    "plan_name": self.subscription.plan.name if self.subscription.plan else "نامشخص"
                }
            )

        self._lock_subscription_for_update()
        if not self.subscription.is_active:
            raise ApiError(
                "SUBSCRIPTION_INACTIVE",
                "اشتراک شما منقضی شده است. لطفاً اشتراک خود را تمدید کنید.",
                http_status=400,
            )
        
        plan = self.subscription.plan
        if not plan:
            raise ApiError("PLAN_NOT_FOUND", "پلن اشتراک یافت نشد", http_status=404)
        
        from app.services.ai.ai_quota_helpers import (
            compute_tokens_remaining,
            effective_tokens_limit,
            has_token_cap,
            quota_allows_tokens,
            renewal_date_iso,
        )

        total_tokens = input_tokens + output_tokens
        
        if total_tokens == 0:
            return {"payment_method": "free", "cost": 0, "wallet_transaction_id": None, "document_id": None}

        if plan.plan_type == "byok":
            # فقط ثبت مصرف برای آمار؛ بدون شارژ کیف پول پلتفرم
            self.subscription.tokens_used = (self.subscription.tokens_used or 0) + total_tokens
            self.db.commit()
            return {
                "payment_method": "byok",
                "cost": 0,
                "wallet_transaction_id": None,
                "document_id": None,
            }
        
        if plan.plan_type == "free":
            tokens_used = self.subscription.tokens_used or 0
            if has_token_cap(self.subscription.tokens_limit) and not quota_allows_tokens(
                tokens_used, self.subscription.tokens_limit, total_tokens
            ):
                remaining = compute_tokens_remaining(tokens_used, self.subscription.tokens_limit) or 0
                cap = effective_tokens_limit(self.subscription.tokens_limit) or 0
                raise ApiError(
                    "QUOTA_EXCEEDED",
                    f"سهمیه رایگان تمام شده است. باقیمانده: {remaining:,} توکن",
                    http_status=400,
                    details={
                        "tokens_used": tokens_used,
                        "tokens_limit": cap,
                        "tokens_remaining": remaining,
                        "tokens_required": total_tokens,
                        "suggestion": "برای استفاده بیشتر، به پلن پولی ارتقا دهید"
                    }
                )
            
            self.subscription.tokens_used += total_tokens
            self.db.commit()
            return {"payment_method": "free", "cost": 0, "wallet_transaction_id": None, "document_id": None}
        
        elif plan.plan_type == "subscription":
            tokens_used = self.subscription.tokens_used or 0
            needed = total_tokens

            if not has_token_cap(self.subscription.tokens_limit):
                self.subscription.tokens_used += needed
                self.db.commit()
                return {"payment_method": "subscription", "cost": 0, "wallet_transaction_id": None, "document_id": None}

            remaining = compute_tokens_remaining(tokens_used, self.subscription.tokens_limit) or 0
            cap = effective_tokens_limit(self.subscription.tokens_limit) or 0
            
            if needed <= remaining:
                self.subscription.tokens_used += needed
                self.db.commit()
                return {"payment_method": "subscription", "cost": 0, "wallet_transaction_id": None, "document_id": None}
            else:
                raise ApiError(
                    "QUOTA_EXCEEDED",
                    f"سهمیه اشتراک تمام شده است. باقیمانده: {remaining:,} توکن",
                    http_status=400,
                    details={
                        "tokens_used": tokens_used,
                        "tokens_limit": cap,
                        "tokens_remaining": remaining,
                        "tokens_required": needed,
                        "suggestion": "منتظر تمدید ماهانه بمانید یا به پلن بالاتر ارتقا دهید",
                        "renewal_date": renewal_date_iso(self.subscription),
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
            cost = self._calculate_cost(plan, input_tokens, output_tokens, model_code=model_code)
            return self._charge_from_wallet(cost, input_tokens, output_tokens)
        
        elif plan.plan_type == "hybrid":
            if not self.business_id:
                raise ApiError(
                    "BUSINESS_REQUIRED",
                    "برای استفاده از پلن ترکیبی، انتخاب کسب‌وکار الزامی است",
                    http_status=400
                )
            
            tokens_used = self.subscription.tokens_used or 0
            needed = total_tokens

            if not has_token_cap(self.subscription.tokens_limit):
                cost = self._calculate_cost(plan, input_tokens, output_tokens, model_code=model_code)
                return self._charge_from_wallet(cost, input_tokens, output_tokens)

            remaining = compute_tokens_remaining(tokens_used, self.subscription.tokens_limit) or 0
            cap = effective_tokens_limit(self.subscription.tokens_limit) or 0
            
            if needed <= remaining:
                self.subscription.tokens_used += needed
                self.db.commit()
                return {"payment_method": "subscription", "cost": 0, "wallet_transaction_id": None, "document_id": None}
            else:
                self.subscription.tokens_used = tokens_used + remaining
                extra_tokens = needed - remaining
                cost = self._calculate_cost(
                    plan, input_tokens, output_tokens, extra_tokens, model_code=model_code
                )
                result = self._charge_from_wallet(cost, input_tokens, output_tokens)
                self.db.commit()
                return result
        
        raise ApiError("INVALID_PLAN_TYPE", "نوع پلن نامعتبر است", http_status=400)

    def _calculate_cost(
        self,
        plan,
        input_tokens: int,
        output_tokens: int,
        extra_tokens: Optional[int] = None,
        model_code: Optional[str] = None,
    ) -> Decimal:
        """محاسبه هزینه بر اساس پلن و مدل"""
        from app.services.ai.ai_model_service import calculate_usage_cost

        code = model_code or self.get_effective_model_code()
        return calculate_usage_cost(
            plan,
            code,
            input_tokens,
            output_tokens,
            extra_tokens=extra_tokens,
        )

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
        cached = 0
        if isinstance(context, dict):
            cached = int(
                context.get("cached_tokens")
                or context.get("prompt_cache_read_tokens")
                or 0
            )
        extra = {"model": model, "input_tokens": input_tokens, "output_tokens": output_tokens}
        if cached:
            extra["cached_tokens"] = cached
        log_ai_event(
            "usage_logged",
            business_id=int(self.business_id) if self.business_id else None,
            user_id=self.ctx.get_user_id(),
            extra=extra,
        )
        return usage_log
