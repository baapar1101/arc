from datetime import date
from decimal import Decimal

import pytest
from sqlalchemy import create_engine
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
from app.services.warehouse_service import _validate_manual_receipt_variant_cancellation

DAY = date(2026, 11, 11)


@pytest.mark.parametrize("replacement", [4, 5])
def test_receipt_cancel_checks_combined_quantity_in_the_same_warehouse_and_variant(
    monkeypatch, replacement
):
    monkeypatch.setattr(business_calendar, "business_today", lambda _: DAY)
    engine = create_engine("sqlite://")
    try:
        with engine.begin() as connection:
            for model in (
                Product,
                Document,
                InvoiceItemLine,
                InvoiceItemLineVariantAllocation,
                WarehouseDocument,
                WarehouseDocumentLine,
                WarehouseLineVariantAllocation,
            ):
                connection.execute(CreateTable(model.__table__, include_foreign_key_constraints=[]))
        with Session(engine, autoflush=False) as db:
            invoice = Document(
                id=1,
                business_id=1,
                fiscal_year_id=1,
                currency_id=1,
                created_by_user_id=1,
                document_type="invoice_sales",
                document_date=DAY,
                code="SALE",
                is_proforma=False,
            )
            db.add_all(
                [
                    Product(id=1, business_id=1, code="P", name="P", variant_mode="inventory"),
                    invoice,
                    InvoiceItemLine(
                        id=1,
                        document_id=1,
                        product_id=1,
                        quantity=5,
                        extra_info={
                            "warehouse_id": 1,
                            "movement": "out",
                            "inventory_tracked": True,
                        },
                    ),
                    InvoiceItemLineVariantAllocation(
                        id=1,
                        business_id=1,
                        invoice_item_line_id=1,
                        product_id=1,
                        variant_id=1,
                        quantity=5,
                        attributes_snapshot=[],
                    ),
                ]
            )
            for doc_id in (1, 2):
                db.add(
                    WarehouseDocument(
                        id=doc_id,
                        business_id=1,
                        code=f"IN-{doc_id}",
                        document_date=DAY,
                        status="posted",
                        doc_type="receipt",
                        source_type="manual",
                    )
                )
            lines = []
            for line_id, (doc_id, warehouse_id, variant_id, quantity) in enumerate(
                [(1, 1, 1, 5), (1, 1, 1, 5), (2, 1, 1, replacement), (2, 1, 2, 20), (2, 2, 1, 20)],
                1,
            ):
                line = WarehouseDocumentLine(
                    id=line_id,
                    warehouse_document_id=doc_id,
                    warehouse_id=warehouse_id,
                    product_id=1,
                    movement="in",
                    quantity=quantity,
                )
                lines.append(line)
                db.add_all(
                    [
                        line,
                        WarehouseLineVariantAllocation(
                            id=line_id,
                            business_id=1,
                            warehouse_document_line_id=line_id,
                            product_id=1,
                            variant_id=variant_id,
                            quantity=quantity,
                        ),
                    ]
                )
            db.commit()
            receipt = db.get(WarehouseDocument, 1)
            if replacement == 4:
                with pytest.raises(ApiError) as error:
                    _validate_manual_receipt_variant_cancellation(db, receipt, lines[:2])
                assert (error.value.code, error.value.status_code) == (
                    "VARIANT_RECEIPT_CANCEL_INSUFFICIENT_STOCK",
                    409,
                )
                details = error.value.detail["error"]["details"]
                assert Decimal(details["receipt_quantity"]) == 10
                assert Decimal(details["remaining_available_quantity"]) == -1
            else:
                _validate_manual_receipt_variant_cancellation(db, receipt, lines[:2])
            assert receipt.status == "posted"
    finally:
        engine.dispose()
