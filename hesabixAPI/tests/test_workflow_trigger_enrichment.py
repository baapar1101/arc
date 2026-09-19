from decimal import Decimal

from app.services.workflow.workflow_trigger_enrichment import _to_decimal


def test_to_decimal_handles_float():
    assert _to_decimal(123.45) == Decimal("123.45")


def test_to_decimal_handles_decimal():
    value = Decimal("99.99")
    assert _to_decimal(value) == value


def test_to_decimal_handles_none():
    assert _to_decimal(None) == Decimal(0)
