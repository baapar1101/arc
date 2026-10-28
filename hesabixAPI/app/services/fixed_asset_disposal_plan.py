"""توازن خروج و مخارج بعدی دارایی ثابت — بدون دیتابیس."""
from __future__ import annotations

from decimal import Decimal
from typing import List, Tuple

LinePlan = Tuple[str, Decimal, str]


class DisposalPlanError(ValueError):
	def __init__(self, code: str, message: str):
		super().__init__(message)
		self.code = code
		self.message = message


KIND_SALE = "sale"
KIND_SCRAP = "scrap"
SUPPORTED_DISPOSAL_KINDS = frozenset({KIND_SALE, KIND_SCRAP})

EXP_ROUTINE = "routine"
EXP_MAJOR = "major"
SUPPORTED_EXPENDITURE_KINDS = frozenset({EXP_ROUTINE, EXP_MAJOR})


def _qcheck(amount: Decimal, field: str) -> Decimal:
	if amount < 0:
		raise DisposalPlanError("INVALID_AMOUNT", f"{field} نمی‌تواند منفی باشد.")
	return amount


def build_disposal_line_plan(
	*,
	kind: str,
	cost: Decimal,
	accum: Decimal,
	proceeds: Decimal,
	vat_output: Decimal,
) -> List[LinePlan]:
	"""
	برنامه سطرها: (debit|credit, amount, role).

	نقش‌ها: proceeds, accum, loss, cost, gain, vat_out
	NBV = cost − accum
	سود/زیان = proceeds − NBV  (مالیات خروجی جدا است؛ نقد = proceeds + vat)
	اسقاط: proceeds و vat باید صفر باشند.
	"""
	kind_s = str(kind or "").strip()
	if kind_s not in SUPPORTED_DISPOSAL_KINDS:
		raise DisposalPlanError("INVALID_DISPOSAL_KIND", "نوع خروج باید sale یا scrap باشد.")
	cost = _qcheck(cost, "بها")
	accum = _qcheck(accum, "استهلاک انباشته")
	proceeds = _qcheck(proceeds, "عواید")
	vat_output = _qcheck(vat_output, "مالیات خروجی")
	if cost <= 0:
		raise DisposalPlanError("INVALID_COST", "بهای تمام‌شده باید بزرگ‌تر از صفر باشد.")
	if accum > cost:
		raise DisposalPlanError("INVALID_ACCUM", "استهلاک انباشته نمی‌تواند از بها بیشتر باشد.")
	if kind_s == KIND_SCRAP:
		if proceeds != 0 or vat_output != 0:
			raise DisposalPlanError(
				"SCRAP_MUST_BE_ZERO",
				"اسقاط عواید و مالیات خروجی ندارد؛ برای فروش با مبلغ صفر از نوع sale استفاده کنید.",
			)

	nbv = cost - accum
	gain_loss = proceeds - nbv
	gain = gain_loss if gain_loss > 0 else Decimal("0")
	loss = -gain_loss if gain_loss < 0 else Decimal("0")
	cash = proceeds + vat_output

	plan: List[LinePlan] = []
	if cash > 0:
		plan.append(("debit", cash, "proceeds"))
	if accum > 0:
		plan.append(("debit", accum, "accum"))
	if loss > 0:
		plan.append(("debit", loss, "loss"))
	plan.append(("credit", cost, "cost"))
	if gain > 0:
		plan.append(("credit", gain, "gain"))
	if vat_output > 0:
		plan.append(("credit", vat_output, "vat_out"))

	debits = sum(a for s, a, _r in plan if s == "debit")
	credits = sum(a for s, a, _r in plan if s == "credit")
	if debits != credits:
		raise DisposalPlanError("UNBALANCED_DISPOSAL", f"سند خروج متوازن نیست ({debits} ≠ {credits}).")
	if debits <= 0:
		raise DisposalPlanError("UNBALANCED_DISPOSAL", "سند خروج مبلغ ندارد.")
	return plan


def build_subsequent_expenditure_plan(
	*,
	kind: str,
	amount: Decimal,
	vat: Decimal,
) -> List[LinePlan]:
	"""
	تعمیر جاری: هزینه دوره. تعمیر اساسی: افزایش بها.
	نقش‌ها: expenditure (هزینه یا بها), vat, counterparty
	"""
	kind_s = str(kind or "").strip()
	if kind_s not in SUPPORTED_EXPENDITURE_KINDS:
		raise DisposalPlanError(
			"INVALID_EXPENDITURE_KIND",
			"نوع مخارج بعدی باید routine یا major باشد.",
		)
	amount = _qcheck(amount, "مبلغ مخارج")
	vat = _qcheck(vat, "مالیات ورودی")
	if amount <= 0:
		raise DisposalPlanError("INVALID_AMOUNT", "مبلغ مخارج باید بزرگ‌تر از صفر باشد.")
	role = "cost" if kind_s == EXP_MAJOR else "repair_expense"
	plan: List[LinePlan] = [("debit", amount, role)]
	if vat > 0:
		plan.append(("debit", vat, "vat"))
	plan.append(("credit", amount + vat, "counterparty"))
	debits = sum(a for s, a, _r in plan if s == "debit")
	credits = sum(a for s, a, _r in plan if s == "credit")
	if debits != credits:
		raise DisposalPlanError("UNBALANCED_EXPENDITURE", f"سند مخارج متوازن نیست ({debits} ≠ {credits}).")
	return plan
