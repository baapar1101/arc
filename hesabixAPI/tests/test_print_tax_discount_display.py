from __future__ import annotations

import pytest

from app.services.print_tax_discount_display import (
    DISPLAY_ALWAYS,
    DISPLAY_NEVER,
    DISPLAY_SMART,
    build_invoice_tax_discount_display_flags,
    enrich_line_amount_fields,
    normalize_display_mode,
    resolve_display,
)


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        ("smart", DISPLAY_SMART),
        ("ALWAYS", DISPLAY_ALWAYS),
        (" never ", DISPLAY_NEVER),
        ("invalid", DISPLAY_SMART),
        (None, DISPLAY_SMART),
    ],
)
def test_normalize_display_mode(raw, expected):
    assert normalize_display_mode(raw) == expected


@pytest.mark.parametrize(
    ("mode", "has_data", "expected"),
    [
        (DISPLAY_SMART, True, True),
        (DISPLAY_SMART, False, False),
        (DISPLAY_ALWAYS, False, True),
        (DISPLAY_NEVER, True, False),
    ],
)
def test_resolve_display(mode, has_data, expected):
    assert resolve_display(mode, has_data) is expected


def test_build_flags_smart_hides_zero_columns():
    flags = build_invoice_tax_discount_display_flags(
        {},
        has_line_discount=False,
        has_line_tax=False,
        discount_total=0,
        tax_total=0,
        amount_without_tax=1000,
        subtotal=1000,
    )
    assert flags["show_line_discount_column"] is False
    assert flags["show_line_tax_column"] is False
    assert flags["show_line_amount_before_discount_column"] is False
    assert flags["show_line_amount_before_tax_column"] is False
    assert flags["show_summary_discount"] is False
    assert flags["show_summary_tax"] is False
    assert flags["show_summary_amount_without_tax"] is False


def test_build_flags_always_shows_columns():
    flags = build_invoice_tax_discount_display_flags(
        {
            "line_discount_display": DISPLAY_ALWAYS,
            "line_tax_display": DISPLAY_ALWAYS,
            "summary_discount_display": DISPLAY_ALWAYS,
            "summary_tax_display": DISPLAY_ALWAYS,
        },
        has_line_discount=False,
        has_line_tax=False,
        discount_total=0,
        tax_total=0,
        amount_without_tax=1000,
        subtotal=1000,
    )
    assert flags["show_line_discount_column"] is True
    assert flags["show_line_tax_column"] is True
    assert flags["show_summary_discount"] is True
    assert flags["show_summary_tax"] is True


def test_build_flags_never_hides_even_with_data():
    flags = build_invoice_tax_discount_display_flags(
        {"line_tax_display": DISPLAY_NEVER, "summary_tax_display": DISPLAY_NEVER},
        has_line_discount=True,
        has_line_tax=True,
        discount_total=50,
        tax_total=9,
        amount_without_tax=950,
        subtotal=1000,
    )
    assert flags["show_line_tax_column"] is False
    assert flags["show_summary_tax"] is False
    assert flags["show_line_discount_column"] is True


def test_enrich_line_amount_fields():
    line = enrich_line_amount_fields(
        {
            "line_total": 109,
            "discount": 10,
            "tax_amount": 9,
        }
    )
    assert line["amount_before_discount"] == 110
    assert line["amount_before_tax"] == 100
