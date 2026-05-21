"""تست سیاست امنیت مالی بکاپ کسب‌وکار."""
from __future__ import annotations

import pytest

from app.core.responses import ApiError
from app.services.business_backup_financial_policy import (
    BACKUP_EXCLUDED_TABLES,
    BACKUP_SCHEMA_VERSION,
    build_backup_metadata,
    compute_backup_checksum,
    filter_restorable_table_names,
    is_backup_excluded_table,
    resolve_backup_owner_id,
    validate_backup_owner,
)


def test_wallet_tables_excluded():
    assert is_backup_excluded_table("wallet_accounts")
    assert is_backup_excluded_table("wallet_transactions")
    assert "wallet_accounts" in BACKUP_EXCLUDED_TABLES


def test_ai_voice_interactions_excluded():
    assert is_backup_excluded_table("ai_voice_interactions")
    assert "ai_voice_interactions" in BACKUP_EXCLUDED_TABLES


def test_filter_restorable_tables():
    tables = ["documents", "wallet_accounts", "persons", "user_ai_subscriptions"]
    filtered = filter_restorable_table_names(tables)
    assert "documents" in filtered
    assert "persons" in filtered
    assert "wallet_accounts" not in filtered
    assert "user_ai_subscriptions" not in filtered


def test_build_backup_metadata():
    meta = build_backup_metadata(business_id=10, table_names=["documents", "wallet_accounts"], owner_id=5)
    assert meta["schema_version"] == BACKUP_SCHEMA_VERSION
    assert meta["financial_data_excluded"] is True
    assert meta["owner_id"] == 5
    assert "wallet_accounts" not in meta["tables"]
    assert "documents" in meta["tables"]


def test_compute_backup_checksum_stable():
    data = b"test-backup-content"
    assert compute_backup_checksum(data) == compute_backup_checksum(data)
    assert len(compute_backup_checksum(data)) == 64


def test_resolve_owner_from_metadata():
    assert resolve_backup_owner_id({"owner_id": 7}) == 7


def test_resolve_owner_from_business_row():
    meta = {"business_id": 1}
    row = {"owner_id": 42}
    assert resolve_backup_owner_id(meta, backup_business_row=row) == 42


def test_validate_owner_mismatch():
    with pytest.raises(ApiError) as exc:
        validate_backup_owner({"owner_id": 1}, importing_user_id=2)
    assert exc.value.detail["error"]["code"] == "BACKUP_OWNER_MISMATCH"


def test_validate_legacy_without_owner_rejected():
    with pytest.raises(ApiError) as exc:
        validate_backup_owner({"business_id": 1, "schema_version": "v1"}, importing_user_id=1)
    assert exc.value.detail["error"]["code"] == "BACKUP_LEGACY_NOT_ALLOWED"


def test_validate_legacy_with_business_row_owner_ok():
    validate_backup_owner(
        {"business_id": 1, "schema_version": "v1"},
        importing_user_id=99,
        backup_business_row={"owner_id": 99},
    )
