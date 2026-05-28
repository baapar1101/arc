"""تست سیاست retry LLM."""
from app.core.responses import ApiError
from app.services.ai.ai_retry_policy import is_retryable_error


def test_retryable_api_error_codes():
    assert is_retryable_error(
        ApiError("RATE_LIMIT_EXCEEDED", "limit", http_status=429)
    )
    assert is_retryable_error(
        ApiError("AI_PROVIDER_ERROR", "server", http_status=500)
    )


def test_non_retryable_api_error():
    assert not is_retryable_error(
        ApiError("INVALID_API_KEY", "bad key", http_status=400)
    )


def test_retryable_message_tokens():
    assert is_retryable_error(TimeoutError("connection timed out"))
    assert is_retryable_error(Exception("rate_limit exceeded"))
