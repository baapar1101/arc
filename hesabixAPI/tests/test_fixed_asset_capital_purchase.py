"""تفکیک سطر سرمایه‌ای فاکتور خرید از موجودی — بدون دیتابیس."""
from decimal import Decimal

from app.services.fixed_asset_capital_purchase import (
	is_capital_invoice_line,
	invoice_line_skips_warehouse,
	purchase_gl_balances,
	split_purchase_debit_amounts,
)


def _line(*, qty, price, discount=0, tax=0, capital=False, class_id=None):
	extra = {
		"unit_price": price,
		"line_discount": discount,
		"tax_amount": tax,
	}
	if capital:
		extra["fixed_asset"] = True
		if class_id is not None:
			extra["fixed_asset_class_id"] = class_id
	return {"quantity": qty, "extra_info": extra}


def test_capital_flag_parsing():
	assert is_capital_invoice_line({"fixed_asset": True})
	assert is_capital_invoice_line({"fixed_asset": "true"})
	assert is_capital_invoice_line({"capitalization": {"enabled": True}})
	assert not is_capital_invoice_line({"fixed_asset": False})
	assert not is_capital_invoice_line({})
	assert invoice_line_skips_warehouse({"fixed_asset": True})
	assert not invoice_line_skips_warehouse({})


def test_mixed_invoice_splits_inventory_and_ppe_net_of_discount():
	split = split_purchase_debit_amounts(
		[
			_line(qty=2, price=1_000_000, discount=100_000, tax=90_000),
			_line(qty=1, price=5_000_000, discount=500_000, tax=450_000, capital=True, class_id=7),
		]
	)
	assert split.inventory_gross == Decimal("2000000.00")
	assert split.inventory_discount == Decimal("100000.00")
	assert split.capital_gross == Decimal("5000000.00")
	assert split.capital_discount == Decimal("500000.00")
	assert split.capital_net == Decimal("4500000.00")
	assert split.capital_net_by_class[7] == Decimal("4500000.00")
	assert split.purchase_discount_credit == Decimal("100000.00")


def test_all_capital_hits_no_inventory_and_balances():
	split = split_purchase_debit_amounts(
		[_line(qty=1, price=10_000_000, discount=1_000_000, tax=900_000, capital=True, class_id=4)]
	)
	assert split.inventory_gross == Decimal("0.00")
	assert split.purchase_discount_credit == Decimal("0.00")
	assert split.capital_net == Decimal("9000000.00")
	tax = Decimal("900000.00")
	payable = Decimal("9900000.00")  # 10m - 1m + 0.9m
	debits, credits = purchase_gl_balances(split, tax=tax, payable=payable)
	assert debits == credits == Decimal("9900000.00")


def test_mixed_gl_stays_balanced_when_fa_discount_is_netted_into_107():
	split = split_purchase_debit_amounts(
		[
			_line(qty=1, price=2_000_000, discount=0, tax=180_000),
			_line(qty=1, price=8_000_000, discount=800_000, tax=720_000, capital=True, class_id=4),
		]
	)
	tax = Decimal("900000.00")
	payable = Decimal("10100000.00")  # 2m + 8m - 0.8m + 0.9m
	debits, credits = purchase_gl_balances(split, tax=tax, payable=payable)
	assert debits == credits
	assert split.inventory_gross == Decimal("2000000.00")
	assert split.capital_net == Decimal("7200000.00")
	assert split.purchase_discount_credit == Decimal("0.00")


def test_capital_does_not_share_discount_account_with_inventory():
	split = split_purchase_debit_amounts(
		[
			_line(qty=1, price=1_000_000, discount=50_000),
			_line(qty=1, price=3_000_000, discount=300_000, capital=True, class_id=1),
		]
	)
	assert split.purchase_discount_credit == Decimal("50000.00")
	assert split.capital_net == Decimal("2700000.00")
