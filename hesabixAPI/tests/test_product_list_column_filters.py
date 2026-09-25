"""Unit tests for product list DataTable column filter helpers."""

from __future__ import annotations

from adapters.db.models.product import Product, ProductItemType
from adapters.db.repositories.product_list_filters import (
    _as_str,
    _bool_condition,
    _filter_parts,
    _like_escape,
    _numeric_condition,
    _parse_bool_filter_value,
    _parse_item_type_filter_value,
    _text_condition,
)


def test_filter_parts_from_dict_and_object() -> None:
    field, op, value = _filter_parts({"property": "name", "operator": "*", "value": "آب"})
    assert field == "name"
    assert op == "*"
    assert value == "آب"

    class _F:
        property = "code"
        operator = "*?"
        value = "P-"

    field2, op2, value2 = _filter_parts(_F())
    assert (field2, op2, value2) == ("code", "*?", "P-")


def test_like_escape_protects_wildcards() -> None:
    assert _like_escape(r"a%b_c\d") == r"a\%b\_c\\d"


def test_text_condition_datatable_operators() -> None:
    contains = _text_condition(Product.name, "*", "شیر")
    starts = _text_condition(Product.name, "*?", "شیر")
    ends = _text_condition(Product.name, "?*", "شیر")
    exact = _text_condition(Product.name, "=", "شیر کامل")
    ignored = _text_condition(Product.name, "*", "   ")

    assert contains is not None
    assert starts is not None
    assert ends is not None
    assert exact is not None
    assert ignored is None

    contains_sql = str(contains.compile(compile_kwargs={"literal_binds": True}))
    starts_sql = str(starts.compile(compile_kwargs={"literal_binds": True}))
    ends_sql = str(ends.compile(compile_kwargs={"literal_binds": True}))
    assert "%شیر%" in contains_sql
    assert "شیر%" in starts_sql
    assert "%شیر" in ends_sql


def test_text_condition_legacy_contains_still_works() -> None:
    cond = _text_condition(Product.name, "contains", "آب میوه")
    assert cond is not None
    sql = str(cond.compile(compile_kwargs={"literal_binds": True}))
    assert "آب" in sql
    assert "میوه" in sql


def test_item_type_exact_accepts_fa_and_en() -> None:
    assert _parse_item_type_filter_value("product") == ProductItemType.PRODUCT
    assert _parse_item_type_filter_value("کالا") == ProductItemType.PRODUCT
    assert _parse_item_type_filter_value("service") == ProductItemType.SERVICE
    assert _parse_item_type_filter_value("خدمت") == ProductItemType.SERVICE
    assert _parse_item_type_filter_value("کا") is None


def test_bool_filter_labels() -> None:
    assert _parse_bool_filter_value("بله") is True
    assert _parse_bool_filter_value("خیر") is False
    assert _parse_bool_filter_value("yes") is True
    assert _parse_bool_filter_value("false") is False
    assert _bool_condition(Product.track_inventory, "*", "بله") is not None
    assert _bool_condition(Product.track_inventory, "=", "maybe") is None


def test_numeric_condition_equality_and_contains() -> None:
    eq = _numeric_condition(Product.base_sales_price, "=", "1000")
    assert eq is not None
    contains = _numeric_condition(Product.base_sales_price, "*", "100")
    assert contains is not None
    gt = _numeric_condition(Product.reorder_point, ">", "5")
    assert gt is not None
    eq_sql = str(eq.compile(compile_kwargs={"literal_binds": True}))
    assert "1000" in eq_sql
    contains_sql = str(contains.compile(compile_kwargs={"literal_binds": True}))
    assert "%100%" in contains_sql


def test_as_str_trims() -> None:
    assert _as_str("  x  ") == "x"
    assert _as_str(None) == ""


def test_apply_name_contains_filter_adds_where() -> None:
    from sqlalchemy import select
    from adapters.db.repositories.product_list_filters import _apply_product_list_filters

    stmt = select(Product)
    filtered = _apply_product_list_filters(
        stmt,
        [{"property": "name", "operator": "*", "value": "شیر"}],
        business_id=1,
    )
    sql = str(filtered.compile(compile_kwargs={"literal_binds": True}))
    assert "شیر" in sql
    assert "LIKE" in sql.upper() or "ILIKE" in sql.upper()


def test_unknown_filter_property_is_ignored() -> None:
    from sqlalchemy import select
    from adapters.db.repositories.product_list_filters import _apply_product_list_filters

    stmt = select(Product)
    filtered = _apply_product_list_filters(
        stmt,
        [{"property": "not_a_real_field", "operator": "*", "value": "x"}],
        business_id=1,
    )
    # بدون where اضافه برای فیلد ناشناخته
    assert filtered.whereclause is None
