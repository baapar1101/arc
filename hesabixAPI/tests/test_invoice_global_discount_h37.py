from copy import deepcopy
from decimal import Decimal

import pytest

from adapters.db import models
from adapters.db.models.invoice_item_line import InvoiceItemLine
from app.core.responses import ApiError
from app.services.invoice_service import create_invoice, update_invoice
from tests.test_invoice_line_total_h23 import create, db as db, line
from tests.test_invoice_net_contract_h30 import db as finalized_db

D = Decimal


def _stored(db, document_id):
    doc = db.get(models.Document, document_id)
    lines = db.query(InvoiceItemLine).filter_by(document_id=document_id).order_by(InvoiceItemLine.id)
    print(f"stored totals for {doc.code}: {doc.extra_info['totals']}")
    return [
        (D(str(row.extra_info["line_total"])), D(str(row.extra_info.get("tax_amount", 0))))
        for row in lines
    ], doc.extra_info["totals"]


@pytest.mark.parametrize("sent", [100, 90])
def test_create_accepts_pre_discount_and_server_allocated_amount(db, sent):
    did = create(db, [line(1, 100, sent)], discount=10)
    assert _stored(db, did) == ([(D(90), D(0))], {"gross": 100, "discount": 10, "tax": 0,
                                                 "net": 90, "adjustments_net": 0, "adjustments_tax": 0})


def test_create_rejects_mismatched_line_before_writing(db):
    with pytest.raises(ApiError) as error:
        create(db, [line(1, 100, 91)], discount=10)
    assert (error.value.code, error.value.status_code) == ("INCONSISTENT_LINE_TOTAL", 422)
    assert db.query(models.Document).count() == 0
    assert db.query(models.DocumentLine).count() == 0


@pytest.mark.parametrize("discount_payload", [{"header_discount": 10}, {"global_discount_amount": 10}])
def test_discount_fields_do_not_exempt_unsupported_invoice_type(db, discount_payload):
    payload = {"invoice_type": "invoice_waste", "currency_id": 1, "code": "NO-DISCOUNT", "is_proforma": True, "lines": [line(1, 100, 91)],
               **discount_payload}
    with pytest.raises(ApiError) as error:
        create_invoice(db, 1, 1, payload, commit=False)
    assert (error.value.code, error.value.status_code) == ("INCONSISTENT_LINE_TOTAL", 422)
    assert db.query(models.Document).count() == 0


def test_update_validates_before_mutation_and_accepts_allocated_total(db):
    did = create(db, [line(1, 100, 100)], discount=10)
    db.commit()
    doc = db.get(models.Document, did)
    original = _stored(db, did)
    original_date = doc.document_date
    with pytest.raises(ApiError) as error:
        update_invoice(db, did, 1, {"document_date": "2026-11-12", "lines": [line(1, 100, 91)]})
    assert (error.value.code, error.value.status_code) == ("INCONSISTENT_LINE_TOTAL", 422)
    assert doc.document_date == original_date
    assert doc.code == "H23"
    assert _stored(db, did) == original

    update_invoice(db, did, 1, {"code": "H37-EDIT", "lines": [line(1, 100, 90)]})
    assert doc.code == "H37-EDIT"
    assert _stored(db, did) == original


def test_uses_server_allocation_rounding_remainder_and_tax(db):
    items = [line(1, 1, 1.1, product) for product in (1, 2, 2)]
    for item in items:
        item["extra_info"].update(tax_rate=10, tax_amount=0.1)
    did = create(db, items, discount=0.01)
    db.commit()
    observed, totals = _stored(db, did)
    assert observed == [(D("1.09"), D("0.10")), (D("1.10"), D("0.10")), (D("1.10"), D("0.10"))]
    assert (totals["discount"], totals["tax"], totals["net"]) == (0.01, 0.3, 3.29)

    wrong = deepcopy(items)
    wrong[1]["extra_info"]["line_total"] = 1.07
    with pytest.raises(ApiError) as error:
        update_invoice(db, did, 1, {"code": "INVALID", "currency_id": 1, "lines": wrong})
    assert (error.value.code, error.value.status_code) == ("INCONSISTENT_LINE_TOTAL", 422)
    assert error.value.detail["error"]["details"]["line_index"] == 2
    assert _stored(db, did) == (observed, totals)

    for item, (total, tax) in zip(items, observed):
        item["extra_info"].update(line_total=float(total), tax_amount=float(tax))
    update_invoice(db, did, 1, {"code": "ROUNDTRIP", "currency_id": 1, "lines": items})
    assert _stored(db, did) == (observed, totals)

def test_finalized_update_rejects_before_rebuilding_receivable(finalized_db):
    db = finalized_db
    item = line(1, 100, 110)
    item["extra_info"].pop("unit")
    item["extra_info"].update(tax_rate=10, tax_amount=10)
    result = create_invoice(db, 1, 1, {
        "invoice_type": "invoice_sales", "document_date": "2026-11-11", "currency_id": 1,
        "code": "H37-GL", "global_discount_amount": 10,
        "extra_info": {"person_id": 1, "post_inventory": False}, "lines": [item],
    }, commit=False)
    db.commit()
    did = result["data"]["id"]
    doc = db.get(models.Document, did)
    gl = db.query(models.DocumentLine).filter_by(document_id=did).order_by(models.DocumentLine.id)

    def posted():
        return [(row.id, row.account.code, row.debit, row.credit) for row in gl]

    before = posted()
    assert [(code, debit, credit) for _, code, debit, credit in before] == [
        ("10401", 99, 0), ("50001", 0, 100), ("50003", 10, 0), ("20101", 0, 9),
    ]
    body_before = _stored(db, did)
    assert body_before[0] == [(D(99), D(9))]
    bad = line(1, 100, 101)
    bad["extra_info"].pop("unit")
    bad["extra_info"].update(tax_rate=10, tax_amount=10)
    with pytest.raises(ApiError) as error:
        update_invoice(db, did, 1, {"code": "H37-GL-BAD", "currency_id": 1, "lines": [bad]})
    assert (error.value.code, error.value.status_code) == ("INCONSISTENT_LINE_TOTAL", 422)
    assert doc.code == "H37-GL"
    assert posted() == before
    assert _stored(db, did) == body_before
    print(f"persisted GL after rejected update: {posted()}")
