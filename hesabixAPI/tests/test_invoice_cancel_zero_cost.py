from datetime import date, datetime
from decimal import Decimal

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import Session

from adapters.db import models
from adapters.db.models.business import BusinessField, BusinessType
from adapters.db.models.invoice_item_line import InvoiceItemLine
from app.core import cache
from app.services import invoice_service
from app.services.invoice_cogs_gl_service import (
    _calculate_invoice_cogs_amount_for_gl,
    _existing_cogs_gl_amount,
)
from app.services.invoice_profit_ledger_service import (
    apply_recognized_profit_to_invoice_lines,
    sync_ledger_profit_from_analytical_for_document,
)
from app.services.warehouse_service import _compute_line_quantities_core, cancel_warehouse_document


@pytest.fixture
def sale(monkeypatch):
    monkeypatch.setattr(cache, "_redis_config", {"enabled": False})
    monkeypatch.setattr(cache, "_redis_config_expires_at", float("inf"))
    monkeypatch.setattr(cache, "_redis_client", None)
    monkeypatch.setattr(cache, "_cache_service", None)
    engine = create_engine("sqlite://")
    tables = ("businesses", "currencies", "fiscal_years", "products", "documents", "document_lines",
              "invoice_item_lines", "warehouse_documents", "warehouse_document_lines",
              "warehouse_line_variant_allocations", "warehouse_line_lot_allocations",
              "business_document_numbering_settings", "document_number_counters")
    models.Base.metadata.create_all(engine, tables=[models.Base.metadata.tables[name] for name in tables])
    day = date(2026, 11, 11)
    with Session(engine, autoflush=False) as db:
        item = InvoiceItemLine(id=1, document_id=1, product_id=1, quantity=2, extra_info={"unit_price": 250},
                               purchase_price_snapshot_unit_cost_base=100, purchase_price_snapshot_currency_id=1,
                               ledger_unit_cogs=100, ledger_line_cogs=200, ledger_recognized_at=datetime(2026, 11, 11))
        db.add_all([
            models.Business(id=1, name="Test", business_type=BusinessType.SHOP, business_field=BusinessField.TRADING,
                     owner_id=1, default_currency_id=1, invoice_profit_ledger_recognition_basis="sales_invoice_document"),
            models.Currency(id=1, name="Base", title="Base", symbol="B", code="B"),
            models.FiscalYear(id=1, business_id=1, title="2026", is_last=True, start_date=day, end_date=day),
            models.Product(id=1, business_id=1, code="P", name="P"),
            models.Document(id=1, code="SALE", business_id=1, fiscal_year_id=1, currency_id=1, created_by_user_id=1,
                     document_date=day, document_type="invoice_sales", extra_info={"links": {"warehouse_document_ids": [1]}}),
            models.WarehouseDocument(id=1, business_id=1, fiscal_year_id=1, code="ISSUE", document_date=day,
                              status="posted", doc_type="issue", source_type="invoice", source_document_id=1),
            models.WarehouseDocumentLine(warehouse_document_id=1, product_id=1, movement="out", quantity=2,
                                  extra_info={"invoice_item_line_id": 1}),
            models.DocumentLine(document_id=1, debit=200, credit=0, extra_info={"side": "gl_cogs"}),
            models.DocumentLine(document_id=1, debit=0, credit=200, extra_info={"side": "gl_inventory_cogs"}),
            item,
        ])
        db.flush()
        yield db, item
    engine.dispose()


def test_cancel_only_issue_clears_snapshot_and_gl(sale):
    db, item = sale
    assert item.ledger_line_cogs == _calculate_invoice_cogs_amount_for_gl(db, 1, 1) == 200
    reversal = cancel_warehouse_document(db, 1, 1, 1)
    issue = db.get(models.WarehouseDocument, 1)
    assert (issue.status, reversal.status) == ("cancelled", "draft")
    assert _compute_line_quantities_core("invoice_sales", [item], [issue, reversal])[0]["processed_quantity"] == 0
    assert item.ledger_unit_cogs == item.ledger_line_cogs == 0
    assert _existing_cogs_gl_amount(db.query(models.DocumentLine).all()) == 0
    assert _calculate_invoice_cogs_amount_for_gl(db, 1, 1) == 0
    assert sync_ledger_profit_from_analytical_for_document(db, 1, 1)
    assert item.ledger_unit_cogs == item.ledger_line_cogs == 0
    assert item.purchase_price_snapshot_unit_cost_base == 100


def test_unknown_cost_preserves_snapshot_and_falls_back(sale, monkeypatch):
    db, item = sale
    # The team calculator emits numeric costs. Inject the nullable producer result only.
    monkeypatch.setattr(invoice_service, "_calculate_invoice_profit",
                        lambda *a, **kw: {"line_profits": [{"line_id": 1, "total_cost": None}]})
    assert not apply_recognized_profit_to_invoice_lines(db, 1, 1, recognition_event="sales_invoice_document")
    assert item.ledger_line_cogs == 200
    assert not sync_ledger_profit_from_analytical_for_document(db, 1, 1)
    assert item.ledger_line_cogs == _calculate_invoice_cogs_amount_for_gl(db, 1, 1) == 200


@pytest.mark.parametrize("issue_count, expected", [(1, 0), (2, 200)])
def test_known_zero_ignores_old_snapshot_only_for_single_issue(sale, issue_count, expected):
    db, item = sale
    item.purchase_price_snapshot_unit_cost_base = Decimal(0)
    if issue_count == 2:
        first = db.get(models.WarehouseDocument, 1)
        db.add(models.WarehouseDocument(business_id=1, code="ISSUE-2", document_date=first.document_date,
                                        status="posted", doc_type="issue", source_type="invoice", source_document_id=1))
    db.flush()
    assert _calculate_invoice_cogs_amount_for_gl(db, 1, 1) == expected
