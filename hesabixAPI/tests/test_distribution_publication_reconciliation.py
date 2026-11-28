"""Publication contract on the master-based candidate; no production connections."""
from datetime import date, datetime
from types import SimpleNamespace
from unittest.mock import Mock

import pytest
import sqlalchemy as sa
from sqlalchemy.orm import Session
from sqlalchemy.schema import CreateTable

from adapters.api.v1.schema_models.distribution import DailyPlanPublishPayload
from adapters.db.models.distribution import (
    DistributionDailyPlanLock, DistributionRoute, DistributionRouteAssignment,
    DistributionBusinessSettings, DistributionRouteStop, DistributionCustomerProfile, DistributionTerritory,
)
from adapters.db.models.person import Person
from app.core.responses import ApiError
from app.services import distribution_phase3_service as phase3
from app.services import distribution_service as svc

DAY = date(2026, 11, 23)


@pytest.fixture
def db(monkeypatch):
    engine = sa.create_engine("sqlite+pysqlite:///:memory:")
    with engine.begin() as connection:
        for table in (DistributionRoute.__table__, DistributionRouteAssignment.__table__, DistributionDailyPlanLock.__table__,
                      DistributionBusinessSettings.__table__, DistributionRouteStop.__table__,
                      DistributionCustomerProfile.__table__, DistributionTerritory.__table__, Person.__table__):
            connection.execute(CreateTable(table, include_foreign_key_constraints=[]))
    monkeypatch.setattr(svc, "_ensure_plugin", lambda *_a: None)
    with Session(engine) as session:
        session.add_all([
            DistributionRoute(id=1, business_id=10, code="A", name="Own active", is_active=True),
            DistributionRoute(id=2, business_id=11, code="B", name="Foreign active", is_active=True),
            DistributionRoute(id=3, business_id=10, code="C", name="Own inactive", is_active=False),
        ])
        session.flush()
        for route, user in [(1, 20), (1, 21), (2, 22), (3, 23)]:
            session.add(DistributionRouteAssignment(
                business_id=10, route_id=route, user_id=user,
                valid_from=date(2026, 11, 1),
            ))
        session.commit()
        yield session
    engine.dispose()


def test_default_publication_is_unlocked():
    assert DailyPlanPublishPayload().locked is False


def test_assignment_scope_excludes_foreign_and_inactive_routes(db):
    assert svc.assigned_user_ids_for_date(db, 10, DAY) == {20, 21}
    for uid in (22, 23, 999):
        with pytest.raises(ApiError):
            svc.publish_daily_plan(db, 10, 1, uid, DAY)
    assert db.query(DistributionDailyPlanLock).count() == 0


def test_bulk_respects_supervisor_scope_and_transaction_lock(db, monkeypatch):
    lock = Mock()
    monkeypatch.setattr(svc, "_serialize_distribution_plan_mutation", lock)
    monkeypatch.setattr(svc, "scoped_user_ids_for_ctx", lambda *_a: {20, 22})
    ctx = SimpleNamespace()
    result = svc.publish_daily_plans_for_date(db, 10, 1, DAY, ctx=ctx)
    lock.assert_called_once_with(db, 10)
    assert result["published_count"] == 1
    assert result["items"][0]["user_id"] == 20
    assert db.query(DistributionDailyPlanLock).one().is_locked is False


def test_single_authorization_is_preserved(db, monkeypatch):
    def deny(*args, **kwargs):
        assert kwargs["write"] is True
        raise ApiError("FORBIDDEN", "Denied by supervisor scope", http_status=403)
    monkeypatch.setattr(svc, "assert_user_visible_for_ctx", deny)
    with pytest.raises(ApiError) as error:
        svc.publish_daily_plan(db, 10, 1, 20, DAY, ctx=object())
    assert error.value.status_code == 403
    assert db.query(DistributionDailyPlanLock).count() == 0


def test_explicit_locked_publication_refused(db):
    with pytest.raises(ApiError) as error:
        svc.publish_daily_plan(db, 10, 1, 20, DAY, locked=True)
    assert error.value.status_code == 400
    with pytest.raises(ApiError) as error:
        svc.publish_daily_plans_for_date(db, 10, 1, DAY, locked=True)
    assert error.value.status_code == 400
    assert db.query(DistributionDailyPlanLock).count() == 0


def test_existing_locked_publication_requires_explicit_unpublish(db):
    db.add(DistributionDailyPlanLock(
        business_id=10, user_id=20, plan_date=DAY, is_locked=True,
        published_by_user_id=1, published_at=datetime.utcnow(),
    ))
    db.commit()
    with pytest.raises(ApiError) as error:
        svc.publish_daily_plan(db, 10, 1, 20, DAY)
    assert error.value.status_code == 409
    db.rollback()
    assert db.query(DistributionDailyPlanLock).one().is_locked is True
    svc.unpublish_daily_plan(db, 10, 20, DAY)
    assert db.query(DistributionDailyPlanLock).count() == 0
    svc.publish_daily_plan(db, 10, 1, 20, DAY)
    assert db.query(DistributionDailyPlanLock).one().is_locked is False


def _existing_lock(db, *, business=10, user=20, day=DAY):
    db.add(DistributionDailyPlanLock(
        business_id=business, user_id=user, plan_date=day, is_locked=True,
        published_by_user_id=1, published_at=datetime.utcnow(),
    ))
    db.commit()


def test_catalog_guards_respect_actual_lock_without_creating_settings(db):
    _existing_lock(db)
    with pytest.raises(ApiError) as error:
        svc.assert_plan_unlocked_for_route(db, 10, 1, DAY)
    assert error.value.status_code == 409
    svc.assert_plan_unlocked_for_route(db, 10, 1, date(2026, 11, 24))
    svc.assert_plan_unlocked_for_route(db, 11, 2, DAY)
    assert db.query(DistributionBusinessSettings).count() == 0


def test_locked_assignment_and_stop_mutations_fail_before_writes(db):
    _existing_lock(db)
    row = db.query(DistributionRouteAssignment).filter_by(business_id=10, user_id=20).one()
    for operation in (
        lambda: svc.delete_assignment(db, 10, row.id),
        lambda: svc.create_assignment(db, 10, dict(route_id=1, user_id=20, valid_from="2026-11-20")),
        lambda: svc.upsert_route_stop(db, 10, 1, dict(person_id=99)),
        lambda: svc.delete_route_stop(db, 10, 1, 99),
        lambda: svc.update_distribution_settings(db, 10, dict(carry_over_days=3)),
    ):
        with pytest.raises(ApiError) as error:
            operation()
        assert error.value.status_code == 409
        db.rollback()
    assert db.query(DistributionRouteAssignment).count() == 4
    assert db.query(DistributionBusinessSettings).count() == 0


def test_new_settings_are_committed_only_once(db, monkeypatch):
    original_commit = db.commit
    calls = []
    def commit():
        calls.append("commit")
        original_commit()
    monkeypatch.setattr(db, "commit", commit)
    svc.update_distribution_settings(db, 10, dict(carry_over_days=3))
    assert calls == ["commit"]
    assert db.query(DistributionBusinessSettings).one().carry_over_days == 3


def test_assignment_merge_has_no_intermediate_settings_commit(db, monkeypatch):
    # Use a route without a conflicting assignment; keep the new master's
    # same-visitor range merging and exclusive ownership logic intact.
    original_commit = db.commit
    calls = []
    def commit():
        calls.append("commit")
        original_commit()
    monkeypatch.setattr(db, "commit", commit)
    result = svc.create_assignment(db, 10, dict(
        route_id=3, user_id=23, valid_from="2026-11-15", valid_to="2026-11-30",
    ))
    assert result["merged"] is True
    assert calls == ["commit"]
    assert db.query(DistributionBusinessSettings).count() == 0


def test_route_optimizer_checks_lock_before_calculation(db, monkeypatch):
    _existing_lock(db)
    monkeypatch.setattr(phase3, "optimize_route_plan", lambda *_a: pytest.fail("locked plan must not be recalculated"))
    with pytest.raises(ApiError) as error:
        phase3.apply_route_optimize(db, 10, 1, DAY)
    assert error.value.status_code == 409


def test_optimizer_preserves_old_day_override(db, monkeypatch):
    route = db.get(DistributionRoute, 1)
    route.plan_sort_overrides = {"2026-01-01": {"3": 1}}
    db.commit()
    monkeypatch.setattr(phase3, "optimize_route_plan", lambda *_a: {
        "optimized": True, "items": [{"stop_id": 4, "optimized_sort": 1}],
    })
    assert phase3.apply_route_optimize(db, 10, 1, DAY)["persisted"] is True
    assert db.get(DistributionRoute, 1).plan_sort_overrides == {
        "2026-01-01": {"3": 1}, DAY.isoformat(): {"4": 1},
    }
