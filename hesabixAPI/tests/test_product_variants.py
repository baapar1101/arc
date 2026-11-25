"""Unit tests for product inventory variants (additive, default-off)."""

from decimal import Decimal
from types import SimpleNamespace
from unittest.mock import MagicMock

from app.services.product_attribute_option_service import normalize_option_label
from app.services.product_variant_service import (
    VARIANT_MODE_INVENTORY,
    VARIANT_MODE_NONE,
    build_combination_key,
    is_variant_inventory_product,
)
from app.services.variant_allocation_service import (
    parse_payload_allocations,
    validate_allocation_sum,
)
from app.services.variant_inventory_service import expand_outgoing_shortage_requirements


def test_combination_key_is_sorted_and_stable() -> None:
    assert build_combination_key([(12, 4), (3, 9)]) == "3:9|12:4"
    assert build_combination_key([(3, 9), (12, 4)]) == "3:9|12:4"


def test_option_label_normalization_unifies_yeh_kaf() -> None:
    assert normalize_option_label("  آبي  ") == "آبی"
    assert normalize_option_label("كفش") == "کفش"


def test_allocation_sum_accepts_split_purchase() -> None:
    validate_allocation_sum(
        Decimal("100"),
        [
            (1, Decimal("30"), None),
            (2, Decimal("20"), None),
            (3, Decimal("25"), None),
            (4, Decimal("25"), None),
        ],
    )


def test_parse_allocations_from_extra_info() -> None:
    items = parse_payload_allocations(
        {"extra_info": {"allocations": [{"variant_id": 7, "quantity": "2"}]}}
    )
    assert items[0]["variant_id"] == 7


def test_simple_product_is_not_inventory_variant() -> None:
    product = SimpleNamespace(variant_mode=None)
    assert is_variant_inventory_product(product) is False
    product.variant_mode = VARIANT_MODE_NONE
    assert is_variant_inventory_product(product) is False
    product.variant_mode = VARIANT_MODE_INVENTORY
    assert is_variant_inventory_product(product) is True


def test_expand_shortages_keeps_simple_product_at_product_level() -> None:
    product = SimpleNamespace(
        variant_mode="none",
        inventory_mode="bulk",
        main_unit="عدد",
        secondary_unit=None,
        unit_conversion_factor=None,
    )
    required, lock_keys = expand_outgoing_shortage_requirements(
        MagicMock(),
        17,
        [{"product_id": 1, "quantity": 3, "extra_info": {"warehouse_id": 9}}],
        {1: product},
    )
    assert lock_keys == []
    assert required[(1, 9, None)] == Decimal("3")


def test_expand_shortages_splits_variant_keys() -> None:
    product = SimpleNamespace(
        variant_mode="inventory",
        inventory_mode="bulk",
        main_unit="عدد",
        secondary_unit=None,
        unit_conversion_factor=None,
    )
    required, lock_keys = expand_outgoing_shortage_requirements(
        MagicMock(),
        17,
        [
            {
                "product_id": 1,
                "quantity": 5,
                "allocations": [
                    {"variant_id": 11, "quantity": 3},
                    {"variant_id": 12, "quantity": 2},
                ],
                "extra_info": {"warehouse_id": 9},
            }
        ],
        {1: product},
    )
    assert required[(1, 9, 11)] == Decimal("3")
    assert required[(1, 9, 12)] == Decimal("2")
    assert (9, 1, 11) in lock_keys
    assert (9, 1, 12) in lock_keys


def test_carton_piece_variant_allocation_converts_to_main() -> None:
    product = SimpleNamespace(
        variant_mode="inventory",
        inventory_mode="bulk",
        main_unit="کارتن",
        secondary_unit="عدد",
        unit_conversion_factor=Decimal("10"),
    )
    required, _ = expand_outgoing_shortage_requirements(
        MagicMock(),
        17,
        [
            {
                "product_id": 1,
                "quantity": 20,
                "allocations": [{"variant_id": 4, "quantity": 20}],
                "extra_info": {"warehouse_id": 9, "unit": "عدد"},
            }
        ],
        {1: product},
    )
    assert required[(1, 9, 4)] == Decimal("2")
