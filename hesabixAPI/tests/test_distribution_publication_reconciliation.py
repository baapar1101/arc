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
)
from app.core.responses import ApiError
from app.services import distribution_service as svc

DAY = date(2026, 11, 23)


@pytest.fixture
def db(monkeypatch):
    engine = sa.create_engine("sqlite+pysqlite:///:memory:")
    with engine.begin() as connection:
        for table in (DistributionRoute.__table__, DistributionRouteAssignment.__table__, DistributionDailyPlanLock.__table__):
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
