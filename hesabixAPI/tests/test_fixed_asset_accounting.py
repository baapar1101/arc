"""تست توازن تحصیل دارایی — بدون دیتابیس و بدون FastAPI."""
from decimal import Decimal

import pytest

from app.core.fixed_asset_accounts import COST_FURNITURE, COST_LAND, SYSTEM_CLASSES
from app.services.fixed_asset_acquisition_plan import AcquisitionPlanError, build_acquisition_line_plan


def test_purchase_balances_cost_plus_vat():
	plan = build_acquisition_line_plan(
		kind="purchase",
		cost=Decimal("15000000"),
		vat=Decimal("1350000"),
		opening_accum=Decimal("0"),
	)
	debits = sum(a for s, a in plan if s == "debit")
	credits = sum(a for s, a in plan if s == "credit")
	assert debits == credits == Decimal("16350000")
	assert plan == [
		("debit", Decimal("15000000")),
		("debit", Decimal("1350000")),
		("credit", Decimal("16350000")),
	]


def test_purchase_without_vat_is_simple_two_line():
	plan = build_acquisition_line_plan(
		kind="purchase",
		cost=Decimal("1000"),
		vat=Decimal("0"),
		opening_accum=Decimal("0"),
	)
	assert plan == [("debit", Decimal("1000")), ("credit", Decimal("1000"))]


def test_opening_credits_accum_and_equity_for_nbv():
	plan = build_acquisition_line_plan(
		kind="opening",
		cost=Decimal("10000000"),
		vat=Decimal("0"),
		opening_accum=Decimal("2500000"),
	)
	debits = sum(a for s, a in plan if s == "debit")
	credits = sum(a for s, a in plan if s == "credit")
	assert debits == credits == Decimal("10000000")
	assert ("credit", Decimal("2500000")) in plan
	assert ("credit", Decimal("7500000")) in plan


def test_opening_accum_not_allowed_to_equal_cost():
	with pytest.raises(AcquisitionPlanError) as exc:
		build_acquisition_line_plan(
			kind="opening",
			cost=Decimal("100"),
			vat=Decimal("0"),
			opening_accum=Decimal("100"),
		)
	assert exc.value.code == "INVALID_OPENING_ACCUM"


def test_zero_cost_rejected():
	with pytest.raises(AcquisitionPlanError) as exc:
		build_acquisition_line_plan(
			kind="purchase",
			cost=Decimal("0"),
			vat=Decimal("0"),
			opening_accum=Decimal("0"),
		)
	assert exc.value.code == "INVALID_COST"


def test_system_classes_cover_land_and_furniture():
	codes = {c["code"]: c for c in SYSTEM_CLASSES}
	assert codes["land"]["depreciable"] is False
	assert codes["land"]["cost_account_code"] == COST_LAND
	assert codes["furniture"]["depreciable"] is True
	assert codes["furniture"]["cost_account_code"] == COST_FURNITURE
	assert codes["furniture"]["accum_dep_account_code"] == "10804"
	assert codes["furniture"]["dep_expense_account_code"] == "70411"
