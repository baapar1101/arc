"""تست‌های عددی موتور استهلاک — بدون دیتابیس."""
from datetime import date
from decimal import Decimal

import pytest

from app.services.fixed_asset_depreciation_engine import (
	ACCOUNTING_IDLE_FACTOR,
	CONVENTION_FROM_READY,
	CONVENTION_NEXT_MONTH,
	DepreciationEngineError,
	DepreciationPeriodInput,
	METHOD_DECLINING,
	METHOD_STRAIGHT_LINE,
	METHOD_UNITS,
	TAX_IDLE_FACTOR_AFTER,
	compute_period_depreciation,
	depreciation_start_date,
	inclusive_days,
	prospective_straight_line_monthly,
	remaining_depreciable,
	tax_idle_factor,
)


def _inp(**overrides) -> DepreciationPeriodInput:
	base = dict(
		cost=Decimal("15000000"),
		salvage=Decimal("0"),
		useful_life_months=60,
		method=METHOD_STRAIGHT_LINE,
		declining_annual_rate=None,
		commission_date=date(2026, 5, 15),
		convention=CONVENTION_NEXT_MONTH,
		depreciable=True,
		already_depreciated=Decimal("0"),
		period_start=date(2026, 6, 1),
		period_end=date(2026, 6, 30),
		quant=Decimal("1"),
	)
	base.update(overrides)
	return DepreciationPeriodInput(**base)


def test_land_never_depreciates():
	assert compute_period_depreciation(_inp(depreciable=False)) == Decimal("0")


def test_next_month_starts_first_of_following_month():
	assert depreciation_start_date(date(2026, 5, 15), CONVENTION_NEXT_MONTH) == date(2026, 6, 1)
	assert depreciation_start_date(date(2026, 5, 1), CONVENTION_NEXT_MONTH) == date(2026, 6, 1)


def test_from_ready_starts_on_commission_date():
	assert depreciation_start_date(date(2026, 5, 15), CONVENTION_FROM_READY) == date(2026, 5, 15)


def test_straight_line_full_month_is_cost_over_life():
	# 15,000,000 / 60 = 250,000
	assert compute_period_depreciation(_inp()) == Decimal("250000")


def test_straight_line_month_before_start_is_zero():
	got = compute_period_depreciation(
		_inp(period_start=date(2026, 5, 1), period_end=date(2026, 5, 31))
	)
	assert got == Decimal("0")


def test_from_ready_prorates_first_month_inclusive_days():
	# May 15..31 inclusive = 17 days; May has 31 days
	assert inclusive_days(date(2026, 5, 15), date(2026, 5, 31)) == 17
	monthly = Decimal("15000000") / Decimal("60")
	expected = (monthly * Decimal("17") / Decimal("31")).quantize(Decimal("1"))
	got = compute_period_depreciation(
		_inp(
			convention=CONVENTION_FROM_READY,
			period_start=date(2026, 5, 1),
			period_end=date(2026, 5, 31),
		)
	)
	assert got == expected


def test_from_ready_second_month_is_full():
	got = compute_period_depreciation(
		_inp(
			convention=CONVENTION_FROM_READY,
			period_start=date(2026, 6, 1),
			period_end=date(2026, 6, 30),
		)
	)
	assert got == Decimal("250000")


def test_does_not_exceed_remaining():
	got = compute_period_depreciation(_inp(already_depreciated=Decimal("14980000")))
	assert got == Decimal("20000")


def test_fully_depreciated_is_zero():
	got = compute_period_depreciation(_inp(already_depreciated=Decimal("15000000")))
	assert got == Decimal("0")


def test_salvage_floor():
	got = compute_period_depreciation(
		_inp(salvage=Decimal("1000000"), already_depreciated=Decimal("13980000"))
	)
	assert got == Decimal("20000")
	assert remaining_depreciable(Decimal("15000000"), Decimal("1000000"), Decimal("14000000")) == 0


def test_salvage_equal_cost_is_zero():
	assert compute_period_depreciation(_inp(salvage=Decimal("15000000"))) == Decimal("0")


def test_declining_first_month():
	# NBV 10,000,000 × 25% / 12 = 208,333.333... → 208333 with quant=1
	got = compute_period_depreciation(
		_inp(
			cost=Decimal("10000000"),
			method=METHOD_DECLINING,
			declining_annual_rate=Decimal("0.25"),
			useful_life_months=None,
		)
	)
	assert got == Decimal("208333")


def test_declining_uses_remaining_book_value():
	got = compute_period_depreciation(
		_inp(
			cost=Decimal("10000000"),
			already_depreciated=Decimal("208333"),
			method=METHOD_DECLINING,
			declining_annual_rate=Decimal("0.25"),
			useful_life_months=None,
		)
	)
	from decimal import ROUND_HALF_UP

	nbv = Decimal("10000000") - Decimal("208333")
	expected = (nbv * Decimal("0.25") / Decimal("12")).quantize(Decimal("1"), rounding=ROUND_HALF_UP)
	assert got == expected


def test_units_of_production_rejected_in_phase1():
	with pytest.raises(DepreciationEngineError):
		compute_period_depreciation(_inp(method=METHOD_UNITS))


def test_invalid_period_raises():
	with pytest.raises(DepreciationEngineError):
		compute_period_depreciation(
			_inp(period_start=date(2026, 6, 30), period_end=date(2026, 6, 1))
		)


def test_straight_line_requires_life():
	with pytest.raises(DepreciationEngineError):
		compute_period_depreciation(_inp(useful_life_months=0))


def test_declining_rate_must_be_fraction():
	with pytest.raises(DepreciationEngineError):
		compute_period_depreciation(
			_inp(
				method=METHOD_DECLINING,
				declining_annual_rate=Decimal("25"),
				useful_life_months=None,
			)
		)


def test_negative_amounts_rejected():
	with pytest.raises(DepreciationEngineError):
		remaining_depreciable(Decimal("10"), Decimal("-1"), Decimal("0"))


def test_quant_two_decimals():
	got = compute_period_depreciation(
		_inp(
			cost=Decimal("100"),
			useful_life_months=3,
			commission_date=date(2026, 5, 1),
			convention=CONVENTION_NEXT_MONTH,
			period_start=date(2026, 6, 1),
			period_end=date(2026, 6, 30),
			quant=Decimal("0.01"),
		)
	)
	assert got == Decimal("33.33")


def test_accounting_idle_factor_default_is_full():
	assert ACCOUNTING_IDLE_FACTOR == Decimal("1")
	assert compute_period_depreciation(_inp(idle_factor=ACCOUNTING_IDLE_FACTOR)) == Decimal("250000")


def test_tax_idle_factor_stays_one_until_more_than_six_months():
	idle_from = date(2026, 1, 1)
	assert tax_idle_factor(None, date(2026, 12, 31)) == Decimal("1")
	assert tax_idle_factor(idle_from, date(2026, 6, 30)) == Decimal("1")
	assert tax_idle_factor(idle_from, date(2026, 7, 1)) == Decimal("1")
	assert tax_idle_factor(idle_from, date(2026, 7, 2)) == TAX_IDLE_FACTOR_AFTER


def test_tax_idle_threshold_and_factor_are_configurable():
	idle_from = date(2026, 1, 1)
	assert tax_idle_factor(
		idle_from,
		date(2026, 4, 2),
		idle_months=3,
		factor_after=Decimal("0.5"),
	) == Decimal("0.5")
	assert tax_idle_factor(
		idle_from,
		date(2026, 4, 1),
		idle_months=3,
		factor_after=Decimal("0.5"),
	) == Decimal("1")


def test_idle_factor_reduces_posted_amount_only_when_passed():
	full = compute_period_depreciation(_inp())
	reduced = compute_period_depreciation(_inp(idle_factor=TAX_IDLE_FACTOR_AFTER))
	assert full == Decimal("250000")
	assert reduced == Decimal("175000")


def test_sl_monthly_override_is_prospective_not_original_life():
	# بها ۱۵٬۰۰۰٬۰۰۰ / ۶۰ = ۲۵۰٬۰۰۰ اصلی؛ پس از انباشته ۵٬۰۰۰٬۰۰۰ باقی ۱۰٬۰۰۰٬۰۰۰ روی ۴۰ ماه = ۲۵۰٬۰۰۰
	# اگر عمر باقیمانده را ۲۰ ماه بگذاریم ماهانه باید ۵۰۰٬۰۰۰ شود نه ۲۵۰٬۰۰۰.
	override = prospective_straight_line_monthly(
		cost=Decimal("15000000"),
		salvage=Decimal("0"),
		already=Decimal("5000000"),
		remaining_months=20,
	)
	assert override == Decimal("500000")
	got = compute_period_depreciation(
		_inp(
			already_depreciated=Decimal("5000000"),
			useful_life_months=60,
			sl_monthly_override=override,
		)
	)
	assert got == Decimal("500000")
	original_monthly = compute_period_depreciation(
		_inp(already_depreciated=Decimal("5000000"), useful_life_months=60)
	)
	assert original_monthly == Decimal("250000")
	assert got != original_monthly


def test_sl_override_still_respects_salvage_floor():
	got = compute_period_depreciation(
		_inp(
			salvage=Decimal("1000000"),
			already_depreciated=Decimal("13980000"),
			sl_monthly_override=Decimal("500000"),
		)
	)
	assert got == Decimal("20000")
