"""توازن تحصیل دارایی ثابت — بدون دیتابیس."""
from __future__ import annotations

from decimal import Decimal
from typing import List, Tuple


class AcquisitionPlanError(ValueError):
	def __init__(self, code: str, message: str):
		super().__init__(message)
		self.code = code
		self.message = message


def build_acquisition_line_plan(
	*,
	kind: str,
	cost: Decimal,
	vat: Decimal,
	opening_accum: Decimal,
) -> List[Tuple[str, Decimal]]:
	"""برنامه سطرها بدون حساب: (debit|credit, amount)."""
	if cost <= 0:
		raise AcquisitionPlanError("INVALID_COST", "بهای تمام‌شده باید بزرگ‌تر از صفر باشد.")
	if vat < 0 or opening_accum < 0:
		raise AcquisitionPlanError("INVALID_AMOUNT", "مالیات و استهلاک افتتاحیه نمی‌توانند منفی باشند.")
	if opening_accum >= cost:
		raise AcquisitionPlanError("INVALID_OPENING_ACCUM", "استهلاک انباشته افتتاحیه باید از بها کمتر باشد.")
	plan: List[Tuple[str, Decimal]] = [("debit", cost)]
	if vat > 0:
		plan.append(("debit", vat))
	if kind == "opening" and opening_accum > 0:
		plan.append(("credit", opening_accum))
	credit_rest = cost + vat - (opening_accum if kind == "opening" else Decimal("0"))
	if credit_rest <= 0:
		raise AcquisitionPlanError("INVALID_OPENING_ACCUM", "مانده تحصیل برای طرف حساب صفر یا منفی است.")
	plan.append(("credit", credit_rest))
	debits = sum(a for s, a in plan if s == "debit")
	credits = sum(a for s, a in plan if s == "credit")
	if debits != credits:
		raise AcquisitionPlanError("UNBALANCED_ACQUISITION", f"سند تحصیل متوازن نیست ({debits} ≠ {credits}).")
	return plan
