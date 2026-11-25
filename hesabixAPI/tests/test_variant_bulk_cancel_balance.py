from datetime import date
from decimal import Decimal

from sqlalchemy import create_engine
from sqlalchemy.orm import Session
from sqlalchemy.schema import CreateTable

from adapters.db.models.inventory_variant_balance import InventoryVariantBalance
from adapters.db.models.product import Product
from adapters.db.models.product_variant_allocation import WarehouseLineVariantAllocation
from adapters.db.models.warehouse_document import WarehouseDocument
from adapters.db.models.warehouse_document_line import WarehouseDocumentLine
from app.core import business_calendar
from app.services.product_variant_service import list_variant_balances
from app.services.variant_inventory_service import rebuild_balances_for_warehouse_document
from app.services.warehouse_service import get_physical_stock


def test_next_receipt_does_not_count_posted_reversal_of_cancelled_issue(monkeypatch):
    day = date(2026, 11, 11)
    monkeypatch.setattr(business_calendar, "business_today", lambda _business_id: day)
    engine = create_engine("sqlite://")
    try:
        with engine.begin() as connection:
            for model in (
                Product,
                WarehouseDocument,
                WarehouseDocumentLine,
                WarehouseLineVariantAllocation,
                InventoryVariantBalance,
            ):
                connection.execute(CreateTable(model.__table__, include_foreign_key_constraints=[]))

        with Session(engine, autoflush=False) as db:
            db.add(Product(id=1, business_id=1, code="P", name="Variant", variant_mode="inventory"))
            for doc_id, doc_type, status, movement, quantity, source_id, extra_info in (
                (1, "receipt", "posted", "in", 10, None, None),
                (2, "issue", "cancelled", "out", 2, None, None),
                (3, "receipt", "posted", "in", 2, 2, {"cancels_warehouse_document_id": 2}),
                (4, "receipt", "posted", "in", 1, 2, None),
            ):
                db.add(
                    WarehouseDocument(
                        id=doc_id,
                        business_id=1,
                        code=str(doc_id),
                        document_date=day,
                        doc_type=doc_type,
                        status=status,
                        source_type="manual",
                        source_document_id=source_id,
                        extra_info=extra_info,
                    )
                )
                db.add(
                    WarehouseDocumentLine(
                        id=doc_id,
                        warehouse_document_id=doc_id,
                        product_id=1,
                        warehouse_id=1,
                        movement=movement,
                        quantity=quantity,
                    )
                )
                db.add(
                    WarehouseLineVariantAllocation(
                        id=doc_id,
                        business_id=1,
                        warehouse_document_line_id=doc_id,
                        product_id=1,
                        variant_id=1,
                        quantity=quantity,
                    )
                )
            db.commit()
            rebuild_balances_for_warehouse_document(db, db.get(WarehouseDocument, 4))
            db.commit()

        with Session(engine) as db:
            listed = list_variant_balances(db, 1, 1, 1)
            assert {row["variant_id"]: Decimal(row["quantity"]) for row in listed} == {1: 11}
            assert get_physical_stock(db, 1, 1, warehouse_id=1, as_of_date=day) == 11
    finally:
        engine.dispose()
