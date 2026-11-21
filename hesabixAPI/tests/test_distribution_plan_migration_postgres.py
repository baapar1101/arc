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
    snapshot_path = migration_path.with_name(
        "20261121_000002_distribution_daily_plan_snapshot.py"
    )
    snapshot_spec = spec_from_file_location("dist_plan_snapshot_postgres", snapshot_path)
    assert snapshot_spec is not None and snapshot_spec.loader is not None
    snapshot_migration = module_from_spec(snapshot_spec)
    snapshot_spec.loader.exec_module(snapshot_migration)

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
            monkeypatch.setattr(
                snapshot_migration,
                "op",
                Operations(MigrationContext.configure(conn)),
            )
            snapshot_migration.upgrade()

            inspector = sa.inspect(conn)
            table = "distribution_daily_plan_locks"
            assert inspector.has_table(table)
            cols = {c["name"]: c for c in inspector.get_columns(table)}
            assert {"business_id", "user_id", "plan_date", "is_locked", "published_at"}.issubset(cols)
            assert cols["is_locked"]["nullable"] is False
            assert "plan_snapshot" in cols
            assert cols["plan_snapshot"]["nullable"] is True
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

            snapshot_value = '{"plan_date":"2026-11-21","items":[{"stop_id":7}]}'
            conn.execute(
                sa.text(
                    "UPDATE distribution_daily_plan_locks "
                    "SET plan_snapshot = CAST(:snapshot AS JSON) WHERE business_id = 10"
                ),
                {"snapshot": snapshot_value},
            )
            assert conn.execute(
                sa.text(
                    "SELECT plan_snapshot -> 'items' -> 0 ->> 'stop_id' "
                    "FROM distribution_daily_plan_locks WHERE business_id = 10"
                )
            ).scalar_one() == "7"

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

            snapshot_migration.downgrade()
            assert "plan_snapshot" not in {
                c["name"] for c in sa.inspect(conn).get_columns(table)
            }
            migration.downgrade()
            assert not sa.inspect(conn).has_table(table)
    finally:
        engine.dispose()


@pytest.mark.skipif(
    not os.environ.get("DISTRIBUTION_PG_TEST_DSN"),
    reason="Requires ephemeral PostgreSQL GitHub Actions service",
)
def test_postgres_distribution_mutation_lock_serialization():
    """One business is serialized; other businesses remain independent."""
    from sqlalchemy.orm import Session
    from app.services.distribution_service import _serialize_distribution_plan_mutation

    engine = sa.create_engine(os.environ["DISTRIBUTION_PG_TEST_DSN"])
    try:
        with Session(engine) as owner:
            _serialize_distribution_plan_mutation(owner, 10)
            with engine.connect() as concurrent:
                same_business = concurrent.execute(
                    sa.text("SELECT pg_try_advisory_xact_lock(174021, 10)")
                ).scalar_one()
                other_business = concurrent.execute(
                    sa.text("SELECT pg_try_advisory_xact_lock(174021, 11)")
                ).scalar_one()
                assert same_business is False
                assert other_business is True
                concurrent.rollback()

            owner.commit()  # transaction-scoped lock is now released
            with engine.connect() as next_transaction:
                assert next_transaction.execute(
                    sa.text("SELECT pg_try_advisory_xact_lock(174021, 10)")
                ).scalar_one() is True
                next_transaction.rollback()
    finally:
        engine.dispose()
