"""Tests for BYOK (business AI provider) helpers."""

from __future__ import annotations

import json
from types import SimpleNamespace

import pytest

from app.core.responses import ApiError
from app.services.ai.business_ai_provider_service import (
    get_byok_platform_fee,
    is_byok_plan,
    normalize_models_payload,
    validate_api_base_url,
)


def _err_code(exc: ApiError) -> str:
    return exc.detail["error"]["code"]


def test_is_byok_plan():
    assert is_byok_plan(None) is False
    assert is_byok_plan(SimpleNamespace(plan_type="free")) is False
    assert is_byok_plan(SimpleNamespace(plan_type="byok")) is True


def test_get_byok_platform_fee_from_platform_fee():
    plan = SimpleNamespace(
        pricing_config=json.dumps(
            {"platform_fee": {"monthly_price": 10, "yearly_price": 100}}
        )
    )
    fee = get_byok_platform_fee(plan)
    assert fee["monthly_price"] == 10
    assert fee["yearly_price"] == 100


def test_get_byok_platform_fee_from_subscription_fallback():
    plan = SimpleNamespace(
        pricing_config=json.dumps(
            {"subscription": {"monthly_price": 5, "yearly_price": 50}}
        )
    )
    fee = get_byok_platform_fee(plan)
    assert fee["monthly_price"] == 5
    assert fee["yearly_price"] == 50


def test_normalize_models_payload_strings_and_dicts():
    models = normalize_models_payload(
        [
            "gpt-4o",
            {"code": "gpt-4o-mini", "display_name": "Mini", "supports_tools": False},
            {"code": "gpt-4o"},  # duplicate ignored
        ]
    )
    assert len(models) == 2
    assert models[0]["code"] == "gpt-4o"
    assert models[1]["display_name"] == "Mini"
    assert models[1]["supports_tools"] is False


def test_normalize_models_payload_empty_raises():
    with pytest.raises(ApiError) as exc:
        normalize_models_payload({"not": "a list"})
    assert _err_code(exc.value) == "INVALID_MODELS"


def test_validate_api_base_url_rejects_bad_scheme():
    with pytest.raises(ApiError) as exc:
        validate_api_base_url("ftp://example.com", provider="openai")
    assert _err_code(exc.value) == "INVALID_API_BASE_URL"


def test_validate_api_base_url_local_allows_localhost():
    url = validate_api_base_url("http://localhost:11434", provider="local")
    assert url == "http://localhost:11434"


def test_validate_api_base_url_openai_blocks_localhost():
    with pytest.raises(ApiError) as exc:
        validate_api_base_url("http://localhost:8080", provider="openai")
    assert _err_code(exc.value) == "PRIVATE_API_BASE_URL_BLOCKED"


def test_validate_api_base_url_optional_for_openai():
    assert validate_api_base_url(None, provider="openai") is None
    assert validate_api_base_url("  ", provider="openai") is None


def test_validate_api_base_url_required_for_local():
    with pytest.raises(ApiError) as exc:
        validate_api_base_url("", provider="local")
    assert _err_code(exc.value) == "API_BASE_URL_REQUIRED"
