"""خدمت و کالای بدون موجودی نباید حساب موجودی کالا را لمس کنند."""
from decimal import Decimal
from types import SimpleNamespace
from unittest.mock import MagicMock

from adapters.db.models.product import ProductItemType
from app.services.invoice_inventory_policy import invoice_line_posts_to_inventory
from app.services.invoice_service import _extract_cogs_total_for_invoice
from app.services.purchase_accounting_service import (
	PURCHASE_ACCOUNTING_DIRECT,
	PURCHASE_ACCOUNTING_GRNI,
	add_purchase_invoice_debit_lines,
	add_purchase_return_credit_lines,
)


def test_tracked_goods_post_to_inventory():
	assert invoice_line_posts_to_inventory({"inventory_tracked": True}) is True
	assert invoice_line_posts_to_inventory({}) is True


def test_service_and_untracked_do_not_post_to_inventory():
	assert invoice_line_posts_to_inventory({"inventory_tracked": False}) is False
	assert invoice_line_posts_to_inventory({"item_type": "خدمت"}) is False
	product = SimpleNamespace(item_type=ProductItemType.SERVICE, track_inventory=False)
	assert invoice_line_posts_to_inventory({}, product) is False
	untracked_goods = SimpleNamespace(item_type=ProductItemType.PRODUCT, track_inventory=False)
	assert invoice_line_posts_to_inventory({}, untracked_goods) is False
	assert invoice_line_posts_to_inventory({"inventory_tracked": True}, untracked_goods) is True


def test_capital_line_does_not_post_to_inventory():
	assert invoice_line_posts_to_inventory({"fixed_asset": True, "inventory_tracked": True}) is False


def test_extract_cogs_skips_services():
	total = _extract_cogs_total_for_invoice(
		[
			{"quantity": 2, "extra_info": {"cost_price": 100, "inventory_tracked": True}},
			{"quantity": 3, "extra_info": {"cost_price": 50, "inventory_tracked": False}},
			{"quantity": 1, "extra_info": {"unit_price": 999, "item_type": "خدمت"}},
		]
	)
	assert total == Decimal("200")


def _accounts():
	return {
		"inventory": SimpleNamespace(id=10102),
		"grni": SimpleNamespace(id=10107),
		"purchase_service": SimpleNamespace(id=70401),
	}


def test_purchase_posts_services_to_70401_and_goods_to_inventory():
	db = MagicMock()
	add_purchase_invoice_debit_lines(
		db,
		document_id=9,
		mode=PURCHASE_ACCOUNTING_DIRECT,
		accounts=_accounts(),
		gross=Decimal("2000000"),
		service_gross=Decimal("7000000"),
	)
	added = [call.args[0] for call in db.add.call_args_list]
	by_account = {int(row.account_id): row for row in added}
	assert by_account[10102].debit == Decimal("2000000")
	assert by_account[10102].credit == Decimal("0")
	assert by_account[70401].debit == Decimal("7000000")
	assert by_account[70401].description == "خرید خدمات"


def test_purchase_service_only_does_not_touch_inventory():
	db = MagicMock()
	add_purchase_invoice_debit_lines(
		db,
		document_id=9,
		mode=PURCHASE_ACCOUNTING_DIRECT,
		accounts=_accounts(),
		gross=Decimal("0"),
		service_gross=Decimal("1500000"),
	)
	added = [call.args[0] for call in db.add.call_args_list]
	assert len(added) == 1
	assert added[0].account_id == 70401
	assert added[0].debit == Decimal("1500000")


def test_grni_mode_still_expenses_services():
	db = MagicMock()
	add_purchase_invoice_debit_lines(
		db,
		document_id=9,
		mode=PURCHASE_ACCOUNTING_GRNI,
		accounts=_accounts(),
		gross=Decimal("500"),
		service_gross=Decimal("300"),
	)
	added = [call.args[0] for call in db.add.call_args_list]
	by_account = {int(row.account_id): row for row in added}
	assert by_account[10107].debit == Decimal("500")
	assert by_account[70401].debit == Decimal("300")
	assert 10102 not in by_account


def test_purchase_return_credits_service_expense():
	db = MagicMock()
	add_purchase_return_credit_lines(
		db,
		document_id=4,
		mode=PURCHASE_ACCOUNTING_DIRECT,
		accounts=_accounts(),
		gross=Decimal("100"),
		service_gross=Decimal("40"),
	)
	added = [call.args[0] for call in db.add.call_args_list]
	by_account = {int(row.account_id): row for row in added}
	assert by_account[10102].credit == Decimal("100")
	assert by_account[70401].credit == Decimal("40")
	assert by_account[70401].description == "برگشت خرید خدمات"
