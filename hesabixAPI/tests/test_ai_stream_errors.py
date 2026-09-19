from app.services.ai.ai_stream_errors import (
    STREAM_ERROR_CREDIT,
    STREAM_ERROR_PROVIDER_TIMEOUT,
    STREAM_ERROR_RATE_LIMIT,
    classify_stream_exception,
    stream_error_payload,
)
from app.core.responses import ApiError


def test_timeout_classifies_as_provider_timeout():
    assert classify_stream_exception(TimeoutError("timed out")) == STREAM_ERROR_PROVIDER_TIMEOUT


def test_quota_api_error_is_credit():
    err = ApiError("AI_QUOTA_EXCEEDED", "no credit", http_status=402)
    assert classify_stream_exception(err) == STREAM_ERROR_CREDIT


def test_rate_limit_suggested_action():
    payload = stream_error_payload(
        ApiError("RATE_LIMIT_EXCEEDED", "slow down", http_status=429),
        can_continue=False,
    )
    assert payload["error_code"] == STREAM_ERROR_RATE_LIMIT
    assert payload["recoverable"] is True
    assert payload["suggested_action"] == "retry"
    assert payload["error"]


def test_idle_payload_offers_continue():
    payload = stream_error_payload(code="RUN_IDLE", run_id="abc", can_continue=True)
    assert payload["suggested_action"] == "continue"
    assert payload["can_continue"] is True
