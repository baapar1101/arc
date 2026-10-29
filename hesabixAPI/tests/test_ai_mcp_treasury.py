"""Tenant-bound MCP tools for daily treasury ops: bank, cash, petty, opening balance."""
from __future__ import annotations

from types import SimpleNamespace
from unittest.mock import MagicMock, patch

import pytest

from app.core.responses import ApiError
from app.services.ai.ai_function_extensions_mcp_treasury import (
    BULK_DELETE_BANK_ACCOUNTS_SCHEMA,
    BULK_DELETE_CASH_REGISTERS_SCHEMA,
    BULK_DELETE_PETTY_CASH_SCHEMA,
    CREATE_BANK_ACCOUNT_SCHEMA,
    CREATE_CASH_REGISTER_SCHEMA,
    CREATE_PETTY_CASH_SCHEMA,
    OPENING_BALANCE_WRITE_SCHEMA,
    _opening_payload,
    bulk_delete_bank_accounts_handler,
    bulk_delete_cash_registers_handler,
    bulk_delete_petty_cash_handler,
    create_bank_account_handler,
    create_cash_register_handler,
    delete_bank_account_handler,
    delete_cash_register_handler,
    delete_petty_cash_handler,
    get_bank_account_handler,
    post_opening_balance_handler,
    preview_opening_balance_handler,
    unpost_opening_balance_handler,
    update_bank_account_handler,
    upsert_opening_balance_handler,
)
from app.services.ai.ai_tool_catalog_quality import parse_registered_tool_fields
from app.services.ai.ai_tool_manifest import get_manifest_entry
from app.services.ai.ai_write_guard import is_write_function

TREASURY_TOOLS = (
    "get_bank_account",
    "create_bank_account",
    "update_bank_account",
    "delete_bank_account",
    "bulk_delete_bank_accounts",
    "get_cash_register",
    "create_cash_register",
    "update_cash_register",
    "delete_cash_register",
    "bulk_delete_cash_registers",
    "get_petty_cash",
    "create_petty_cash",
    "update_petty_cash",
    "delete_petty_cash",
    "bulk_delete_petty_cash",
    "upsert_opening_balance",
    "preview_opening_balance",
    "post_opening_balance",
    "unpost_opening_balance",
)


def _ctx(*, business_id: int = 7, user_id: int = 9, db=None):
    user = MagicMock()
    user.get_user_id.return_value = user_id
    return {
        "db": db if db is not None else MagicMock(),
        "business_id": business_id,
        "user_context": user,
    }


def _query_db(*, row=None, rows=None):
    from adapters.db.models.bank_account import BankAccount
    from adapters.db.models.cash_register import CashRegister
    from adapters.db.models.petty_cash import PettyCash

    db = MagicMock()
    found = list(rows) if rows is not None else ([] if row is None else [row])

    def query(model):
        q = MagicMock()
        q.filter.return_value = q
        if model in (BankAccount, CashRegister, PettyCash):
            q.first.return_value = row
            q.all.return_value = found
        else:
            q.first.return_value = None
            q.all.return_value = []
        return q

    db.query.side_effect = query
    return db


def test_treasury_tools_are_registered_with_strict_schemas():
    parsed = parse_registered_tool_fields()
    for name in TREASURY_TOOLS:
        assert name in parsed, name

    create = parsed["create_bank_account"]
    assert create["requires_approval"] is True
    assert create["is_readonly"] is False
    assert create["risk_level"] == "medium"
    assert create["required_permissions"] == ["bank_accounts.write"]
    assert CREATE_BANK_ACCOUNT_SCHEMA["additionalProperties"] is False
    assert "extra_info" not in CREATE_BANK_ACCOUNT_SCHEMA["properties"]
    assert CREATE_CASH_REGISTER_SCHEMA["additionalProperties"] is False
    assert CREATE_PETTY_CASH_SCHEMA["additionalProperties"] is False
    assert CREATE_BANK_ACCOUNT_SCHEMA["required"] == ["name", "currency_id"]

    delete = parsed["delete_bank_account"]
    assert delete["required_permissions"] == ["bank_accounts.delete"]
    assert delete["risk_level"] == "high"
    assert delete["requires_approval"] is True
    assert parsed["delete_cash_register"]["required_permissions"] == ["cash_registers.delete"]
    assert parsed["delete_petty_cash"]["required_permissions"] == ["petty_cash.delete"]
    assert BULK_DELETE_BANK_ACCOUNTS_SCHEMA["properties"]["bank_account_ids"]["maxItems"] == 100
    assert BULK_DELETE_CASH_REGISTERS_SCHEMA["properties"]["cash_register_ids"]["maxItems"] == 100
    assert BULK_DELETE_PETTY_CASH_SCHEMA["properties"]["petty_cash_ids"]["maxItems"] == 100

    preview = parsed["preview_opening_balance"]
    assert preview["is_readonly"] is True
    assert preview["required_permissions"] == ["opening_balance.edit"]
    upsert = parsed["upsert_opening_balance"]
    assert upsert["is_readonly"] is False
    assert upsert["risk_level"] == "high"
    assert upsert["requires_approval"] is True
    assert parsed["post_opening_balance"]["requires_approval"] is True
    assert parsed["unpost_opening_balance"]["risk_level"] == "high"
    assert OPENING_BALANCE_WRITE_SCHEMA["additionalProperties"] is False
    assert "extra_info" not in OPENING_BALANCE_WRITE_SCHEMA["properties"]
    inventory = OPENING_BALANCE_WRITE_SCHEMA["properties"]["inventory_lines"]["items"]
    assert inventory["additionalProperties"] is False
    assert "extra_info" not in inventory["properties"]
    assert inventory["properties"]["quantity"]["exclusiveMinimum"] == 0
    account_line = OPENING_BALANCE_WRITE_SCHEMA["properties"]["account_lines"]["items"]
    assert "extra_info" not in account_line["properties"]


def test_manifest_marks_treasury_writes_and_delete_confirm():
    create = get_manifest_entry("create_bank_account")
    delete = get_manifest_entry("delete_bank_account")
    bulk = get_manifest_entry("bulk_delete_bank_accounts")
    preview = get_manifest_entry("preview_opening_balance")
    upsert = get_manifest_entry("upsert_opening_balance")
    post = get_manifest_entry("post_opening_balance")
    unpost = get_manifest_entry("unpost_opening_balance")
    list_bank = get_manifest_entry("list_bank_accounts")
    list_petty = get_manifest_entry("list_petty_cash")
    assert create is not None and create.intent_write is True and create.always_confirm is False
    assert delete is not None and delete.always_confirm is True and delete.side_effect == "delete"
    assert bulk is not None and bulk.always_confirm is True and bulk.intent_write is True
    assert preview is not None and preview.intent_write is False
    assert upsert is not None and upsert.intent_write is True and upsert.always_confirm is False
    assert post is not None and post.always_confirm is True and post.intent_write is True
    assert unpost is not None and unpost.always_confirm is True
    assert "create_bank_account" in (list_bank.companion_tools if list_bank else ())
    assert list_petty is not None and list_petty.domains == ("financial",)
    assert is_write_function("create_bank_account") is True
    assert is_write_function("delete_cash_register") is True
    assert is_write_function("upsert_opening_balance") is True
    assert is_write_function("post_opening_balance") is True
    assert is_write_function("preview_opening_balance") is False
    assert is_write_function("get_bank_account") is False


def test_create_bank_account_pins_tenant_and_converts_api_error():
    db = MagicMock()
    with patch(
        "app.services.bank_account_service.create_bank_account",
        return_value={"id": 12, "name": "ملت"},
    ) as create:
        result = create_bank_account_handler(
            {"name": "ملت", "currency_id": 1, "business_id": 99},
            _ctx(db=db),
        )
    assert result["id"] == 12
    create.assert_called_once()
    args = create.call_args.args
    assert args[1] == 7
    assert args[2]["name"] == "ملت"

    with patch(
        "app.services.bank_account_service.create_bank_account",
        side_effect=ApiError("DUPLICATE_BANK_ACCOUNT_CODE", "کد تکراری", http_status=400),
    ):
        with pytest.raises(ValueError, match="کد تکراری"):
            create_bank_account_handler({"name": "ملت", "currency_id": 1}, _ctx(db=db))


def test_create_cash_register_uses_session_business_id():
    db = MagicMock()
    with patch(
        "app.services.cash_register_service.create_cash_register",
        return_value={"id": 3},
    ) as create:
        create_cash_register_handler({"name": "صندوق ۱", "currency_id": 1}, _ctx(db=db))
    assert create.call_args.args[1] == 7


def test_get_and_update_reject_foreign_bank_account():
    db = _query_db(row=None)
    with pytest.raises(ValueError, match="کسب‌وکار متصل"):
        get_bank_account_handler({"bank_account_id": 5}, _ctx(db=db))
    with pytest.raises(ValueError, match="کسب‌وکار متصل"):
        update_bank_account_handler({"bank_account_id": 5, "name": "x"}, _ctx(db=db))


def test_update_bank_account_calls_service_for_tenant_row():
    row = SimpleNamespace(id=5, business_id=7)
    db = _query_db(row=row)
    with patch(
        "app.services.bank_account_service.update_bank_account",
        return_value={"id": 5, "name": "ملت"},
    ) as update:
        result = update_bank_account_handler(
            {"bank_account_id": 5, "name": "ملت"},
            _ctx(db=db),
        )
    assert result["id"] == 5
    update.assert_called_once()
    assert update.call_args.args[1] == 5
    assert update.call_args.args[2] == {"name": "ملت"}


def test_delete_rejects_missing_permission_and_foreign_id():
    db = _query_db(row=None)
    with patch(
        "app.core.permissions.has_business_permission_for_business",
        return_value=True,
    ):
        with pytest.raises(ValueError, match="کسب‌وکار متصل"):
            delete_bank_account_handler({"bank_account_id": 8}, _ctx(db=db))

    row = SimpleNamespace(id=8, business_id=7)
    db = _query_db(row=row)
    with patch(
        "app.core.permissions.has_business_permission_for_business",
        return_value=False,
    ):
        with pytest.raises(ValueError, match="bank_accounts.delete"):
            delete_bank_account_handler({"bank_account_id": 8}, _ctx(db=db))


def test_delete_bank_account_success_and_service_error():
    row = SimpleNamespace(id=8, business_id=7)
    db = _query_db(row=row)
    with patch(
        "app.core.permissions.has_business_permission_for_business",
        return_value=True,
    ), patch(
        "app.services.bank_account_service.delete_bank_account",
        return_value=(True, None),
    ) as delete:
        result = delete_bank_account_handler({"bank_account_id": 8}, _ctx(db=db))
    assert result == {"deleted": True, "bank_account_id": 8}
    delete.assert_called_once()

    with patch(
        "app.core.permissions.has_business_permission_for_business",
        return_value=True,
    ), patch(
        "app.services.bank_account_service.delete_bank_account",
        return_value=(False, "دارای اسناد حسابداری مرتبط است"),
    ):
        with pytest.raises(ValueError, match="اسناد حسابداری"):
            delete_bank_account_handler({"bank_account_id": 8}, _ctx(db=db))


def test_delete_cash_and_petty_use_mapped_permission_sections():
    row = SimpleNamespace(id=4, business_id=7)
    db = _query_db(row=row)
    with patch(
        "app.core.permissions.has_business_permission_for_business",
        return_value=True,
    ) as perm, patch(
        "app.services.cash_register_service.delete_cash_register",
        return_value=(True, None),
    ):
        delete_cash_register_handler({"cash_register_id": 4}, _ctx(db=db))
    assert perm.call_args.args[3:5] == ("cash", "delete")

    with patch(
        "app.core.permissions.has_business_permission_for_business",
        return_value=True,
    ) as perm, patch(
        "app.services.petty_cash_service.delete_petty_cash",
        return_value=(True, None),
    ):
        delete_petty_cash_handler({"petty_cash_id": 4}, _ctx(db=db))
    assert perm.call_args.args[3:5] == ("petty_cash", "delete")


def test_bulk_delete_rejects_duplicate_and_foreign_ids():
    with pytest.raises(ValueError, match="تکراری"):
        bulk_delete_bank_accounts_handler({"bank_account_ids": [1, 1]}, _ctx())

    local = SimpleNamespace(id=1, business_id=7)
    db = _query_db(row=local, rows=[local])
    with patch(
        "app.core.permissions.has_business_permission_for_business",
        return_value=True,
    ):
        with pytest.raises(ValueError, match="متعلق به کسب‌وکار"):
            bulk_delete_bank_accounts_handler({"bank_account_ids": [1, 99]}, _ctx(db=db))
        with pytest.raises(ValueError, match="متعلق به کسب‌وکار"):
            bulk_delete_cash_registers_handler({"cash_register_ids": [1, 99]}, _ctx(db=db))
        with pytest.raises(ValueError, match="متعلق به کسب‌وکار"):
            bulk_delete_petty_cash_handler({"petty_cash_ids": [1, 99]}, _ctx(db=db))


def test_bulk_delete_bank_accounts_calls_service_when_all_ids_are_tenant():
    rows = [SimpleNamespace(id=1, business_id=7), SimpleNamespace(id=2, business_id=7)]
    db = _query_db(rows=rows)
    with patch(
        "app.core.permissions.has_business_permission_for_business",
        return_value=True,
    ), patch(
        "app.services.bank_account_service.bulk_delete_bank_accounts",
        return_value={"deleted": 2, "skipped": 0, "errors": []},
    ) as bulk:
        result = bulk_delete_bank_accounts_handler({"bank_account_ids": [1, 2]}, _ctx(db=db))
    bulk.assert_called_once()
    assert bulk.call_args.args[1] == 7
    assert bulk.call_args.args[2] == [1, 2]
    assert result["deleted"] == 2


def test_opening_payload_builds_inventory_extra_info_internally():
    payload = _opening_payload(
        {
            "currency_id": 1,
            "account_lines": [{"account_id": 10, "debit": 100, "credit": 0}],
            "inventory_lines": [
                {
                    "product_id": 4,
                    "warehouse_id": 8,
                    "quantity": 2,
                    "cost_price": 50,
                    "description": "افتتاحیه",
                }
            ],
        }
    )
    assert "extra_info" not in payload
    line = payload["inventory_lines"][0]
    assert line["product_id"] == 4
    assert line["extra_info"] == {"movement": "in", "warehouse_id": 8, "cost_price": 50}
    assert "warehouse_id" not in line


def test_upsert_and_preview_use_session_tenant_and_built_payload():
    db = MagicMock()
    args = {
        "currency_id": 1,
        "inventory_lines": [{"product_id": 4, "warehouse_id": 8, "quantity": 1}],
    }
    with patch(
        "app.services.opening_balance_service.upsert_opening_balance",
        return_value={"id": 21},
    ) as upsert:
        result = upsert_opening_balance_handler(args, _ctx(db=db))
    assert result["id"] == 21
    _, bid, uid, data = upsert.call_args.args
    assert bid == 7
    assert uid == 9
    assert data["inventory_lines"][0]["extra_info"]["warehouse_id"] == 8

    with patch(
        "app.services.opening_balance_service.preview_opening_balance",
        return_value={"balanced": True},
    ) as preview:
        preview_opening_balance_handler({"currency_id": 1}, _ctx(db=db))
    assert preview.call_args.args[1] == 7


def test_post_and_unpost_opening_balance_pin_tenant():
    db = MagicMock()
    with patch(
        "app.services.opening_balance_service.post_opening_balance",
        return_value={"posted": True},
    ) as post:
        post_opening_balance_handler({"fiscal_year_id": 3}, _ctx(db=db))
    assert post.call_args.args[1:4] == (7, 9, 3)

    with patch(
        "app.services.opening_balance_service.unpost_opening_balance",
        side_effect=ApiError(
            "OPENING_BALANCE_UNPOST_BLOCKED",
            "به‌دلیل ثبت اسناد دیگر",
            http_status=409,
        ),
    ):
        with pytest.raises(ValueError, match="اسناد دیگر"):
            unpost_opening_balance_handler({}, _ctx(db=db))
