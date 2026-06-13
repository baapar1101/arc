"""
توابع مشترک برای سهمیه توکن اشتراک AI.
None یا مقدار <= 0 یعنی بدون سقف معین (نامحدود از نظر سهمیه).
"""

from __future__ import annotations

from datetime import datetime, timedelta
from typing import Any, Dict, Optional, TYPE_CHECKING

if TYPE_CHECKING:
    from adapters.db.models.ai_subscription import UserAISubscription


def effective_tokens_limit(limit: Optional[int]) -> Optional[int]:
    if limit is None or limit <= 0:
        return None
    return int(limit)


def has_token_cap(limit: Optional[int]) -> bool:
    return effective_tokens_limit(limit) is not None


def compute_tokens_remaining(used: int, limit: Optional[int]) -> Optional[int]:
    cap = effective_tokens_limit(limit)
    if cap is None:
        return None
    return max(0, cap - (used or 0))


def usage_percentage(used: int, limit: Optional[int]) -> float:
    cap = effective_tokens_limit(limit)
    if cap is None or cap <= 0:
        return 0.0
    return round((used or 0) / cap * 100, 1)


def subscription_quota_info(subscription: "UserAISubscription") -> Dict[str, Any]:
    used = subscription.tokens_used or 0
    limit = subscription.tokens_limit
    remaining = compute_tokens_remaining(used, limit)
    cap = effective_tokens_limit(limit)
    return {
        "tokens_used": used,
        "tokens_limit": cap,
        "tokens_remaining": remaining if remaining is not None else None,
        "usage_percentage": usage_percentage(used, limit),
        "has_token_cap": has_token_cap(limit),
    }


def quota_allows_tokens(used: int, limit: Optional[int], needed: int) -> bool:
    remaining = compute_tokens_remaining(used, limit)
    if remaining is None:
        return True
    return needed <= remaining


def renewal_date_iso(subscription: "UserAISubscription") -> Optional[str]:
    dt = subscription.period_end or subscription.expires_at
    return dt.isoformat() if dt else None


def split_tokens_proportionally(
    input_tokens: int,
    output_tokens: int,
    token_count: int,
) -> tuple[int, int]:
    total = input_tokens + output_tokens
    if token_count <= 0:
        return 0, 0
    if total <= 0:
        half = token_count // 2
        return half, token_count - half
    over_in = int(token_count * input_tokens / total)
    over_out = token_count - over_in
    return over_in, over_out


def reset_monthly_quota(subscription: "UserAISubscription", *, now: Optional[datetime] = None) -> None:
    """ریست سهمیه ماهانه و تمدید دوره برای پلن‌های اشتراکی."""
    now = now or datetime.utcnow()
    subscription.tokens_used = 0
    subscription.last_reset_at = now

    plan_type = subscription.plan.plan_type if subscription.plan else None
    period_days = 30
    if (
        plan_type in ("subscription", "hybrid")
        and subscription.period_end is not None
        and subscription.period_start is not None
    ):
        prev_days = (subscription.period_end - subscription.period_start).days
        if prev_days > 60:
            period_days = 365

    subscription.period_start = now
    if plan_type in ("subscription", "hybrid") and subscription.period_end is not None:
        subscription.period_end = now + timedelta(days=period_days)
        subscription.expires_at = subscription.period_end
