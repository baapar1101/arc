"""آزمون بررسی‌های مالکیت و تأیید CRM، بدون پایگاه داده."""
import pytest

from app.core.responses import ApiError
from app.services.crm_chat_service import origin_allowed
from app.services.crm_guards import (
    assert_bulk_delete_confirmed,
    normalize_allowed_origins,
    origins_unrestricted,
    require_allowed_origins,
)


class _Widget:
    def __init__(self, allowed_origins):
        self.allowed_origins = allowed_origins


def test_normalize_allowed_origins_strips_scheme_and_dedupes():
    assert normalize_allowed_origins(
        ["https://Shop.Example.com/path", "shop.example.com", "  ", None]
    ) == ["shop.example.com"]


def test_require_allowed_origins_rejects_empty():
    with pytest.raises(ApiError) as exc:
        require_allowed_origins([])
    assert exc.value.code == "CRM_CHAT_ORIGINS_REQUIRED" if hasattr(exc.value, "code") else exc.value.detail


def test_existing_widget_without_origins_stays_open_until_edited():
    assert origins_unrestricted(None) is True
    assert origin_allowed(_Widget(None), "https://other.example") is True
    assert origin_allowed(_Widget([]), "https://other.example") is True


def test_configured_widget_rejects_other_hosts():
    widget = _Widget(["shop.example.com"])
    assert origin_allowed(widget, "https://shop.example.com") is True
    assert origin_allowed(widget, "https://evil.example") is False


def test_bulk_delete_of_all_conversations_needs_explicit_confirm():
    with pytest.raises(ApiError):
        assert_bulk_delete_confirmed(status=None, confirm_all=False)
    assert_bulk_delete_confirmed(status=None, confirm_all=True)
    assert_bulk_delete_confirmed(status="resolved", confirm_all=False)
