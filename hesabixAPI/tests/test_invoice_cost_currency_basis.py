from decimal import Decimal
from types import SimpleNamespace

import pytest

from app.core.responses import ApiError
from app.services.invoice_profit_costing import inventory_line_unit_cost_main_base


def _cost(basis):
    info = {"cost_price": "100"}
    if basis is not None:
        info["cost_currency_basis"] = basis
    return inventory_line_unit_cost_main_base(
        SimpleNamespace(main_unit="unit"), info, Decimal("1"),
        document_type="invoice_purchase", fx_rate=Decimal("10"),
    )


@pytest.mark.parametrize("basis,expected", [(None, "1000"), ("document", "1000"), ("base", "100")])
def test_cost_currency_basis(basis, expected):
    assert _cost(basis) == Decimal(expected)


def test_invalid_cost_currency_basis():
    with pytest.raises(ApiError) as caught:
        _cost("invalid")
    assert (caught.value.code, caught.value.status_code) == ("INVALID_COST_CURRENCY_BASIS", 422)
