"""تست سرویس تنظیمات فروش سریع — پیش‌فرض اشتراک‌گذاری."""

from __future__ import annotations

from unittest.mock import MagicMock

import pytest

from adapters.db.seed_data.notification_event_types_seed import (
    INVOICE_SHARE_LINK_EVENT_CODES,
    NOTIFICATION_EVENT_TYPES_ROWS,
)
from app.core.responses import ApiError
from app.services.quick_sales_service import (
    DEFAULT_SHARE_CHANNELS,
    DEFAULT_SHARE_EXPIRY_HOURS,
    normalize_default_share_channels,
    normalize_share_expiry_hours,
    get_quick_sales_settings,
    _share_settings_from_obj,
)


def test_normalize_default_share_channels_defaults() -> None:
    assert normalize_default_share_channels(None) == DEFAULT_SHARE_CHANNELS


def test_normalize_default_share_channels_filters_invalid() -> None:
    assert normalize_default_share_channels(["sms", "telegram", "email"]) == ["sms", "email"]


def test_normalize_default_share_channels_json_string() -> None:
    assert normalize_default_share_channels('["email", "native"]') == ["email", "native"]


def test_normalize_default_share_channels_empty_list_falls_back() -> None:
    assert normalize_default_share_channels([]) == DEFAULT_SHARE_CHANNELS


def test_normalize_share_expiry_hours_clamps() -> None:
    assert normalize_share_expiry_hours(0) == 1
    assert normalize_share_expiry_hours(9999) == 720
    assert normalize_share_expiry_hours("336") == 336


def test_normalize_share_expiry_hours_invalid() -> None:
    assert normalize_share_expiry_hours("bad") == DEFAULT_SHARE_EXPIRY_HOURS


def test_share_settings_from_obj_none() -> None:
    data = _share_settings_from_obj(None)
    assert data["default_share_online_payment"] is True
    assert data["default_share_gateway_id"] is None
    assert data["default_share_channels"] == DEFAULT_SHARE_CHANNELS
    assert data["default_share_expiry_hours"] == DEFAULT_SHARE_EXPIRY_HOURS


def test_get_quick_sales_settings_includes_share_defaults_when_missing_row() -> None:
    db = MagicMock()
    settings_query = MagicMock()
    settings_query.filter.return_value.first.return_value = None
    business = MagicMock()
    business.default_currency_id = 42
    business_query = MagicMock()
    business_query.filter.return_value.first.return_value = business

    def _query_side(model):
        name = getattr(model, "__name__", "")
        if name == "QuickSalesSetting":
            return settings_query
        if name == "Business":
            return business_query
        return MagicMock()

    db.query.side_effect = _query_side

    result = get_quick_sales_settings(db, 1)
    assert result["default_share_online_payment"] is True
    assert result["default_share_channels"] == DEFAULT_SHARE_CHANNELS
    assert result["default_share_expiry_hours"] == 168
    assert result["default_currency_id"] == 42


def test_invoice_share_link_event_type_in_seed_catalog() -> None:
    codes = {row["code"] for row in NOTIFICATION_EVENT_TYPES_ROWS}
    assert INVOICE_SHARE_LINK_EVENT_CODES <= codes
    row = next(r for r in NOTIFICATION_EVENT_TYPES_ROWS if r["code"] == "invoice_share_link")
    assert "share_link" in row["default_sms_template"]
    assert "share_link" in row["default_email_template"]


def test_validate_share_gateway_id_rejects_unknown_gateway() -> None:
    from app.services.quick_sales_service import _validate_share_gateway_id

    db = MagicMock()
    gw_query = MagicMock()
    gw_query.filter.return_value.first.return_value = None
    db.query.return_value = gw_query

    with pytest.raises(ApiError) as exc:
        _validate_share_gateway_id(db, 1, 99)
    assert exc.value.detail["error"]["code"] == "GATEWAY_NOT_FOUND"
