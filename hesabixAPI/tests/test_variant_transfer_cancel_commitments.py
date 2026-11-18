from decimal import Decimal

import pytest
from sqlalchemy import update

from adapters.db.models.invoice_item_line import InvoiceItemLine
from adapters.db.models.product_variant_allocation import WarehouseLineVariantAllocation
from adapters.db.models.warehouse_document import WarehouseDocument
from app.core.responses import ApiError
from app.services.warehouse_service import (
    _validate_manual_variant_cancellation,
    cancel_warehouse_document,
)
from tests.test_variant_adjustment_cancel_commitments import stock_case as stock_case


@pytest.mark.parametrize("replacement,allowed", [(4, False), (5, True)])
@pytest.mark.parametrize("destination", [1, 2])
@pytest.mark.parametrize("reverse_order", [False, True])
def test_whole_transfer_preserves_each_warehouse_commitment(stock_case, replacement, allowed, destination, reverse_order):
    source = 3 - destination
    entries = [(source, 1, "out", 5), (destination, 1, "in", 5)] * 2
    db, document, lines = stock_case([(source, 1, 10), (destination, 1, replacement)], entries, 5)
    document.doc_type = "transfer"
    document.warehouse_id_from, document.warehouse_id_to = source, destination
    invoice_line = db.get(InvoiceItemLine, 1)
    invoice_line.extra_info = {**invoice_line.extra_info, "warehouse_id": destination}
    db.commit()
    if reverse_order:
        lines.reverse()
    before = [(row.id, row.quantity) for row in db.query(WarehouseLineVariantAllocation)]
    if allowed:
        _validate_manual_variant_cancellation(db, document, lines)
    else:
        with pytest.raises(ApiError) as error:
            cancel_warehouse_document(db, 1, document.id, 1)
        assert (error.value.code, error.value.status_code) == ("VARIANT_TRANSFER_CANCEL_INSUFFICIENT_STOCK", 409)
        details = error.value.detail["error"]["details"]
        assert (details["warehouse_id"], details["variant_id"]) == (destination, 1)
        assert Decimal(details["document_net_quantity"]) == 10
        assert Decimal(details["remaining_available_quantity"]) == -1
    assert document.status == "posted" and db.query(WarehouseDocument).count() == 2
    assert [(row.id, row.quantity) for row in db.query(WarehouseLineVariantAllocation)] == before


def test_surplus_of_another_variant_does_not_cover_transfer_shortage(stock_case):
    entries = [(1, 1, "out", 5), (2, 1, "in", 5)] * 2 + [(1, 2, "out", 5), (2, 2, "in", 5)]
    db, document, lines = stock_case([(1, 1, 10), (2, 1, 4), (1, 2, 10), (2, 2, 100)], entries, 5)
    document.doc_type = "transfer"
    invoice = db.get(InvoiceItemLine, 1)
    invoice.extra_info = {**invoice.extra_info, "warehouse_id": 2}
    db.commit()
    with pytest.raises(ApiError) as error:
        _validate_manual_variant_cancellation(db, document, lines)
    assert error.value.code == "VARIANT_TRANSFER_CANCEL_INSUFFICIENT_STOCK"
    assert error.value.detail["error"]["details"]["variant_id"] == 1


def test_stale_posted_transfer_is_reloaded_before_cancellation(stock_case):
    db, document, _ = stock_case([(1, 1, 10), (2, 1, 5)], [(1, 1, "out", 10), (2, 1, "in", 10)], 1)
    document.doc_type = "transfer"
    db.commit()
    db.execute(update(WarehouseDocument).where(WarehouseDocument.id == document.id).values(status="cancelled"),
               execution_options={"synchronize_session": False})
    db.commit()
    assert document.status == "posted"
    with pytest.raises(ApiError) as error:
        cancel_warehouse_document(db, 1, document.id, 1)
    assert (error.value.code, error.value.status_code) == ("NOT_CANCELLABLE", 400)
    assert document.status == "cancelled" and db.query(WarehouseDocument).count() == 2
