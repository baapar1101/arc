from __future__ import annotations

from datetime import date
from decimal import Decimal
from types import SimpleNamespace
from unittest.mock import MagicMock

import pytest

from app.core.responses import ApiError
from app.services import quick_sales_service
from app.services.invoice_service import (
    _adjust_quick_sale_invoice_paid,
    _normalize_quick_sale_customer_balance_application,
    _quick_sale_change_amount,
    _quick_sale_payment_target,
)


def _document(*, total: float, meta: dict | None = None) -> SimpleNamespace:
    extra = {"totals": {"net": total}}
    if meta is not None:
        extra["quick_sale_customer_balance"] = {"applied": True, **meta}
    return SimpleNamespace(extra_info=extra)


def test_prior_debt_increases_payment_target_and_is_allocated_first() -> None:
    document = _document(
        total=5_000_000,
        meta={
            "prior_debt_amount": 2_000_000,
            "credit_applied_amount": 0,
            "payment_target": 7_000_000,
        },
    )

    assert _quick_sale_payment_target(document) == Decimal("7000000")
    assert _adjust_quick_sale_invoice_paid(document, Decimal("7000000")) == Decimal(
        "5000000"
    )
    assert _adjust_quick_sale_invoice_paid(document, Decimal("4000000")) == Decimal(
        "2000000"
    )


def test_prior_credit_reduces_target_and_settles_invoice() -> None:
    document = _document(
        total=5_000_000,
        meta={
            "prior_debt_amount": 0,
            "credit_applied_amount": 2_000_000,
            "payment_target": 3_000_000,
        },
    )

    assert _quick_sale_payment_target(document) == Decimal("3000000")
    assert _adjust_quick_sale_invoice_paid(document, Decimal("3000000")) == Decimal(
        "5000000"
    )
    assert _quick_sale_change_amount(
        document,
        [{"amount": 3_500_000}],
    ) == Decimal("500000")


def test_credit_larger_than_invoice_caps_applied_credit() -> None:
    document = _document(
        total=5_000_000,
        meta={
            "prior_debt_amount": 0,
            "credit_applied_amount": 5_000_000,
            "payment_target": 0,
        },
    )

    assert _adjust_quick_sale_invoice_paid(document, Decimal(0)) == Decimal("5000000")


def test_server_normalizes_customer_balance_application(monkeypatch) -> None:
    monkeypatch.setattr(
        quick_sales_service,
        "get_quick_sales_customer_balance",
        lambda *_args, **_kwargs: {
            "balance": -2_000_000,
            "status": "بدهکار",
            "decimal_places": 0,
        },
    )
    extra = {
        "quick_sale_customer_balance": {
            "apply": True,
            "person_id": 10,
            "currency_id": 1,
            "balance_before": -2_000_000,
        }
    }

    result = _normalize_quick_sale_customer_balance_application(
        MagicMock(),
        business_id=1,
        person_id=10,
        currency_id=1,
        document_date=date(2026, 10, 16),
        fiscal_year_id=2,
        invoice_total=Decimal("5000000"),
        header_extra=extra,
    )

    normalized = result["quick_sale_customer_balance"]
    assert normalized["prior_debt_amount"] == 2_000_000
    assert normalized["credit_applied_amount"] == 0
    assert normalized["payment_target"] == 7_000_000


def test_server_rejects_stale_customer_balance(monkeypatch) -> None:
    monkeypatch.setattr(
        quick_sales_service,
        "get_quick_sales_customer_balance",
        lambda *_args, **_kwargs: {
            "balance": -2_500_000,
            "status": "بدهکار",
            "decimal_places": 0,
        },
    )

    with pytest.raises(ApiError) as exc_info:
        _normalize_quick_sale_customer_balance_application(
            MagicMock(),
            business_id=1,
            person_id=10,
            currency_id=1,
            document_date=date(2026, 10, 16),
            fiscal_year_id=2,
            invoice_total=Decimal("5000000"),
            header_extra={
                "quick_sale_customer_balance": {
                    "apply": True,
                    "person_id": 10,
                    "currency_id": 1,
                    "balance_before": -2_000_000,
                }
            },
        )

    assert exc_info.value.code == "QUICK_SALE_CUSTOMER_BALANCE_CHANGED"
    assert exc_info.value.status_code == 409
