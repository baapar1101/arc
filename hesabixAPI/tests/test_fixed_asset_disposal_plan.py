"""تست توازن خروج و مخارج بعدی — بدون دیتابیس."""
from decimal import Decimal

import pytest

from app.core.fixed_asset_accounts import (
	GAIN_DISPOSAL,
	LOSS_DISPOSAL,
	REPAIR_EXPENSE,
	VAT_OUTPUT,
)
from app.services.fixed_asset_disposal_plan import (
	DisposalPlanError,
	build_disposal_line_plan,
	build_subsequent_expenditure_plan,
)


def _sides(plan):
	return (
		sum(a for s, a, _r in plan if s == "debit"),
		sum(a for s, a, _r in plan if s == "credit"),
	)


def test_sale_with_gain_balances():
	# بها ۱۰٬ NBV ۷٬ عواید ۸ → سود ۱
	plan = build_disposal_line_plan(
		kind="sale",
		cost=Decimal("10000000"),
		accum=Decimal("3000000"),
		proceeds=Decimal("8000000"),
		vat_output=Decimal("0"),
	)
	debits, credits = _sides(plan)
	assert debits == credits == Decimal("11000000")
	roles = {r: a for _s, a, r in plan}
	assert roles["proceeds"] == Decimal("8000000")
	assert roles["accum"] == Decimal("3000000")
	assert roles["cost"] == Decimal("10000000")
	assert roles["gain"] == Decimal("1000000")
	assert "loss" not in roles


def test_sale_with_loss_balances():
	plan = build_disposal_line_plan(
		kind="sale",
		cost=Decimal("10000000"),
		accum=Decimal("3000000"),
		proceeds=Decimal("5000000"),
		vat_output=Decimal("0"),
	)
	debits, credits = _sides(plan)
	assert debits == credits == Decimal("10000000")
	roles = {r: a for _s, a, r in plan}
	assert roles["loss"] == Decimal("2000000")
	assert "gain" not in roles


def test_sale_at_nbv_has_neither_gain_nor_loss():
	plan = build_disposal_line_plan(
		kind="sale",
		cost=Decimal("10000000"),
		accum=Decimal("3000000"),
		proceeds=Decimal("7000000"),
		vat_output=Decimal("0"),
	)
	roles = {r: a for _s, a, r in plan}
	assert "gain" not in roles
	assert "loss" not in roles
	debits, credits = _sides(plan)
	assert debits == credits == Decimal("10000000")


def test_sale_with_output_vat_cash_is_proceeds_plus_vat():
	plan = build_disposal_line_plan(
		kind="sale",
		cost=Decimal("10000000"),
		accum=Decimal("4000000"),
		proceeds=Decimal("7000000"),
		vat_output=Decimal("630000"),
	)
	debits, credits = _sides(plan)
	assert debits == credits == Decimal("11630000")
	roles = {r: a for _s, a, r in plan}
	assert roles["proceeds"] == Decimal("7630000")
	assert roles["vat_out"] == Decimal("630000")
	assert roles["gain"] == Decimal("1000000")


def test_scrap_writes_nbv_to_loss():
	plan = build_disposal_line_plan(
		kind="scrap",
		cost=Decimal("10000000"),
		accum=Decimal("2500000"),
		proceeds=Decimal("0"),
		vat_output=Decimal("0"),
	)
	debits, credits = _sides(plan)
	assert debits == credits == Decimal("10000000")
	roles = {r: a for _s, a, r in plan}
	assert roles["loss"] == Decimal("7500000")
	assert "proceeds" not in roles
	assert "vat_out" not in roles


def test_fully_depreciated_scrap_only_reverses_cost_and_accum():
	plan = build_disposal_line_plan(
		kind="scrap",
		cost=Decimal("10000000"),
		accum=Decimal("10000000"),
		proceeds=Decimal("0"),
		vat_output=Decimal("0"),
	)
	assert plan == [
		("debit", Decimal("10000000"), "accum"),
		("credit", Decimal("10000000"), "cost"),
	]


def test_land_sale_no_accum_is_gain_or_loss_on_full_cost():
	plan = build_disposal_line_plan(
		kind="sale",
		cost=Decimal("50000000"),
		accum=Decimal("0"),
		proceeds=Decimal("60000000"),
		vat_output=Decimal("0"),
	)
	roles = {r: a for _s, a, r in plan}
	assert "accum" not in roles
	assert roles["gain"] == Decimal("10000000")


def test_scrap_rejects_proceeds():
	with pytest.raises(DisposalPlanError) as exc:
		build_disposal_line_plan(
			kind="scrap",
			cost=Decimal("100"),
			accum=Decimal("40"),
			proceeds=Decimal("1"),
			vat_output=Decimal("0"),
		)
	assert exc.value.code == "SCRAP_MUST_BE_ZERO"


def test_accum_over_cost_rejected():
	with pytest.raises(DisposalPlanError) as exc:
		build_disposal_line_plan(
			kind="sale",
			cost=Decimal("100"),
			accum=Decimal("101"),
			proceeds=Decimal("0"),
			vat_output=Decimal("0"),
		)
	assert exc.value.code == "INVALID_ACCUM"


def test_routine_repair_is_period_expense():
	plan = build_subsequent_expenditure_plan(
		kind="routine",
		amount=Decimal("400000"),
		vat=Decimal("36000"),
	)
	assert plan == [
		("debit", Decimal("400000"), "repair_expense"),
		("debit", Decimal("36000"), "vat"),
		("credit", Decimal("436000"), "counterparty"),
	]


def test_major_repair_is_added_to_cost():
	plan = build_subsequent_expenditure_plan(
		kind="major",
		amount=Decimal("2000000"),
		vat=Decimal("0"),
	)
	assert plan[0] == ("debit", Decimal("2000000"), "cost")
	debits, credits = _sides(plan)
	assert debits == credits


def test_phase2_coa_codes_do_not_collide_with_phase1():
	assert GAIN_DISPOSAL == "60206"
	assert LOSS_DISPOSAL == "70804"
	assert REPAIR_EXPENSE == "70404"
	assert VAT_OUTPUT == "20101"
