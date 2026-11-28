"""Snapshot schema contract using a disposable SQLite database."""
from datetime import date, datetime
from importlib.util import module_from_spec, spec_from_file_location
from pathlib import Path

import pytest
import sqlalchemy as sa
from alembic.migration import MigrationContext
from alembic.operations import Operations
from alembic.script import ScriptDirectory
from sqlalchemy.orm import Session
from sqlalchemy.schema import CreateTable

from adapters.db.models.distribution import DistributionDailyPlanLock

ROOT = Path(__file__).resolve().parents[1]
REVISION = "20261128_000001_plan_snapshot"


def test_snapshot_is_single_migration_head():
    scripts = ScriptDirectory(str(ROOT / "migrations"))
    assert scripts.get_heads() == [REVISION]
    assert scripts.get_revision(REVISION).down_revision == "20261125_000001_safe_upstream"


def test_additive_snapshot_migration_and_safe_downgrade(monkeypatch):
    path = ROOT / "migrations/versions/20261128_000001_distribution_plan_snapshot.py"
    spec = spec_from_file_location("distribution_snapshot_migration", path)
    migration = module_from_spec(spec)
    spec.loader.exec_module(migration)
    engine = sa.create_engine("sqlite+pysqlite:///:memory:")
    with engine.begin() as conn:
        conn.execute(sa.text("CREATE TABLE distribution_daily_plan_locks (id INTEGER PRIMARY KEY, is_locked BOOLEAN NOT NULL)"))
        conn.execute(sa.text("INSERT INTO distribution_daily_plan_locks VALUES (1, 1)"))
        monkeypatch.setattr(migration, "op", Operations(MigrationContext.configure(conn)))
        migration.upgrade()
        assert conn.execute(sa.text("SELECT is_locked, plan_snapshot FROM distribution_daily_plan_locks")).one() == (1, None)
        conn.execute(sa.text("UPDATE distribution_daily_plan_locks SET plan_snapshot = :value"), {"value": '{"items":[]}'})
        with pytest.raises(RuntimeError, match="stored distribution plan snapshots exist"):
            migration.downgrade()
        assert "plan_snapshot" in {c["name"] for c in sa.inspect(conn).get_columns("distribution_daily_plan_locks")}
        conn.execute(sa.text("UPDATE distribution_daily_plan_locks SET plan_snapshot = NULL"))
        migration.downgrade()
        assert "plan_snapshot" not in {c["name"] for c in sa.inspect(conn).get_columns("distribution_daily_plan_locks")}
        assert conn.execute(sa.text("SELECT is_locked FROM distribution_daily_plan_locks")).scalar_one() == 1
    engine.dispose()


def test_orm_snapshot_roundtrip_and_null_semantics():
    engine = sa.create_engine("sqlite+pysqlite:///:memory:")
    with engine.begin() as conn:
        conn.execute(CreateTable(DistributionDailyPlanLock.__table__, include_foreign_key_constraints=[]))
    with Session(engine) as db:
        row = DistributionDailyPlanLock(
            business_id=10, user_id=20, plan_date=date(2026, 11, 28),
            is_locked=False, published_at=datetime.utcnow(), plan_snapshot=None,
        )
        db.add(row)
        db.commit()
        assert db.execute(sa.text("SELECT plan_snapshot FROM distribution_daily_plan_locks")).scalar_one() is None
        row.plan_snapshot = {"items": [{"person_id": 707, "route_id": 99}]}
        db.commit()
        db.expire_all()
        assert row.plan_snapshot == {"items": [{"person_id": 707, "route_id": 99}]}
    engine.dispose()
