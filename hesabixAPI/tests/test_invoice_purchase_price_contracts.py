from datetime import date, datetime
from decimal import Decimal
from types import SimpleNamespace

import pytest

from adapters.api.v1.schemas import BusinessUpdateRequest
from app.core.responses import ApiError
from app.services.invoice_product_price_sync_service import (
    POLICY_HIGHEST_PRICE,
    POLICY_LAST_LINE,
    POLICY_LOWEST_PRICE,
    POLICY_WEIGHTED_AVERAGE,
    _select_multi_line_price,
    _source_is_newer_than_document,
    _to_main_unit_price,
)
from app.services.invoice_purchase_price_snapshot_service import (
    _snapshot_value_for_line,
    purchase_price_unit_cost_base_from_snapshot,
    resolve_missing_purchase_price_unit_cost,
)
from app.services.invoice_unit_conversion_service import (
    price_line_to_main,
    price_main_to_line,
    quantity_line_to_main,
)


def _product(*, purchase_price=Decimal("2000")):
    return SimpleNamespace(
        main_unit="کارتن",
        secondary_unit="عدد",
        unit_conversion_factor=Decimal("20"),
        base_purchase_price=purchase_price,
    )


def _line(*, unit="عدد", cost_price=None):
    info = {"unit": unit}
    if cost_price is not None:
        info["cost_price"] = cost_price
    return SimpleNamespace(extra_info=info)


def test_unit_conversion_contract_is_secondary_units_per_main_unit():
    product = _product()
    assert quantity_line_to_main(Decimal("20"), product, "عدد") == Decimal("1")
    assert price_main_to_line(Decimal("2000"), product, "عدد") == Decimal("100")
    assert price_line_to_main(Decimal("100"), product, "عدد") == Decimal("2000")
    assert _to_main_unit_price(Decimal("100"), product, "عدد") == Decimal("2000.00")


def test_purchase_price_snapshot_is_base_currency_price_on_line_unit():
    value, source, unit, factor = _snapshot_value_for_line(
        _product(),
        _line(unit="عدد"),
        "block_calculation",
    )
    assert value == Decimal("100")
    assert source == "product_base_purchase_price"
    assert unit == "عدد"
    assert factor == Decimal("20")


def test_missing_purchase_price_policies_are_explicit():
    assert resolve_missing_purchase_price_unit_cost(_line(), "zero_cost") == Decimal("0")
    assert resolve_missing_purchase_price_unit_cost(
        _line(cost_price="125.5"), "use_line_cost_price"
    ) == Decimal("125.5")
    with pytest.raises(ApiError):
        resolve_missing_purchase_price_unit_cost(_line(), "use_line_cost_price")
    with pytest.raises(ApiError):
        resolve_missing_purchase_price_unit_cost(_line(), "block_calculation")


def test_snapshot_currency_must_match_current_business_base_currency():
    line = SimpleNamespace(
        purchase_price_snapshot_unit_cost_base=Decimal("100"),
        purchase_price_snapshot_currency_id=1,
    )
    assert purchase_price_unit_cost_base_from_snapshot(
        line,
        missing_policy="zero_cost",
        expected_base_currency_id=1,
    ) == Decimal("100")
    with pytest.raises(ApiError):
        purchase_price_unit_cost_base_from_snapshot(
            line,
            missing_policy="zero_cost",
            expected_base_currency_id=2,
        )


def test_purchase_multi_line_policies_are_deterministic():
    candidates = [
        (10, Decimal("100"), Decimal("2")),
        (11, Decimal("200"), Decimal("1")),
    ]
    assert _select_multi_line_price(candidates, POLICY_WEIGHTED_AVERAGE) == Decimal("133.33")
    assert _select_multi_line_price(candidates, POLICY_LAST_LINE) == Decimal("200")
    assert _select_multi_line_price(candidates, POLICY_HIGHEST_PRICE) == Decimal("200")
    assert _select_multi_line_price(candidates, POLICY_LOWEST_PRICE) == Decimal("100")


def test_older_purchase_invoice_cannot_replace_newer_synced_source():
    product = SimpleNamespace(
        base_purchase_price_sync_meta={
            "document_id": 20,
            "document_date": "2026-10-20",
            "registered_at": "2026-10-20T12:00:00",
        }
    )
    older = SimpleNamespace(
        id=10,
        document_date=date(2026, 10, 19),
        registered_at=datetime(2026, 10, 19, 12, 0),
    )
    same_source = SimpleNamespace(
        id=20,
        document_date=date(2026, 10, 20),
        registered_at=datetime(2026, 10, 20, 12, 0),
    )
    assert _source_is_newer_than_document(product, older) is True
    assert _source_is_newer_than_document(product, same_source) is False


def test_business_settings_validate_new_policies():
    payload = BusinessUpdateRequest(
        invoice_profit_missing_purchase_price_policy="block_calculation",
        invoice_sync_purchase_price_multi_line_policy="weighted_average",
    )
    assert payload.invoice_profit_missing_purchase_price_policy == "block_calculation"
    assert payload.invoice_sync_purchase_price_multi_line_policy == "weighted_average"

    with pytest.raises(ValueError):
        BusinessUpdateRequest(invoice_profit_missing_purchase_price_policy="guess")
    with pytest.raises(ValueError):
        BusinessUpdateRequest(invoice_sync_purchase_price_multi_line_policy="random")
