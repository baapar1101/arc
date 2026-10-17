"""تست سرویس تنظیمات فروش سریع — پیش‌فرض اشتراک‌گذاری."""

from __future__ import annotations

from types import SimpleNamespace
from unittest.mock import ANY, MagicMock

import pytest

from adapters.db.seed_data.notification_event_types_seed import (
    INVOICE_SHARE_LINK_EVENT_CODES,
    NOTIFICATION_EVENT_TYPES_ROWS,
)
from app.core.responses import ApiError
from app.services.quick_sales_service import (
    DEFAULT_SHARE_CHANNELS,
    DEFAULT_SHARE_EXPIRY_HOURS,
    PAYMENT_BUTTON_SHORTCUT_DISABLED,
    _apply_user_payment_shortcuts,
    _assert_user_payment_shortcut_available,
    _normalize_payment_button_shortcut,
    _resolve_user_payment_shortcuts,
    _share_settings_from_obj,
    get_quick_sales_settings,
    normalize_default_share_channels,
    normalize_share_expiry_hours,
    set_quick_sales_payment_default_shortcuts,
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
    assert result["enable_stock_shortage_override"] is False
    assert result["quick_customer_group_id"] is None


def test_update_quick_sales_settings_validates_and_saves_customer_group(monkeypatch) -> None:
    from app.services import quick_sales_service as service

    db = MagicMock()
    settings = MagicMock()
    settings.quick_customer_group_id = None
    settings_query = MagicMock()
    settings_query.filter.return_value.first.return_value = settings
    db.query.return_value = settings_query
    validate_group = MagicMock()
    monkeypatch.setattr(service, "assert_assignable_person_group", validate_group)
    monkeypatch.setattr(
        service,
        "get_quick_sales_settings",
        lambda _db, _business_id: {
            "quick_customer_group_id": settings.quick_customer_group_id,
        },
    )

    result = service.update_quick_sales_settings(
        db,
        business_id=5,
        payload={"quick_customer_group_id": 19},
    )

    validate_group.assert_called_once_with(db, 5, 19)
    assert settings.quick_customer_group_id == 19
    assert result["quick_customer_group_id"] == 19
    db.commit.assert_called_once()


def test_update_quick_sales_settings_can_clear_customer_group(monkeypatch) -> None:
    from app.services import quick_sales_service as service

    db = MagicMock()
    settings = MagicMock()
    settings.quick_customer_group_id = 19
    settings_query = MagicMock()
    settings_query.filter.return_value.first.return_value = settings
    db.query.return_value = settings_query
    validate_group = MagicMock()
    monkeypatch.setattr(service, "assert_assignable_person_group", validate_group)
    monkeypatch.setattr(
        service,
        "get_quick_sales_settings",
        lambda _db, _business_id: {
            "quick_customer_group_id": settings.quick_customer_group_id,
        },
    )

    result = service.update_quick_sales_settings(
        db,
        business_id=5,
        payload={"quick_customer_group_id": None},
    )

    validate_group.assert_not_called()
    assert settings.quick_customer_group_id is None
    assert result["quick_customer_group_id"] is None


def _payment_button_row(*, scope: str, owner_user_id: int | None):
    return SimpleNamespace(
        id=11,
        business_id=5,
        scope=scope,
        owner_user_id=owner_user_id,
        target_type="cash_register",
        cash_register_id=7,
        bank_account_id=None,
        person_id=None,
        label="صندوق اصلی",
        shortcut=None,
        web_shortcut=None,
        position=2,
        is_active=True,
    )


def _query_with_scalar(value):
    query = MagicMock()
    query.filter.return_value.scalar.return_value = value
    return query


def test_update_payment_button_can_move_personal_button_to_business(monkeypatch) -> None:
    from app.services import quick_sales_service as service

    row = _payment_button_row(scope="user", owner_user_id=9)
    row_query = MagicMock()
    row_query.filter.return_value.first.return_value = row
    db = MagicMock()
    db.query.side_effect = [
        row_query,
        _query_with_scalar(3),
        _query_with_scalar(6),
    ]
    monkeypatch.setattr(
        service,
        "_payment_button_target",
        lambda *_args: (SimpleNamespace(id=7), "صندوق اصلی"),
    )
    monkeypatch.setattr(
        service,
        "list_quick_sales_payment_buttons",
        lambda *_args: [{"id": 11, "scope": row.scope}],
    )

    result = service.update_quick_sales_payment_button(
        db,
        business_id=5,
        button_id=11,
        user_id=9,
        payload={"scope": "business"},
        can_manage_business=True,
    )

    assert row.scope == "business"
    assert row.owner_user_id is None
    assert row.position == 7
    assert result["scope"] == "business"
    db.commit.assert_called_once()


def test_update_payment_button_can_move_shared_button_to_current_user(monkeypatch) -> None:
    from app.services import quick_sales_service as service

    row = _payment_button_row(scope="business", owner_user_id=None)
    row_query = MagicMock()
    row_query.filter.return_value.first.return_value = row
    db = MagicMock()
    db.query.side_effect = [
        row_query,
        _query_with_scalar(0),
        _query_with_scalar(None),
    ]
    monkeypatch.setattr(
        service,
        "_payment_button_target",
        lambda *_args: (SimpleNamespace(id=7), "صندوق اصلی"),
    )
    monkeypatch.setattr(
        service,
        "list_quick_sales_payment_buttons",
        lambda *_args: [{"id": 11, "scope": row.scope}],
    )

    service.update_quick_sales_payment_button(
        db,
        business_id=5,
        button_id=11,
        user_id=9,
        payload={"scope": "user"},
        can_manage_business=True,
    )

    assert row.scope == "user"
    assert row.owner_user_id == 9
    assert row.position == 0


def test_update_payment_button_scope_requires_business_permission() -> None:
    from app.services import quick_sales_service as service

    row = _payment_button_row(scope="user", owner_user_id=9)
    row_query = MagicMock()
    row_query.filter.return_value.first.return_value = row
    db = MagicMock()
    db.query.return_value = row_query

    with pytest.raises(ApiError) as exc:
        service.update_quick_sales_payment_button(
            db,
            business_id=5,
            button_id=11,
            user_id=9,
            payload={"scope": "business"},
            can_manage_business=False,
        )

    assert exc.value.detail["error"]["code"] == "FORBIDDEN"
    db.commit.assert_not_called()


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


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        ("alt + 1", "ALT+1"),
        ("F3", "F3"),
        ("F12", "F12"),
        ("ctrl+shift+k", "CTRL+SHIFT+K"),
    ],
)
def test_normalize_payment_button_shortcut(raw: str, expected: str) -> None:
    assert _normalize_payment_button_shortcut(raw) == expected


@pytest.mark.parametrize("raw", ["F5", "Enter", "plain text", "Ctrl+"])
def test_normalize_payment_button_shortcut_rejects_invalid_or_reserved(raw: str) -> None:
    with pytest.raises(ApiError):
        _normalize_payment_button_shortcut(raw)


@pytest.mark.parametrize(
    ("raw", "expected"),
    [("alt + 1", "ALT+1"), ("ctrl+alt+r", "CTRL+ALT+R")],
)
def test_normalize_web_payment_button_shortcut(raw: str, expected: str) -> None:
    assert _normalize_payment_button_shortcut(raw, platform="web") == expected


@pytest.mark.parametrize("raw", ["F12", "SHIFT+A", "CTRL+L"])
def test_normalize_web_payment_button_shortcut_rejects_invalid_or_reserved(
    raw: str,
) -> None:
    with pytest.raises(ApiError):
        _normalize_payment_button_shortcut(raw, platform="web")


def test_user_payment_shortcut_conflict_is_scoped_to_current_mapping() -> None:
    with pytest.raises(ApiError) as exc:
        _assert_user_payment_shortcut_available(
            [
                {"id": 11, "effective_shortcut": "F12"},
                {"id": 12, "effective_shortcut": "ALT+R"},
            ],
            shortcut="F12",
            exclude_button_key="12",
        )
    assert exc.value.detail["error"]["code"] == "PAYMENT_BUTTON_SHORTCUT_CONFLICT"


def test_user_payment_shortcut_can_keep_its_own_value() -> None:
    _assert_user_payment_shortcut_available(
        [{"id": 11, "effective_shortcut": "F12"}],
        shortcut="F12",
        exclude_button_key="11",
    )


def test_resolve_shortcuts_inherits_business_default() -> None:
    result, stored = _resolve_user_payment_shortcuts(
        [{"id": 11, "default_shortcut": "F12"}],
        {},
    )

    assert stored == {}
    assert result[0]["effective_shortcut"] == "F12"
    assert result[0]["shortcut_source"] == "business"
    assert result[0]["user_shortcut"] is None


def test_resolve_shortcuts_personal_override_wins() -> None:
    result, _ = _resolve_user_payment_shortcuts(
        [{"id": 11, "default_shortcut": "F12"}],
        {"11": "ALT+R"},
    )

    assert result[0]["effective_shortcut"] == "ALT+R"
    assert result[0]["shortcut_source"] == "user"


def test_resolve_shortcuts_can_disable_inherited_default() -> None:
    result, _ = _resolve_user_payment_shortcuts(
        [{"id": 11, "default_shortcut": "F12"}],
        {"11": PAYMENT_BUTTON_SHORTCUT_DISABLED},
    )

    assert result[0]["effective_shortcut"] is None
    assert result[0]["shortcut_source"] == "disabled"
    assert result[0]["user_shortcut_disabled"] is True


def test_resolve_shortcuts_personal_choice_suppresses_later_conflicting_default() -> None:
    result, _ = _resolve_user_payment_shortcuts(
        [
            {"id": 11, "default_shortcut": "F12"},
            {"id": 12, "default_shortcut": "ALT+R"},
        ],
        {"12": "F12"},
    )

    assert result[0]["effective_shortcut"] is None
    assert result[0]["shortcut_conflict"] is True
    assert result[1]["effective_shortcut"] == "F12"
    assert result[1]["shortcut_source"] == "user"


def test_apply_user_shortcuts_prunes_stale_values_without_copying_defaults(
    monkeypatch,
) -> None:
    from app.services import quick_sales_service as service

    saved = MagicMock()
    monkeypatch.setattr(
        service,
        "get_quick_sales_payment_shortcuts",
        lambda _db, _user_id, _business_id, platform="windows": (
            {"stale": "F9"} if platform == "windows" else {}
        ),
    )
    monkeypatch.setattr(service, "save_quick_sales_payment_shortcuts", saved)
    buttons = [
        {"id": 11, "default_shortcut": "F12"},
        {"id": 12, "default_shortcut": "ALT+R"},
    ]

    result = _apply_user_payment_shortcuts(
        MagicMock(),
        business_id=5,
        user_id=7,
        buttons=buttons,
    )

    assert [row["shortcut"] for row in result] == ["F12", "ALT+R"]
    saved.assert_called_once_with(
        ANY,
        7,
        5,
        {},
        platform="windows",
    )


def test_apply_user_shortcuts_migrates_only_legacy_personal_button(
    monkeypatch,
) -> None:
    from app.services import quick_sales_service as service

    saved = MagicMock()
    monkeypatch.setattr(
        service,
        "get_quick_sales_payment_shortcuts",
        lambda _db, _user_id, _business_id, platform="windows": {},
    )
    monkeypatch.setattr(service, "save_quick_sales_payment_shortcuts", saved)

    result = _apply_user_payment_shortcuts(
        MagicMock(),
        business_id=5,
        user_id=7,
        buttons=[
            {
                "id": 11,
                "default_shortcut": None,
                "legacy_user_shortcut": "ALT+R",
            }
        ],
    )

    assert result[0]["shortcut"] == "ALT+R"
    assert result[0]["shortcut_source"] == "user"
    saved.assert_called_once_with(
        ANY, 7, 5, {"11": "ALT+R"}, platform="windows"
    )


def test_apply_user_shortcuts_respects_explicitly_disabled_default(
    monkeypatch,
) -> None:
    from app.services import quick_sales_service as service

    saved = MagicMock()
    monkeypatch.setattr(
        service,
        "get_quick_sales_payment_shortcuts",
        lambda _db, _user_id, _business_id, platform="windows": (
            {"11": PAYMENT_BUTTON_SHORTCUT_DISABLED}
            if platform == "windows"
            else {}
        ),
    )
    monkeypatch.setattr(service, "save_quick_sales_payment_shortcuts", saved)

    result = _apply_user_payment_shortcuts(
        MagicMock(),
        business_id=5,
        user_id=7,
        buttons=[{"id": 11, "default_shortcut": "F12"}],
    )

    assert result[0]["shortcut"] is None
    saved.assert_not_called()


def test_bulk_default_shortcuts_rejects_duplicate_keys_before_writing() -> None:
    db = MagicMock()

    with pytest.raises(ApiError) as exc:
        set_quick_sales_payment_default_shortcuts(
            db,
            business_id=5,
            items=[
                {"button_id": 11, "shortcut": "F1"},
                {"button_id": 12, "shortcut": "F1"},
            ],
        )

    assert exc.value.detail["error"]["code"] == "PAYMENT_BUTTON_SHORTCUT_CONFLICT"
    db.query.assert_not_called()


def test_bulk_default_shortcuts_rejects_duplicate_web_keys_before_writing() -> None:
    db = MagicMock()

    with pytest.raises(ApiError) as exc:
        set_quick_sales_payment_default_shortcuts(
            db,
            business_id=5,
            items=[
                {
                    "button_id": 11,
                    "shortcuts": {"windows": "F1", "web": "ALT+1"},
                },
                {
                    "button_id": 12,
                    "shortcuts": {"windows": "F2", "web": "ALT+1"},
                },
            ],
        )

    assert exc.value.detail["error"]["code"] == "PAYMENT_BUTTON_SHORTCUT_CONFLICT"
    db.query.assert_not_called()


def test_bulk_default_shortcuts_updates_all_rows_after_validation(
    monkeypatch,
) -> None:
    from app.services import quick_sales_service as service

    first = SimpleNamespace(id=11, shortcut="F1", web_shortcut="ALT+1")
    second = SimpleNamespace(id=12, shortcut=None, web_shortcut="ALT+2")
    query = MagicMock()
    query.filter.return_value.all.side_effect = [
        [first, second],
        [first, second],
    ]
    db = MagicMock()
    db.query.return_value = query
    monkeypatch.setattr(
        service,
        "list_quick_sales_payment_default_shortcuts",
        lambda _db, _business_id: [
            {"button_id": 11, "default_shortcut": first.shortcut},
            {"button_id": 12, "default_shortcut": second.shortcut},
        ],
    )

    result = set_quick_sales_payment_default_shortcuts(
        db,
        business_id=5,
        items=[
            {"button_id": 11, "shortcut": "F2"},
            {"button_id": 12, "shortcut": "ALT+R"},
        ],
    )

    assert first.shortcut == "F2"
    assert second.shortcut == "ALT+R"
    assert first.web_shortcut == "ALT+1"
    assert second.web_shortcut == "ALT+2"
    assert result[1]["default_shortcut"] == "ALT+R"
    db.flush.assert_called_once_with()
