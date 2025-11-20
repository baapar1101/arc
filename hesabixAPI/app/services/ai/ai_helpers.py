"""
Helper functions برای AI Service
"""

from __future__ import annotations

from typing import Dict, Any, Optional
from decimal import Decimal
from datetime import datetime
from sqlalchemy.orm import Session

from adapters.db.repositories.ai_subscription_repository import AISubscriptionRepository
from adapters.db.repositories.ai_usage_log_repository import AIUsageLogRepository
from adapters.db.models.ai_subscription import UserAISubscription


def get_user_ai_quota(
    db: Session,
    user_id: int,
    business_id: Optional[int] = None
) -> Dict[str, Any]:
    """
    دریافت سهمیه باقیمانده کاربر
    """
    repo = AISubscriptionRepository(db)
    subscription = repo.get_active_subscription(
        user_id=user_id,
        business_id=business_id
    )
    
    if not subscription:
        return {
            "has_subscription": False,
            "remaining_tokens": 0,
            "used_tokens": 0,
            "total_tokens": 0,
            "plan_name": None
        }
    
    plan = subscription.plan
    used = subscription.tokens_used or 0
    limit = subscription.tokens_limit or 0
    remaining = max(0, limit - used)
    
    return {
        "has_subscription": True,
        "remaining_tokens": remaining,
        "used_tokens": used,
        "total_tokens": limit,
        "plan_name": plan.name if plan else None,
        "plan_type": plan.plan_type if plan else None,
        "subscription_id": subscription.id
    }


def get_user_usage_summary(
    db: Session,
    user_id: int,
    business_id: Optional[int] = None,
    days: int = 30
) -> Dict[str, Any]:
    """
    دریافت خلاصه استفاده کاربر در بازه زمانی مشخص
    """
    from datetime import timedelta
    
    repo = AIUsageLogRepository(db)
    start_date = datetime.utcnow() - timedelta(days=days)
    
    stats = repo.get_usage_statistics(
        user_id=user_id,
        business_id=business_id,
        from_date=start_date
    )
    
    return {
        "period_days": days,
        "total_tokens": stats.get("total_tokens", 0),
        "input_tokens": stats.get("total_input_tokens", 0),
        "output_tokens": stats.get("total_output_tokens", 0),
        "total_cost": float(stats.get("total_cost", 0)),
        "total_requests": stats.get("total_requests", 0),
        "average_tokens_per_request": (
            stats.get("total_tokens", 0) / stats.get("total_requests", 1)
            if stats.get("total_requests", 0) > 0
            else 0
        )
    }


def estimate_request_cost(
    plan_type: str,
    pricing_config: Dict[str, Any],
    input_tokens: int,
    output_tokens: int
) -> Decimal:
    """
    تخمین هزینه یک درخواست بر اساس پلن
    """
    if plan_type == "free":
        return Decimal(0)
    
    if plan_type == "subscription":
        # در subscription معمولاً هزینه اضافی نداریم
        return Decimal(0)
    
    # برای pay_as_go و hybrid
    input_price = Decimal(str(pricing_config.get("input_token_price", 0)))
    output_price = Decimal(str(pricing_config.get("output_token_price", 0)))
    
    cost = (Decimal(input_tokens) * input_price) + (Decimal(output_tokens) * output_price)
    return cost


def can_user_use_ai(
    db: Session,
    user_id: int,
    business_id: Optional[int] = None,
    required_tokens: int = 0
) -> Dict[str, Any]:
    """
    بررسی اینکه آیا کاربر می‌تواند از AI استفاده کند
    """
    quota = get_user_ai_quota(db, user_id, business_id)
    
    if not quota["has_subscription"]:
        return {
            "can_use": False,
            "reason": "NO_SUBSCRIPTION",
            "message": "اشتراک فعالی وجود ندارد"
        }
    
    if quota["plan_type"] == "free" and quota["remaining_tokens"] < required_tokens:
        return {
            "can_use": False,
            "reason": "QUOTA_EXCEEDED",
            "message": f"سهمیه باقیمانده ({quota['remaining_tokens']}) کمتر از نیاز ({required_tokens}) است",
            "remaining": quota["remaining_tokens"],
            "required": required_tokens
        }
    
    if quota["plan_type"] == "subscription" and quota["remaining_tokens"] < required_tokens:
        # برای subscription باید بررسی کنیم که آیا hybrid است یا نه
        # این بررسی در check_quota_and_charge انجام می‌شود
        pass
    
    return {
        "can_use": True,
        "quota": quota
    }

