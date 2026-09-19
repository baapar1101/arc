from decimal import Decimal

from app.services.person_service import _person_balance_status_from_totals


def test_sale_invoice_debit_makes_person_debtor():
    debit = Decimal("10000000")
    credit = Decimal("0")
    balance = credit - debit
    assert _person_balance_status_from_totals(credit, debit, balance) == "بدهکار"
    assert balance < 0


def test_purchase_invoice_credit_makes_person_creditor():
    debit = Decimal("0")
    credit = Decimal("10000000")
    balance = credit - debit
    assert _person_balance_status_from_totals(credit, debit, balance) == "بستانکار"
    assert balance > 0


def test_zero_activity_is_no_transaction():
    assert _person_balance_status_from_totals(Decimal(0), Decimal(0), Decimal(0)) == "بدون تراکنش"


def test_equal_debit_credit_is_balanced():
    assert _person_balance_status_from_totals(Decimal(5), Decimal(5), Decimal(0)) == "بالانس"
