from __future__ import annotations

from app.services.business_print_settings_resolver import (
    default_print_settings_dict,
    pick_print_settings,
)
from app.services.print_tax_discount_display import DISPLAY_ALWAYS


class _FakeRow:
    def __init__(self, document_type: str, **kwargs):
        self.document_type = document_type
        defaults = default_print_settings_dict()
        for key, value in defaults.items():
            setattr(self, key, value)
        for key, value in kwargs.items():
            setattr(self, key, value)


def test_pick_print_settings_merges_per_type():
    rows = [
        _FakeRow("all", show_share_qr=False, line_tax_display="smart"),
        _FakeRow("invoice_sales", show_share_qr=True, line_tax_display=DISPLAY_ALWAYS),
    ]
    merged = pick_print_settings(rows, "invoice_sales")
    assert merged["show_share_qr"] is True
    assert merged["line_tax_display"] == DISPLAY_ALWAYS


def test_pick_print_settings_falls_back_to_all():
    rows = [_FakeRow("all", summary_tax_display=DISPLAY_ALWAYS)]
    merged = pick_print_settings(rows, "invoice_purchase")
    assert merged["summary_tax_display"] == DISPLAY_ALWAYS
