"""قرارداد دوگانهٔ handler رجیستری — (args, context) در برابر (db, **kwargs)."""
from __future__ import annotations

from unittest.mock import MagicMock

from app.services.ai.ai_handler_convention import (
    handler_uses_args_context,
    kwargs_for_old_style_handler,
    wrap_registry_service_func,
)


class _Ctx:
    def get_user_id(self) -> int:
        return 7

    def can_access_business(self, _bid) -> bool:
        return True

    def get_calendar_type(self) -> str:
        return "jalali"


def test_handler_uses_args_context_detects_new_convention():
    def new_style(args, context):
        return args

    def old_style(db, business_id=None, user_id=None, **kwargs):
        return kwargs

    assert handler_uses_args_context(new_style) is True
    assert handler_uses_args_context(old_style) is False


def test_create_handler_does_not_pass_db_to_args_context_fn():
    """باگ لاگ: create_session_plan_handler() got an unexpected keyword argument 'db'."""
    seen = {}

    def create_session_plan_handler(args, context):
        seen["args"] = dict(args)
        seen["has_db"] = "db" in context
        return {"success": True, "items": args.get("items")}

    handler = wrap_registry_service_func(create_session_plan_handler)
    result = handler(
        {"items": [{"title": "گزارش فروش"}]},
        {
            "db": MagicMock(),
            "user_context": _Ctx(),
            "business_id": 1,
            "session_id": 42,
        },
    )
    assert result["success"] is True
    assert result["items"][0]["title"] == "گزارش فروش"
    assert seen["has_db"] is True
    assert "db" not in seen["args"]


def test_create_handler_old_style_still_gets_db_kwarg():
    seen = {}

    def search_wrapper(db=None, business_id=None, user_id=None, query="", **kwargs):
        seen["db"] = db
        seen["query"] = query
        seen["user_id"] = user_id
        return {"ok": True, "query": query}

    handler = wrap_registry_service_func(search_wrapper)
    result = handler(
        {"query": "فروش"},
        {
            "db": object(),
            "user_context": _Ctx(),
            "business_id": 3,
        },
    )
    assert result["ok"] is True
    assert seen["db"] is not None
    assert seen["query"] == "فروش"
    assert seen["user_id"] == 7


def test_kwargs_for_old_style_drops_unexpected_user_id():
    def get_product(db, product_id, business_id):
        return (product_id, business_id)

    kwargs = kwargs_for_old_style_handler(
        get_product,
        {"product_id": 4, "business_id": 2, "user_id": 99, "db": object()},
    )
    assert kwargs == {"product_id": 4, "business_id": 2}


def test_wrap_does_not_pass_user_id_to_get_product_style_handler():
    seen = {}

    def get_product(db, product_id: int, business_id: int):
        seen["product_id"] = product_id
        seen["business_id"] = business_id
        seen["db"] = db
        return {"id": product_id}

    handler = wrap_registry_service_func(get_product)
    result = handler(
        {"product_id": 44},
        {
            "db": object(),
            "user_context": _Ctx(),
            "business_id": 8,
        },
    )
    assert result["id"] == 44
    assert seen["product_id"] == 44
    assert seen["business_id"] == 8


def test_wrap_clamps_take_above_queryinfo_max():
    seen = {}

    def search_wrapper(db=None, business_id=None, user_id=None, take=None, **kwargs):
        seen["take"] = take
        return {"take": take}

    handler = wrap_registry_service_func(search_wrapper)
    result = handler(
        {"take": 1000},
        {"db": object(), "user_context": _Ctx(), "business_id": 1},
    )
    assert result["take"] == 100
    assert seen["take"] == 100
