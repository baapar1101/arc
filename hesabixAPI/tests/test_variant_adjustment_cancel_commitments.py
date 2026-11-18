from datetime import date
from decimal import Decimal

import pytest
from sqlalchemy import create_engine, update
from sqlalchemy.orm import Session
from sqlalchemy.schema import CreateTable

from adapters.db.models.document import Document
from adapters.db.models.invoice_item_line import InvoiceItemLine
from adapters.db.models.product import Product
from adapters.db.models.product_variant_allocation import (
    InvoiceItemLineVariantAllocation,
    WarehouseLineVariantAllocation,
)
from adapters.db.models.warehouse_document import WarehouseDocument
from adapters.db.models.warehouse_document_line import WarehouseDocumentLine
from app.core import business_calendar
from app.core.responses import ApiError
from app.services.warehouse_service import (
    _validate_manual_variant_cancellation,
    cancel_warehouse_document,
)

DAY = date(2026, 11, 11)
MODELS = (Product, Document, InvoiceItemLine, InvoiceItemLineVariantAllocation,
          WarehouseDocument, WarehouseDocumentLine, WarehouseLineVariantAllocation)


@pytest.fixture
def stock_case(monkeypatch):
    monkeypatch.setattr(business_calendar, "business_today", lambda _: DAY)
    engine = create_engine("sqlite://")
    with engine.begin() as connection:
        for model in MODELS:
            connection.execute(CreateTable(model.__table__, include_foreign_key_constraints=[]))
    with Session(engine, autoflush=False, expire_on_commit=False) as db:
        def prepare(base, entries, reserved):
            db.add_all([
                Product(id=1, business_id=1, code="P", name="P", variant_mode="inventory", main_unit="each"),
                Document(id=1, business_id=1, fiscal_year_id=1, currency_id=1, created_by_user_id=1,
                         code="SALE", document_type="invoice_sales", is_proforma=False, document_date=DAY),
                InvoiceItemLine(id=1, document_id=1, product_id=1, quantity=reserved,
                                extra_info={"warehouse_id": 1, "movement": "out", "unit": "main"}),
                InvoiceItemLineVariantAllocation(id=1, invoice_item_line_id=1, business_id=1, product_id=1,
                                                 variant_id=1, quantity=reserved, attributes_snapshot=[]),
                WarehouseDocument(id=1, business_id=1, code="ADJ", document_date=DAY, status="posted",
                                  doc_type="adjustment", source_type="manual"),
                WarehouseDocument(id=2, business_id=1, code="IN", document_date=DAY, status="posted",
                                  doc_type="receipt", source_type="manual"),
            ])
            lines = []
            for line_id, (doc_id, wid, vid, movement, qty) in enumerate(
                [(1, *entry) for entry in entries] + [(2, wid, vid, "in", qty) for wid, vid, qty in base], 1,
            ):
                line = WarehouseDocumentLine(id=line_id, warehouse_document_id=doc_id, product_id=1,
                                             warehouse_id=wid, movement=movement, quantity=qty)
                db.add_all([line, WarehouseLineVariantAllocation(
                    id=line_id, business_id=1, warehouse_document_line_id=line_id, product_id=1,
                    variant_id=vid, quantity=qty,
                )])
                if doc_id == 1:
                    lines.append(line)
            db.commit()
            return db, db.get(WarehouseDocument, 1), lines
        yield prepare
    engine.dispose()


@pytest.mark.parametrize("initial,incoming,outgoing,reserved,allowed", [
    (4, 10, 0, 5, False), (5, 10, 0, 5, True),
    (3, 5, 3, 5, False), (5, 5, 3, 5, True),
    (5, 5, 5, 5, True), (5, 3, 5, 3, True), (15, 0, 10, 5, True),
])
@pytest.mark.parametrize("reverse_order", [False, True])
def test_whole_adjustment_uses_net_effect_and_preserves_rows(
    stock_case, initial, incoming, outgoing, reserved, allowed, reverse_order,
):
    entries = ([(1, 1, "in", incoming)] if incoming else []) + ([(1, 1, "out", outgoing)] if outgoing else [])
    if incoming == 10:
        entries = [(1, 1, "in", 5), (1, 1, "in", 5)]
    db, doc, lines = stock_case([(1, 1, initial)], entries, reserved)
    if reverse_order:
        lines.reverse()
    before = [(r.id, r.quantity) for r in db.query(WarehouseLineVariantAllocation).all()]
    if allowed:
        _validate_manual_variant_cancellation(db, doc, lines)
    else:
        with pytest.raises(ApiError) as error:
            cancel_warehouse_document(db, 1, doc.id, 1)
        assert (error.value.code, error.value.status_code) == ("VARIANT_ADJUSTMENT_CANCEL_INSUFFICIENT_STOCK", 409)
        assert Decimal(error.value.detail["error"]["details"]["remaining_available_quantity"]) == initial - reserved
    assert doc.status == "posted" and db.query(WarehouseDocument).count() == 2
    assert [(r.id, r.quantity) for r in db.query(WarehouseLineVariantAllocation).all()] == before


@pytest.mark.parametrize("other_warehouse,other_variant", [(1, 2), (2, 1)])
def test_another_variant_or_warehouse_cannot_offset_shortage(stock_case, other_warehouse, other_variant):
    db, doc, lines = stock_case(
        [(1, 1, 3), (other_warehouse, other_variant, 100)],
        [(1, 1, "in", 5), (other_warehouse, other_variant, "out", 5)], 5,
    )
    with pytest.raises(ApiError) as error:
        _validate_manual_variant_cancellation(db, doc, lines)
    details = error.value.detail["error"]["details"]
    assert (details["warehouse_id"], details["variant_id"], Decimal(details["document_net_quantity"])) == (1, 1, 5)
    assert doc.status == "posted"


def test_stale_posted_document_cannot_be_cancelled_again(stock_case):
    db, doc, _ = stock_case([(1, 1, 5)], [(1, 1, "in", 10)], 5)
    db.execute(update(WarehouseDocument).where(WarehouseDocument.id == doc.id).values(status="cancelled"),
               execution_options={"synchronize_session": False})
    db.commit()
    assert doc.status == "posted"
    with pytest.raises(ApiError) as error:
        cancel_warehouse_document(db, 1, doc.id, 1)
    assert (error.value.code, error.value.status_code) == ("NOT_CANCELLABLE", 400)
    assert doc.status == "cancelled" and db.query(WarehouseDocument).count() == 2
