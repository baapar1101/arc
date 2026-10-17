from unittest.mock import MagicMock
import inspect

import pytest

from app.core.responses import ApiError
from app.services.invoice_service import (
    _canonicalize_quick_sale_line_amounts,
    _extract_totals_from_lines,
)


def test_quick_sale_line_money_is_rebuilt_from_canonical_inputs() -> None:
    lines = [
        {
            "product_id": 7,
            "quantity": 2,
            "extra_info": {
                "unit_price": 100,
                "discount_type": "percent",
                "discount_value": 10,
                "tax_rate": 10,
                # مقادیر جعلی که نباید وارد سند شوند.
                "line_discount": 199,
                "tax_amount": 9000,
                "line_total": 1,
            },
        }
    ]

    _canonicalize_quick_sale_line_amounts(lines)
    totals = _extract_totals_from_lines(lines)

    assert lines[0]["extra_info"]["line_discount"] == 20
    assert lines[0]["extra_info"]["tax_amount"] == 18
    assert lines[0]["extra_info"]["line_total"] == 198
    assert float(totals["net"]) == 198


def test_quick_sale_line_rejects_discount_above_line_gross() -> None:
    lines = [
        {
            "product_id": 7,
            "quantity": 1,
            "extra_info": {
                "unit_price": 100,
                "discount_type": "amount",
                "discount_value": 101,
                "tax_rate": 0,
            },
        }
    ]

    with pytest.raises(ApiError) as exc_info:
        _canonicalize_quick_sale_line_amounts(lines)

    assert exc_info.value.code == "INVALID_QUICK_SALE_LINE_DISCOUNT"


def test_quick_sale_invoice_requires_stable_request_id() -> None:
    from adapters.api.v1.invoices import create_invoice_endpoint

    with pytest.raises(ApiError) as exc_info:
        inspect.unwrap(create_invoice_endpoint)(
            request=MagicMock(),
            business_id=5,
            payload={
                "invoice_type": "invoice_sales",
                "extra_info": {"quick_sale": True},
            },
            ctx=MagicMock(),
            db=MagicMock(),
        )

    assert exc_info.value.code == "QUICK_SALE_REQUEST_ID_REQUIRED"


def test_quick_sale_rejects_non_sales_invoice_type() -> None:
    from adapters.api.v1.invoices import create_invoice_endpoint

    with pytest.raises(ApiError) as exc_info:
        inspect.unwrap(create_invoice_endpoint)(
            request=MagicMock(),
            business_id=5,
            payload={
                "invoice_type": "invoice_purchase",
                "extra_info": {
                    "quick_sale": True,
                    "quick_sale_request_id": "8ef087a7-cadc-4b69-9366-163b40723b37",
                },
            },
            ctx=MagicMock(),
            db=MagicMock(),
        )

    assert exc_info.value.code == "QUICK_SALE_INVOICE_TYPE_INVALID"
