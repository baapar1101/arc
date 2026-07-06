"""Regression: tax submission must use current product tax data, not stale line snapshots."""

from __future__ import annotations

from types import SimpleNamespace
from unittest.mock import MagicMock, patch

from app.integrations.moadian.invoice_builder import InvoiceBuilder


def test_invoice_builder_uses_product_tax_code_when_snapshot_is_stale() -> None:
    builder = InvoiceBuilder(seller_economic_code="12345678901")
    document = {
        "product_lines": [
            {
                "product_id": 261585,
                "product_name": "پشتیبانی سازمانی",
                "product_tax_code": "1234567890123",
                "product_main_unit": "عدد",
                "quantity": 1,
                "extra_info": {
                    "unit_price": 1000000,
                    "tax_snapshot": {},
                },
            }
        ],
        "extra_info": {"totals": {"net": 1000000}},
    }
    tax_setting = SimpleNamespace(economic_code="12345678901", tax_memory_id="A123")

    dto = builder.build_invoice_dto(document, tax_setting, submission_mode="normal")
    assert dto.body[0].sstid == "1234567890123"


def test_refresh_invoice_line_tax_snapshots_updates_lines() -> None:
    from app.services.invoice_service import refresh_invoice_line_tax_snapshots

    line = SimpleNamespace(
        product_id=10,
        extra_info={"tax_snapshot": {"tax_code": "old"}},
    )
    document = SimpleNamespace(id=1, business_id=99)
    db = MagicMock()
    db.query.return_value.filter.return_value.all.return_value = [line]

    tax_map = {
        10: {
            "tax_code": "1234567890123",
            "tax_unit_id": 3,
            "tax_unit_code": "164",
            "tax_unit_name": "عدد",
            "product_main_unit": "عدد",
        }
    }

    with patch(
        "app.services.invoice_service._build_product_tax_snapshot_map",
        return_value=tax_map,
    ), patch("app.services.invoice_service.flag_modified"):
        updated = refresh_invoice_line_tax_snapshots(db, document)

    assert updated == 1
    assert line.extra_info["tax_snapshot"]["tax_code"] == "1234567890123"
    db.flush.assert_called_once()
