"""Run distribution publication Alembic revisions on local ephemeral SQL Server.

Opt-in only; refuses remote hosts and all databases other than tempdb.
The test creates and removes minimal parent tables in the disposable CI DB.
"""

from __future__ import annotations

import os
from importlib.util import module_from_spec, spec_from_file_location
from pathlib import Path

import pytest
import sqlalchemy as sa
from alembic.migration import MigrationContext
from alembic.operations import Operations
from sqlalchemy.engine import make_url

_DSN = os.getenv("DISTRIBUTION_MSSQL_TEST_DSN", "")
_ENABLED = os.getenv("DISTRIBUTION_MSSQL_TEST_ENABLE") == "1"

pytestmark = pytest.mark.skipif(
    not (_DSN and _ENABLED),
    reason="Requires isolated SQL Server 2022 CI container",
)


def _load_migration(filename: str):
    path = Path(__file__).resolve().parents[1] / "migrations" / "versions" / filename
    spec = spec_from_file_location(filename.replace(".", "_"), path)
    assert spec is not None and spec.loader is not None
    module = module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_mssql_daily_plan_schema_snapshot_and_fk_behavior(monkeypatch):
    url = make_url(_DSN)
    assert url.get_backend_name() == "mssql"
    assert url.host in ("localhost", "127.0.0.1")
    assert url.database == "tempdb" and url.port == 1433

    initial = _load_migration("20261121_000001_distribution_daily_plan_locks.py")
    snapshot = _load_migration("20261121_000002_distribution_daily_plan_snapshot.py")
    engine = sa.create_engine(url, pool_pre_ping=True)
    try:
        with engine.begin() as conn:
            assert conn.execute(sa.text("SELECT DB_NAME()")).scalar_one() == "tempdb"
            assert not sa.inspect(conn).has_table("distribution_daily_plan_locks")
            # Mirror the production users -> businesses ownership cascade,
            # which creates a third path to the plan-lock table in SQL Server.
            conn.exec_driver_sql("CREATE TABLE users (id int NOT NULL PRIMARY KEY)")
            conn.exec_driver_sql(
                "CREATE TABLE businesses (id int NOT NULL PRIMARY KEY, "
                "owner_id int NOT NULL REFERENCES users(id) ON DELETE CASCADE)"
            )
            try:
                operation = Operations(MigrationContext.configure(conn))
                monkeypatch.setattr(initial, "op", operation)
                monkeypatch.setattr(snapshot, "op", operation)
                initial.upgrade()
                snapshot.upgrade()

                inspector = sa.inspect(conn)
                table = "distribution_daily_plan_locks"
                assert inspector.has_table(table)
                names = {column["name"] for column in inspector.get_columns(table)}
                assert {"business_id", "user_id", "plan_date", "is_locked", "plan_snapshot"}.issubset(names)

                conn.execute(sa.text("INSERT INTO users (id) VALUES (20), (21), (88), (99)"))
                conn.execute(sa.text(
                    "INSERT INTO businesses (id, owner_id) VALUES (10, 88), (11, 88)"
                ))
                conn.execute(sa.text(
                    "INSERT INTO distribution_daily_plan_locks "
                    "(business_id, user_id, plan_date, published_by_user_id, published_at, created_at, updated_at) "
                    "VALUES (10, 20, '2026-11-22', 99, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP), "
                    "(11, 21, '2026-11-22', 99, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)"
                ))
                assert conn.execute(sa.text(
                    "SELECT CAST(is_locked AS int) FROM distribution_daily_plan_locks WHERE business_id = 10"
                )).scalar_one() == 0

                conn.execute(sa.text(
                    "UPDATE distribution_daily_plan_locks SET plan_snapshot = :snapshot WHERE business_id = 10"
                ), {"snapshot": '{"plan_date":"2026-11-22","items":[{"stop_id":7}]}'})
                assert conn.execute(sa.text(
                    "SELECT JSON_VALUE(plan_snapshot, '$.items[0].stop_id') "
                    "FROM distribution_daily_plan_locks WHERE business_id = 10"
                )).scalar_one() == "7"

                # SQL Server intentionally uses NO ACTION on visitor and
                # publisher references. Clear optional publisher references
                # explicitly before deleting their User; PostgreSQL uses
                # ON DELETE SET NULL instead.
                fks = {
                    tuple(fk["constrained_columns"]): fk
                    for fk in sa.inspect(conn).get_foreign_keys(table)
                }
                assert fks[("business_id",)]["options"].get("ondelete") == "CASCADE"
                assert fks[("user_id",)]["options"].get("ondelete") is None
                assert fks[("published_by_user_id",)]["options"].get("ondelete") is None
                conn.execute(sa.text(
                    "UPDATE distribution_daily_plan_locks SET published_by_user_id = NULL "
                    "WHERE published_by_user_id = 99"
                ))
                conn.execute(sa.text("DELETE FROM users WHERE id = 99"))
                assert conn.execute(sa.text(
                    "SELECT COUNT(*) FROM distribution_daily_plan_locks WHERE published_by_user_id IS NULL"
                )).scalar_one() == 2
                conn.execute(sa.text("DELETE FROM businesses WHERE id = 10"))
                assert conn.execute(sa.text(
                    "SELECT business_id FROM distribution_daily_plan_locks"
                )).scalars().all() == [11]

                snapshot.downgrade()
                assert "plan_snapshot" not in {
                    column["name"] for column in sa.inspect(conn).get_columns(table)
                }
                initial.downgrade()
                assert not sa.inspect(conn).has_table(table)
            finally:
                # No schema changes outlive a failed test in the temporary DB.
                conn.exec_driver_sql(
                    "IF OBJECT_ID('distribution_daily_plan_locks', 'U') IS NOT NULL "
                    "DROP TABLE distribution_daily_plan_locks"
                )
                conn.exec_driver_sql(
                    "IF OBJECT_ID('businesses', 'U') IS NOT NULL DROP TABLE businesses"
                )
                conn.exec_driver_sql(
                    "IF OBJECT_ID('users', 'U') IS NOT NULL DROP TABLE users"
                )
    finally:
        engine.dispose()
