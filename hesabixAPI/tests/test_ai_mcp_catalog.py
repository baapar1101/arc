"""Tenant-bound MCP tools for product bundles, price lists, and categories."""
from __future__ import annotations

from types import SimpleNamespace
from unittest.mock import MagicMock, patch

import pytest

from app.core.responses import ApiError
from app.services.ai.ai_function_extensions_mcp_bundles import (
    CREATE_PRODUCT_BUNDLE_SCHEMA,
    create_product_bundle_handler,
    delete_product_bundle_handler,
    expand_product_bundle_handler,
    get_product_bundle_handler,
    search_product_bundles_handler,
)
from app.services.ai.ai_function_extensions_mcp_categories import (
    CREATE_PRODUCT_CATEGORY_SCHEMA,
    create_product_category_handler,
    delete_product_category_handler,
    get_product_category_tree_handler,
    move_product_category_handler,
    update_product_category_handler,
)
from app.services.ai.ai_function_extensions_mcp_price_lists import (
    CREATE_PRICE_LIST_SCHEMA,
    UPSERT_PRICE_LIST_ITEM_SCHEMA,
    create_price_list_handler,
    delete_price_list_handler,
    delete_price_list_item_handler,
    get_price_list_handler,
    upsert_price_list_item_handler,
)
from app.services.ai.ai_tool_catalog_quality import parse_registered_tool_fields
from app.services.ai.ai_tool_manifest import get_manifest_entry
from app.services.ai.ai_write_guard import is_write_function

CATALOG_TOOLS = (
    "search_product_bundles",
    "get_product_bundle",
    "create_product_bundle",
    "update_product_bundle",
    "delete_product_bundle",
    "expand_product_bundle",
    "get_price_list",
    "create_price_list",
    "update_price_list",
    "delete_price_list",
    "upsert_price_list_item",
    "delete_price_list_item",
    "get_product_category_tree",
    "create_product_category",
    "update_product_category",
    "move_product_category",
    "delete_product_category",
)
ALWAYS_CONFIRM = (
    "delete_product_bundle",
    "delete_price_list",
    "delete_price_list_item",
    "delete_product_category",
)


def _ctx(*, business_id: int = 7, user_id: int = 9, db=None):
    user = MagicMock()
    user.get_user_id.return_value = user_id
    return {
        "db": db if db is not None else MagicMock(),
        "business_id": business_id,
        "user_context": user,
    }


def _assert_no_extra_blob(schema: dict) -> None:
    assert schema.get("additionalProperties") is False
    props = schema.get("properties") or {}
    assert "extra_info" not in props
    assert "business_id" not in props


def test_catalog_tools_are_registered_with_strict_schemas():
    parsed = parse_registered_tool_fields()
    for name in CATALOG_TOOLS:
        assert name in parsed, name
        fields = parsed[name]
        if fields["is_readonly"]:
            assert fields["requires_approval"] is False
        else:
            assert fields["requires_approval"] is True
            assert fields["is_readonly"] is False

    create = parsed["create_product_bundle"]
    assert create["required_permissions"] == ["products.write"]
    assert CREATE_PRODUCT_BUNDLE_SCHEMA["required"] == ["name", "items"]
    items = CREATE_PRODUCT_BUNDLE_SCHEMA["properties"]["items"]
    assert items["maxItems"] == 500
    assert items["items"]["additionalProperties"] is False
    assert items["items"]["properties"]["quantity"]["exclusiveMinimum"] == 0
    _assert_no_extra_blob(CREATE_PRODUCT_BUNDLE_SCHEMA)
    assert parsed["delete_product_bundle"]["required_permissions"] == ["products.delete"]
    assert parsed["delete_product_bundle"]["risk_level"] == "high"
    assert parsed["expand_product_bundle"]["is_readonly"] is True
    assert parsed["search_product_bundles"]["is_readonly"] is True

    assert parsed["create_price_list"]["required_permissions"] == ["price_lists.write"]
    assert parsed["delete_price_list"]["required_permissions"] == ["price_lists.delete"]
    assert CREATE_PRICE_LIST_SCHEMA["required"] == ["name"]
    _assert_no_extra_blob(CREATE_PRICE_LIST_SCHEMA)
    _assert_no_extra_blob(UPSERT_PRICE_LIST_ITEM_SCHEMA)
    assert UPSERT_PRICE_LIST_ITEM_SCHEMA["required"] == [
        "price_list_id",
        "product_id",
        "currency_id",
        "price",
    ]

    assert parsed["create_product_category"]["required_permissions"] == ["categories.write"]
    assert parsed["delete_product_category"]["required_permissions"] == ["categories.delete"]
    assert parsed["get_product_category_tree"]["is_readonly"] is True
    _assert_no_extra_blob(CREATE_PRODUCT_CATEGORY_SCHEMA)
    assert CREATE_PRODUCT_CATEGORY_SCHEMA["required"] == ["label"]


def test_manifest_marks_catalog_writes_and_companions():
    for name in CATALOG_TOOLS:
        entry = get_manifest_entry(name)
        assert entry is not None, name
        assert entry.capability == "inventory.product"
    for name in ALWAYS_CONFIRM:
        entry = get_manifest_entry(name)
        assert entry is not None and entry.always_confirm is True and entry.intent_write is True, name
    assert get_manifest_entry("delete_product_bundle").side_effect == "delete"
    assert get_manifest_entry("delete_price_list_item").side_effect == "delete"
    assert get_manifest_entry("expand_product_bundle").intent_write is False
    lists = get_manifest_entry("list_price_lists")
    assert "create_price_list" in (lists.companion_tools if lists else ())
    cats = get_manifest_entry("search_categories")
    assert "create_product_category" in (cats.companion_tools if cats else ())
    bundles = get_manifest_entry("search_product_bundles")
    assert "create_product_bundle" in (bundles.companion_tools if bundles else ())
    assert is_write_function("create_product_bundle") is True
    assert is_write_function("expand_product_bundle") is False
    assert is_write_function("get_price_list") is False


def test_bundle_writes_pin_tenant_and_omit_extra():
    with patch(
        "app.services.product_bundle_service.create_bundle",
        return_value={"id": 4, "name": "پک فروش", "items": []},
    ) as create:
        out = create_product_bundle_handler(
            {
                "name": "پک فروش",
                "items": [{"product_id": 2, "quantity": 3}],
                "business_id": 99,
                "extra_info": {"x": 1},
            },
            _ctx(),
        )
    assert out["id"] == 4
    assert create.call_args.args[1] == 7
    body = create.call_args.args[2]
    assert body.name == "پک فروش"
    assert len(body.items) == 1
    assert not hasattr(body, "extra_info") or getattr(body, "extra_info", None) is None

    with patch(
        "app.services.product_bundle_service.get_bundle",
        return_value=None,
    ):
        with pytest.raises(ValueError, match="کسب‌وکار متصل"):
            get_product_bundle_handler({"bundle_id": 4}, _ctx())

    with patch(
        "app.services.product_bundle_service.delete_bundle",
        return_value=False,
    ):
        with pytest.raises(ValueError, match="کسب‌وکار متصل"):
            delete_product_bundle_handler({"bundle_id": 4}, _ctx())

    with patch(
        "app.services.product_bundle_service.search_bundles",
        return_value={"items": [], "pagination": {"total": 0}},
    ) as search:
        search_product_bundles_handler({"search": "پک", "take": 20}, _ctx())
    assert search.call_args.args[1] == 7


def test_expand_bundle_is_readonly_and_converts_api_error():
    with patch(
        "app.services.product_bundle_service.expand_bundle",
        side_effect=ApiError("BUNDLE_INACTIVE", "باندل غیرفعال است.", http_status=409),
    ):
        with pytest.raises(ValueError, match="غیرفعال"):
            expand_product_bundle_handler({"bundle_id": 4, "quantity": 2}, _ctx())

    with patch(
        "app.services.product_bundle_service.expand_bundle",
        return_value={"bundle_id": 4, "quantity": 2, "items": []},
    ) as expand:
        expand_product_bundle_handler({"bundle_id": 4, "quantity": 2}, _ctx())
    assert expand.call_args.args[1] == 7
    assert expand.call_args.args[2] == 4


def test_price_list_writes_pin_tenant():
    with patch(
        "app.services.price_list_service.create_price_list",
        return_value={"message": "PRICE_LIST_CREATED", "data": {"id": 3, "name": "عمده"}},
    ) as create:
        out = create_price_list_handler({"name": "عمده", "business_id": 99}, _ctx())
    assert out == {"id": 3, "name": "عمده"}
    assert create.call_args.args[1] == 7

    with patch(
        "app.services.price_list_service.get_price_list",
        return_value=None,
    ):
        with pytest.raises(ValueError, match="کسب‌وکار متصل"):
            get_price_list_handler({"price_list_id": 3}, _ctx())

    with patch(
        "app.services.price_list_service.delete_price_list",
        return_value=False,
    ):
        with pytest.raises(ValueError, match="کسب‌وکار متصل"):
            delete_price_list_handler({"price_list_id": 3}, _ctx())

    with patch(
        "app.services.price_list_service.upsert_price_item",
        return_value={"message": "PRICE_ITEM_UPSERTED", "data": {"id": 9, "price": 1000}},
    ) as upsert:
        out = upsert_price_list_item_handler(
            {
                "price_list_id": 3,
                "product_id": 2,
                "currency_id": 1,
                "price": 1000,
                "business_id": 99,
            },
            _ctx(),
        )
    assert out["id"] == 9
    assert upsert.call_args.args[1] == 7
    assert upsert.call_args.args[2] == 3

    with patch(
        "app.services.price_list_service.delete_price_item",
        return_value=False,
    ):
        with pytest.raises(ValueError, match="کسب‌وکار متصل"):
            delete_price_list_item_handler({"item_id": 9}, _ctx())


def test_category_tree_and_writes_pin_tenant():
    db = MagicMock()
    local = SimpleNamespace(
        id=5,
        business_id=7,
        parent_id=None,
        title_translations={"fa": "خوراکی"},
        description=None,
        sort_order=0,
    )
    foreign = SimpleNamespace(id=8, business_id=99, parent_id=None, title_translations={})

    def getter(_model, pk):
        if int(pk) == 5:
            return local
        if int(pk) == 8:
            return foreign
        return None

    db.get.side_effect = getter

    with patch(
        "adapters.db.repositories.category_repository.CategoryRepository.get_tree",
        return_value=[{"id": 5, "parent_id": None, "title": "خوراکی", "children": []}],
    ):
        tree = get_product_category_tree_handler({}, _ctx(db=db))
    assert tree["items"][0]["label"] == "خوراکی"
    assert tree["items"][0]["id"] == 5

    with pytest.raises(ValueError, match="کسب‌وکار متصل"):
        create_product_category_handler({"label": "خوراکی", "parent_id": 8}, _ctx(db=db))

    with patch(
        "adapters.db.repositories.category_repository.CategoryRepository.create_category",
        return_value=local,
    ) as create:
        out = create_product_category_handler(
            {"label": "خوراکی", "business_id": 99},
            _ctx(db=db),
        )
    assert out["id"] == 5
    assert create.call_args.kwargs["business_id"] == 7

    with pytest.raises(ValueError, match="کسب‌وکار متصل"):
        update_product_category_handler({"category_id": 8, "label": "دیگر"}, _ctx(db=db))
    with pytest.raises(ValueError, match="کسب‌وکار متصل"):
        delete_product_category_handler({"category_id": 8}, _ctx(db=db))
    with pytest.raises(ValueError, match="کسب‌وکار متصل"):
        move_product_category_handler({"category_id": 5, "new_parent_id": 8}, _ctx(db=db))
