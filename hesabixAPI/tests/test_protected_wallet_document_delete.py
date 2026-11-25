"""پرداخت آنلاین موفق نباید با حذف سند دریافت، بدون سند باقی بماند."""
from types import SimpleNamespace
from unittest.mock import MagicMock

import pytest

from app.core.responses import ApiError
from app.services.receipt_payment_service import delete_receipt_payment
from app.services.wallet_service import raise_if_protected_wallet_document


def _db_with_transactions(transactions):
    db = MagicMock()
    db.query.return_value.filter.return_value.all.return_value = transactions
    return db


def test_online_invoice_payment_blocks_document_delete():
    db = _db_with_transactions([SimpleNamespace(id=321, type="public_invoice_share_pay")])
    with pytest.raises(ApiError) as exc:
        raise_if_protected_wallet_document(db, 98248)
    assert exc.value.code == "DOCUMENT_HAS_WALLET_TRANSACTIONS"
    assert exc.value.status_code == 409


def test_public_pay_link_blocks_document_delete():
    db = _db_with_transactions([SimpleNamespace(id=12, type="public_pay_link")])
    with pytest.raises(ApiError) as exc:
        raise_if_protected_wallet_document(db, 50)
    assert exc.value.code == "DOCUMENT_HAS_WALLET_TRANSACTIONS"


def test_unprotected_wallet_link_does_not_block_delete():
    db = _db_with_transactions([SimpleNamespace(id=4, type="manual_note")])
    raise_if_protected_wallet_document(db, 9)


def test_receipt_without_wallet_link_can_be_deleted():
    raise_if_protected_wallet_document(_db_with_transactions([]), 9)


def test_delete_receipt_payment_keeps_online_invoice_receipt():
    document = SimpleNamespace(
        id=98248,
        document_type="receipt",
        fiscal_year_id=1,
        code="RC-20250820-0001",
        extra_info={},
        developer_settings={},
    )
    fiscal_year = SimpleNamespace(is_last=True)
    db = MagicMock()
    db.query.return_value.filter.return_value.first.side_effect = [
        document,
        fiscal_year,
        None,
    ]
    db.query.return_value.filter.return_value.all.return_value = [
        SimpleNamespace(id=321, type="public_invoice_share_pay"),
    ]

    with pytest.raises(ApiError) as exc:
        delete_receipt_payment(db, 98248, commit=False)

    assert exc.value.code == "DOCUMENT_HAS_WALLET_TRANSACTIONS"
    db.delete.assert_not_called()
    db.commit.assert_not_called()
