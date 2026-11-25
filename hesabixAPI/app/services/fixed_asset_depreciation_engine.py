"""
موتور استهلاک — بدون دسترسی به دیتابیس.

قراردادها:
- from_ready_date: استاندارد ۱۱؛ از تاریخ بهره‌برداری؛ ماه اول به نسبت روزهای فعال.
- next_month: ماده ۱۴۹؛ از اول ماه بعد از بهره‌برداری؛ ماه کامل.
- خط مستقیم: مبلغ استهلاک‌پذیر / عمر به ماه؛ یا sl_monthly_override پس از تغییر برآورد.
- مانده نزولی: NBV × نرخ سالانه / ۱۲.
- زمین و دارایی غیراستهلاک‌پذیر: صفر.
- NBV هرگز از ارزش اسقاط کمتر نمی‌شود.
- دفتر حسابداری هنگام رکود عامل ۱٫۰ دارد (استاندارد ۱۱ استهلاک را متوقف نمی‌کند).
- عامل راکد مالیاتی ۰٫۷ پس از بیش از ۶ ماه رکود فقط برای پیش‌نمایش است؛ در فاز ۲ سند دوم ثبت نمی‌شود.
"""
from __future__ import annotations

from calendar import monthrange
from dataclasses import dataclass
from datetime import date
from decimal import Decimal, ROUND_HALF_UP
from typing import Optional


METHOD_STRAIGHT_LINE = "straight_line"
METHOD_DECLINING = "declining_balance"
METHOD_UNITS = "units_of_production"

CONVENTION_FROM_READY = "from_ready_date"
CONVENTION_NEXT_MONTH = "next_month"

SUPPORTED_METHODS = frozenset({METHOD_STRAIGHT_LINE, METHOD_DECLINING})
SUPPORTED_CONVENTIONS = frozenset({CONVENTION_FROM_READY, CONVENTION_NEXT_MONTH})

TAX_IDLE_MONTHS = 6
TAX_IDLE_FACTOR_AFTER = Decimal("0.7")
ACCOUNTING_IDLE_FACTOR = Decimal("1")


class DepreciationEngineError(ValueError):
	"""خطای ورودی موتور؛ سرویس باید آن را به ApiError تبدیل کند."""


def month_start(d: date) -> date:
	return date(d.year, d.month, 1)


def month_end(d: date) -> date:
	return date(d.year, d.month, monthrange(d.year, d.month)[1])


def add_months(d: date, months: int) -> date:
	year = d.year + (d.month - 1 + months) // 12
	month = (d.month - 1 + months) % 12 + 1
	last = monthrange(year, month)[1]
	return date(year, month, min(d.day, last))


def inclusive_days(start: date, end: date) -> int:
	if end < start:
		return 0
	return (end - start).days + 1


def depreciation_start_date(commission_date: date, convention: str) -> date:
	if convention == CONVENTION_NEXT_MONTH:
		return add_months(month_start(commission_date), 1)
	if convention == CONVENTION_FROM_READY:
		return commission_date
	raise DepreciationEngineError(f"قرارداد استهلاک نامعتبر است: {convention}")


def _q(amount: Decimal, quant: Decimal) -> Decimal:
	return amount.quantize(quant, rounding=ROUND_HALF_UP)


def _as_decimal(value: object, field: str) -> Decimal:
	try:
		return Decimal(str(value))
	except Exception as exc:
		raise DepreciationEngineError(f"مقدار {field} نامعتبر است") from exc


@dataclass(frozen=True)
class DepreciationPeriodInput:
	cost: Decimal
	salvage: Decimal
	useful_life_months: Optional[int]
	method: str
	declining_annual_rate: Optional[Decimal]
	commission_date: date
	convention: str
	depreciable: bool
	already_depreciated: Decimal
	period_start: date
	period_end: date
	quant: Decimal = Decimal("1")
	idle_factor: Decimal = Decimal("1")
	sl_monthly_override: Optional[Decimal] = None


def remaining_depreciable(cost: Decimal, salvage: Decimal, already: Decimal) -> Decimal:
	if salvage < 0 or cost < 0 or already < 0:
		raise DepreciationEngineError("بها، اسقاط و استهلاک انباشته نمی‌توانند منفی باشند")
	if salvage > cost:
		return Decimal("0")
	left = cost - salvage - already
	return left if left > 0 else Decimal("0")


def compute_period_depreciation(inp: DepreciationPeriodInput) -> Decimal:
	"""مبلغ استهلاک یک دوره بسته [period_start, period_end]."""
	if inp.period_end < inp.period_start:
		raise DepreciationEngineError("پایان دوره قبل از شروع دوره است")
	if inp.quant <= 0:
		raise DepreciationEngineError("واحد گرد کردن نامعتبر است")

	if not inp.depreciable:
		return Decimal("0")
	if inp.method == METHOD_UNITS:
		raise DepreciationEngineError("روش تعداد تولید/کارکرد در این فاز پشتیبانی نمی‌شود")
	if inp.method not in SUPPORTED_METHODS:
		raise DepreciationEngineError(f"روش استهلاک نامعتبر است: {inp.method}")
	if inp.convention not in SUPPORTED_CONVENTIONS:
		raise DepreciationEngineError(f"قرارداد استهلاک نامعتبر است: {inp.convention}")

	cost = _as_decimal(inp.cost, "cost")
	salvage = _as_decimal(inp.salvage, "salvage")
	already = _as_decimal(inp.already_depreciated, "already_depreciated")
	remaining = remaining_depreciable(cost, salvage, already)
	if remaining <= 0:
		return Decimal("0")

	start = depreciation_start_date(inp.commission_date, inp.convention)
	if inp.period_end < start:
		return Decimal("0")

	active_start = max(inp.period_start, start)
	active_end = inp.period_end
	if active_end < active_start:
		return Decimal("0")

	if inp.method == METHOD_STRAIGHT_LINE:
		if inp.sl_monthly_override is not None:
			monthly = _as_decimal(inp.sl_monthly_override, "sl_monthly_override")
			if monthly < 0:
				raise DepreciationEngineError("مبلغ ماهانه خط مستقیم نمی‌تواند منفی باشد")
		else:
			life = int(inp.useful_life_months or 0)
			if life < 1:
				raise DepreciationEngineError("عمر مفید برای روش خط مستقیم باید حداقل یک ماه باشد")
			base = cost - salvage
			if base <= 0:
				return Decimal("0")
			monthly = base / Decimal(life)
		amount = _straight_line_for_active_window(
			monthly=monthly,
			convention=inp.convention,
			start=start,
			active_start=active_start,
			active_end=active_end,
		)
	else:
		rate = inp.declining_annual_rate
		if rate is None:
			raise DepreciationEngineError("نرخ سالانه مانده نزولی الزامی است")
		rate = _as_decimal(rate, "declining_annual_rate")
		if rate <= 0 or rate >= 1:
			raise DepreciationEngineError("نرخ مانده نزولی باید کسری بین ۰ و ۱ باشد (مثلاً ۰٫۲۵ برای ۲۵٪)")
		nbv = cost - already
		if nbv <= salvage:
			return Decimal("0")
		monthly = nbv * rate / Decimal("12")
		amount = _prorate_if_partial_first_month(
			monthly=monthly,
			convention=inp.convention,
			start=start,
			active_start=active_start,
			active_end=active_end,
		)

	if amount <= 0:
		return Decimal("0")
	factor = _as_decimal(inp.idle_factor, "idle_factor")
	if factor < 0 or factor > 1:
		raise DepreciationEngineError("عامل رکود باید بین ۰ و ۱ باشد")
	if factor != 1:
		amount = amount * factor
	if amount <= 0:
		return Decimal("0")
	if amount > remaining:
		amount = remaining
	return _q(amount, inp.quant)


def tax_idle_factor(
	idle_from: Optional[date],
	period_end: date,
	*,
	idle_months: int = TAX_IDLE_MONTHS,
	factor_after: Decimal = TAX_IDLE_FACTOR_AFTER,
) -> Decimal:
	"""پیش‌نمایش مالیاتی رکود. پیش‌فرض ماده ۱۴۹: پس از بیش از ۶ ماه، عامل ۰٫۷.

	ماه و عامل از تنظیمات کسب‌وکار خوانده می‌شوند تا با تغییر قانون عوض شوند.
	"""
	if idle_from is None:
		return Decimal("1")
	if period_end < idle_from:
		return Decimal("1")
	months = int(idle_months)
	if months < 0:
		raise DepreciationEngineError("آستانه ماه رکود مالیاتی نمی‌تواند منفی باشد")
	factor = _as_decimal(factor_after, "tax_idle_factor")
	if factor < 0 or factor > 1:
		raise DepreciationEngineError("عامل استهلاک مالیاتی رکود باید بین ۰ و ۱ باشد")
	threshold = add_months(idle_from, months)
	if period_end > threshold:
		return factor
	return Decimal("1")


def prospective_straight_line_monthly(
	*,
	cost: Decimal,
	salvage: Decimal,
	already: Decimal,
	remaining_months: int,
) -> Decimal:
	"""ماهانه خط مستقیم از تاریخ مؤثر: باقیمانده استهلاک‌پذیر / ماه‌های باقیمانده. گذشته بازنویسی نمی‌شود."""
	if remaining_months < 1:
		raise DepreciationEngineError("عمر باقیمانده باید حداقل یک ماه باشد")
	rem = remaining_depreciable(cost, salvage, already)
	if rem <= 0:
		return Decimal("0")
	return rem / Decimal(remaining_months)


def _straight_line_for_active_window(
	*,
	monthly: Decimal,
	convention: str,
	start: date,
	active_start: date,
	active_end: date,
) -> Decimal:
	return _prorate_if_partial_first_month(
		monthly=monthly,
		convention=convention,
		start=start,
		active_start=active_start,
		active_end=active_end,
	)


def _prorate_if_partial_first_month(
	*,
	monthly: Decimal,
	convention: str,
	start: date,
	active_start: date,
	active_end: date,
) -> Decimal:
	"""
	برای دوره ماهانه معمولی active_start..active_end یک ماه است.
	اگر قرارداد from_ready_date و شروع بهره‌برداری وسط ماه اول باشد، نسبت روز اعمال می‌شود.
	قرارداد next_month همیشه ماه کامل است (شروع از روز ۱).
	اگر بازه بیش از یک ماه باشد، ماه‌به‌ماه جمع می‌شود.
	"""
	total = Decimal("0")
	cursor = month_start(active_start)
	last = month_start(active_end)
	while cursor <= last:
		ms = month_start(cursor)
		me = month_end(cursor)
		win_start = max(ms, active_start)
		win_end = min(me, active_end)
		if win_end >= win_start:
			if convention == CONVENTION_FROM_READY and ms == month_start(start) and start > ms:
				days_month = inclusive_days(ms, me)
				days_active = inclusive_days(win_start, win_end)
				total += monthly * Decimal(days_active) / Decimal(days_month)
			else:
				# ماه کامل یا next_month
				if win_start == ms and win_end == me:
					total += monthly
				else:
					days_month = inclusive_days(ms, me)
					days_active = inclusive_days(win_start, win_end)
					total += monthly * Decimal(days_active) / Decimal(days_month)
		cursor = add_months(ms, 1)
	return total
