from datetime import date
from decimal import Decimal

import pytest
from sqlalchemy import create_engine, select
from sqlalchemy.orm import Session
from sqlalchemy.schema import CreateTable

from adapters.db import models
from adapters.db.models.business import BusinessField, BusinessType
from adapters.db.models.document_monetization import DocumentUsagePolicy
from adapters.db.models.inventory_variant_balance import InventoryVariantBalance
from adapters.db.models.invoice_item_line import InvoiceItemLine
from adapters.db.models.product_variant import ProductVariant
from adapters.db.models.product_variant_allocation import WarehouseLineVariantAllocation
from adapters.db.models.warehouse import Warehouse
from adapters.db.models.warehouse_document import WarehouseDocument
from adapters.db.models.warehouse_document_line import WarehouseDocumentLine
from app.core import business_calendar, cache
from app.services import woocommerce_stock_push_hook
from app.services.product_variant_service import list_variant_balances
from app.services.warehouse_service import post_warehouse_document

DAY = date(2026, 11, 11)


@pytest.mark.parametrize(
    ("doc_type", "receipt_quantities", "movements", "expected"),
    [
        ("issue", (10, 10), ((1, "out", 2), (2, "out", 3)), {1: 8, 2: 7}),
        ("adjustment", (8, 12), ((1, "out", 1),), {1: 7, 2: 12}),
        ("adjustment", (8, 12), ((1, "in", 1),), {1: 9, 2: 12}),
    ],
    ids=("issue", "adjustment-shortage", "adjustment-surplus"),
)
def test_post_receipt_then_movement_refreshes_variant_balance(
    monkeypatch, doc_type, receipt_quantities, movements, expected
):
    monkeypatch.setattr(cache, "get_redis_client", lambda *args, **kwargs: None)
    monkeypatch.setattr(cache, "_cache_service", None)
    monkeypatch.setattr(business_calendar, "business_today", lambda *args: DAY)
    monkeypatch.setattr(woocommerce_stock_push_hook, "_execute_stock_push", lambda *args: None)
    engine = create_engine("sqlite://")
    try:
        names = (
            "businesses",
            "currencies",
            "fiscal_years",
            "products",
            "warehouses",
            "warehouse_documents",
            "warehouse_document_lines",
            "warehouse_line_variant_allocations",
            "warehouse_line_lot_allocations",
            "invoice_item_line_variant_allocations",
            "documents",
            "document_usage_policies",
            "product_instances",
            "product_variants",
            "inventory_variant_balances",
        )
        with engine.begin() as connection:
            connection.execute(
                CreateTable(InvoiceItemLine.__table__, include_foreign_key_constraints=[])
            )
            for name in names:
                table = models.Base.metadata.tables[name]
                connection.execute(CreateTable(table, include_foreign_key_constraints=[]))

        with Session(engine, autoflush=False) as db:
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
                    models.Product(
                        id=1,
                        business_id=1,
                        code="P",
                        name="P",
                        track_inventory=True,
                        inventory_mode="bulk",
                        variant_mode="inventory",
                    ),
                    Warehouse(id=1, business_id=1, code="W", name="W"),
                    DocumentUsagePolicy(
                        business_id=1, policy_type="free", title="Test", is_active=True
                    ),
                    WarehouseDocument(
                        id=1,
                        business_id=1,
                        code="IN",
                        document_date=DAY,
                        status="draft",
                        doc_type="receipt",
                        warehouse_id_to=1,
                        source_type="manual",
                    ),
                    WarehouseDocument(
                        id=2,
                        business_id=1,
                        code="MOVE",
                        document_date=DAY,
                        status="draft",
                        doc_type=doc_type,
                        warehouse_id_from=1 if doc_type == "issue" else None,
                        source_type="manual",
                    ),
                ]
            )
            for variant_id in (1, 2):
                db.add(
                    ProductVariant(
                        id=variant_id, business_id=1, product_id=1, combination_key=str(variant_id)
                    )
                )
            receipt_lines = [
                (1, variant_id, "in", quantity)
                for variant_id, quantity in enumerate(receipt_quantities, 1)
            ]
            movement_lines = [
                (2, variant_id, movement, qty) for variant_id, movement, qty in movements
            ]
            for line_id, (document_id, variant_id, movement, quantity) in enumerate(
                receipt_lines + movement_lines, 1
            ):
                db.add(
                    WarehouseDocumentLine(
                        id=line_id,
                        warehouse_document_id=document_id,
                        product_id=1,
                        warehouse_id=1,
                        movement=movement,
                        quantity=quantity,
                    )
                )
                db.add(
                    WarehouseLineVariantAllocation(
                        id=line_id,
                        business_id=1,
                        product_id=1,
                        variant_id=variant_id,
                        quantity=quantity,
                        warehouse_document_line_id=line_id,
                    )
                )
            db.commit()

        for document_id, expected_balances in (
            (1, dict(enumerate(receipt_quantities, 1))),
            (2, expected),
        ):
            with Session(engine, autoflush=False) as db:
                assert post_warehouse_document(db, document_id)["status"] == "posted"
                db.commit()

            with Session(engine, autoflush=False) as db:
                assert db.get(WarehouseDocument, document_id).status == "posted"
                stored = {
                    row.variant_id: row.quantity
                    for row in db.scalars(select(InventoryVariantBalance))
                }
                assert stored == expected_balances
                listed = {
                    row["variant_id"]: Decimal(row["quantity"])
                    for row in list_variant_balances(db, 1, 1, 1)
                }
                assert listed == expected_balances
    finally:
        engine.dispose()
