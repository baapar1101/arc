from decimal import Decimal

import pytest
from sqlalchemy.orm import Session

from adapters.db.models.ai_plan import AIPlan
from app.services.ai.ai_model_service import (
    calculate_usage_cost,
    estimate_cost_for_tokens,
    get_model_pricing_rates,
    get_plan_allowed_model_codes,
)


def _plan_with_pricing(pricing: dict) -> AIPlan:
    import json

    return AIPlan(
        code="test",
        name="Test",
        plan_type="pay_as_go",
        pricing_config=json.dumps(pricing, ensure_ascii=False),
    )


def test_get_model_pricing_rates_prefers_per_model():
    plan = _plan_with_pricing(
        {
            "pay_as_go": {
                "price_per_1k_input_tokens": 1,
                "price_per_1k_output_tokens": 2,
                "models": {
                    "gpt-4o": {
                        "price_per_1k_input_tokens": 10,
                        "price_per_1k_output_tokens": 30,
                    }
                },
            }
        }
    )
    in_p, out_p = get_model_pricing_rates(plan, "gpt-4o")
    assert in_p == Decimal("0.01")
    assert out_p == Decimal("0.03")


def test_get_model_pricing_rates_fallback_to_global():
    plan = _plan_with_pricing(
        {"pay_as_go": {"price_per_1k_input_tokens": 5, "price_per_1k_output_tokens": 7}}
    )
    in_p, out_p = get_model_pricing_rates(plan, "unknown-model")
    assert in_p == Decimal("0.005")
    assert out_p == Decimal("0.007")


def test_calculate_usage_cost():
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
    cost = calculate_usage_cost(plan, "mini", input_tokens=1000, output_tokens=500)
    assert cost == Decimal("1000") + Decimal("1000")


def test_get_plan_allowed_model_codes():
    plan = _plan_with_pricing({"allowed_models": ["a", "b"]})
    assert get_plan_allowed_model_codes(plan) == ["a", "b"]


def test_estimate_cost_for_tokens():
    plan = _plan_with_pricing(
        {"pay_as_go": {"price_per_1k_input_tokens": 10, "price_per_1k_output_tokens": 10}}
    )
    cost = estimate_cost_for_tokens(plan, "any", 1000)
    assert cost == Decimal("5") + Decimal("5")
