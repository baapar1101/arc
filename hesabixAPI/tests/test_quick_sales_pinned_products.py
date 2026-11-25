from __future__ import annotations

from types import SimpleNamespace
from unittest.mock import MagicMock

import pytest

from app.core.responses import ApiError
from app.services.quick_sales_service import (
    _normalize_pinned_product_ids_payload,
    list_quick_sales_pinned_products,
    set_quick_sales_pinned_products,
)
from app.services.user_ui_preferences_service import (
    MAX_QUICK_SALES_PINNED_PRODUCTS_PER_BUSINESS,
    _normalize_quick_sales_pinned_products,
    get_user_ui_preferences,
    save_user_ui_preferences,
)


def test_normalize_pinned_products_keeps_order_and_dedupes() -> None:
    result = _normalize_quick_sales_pinned_products(
        {
            "12": [4, "4", 9, 0, "x", 9, 2],
            "bad": [1],
            "-3": [1],
        }
    )
    assert result == {"12": [4, 9, 2]}


def test_normalize_pinned_products_caps_length() -> None:
    ids = list(range(1, 20))
    result = _normalize_quick_sales_pinned_products({"8": ids})
    assert result["8"] == list(range(1, MAX_QUICK_SALES_PINNED_PRODUCTS_PER_BUSINESS + 1))


def test_generic_preference_update_preserves_pinned_products() -> None:
    row = SimpleNamespace(
        preferences={
            "business_panel_navigation": "single",
            "business_panel_sidebar_tab_behavior": "reuse_across_tabs",
            "business_panel_tabs": {},
            "quick_sales_payment_shortcuts": {
                "4952": {"windows": {"17": "F12"}}
            },
            "quick_sales_pinned_products": {"4952": [11, 8]},
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
    assert result["quick_sales_pinned_products"] == {"4952": [11, 8]}
    assert result["quick_sales_payment_shortcuts"] == {
        "4952": {"windows": {"17": "F12"}}
    }
    assert row.preferences["quick_sales_pinned_products"] == {"4952": [11, 8]}


def test_saving_pinned_products_is_isolated_per_user() -> None:
    rows = {
        7: SimpleNamespace(
            preferences={
                "business_panel_navigation": "single",
                "business_panel_sidebar_tab_behavior": "reuse_across_tabs",
                "business_panel_tabs": {},
                "quick_sales_pinned_products": {"3": [1, 2]},
            },
            updated_at=None,
        ),
        8: SimpleNamespace(
            preferences={
                "business_panel_navigation": "single",
                "business_panel_sidebar_tab_behavior": "reuse_across_tabs",
                "business_panel_tabs": {},
                "quick_sales_pinned_products": {"3": [9]},
            },
            updated_at=None,
        ),
    }

    def _first_for_user(user_id: int):
        db = MagicMock()
        db.query.return_value.filter.return_value.first.return_value = rows[user_id]
        return get_user_ui_preferences(db, user_id=user_id)

    user_seven = _first_for_user(7)
    user_eight = _first_for_user(8)
    assert user_seven["quick_sales_pinned_products"] == {"3": [1, 2]}
    assert user_eight["quick_sales_pinned_products"] == {"3": [9]}


def test_get_preferences_returns_empty_pinned_map_by_default() -> None:
    db = MagicMock()
    db.query.return_value.filter.return_value.first.return_value = None
    result = get_user_ui_preferences(db, user_id=7)
    assert result.get("quick_sales_pinned_products", {}) == {}


def test_normalize_payload_rejects_over_limit() -> None:
    with pytest.raises(ApiError) as exc:
        _normalize_pinned_product_ids_payload(list(range(1, 14)))
    assert exc.value.code == "PINNED_PRODUCTS_LIMIT"


def test_set_pinned_products_rejects_missing_and_inactive(monkeypatch: pytest.MonkeyPatch) -> None:
    db = MagicMock()
    db.query.return_value.filter.return_value.all.return_value = [(1, True), (2, False)]

    with pytest.raises(ApiError) as missing:
        set_quick_sales_pinned_products(
            db,
            business_id=4,
            user_id=7,
            product_ids=[1, 99],
        )
    assert missing.value.code == "PRODUCT_NOT_FOUND"

    with pytest.raises(ApiError) as inactive:
        set_quick_sales_pinned_products(
            db,
            business_id=4,
            user_id=7,
            product_ids=[1, 2],
        )
    assert inactive.value.code == "PRODUCT_INACTIVE"


def test_set_pinned_products_saves_deduped_order(monkeypatch: pytest.MonkeyPatch) -> None:
    db = MagicMock()
    db.query.return_value.filter.return_value.all.return_value = [(4, True), (8, True)]
    saved: dict[str, list[int]] = {}

    def _save(_db, user_id, business_id, ids):
        saved["user_id"] = user_id
        saved["business_id"] = business_id
        saved["ids"] = list(ids)
        return list(ids)

    monkeypatch.setattr(
        "app.services.quick_sales_service.save_quick_sales_pinned_product_ids",
        _save,
    )
    monkeypatch.setattr(
        "app.services.quick_sales_service.list_quick_sales_pinned_products",
        lambda *args, **kwargs: {
            "product_ids": saved["ids"],
            "items": [],
            "max_count": MAX_QUICK_SALES_PINNED_PRODUCTS_PER_BUSINESS,
        },
    )

    result = set_quick_sales_pinned_products(
        db,
        business_id=4,
        user_id=7,
        product_ids=[8, 4, 8],
    )
    assert saved == {"user_id": 7, "business_id": 4, "ids": [8, 4]}
    assert result["product_ids"] == [8, 4]


def test_list_pinned_products_skips_inactive_and_keeps_order(monkeypatch: pytest.MonkeyPatch) -> None:
    db = MagicMock()
    monkeypatch.setattr(
        "app.services.user_ui_preferences_service.get_quick_sales_pinned_product_ids",
        lambda *_args, **_kwargs: [5, 8, 3],
    )
    products = {
        5: {"id": 5, "name": "نان", "is_active": True},
        8: {"id": 8, "name": "شیر", "is_active": False},
        3: {"id": 3, "name": "تخم‌مرغ", "is_active": True},
    }

    def _get_product(_db, product_id, _business_id):
        return products.get(product_id)

    monkeypatch.setattr(
        "app.services.product_service.get_product",
        _get_product,
    )
    monkeypatch.setattr(
        "app.services.quick_sales_service.get_quick_sales_pinned_product_ids",
        lambda *_args, **_kwargs: [5, 8, 3],
    )

    result = list_quick_sales_pinned_products(db, business_id=4, user_id=7)
    assert [item["id"] for item in result["items"]] == [5, 3]
    assert result["product_ids"] == [5, 8, 3]
    assert result["max_count"] == MAX_QUICK_SALES_PINNED_PRODUCTS_PER_BUSINESS
