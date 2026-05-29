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
