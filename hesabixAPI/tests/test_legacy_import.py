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


def test_invoice_payload_requires_person_in_extra_info():
    """create_invoice reads person_id from extra_info, not root payload."""
    from app.services.legacy_import.document_importer import LegacyDocumentImporter
    from app.services.legacy_import.id_map import LegacyImportStats
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

    class _Db:
        pass

    importer = LegacyDocumentImporter(_Db(), 1, 1, 1, id_map, stats)
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
    assert "person_id" not in payload or payload.get("extra_info", {}).get("person_id")
