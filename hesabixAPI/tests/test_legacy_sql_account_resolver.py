"""Tests for legacy SQL account resolution."""

from __future__ import annotations

from app.services.legacy_sql.mappers import is_valid_mapped_id


def test_is_valid_mapped_id_accepts_dry_run_placeholders():
	assert is_valid_mapped_id(-5, dry_run=True)
	assert not is_valid_mapped_id(-5, dry_run=False)
	assert is_valid_mapped_id(10, dry_run=False)


def test_resolve_legacy_expense_account_by_name():
	from adapters.db.models.account import Account
	from adapters.db.session import get_db_session
	from app.services.legacy_sql.legacy_account_resolver import (
		LegacySqlAccountResolver,
		build_ref_id_index,
	)
	from app.services.legacy_sql.sql_dump_reader import load_legacy_sql_dump

	data = load_legacy_sql_dump("/opt/hesabix/app/oldsimpleDatabase.sql")
	ref_index = build_ref_id_index(data.rows("hesabdari_table"))
	with get_db_session() as db:
		resolver = LegacySqlAccountResolver(db, business_id=1, ref_index=ref_index)
		account_id = resolver.resolve_account_id_for_ref(
			98,
			is_income=False,
			fallback_expense=True,
		)
		assert account_id is not None
		account = db.get(Account, account_id)
		assert account is not None
		assert account.code == "70401"
		assert "خدمات" in account.name
