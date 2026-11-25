"""تست ایجاد اسناد دریافت/پرداخت جداگانه برای پرداخت‌های فاکتور."""

from datetime import date
from unittest.mock import MagicMock, patch

from adapters.db.models.document import Document
from app.services.invoice_service import (
    INVOICE_SALES,
    _build_invoice_payment_account_line,
    _create_receipt_payment_documents_for_invoice_payments,
)


def test_build_invoice_payment_account_line_skips_non_positive_amounts():
    assert _build_invoice_payment_account_line({"amount": 0}) is None
    assert _build_invoice_payment_account_line({"amount": -10}) is None


def test_build_invoice_payment_account_line_preserves_transaction_date():
    line = _build_invoice_payment_account_line({
        "type": "cash_register",
        "amount": 150000,
        "transaction_date": "2024-03-10",
        "cash_register_id": 7,
        "description": "پرداخت نقدی",
    })
    assert line is not None
    assert line["transaction_type"] == "cash_register"
    assert line["amount"] == 150000.0
    assert line["transaction_date"] == "2024-03-10"
    assert line["cash_register_id"] == 7


@patch("app.services.invoice_service._validate_invoice_payment_item_currency", return_value=None)
@patch("app.services.receipt_payment_service.create_receipt_payment")
def test_create_receipt_payment_documents_for_invoice_payments_creates_one_per_item(
    mock_create,
    _mock_validate,
):
    mock_create.side_effect = [
        {"id": 101},
        {"id": 102},
    ]
    document = Document(
        id=55,
        code="1001",
        business_id=1,
        currency_id=1,
        document_date=date(2024, 3, 1),
    )
    payments = [
        {
            "type": "cash_register",
            "amount": 100000,
            "transaction_date": "2024-03-05",
            "cash_register_id": 3,
        },
        {
            "type": "bank",
            "amount": 250000,
            "transaction_date": "2024-03-12",
            "bank_id": 9,
        },
    ]

    created_ids = _create_receipt_payment_documents_for_invoice_payments(
        MagicMock(),
        business_id=1,
        user_id=2,
        document=document,
        person_id=10,
        payments=payments,
        invoice_type=INVOICE_SALES,
    )

    assert created_ids == [101, 102]
    assert mock_create.call_count == 2

    first_call = mock_create.call_args_list[0].kwargs["data"]
    second_call = mock_create.call_args_list[1].kwargs["data"]

    assert first_call["document_type"] == "receipt"
    assert first_call["person_lines"][0]["amount"] == 100000.0
    assert len(first_call["account_lines"]) == 1
    assert first_call["account_lines"][0]["amount"] == 100000.0
    assert first_call["account_lines"][0]["transaction_date"] == "2024-03-05"
    assert first_call["document_date"] == "2024-03-05"

    assert second_call["person_lines"][0]["amount"] == 250000.0
    assert len(second_call["account_lines"]) == 1
    assert second_call["account_lines"][0]["transaction_date"] == "2024-03-12"
    assert second_call["document_date"] == "2024-03-12"


@patch("app.services.invoice_service._validate_invoice_payment_item_currency", return_value=None)
@patch("app.services.receipt_payment_service.create_receipt_payment")
def test_create_receipt_payment_documents_allows_two_same_type_bank_items(
    mock_create,
    _mock_validate,
):
    """دو دریافت بانکی جدا — حتی به یک حساب — دو سند دریافت متوازن می‌سازند."""
    mock_create.side_effect = [{"id": 301}, {"id": 302}]
    document = Document(
        id=77,
        code="1003",
        business_id=1,
        currency_id=1,
        document_date=date(2024, 3, 1),
    )
    payments = [
        {
            "type": "bank",
            "amount": 500000,
            "transaction_date": "2024-03-12",
            "bank_id": 9,
        },
        {
            "type": "bank",
            "amount": 300000,
            "transaction_date": "2024-03-12",
            "bank_id": 9,
        },
    ]

    created_ids = _create_receipt_payment_documents_for_invoice_payments(
        MagicMock(),
        business_id=1,
        user_id=2,
        document=document,
        person_id=10,
        payments=payments,
        invoice_type=INVOICE_SALES,
    )

    assert created_ids == [301, 302]
    assert mock_create.call_count == 2

    first = mock_create.call_args_list[0].kwargs["data"]
    second = mock_create.call_args_list[1].kwargs["data"]
    assert first["document_type"] == "receipt"
    assert second["document_type"] == "receipt"
    assert first["account_lines"][0]["transaction_type"] == "bank"
    assert second["account_lines"][0]["transaction_type"] == "bank"
    assert first["account_lines"][0]["bank_id"] == 9
    assert second["account_lines"][0]["bank_id"] == 9
    assert first["person_lines"][0]["amount"] == 500000.0
    assert second["person_lines"][0]["amount"] == 300000.0
    assert first["account_lines"][0]["amount"] == 500000.0
    assert second["account_lines"][0]["amount"] == 300000.0


@patch("app.services.invoice_service._validate_invoice_payment_item_currency", return_value=None)
@patch("app.services.receipt_payment_service.create_receipt_payment")
def test_create_receipt_payment_documents_skips_zero_amount_items(
    mock_create,
    _mock_validate,
):
    document = Document(
        id=56,
        code="1002",
        business_id=1,
        currency_id=1,
        document_date=date(2024, 3, 1),
    )
    payments = [
        {"type": "cash_register", "amount": 0, "cash_register_id": 3},
        {
            "type": "bank",
            "amount": 50000,
            "transaction_date": "2024-03-08",
            "bank_id": 9,
        },
    ]
    mock_create.return_value = {"id": 201}

    created_ids = _create_receipt_payment_documents_for_invoice_payments(
        MagicMock(),
        business_id=1,
        user_id=2,
        document=document,
        person_id=10,
        payments=payments,
        invoice_type=INVOICE_SALES,
    )

    assert created_ids == [201]
    assert mock_create.call_count == 1
    assert mock_create.call_args.kwargs["data"]["person_lines"][0]["amount"] == 50000.0
    assert mock_create.call_args.kwargs["data"]["document_date"] == "2024-03-08"


def test_validate_invoice_payment_rejects_bank_from_other_business():
    from types import SimpleNamespace

    from app.core.responses import ApiError
    from app.services.invoice_service import _validate_invoice_payment_item_currency

    db = MagicMock()
    db.query.return_value.filter.return_value.first.return_value = SimpleNamespace(
        id=3395,
        business_id=5433,
        currency_id=1,
    )
    try:
        _validate_invoice_payment_item_currency(
            db,
            1,
            {"type": "bank", "bank_id": 3395, "amount": 100},
            INVOICE_SALES,
            business_id=6342,
        )
        assert False, "expected ApiError"
    except ApiError as exc:
        assert exc.status_code == 400
        assert exc.detail["error"]["code"] == "PAYMENT_ACCOUNT_BUSINESS_MISMATCH"


def test_validate_invoice_payment_accepts_bank_of_same_business():
    from types import SimpleNamespace

    from app.services.invoice_service import _validate_invoice_payment_item_currency

    db = MagicMock()
    db.query.return_value.filter.return_value.first.return_value = SimpleNamespace(
        id=4387,
        business_id=6342,
        currency_id=1,
    )
    result = _validate_invoice_payment_item_currency(
        db,
        1,
        {"type": "bank", "bank_id": 4387, "amount": 100},
        INVOICE_SALES,
        business_id=6342,
    )
    assert result is None


@patch("app.services.invoice_service._validate_invoice_payment_item_currency", return_value=None)
@patch("app.services.receipt_payment_service.create_receipt_payment")
def test_invoice_prepayment_receipt_uses_bank_date_not_later_invoice_date(
    mock_create,
    _mock_validate,
):
    """پیش‌دریافت: واریز بانکی قبل از فاکتور باید سند دریافت را با تاریخ واریز بسازد."""
    mock_create.return_value = {"id": 421}
    document = Document(
        id=88,
        code="INV-20260620-00021",
        business_id=1,
        currency_id=1,
        document_date=date(2026, 6, 20),  # ۱۴۰۵/۰۳/۳۰
    )
    created_ids = _create_receipt_payment_documents_for_invoice_payments(
        MagicMock(),
        business_id=1,
        user_id=2,
        document=document,
        person_id=10,
        payments=[{
            "type": "bank",
            "amount": 1500000,
            "transaction_date": "2026-04-01",  # ۱۴۰۵/۰۱/۱۲
            "bank_id": 9,
        }],
        invoice_type=INVOICE_SALES,
    )

    assert created_ids == [421]
    payload = mock_create.call_args.kwargs["data"]
    assert payload["document_type"] == "receipt"
    assert payload["document_date"] == "2026-04-01"
    assert payload["account_lines"][0]["transaction_date"] == "2026-04-01"


def test_resolve_receipt_document_date_prefers_cash_event_over_invoice_date():
    from app.services.receipt_payment_service import (
        resolve_receipt_document_date_from_account_lines,
    )

    invoice_date = date(2026, 6, 20)
    assert resolve_receipt_document_date_from_account_lines(
        invoice_date,
        [{"transaction_date": "2026-04-01"}],
    ) == date(2026, 4, 1)
    assert resolve_receipt_document_date_from_account_lines(
        invoice_date,
        [{"transaction_date": "2026-07-10"}],
    ) == date(2026, 7, 10)
    assert resolve_receipt_document_date_from_account_lines(
        invoice_date,
        [{"amount": 10}],
    ) == invoice_date
    assert resolve_receipt_document_date_from_account_lines(
        invoice_date,
        [
            {"transaction_date": "2026-04-12"},
            {"transaction_date": "2026-04-01"},
        ],
    ) == date(2026, 4, 1)
    assert resolve_receipt_document_date_from_account_lines(
        invoice_date,
        [
            {"transaction_date": "2026-07-10", "is_commission_line": True},
            {"transaction_date": "2026-04-01"},
        ],
    ) == date(2026, 4, 1)
