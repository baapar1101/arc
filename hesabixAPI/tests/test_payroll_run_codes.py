"""تست شماره‌گذاری سند حقوق، برخورد یکتایی، و ایجاد تنظیمات."""

from __future__ import annotations

from datetime import datetime
from decimal import Decimal
from types import SimpleNamespace
from unittest.mock import MagicMock

import pytest
from sqlalchemy.exc import IntegrityError

from adapters.db.models.business import Business
from adapters.db.models.payroll import PayrollSettings
from app.core.responses import ApiError
from app.services import payroll_service as svc


def test_next_sequential_skips_deleted_leading_codes():
	# کسب‌وکار ۶۴۳۴: فقط PAY-2026-0002 مانده؛ COUNT+1 به 0002 برمی‌گشت.
	assert (
		svc._next_sequential_run_code(["PAY-2026-0002"], "PAY", 2026)
		== "PAY-2026-0003"
	)


def test_next_sequential_skips_gap_after_deletes():
	# کسب‌وکار ۷۱۵۱: 0002 و 0003 مانده؛ COUNT+1 به 0003 برمی‌گشت.
	assert (
		svc._next_sequential_run_code(["PAY-2026-0003", "PAY-2026-0002"], "PAY", 2026)
		== "PAY-2026-0004"
	)


def test_next_sequential_first_code():
	assert svc._next_sequential_run_code([], "PAY", 2026) == "PAY-2026-0001"


def test_next_sequential_ignores_other_year_and_custom_codes():
	codes = ["PAY-2025-0099", "CUSTOM", "PAY-2026-0007", "PAY-2026-0007-copy"]
	assert svc._next_sequential_run_code(codes, "PAY", 2026) == "PAY-2026-0008"


def test_generate_run_code_locks_and_uses_max_not_count(monkeypatch):
	lock_keys: list[str] = []
	monkeypatch.setattr(svc, "acquire_transaction_lock", lambda _db, key: lock_keys.append(key))
	monkeypatch.setattr(svc, "datetime", SimpleNamespace(utcnow=lambda: datetime(2026, 11, 12)))
	db = MagicMock()
	db.query.return_value.filter.return_value.all.return_value = [
		("PAY-2026-0002",),
		("PAY-2026-0003",),
	]
	settings = SimpleNamespace(document_code_prefix="PAY", document_code_format="sequential")
	assert svc._generate_run_code(db, 7151, settings) == "PAY-2026-0004"
	assert lock_keys == ["payroll:run-code:7151"]


def _nested_session(flush_side_effect):
	db = MagicMock()
	nested = MagicMock()
	nested.__enter__.return_value = nested
	nested.__exit__.return_value = False
	db.begin_nested.return_value = nested
	db.flush.side_effect = flush_side_effect
	return db


def test_flush_explicit_duplicate_code_is_conflict():
	db = _nested_session(
		IntegrityError(
			"INSERT",
			{},
			Exception('duplicate key value violates unique constraint "uq_payroll_runs_biz_code"'),
		)
	)
	with pytest.raises(ApiError) as caught:
		svc._flush_new_payroll_run(
			db,
			1,
			SimpleNamespace(),
			lambda code: SimpleNamespace(code=code),
			explicit_code="PAY-2026-0003",
		)
	assert caught.value.code == "DUPLICATE_CODE"
	assert caught.value.status_code == 409


def test_flush_retries_generated_code_after_collision(monkeypatch):
	codes = iter(["PAY-2026-0003", "PAY-2026-0004"])
	monkeypatch.setattr(svc, "_generate_run_code", lambda *_args, **_kwargs: next(codes))
	db = _nested_session(
		[
			IntegrityError(
				"INSERT",
				{},
				Exception('duplicate key value violates unique constraint "uq_payroll_runs_biz_code"'),
			),
			None,
		]
	)
	run = svc._flush_new_payroll_run(
		db,
		7151,
		SimpleNamespace(),
		lambda code: SimpleNamespace(code=code),
	)
	assert run.code == "PAY-2026-0004"


def test_get_or_create_settings_recovers_from_unique_violation(monkeypatch):
	monkeypatch.setattr(svc, "acquire_transaction_lock", lambda *_args, **_kwargs: None)
	seeded: list[int] = []
	monkeypatch.setattr(svc, "_seed_defaults", lambda _db, business_id: seeded.append(business_id))

	existing = SimpleNamespace(id=51, business_id=7151)
	db = MagicMock()
	nested = MagicMock()
	nested.__enter__.return_value = nested
	nested.__exit__.return_value = False
	db.begin_nested.return_value = nested
	db.flush.side_effect = IntegrityError(
		"INSERT",
		{},
		Exception('duplicate key value violates unique constraint "uq_payroll_settings_business"'),
	)

	settings_lookups = [None, None, existing]

	def query_side_effect(model):
		q = MagicMock()
		if model is PayrollSettings:
			q.filter.return_value.first.side_effect = settings_lookups
		elif model is Business:
			q.filter.return_value.first.return_value = SimpleNamespace(
				id=7151, default_currency_id=1
			)
		return q

	db.query.side_effect = query_side_effect
	row = svc._get_or_create_settings(db, 7151)
	assert row is existing
	assert seeded == [7151]


def test_run_has_accounting_amounts():
	empty = SimpleNamespace(
		gross_total=Decimal("0"),
		deduction_total=Decimal("0"),
		employer_cost_total=Decimal("0"),
		net_total=Decimal("0"),
	)
	balanced_zero_net = SimpleNamespace(
		gross_total=Decimal("1000"),
		deduction_total=Decimal("1000"),
		employer_cost_total=Decimal("0"),
		net_total=Decimal("0"),
	)
	assert svc._run_has_accounting_amounts(empty) is False
	assert svc._run_has_accounting_amounts(balanced_zero_net) is True


def test_unique_violation_helper():
	exc = IntegrityError(
		"INSERT",
		{},
		Exception('duplicate key value violates unique constraint "uq_payroll_runs_biz_code"'),
	)
	assert svc._is_payroll_unique_violation(exc, "uq_payroll_runs_biz_code") is True
	assert svc._is_payroll_unique_violation(exc, "uq_payroll_settings_business") is False
