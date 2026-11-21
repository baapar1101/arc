"""Regression tests for isolated distribution plan publication state."""

from __future__ import annotations

from datetime import date

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import Session

from adapters.api.v1.schema_models.distribution import DailyPlanPublishPayload
from adapters.db.models.distribution import DistributionDailyPlanLock, DistributionRouteAssignment
from app.core.responses import ApiError
from app.services import distribution_service as svc


@pytest.fixture()
def db(monkeypatch):
    # The publishing service is exercised without an external PostgreSQL server.
    # Plugin activation and API-level manager permission are separate concerns.
    monkeypatch.setattr(svc, "_ensure_plugin", lambda *_args: None)
    engine = create_engine("sqlite+pysqlite:///:memory:")
    DistributionRouteAssignment.__table__.create(engine)
    DistributionDailyPlanLock.__table__.create(engine)
    with Session(engine) as session:
        yield session
    engine.dispose()


def _assign(db: Session, business_id: int, user_id: int, start: date, end: date | None = None) -> None:
    db.add(
        DistributionRouteAssignment(
            business_id=business_id,
            user_id=user_id,
            route_id=99,
            valid_from=start,
            valid_to=end,
        )
    )
    db.commit()


@pytest.mark.parametrize("method", ["POST", "DELETE"])
def test_publication_endpoints_require_distribution_manage(method):
    from adapters.api.v1.distribution import router

    matches = [
        route for route in router.routes
        if route.path == "/distribution/business/{business_id}/daily-plan/publish"
        and method in route.methods
    ]
    assert len(matches) == 1

    captured = []
    for dependency in matches[0].dependant.dependencies:
        callback = dependency.call
        closure = getattr(callback, "__closure__", None)
        if closure:
            captured.append({
                key: cell.cell_contents
                for key, cell in zip(callback.__code__.co_freevars, closure)
            })
    assert any(
        values.get("section") == "distribution" and values.get("action") == "manage"
        for values in captured
    )


def test_alembic_plan_lock_migration_upgrade_and_downgrade(monkeypatch):
    from importlib.util import module_from_spec, spec_from_file_location
    from pathlib import Path

    from alembic.migration import MigrationContext
    from alembic.operations import Operations
    from sqlalchemy import inspect

    path = (
        Path(__file__).resolve().parents[1]
        / "migrations"
        / "versions"
        / "20261121_000001_distribution_daily_plan_locks.py"
    )
    spec = spec_from_file_location("distribution_daily_plan_migration", path)
    assert spec is not None and spec.loader is not None
    migration = module_from_spec(spec)
    spec.loader.exec_module(migration)
    engine = create_engine("sqlite+pysqlite:///:memory:")
    with engine.begin() as connection:
        monkeypatch.setattr(migration, "op", Operations(MigrationContext.configure(connection)))
        migration.upgrade()
        columns = {
            col["name"]
            for col in inspect(connection).get_columns("distribution_daily_plan_locks")
        }
        assert {
            "business_id", "user_id", "plan_date", "is_locked",
            "published_by_user_id", "published_at",
        }.issubset(columns)
        migration.downgrade()
        assert not inspect(connection).has_table("distribution_daily_plan_locks")
    engine.dispose()


def test_schema_keeps_explicit_single_and_bulk_options():
    assert DailyPlanPublishPayload().all_assigned is False
    assert DailyPlanPublishPayload(all_assigned=True).locked is False
    with pytest.raises(ValueError):
        DailyPlanPublishPayload(target_user_id=-1)


def test_publish_is_idempotent_per_business_user_day(db):
    day = date(2026, 11, 21)
    _assign(db, 10, 20, date(2026, 11, 1))

    first = svc.publish_daily_plan(db, 10, 1, 20, day, notes="approved")
    second = svc.publish_daily_plan(db, 10, 1, 20, day, locked=False)

    assert first["published"] is True
    assert first["locked"] is False
    assert second["locked"] is False
    assert second["notes"] == "approved"
    assert db.query(DistributionDailyPlanLock).count() == 1


def test_rejects_locked_publication_until_edit_guards_exist(db):
    day = date(2026, 11, 21)
    _assign(db, 10, 20, date(2026, 11, 1))

    with pytest.raises(ApiError):
        svc.publish_daily_plan(db, 10, 1, 20, day, locked=True)
    with pytest.raises(ApiError):
        svc.publish_daily_plans_for_date(db, 10, 1, day, locked=True)
    assert db.query(DistributionDailyPlanLock).count() == 0


def test_rejects_target_without_active_assignment(db):
    day = date(2026, 11, 21)
    _assign(db, 10, 20, date(2026, 10, 1), date(2026, 11, 20))
    _assign(db, 11, 30, date(2026, 11, 1))

    with pytest.raises(ApiError):
        svc.publish_daily_plan(db, 10, 1, 20, day)
    with pytest.raises(ApiError):
        svc.publish_daily_plan(db, 10, 1, 30, day)
    assert db.query(DistributionDailyPlanLock).count() == 0


def test_bulk_publish_is_business_scoped_and_ignores_expired_assignments(db):
    day = date(2026, 11, 21)
    _assign(db, 10, 20, date(2026, 11, 1))
    _assign(db, 10, 21, date(2026, 11, 1))
    _assign(db, 10, 22, date(2026, 11, 1), date(2026, 11, 20))
    _assign(db, 11, 30, date(2026, 11, 1))

    result = svc.publish_daily_plans_for_date(db, 10, 1, day)

    assert result["published_count"] == 2
    assert {row["user_id"] for row in result["items"]} == {20, 21}
    assert {row.user_id for row in db.query(DistributionDailyPlanLock).all()} == {20, 21}


def test_unpublish_is_idempotent_and_scoped_to_current_business(db):
    day = date(2026, 11, 21)
    _assign(db, 10, 20, date(2026, 11, 1))
    _assign(db, 11, 20, date(2026, 11, 1))
    svc.publish_daily_plan(db, 10, 1, 20, day)
    svc.publish_daily_plan(db, 11, 2, 20, day)

    svc.unpublish_daily_plan(db, 10, 20, day)
    svc.unpublish_daily_plan(db, 10, 20, day)

    assert svc.get_plan_lock(db, 10, 20, day) is None
    assert svc.get_plan_lock(db, 11, 20, day) is not None
    assert svc.plan_lock_to_dict(None)["published"] is False
