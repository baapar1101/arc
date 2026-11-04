"""محاسبات خالص افزونه تولید پیشرفته.

این ماژول به پایگاه‌داده و فریم‌ورک وابسته نیست تا قواعد بها و پیشرفت
بدون اثر روی دفتر کل قابل آزمون باشند.
"""
from __future__ import annotations

from datetime import date, datetime
from decimal import Decimal, ROUND_HALF_UP
from typing import Optional

COSTING_METHODS = ("actual", "standard", "weighted_average")
OVERHEAD_MODES = ("bom_operations",)
OPEN_STATUSES = ("draft", "released", "in_progress")
CLOSED_STATUSES = ("completed", "cancelled")
MONEY = Decimal("0.01")
QTY = Decimal("0.000001")
PERCENT = Decimal("0.01")


def D(value) -> Decimal:
	if value is None or value == "":
		return Decimal("0")
	if isinstance(value, Decimal):
		return value
	return Decimal(str(value))


def money(value) -> Decimal:
	return D(value).quantize(MONEY, rounding=ROUND_HALF_UP)


def qty(value) -> Decimal:
	return D(value).quantize(QTY, rounding=ROUND_HALF_UP)


def remaining_quantity(planned, produced) -> Decimal:
	return qty(max(D(planned) - D(produced), Decimal("0")))


def progress_percent(planned, produced) -> Decimal:
	planned_qty = D(planned)
	if planned_qty <= 0:
		return Decimal("0.00")
	return (D(produced) / planned_qty * Decimal("100")).quantize(PERCENT, rounding=ROUND_HALF_UP)


def intersect_date_range(requested_from, requested_to, bound_from, bound_to):
	"""اشتراک دو بازه inclusive. اگر اشتراکی نباشد ردیف سوم True است."""
	start = requested_from
	end = requested_to
	if bound_from is not None and (start is None or start < bound_from):
		start = bound_from
	if bound_to is not None and (end is None or end > bound_to):
		end = bound_to
	empty = start is not None and end is not None and start > end
	return start, end, empty


def is_overdue(due: Optional[date], today: date, status: str) -> bool:
	if due is None or status in CLOSED_STATUSES:
		return False
	return due < today


def cycle_hours(started: Optional[datetime], completed: Optional[datetime]) -> Optional[Decimal]:
	if started is None or completed is None:
		return None
	seconds = (completed - started).total_seconds()
	if seconds < 0:
		return None
	return (D(seconds) / Decimal("3600")).quantize(PERCENT, rounding=ROUND_HALF_UP)


def quantity_variance(actual_qty, standard_qty) -> Decimal:
	"""مثبت یعنی مصرف یا تولید بیش از استاندارد."""
	return qty(D(actual_qty) - D(standard_qty))


def wage_variances(actual_hours, standard_hours, standard_hourly_rate, actual_hourly_rate) -> Optional[dict]:
	"""انحراف نرخ و کارایی دستمزد. مثبت نامساعد است.

	بدون ساعت واقعی، یا بدون نرخ استاندارد، هیچ انحرافی ساخته نمی‌شود.
	بدون ساعت استاندارد، فقط انحراف نرخ (اگر نرخ واقعی باشد) برمی‌گردد.
	"""
	actual = D(actual_hours)
	if actual <= 0 or standard_hourly_rate in (None, ""):
		return None
	standard_rate = D(standard_hourly_rate)
	if standard_rate <= 0:
		return None
	rate = None
	if actual_hourly_rate not in (None, ""):
		rate = money((D(actual_hourly_rate) - standard_rate) * actual)
	efficiency = None
	if standard_hours not in (None, ""):
		efficiency = money((actual - D(standard_hours)) * standard_rate)
	if rate is None and efficiency is None:
		return None
	return {"rate_variance": rate, "efficiency_variance": efficiency}


def material_rate_split(planned_qty, issued_qty, standard_unit_cost, actual_total) -> Optional[dict]:
	"""انحراف مصرف به نرخ استاندارد سفارش، و انحراف نرخ روی مقدار صادرشده.

	اگر نرخ استاندارد صفر باشد None است. بدون صدور، انحراف نرخ قابل محاسبه نیست.
	نرخ استاندارد همان نرخ ردیف سفارش است، نه فهرست جداگانه قیمت خرید.
	"""
	standard_unit = D(standard_unit_cost)
	if standard_unit <= 0:
		return None
	issued = D(issued_qty)
	usage = money((issued - D(planned_qty)) * standard_unit)
	price = None if issued <= 0 else money(D(actual_total) - issued * standard_unit)
	return {"usage_variance": usage, "price_variance": price}


def cost_variance(actual_cost, standard_cost) -> Decimal:
	"""مثبت یعنی هزینه نامساعد نسبت به استاندارد."""
	return money(D(actual_cost) - D(standard_cost))


def weighted_average_unit(total_cost, total_quantity) -> Optional[Decimal]:
	total_qty = D(total_quantity)
	if total_qty <= 0:
		return None
	return (D(total_cost) / total_qty).quantize(Decimal("0.000001"), rounding=ROUND_HALF_UP)


def calendar_period(value, calendar_type: str) -> Optional[str]:
	"""ماه دوره بر اساس تقویم نمایش. تاریخ خالی None است."""
	if value in (None, ""):
		return None
	from datetime import date, datetime
	from app.core.calendar import CalendarConverter

	if isinstance(value, datetime):
		day = value.date()
	elif isinstance(value, date):
		day = value
	else:
		day = date.fromisoformat(str(value)[:10])
	formatted = CalendarConverter.format_datetime(datetime(day.year, day.month, day.day), "jalali" if calendar_type == "jalali" else "gregorian")
	if not formatted:
		return None
	return f"{int(formatted['year']):04d}-{int(formatted['month']):02d}"


def required_hours(remaining_quantity, nominal_per_hour) -> Optional[Decimal]:
	"""ساعت لازم برای مانده سفارش روی نرخ ساعتی خط. نرخ صفر یعنی ساعت قابل محاسبه نیست."""
	nominal = D(nominal_per_hour)
	if nominal <= 0:
		return None
	remaining = D(remaining_quantity)
	if remaining < 0:
		remaining = Decimal("0")
	return (remaining / nominal).quantize(Decimal("0.000001"), rounding=ROUND_HALF_UP)


def units_per_hour(quantity, run_minutes) -> Optional[Decimal]:
	minutes = D(run_minutes)
	if minutes <= 0:
		return None
	return (D(quantity) * Decimal("60") / minutes).quantize(Decimal("0.000001"), rounding=ROUND_HALF_UP)


def conversion_percent(output_quantity, input_quantity) -> Optional[Decimal]:
	"""خروجی تقسیم بر مصرف همان سفارش. سقف ندارد؛ واحدهای متفاوت را با هم قاطی نمی‌کند."""
	output = D(output_quantity)
	incoming = D(input_quantity)
	if output <= 0 or incoming <= 0:
		return None
	return (output / incoming * Decimal("100")).quantize(PERCENT, rounding=ROUND_HALF_UP)


def yield_percent(good_quantity, scrap_quantity) -> Optional[Decimal]:
	good = D(good_quantity)
	scrap = D(scrap_quantity)
	total = good + scrap
	if total <= 0 or good < 0 or scrap < 0:
		return None
	return (good / total * Decimal("100")).quantize(PERCENT, rounding=ROUND_HALF_UP)


def unused_quantity(ideal_quantity, actual_quantity) -> Optional[Decimal]:
	if ideal_quantity is None:
		return None
	gap = D(ideal_quantity) - D(actual_quantity)
	if gap <= 0:
		return Decimal("0")
	return qty(gap)


def break_even_quantity(fixed_cost, sales_amount, sales_quantity, variable_unit_cost) -> Optional[Decimal]:
	"""مقدار فروش برای پوشش هزینه ثابت. اگر حاشیه سهم صفر یا منفی باشد None است."""
	fixed = D(fixed_cost)
	sold = D(sales_quantity)
	if fixed <= 0 or sold <= 0 or variable_unit_cost is None:
		return None
	price = D(sales_amount) / sold
	contribution = price - D(variable_unit_cost)
	if contribution <= 0:
		return None
	return (fixed / contribution).quantize(QTY, rounding=ROUND_HALF_UP)


def capacity_gap(nominal_per_hour, run_minutes, actual_quantity) -> Optional[dict]:
	"""ظرفیت اسمی در برابر مقدار واقعی. اگر ظرفیت یا زمان صفر باشد None است."""
	minutes = D(run_minutes)
	nominal = D(nominal_per_hour)
	if minutes <= 0 or nominal <= 0:
		return None
	ideal = (nominal * minutes / Decimal("60")).quantize(Decimal("0.000001"), rounding=ROUND_HALF_UP)
	if ideal <= 0:
		return None
	actual = D(actual_quantity)
	return {
		"ideal_quantity": ideal,
		"actual_quantity": qty(actual),
		"utilization_percent": (actual / ideal * Decimal("100")).quantize(PERCENT, rounding=ROUND_HALF_UP),
	}


def cost_share(materials_cost, operations_cost) -> Optional[dict]:
	"""سهم مواد و عملیات از جمع همان دو جزء. اگر جمع صفر باشد None است."""
	materials = money(materials_cost)
	operations = money(operations_cost)
	total = materials + operations
	if total <= 0:
		return None
	return {
		"materials": materials,
		"operations": operations,
		"total": total,
		"materials_percent": (materials / total * Decimal("100")).quantize(PERCENT, rounding=ROUND_HALF_UP),
		"operations_percent": (operations / total * Decimal("100")).quantize(PERCENT, rounding=ROUND_HALF_UP),
	}


def acceptance_rate(quantity_checked, quantity_rejected) -> Optional[Decimal]:
	checked = D(quantity_checked)
	rejected = D(quantity_rejected)
	if checked <= 0 or rejected < 0 or rejected > checked:
		return None
	return ((checked - rejected) / checked * Decimal("100")).quantize(PERCENT, rounding=ROUND_HALF_UP)


def product_margin(sales_amount, sales_quantity, production_cost, produced_quantity):
	"""حاشیه مدیریتی: فروش دوره منهای بهای واحد تولید همان دوره ضربدر مقدار فروش.

	اگر در دوره تولید نشده باشد، حاشیه None است تا سود صددرصد جعلی ساخته نشود.
	این عدد بهای تمام‌شده فروش ثبت‌شده در دفتر کل نیست.
	"""
	sold = D(sales_quantity)
	made = D(produced_quantity)
	if sold <= 0 or made <= 0:
		return None
	unit = (D(production_cost) / made).quantize(Decimal("0.000001"), rounding=ROUND_HALF_UP)
	cogs = money(unit * sold)
	margin = money(D(sales_amount) - cogs)
	ratio = None
	sales = D(sales_amount)
	if sales > 0:
		ratio = (margin / sales * Decimal("100")).quantize(PERCENT, rounding=ROUND_HALF_UP)
	return {"unit_cost": unit, "estimated_cogs": cogs, "margin": margin, "margin_percent": ratio}


EXPORT_CODE_MESSAGES = {
	"status": {
		"draft": "AP_STATUS_DRAFT",
		"released": "AP_STATUS_RELEASED",
		"in_progress": "AP_STATUS_IN_PROGRESS",
		"completed": "AP_STATUS_COMPLETED",
		"cancelled": "AP_STATUS_CANCELLED",
	},
	"stage": {
		"incoming": "AP_STAGE_INCOMING",
		"in_process": "AP_STAGE_IN_PROCESS",
		"final": "AP_STAGE_FINAL",
	},
	"result": {
		"pass": "AP_RESULT_PASS",
		"fail": "AP_RESULT_FAIL",
	},
	"kind": {
		"breakdown": "AP_MAINTENANCE_BREAKDOWN",
		"preventive": "AP_MAINTENANCE_PREVENTIVE",
	},
	"maintenance_kind": {
		"breakdown": "AP_MAINTENANCE_BREAKDOWN",
		"preventive": "AP_MAINTENANCE_PREVENTIVE",
	},
	"basis": {
		"actual": "AP_BASIS_ACTUAL",
		"standard": "AP_BASIS_STANDARD",
	},
	"role": {
		"material": "AP_ROLE_MATERIAL",
		"output": "AP_ROLE_OUTPUT",
	},
	"costing_method": {
		"actual": "AP_BASIS_ACTUAL",
		"standard": "AP_BASIS_STANDARD",
		"weighted_average": "AP_BASIS_WEIGHTED_AVERAGE",
	},
	"recyclable": {
		"true": "AP_RECYCLABLE_YES",
		"false": "AP_RECYCLABLE_NO",
	},
}


def export_code_message(field: str, value) -> Optional[str]:
	"""کلید ترجمهٔ کدهای ثابت خروجی. مقدار ناشناخته یا ستون آزاد None می‌ماند."""
	table = EXPORT_CODE_MESSAGES.get(field)
	if table is None or value is None or value == "":
		return None
	if isinstance(value, bool):
		token = "true" if value else "false"
	else:
		token = str(value).strip()
		if field == "recyclable":
			token = token.lower()
	return table.get(token)


def mean_gap_days(dates: list[date]) -> Optional[Decimal]:
	"""میانگین فاصله روز بین خرابی‌های مرتب‌شده. با کمتر از دو تاریخ None است."""
	ordered = sorted(dates)
	if len(ordered) < 2:
		return None
	gaps = [(ordered[index] - ordered[index - 1]).days for index in range(1, len(ordered))]
	return (Decimal(sum(gaps)) / Decimal(len(gaps))).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)


def mean_minutes(values: list[int]) -> Optional[Decimal]:
	if not values:
		return None
	return (Decimal(sum(values)) / Decimal(len(values))).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)


def oee_factors(run_minutes, downtime_minutes, ideal_quantity, good_quantity, scrap_quantity) -> dict:
	"""OEE = دسترس‌پذیری × عملکرد × کیفیت. هر عامل حداکثر ۱ است. بدون داده، None."""
	run = D(run_minutes)
	down = D(downtime_minutes)
	planned = run + down
	ideal = D(ideal_quantity)
	good = D(good_quantity)
	scrap = D(scrap_quantity)
	total = good + scrap
	availability = (run / planned) if planned > 0 else None
	performance = (total / ideal) if ideal > 0 else None
	quality = (good / total) if total > 0 else None

	def cap(value):
		if value is None:
			return None
		return min(max(value, Decimal("0")), Decimal("1"))

	availability_c, performance_c, quality_c = cap(availability), cap(performance), cap(quality)
	index = None
	if None not in (availability_c, performance_c, quality_c):
		index = (availability_c * performance_c * quality_c).quantize(Decimal("0.0001"), rounding=ROUND_HALF_UP)
	return {
		"availability": None if availability_c is None else availability_c.quantize(Decimal("0.0001"), rounding=ROUND_HALF_UP),
		"performance": None if performance_c is None else performance_c.quantize(Decimal("0.0001"), rounding=ROUND_HALF_UP),
		"quality": None if quality_c is None else quality_c.quantize(Decimal("0.0001"), rounding=ROUND_HALF_UP),
		"oee": index,
	}


def valued_order_cost(method: str, standard_total, actual_total, produced_qty, average_unit) -> Decimal:
	"""بهای گزارشی سفارش. این عدد سند دفتر کل را عوض نمی‌کند."""
	if method not in COSTING_METHODS:
		raise ValueError("INVALID_COSTING_METHOD")
	if method == "standard":
		return money(standard_total)
	if method == "weighted_average" and average_unit is not None and D(produced_qty) > 0:
		return money(D(average_unit) * D(produced_qty))
	return money(actual_total)
