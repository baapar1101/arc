"""Regression tests for goods expense/income hardening."""

from __future__ import annotations

from types import SimpleNamespace
from unittest.mock import MagicMock

import pytest

from app.core.responses import ApiError
from app.services import goods_expense_income_service as svc
from app.services import warehouse_service as wh_svc
from app.services.invoice_service import _warehouse_doc_is_cancel_reversal_of_cancelled


def test_voucher_numbering_types_separated_from_gl():
	assert svc.VOUCHER_NUMBERING_BY_KIND[svc.DOC_KIND_EXPENSE] == "goods_expense_voucher"
	assert svc.VOUCHER_NUMBERING_BY_KIND[svc.DOC_KIND_INCOME] == "goods_income_voucher"
	assert svc.VOUCHER_NUMBERING_BY_KIND[svc.DOC_KIND_EXPENSE] != svc.DOC_KIND_EXPENSE


def test_account_kind_allows_cogs_branch_for_expense():
	acc = SimpleNamespace(code="40001", name="بهای تمام شده")
	svc._assert_account_kind_compatible(acc, svc.DOC_KIND_EXPENSE)


def test_invalid_stock_count_mode_falls_back():
	biz = SimpleNamespace(
		goods_expense_income_workflow_mode="simple",
		goods_expense_income_auto_post_in_simple_mode=True,
		goods_expense_income_default_expense_account_code="70407",
		goods_expense_income_default_income_account_code="60103",
		goods_expense_income_stock_count_mode="something_else",
		goods_expense_income_allow_manual_unit_cost=False,
		goods_expense_income_require_person=False,
	)
	s = svc.get_workflow_settings(biz)
	assert s["stock_count_mode"] == "goods_docs"


def test_should_seal_reversal_for_gei_and_manual():
	db = MagicMock()
	gei = SimpleNamespace(source_type="goods_expense_income", source_document_id=99)
	manual = SimpleNamespace(source_type="manual", source_document_id=None)
	assert wh_svc.should_seal_warehouse_cancel_reversal(db, 1, gei) is True
	assert wh_svc.should_seal_warehouse_cancel_reversal(db, 1, manual) is True


def test_should_not_seal_reversal_for_invoice_sourced():
	db = MagicMock()
	inv = SimpleNamespace(source_type="invoice", source_document_id=10)
	assert wh_svc.should_seal_warehouse_cancel_reversal(db, 1, inv) is False


def test_assert_cancel_reversal_postable_blocks_audit_only():
	db = MagicMock()
	wh = SimpleNamespace(
		business_id=1,
		extra_info={
			"cancels_warehouse_document_id": 5,
			"audit_only_reversal": True,
			"stock_already_corrected_by_cancel": True,
		},
	)
	with pytest.raises(ApiError) as ei:
		wh_svc.assert_cancel_reversal_postable(db, wh)
	assert ei.value.detail["error"]["code"] == "CANCEL_REVERSAL_NOT_POSTABLE"


def test_assert_cancel_reversal_postable_blocks_sealed_gei_original():
	db = MagicMock()
	original = SimpleNamespace(
		id=5,
		business_id=1,
		status="cancelled",
		source_type="goods_expense_income",
		source_document_id=None,
	)
	q = MagicMock()
	q.filter.return_value.first.return_value = original
	db.query.return_value = q

	wh = SimpleNamespace(
		business_id=1,
		extra_info={"cancels_warehouse_document_id": 5},
	)
	with pytest.raises(ApiError) as ei:
		wh_svc.assert_cancel_reversal_postable(db, wh)
	assert ei.value.detail["error"]["code"] == "CANCEL_REVERSAL_NOT_POSTABLE"


def test_stock_skips_audit_only_cancel_reversal():
	db = MagicMock()
	wh_doc = SimpleNamespace(
		extra_info={
			"cancels_warehouse_document_id": 9,
			"audit_only_reversal": True,
		}
	)
	assert _warehouse_doc_is_cancel_reversal_of_cancelled(db, 1, wh_doc) is True


def test_stock_skips_cancel_reversal_when_original_cancelled():
	db = MagicMock()
	original = SimpleNamespace(id=9, status="cancelled")
	q = MagicMock()
	q.filter.return_value.first.return_value = original
	db.query.return_value = q
	wh_doc = SimpleNamespace(extra_info={"cancels_warehouse_document_id": 9})
	assert _warehouse_doc_is_cancel_reversal_of_cancelled(db, 1, wh_doc) is True
