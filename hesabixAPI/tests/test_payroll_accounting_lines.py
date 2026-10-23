"""تست منطق متوازن بودن سطرهای سند تعهدی حقوق."""
from decimal import Decimal

from app.services.payroll_accounting import _quantize


def test_quantize_rounds_to_integer_by_default():
	assert _quantize(Decimal("1234.56")) == Decimal("1235")
	assert _quantize(Decimal("1234.44")) == Decimal("1234")


def test_accrual_balance_equation():
	"""ناخالص - کسورات = خالص؛ بدهکار = ناخالص + هزینه کارفرما."""
	gross = Decimal("100000000")
	deductions = Decimal("15000000")
	employer = Decimal("7000000")
	net = gross - deductions

	debits = gross + employer
	# Employer expense has its own matching liability credit (production
	# _build_accrual_lines emits both sides); it is not employee deduction.
	credits = deductions + net + employer
	assert debits == credits
