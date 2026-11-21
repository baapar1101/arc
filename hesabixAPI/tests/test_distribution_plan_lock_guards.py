"""Regression for locked daily plans and their route/assignment mutation guards."""

from __future__ import annotations

from datetime import date, datetime

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import Session

from adapters.db.models.distribution import (
    DistributionDailyPlanLock,
    DistributionRoute,
    DistributionRouteAssignment,
    DistributionRouteStop,
)
from app.core.responses import ApiError
from app.services import distribution_service as svc
from app.services import distribution_phase3_service as phase3


DAY = date(2026, 11, 21)


@pytest.fixture()
def db(monkeypatch):
    monkeypatch.setattr(svc, "_ensure_plugin", lambda *_args: None)
    engine = create_engine("sqlite+pysqlite:///:memory:")
    for table in (
        DistributionRoute.__table__,
        DistributionRouteStop.__table__,
        DistributionRouteAssignment.__table__,
        DistributionDailyPlanLock.__table__,
    ):
        table.create(engine)
    with Session(engine) as session:
        yield session
    engine.dispose()


def setup_route(db: Session, *, business_id=10, route_id=99, user_id=20, locked=True):
    route = DistributionRoute(
        id=route_id, business_id=business_id, code=f"R-{route_id}",
        name="Test route", is_active=True,
    )
    db.add(route)
    db.add(DistributionRouteAssignment(
        business_id=business_id, route_id=route_id, user_id=user_id,
        valid_from=date(2026, 11, 1), valid_to=None,
    ))
    db.add(DistributionDailyPlanLock(
        business_id=business_id, user_id=user_id, plan_date=DAY,
        is_locked=locked, published_by_user_id=1,
        published_at=datetime.utcnow(),
    ))
    db.commit()
    return route


def test_locked_route_blocks_catalog_edit_and_unrelated_date_is_allowed(db):
    setup_route(db)
    with pytest.raises(ApiError):
        svc.assert_route_has_no_locked_plans(db, 10, 99)
    with pytest.raises(ApiError):
        svc.assert_route_has_no_locked_plans(db, 10, 99, plan_date=DAY)
    svc.assert_route_has_no_locked_plans(db, 10, 99, plan_date=date(2026, 11, 22))
    svc.assert_route_has_no_locked_plans(db, 10, 1234)
    svc.assert_route_has_no_locked_plans(db, 11, 99)


def test_locked_route_blocks_stop_change_and_assignment_deletion(db):
    setup_route(db)
    with pytest.raises(ApiError):
        svc.upsert_route_stop(db, 10, 99, {"person_id": 1234, "weekday": 5})
    with pytest.raises(ApiError):
        svc.delete_route_stop(db, 10, 99, 1234)
    assignment = db.query(DistributionRouteAssignment).one()
    with pytest.raises(ApiError):
        svc.delete_assignment(db, 10, assignment.id)
    assert db.query(DistributionRouteAssignment).count() == 1
    assert db.query(DistributionRouteStop).count() == 0


def test_locked_plan_blocks_overlapping_assignment_but_not_future_interval(db):
    setup_route(db)
    with pytest.raises(ApiError):
        svc.assert_assignment_has_no_locked_plans(db, 10, 20, DAY, None)
    with pytest.raises(ApiError):
        svc.assert_assignment_has_no_locked_plans(
            db, 10, 20, date(2026, 11, 1), date(2026, 11, 25),
        )
    svc.assert_assignment_has_no_locked_plans(
        db, 10, 20, date(2026, 11, 22), None,
    )
    svc.assert_assignment_has_no_locked_plans(
        db, 11, 20, date(2026, 11, 1), None,
    )
    with pytest.raises(ApiError):
        svc.assert_assignment_has_no_locked_plans(
            db, 10, 20, date(2026, 11, 22), date(2026, 11, 21),
        )


def test_add_assignment_cannot_change_locked_visitors_itinerary(db):
    setup_route(db)
    db.add(DistributionRoute(
        id=101, business_id=10, code="R-101", name="Extra route", is_active=True,
    ))
    db.commit()
    with pytest.raises(ApiError):
        svc.create_assignment(db, 10, {
            "route_id": 101,
            "user_id": 20,
            "valid_from": "2026-11-01",
        })
    assert db.query(DistributionRouteAssignment).count() == 1
    allowed = svc.create_assignment(db, 10, {
        "route_id": 101,
        "user_id": 20,
        "valid_from": "2026-11-22",
    })
    assert allowed["user_id"] == 20


def test_editing_route_rejected_before_changes_and_unpublish_restores_access(db, monkeypatch):
    setup_route(db)
    from app.services import sepidar_plugin_service

    monkeypatch.setattr(sepidar_plugin_service, "assert_plugin_entity_editable", lambda *_: None)
    with pytest.raises(ApiError):
        svc.update_route(db, 10, 99, {"name": "Blocked"})
    assert db.query(DistributionRoute).filter_by(id=99).one().name == "Test route"

    svc.unpublish_daily_plan(db, 10, 20, DAY)
    updated = svc.update_route(db, 10, 99, {"name": "Now allowed"})
    assert updated["name"] == "Now allowed"


def test_day_optimization_override_cannot_change_locked_date(db, monkeypatch):
    route = setup_route(db)
    monkeypatch.setattr(
        phase3, "optimize_route_plan",
        lambda *_args, **_kwargs: {
            "items": [{"stop_id": 44, "optimized_sort": 1}],
            "optimized": True,
        },
    )

    with pytest.raises(ApiError):
        phase3.apply_route_optimize(db, 10, 99, DAY)
    db.refresh(route)
    assert not route.plan_sort_overrides

    result = phase3.apply_route_optimize(db, 10, 99, date(2026, 11, 22))
    assert result["persisted"] is True
    db.refresh(route)
    assert "2026-11-22" in route.plan_sort_overrides


def test_unlocked_publication_does_not_block_route_mutations(db):
    setup_route(db, locked=False)
    svc.assert_route_has_no_locked_plans(db, 10, 99)
    svc.assert_assignment_has_no_locked_plans(db, 10, 20, DAY, None)


def test_customer_schedule_edit_guard_follows_locked_route_stops(db):
    setup_route(db)
    db.add(DistributionRouteStop(
        route_id=99,
        person_id=707,
        sort_order=1,
        weekday=5,
        frequency="weekly",
    ))
    db.commit()

    with pytest.raises(ApiError):
        svc.assert_customer_schedule_unlocked(db, 10, 707)

    # A different person or business is not affected by this lock.
    svc.assert_customer_schedule_unlocked(db, 10, 708)
    svc.assert_customer_schedule_unlocked(db, 11, 707)

    svc.unpublish_daily_plan(db, 10, 20, DAY)
    svc.assert_customer_schedule_unlocked(db, 10, 707)


def test_unlocked_plan_allows_customer_schedule_changes(db):
    setup_route(db, locked=False)
    db.add(DistributionRouteStop(route_id=99, person_id=707, sort_order=1))
    db.commit()
    svc.assert_customer_schedule_unlocked(db, 10, 707)
