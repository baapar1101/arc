from datetime import date
from decimal import Decimal

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.schema import CreateTable

from adapters.db import models
from adapters.db.models.business import BusinessField, BusinessType
from adapters.db.models.document_monetization import DocumentUsagePolicy
from adapters.db.models.invoice_item_line import InvoiceItemLine
from adapters.db.models.product_variant import ProductVariant
from adapters.db.models.product_variant_allocation import (
    InvoiceItemLineVariantAllocation,
    WarehouseLineVariantAllocation,
)
from app.core import business_calendar, cache
from app.core.responses import ApiError
from app.services import business_timezone_service, warehouse_service

DAY = date(2026, 11, 26)


@pytest.fixture
def sessions(monkeypatch):
    monkeypatch.setattr(cache, "get_redis_client", lambda *args, **kwargs: None)
    monkeypatch.setattr(cache, "_redis_config", {"enabled": False})
    monkeypatch.setattr(cache, "_redis_config_expires_at", float("inf"))
    monkeypatch.setattr(cache, "_cache_service", None)
    monkeypatch.setattr(business_calendar, "business_today", lambda *_: DAY)
    monkeypatch.setattr(
        business_timezone_service, "get_business_display_timezone_cached", lambda *_: "Asia/Tehran"
    )
    tables = (
        "businesses",
        "currencies",
        "fiscal_years",
        "documents",
        "document_lines",
        "products",
        "warehouses",
        "invoice_item_lines",
        "invoice_item_line_variant_allocations",
        "warehouse_documents",
        "warehouse_document_lines",
        "warehouse_line_variant_allocations",
        "warehouse_line_lot_allocations",
        "product_variants",
        "product_instances",
        "inventory_variant_balances",
        "document_usage_policies",
        "document_number_counters",
        "business_document_numbering_settings",
    )
    engine = create_engine("sqlite://")
    try:
        with engine.begin() as connection:
            for name in tables:
                connection.execute(
                    CreateTable(
                        models.Base.metadata.tables[name], include_foreign_key_constraints=[]
                    )
                )
        factory = sessionmaker(engine, autoflush=False)
        with factory.begin() as db:
            db.add_all(
                [
                    models.Business(
                        id=1,
                        name="Test",
                        owner_id=1,
                        default_currency_id=1,
                        business_type=BusinessType.SHOP,
                        business_field=BusinessField.TRADING,
                    ),
                    models.Currency(id=1, name="Base", title="Base", symbol="B", code="B"),
                    models.FiscalYear(
                        id=1, business_id=1, title="FY", start_date=DAY, end_date=DAY, is_last=True
                    ),
                    models.Warehouse(id=1, business_id=1, code="W", name="W"),
                    DocumentUsagePolicy(
                        business_id=1, policy_type="free", title="Test", is_active=True
                    ),
                ]
            )
        yield factory
    finally:
        engine.dispose()


def _purchase(sessions, qty, *, unit="main", variant=False, factor=4):
    with sessions.begin() as db:
        db.add(
            models.Product(
                id=1,
                business_id=1,
                code="P",
                name="P",
                track_inventory=True,
                main_unit="carton",
                secondary_unit="piece",
                unit_conversion_factor=factor,
                variant_mode="inventory" if variant else "none",
            )
        )
        db.add(
            models.Document(
                id=1,
                document_type="invoice_purchase",
                code="BUY",
                business_id=1,
                fiscal_year_id=1,
                currency_id=1,
                document_date=DAY,
                created_by_user_id=1,
            )
        )
        db.add(
            InvoiceItemLine(
                id=1, document_id=1, product_id=1, quantity=qty, extra_info={"unit": unit}
            )
        )
        if variant:
            db.add(ProductVariant(id=1, business_id=1, product_id=1, combination_key="V"))
            db.add(
                InvoiceItemLineVariantAllocation(
                    id=1,
                    business_id=1,
                    product_id=1,
                    variant_id=1,
                    invoice_item_line_id=1,
                    quantity=qty,
                    attributes_snapshot=[],
                )
            )


def _draft(sessions, code, *main_quantities, variant=False, source_line_id=1):
    with sessions.begin() as db:
        receipt = models.WarehouseDocument(
            business_id=1,
            code=code,
            document_date=DAY,
            doc_type="receipt",
            status="draft",
            warehouse_id_to=1,
            source_type="invoice",
            source_document_id=1,
        )
        db.add(receipt)
        db.flush()
        for amount in main_quantities:
            line = models.WarehouseDocumentLine(
                warehouse_document_id=receipt.id,
                product_id=1,
                warehouse_id=1,
                movement="in",
                quantity=amount,
                extra_info={
                    "inventory_quantity_unit": "main",
                    "invoice_item_line_id": source_line_id,
                },
            )
            db.add(line)
            db.flush()
            if variant:
                db.add(
                    WarehouseLineVariantAllocation(
                        id=line.id,
                        business_id=1,
                        product_id=1,
                        variant_id=1,
                        warehouse_document_line_id=line.id,
                        quantity=amount,
                        source_document_allocation_id=1,
                    )
                )
        return receipt.id


def _post(sessions, receipt):
    with sessions.begin() as db:
        return warehouse_service.post_warehouse_document(db, receipt)


def _state(sessions, receipts):
    with sessions() as db:
        return (
            warehouse_service.get_physical_stock(db, 1, 1, 1),
            [db.get(models.WarehouseDocument, receipt).status for receipt in receipts],
            warehouse_service.compute_invoice_line_quantities(db, 1, db.get(models.Document, 1))[0],
        )


@pytest.mark.parametrize(
    ("unit", "invoice_qty", "stock_qty"), [("main", 4, 4), ("secondary", 16, 4)]
)
def test_second_purchase_receipt_is_rejected_after_full_variant_receipt(
    sessions, unit, invoice_qty, stock_qty
):
    _purchase(sessions, invoice_qty, unit=unit, variant=True)
    first = _draft(sessions, "A", stock_qty, variant=True)
    second = _draft(sessions, "B", stock_qty, variant=True)
    _post(sessions, first)
    before = _state(sessions, [first, second])
    with pytest.raises(ApiError, match="QUANTITY_EXCEEDS_REMAINING"):
        _post(sessions, second)
    assert _state(sessions, [first, second]) == before
    assert before[0] == stock_qty and before[1] == ["posted", "draft"]
    assert before[2]["processed_quantity"] == invoice_qty
    _post(sessions, first)
    assert _state(sessions, [first, second]) == before


def test_purchase_receipt_checks_aggregate_for_a_repeated_source_line(sessions):
    _purchase(sessions, 4)
    receipt = _draft(sessions, "OVER", 2, 3)
    with pytest.raises(ApiError, match="QUANTITY_EXCEEDS_REMAINING"):
        _post(sessions, receipt)
    assert _state(sessions, [receipt])[:2] == (0, ["draft"])


def test_cancelled_partial_purchase_receipt_frees_capacity_and_same_request_can_retry(sessions):
    _purchase(sessions, 4)
    first = _draft(sessions, "PART", 2)
    replacement = _draft(sessions, "FULL", 4)
    _post(sessions, first)
    assert _state(sessions, [first])[2]["remaining_quantity"] == 2
    with pytest.raises(ApiError, match="QUANTITY_EXCEEDS_REMAINING"):
        _post(sessions, replacement)
    with sessions.begin() as db:
        warehouse_service.cancel_warehouse_document(db, 1, first, 1)
    assert _state(sessions, [first, replacement])[:2] == (0, ["cancelled", "draft"])
    _post(sessions, replacement)
    assert _state(sessions, [first, replacement])[:2] == (4, ["cancelled", "posted"])


def test_receipt_counts_preexisting_unmatched_line_as_product_fulfillment(sessions):
    _purchase(sessions, 4)
    old = _draft(sessions, "OLD", 2, source_line_id=999)
    with sessions.begin() as db:
        db.get(models.WarehouseDocument, old).status = "posted"
    receipt = _draft(sessions, "OVER", 3)
    with pytest.raises(ApiError, match="QUANTITY_EXCEEDS_REMAINING"):
        _post(sessions, receipt)
    assert _state(sessions, [old, receipt])[:2] == (2, ["posted", "draft"])


def test_receipt_uses_saved_stock_precision_for_fractional_unit_conversion(sessions):
    _purchase(sessions, 1, unit="secondary", factor=6)
    receipt = _draft(sessions, "ROUND", Decimal("0.166667"))
    _post(sessions, receipt)
    assert _state(sessions, [receipt])[:2] == (Decimal("0.166667"), ["posted"])
