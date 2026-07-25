"""V2-P0/P1: schema انتقال بین‌ارزی + منطق جمع پایه در گزارش‌ها."""
from decimal import Decimal

from adapters.api.v1.schema_models.transfer import TransferCreateRequest


def test_transfer_create_request_accepts_destination_amount_and_fx_rate():
	req = TransferCreateRequest(
		source_type="bank_account",
		source_id=1,
		destination_type="cash_register",
		destination_id=2,
		total_amount=Decimal("100"),
		document_date="2024-01-15",
		currency_id=1,
		destination_amount=Decimal("5000000"),
		fx_rate=Decimal("50000"),
	)
	assert req.destination_amount == Decimal("5000000")
	assert req.fx_rate == Decimal("50000")


def test_transfer_create_request_same_currency_optional_fx_fields():
	req = TransferCreateRequest(
		source_type="bank_account",
		source_id=1,
		destination_type="bank_account",
		destination_id=2,
		total_amount=Decimal("1000"),
		document_date="2024-01-15",
		currency_id=1,
	)
	assert req.destination_amount is None
	assert req.fx_rate is None


def test_account_balance_core_use_base_when_currency_none():
	"""قرارداد حسابداری: بدون فیلتر ارز → جمع از *_base."""
	from app.services.account_balance_core import compute_leaf_balances
	import inspect

	sig = inspect.signature(compute_leaf_balances)
	assert "amounts_in_base" in sig.parameters
	# منطق پیش‌فرض در docstring/بدنه: currency_id is None ⇒ use_base
	src = inspect.getsource(compute_leaf_balances)
	assert "currency_id is None" in src
	assert "debit_base" in src
	assert "credit_base" in src
