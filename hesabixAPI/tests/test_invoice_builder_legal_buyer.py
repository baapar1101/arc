"""Legal buyers must go as Moadian type 1 with tinb, without changing VAT amounts."""

from __future__ import annotations

from types import SimpleNamespace

from app.integrations.moadian.invoice_builder import (
    InvoiceBuilder,
    _resolve_buyer_tin,
)


def _sale_document(*, snapshot: dict, net: int = 440_000_000, tax: int = 40_000_000, gross: int = 400_000_000):
    return {
        "id": 246736,
        "document_type": "invoice_sales",
        "document_date": "2026-11-07T12:43:38",
        "registered_at": "2026-11-07T12:43:38",
        "product_lines": [
            {
                "product_id": 10,
                "product_name": "کالا",
                "product_tax_code": "2330001421954",
                "product_main_unit": "عدد",
                "quantity": 1,
                "extra_info": {
                    "unit_price": gross,
                    "tax_amount": tax,
                    "tax_snapshot": {
                        "tax_code": "2330001421954",
                        "tax_unit_id": 1627,
                    },
                },
            }
        ],
        "extra_info": {
            "person_id": 185796,
            "person_snapshot": snapshot,
            "totals": {"net": net, "tax": tax, "gross": gross},
        },
    }


def _build(snapshot: dict, *, mode: str = "normal"):
    builder = InvoiceBuilder(seller_economic_code="14013470855")
    tax_setting = SimpleNamespace(economic_code="14013470855", tax_memory_id="A48RYR")
    return builder.build_invoice_dto(_sale_document(snapshot=snapshot), tax_setting, submission_mode=mode)


def test_resolve_buyer_tin_prefers_legal_national_id_over_legacy_12_digit() -> None:
    assert _resolve_buyer_tin("10103299986", "411319575443") == "10103299986"


def test_resolve_buyer_tin_ignores_10_digit_natural_as_tinb() -> None:
    assert _resolve_buyer_tin("0012345678", "") is None


def test_legal_buyer_with_legacy_12_digit_economic_code_sends_type1() -> None:
    """Production case: شرکت حقوقی با شناسه ملی ۱۱ و شناسه اقتصادی ۱۲ رقمی قدیم."""
    dto = _build(
        {
            "name": "توسعه کشاورزی هزاره سوم",
            "national_id": "10103299986",
            "economic_code": "411319575443",
            "postal_code": "1991793541",
            "legal_entity_type": "legal",
        }
    )
    h = dto.header
    assert h.inty == 1
    assert h.tob == 2
    assert h.tinb == "10103299986"
    assert h.bid is None
    assert h.setm == 1
    assert h.tvam == 40_000_000
    assert h.tbill == 440_000_000
    assert dto.body[0].vam == 40_000_000


def test_legal_buyer_national_id_alone_is_enough_for_type1() -> None:
    dto = _build(
        {
            "national_id": "10103299986",
            "economic_code": None,
            "postal_code": None,
            "legal_entity_type": "legal",
        }
    )
    assert dto.header.inty == 1
    assert dto.header.tob == 2
    assert dto.header.tinb == "10103299986"
    assert dto.header.bid is None
    assert dto.header.bpc is None


def test_legacy_12_digit_economic_code_without_national_id_stays_type2() -> None:
    dto = _build(
        {
            "national_id": None,
            "economic_code": "411319575443",
            "legal_entity_type": "legal",
        }
    )
    assert dto.header.inty == 2
    assert dto.header.tinb is None
    assert dto.header.tob is None
    assert dto.header.bid is None


def test_legal_11_digit_economic_code_without_national_id_sends_type1() -> None:
    dto = _build(
        {
            "national_id": None,
            "economic_code": "14013470855",
            "legal_entity_type": "legal",
        }
    )
    assert dto.header.inty == 1
    assert dto.header.tob == 2
    assert dto.header.tinb == "14013470855"


def test_natural_buyer_without_ids_still_type2() -> None:
    dto = _build(
        {
            "national_id": None,
            "economic_code": None,
            "postal_code": None,
            "legal_entity_type": "natural",
        }
    )
    assert dto.header.inty == 2
    assert dto.header.tinb is None
    assert dto.header.bid is None


def test_natural_buyer_with_national_id_and_postal_sends_type1_bid() -> None:
    dto = _build(
        {
            "national_id": "0013540809",
            "economic_code": None,
            "postal_code": "1991793541",
            "legal_entity_type": "natural",
        }
    )
    assert dto.header.inty == 1
    assert dto.header.tob == 1
    assert dto.header.bid == "0013540809"
    assert dto.header.bpc == "1991793541"
    assert dto.header.tinb is None


def test_type1_legal_does_not_change_vat_totals() -> None:
    type1 = _build(
        {
            "national_id": "10103299986",
            "economic_code": "411319575443",
            "legal_entity_type": "legal",
        }
    )
    type2 = _build(
        {
            "national_id": None,
            "economic_code": None,
        }
    )
    assert type1.header.inty == 1
    assert type2.header.inty == 2
    assert type1.header.tprdis == type2.header.tprdis
    assert type1.header.tadis == type2.header.tadis
    assert type1.header.tvam == type2.header.tvam
    assert type1.header.tbill == type2.header.tbill
    assert type1.body[0].vam == type2.body[0].vam
    assert type1.body[0].adis == type2.body[0].adis
