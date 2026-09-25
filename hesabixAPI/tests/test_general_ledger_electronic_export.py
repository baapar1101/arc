from __future__ import annotations

from datetime import date

import pytest

from app.services.general_ledger_electronic_export_service import (
    ELECTRONIC_GENERAL_LEDGER_HEADERS,
    build_electronic_general_ledger_csv_bytes,
    build_electronic_general_ledger_excel_bytes,
    build_electronic_general_ledger_rows,
    item_to_electronic_general_ledger_row,
)
from app.services.journal_ledger_service import _find_detail_account


def _accounts_map() -> dict:
    return {
        1: {"id": 1, "code": "11", "name": "موجودی نقد", "parent_id": None},
        2: {"id": 2, "code": "1101", "name": "صندوق", "parent_id": 1},
        3: {"id": 3, "code": "110101", "name": "صندوق مرکزی", "parent_id": 2},
        4: {"id": 4, "code": "41", "name": "فروش", "parent_id": None},
    }


def test_find_detail_account_below_subsidiary():
    accounts = _accounts_map()
    subsidiary = accounts[2]
    detail = _find_detail_account(3, accounts, subsidiary)
    assert detail is not None
    assert detail["code"] == "110101"
    assert detail["name"] == "صندوق مرکزی"


def test_find_detail_account_none_at_subsidiary_level():
    accounts = _accounts_map()
    subsidiary = accounts[2]
    assert _find_detail_account(2, accounts, subsidiary) is None


def test_find_detail_account_none_at_general_level():
    accounts = _accounts_map()
    subsidiary = accounts[2]
    assert _find_detail_account(1, accounts, subsidiary) is None


def test_general_ledger_headers_match_tax_template():
    assert len(ELECTRONIC_GENERAL_LEDGER_HEADERS) == 9
    assert ELECTRONIC_GENERAL_LEDGER_HEADERS[-1] == "تاریخ گردش"
    assert ELECTRONIC_GENERAL_LEDGER_HEADERS[6] == "گردش بدهکار (ریال)"


def test_item_to_electronic_general_ledger_row_with_detail():
    row = item_to_electronic_general_ledger_row(
        {
            "document_date": date(2024, 3, 20),
            "general_account_code": "11",
            "general_account_name": "موجودی نقد",
            "subsidiary_account_code": "1101",
            "subsidiary_account_name": "صندوق",
            "detail_account_code": "110101",
            "detail_account_name": "صندوق مرکزی",
            "debit_amount": 500000,
            "credit_amount": 0,
        }
    )
    assert row[0] == "11"
    assert row[4] == "110101"
    assert row[6] == 500000
    assert row[7] is None
    assert row[8] == "1403/01/01"


def test_item_to_electronic_general_ledger_row_credit_only():
    row = item_to_electronic_general_ledger_row(
        {
            "document_date": date(2024, 3, 20),
            "general_account_code": "41",
            "general_account_name": "فروش",
            "subsidiary_account_code": "",
            "subsidiary_account_name": "",
            "detail_account_code": "",
            "detail_account_name": "",
            "debit_amount": 0,
            "credit_amount": 1200000,
        }
    )
    assert row[6] is None
    assert row[7] == 1200000


def test_build_electronic_general_ledger_rows_skips_zero_lines():
    rows = build_electronic_general_ledger_rows(
        [
            {
                "document_date": date(2024, 3, 20),
                "general_account_code": "11",
                "general_account_name": "موجودی نقد",
                "debit_amount": 0,
                "credit_amount": 0,
            }
        ]
    )
    assert rows == []


def test_build_excel_and_csv_outputs():
    items = [
        {
            "document_date": date(2024, 3, 20),
            "general_account_code": "11",
            "general_account_name": "موجودی نقد",
            "subsidiary_account_code": "1101",
            "subsidiary_account_name": "صندوق",
            "detail_account_code": "110101",
            "detail_account_name": "صندوق مرکزی",
            "debit_amount": 1000,
            "credit_amount": 0,
        }
    ]
    rows = build_electronic_general_ledger_rows(items)
    xlsx = build_electronic_general_ledger_excel_bytes(rows)
    csv = build_electronic_general_ledger_csv_bytes(rows)
    assert xlsx[:2] == b"PK"
    assert csv.startswith(b"\xef\xbb\xbf")
    assert "گردش بدهکار (ریال)" in csv.decode("utf-8-sig")
    assert "تاریخ گردش" in csv.decode("utf-8-sig")
