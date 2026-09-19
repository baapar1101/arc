"""Type-2 Moadian invoices must validate without buyer tax IDs."""

from __future__ import annotations

from types import SimpleNamespace
from unittest.mock import MagicMock, patch

from app.integrations.moadian.invoice_builder import (
    InvoiceBuilder,
    ensure_person_snapshot_on_document_dict,
)
from app.services.tax_validation_service import validate_document_for_tax


def _person(**kwargs):
    defaults = dict(
        id=172528,
        alias_name="محمدرضا دروا",
        first_name="محمدرضا",
        last_name="دروا",
        company_name=None,
        national_id=None,
        economic_id=None,
        postal_code=None,
        address=None,
        mobile=None,
        phone=None,
        legal_entity_type=None,
    )
    defaults.update(kwargs)
    return SimpleNamespace(**defaults)


def _document(person_id=172528, net=1_000_000):
    return SimpleNamespace(
        id=141007,
        business_id=6353,
        document_type="invoice_sales",
        extra_info={
            "person_id": person_id,
            "tax_workspace": True,
            "tax_status": "not_sent",
            "totals": {"net": net},
        },
    )


def _mock_db_with_person(person, lines=None):
    db = MagicMock()
    lines = lines if lines is not None else [
        SimpleNamespace(
            id=1,
            product_id=10,
            extra_info={"tax_amount": 90_000},
        )
    ]
    product = SimpleNamespace(
        id=10,
        name="کالا",
        tax_code="2330001421954",
        tax_unit_id=1627,
    )

    def query(model):
        q = MagicMock()
        name = getattr(model, "__name__", str(model))
        if name == "Person" or "person" in str(model).lower():
            q.filter.return_value.first.return_value = person
        elif "InvoiceItemLine" in str(model) or "invoice_item" in str(model).lower():
            q.filter.return_value.all.return_value = lines
        elif "Product" in str(model) or "product" in str(model).lower():
            q.filter.return_value.first.return_value = product
        else:
            q.filter.return_value.first.return_value = None
            q.filter.return_value.all.return_value = []
        return q

    db.query.side_effect = query
    return db


def test_validate_allows_person_without_tax_ids() -> None:
    person = _person(national_id=None, economic_id=None)
    db = _mock_db_with_person(person)
    result = validate_document_for_tax(db, _document())
    assert result["valid"] is True
    assert result["issues"] == []


def test_validate_allows_placeholder_invalid_tax_ids() -> None:
    person = _person(national_id="0", economic_id="0")
    db = _mock_db_with_person(person)
    result = validate_document_for_tax(db, _document())
    assert result["valid"] is True
    codes = {i["code"] for i in result["issues"]}
    assert "PERSON_TAX_ID_MISSING" not in codes
    assert "PERSON_NATIONAL_ID_INVALID" not in codes
    assert "PERSON_ECONOMIC_CODE_INVALID" not in codes


def test_validate_still_requires_person() -> None:
    db = _mock_db_with_person(None, lines=[])
    doc = _document(person_id=None)
    doc.extra_info.pop("person_id", None)
    # no lines → also LINES_MISSING; focus on person
    result = validate_document_for_tax(db, doc)
    codes = {i["code"] for i in result["issues"]}
    assert "PERSON_MISSING" in codes


def test_builder_sends_type2_without_buyer_fields() -> None:
    builder = InvoiceBuilder(seller_economic_code="12345678901")
    document = {
        "id": 141007,
        "document_type": "invoice_sales",
        "document_date": "2026-05-30T10:00:00",
        "product_lines": [
            {
                "product_id": 10,
                "product_name": "کالا",
                "product_tax_code": "2330001421954",
                "product_main_unit": "عدد",
                "quantity": 1,
                "extra_info": {
                    "unit_price": 1_000_000,
                    "tax_amount": 90_000,
                    "tax_snapshot": {
                        "tax_code": "2330001421954",
                        "tax_unit_id": 1627,
                    },
                },
            }
        ],
        "extra_info": {
            "person_id": 172528,
            "person_snapshot": {
                "national_id": None,
                "economic_code": None,
                "postal_code": None,
                "name": "محمدرضا دروا",
            },
            "totals": {"net": 1_090_000},
        },
    }
    tax_setting = SimpleNamespace(economic_code="12345678901", tax_memory_id="A123")
    dto = builder.build_invoice_dto(document, tax_setting, submission_mode="normal")
    assert dto.header.inty == 2
    assert getattr(dto.header, "tob", None) in (None,)
    assert getattr(dto.header, "tinb", None) in (None,)
    assert getattr(dto.header, "bid", None) in (None,)
    assert getattr(dto.header, "bpc", None) in (None,)


def test_ensure_person_snapshot_refreshes_stale_ids() -> None:
    person = _person(national_id=None, economic_id=None)
    db = MagicMock()
    db.query.return_value.filter.return_value.first.return_value = person
    document = {
        "extra_info": {
            "person_id": 172528,
            "person_snapshot": {
                "national_id": "0",
                "economic_code": "0",
                "name": "old",
            },
        }
    }
    out = ensure_person_snapshot_on_document_dict(db, document)
    snap = out["extra_info"]["person_snapshot"]
    assert snap.get("national_id") in (None, "")
    assert snap.get("economic_code") in (None, "")
