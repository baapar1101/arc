from __future__ import annotations

from app.services.print_tax_discount_display import (
    build_global_discount_print_info,
    enrich_line_amount_fields,
    format_line_discount_display,
    line_amounts_before_global_discount,
    should_restore_line_amounts_before_global,
)


def test_format_line_discount_percent_shows_percent_and_amount():
    assert format_line_discount_display(1200, "percent", 12) == "12٪ (1,200)"
    assert format_line_discount_display(1200, "percent", 12, is_fa=False) == "12% (1,200)"


def test_format_line_discount_amount_only_shows_amount():
    assert format_line_discount_display(500, "amount", 500) == "500"
    assert format_line_discount_display(500, None, None) == "500"


def test_enrich_line_includes_discount_display():
    line = enrich_line_amount_fields(
        {
            "line_total": 1090,
            "discount": 120,
            "tax_amount": 90,
            "discount_type": "percent",
            "discount_value": 10,
        }
    )
    assert line["discount_display"] == "10٪ (120)"
    assert line["amount_before_discount"] == 1120.0


def test_global_discount_percent_summary_display():
    info = build_global_discount_print_info(
        {
            "global_discount": {
                "type": "percent",
                "value": 12,
                "amount": 2400,
                "tax_mode": "recalculate_tax_proportional",
            },
            "totals": {"discount": 2400},
        },
        line_discount_total=0,
    )
    assert info["has_global_discount"] is True
    assert info["show_discount_breakdown"] is False
    assert info["discount_summary_label"] == "تخفیف کلی"
    assert info["discount_summary_display"] == "12٪ (2,400)"
    assert info["restore_line_amounts_before_global"] is True


def test_global_and_line_discount_breakdown():
    info = build_global_discount_print_info(
        {
            "global_discount": {"type": "percent", "value": 5, "amount": 100},
            "totals": {"discount": 250},
        },
        line_discount_total=150,
    )
    assert info["show_discount_breakdown"] is True
    assert info["discount_line_label"] == "تخفیف سطری"
    assert info["discount_global_label"] == "تخفیف کلی"
    assert info["global_discount_display"] == "5٪ (100)"


def test_restore_amounts_skipped_for_keep_line_taxes():
    assert (
        should_restore_line_amounts_before_global(
            {"amount": 100, "tax_mode": "keep_line_taxes"}
        )
        is False
    )
    assert (
        should_restore_line_amounts_before_global(
            {"amount": 100, "tax_mode": "recalculate_tax_proportional"}
        )
        is True
    )


def test_line_amounts_before_global_discount_math():
    restored = line_amounts_before_global_discount(
        quantity=2,
        unit_price=1000,
        line_discount=200,
        tax_rate=9,
    )
    assert restored["taxable"] == 1800.0
    assert restored["tax_amount"] == 162.0
    assert restored["line_total"] == 1962.0
