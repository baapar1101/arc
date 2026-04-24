from __future__ import annotations

from typing import Dict, Any, Optional
from decimal import Decimal
from datetime import datetime, timedelta
from sqlalchemy.orm import Session
import json
import logging

from app.core.responses import ApiError
from adapters.db.models.ai_plan import AIPlan, AIPlanType
from adapters.db.models.ai_subscription import UserAISubscription, SubscriptionType
from adapters.db.repositories.ai_plan_repository import AIPlanRepository
from adapters.db.repositories.ai_subscription_repository import AISubscriptionRepository
from app.services.ai.ai_invoice_service import create_subscription_invoice, pay_ai_invoice_from_wallet
from app.services.system_settings_service import get_wallet_settings

logger = logging.getLogger(__name__)


def _monthly_tokens_cap_from_plan(plan: AIPlan) -> int:
    """سقف توکن ماهانه برای اشتراک: اولویت با usage_limits سپس ستون‌های پلن."""
    try:
        ul = json.loads(plan.usage_limits or "{}")
    except Exception:
        ul = {}
    v = ul.get("monthly_tokens")
    if v is not None:
        try:
            return int(v)
        except (TypeError, ValueError):
            pass
    if plan.monthly_tokens_limit is not None:
        return int(plan.monthly_tokens_limit)
    if plan.tokens_limit is not None:
        return int(plan.tokens_limit)
    return 0


def _merge_usage_limits_for_save(
    usage_limits: Optional[Dict[str, Any]],
    tokens_limit: Optional[int],
    monthly_tokens_limit: Optional[int],
) -> Dict[str, Any]:
    ul = dict(usage_limits or {})
    if monthly_tokens_limit is not None:
        ul["monthly_tokens"] = int(monthly_tokens_limit)
    elif tokens_limit is not None and "monthly_tokens" not in ul:
        ul["monthly_tokens"] = int(tokens_limit)
    return ul


def _sync_usage_limits_monthly_tokens_from_columns(plan: AIPlan) -> None:
    try:
        ul = json.loads(plan.usage_limits or "{}")
    except Exception:
        ul = {}
    if plan.monthly_tokens_limit is not None:
        ul["monthly_tokens"] = int(plan.monthly_tokens_limit)
    elif plan.tokens_limit is not None:
        ul["monthly_tokens"] = int(plan.tokens_limit)
    plan.usage_limits = json.dumps(ul, ensure_ascii=False)


def create_plan(
    db: Session,
    code: str,
    name: str,
    plan_type: str,
    pricing_config: Dict[str, Any],
    usage_limits: Dict[str, Any],
    features: Dict[str, Any],
    description: Optional[str] = None,
    *,
    tokens_limit: Optional[int] = None,
    monthly_tokens_limit: Optional[int] = None,
    auto_renew: bool = False,
    is_active: bool = True,
) -> AIPlan:
    """ایجاد پلن جدید"""
    repo = AIPlanRepository(db)

    existing = repo.get_by_code(code)
    if existing:
        raise ApiError("DUPLICATE_PLAN_CODE", "کد پلن تکراری است", http_status=400)

    merged_limits = _merge_usage_limits_for_save(usage_limits, tokens_limit, monthly_tokens_limit)

    plan = AIPlan(
        code=code,
        name=name,
        description=description,
        plan_type=plan_type,
        pricing_config=json.dumps(pricing_config or {}, ensure_ascii=False),
        usage_limits=json.dumps(merged_limits, ensure_ascii=False),
        features=json.dumps(features or {}, ensure_ascii=False),
        tokens_limit=tokens_limit,
        monthly_tokens_limit=monthly_tokens_limit,
        is_active=is_active,
        auto_renew=auto_renew,
    )

    db.add(plan)
    db.commit()
    db.refresh(plan)
    return plan


def update_plan(db: Session, plan_id: int, **kwargs: Any) -> AIPlan:
    """به‌روزرسانی پلن؛ فقط کلیدهای ارسال‌شده اعمال می‌شوند."""
    repo = AIPlanRepository(db)
    plan = repo.get_by_id(plan_id)

    if not plan:
        raise ApiError("PLAN_NOT_FOUND", "پلن یافت نشد", http_status=404)

    if "name" in kwargs:
        plan.name = str(kwargs["name"] or "")
    if "description" in kwargs:
        plan.description = kwargs["description"]

    if "pricing_config" in kwargs:
        plan.pricing_config = json.dumps(kwargs["pricing_config"] or {}, ensure_ascii=False)

    if "usage_limits" in kwargs and kwargs["usage_limits"] is not None:
        ul = json.loads(plan.usage_limits or "{}")
        ul.update(kwargs["usage_limits"] or {})
        plan.usage_limits = json.dumps(ul, ensure_ascii=False)

    if "features" in kwargs and kwargs["features"] is not None:
        plan.features = json.dumps(kwargs["features"] or {}, ensure_ascii=False)

    if "is_active" in kwargs:
        plan.is_active = bool(kwargs["is_active"])

    if "plan_type" in kwargs and kwargs["plan_type"] is not None:
        plan.plan_type = str(kwargs["plan_type"])

    if "tokens_limit" in kwargs:
        plan.tokens_limit = kwargs["tokens_limit"]
    if "monthly_tokens_limit" in kwargs:
        plan.monthly_tokens_limit = kwargs["monthly_tokens_limit"]

    if "auto_renew" in kwargs:
        plan.auto_renew = bool(kwargs["auto_renew"])

    if any(k in kwargs for k in ("tokens_limit", "monthly_tokens_limit")):
        _sync_usage_limits_monthly_tokens_from_columns(plan)

    db.commit()
    db.refresh(plan)
    return plan


def subscribe_to_plan(
    db: Session,
    user_id: int,
    business_id: Optional[int],
    plan_id: int,
    period: str = "monthly"  # monthly, yearly
) -> Dict[str, Any]:
    """
    اشتراک به پلن
    - اگر subscription / hybrid و مبلد دوره > 0: ایجاد فاکتور و پرداخت فوری از کیف پول (سند + تراکنش)؛ ناکافی = خطا
    - اگر free: فعال‌سازی مستقیم
    - اگر pay_as_go: فقط ثبت subscription
    """
    plan_repo = AIPlanRepository(db)
    plan = plan_repo.get_by_id(plan_id)

    if not plan or not plan.is_active:
        raise ApiError("PLAN_NOT_FOUND", "پلن یافت نشد یا غیرفعال است", http_status=404)

    sub_repo = AISubscriptionRepository(db)
    existing = sub_repo.get_active_subscription(user_id, business_id)
    if existing:
        existing.is_active = False
        db.flush()

    if plan.plan_type == AIPlanType.FREE.value:
        subscription_type = SubscriptionType.FREE.value
        tokens_limit_val = _monthly_tokens_cap_from_plan(plan)
        period_start = datetime.utcnow()
        period_end = None
    elif plan.plan_type == AIPlanType.SUBSCRIPTION.value:
        subscription_type = SubscriptionType.SUBSCRIPTION.value
        tokens_limit_val = _monthly_tokens_cap_from_plan(plan)
        period_start = datetime.utcnow()
        if period == "monthly":
            period_end = period_start + timedelta(days=30)
        else:
            period_end = period_start + timedelta(days=365)
    elif plan.plan_type == AIPlanType.PAY_AS_GO.value:
        subscription_type = SubscriptionType.PAY_AS_GO.value
        tokens_limit_val = None
        period_start = datetime.utcnow()
        period_end = None
    elif plan.plan_type == AIPlanType.HYBRID.value:
        subscription_type = SubscriptionType.SUBSCRIPTION.value
        tokens_limit_val = _monthly_tokens_cap_from_plan(plan)
        period_start = datetime.utcnow()
        if period == "monthly":
            period_end = period_start + timedelta(days=30)
        else:
            period_end = period_start + timedelta(days=365)
    else:
        raise ApiError("INVALID_PLAN_TYPE", "نوع پلن نامعتبر است", http_status=400)

    subscription = UserAISubscription(
        user_id=user_id,
        business_id=business_id,
        plan_id=plan_id,
        subscription_type=subscription_type,
        tokens_used=0,
        tokens_limit=tokens_limit_val,
        period_start=period_start,
        period_end=period_end,
        is_active=True,
        auto_renew=bool(getattr(plan, "auto_renew", False)),
    )
    db.add(subscription)
    db.flush()

    invoice = None
    payment_info: Optional[Dict[str, Any]] = None
    if plan.plan_type in [AIPlanType.SUBSCRIPTION.value, AIPlanType.HYBRID.value]:
        pricing_config = json.loads(plan.pricing_config or "{}")
        subscription_config = pricing_config.get("subscription", {})

        if period == "monthly":
            amount = Decimal(str(subscription_config.get("monthly_price", 0)))
        else:
            amount = Decimal(str(subscription_config.get("yearly_price", 0)))

        if amount > 0:
            if not business_id:
                raise ApiError(
                    "BUSINESS_ID_REQUIRED",
                    "برای پلن اشتراکی پولی، شناسه کسب‌وکار الزامی است",
                    http_status=400,
                )
            wallet_settings = get_wallet_settings(db)
            currency_id = wallet_settings.get("wallet_base_currency_id")
            if not currency_id:
                raise ApiError("CURRENCY_NOT_SET", "ارز پایه کیف پول تنظیم نشده است", http_status=400)

            invoice = create_subscription_invoice(
                db=db,
                subscription_id=subscription.id,
                business_id=int(business_id),
                amount=amount,
                period=period,
                currency_id=currency_id,
            )
            payment_info = pay_ai_invoice_from_wallet(
                db=db,
                business_id=int(business_id),
                invoice_id=invoice.id,
                user_id=int(user_id),
            )
            db.refresh(invoice)
            db.refresh(subscription)

    if not payment_info:
        db.commit()
    return {
        "subscription": subscription,
        "invoice": invoice,
        "payment": payment_info,
    }
