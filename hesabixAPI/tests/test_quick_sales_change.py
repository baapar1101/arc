from __future__ import annotations

from types import SimpleNamespace

import pytest

from app.core.responses import ApiError
from app.services import receipt_payment_service
from app.services.invoice_service import (
    _create_quick_sale_change_payment,
    _quick_sale_change_amount,
    _quick_sale_change_document_amount,
)


def _invoice(total: int):
    return SimpleNamespace(extra_info={"totals": {"net": total}})


class _FakeQuery:
    def __init__(self, result):
        self.result = result

    def filter(self, *args, **kwargs):
        return self

    def join(self, *args, **kwargs):
        return self

    def first(self):
        return self.result

    def one(self):
        return self.result


class _FakeDb:
    def __init__(self, query_results):
        self.query_results = list(query_results)

    def query(self, *args, **kwargs):
        assert self.query_results, "unexpected database query"
        return _FakeQuery(self.query_results.pop(0))


def _saved_invoice(total: int = 1_000_000):
    return SimpleNamespace(
        id=55,
        code="QS-55",
        currency_id=1,
        fiscal_year_id=9,
        document_date=SimpleNamespace(isoformat=lambda: "2026-10-14"),
        extra_info={"totals": {"net": total}},
    )


def test_quick_sale_change_is_zero_when_payments_do_not_exceed_total() -> None:
    assert _quick_sale_change_amount(
        _invoice(1_000_000),
        [{"amount": 400_000}, {"amount": 600_000}],
    ) == 0


def test_quick_sale_change_returns_overpayment() -> None:
    assert _quick_sale_change_amount(
        _invoice(1_000_000),
        [{"amount": 700_000}, {"amount": 450_000}],
    ) == 150_000


def test_quick_sale_change_uses_settlement_amount_for_foreign_payment() -> None:
    assert _quick_sale_change_amount(
        _invoice(1_000_000),
        [{"amount": 10, "settles_amount": 1_100_000}],
    ) == 100_000


def test_quick_sale_change_document_uses_returned_amount_not_bank_outflow() -> None:
    document = SimpleNamespace(
        extra_info={
            "source": "quick_sale_change",
            "returned_amount": 500_000,
            "bank_commission": 20_000,
        },
        lines=[],
    )

    assert _quick_sale_change_document_amount(document) == 500_000


def test_quick_sale_change_document_supports_legacy_change_amount() -> None:
    document = SimpleNamespace(
        extra_info={"source": "quick_sale_change", "change_amount": 125_000},
        lines=[],
    )

    assert _quick_sale_change_document_amount(document) == 125_000


def test_quick_sale_change_bank_fee_is_separate_from_customer_refund(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    captured = {}

    def fake_create_receipt_payment(**kwargs):
        captured.update(kwargs)
        return {"id": 91}

    monkeypatch.setattr(
        receipt_payment_service,
        "create_receipt_payment",
        fake_create_receipt_payment,
    )
    bank = SimpleNamespace(id=7, name="بانک سامان", currency_id=1, is_active=True)
    db = _FakeDb([bank])

    result = _create_quick_sale_change_payment(
        db,
        business_id=2,
        user_id=4,
        document=_saved_invoice(),
        person_id=10,
        payments=[{"amount": 1_500_000}],
        change_request={
            "amount": 500_000,
            "confirmed": True,
            "credit_amount": 0,
            "allocations": [
                {
                    "source_type": "bank",
                    "source_id": 7,
                    "amount": 500_000,
                    "commission": 20_000,
                }
            ],
        },
    )

    assert result == 91
    assert captured["commit"] is False
    payload = captured["data"]
    assert payload["person_lines"][0]["amount"] == 500_000
    assert payload["account_lines"][0]["amount"] == 520_000
    assert payload["fx_adjustment_lines"] == [
        {
            "account_code": "70902",
            "side": "debit",
            "amount": 20_000,
            "description": "کارمزد خدمات بانکی برگشت وجه فروش سریع",
        }
    ]
    assert payload["extra_info"]["returned_amount"] == 500_000
    assert payload["extra_info"]["bank_commission"] == 20_000


def test_quick_sale_change_can_leave_full_amount_as_customer_credit(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(
        receipt_payment_service,
        "create_receipt_payment",
        lambda **kwargs: pytest.fail("credit-only resolution must not create payment"),
    )
    settings = SimpleNamespace(default_anonymous_customer_id=99)
    db = _FakeDb([settings])

    result = _create_quick_sale_change_payment(
        db,
        business_id=2,
        user_id=4,
        document=_saved_invoice(),
        person_id=10,
        payments=[{"amount": 1_500_000}],
        change_request={
            "amount": 500_000,
            "confirmed": True,
            "credit_amount": 500_000,
            "allocations": [],
        },
    )

    assert result is None


def test_quick_sale_change_defaults_to_customer_credit_without_resolution(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(
        receipt_payment_service,
        "create_receipt_payment",
        lambda **kwargs: pytest.fail("default credit must not create payment"),
    )
    settings = SimpleNamespace(default_anonymous_customer_id=99)
    db = _FakeDb([settings])

    result = _create_quick_sale_change_payment(
        db,
        business_id=2,
        user_id=4,
        document=_saved_invoice(),
        person_id=10,
        payments=[{"amount": 1_500_000}],
        change_request=None,
    )

    assert result is None


def test_quick_sale_change_without_resolution_still_rejects_anonymous_customer() -> None:
    settings = SimpleNamespace(default_anonymous_customer_id=10)
    db = _FakeDb([settings])

    with pytest.raises(ApiError) as exc_info:
        _create_quick_sale_change_payment(
            db,
            business_id=2,
            user_id=4,
            document=_saved_invoice(),
            person_id=10,
            payments=[{"amount": 1_500_000}],
            change_request=None,
        )

    assert exc_info.value.code == "QUICK_SALE_CHANGE_ANONYMOUS_CREDIT_NOT_ALLOWED"


def test_quick_sale_change_rejects_credit_for_anonymous_customer() -> None:
    settings = SimpleNamespace(default_anonymous_customer_id=10)
    db = _FakeDb([settings])

    with pytest.raises(ApiError) as exc_info:
        _create_quick_sale_change_payment(
            db,
            business_id=2,
            user_id=4,
            document=_saved_invoice(),
            person_id=10,
            payments=[{"amount": 1_500_000}],
            change_request={
                "amount": 500_000,
                "confirmed": True,
                "credit_amount": 500_000,
                "allocations": [],
            },
        )

    assert exc_info.value.code == "QUICK_SALE_CHANGE_ANONYMOUS_CREDIT_NOT_ALLOWED"


def test_quick_sale_change_from_person_credits_their_receivable_account(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    captured = {}

    def fake_create_receipt_payment(**kwargs):
        captured.update(kwargs)
        return {"id": 92}

    monkeypatch.setattr(
        receipt_payment_service,
        "create_receipt_payment",
        fake_create_receipt_payment,
    )
    source_person = SimpleNamespace(
        id=15,
        alias_name="صندوقدار",
        business_id=2,
        is_active=True,
    )
    receivable_account = SimpleNamespace(id=10401, code="10401")
    db = _FakeDb([source_person, receivable_account])

    result = _create_quick_sale_change_payment(
        db,
        business_id=2,
        user_id=4,
        document=_saved_invoice(),
        person_id=10,
        payments=[{"amount": 1_500_000}],
        change_request={
            "amount": 500_000,
            "confirmed": True,
            "credit_amount": 0,
            "allocations": [
                {
                    "source_type": "person",
                    "source_id": 15,
                    "amount": 500_000,
                }
            ],
        },
    )

    assert result == 92
    source_line = captured["data"]["account_lines"][0]
    assert source_line["transaction_type"] == "account"
    assert source_line["account_id"] == 10401
    assert source_line["person_id"] == 15
    assert source_line["amount"] == 500_000
