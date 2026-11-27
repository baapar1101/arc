from datetime import date
from decimal import Decimal

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import Session
from sqlalchemy.schema import CreateTable

from adapters.db.models import Product, Warehouse, WarehouseDocument, WarehouseDocumentLine
from adapters.db.models.product_variant_allocation import WarehouseLineVariantAllocation
from app.core.responses import ApiError
from app.services import product_variant_enable_service as service
from app.services import warehouse_service


@pytest.fixture
def conversion(monkeypatch):
    engine = create_engine("sqlite://")
    with engine.begin() as connection:
        for model in (
            Product,
            Warehouse,
            WarehouseDocument,
            WarehouseDocumentLine,
            WarehouseLineVariantAllocation,
        ):
            connection.execute(CreateTable(model.__table__, include_foreign_key_constraints=[]))
    monkeypatch.setattr(service, "list_dimensions", lambda *args: [1])
    monkeypatch.setattr(service, "list_variants", lambda *args: [1, 2])
    monkeypatch.setattr(service, "resolve_variant", lambda *args, **kwargs: None)
    monkeypatch.setattr(service, "get_physical_stock", lambda *args: Decimal(4))
    monkeypatch.setattr(service, "business_today", lambda *args: date(2026, 11, 26))
    with Session(engine) as db:
        db.add(Product(id=1, business_id=1, code="P", name="P", variant_mode="inventory"))
        db.add_all(
            [Warehouse(id=wid, business_id=1, code=str(wid), name=str(wid)) for wid in (1, 2)]
        )
        db.add(
            WarehouseDocument(
                id=1,
                business_id=1,
                code="A",
                doc_type="adjustment",
                source_type="manual",
                document_date=date(2026, 11, 26),
                status="posted",
                warehouse_id_from=1,
                warehouse_id_to=1,
                extra_info={"system_origin": "variant_allocation", "product_id": 1},
            )
        )
        db.add_all(
            [
                WarehouseDocumentLine(
                    id=line_id,
                    warehouse_document_id=1,
                    warehouse_id=1,
                    product_id=1,
                    movement=movement,
                    quantity=4,
                )
                for line_id, movement in [(1, "out"), (2, "in")]
            ]
        )
        db.add(
            WarehouseLineVariantAllocation(
                id=1,
                business_id=1,
                warehouse_document_line_id=2,
                product_id=1,
                variant_id=1,
                quantity=4,
            )
        )
        db.commit()
        yield db
    engine.dispose()


def test_replay_returns_original_adjustment_without_reallocating(conversion, monkeypatch):
    def unexpected_write(*args):
        pytest.fail("Replaying an effective conversion must not create a warehouse document")

    monkeypatch.setattr(warehouse_service, "create_manual_warehouse_document", unexpected_write)
    for variant_id in (1, 2):
        result = service.enable_inventory_variants(
            conversion,
            1,
            1,
            1,
            {"warehouse_id": 1, "splits": [{"variant_id": variant_id, "quantity": "4"}]},
        )
        assert result["warehouse_document_id"] == 1
        assert Decimal(result["allocated"]) == 4


def test_other_warehouse_and_metadata_without_allocation_do_not_prove_conversion(
    conversion, monkeypatch
):
    allocations = conversion.query(WarehouseLineVariantAllocation)
    attempted_warehouses = []

    def record_create(db, business_id, user_id, payload):
        attempted_warehouses.append(payload["warehouse_id_to"])
        return db.get(WarehouseDocument, 1)

    monkeypatch.setattr(warehouse_service, "create_manual_warehouse_document", record_create)
    monkeypatch.setattr(service, "post_warehouse_document", lambda *args: None)
    for wid in (2, 1):
        service.enable_inventory_variants(
            conversion,
            1,
            1,
            1,
            {"warehouse_id": wid, "splits": [{"variant_id": 1, "quantity": "4"}]},
        )
        if wid == 2:
            allocations.delete()
            conversion.query(WarehouseDocumentLine).filter_by(movement="out").delete()
    assert attempted_warehouses == [2, 1]


@pytest.mark.parametrize("status", ["cancelled", "posted"])
def test_ambiguous_conversion_leaves_existing_history(conversion, status):
    conversion.get(WarehouseDocument, 1).status = status
    if status == "posted":
        conversion.query(WarehouseLineVariantAllocation).delete()
    with pytest.raises(ApiError) as caught:
        service.enable_inventory_variants(
            conversion, 1, 1, 1, {"warehouse_id": 1, "splits": [{"variant_id": 1, "quantity": "4"}]}
        )
    assert (caught.value.code, caught.value.status_code) == (
        "VARIANT_ALLOCATION_HISTORY_CONFLICT",
        409,
    )
