from __future__ import annotations

from types import SimpleNamespace
from unittest.mock import MagicMock

from app.services.user_ui_preferences_service import (
    _normalize_quick_sales_payment_shortcuts,
    get_user_ui_preferences,
    save_user_ui_preferences,
)


def test_normalize_quick_sales_shortcuts_keeps_platform_values() -> None:
    result = _normalize_quick_sales_payment_shortcuts(
        {
            "4952": {
                "windows": {"17": " f12 ", "21": "alt + r"},
                "web": {"17": "CTRL+1"},
            },
            "invalid": {"windows": {"1": "F2"}},
        }
    )

    assert result == {
        "4952": {
            "windows": {"17": "F12", "21": "ALT+R"},
            "web": {"17": "CTRL+1"},
        }
    }


def test_generic_preference_update_preserves_quick_sales_shortcuts() -> None:
    row = SimpleNamespace(
        preferences={
            "business_panel_navigation": "single",
            "business_panel_sidebar_tab_behavior": "reuse_across_tabs",
            "business_panel_tabs": {},
            "quick_sales_payment_shortcuts": {
                "4952": {"windows": {"17": "F12"}}
            },
        },
        updated_at=None,
    )
    db = MagicMock()
    db.query.return_value.filter.return_value.first.return_value = row

    result = save_user_ui_preferences(
        db,
        user_id=7,
        payload={"business_panel_navigation": "tabs"},
    )

    assert result["business_panel_navigation"] == "tabs"
    assert result["quick_sales_payment_shortcuts"] == {
        "4952": {"windows": {"17": "F12"}}
    }
    assert row.preferences["quick_sales_payment_shortcuts"] == {
        "4952": {"windows": {"17": "F12"}}
    }


def test_get_preferences_returns_empty_shortcut_map_by_default() -> None:
    db = MagicMock()
    db.query.return_value.filter.return_value.first.return_value = None

    result = get_user_ui_preferences(db, user_id=7)

    assert result.get("quick_sales_payment_shortcuts", {}) == {}
