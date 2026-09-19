"""تست‌های مانده افتتاحیه شخص در سند تراز افتتاحیه."""

from app.services.person_opening_balance_service import _document_lines_to_upsert_inputs


def test_document_lines_to_upsert_inputs_skips_auto_balance_line():
    doc = {
        "extra_info": {"auto_balance_to_equity": True, "equity_account_id": 99},
        "lines": [
            {
                "person_id": 1,
                "account_id": 10,
                "debit": 1000,
                "credit": 0,
                "description": "مانده افتتاحیه - علی",
            },
            {
                "account_id": 99,
                "debit": 0,
                "credit": 1000,
                "description": "بستن اختلاف تراز افتتاحیه",
            },
        ],
    }
    account_lines, inventory_lines, settings = _document_lines_to_upsert_inputs(doc)
    assert len(inventory_lines) == 0
    assert len(account_lines) == 1
    assert account_lines[0]["person_id"] == 1
    assert settings["auto_balance_to_equity"] is True
    assert settings["equity_account_id"] == 99


def test_document_lines_to_upsert_inputs_inventory_and_bank():
    doc = {
        "lines": [
            {
                "product_id": 7,
                "quantity": 2,
                "extra_info": {"warehouse_id": 3, "cost_price": 100},
            },
            {
                "bank_account_id": 4,
                "account_id": 20,
                "debit": 500,
                "credit": 0,
            },
        ],
    }
    account_lines, inventory_lines, _settings = _document_lines_to_upsert_inputs(doc)
    assert len(inventory_lines) == 1
    assert inventory_lines[0]["product_id"] == 7
    assert len(account_lines) == 1
    assert account_lines[0]["bank_account_id"] == 4
