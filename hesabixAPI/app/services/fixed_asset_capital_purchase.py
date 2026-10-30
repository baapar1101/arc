"""تفکیک سطر سرمایه‌ای فاکتور خرید از موجودی کالا.

قفل حسابداری:
- سطر سرمایه‌ای موجودی ۱۰۱۰۲ / GRNI / کاردکس را بدهکار نمی‌کند.
- بهای دارایی = فی × تعداد − تخفیف سطر (استاندارد ۱۱؛ مالیات ورودی جزء بها نیست).
- تخفیف سطر سرمایه‌ای به ۴۰۰۰۳ نمی‌رود چون از قبل از بهای ۱۰۷ کم شده است.
- نوع کالا عوض نمی‌شود؛ پرچم فقط مقصد دفتر کل را عوض می‌کند.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from decimal import Decimal, ROUND_HALF_UP
from typing import Any, Dict, Iterable, List, Mapping, Optional, Tuple

Q2 = Decimal("0.01")
INVOICE_PURCHASE_TYPE = "invoice_purchase"
INVOICE_PURCHASE_RETURN_TYPE = "invoice_purchase_return"

EXTRA_FLAG = "fixed_asset"
EXTRA_CLASS_ID = "fixed_asset_class_id"
EXTRA_LOCATION_ID = "fixed_asset_location_id"
EXTRA_CUSTODIAN_ID = "fixed_asset_custodian_person_id"
EXTRA_SALVAGE = "fixed_asset_salvage"
EXTRA_LIFE = "fixed_asset_useful_life_months"
EXTRA_RATE = "fixed_asset_declining_annual_rate"
EXTRA_ASSET_ID = "fixed_asset_id"
EXTRA_COMMISSION_DATE = "fixed_asset_commission_date"
EXTRA_NAME = "fixed_asset_name"


def q2(value: Any) -> Decimal:
	return Decimal(str(value or 0)).quantize(Q2, rounding=ROUND_HALF_UP)


def is_capital_invoice_line(extra: Any) -> bool:
	info = extra if isinstance(extra, Mapping) else {}
	flag = info.get(EXTRA_FLAG)
	if flag is True or flag == 1:
		return True
	if isinstance(flag, str) and flag.strip().lower() in {"1", "true", "yes"}:
		return True
	cap = info.get("capitalization")
	if isinstance(cap, Mapping) and cap.get("enabled") in (True, 1, "true", "1", "yes"):
		return True
	return False


def invoice_line_skips_warehouse(extra: Any) -> bool:
	return is_capital_invoice_line(extra)


def invoice_line_skips_inventory_kardex(extra: Any) -> bool:
	return is_capital_invoice_line(extra)


def _optional_positive_int(value: Any) -> Optional[int]:
	if value is None or value == "":
		return None
	try:
		parsed = int(value)
	except (TypeError, ValueError):
		return None
	return parsed if parsed > 0 else None


def capital_class_id(extra: Any) -> Optional[int]:
	info = extra if isinstance(extra, Mapping) else {}
	raw = info.get(EXTRA_CLASS_ID)
	if raw is None and isinstance(info.get("capitalization"), Mapping):
		raw = info["capitalization"].get("class_id")
	return _optional_positive_int(raw)


def capital_location_id(extra: Any) -> Optional[int]:
	info = extra if isinstance(extra, Mapping) else {}
	raw = info.get(EXTRA_LOCATION_ID)
	if raw is None and isinstance(info.get("capitalization"), Mapping):
		raw = info["capitalization"].get("location_id")
	return _optional_positive_int(raw)


def capital_custodian_id(extra: Any) -> Optional[int]:
	info = extra if isinstance(extra, Mapping) else {}
	raw = info.get(EXTRA_CUSTODIAN_ID)
	if raw is None and isinstance(info.get("capitalization"), Mapping):
		raw = info["capitalization"].get("custodian_person_id")
	return _optional_positive_int(raw)


def capital_optional_decimal(extra: Any, key: str, nested_key: str) -> Optional[Decimal]:
	info = extra if isinstance(extra, Mapping) else {}
	raw = info.get(key)
	if raw is None and isinstance(info.get("capitalization"), Mapping):
		raw = info["capitalization"].get(nested_key)
	if raw is None or raw == "":
		return None
	return q2(raw)


def capital_optional_int(extra: Any, key: str, nested_key: str) -> Optional[int]:
	info = extra if isinstance(extra, Mapping) else {}
	raw = info.get(key)
	if raw is None and isinstance(info.get("capitalization"), Mapping):
		raw = info["capitalization"].get(nested_key)
	return _optional_positive_int(raw)


def capital_asset_name(extra: Any, fallback: str) -> str:
	info = extra if isinstance(extra, Mapping) else {}
	raw = info.get(EXTRA_NAME)
	if raw is None and isinstance(info.get("capitalization"), Mapping):
		raw = info["capitalization"].get("name")
	name = str(raw or "").strip()
	return name or fallback


def line_purchase_amounts(line: Mapping[str, Any]) -> Tuple[Decimal, Decimal, Decimal, Decimal]:
	"""gross, discount, net_after_discount, tax — هم‌خوان با جمع فاکتور."""
	info = line.get("extra_info") or {}
	if not isinstance(info, Mapping):
		info = {}
	qty = Decimal(str(line.get("quantity", 0) or 0))
	unit_price = Decimal(str(info.get("unit_price", 0) or 0))
	line_discount = Decimal(str(info.get("line_discount", 0) or 0))
	tax_amount = Decimal(str(info.get("tax_amount", 0) or 0))
	gross = q2(qty * unit_price)
	discount = q2(line_discount)
	if discount > gross:
		discount = gross
	net = q2(gross - discount)
	tax = q2(tax_amount)
	return gross, discount, net, tax


@dataclass
class CapitalLineSplit:
	class_id: int
	gross: Decimal
	discount: Decimal
	net: Decimal
	tax: Decimal
	line_index: int


@dataclass
class PurchaseDebitSplit:
	inventory_gross: Decimal = Decimal("0.00")
	inventory_discount: Decimal = Decimal("0.00")
	capital_gross: Decimal = Decimal("0.00")
	capital_discount: Decimal = Decimal("0.00")
	capital_net: Decimal = Decimal("0.00")
	capital_tax: Decimal = Decimal("0.00")
	capital_net_by_class: Dict[int, Decimal] = field(default_factory=dict)
	capital_lines: List[CapitalLineSplit] = field(default_factory=list)

	@property
	def purchase_discount_credit(self) -> Decimal:
		return self.inventory_discount


def split_purchase_debit_amounts(lines: Iterable[Mapping[str, Any]]) -> PurchaseDebitSplit:
	out = PurchaseDebitSplit()
	for idx, line in enumerate(lines):
		info = line.get("extra_info") or {}
		gross, discount, net, tax = line_purchase_amounts(line)
		if is_capital_invoice_line(info):
			class_id = capital_class_id(info) or 0
			out.capital_gross = q2(out.capital_gross + gross)
			out.capital_discount = q2(out.capital_discount + discount)
			out.capital_net = q2(out.capital_net + net)
			out.capital_tax = q2(out.capital_tax + tax)
			out.capital_net_by_class[class_id] = q2(out.capital_net_by_class.get(class_id, Decimal("0")) + net)
			out.capital_lines.append(
				CapitalLineSplit(
					class_id=class_id,
					gross=gross,
					discount=discount,
					net=net,
					tax=tax,
					line_index=idx,
				)
			)
			continue
		out.inventory_gross = q2(out.inventory_gross + gross)
		out.inventory_discount = q2(out.inventory_discount + discount)
	return out


def purchase_gl_balances(
	split: PurchaseDebitSplit,
	*,
	tax: Decimal,
	payable: Decimal,
) -> Tuple[Decimal, Decimal]:
	"""بدهکار/بستانکار سمت خرید پس از تفکیک سرمایه‌ای. برای تست توازن."""
	debits = q2(split.inventory_gross + split.capital_net + tax)
	credits = q2(split.purchase_discount_credit + payable)
	return debits, credits
