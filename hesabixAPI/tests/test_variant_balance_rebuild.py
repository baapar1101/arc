from datetime import date

from adapters.db.models.inventory_variant_balance import InventoryVariantBalance
from adapters.db.models.product_variant import ProductVariant
from adapters.db.models.product_variant_allocation import WarehouseLineVariantAllocation
from adapters.db.models.warehouse_document import WarehouseDocument
from adapters.db.models.warehouse_document_line import WarehouseDocumentLine
from app.services.variant_inventory_service import rebuild_balances_for_warehouse_document
from sqlalchemy import create_engine, select
from sqlalchemy.orm import Session
from sqlalchemy.schema import CreateTable


def test_rebuild_sums_only_posted_movements_for_each_variant_and_warehouse():
    engine = create_engine("sqlite://")
    try:
        with engine.begin() as connection:
            for model in (
                ProductVariant,
                WarehouseDocument,
                WarehouseDocumentLine,
                WarehouseLineVariantAllocation,
                InventoryVariantBalance,
            ):
                connection.execute(CreateTable(model.__table__, include_foreign_key_constraints=[]))

        with Session(engine, autoflush=False) as db:
            db.add_all(
                [
                    ProductVariant(
                        id=variant, product_id=1, business_id=1, combination_key=str(variant)
                    )
                    for variant in (1, 2)
                ]
            )
            db.add_all(
                [
                    WarehouseDocument(
                        id=doc_id,
                        business_id=1,
                        code=str(doc_id),
                        document_date=date(2026, 11, 11),
                        doc_type=kind,
                        status=status,
                    )
                    for doc_id, kind, status in (
                        (1, "receipt", "posted"),
                        (2, "issue", "posted"),
                        (3, "receipt", "draft"),
                        (4, "receipt", "posted"),
                    )
                ]
            )
            movements = (
                (1, 1, 1, "in", 10),
                (1, 1, 2, "in", 10),
                (2, 1, 1, "out", 2),
                (2, 1, 2, "out", 3),
                (3, 1, 1, "in", 100),
                (4, 2, 2, "in", 100),
            )
            for line_id, (doc_id, warehouse_id, variant, movement, quantity) in enumerate(
                movements, 1
            ):
                db.add(
                    WarehouseDocumentLine(
                        id=line_id,
                        warehouse_document_id=doc_id,
                        product_id=1,
                        warehouse_id=warehouse_id,
                        movement=movement,
                        quantity=quantity,
                    )
                )
                db.add(
                    WarehouseLineVariantAllocation(
                        id=line_id,
                        business_id=1,
                        warehouse_document_line_id=line_id,
                        product_id=1,
                        variant_id=variant,
                        quantity=quantity,
                    )
                )
            db.commit()
            rebuild_balances_for_warehouse_document(db, db.get(WarehouseDocument, 2))
            db.commit()

        with Session(engine) as db:
            balances = db.scalars(select(InventoryVariantBalance)).all()
            assert {(row.warehouse_id, row.variant_id): row.quantity for row in balances} == {
                (1, 1): 8,
                (1, 2): 7,
            }
    finally:
        engine.dispose()
