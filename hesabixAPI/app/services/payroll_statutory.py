"""
قوانین بیمه و مالیات حقوق (فاز ۴).

تنظیمات در payroll_settings.extra_settings.statutory_rules ذخیره می‌شود.
"""
from __future__ import annotations

from decimal import Decimal
from typing import Any, Dict, List, Optional, Tuple

from adapters.db.models.payroll import PayrollItemDefinition, PayrollSettings

DEFAULT_STATUTORY_RULES: Dict[str, Any] = {
	"enabled": False,
	"insurance": {
		"employee_rate_percent": 7,
		"employer_rate_percent": 20,
		"unemployment_employer_rate_percent": 3,
		"ceiling_amount": None,
	},
	"tax": {
		"mode": "flat_percent",
		"flat_rate_percent": 10,
		"exemption_amount": 0,
		"brackets": [
			{"up_to": 50000000, "rate_percent": 0},
			{"up_to": 100000000, "rate_percent": 10},
			{"up_to": 200000000, "rate_percent": 15},
			{"up_to": None, "rate_percent": 20},
		],
	},
}

_STATUTORY_ITEM_CODES = frozenset({"insurance_employee", "insurance_employer", "tax"})


def get_statutory_rules(settings: PayrollSettings) -> Dict[str, Any]:
	extra = settings.extra_settings if isinstance(settings.extra_settings, dict) else {}
	raw = extra.get("statutory_rules") if isinstance(extra.get("statutory_rules"), dict) else {}
	rules = {**DEFAULT_STATUTORY_RULES, **raw}
	ins = {**DEFAULT_STATUTORY_RULES["insurance"], **(raw.get("insurance") or {})}
	tax = {**DEFAULT_STATUTORY_RULES["tax"], **(raw.get("tax") or {})}
	rules["insurance"] = ins
	rules["tax"] = tax
	return rules


def _quantize(amount: Decimal, decimals: int) -> Decimal:
	if decimals <= 0:
		return amount.quantize(Decimal("1"))
	step = Decimal(10) ** (-int(decimals))
	return amount.quantize(step)


def _insurable_base(
	items: List[Tuple[PayrollItemDefinition, Decimal, bool]],
) -> Decimal:
	total = Decimal("0")
	for item_def, amount, _ in items:
		if item_def.item_kind == "earning" and item_def.affects_insurance:
			total += amount
	return total


def _taxable_base(
	items: List[Tuple[PayrollItemDefinition, Decimal, bool]],
) -> Decimal:
	total = Decimal("0")
	for item_def, amount, _ in items:
		if item_def.item_kind == "earning" and (item_def.is_taxable or item_def.affects_taxable):
			total += amount
	return total


def _apply_ceiling(base: Decimal, ceiling: Any) -> Decimal:
	if ceiling is None or ceiling == "":
		return base
	try:
		cap = Decimal(str(ceiling))
	except Exception:
		return base
	return min(base, cap) if cap > 0 else base


def compute_employee_insurance(base: Decimal, rules: Dict[str, Any]) -> Decimal:
	ins = rules.get("insurance") or {}
	rate = Decimal(str(ins.get("employee_rate_percent") or 0))
	return base * rate / Decimal("100")


def compute_employer_insurance(base: Decimal, rules: Dict[str, Any]) -> Decimal:
	ins = rules.get("insurance") or {}
	er = Decimal(str(ins.get("employer_rate_percent") or 0))
	ur = Decimal(str(ins.get("unemployment_employer_rate_percent") or 0))
	return base * (er + ur) / Decimal("100")


def compute_income_tax(taxable_base: Decimal, rules: Dict[str, Any]) -> Decimal:
	tax_rules = rules.get("tax") or {}
	exemption = Decimal(str(tax_rules.get("exemption_amount") or 0))
	base = max(Decimal("0"), taxable_base - exemption)
	if base <= 0:
		return Decimal("0")

	mode = str(tax_rules.get("mode") or "flat_percent")
	if mode == "flat_percent":
		rate = Decimal(str(tax_rules.get("flat_rate_percent") or 0))
		return base * rate / Decimal("100")

	brackets = tax_rules.get("brackets") or DEFAULT_STATUTORY_RULES["tax"]["brackets"]
	remaining = base
	tax_total = Decimal("0")
	prev_limit = Decimal("0")
	for bracket in brackets:
		up_to_raw = bracket.get("up_to")
		rate = Decimal(str(bracket.get("rate_percent") or 0))
		if up_to_raw is None:
			tax_total += remaining * rate / Decimal("100")
			break
		limit = Decimal(str(up_to_raw))
		chunk = min(remaining, limit - prev_limit)
		if chunk <= 0:
			prev_limit = limit
			continue
		tax_total += chunk * rate / Decimal("100")
		remaining -= chunk
		prev_limit = limit
		if remaining <= 0:
			break
	return tax_total


def apply_statutory_rules(
	pending: List[Tuple[PayrollItemDefinition, Decimal, bool]],
	explicit_by_id: Dict[int, Any],
	settings: PayrollSettings,
) -> List[Tuple[PayrollItemDefinition, Decimal, bool]]:
	rules = get_statutory_rules(settings)
	if not rules.get("enabled"):
		return pending

	rt = int(settings.round_amounts_to or 0)
	ins_base = _apply_ceiling(
		_insurable_base(pending),
		(rules.get("insurance") or {}).get("ceiling_amount"),
	)
	tax_base = _taxable_base(pending)

	statutory_amounts = {
		"insurance_employee": compute_employee_insurance(ins_base, rules),
		"insurance_employer": compute_employer_insurance(ins_base, rules),
		"tax": compute_income_tax(tax_base, rules),
	}

	out: List[Tuple[PayrollItemDefinition, Decimal, bool]] = []
	for item_def, amount, computed in pending:
		if item_def.id in explicit_by_id and explicit_by_id[item_def.id] not in (None, ""):
			out.append((item_def, amount, computed))
			continue
		if item_def.code in _STATUTORY_ITEM_CODES or item_def.calculation_type == "statutory":
			override = statutory_amounts.get(item_def.code)
			if override is not None:
				out.append((item_def, _quantize(override, rt), True))
				continue
		out.append((item_def, amount, computed))
	return out
