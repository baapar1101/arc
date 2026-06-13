from decimal import Decimal

from app.services.ai.ai_model_service import calculate_usage_cost
from app.services.ai.ai_quota_helpers import (
    compute_tokens_remaining,
    effective_tokens_limit,
    has_token_cap,
    quota_allows_tokens,
    split_tokens_proportionally,
    usage_percentage,
)
from tests.test_ai_model_service import _plan_with_pricing


def test_effective_tokens_limit_treats_zero_as_unlimited():
    assert effective_tokens_limit(None) is None
    assert effective_tokens_limit(0) is None
    assert effective_tokens_limit(-1) is None
    assert effective_tokens_limit(100) == 100


def test_has_token_cap():
    assert not has_token_cap(None)
    assert not has_token_cap(0)
    assert has_token_cap(5000)


def test_compute_tokens_remaining():
    assert compute_tokens_remaining(100, 1000) == 900
    assert compute_tokens_remaining(100, None) is None
    assert compute_tokens_remaining(100, 0) is None


def test_quota_allows_tokens_unlimited():
    assert quota_allows_tokens(999_999, None, 1000)
    assert quota_allows_tokens(999_999, 0, 1000)


def test_usage_percentage_unlimited_is_zero():
    assert usage_percentage(500, None) == 0.0
    assert usage_percentage(250, 1000) == 25.0


def test_split_tokens_proportionally():
    over_in, over_out = split_tokens_proportionally(600, 400, 100)
    assert over_in == 60
    assert over_out == 40


def test_calculate_usage_cost_extra_tokens_uses_both_rates():
    plan = _plan_with_pricing(
        {
            "pay_as_go": {
                "models": {
                    "mini": {
                        "price_per_1k_input_tokens": 1000,
                        "price_per_1k_output_tokens": 2000,
                    }
                }
            }
        }
    )
    cost = calculate_usage_cost(
        plan,
        "mini",
        input_tokens=600,
        output_tokens=400,
        extra_tokens=100,
    )
    assert cost == Decimal("60") + Decimal("80")
