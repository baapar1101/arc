"""تست قوانین بیمه و مالیات حقوق."""

from __future__ import annotations

from decimal import Decimal
from types import SimpleNamespace

from app.services.payroll_statutory import (
	DEFAULT_STATUTORY_RULES,
	apply_statutory_rules,
	compute_employee_insurance,
	compute_income_tax,
	get_statutory_rules,
)


def _item(code: str, kind: str, *, insurable: bool = False, taxable: bool = False, calc: str = "manual"):
	return SimpleNamespace(
		id=hash(code) % 10000,
		code=code,
		item_kind=kind,
		affects_insurance=insurable,
		affects_taxable=taxable,
		is_taxable=taxable,
		calculation_type=calc,
	)


def _settings(enabled: bool = True, round_to: int = 0):
	return SimpleNamespace(
		round_amounts_to=round_to,
		extra_settings={
			"statutory_rules": {
				"enabled": enabled,
				"insurance": {"employee_rate_percent": 7, "employer_rate_percent": 20, "unemployment_employer_rate_percent": 3},
				"tax": {"mode": "flat_percent", "flat_rate_percent": 10, "exemption_amount": 0},
			}
		},
	)


def test_compute_employee_insurance():
	base = Decimal("10000000")
	amt = compute_employee_insurance(base, DEFAULT_STATUTORY_RULES)
	assert amt == Decimal("700000")


def test_compute_income_tax_flat():
	base = Decimal("10000000")
	amt = compute_income_tax(base, DEFAULT_STATUTORY_RULES)
	assert amt == Decimal("1000000")


def test_apply_statutory_rules_disabled():
	earning = _item("base_salary", "earning", insurable=True, taxable=True)
	tax_item = _item("tax", "deduction", calc="statutory")
	pending = [(earning, Decimal("10000000"), True), (tax_item, Decimal("0"), False)]
	out = apply_statutory_rules(pending, {}, _settings(enabled=False))
	assert out[1][1] == Decimal("0")


def test_apply_statutory_rules_enabled():
	earning = _item("base_salary", "earning", insurable=True, taxable=True)
	ins_emp = _item("insurance_employee", "deduction", calc="statutory")
	tax_item = _item("tax", "deduction", calc="statutory")
	pending = [
		(earning, Decimal("10000000"), True),
		(ins_emp, Decimal("0"), False),
		(tax_item, Decimal("0"), False),
	]
	out = apply_statutory_rules(pending, {}, _settings())
	by_code = {row[0].code: row[1] for row in out}
	assert by_code["insurance_employee"] == Decimal("700000")
	assert by_code["tax"] == Decimal("1000000")


def test_explicit_override_kept():
	earning = _item("base_salary", "earning", insurable=True, taxable=True)
	tax_item = _item("tax", "deduction", calc="statutory")
	pending = [(earning, Decimal("10000000"), True), (tax_item, Decimal("500000"), False)]
	explicit = {tax_item.id: "500000"}
	out = apply_statutory_rules(pending, explicit, _settings())
	assert out[1][1] == Decimal("500000")


def test_get_statutory_rules_merges_defaults():
	row = SimpleNamespace(extra_settings={"statutory_rules": {"enabled": True}})
	rules = get_statutory_rules(row)
	assert rules["enabled"] is True
	assert rules["insurance"]["employee_rate_percent"] == 7
