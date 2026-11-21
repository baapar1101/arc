"""Integration checks for the isolated PostgreSQL distribution publication migration.

Only enabled in the dedicated GitHub Actions PostgreSQL job; never touches a
production database. The ephemeral DB contains only minimal FK parent tables.
"""

from __future__ import annotations

import os
from importlib.util import module_from_spec, spec_from_file_location
from pathlib import Path

import pytest
import sqlalchemy as sa
from alembic.migration import MigrationContext
from alembic.operations import Operations
from sqlalchemy.exc import IntegrityError


@pytest.mark.skipif(
    not os.environ.get("DISTRIBUTION_PG_TEST_DSN"),
    reason="Requires the dedicated ephemeral PostgreSQL GitHub Actions service",
)
def test_postgres_daily_plan_publication_migration(monkeypatch):
    dsn = os.environ["DISTRIBUTION_PG_TEST_DSN"]
    assert "postgresql" in dsn.lower()

    migration_path = (
        Path(__file__).resolve().parents[1]
        / "migrations"
        / "versions"
        / "20261121_000001_distribution_daily_plan_locks.py"
    )
    spec = spec_from_file_location("dist_plan_postgres_migration", migration_path)
    assert spec is not None and spec.loader is not None
    migration = module_from_spec(spec)
    spec.loader.exec_module(migration)

    engine = sa.create_engine(dsn)
    try:
        with engine.begin() as conn:
            # Minimal reference tables needed for this additive migration.
            # A dedicated ephemeral Postgres database is required.
            conn.exec_driver_sql("CREATE TABLE businesses (id integer PRIMARY KEY)")
            conn.exec_driver_sql("CREATE TABLE users (id integer PRIMARY KEY)")
            conn.execute(sa.text("INSERT INTO businesses (id) VALUES (10), (11)"))
            conn.execute(sa.text("INSERT INTO users (id) VALUES (20), (21), (99)"))

            monkeypatch.setattr(
                migration,
                "op",
                Operations(MigrationContext.configure(conn)),
            )
            migration.upgrade()

            inspector = sa.inspect(conn)
            table = "distribution_daily_plan_locks"
            assert inspector.has_table(table)
            cols = {c["name"]: c for c in inspector.get_columns(table)}
            assert {"business_id", "user_id", "plan_date", "is_locked", "published_at"}.issubset(cols)
            assert cols["is_locked"]["nullable"] is False
            assert str(cols["is_locked"]["default"]).lower() == "false"
            unique_sets = {
                tuple(sorted(c["column_names"]))
                for c in inspector.get_unique_constraints(table)
            }
            assert ("business_id", "plan_date", "user_id") in unique_sets
            fk = inspector.get_foreign_keys(table)
            assert {
                (item["referred_table"], tuple(item["constrained_columns"]))
                for item in fk
            } >= {
                ("businesses", ("business_id",)),
                ("users", ("user_id",)),
            }

            conn.execute(
                sa.text(
                    "INSERT INTO distribution_daily_plan_locks "
                    "(business_id, user_id, plan_date, published_by_user_id, published_at, created_at, updated_at) "
                    "VALUES (10, 20, '2026-11-21', 99, now(), now(), now()), "
                    "(11, 20, '2026-11-21', 99, now(), now(), now())"
                )
            )
            unlocked = conn.execute(
                sa.text("SELECT is_locked FROM distribution_daily_plan_locks WHERE business_id = 10")
            ).scalar_one()
            assert unlocked is False

            # The same visitor/date can exist in another business, but not twice
            # in one business. A savepoint keeps the outer migration transaction live.
            with pytest.raises(IntegrityError):
                with conn.begin_nested():
                    conn.execute(
                        sa.text(
                            "INSERT INTO distribution_daily_plan_locks "
                            "(business_id, user_id, plan_date, published_at, created_at, updated_at) "
                            "VALUES (10, 20, '2026-11-21', now(), now(), now())"
                        )
                    )

            # The publisher is optional; deleting an approving user clears it,
            # while deleting the business removes only that business' records.
            conn.execute(sa.text("DELETE FROM users WHERE id = 99"))
            assert conn.execute(
                sa.text("SELECT count(*) FROM distribution_daily_plan_locks WHERE published_by_user_id IS NULL")
            ).scalar_one() == 2
            conn.execute(sa.text("DELETE FROM businesses WHERE id = 10"))
            assert conn.execute(
                sa.text("SELECT business_id FROM distribution_daily_plan_locks")
            ).scalars().all() == [11]

            migration.downgrade()
            assert not sa.inspect(conn).has_table(table)
    finally:
        engine.dispose()
