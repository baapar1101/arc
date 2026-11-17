from datetime import date
from decimal import Decimal

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import Session
from sqlalchemy.schema import CreateTable

from adapters.db.models.document import Document
from adapters.db.models.invoice_item_line import InvoiceItemLine
from adapters.db.models.product_variant_allocation import (
    InvoiceItemLineVariantAllocation,
    WarehouseLineVariantAllocation,
)
from adapters.db.models.warehouse_document import WarehouseDocument
from adapters.db.models.warehouse_document_line import WarehouseDocumentLine
from app.core.responses import ApiError
from app.services.woo_return_source_service import STOCK_KEY, prepare_woo_return_stock

DAY = date(2026, 11, 11)
HEADER = {"source": "woocommerce", "wc_order_id": 100, "person_id": 1}
IDENTITY = {"wc_item_id": 77, "wc_product_id": 1, "wc_variation_id": 22, "warehouse_id": 1}


@pytest.fixture
def db():
    engine = create_engine("sqlite://")
    with engine.begin() as connection:
        for model in (
            Document, InvoiceItemLine, InvoiceItemLineVariantAllocation, WarehouseDocument, WarehouseDocumentLine,
            WarehouseLineVariantAllocation,
        ):
            connection.execute(CreateTable(model.__table__, include_foreign_key_constraints=[]))
    with Session(engine) as session:
        session.add_all([
            Document(
                id=1, business_id=1, fiscal_year_id=1, currency_id=1, created_by_user_id=1, code="SALE",
                document_type="invoice_sales", document_date=DAY, extra_info=HEADER,
            ),
            InvoiceItemLine(id=1, document_id=1, product_id=1, quantity=3, extra_info=IDENTITY),
            InvoiceItemLineVariantAllocation(
                id=1, invoice_item_line_id=1, business_id=1, product_id=1, variant_id=1,
                quantity=3, attributes_snapshot={},
            ),
            WarehouseDocument(
                id=1, business_id=1, document_date=DAY, code="ISSUE", status="posted",
                doc_type="issue", source_type="invoice", source_document_id=1,
            ),
            WarehouseDocumentLine(
                id=1, warehouse_document_id=1, warehouse_id=1, product_id=1, movement="out", quantity=1,
                extra_info={"invoice_item_line_id": 1, "inventory_quantity_unit": "main", "source_line_quantity": 3},
            ),
            WarehouseLineVariantAllocation(
                id=1, warehouse_document_line_id=1, source_document_allocation_id=1,
                business_id=1, product_id=1, variant_id=1, quantity=1,
            ),
        ])
        session.commit()
        yield session
    engine.dispose()


def _project(db, *, business_id=1, quantity=1, variant_id=1):
    return prepare_woo_return_stock(
        db, business_id, {"extra_info": {**HEADER, "returned_from_invoice_id": 1}},
        [{"product_id": 1, "quantity": quantity, "extra_info": IDENTITY,
          "allocations": [{"variant_id": variant_id, "quantity": quantity}]}],
        "invoice_sales_return",
    )[0]


def test_partial_returns_use_posted_quantity_and_carry_rounding_remainder(db):
    pieces = []
    for return_id in (2, 3, 4):
        projection = _project(db)
        pieces.append(Decimal(projection["quantity_main"]))
        db.add_all([
            Document(
                id=return_id, business_id=1, fiscal_year_id=1, currency_id=1, created_by_user_id=1,
                code=f"RETURN-{return_id}", document_type="invoice_sales_return", document_date=DAY,
                extra_info={**HEADER, "returned_from_invoice_id": 1},
                developer_settings={STOCK_KEY: {str(return_id): projection}},
            ),
            InvoiceItemLine(id=return_id, document_id=return_id, product_id=1, quantity=1, extra_info=IDENTITY),
        ])
        db.commit()
    assert pieces == list(map(Decimal, ("0.333333", "0.333334", "0.333333")))
    with pytest.raises(ApiError) as error:
        _project(db)
    assert error.value.code == "WOO_RETURN_EXCEEDS_ISSUE"


@pytest.mark.parametrize("mode", ["tenant", "variant", "unlinked"])
def test_ambiguous_source_is_rejected_before_recording_return(db, mode):
    if mode == "unlinked":
        db.get(WarehouseLineVariantAllocation, 1).source_document_allocation_id = None
        db.commit()
    with pytest.raises(ApiError) as error:
        _project(db, business_id=2 if mode == "tenant" else 1, variant_id=2 if mode == "variant" else 1)
    assert error.value.code == "WOO_RETURN_SOURCE_AMBIGUOUS"
    assert db.query(Document).count() == 1
