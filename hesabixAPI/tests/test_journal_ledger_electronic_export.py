from __future__ import annotations

from datetime import date
from decimal import Decimal

import pytest

from app.services.journal_ledger_electronic_export_service import (
    ELECTRONIC_JOURNAL_HEADERS,
    build_electronic_journal_csv_bytes,
    build_electronic_journal_excel_bytes,
    build_electronic_journal_rows,
    format_jalali_date_for_electronic_books,
    item_to_electronic_row,
    round_rial_amount,
    _resolve_export_format,
)
from app.core.responses import ApiError


def test_headers_match_tax_template_exactly():
    assert ELECTRONIC_JOURNAL_HEADERS[1] == "تاریخ "
    assert len(ELECTRONIC_JOURNAL_HEADERS) == 9


def test_format_jalali_date_from_gregorian_date():
  # 2024-03-20 ~= 1403/01/01
    assert format_jalali_date_for_electronic_books(date(2024, 3, 20)) == "1403/01/01"


def test_round_rial_amount_half_up():
    assert round_rial_amount(Decimal("100.4")) == 100
    assert round_rial_amount(Decimal("100.5")) == 101
    assert round_rial_amount(0) == 0


def test_item_to_electronic_row_debit_only():
    row = item_to_electronic_row(
        {
            "document_date": date(2024, 3, 20),
            "general_account_code": "11",
            "general_account_name": "موجودی نقد",
            "subsidiary_account_code": "1101",
            "subsidiary_account_name": "صندوق",
            "description": "دریافت نقدی",
            "debit_amount": 1500000.0,
            "credit_amount": 0.0,
        },
        1,
    )
    assert row[0] == 1
    assert row[1] == "1403/01/01"
    assert row[7] == 1500000
    assert row[8] is None


def test_item_to_electronic_row_credit_only():
    row = item_to_electronic_row(
        {
            "document_date": date(2024, 3, 20),
            "general_account_code": "41",
            "general_account_name": "فروش",
            "subsidiary_account_code": "",
            "subsidiary_account_name": "",
            "description": "فروش کالا",
            "debit_amount": 0,
            "credit_amount": 2500000,
        },
        2,
    )
    assert row[7] is None
    assert row[8] == 2500000


def test_item_to_electronic_row_skips_zero_amount_lines():
    assert item_to_electronic_row(
        {
            "document_date": date(2024, 3, 20),
            "debit_amount": 0,
            "credit_amount": 0,
        },
        1,
    ) == []


def test_build_electronic_journal_rows_sequential_numbering():
    items = [
        {
            "document_date": date(2024, 3, 20),
            "general_account_code": "11",
            "general_account_name": "موجودی نقد",
            "subsidiary_account_code": "1101",
            "subsidiary_account_name": "صندوق",
            "description": "سطر اول",
            "debit_amount": 100,
            "credit_amount": 0,
        },
        {
            "document_date": date(2024, 3, 21),
            "general_account_code": "41",
            "general_account_name": "فروش",
            "subsidiary_account_code": "",
            "subsidiary_account_name": "",
            "description": "سطر دوم",
            "debit_amount": 0,
            "credit_amount": 200,
        },
    ]
    rows = build_electronic_journal_rows(items)
    assert len(rows) == 2
    assert rows[0][0] == 1
    assert rows[1][0] == 2


def test_resolve_export_format_auto_threshold():
    assert _resolve_export_format("auto", 500) == "xlsx"
    assert _resolve_export_format("auto", 1500) == "csv"
    assert _resolve_export_format("xlsx", 1500) == "csv"


def test_resolve_export_format_invalid_raises():
    with pytest.raises(ApiError):
        _resolve_export_format("pdf", 10)


def test_build_excel_contains_headers_and_data():
    rows = build_electronic_journal_rows(
        [
            {
                "document_date": date(2024, 3, 20),
                "general_account_code": "11",
                "general_account_name": "موجودی نقد",
                "subsidiary_account_code": "1101",
                "subsidiary_account_name": "صندوق",
                "description": "تست",
                "debit_amount": 1000,
                "credit_amount": 0,
            }
        ]
    )
    content = build_electronic_journal_excel_bytes(rows)
    assert len(content) > 100
    assert b"PK" in content[:4]  # xlsx zip signature


def test_build_csv_utf8_bom_and_headers():
    rows = build_electronic_journal_rows(
        [
            {
                "document_date": date(2024, 3, 20),
                "general_account_code": "11",
                "general_account_name": "موجودی نقد",
                "subsidiary_account_code": "",
                "subsidiary_account_name": "",
                "description": "تست",
                "debit_amount": 0,
                "credit_amount": 500,
            }
        ]
    )
    content = build_electronic_journal_csv_bytes(rows)
    assert content.startswith(b"\xef\xbb\xbf")
    text = content.decode("utf-8-sig")
    assert "مبلغ بستانکار (ریال)" in text
    assert "1403/01/01" in text
