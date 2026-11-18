from copy import deepcopy
from decimal import Decimal

import pytest
from sqlalchemy.schema import CreateTable

from adapters.db.models.document import Document
from adapters.db.models.invoice_item_line import InvoiceItemLine
from adapters.db.models.product import Product
from adapters.db.models.product_variant import ProductVariant
from adapters.db.models.product_variant_allocation import InvoiceItemLineVariantAllocation
from adapters.db.models.warehouse_document import WarehouseDocument
from adapters.db.models.warehouse_document_line import WarehouseDocumentLine
from app.core.responses import ApiError
from app.services.woo_proforma_service import prepare_woo_proforma_finalization
from tests.test_woo_return_source_service import HEADER, IDENTITY
from tests.test_woo_return_source_service import db as db


@pytest.fixture
def proforma(db):
    for model in (Product, ProductVariant):
        db.execute(CreateTable(model.__table__, include_foreign_key_constraints=[]))
    db.add_all([
        Product(id=1, business_id=1, name="Carton", code="P", variant_mode="inventory", inventory_mode="bulk",
                track_inventory=True, main_unit="کارتن", secondary_unit="عدد", unit_conversion_factor=10),
        ProductVariant(id=1, business_id=1, product_id=1, combination_key="red", is_active=True),
    ])
    document = db.get(Document, 1)
    document.is_proforma = True
    line = db.get(InvoiceItemLine, 1)
    line.extra_info = {**IDENTITY, "unit": "عدد", "unit_price": 250, "tax_amount": 75, "line_total": 825}
    db.get(WarehouseDocument, 1).status = "draft"
    db.commit()
    return document, {
        "invoice_type": "invoice_sales", "is_proforma": False, "extra_info": dict(HEADER),
        "lines": [{"product_id": 1, "quantity": 3, "extra_info": dict(line.extra_info),
                   "allocations": [{"variant_id": 1, "quantity": 3}]}],
    }


@pytest.mark.parametrize("unit", ["عدد", "main"])
def test_first_posting_projects_only_unit_without_changing_input_or_persisted_proforma(db, proforma, unit):
    document, payload = proforma
    db.get(InvoiceItemLine, 1).extra_info = {**payload["lines"][0]["extra_info"], "unit": unit}
    db.commit()
    original = deepcopy(payload)
    result = prepare_woo_proforma_finalization(db, document, payload, "invoice_sales")
    assert result["lines"][0]["extra_info"]["unit"] == "main"
    result["lines"][0]["extra_info"]["unit"] = "عدد"
    assert result == original == payload
    assert document.is_proforma and db.get(InvoiceItemLine, 1).extra_info["unit"] == unit


@pytest.mark.parametrize("fault", ["order", "person", "item", "product", "variant", "duplicate", "unallocated", "missing",
                                  "missing_lines",
                                  "allocation_tenant", "posted", "partial", "cancelled"])
def test_unproven_conversion_is_rejected_before_any_change(db, proforma, fault):
    document, payload = proforma
    if fault in {"order", "person"}:
        payload["extra_info"]["wc_order_id" if fault == "order" else "person_id"] = 2
    elif fault == "item":
        payload["lines"][0]["extra_info"]["wc_item_id"] = 999
    elif fault == "product":
        payload["lines"][0]["product_id"] = 2
    elif fault == "variant":
        payload["lines"][0]["allocations"][0]["variant_id"] = 2
    elif fault == "duplicate":
        payload["lines"].append(deepcopy(payload["lines"][0]))
    elif fault == "unallocated":
        db.query(InvoiceItemLineVariantAllocation).delete()
    elif fault == "missing":
        payload["lines"][0].pop("allocations")
    elif fault == "missing_lines":
        payload.pop("lines")
    elif fault == "allocation_tenant":
        db.get(InvoiceItemLineVariantAllocation, 1).business_id = 2
    else:
        db.get(WarehouseDocument, 1).status = "cancelled" if fault == "cancelled" else "posted"
        if fault == "posted":
            db.get(WarehouseDocumentLine, 1).quantity = 3
    db.commit()
    with pytest.raises(ApiError) as error:
        prepare_woo_proforma_finalization(db, document, payload, "invoice_sales")
    assert (error.value.code, error.value.status_code) == ("WOO_PROFORMA_SOURCE_AMBIGUOUS", 409)
    assert document.is_proforma and db.get(InvoiceItemLine, 1).quantity == Decimal(3)


@pytest.mark.parametrize("outside_scope", ["manual", "posted_sale", "payment_only", "ordinary", "not_tracked"])
def test_other_invoice_paths_keep_their_existing_units(db, proforma, outside_scope):
    document, payload = proforma
    if outside_scope == "manual":
        document.extra_info = {**HEADER, "source": "manual"}
    elif outside_scope == "posted_sale":
        document.is_proforma = False
    elif outside_scope == "payment_only":
        payload = {"payments": []}
    elif outside_scope == "ordinary":
        db.query(InvoiceItemLineVariantAllocation).delete()
        payload["lines"][0].pop("allocations")
    else:
        db.get(Product, 1).track_inventory = False
    db.commit()
    assert prepare_woo_proforma_finalization(db, document, payload, "invoice_sales") == payload
