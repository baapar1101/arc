"""Tests for goods expense/income accounting service (unit-style with mocks where needed)."""

from __future__ import annotations

from decimal import Decimal
from types import SimpleNamespace

import pytest

from app.core.responses import ApiError
from app.services import goods_expense_income_service as svc


def test_money_and_qty_helpers():
	assert svc._money("10.456") == Decimal("10.46")
	assert svc._qty("1.2345678") == Decimal("1.234568")


def test_resolve_product_unit_cost():
	p = SimpleNamespace(base_purchase_price=Decimal("1500.5"))
	assert svc.resolve_product_unit_cost(p) == Decimal("1500.500000")
	p2 = SimpleNamespace(base_purchase_price=None)
	assert svc.resolve_product_unit_cost(p2) == Decimal("0")


def test_assert_account_kind_compatible_expense():
	acc = SimpleNamespace(code="70407", name="کسری")
	svc._assert_account_kind_compatible(acc, svc.DOC_KIND_EXPENSE)
	with pytest.raises(ApiError) as ei:
		svc._assert_account_kind_compatible(acc, svc.DOC_KIND_INCOME)
	detail = ei.value.detail
	assert isinstance(detail, dict)
	assert detail.get("error", {}).get("code") == "ACCOUNT_KIND_MISMATCH"


def test_assert_account_kind_compatible_income():
	acc = SimpleNamespace(code="60103", name="اضافه")
	svc._assert_account_kind_compatible(acc, svc.DOC_KIND_INCOME)
	with pytest.raises(ApiError):
		svc._assert_account_kind_compatible(acc, svc.DOC_KIND_EXPENSE)


def test_get_workflow_settings_defaults():
	biz = SimpleNamespace(
		goods_expense_income_workflow_mode=None,
		goods_expense_income_auto_post_in_simple_mode=True,
		goods_expense_income_default_expense_account_code=None,
		goods_expense_income_default_income_account_code=None,
		goods_expense_income_stock_count_mode=None,
		goods_expense_income_allow_manual_unit_cost=False,
		goods_expense_income_require_person=False,
	)
	s = svc.get_workflow_settings(biz)
	assert s["workflow_mode"] == "simple"
	assert s["default_expense_account_code"] == "70407"
	assert s["default_income_account_code"] == "60103"
	assert s["stock_count_mode"] == "goods_docs"


def test_get_workflow_settings_two_step():
	biz = SimpleNamespace(
		goods_expense_income_workflow_mode="two_step",
		goods_expense_income_auto_post_in_simple_mode=False,
		goods_expense_income_default_expense_account_code="70406",
		goods_expense_income_default_income_account_code="60103",
		goods_expense_income_stock_count_mode="ask",
		goods_expense_income_allow_manual_unit_cost=True,
		goods_expense_income_require_person=True,
	)
	s = svc.get_workflow_settings(biz)
	assert s["workflow_mode"] == "two_step"
	assert s["stock_count_mode"] == "ask"
	assert s["default_expense_account_code"] == "70406"
	assert s["require_person"] is True
