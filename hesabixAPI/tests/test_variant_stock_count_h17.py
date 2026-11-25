from datetime import date
from decimal import Decimal

import pytest
from sqlalchemy import Integer, create_engine, select
from sqlalchemy.orm import Session
from sqlalchemy.schema import CreateTable

from adapters.db.models.fiscal_year import FiscalYear
from adapters.db.models.inventory_lot import WarehouseLineLotAllocation
from adapters.db.models.product import Product
from adapters.db.models.product_instance import ProductInstance
from adapters.db.models.product_variant import ProductVariant
from adapters.db.models.product_variant_allocation import WarehouseLineVariantAllocation
from adapters.db.models.warehouse_document import WarehouseDocument
from adapters.db.models.warehouse_document_line import WarehouseDocumentLine
from app.core.responses import ApiError
from app.services import inventory_lot_service
from app.services.warehouse_service import (
    calculate_stock_count_differences,
    create_stock_count_adjustment,
)

DAY = date(2026, 11, 11)
LATER = date(2026, 11, 12)


@pytest.fixture
def db(monkeypatch):
    engine = create_engine("sqlite://")
    allocation_id = WarehouseLineVariantAllocation.__table__.c.id
    monkeypatch.setattr(allocation_id, "type", allocation_id.type.with_variant(Integer, "sqlite"))
    with engine.begin() as connection:
        for model in (
            FiscalYear,
            Product,
            ProductInstance,
            ProductVariant,
            WarehouseDocument,
            WarehouseDocumentLine,
            WarehouseLineVariantAllocation,
            WarehouseLineLotAllocation,
        ):
            connection.execute(CreateTable(model.__table__, include_foreign_key_constraints=[]))
    from app.services import warehouse_service

    monkeypatch.setattr(warehouse_service, "_generate_warehouse_document_code", lambda *_: "H17")
    with Session(engine, autoflush=False) as session:
        session.add_all(
            [
                FiscalYear(
                    id=1, business_id=1, title="FY", is_last=True, start_date=DAY, end_date=LATER
                ),
                Product(id=1, business_id=1, code="P", name="Variant", variant_mode="inventory"),
                Product(id=2, business_id=1, code="U", name="Unique", inventory_mode="unique"),
                ProductInstance(
                    id=1,
                    business_id=1,
                    product_id=2,
                    warehouse_id=1,
                    serial_number="U1",
                    status="available",
                    entry_date=DAY,
                ),
                ProductVariant(id=1, business_id=1, product_id=1, combination_key="red"),
                ProductVariant(id=2, business_id=1, product_id=1, combination_key="blue"),
            ]
        )
        for key, (variant, qty, date_, warehouse, status) in enumerate(
            (
                (1, 8, DAY, 1, "posted"),
                (2, 12, DAY, 1, "posted"),
                (1, 3, LATER, 1, "posted"),
                (1, 5, DAY, 2, "posted"),
                (1, 30, DAY, 1, "draft"),
            ),
            1,
        ):
            session.add_all(
                [
                    WarehouseDocument(
                        id=key,
                        business_id=1,
                        code=str(key),
                        status=status,
                        doc_type="receipt",
                        document_date=date_,
                    ),
                    WarehouseDocumentLine(
                        id=key,
                        warehouse_document_id=key,
                        product_id=1,
                        warehouse_id=warehouse,
                        movement="in",
                        quantity=qty,
                    ),
                    WarehouseLineVariantAllocation(
                        id=key,
                        business_id=1,
                        product_id=1,
                        warehouse_document_line_id=key,
                        variant_id=variant,
                        quantity=qty,
                    ),
                ]
            )
        session.commit()
        yield session
    engine.dispose()


def calculate(db, count, **selector):
    row = {"product_id": 1, "warehouse_id": 1, "physical_quantity": count, **selector}
    return calculate_stock_count_differences(db, 1, [row], as_of_date=DAY)["items"][0]


@pytest.mark.parametrize(("count", "movement"), [(7, "out"), (8, None), (9, "in")])
def test_count_uses_historical_variant_stock_and_keeps_adjustment_allocation(db, count, movement):
    row = calculate(db, count, variant_id=1)
    assert (row["system_quantity"], row["difference"], row["movement"]) == (8, count - 8, movement)
    if movement is None:
        with pytest.raises(ApiError) as error:
            create_stock_count_adjustment(db, 1, None, "COUNT", DAY, [row])
        assert error.value.code == "NO_DIFFERENCES"
        assert db.scalar(select(WarehouseDocument.id).filter_by(doc_type="adjustment")) is None
        return

    document = create_stock_count_adjustment(db, 1, None, "COUNT", DAY, [row])
    line = db.scalars(
        select(WarehouseDocumentLine).filter_by(warehouse_document_id=document.id)
    ).one()
    allocation = db.scalars(
        select(WarehouseLineVariantAllocation).filter_by(warehouse_document_line_id=line.id)
    ).one()
    assert (line.movement, line.quantity, allocation.variant_id, allocation.quantity) == (
        movement,
        1,
        1,
        1,
    )


def test_existing_stock_count_selectors_keep_their_basis(db, monkeypatch):
    assert calculate(db, 20)["system_quantity"] == 20
    monkeypatch.setattr(inventory_lot_service, "compute_available_lot_stock", lambda *_: Decimal(4))
    assert calculate(db, 4, lot_id=1, variant_id=2)["difference"] == 0
    assert calculate(db, 1, product_id=2, instance_id=1)["difference"] == 0


def test_stock_count_rejects_unknown_variant(db):
    with pytest.raises(ApiError) as error:
        calculate(db, 8, variant_id=999)
    assert error.value.code == "VARIANT_NOT_FOUND"


def test_stock_count_does_not_count_posted_reversal_of_cancelled_issue(db):
    db.add_all(
        [
            WarehouseDocument(
                id=6,
                business_id=1,
                code="ISSUE",
                status="cancelled",
                doc_type="issue",
                document_date=DAY,
            ),
            WarehouseDocument(
                id=7,
                business_id=1,
                code="REVERSE",
                status="posted",
                doc_type="receipt",
                document_date=DAY,
                source_document_id=6,
                extra_info={"cancels_warehouse_document_id": 6},
            ),
            WarehouseDocumentLine(
                id=7,
                warehouse_document_id=7,
                product_id=1,
                warehouse_id=1,
                movement="in",
                quantity=2,
            ),
            WarehouseLineVariantAllocation(
                id=7,
                business_id=1,
                product_id=1,
                warehouse_document_line_id=7,
                variant_id=1,
                quantity=2,
            ),
        ]
    )
    db.flush()
    assert calculate(db, 8, variant_id=1)["difference"] == 0
