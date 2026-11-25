from decimal import Decimal

import pytest

from adapters.db import models
from adapters.db.models.invoice_item_line import InvoiceItemLine
from adapters.db.models.product_variant import ProductVariant
from adapters.db.models.product_variant_allocation import InvoiceItemLineVariantAllocation
from app.core.responses import ApiError
from app.services.variant_inventory_service import compute_available_variant_stock
from app.services.warehouse_service import (
    cancel_warehouse_document,
    create_manual_warehouse_document,
    post_warehouse_document,
)
from tests.test_warehouse_transfer_currency import DAY
from tests.test_warehouse_transfer_currency import transfer_db as transfer_db


@pytest.mark.parametrize("negative", [False, True])
@pytest.mark.parametrize("replacement,reserved", [(4, 5), (5, 5), (0, 0)])
def test_manual_production_receipt_cancel_uses_whole_variant_effect(transfer_db, negative, replacement, reserved):
    db = transfer_db
    business, product = db.get(models.Business, 1), db.get(models.Product, 1)
    business.allow_negative_inventory_for_bulk = negative
    product.variant_mode, product.track_inventory = "inventory", True
    db.add_all([ProductVariant(id=1, business_id=1, product_id=1, combination_key="one"),
                ProductVariant(id=2, business_id=1, product_id=1, combination_key="two")])
    db.commit()

    def receipt(kind, entries):
        document = create_manual_warehouse_document(db, 1, 1, {
            "doc_type": kind, "document_date": DAY.isoformat(), "warehouse_id_to": 11,
            "lines": [{"product_id": 1, "quantity": qty, "allocations": [{"variant_id": vid, "quantity": qty}],
                       "extra_info": {"unit": "main", "cost_price": 100}} for vid, qty in entries],
        })
        post_warehouse_document(db, document.id)
        db.commit()
        return document.id

    did = receipt("production_in", [(1, 5), (1, 5)])
    # A different Variant's surplus must never cover this Variant's commitment.
    receipt("receipt", ([(1, replacement)] if replacement else []) + [(2, 30)])
    if reserved:
        invoice = models.Document(business_id=1, fiscal_year_id=1, currency_id=2, created_by_user_id=1,
                                  document_type="invoice_sales", code="COMMITMENT", document_date=DAY, is_proforma=False)
        db.add(invoice)
        db.flush()
        item = InvoiceItemLine(document_id=invoice.id, product_id=1, quantity=reserved,
                                      extra_info={"unit": "main", "warehouse_id": 11, "movement": "out", "inventory_tracked": True})
        db.add(item)
        db.flush()
        db.add(InvoiceItemLineVariantAllocation(business_id=1, invoice_item_line_id=item.id, product_id=1,
                                               variant_id=1, quantity=reserved, attributes_snapshot=[]))
        db.commit()
    original_count = db.query(models.WarehouseDocument).count()
    if replacement < reserved:
        with pytest.raises(ApiError) as error:
            cancel_warehouse_document(db, 1, did, 1)
        assert (error.value.code, error.value.status_code) == ("VARIANT_PRODUCTION_RECEIPT_CANCEL_INSUFFICIENT_STOCK", 409)
        assert Decimal(error.value.detail["error"]["details"]["receipt_quantity"]) == 10
        db.rollback()
        assert db.get(models.WarehouseDocument, did).status == "posted"
        assert db.query(models.WarehouseDocument).count() == original_count
        assert compute_available_variant_stock(db, 1, 1, 11, 1, DAY) == 10 + replacement - reserved
    else:
        reverse = cancel_warehouse_document(db, 1, did, 1)
        db.commit()
        assert reverse.status == db.get(models.WarehouseDocument, did).status == "cancelled"
        assert compute_available_variant_stock(db, 1, 1, 11, 1, DAY) == replacement - reserved
        with pytest.raises(ApiError) as error:
            cancel_warehouse_document(db, 1, did, 1)
        assert error.value.code == "NOT_CANCELLABLE"
