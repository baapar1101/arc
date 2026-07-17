"""Tests for legacy Hesabix v1 API import helpers."""

from __future__ import annotations

import json
import zipfile
from io import BytesIO

import pytest

from app.services.legacy_import.archive import parse_legacy_archive
from app.services.legacy_import.expense_income_rows import (
    build_expense_income_payload,
    normalize_api_document_rows,
)
from app.services.legacy_import.id_map import LegacyIdMap
from app.services.legacy_import.mappers import (
    map_legacy_person_types,
    normalize_server_url,
    parse_legacy_date,
)


def test_normalize_server_url():
    assert normalize_server_url("") == "https://app.hesabix.ir"
    assert normalize_server_url("app.hesabix.ir") == "https://app.hesabix.ir"
    assert normalize_server_url("https://app.hesabix.ir/") == "https://app.hesabix.ir"


def test_legacy_response_indicates_accpro_required():
    from app.services.legacy_import.client import legacy_response_indicates_accpro_required

    assert legacy_response_indicates_accpro_required(
        '{"result":0,"message":"این قابلیت فقط برای کاربران افزونه accpro در دسترس است."}'
    )
    assert legacy_response_indicates_accpro_required("افزونه حسابداری پیشرفته فعال نیست")
    assert not legacy_response_indicates_accpro_required('{"result":0,"message":"خطای دیگر"}')
    assert not legacy_response_indicates_accpro_required("")


def test_map_legacy_person_types_defaults():
    assert map_legacy_person_types([]) == ["مشتری"]
    assert "مشتری" in map_legacy_person_types([1])
    assert "بازاریاب" in map_legacy_person_types([1, 2])


def test_parse_legacy_jalali_date():
    d = parse_legacy_date("1404/07/10")
    assert d.year >= 2024


def test_parse_legacy_archive_minimal():
    buf = BytesIO()
    manifest = {
        "version": "1.0",
        "sourceBusinessId": 1,
        "sourceBusinessName": "Test Biz",
    }
    with zipfile.ZipFile(buf, "w") as zf:
        zf.writestr("manifest.json", json.dumps(manifest))
        zf.writestr("data/business.json", json.dumps([{"id": 1, "name": "Test Biz"}]))
        zf.writestr("data/persons.json", json.dumps([]))
        zf.writestr("data/commodities.json", json.dumps([]))
        zf.writestr("data/hesabdari_docs.json", json.dumps([]))
        zf.writestr("data/hesabdari_rows.json", json.dumps([]))
    archive = parse_legacy_archive(buf.getvalue())
    assert archive.source_business_id == 1
    assert archive.source_business_name == "Test Biz"
    assert archive.counts()["persons"] == 0


class _StubChart:
    def resolve_account_id(self, ref_id, *, is_income=False, **kwargs):
        return 501 if ref_id == 98 else 502


def test_normalize_api_document_rows():
    api_rows = [
        {
            "ref": {"id": 98, "tableType": "calc"},
            "bd": 25,
            "des": "هزینه",
        },
        {
            "ref": {"id": 5, "tableType": "bank"},
            "bs": 25,
            "bankAccount": 36,
        },
    ]
    rows = normalize_api_document_rows(api_rows)
    assert rows[0]["ref_id"] == 98
    assert rows[0]["bd"] == 25
    assert rows[1]["bank_id"] == 36
    assert rows[1]["bs"] == 25


def test_build_expense_income_payload_cost():
    """نمونه سند cost: bd روی calc، bs روی بانک."""
    id_map = LegacyIdMap()
    id_map.bank_accounts[36] = 1001
    archive_rows = [
        {"ref_id": 98, "bd": 25, "des": "خرید"},
        {"ref_id": 5, "bank_id": 36, "bs": 25},
        {"person_id": 10, "bd": 0, "bs": 0},
    ]
    items, counterparties = build_expense_income_payload(
        "cost",
        archive_rows,
        chart=_StubChart(),
        id_map=id_map,
        doc_amount=25,
    )
    assert len(items) == 1
    assert items[0]["account_id"] == 501
    assert items[0]["amount"] == 25.0
    assert len(counterparties) == 1
    assert counterparties[0]["transaction_type"] == "bank"
    assert counterparties[0]["bank_id"] == 1001
    assert counterparties[0]["amount"] == 25.0


def test_build_expense_income_payload_income():
    id_map = LegacyIdMap()
    id_map.bank_accounts[12] = 2002
    rows = [
        {"ref_id": 40, "bs": 100},
        {"bank_id": 12, "bd": 100},
    ]
    items, counterparties = build_expense_income_payload(
        "income",
        rows,
        chart=_StubChart(),
        id_map=id_map,
    )
    assert items[0]["amount"] == 100.0
    assert counterparties[0]["bank_id"] == 2002


def test_build_invoice_lines_extra_info_pricing():
    """قیمت واحد و جمع سطر باید در extra_info باشند (قرارداد create_invoice)."""
    from app.services.legacy_import.document_importer import LegacyDocumentImporter
    from app.services.legacy_import.id_map import LegacyIdMap, LegacyImportStats

    id_map = LegacyIdMap()
    id_map.products[769] = 5001
    stats = LegacyImportStats()
    importer = LegacyDocumentImporter(None, 1, 1, 1, id_map, stats)

    rows = [
        {
            "commodity_id": 769,
            "commdityCount": 20,
            "bs": "69400000",
            "bd": "0",
            "discount": "0",
            "tax": "0",
        }
    ]
    lines = importer._build_invoice_lines(rows)
    assert len(lines) == 1
    info = lines[0]["extra_info"]
    assert info["unit_price"] == 3470000.0
    assert info["line_total"] == 69400000.0
    assert "unit_price" not in lines[0] or lines[0].get("unit_price") is None


def test_extract_invoice_header_discount():
    from app.services.legacy_import.document_importer import LegacyDocumentImporter
    from app.services.legacy_import.id_map import LegacyIdMap, LegacyImportStats

    importer = LegacyDocumentImporter(None, 1, 1, 1, LegacyIdMap(), LegacyImportStats())
    rows = [
        {"bd": "5000", "bs": "0", "des": "تخفیف فاکتور"},
        {"commodity_id": 1, "bs": "1000", "bd": "0", "commdityCount": 1},
    ]
    assert float(importer._extract_invoice_header_discount(rows)) == 5000.0


def test_invoice_payload_requires_person_in_extra_info():
    """create_invoice reads person_id from extra_info, not root payload."""
    from app.services.legacy_import.document_importer import LegacyDocumentImporter
    from app.services.legacy_import.id_map import LegacyIdMap, LegacyImportStats
    from app.services.legacy_import.mappers import parse_legacy_date

    id_map = LegacyIdMap()
    id_map.persons[33] = 9001
    id_map.products[769] = 5001
    stats = LegacyImportStats()

    doc = {"id": 132, "code": "1129", "type": "sell", "date": "1404/05/22"}
    rows = [
        {
            "commodity_id": 769,
            "commdityCount": 2,
            "bs": "100000",
            "person_id": 33,
        }
    ]

    importer = LegacyDocumentImporter(None, 1, 1, 1, id_map, stats)
    person_id = importer._resolve_person_for_doc(doc, rows)
    lines = importer._build_invoice_lines(rows)
    payload = {
        "invoice_type": "invoice_sales",
        "document_date": parse_legacy_date(doc["date"]).isoformat(),
        "currency_id": 1,
        "lines": lines,
        "extra_info": {
            "person_id": int(person_id),
            "legacy_import": True,
        },
    }
    assert payload["extra_info"]["person_id"] == 9001
    assert payload["lines"][0]["extra_info"]["unit_price"] == 50000.0


def test_parse_legacy_invoice_code_patterns():
    from app.services.legacy_import.invoice_settlement import parse_legacy_invoice_code

    assert parse_legacy_invoice_code("بابت تسویه فاکتور 1192") == "1192"
    assert parse_legacy_invoice_code("بابت تسویه فاکتور فروش 1182") == "1182"
    assert parse_legacy_invoice_code("پرداخت وجه فاکتور شماره 1000") == "1000"
    assert parse_legacy_invoice_code("دریافت وجه فاکتور شماره ۱٬۱۲۹") == "1129"
    assert parse_legacy_invoice_code("بابت فاکتور فروش بارمان شیمی") is None


def test_extract_linked_invoice_legacy_code_from_rows():
    from app.services.legacy_import.invoice_settlement import extract_linked_invoice_legacy_code

    doc = {"des": ""}
    rows = [{"des": "بابت تسویه فاکتور فروش 1188"}]
    assert extract_linked_invoice_legacy_code(doc, rows) == "1188"


def test_apply_related_docs_to_link_map():
    from app.services.legacy_import.invoice_settlement import apply_related_docs_to_link_map

    link_map: dict[str, str] = {}
    apply_related_docs_to_link_map(
        link_map,
        "2034",
        [
            {"type": "sell_receive", "code": "2035", "des": "بابت دریافت فاکتور فروش"},
            {"type": "cost", "code": "9999", "des": "ignored"},
        ],
    )
    assert link_map == {"2035": "2034"}


def test_resolve_linked_invoice_legacy_code_prefers_related_docs():
    from app.services.legacy_import.invoice_settlement import resolve_linked_invoice_legacy_code

    doc = {"des": "توضیح قدیمی بدون کد فاکتور"}
    rows = [{"des": "توضیح تغییر یافته"}]
    code = resolve_linked_invoice_legacy_code(
        receipt_payment_code="2035",
        related_docs_link_map={"2035": "2034"},
        doc=doc,
        rows=rows,
    )
    assert code == "2034"


def test_resolve_linked_invoice_legacy_code_falls_back_to_description():
    from app.services.legacy_import.invoice_settlement import resolve_linked_invoice_legacy_code

    code = resolve_linked_invoice_legacy_code(
        receipt_payment_code="1194",
        related_docs_link_map={},
        doc={"des": "بابت تسویه فاکتور 1192"},
        rows=[],
    )
    assert code == "1192"


def test_receipt_payment_person_lines_get_invoice_id():
    """sell_receive/buy_send must attach invoice_id to person_lines for settlement."""
    from app.services.legacy_import.document_importer import LegacyDocumentImporter
    from app.services.legacy_import.id_map import LegacyIdMap, LegacyImportStats

    id_map = LegacyIdMap()
    id_map.invoice_codes["1192"] = 7001
    id_map.persons[33] = 9001
    id_map.bank_accounts[36] = 1001
    stats = LegacyImportStats()
    importer = LegacyDocumentImporter(None, 1, 1, 1, id_map, stats)

    doc = {
        "id": 197,
        "code": "1194",
        "type": "sell_receive",
        "date": "1404/06/15",
        "des": "بابت تسویه فاکتور 1192",
    }
    rows = [
        {"person_id": 33, "bs": "5000000", "des": "بابت تسویه فاکتور 1192"},
        {"bank_id": 36, "bd": "5000000", "des": "بابت تسویه فاکتور 1192"},
    ]
    from app.services.legacy_import.document_rows import build_receipt_payment_lines
    from app.services.legacy_import.invoice_settlement import (
        INVOICE_LINKED_RECEIPT_PAYMENT_TYPES,
        resolve_linked_invoice_legacy_code,
    )

    person_lines, account_lines = build_receipt_payment_lines(rows, id_map=id_map)
    legacy_type = str(doc.get("type") or "").strip()
    assert legacy_type in INVOICE_LINKED_RECEIPT_PAYMENT_TYPES
    linked_code = resolve_linked_invoice_legacy_code(
        receipt_payment_code=doc.get("code"),
        related_docs_link_map={"1194": "1192"},
        doc=doc,
        rows=rows,
    )
    assert linked_code == "1192"
    linked_id = id_map.invoice_codes.get(linked_code)
    assert linked_id == 7001
    for pl in person_lines:
        pl.setdefault("extra_info", {})
        pl["extra_info"]["invoice_id"] = int(linked_id)
    assert person_lines[0]["extra_info"]["invoice_id"] == 7001
