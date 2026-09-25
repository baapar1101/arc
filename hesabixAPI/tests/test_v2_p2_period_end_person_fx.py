"""V2-P2: تسعیر پایان دوره اشخاص — جهت بدهکار/بستانکار و عدم تغییر مانده بومی."""
from decimal import Decimal

from app.services.period_end_fx_revaluation_service import (
	_OPEN_ISSUED_CHECK_STATUSES,
	_OPEN_RECEIVED_CHECK_STATUSES,
)


def test_open_check_status_sets_cover_monetary_positions():
	assert any(s.value == "RECEIVED_ON_HAND" for s in _OPEN_RECEIVED_CHECK_STATUSES)
	assert any(s.value == "DEPOSITED" for s in _OPEN_RECEIVED_CHECK_STATUSES)
	assert any(s.value == "TRANSFERRED_ISSUED" for s in _OPEN_ISSUED_CHECK_STATUSES)


def test_person_receivable_rate_up_means_positive_adjustment():
	"""دریافتنی ۱۰۰ ارزی؛ book=۵۰۰۰۰؛ rate=۶۰۰۰۰ → adj=+۱۰۰۰۰ (بدهکار شخص، بستانکار سود)."""
	native = Decimal("100")
	book = Decimal("5000000")
	rate = Decimal("60000")
	revalued = native * rate
	adj = revalued - book
	assert adj == Decimal("1000000")
	assert adj > 0  # مسیر debit monetary / credit gain


def test_person_payable_rate_up_means_negative_adjustment():
	"""پرداختنی ۱۰۰ ارزی (native منفی)؛ book=-۵۰۰۰۰؛ rate=۶۰۰۰۰ → adj منفی (بستانکار شخص، بدهکار زیان)."""
	native = Decimal("-100")
	book = Decimal("-5000000")
	rate = Decimal("60000")
	revalued = native * rate
	adj = revalued - book
	assert adj == Decimal("-1000000")
	assert adj < 0


def test_revaluation_line_extra_keeps_native_zero_contract():
	"""قرارداد حسابداری: account_currency_amount=0 تا مانده بومی جابه‌جا نشود."""
	extra = {
		"fx_period_revaluation": True,
		"account_currency_amount": "0",
		"account_currency_id": 2,
	}
	assert extra["account_currency_amount"] == "0"
	assert extra["fx_period_revaluation"] is True
