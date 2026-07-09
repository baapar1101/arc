"""تست‌های کمکی برای محاسبه پرداخت فاکتور و خطوط سند دریافت/پرداخت."""

from decimal import Decimal

from adapters.db.models.document import Document
from adapters.db.models.document_line import DocumentLine
from app.services.invoice_service import (
    _is_account_payment_line,
    _sum_receipt_doc_account_payments,
    _sum_receipt_doc_payments_for_invoice,
)


def _line(**kwargs) -> DocumentLine:
    line = DocumentLine()
    for key, value in kwargs.items():
        setattr(line, key, value)
    return line


def test_is_account_payment_line_excludes_check_auxiliary_and_commission():
    bank_line = _line(
        person_id=None,
        bank_account_id=1,
        debit=Decimal("100"),
        credit=Decimal(0),
        extra_info={"transaction_type": "bank"},
    )
    assert _is_account_payment_line(bank_line) is True

    check_target = _line(
        person_id=None,
        bank_account_id=1,
        debit=Decimal("100"),
        credit=Decimal(0),
        extra_info={"transaction_type": "bank", "is_check_target_account": True},
    )
    assert _is_account_payment_line(check_target) is False

    commission = _line(
        person_id=None,
        bank_account_id=1,
        debit=Decimal("5"),
        credit=Decimal(0),
        extra_info={"transaction_type": "bank", "is_commission_line": True},
    )
    assert _is_account_payment_line(commission) is False


def test_sum_receipt_doc_account_payments_counts_check_once():
    doc = Document()
    doc.lines = [
        _line(
            person_id=None,
            check_id=10,
            debit=Decimal(0),
            credit=Decimal("100"),
            extra_info={"transaction_type": "check"},
        ),
        _line(
            person_id=None,
            bank_account_id=1,
            debit=Decimal("100"),
            credit=Decimal(0),
            extra_info={"transaction_type": "bank", "is_check_target_account": True},
        ),
    ]
    assert _sum_receipt_doc_account_payments(doc) == Decimal("100")


def test_sum_receipt_doc_payments_for_invoice_via_person_line():
    doc = Document()
    doc.lines = [
        _line(
            person_id=5,
            debit=Decimal(0),
            credit=Decimal("300"),
            extra_info={"invoice_id": 42},
        ),
        _line(
            person_id=6,
            debit=Decimal(0),
            credit=Decimal("200"),
            extra_info={"invoice_id": 99},
        ),
        _line(
            person_id=None,
            bank_account_id=1,
            debit=Decimal("500"),
            credit=Decimal(0),
            extra_info={"transaction_type": "bank"},
        ),
    ]
    assert _sum_receipt_doc_payments_for_invoice(doc, 42, via_person_line=True) == Decimal("300")
    assert _sum_receipt_doc_payments_for_invoice(doc, 42, via_person_line=False) == Decimal("500")
