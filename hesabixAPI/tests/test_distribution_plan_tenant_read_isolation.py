"""Tenant isolation for route-stop lists and daily-plan customer data.

Uses deliberately inconsistent legacy route/person references to prove that
the distribution read paths never reveal another business's PII. No
production connections, database migrations or locked publication enabled.
"""

from __future__ import annotations

from datetime import date, datetime
from types import SimpleNamespace

import pytest
import sqlalchemy as sa
from sqlalchemy.orm import Session
from sqlalchemy.schema import CreateTable

from adapters.db.models.person import Person
from adapters.db.models.distribution import (
    DistributionBusinessSettings,
    DistributionCustomerProfile,
    DistributionDailyPlanLock,
    DistributionFieldVisit,
    DistributionRoute,
    DistributionRouteAssignment,
    DistributionRouteStop,
    DistributionTerritory,
    DistributionVan,
    DistributionUserLiveLocation,
    DistributionReturnRequest,
)
from app.services import distribution_service as distribution
from app.services import distribution_field_ops_service as field_ops
from app.services import distribution_phase3_service as phase3

DAY = date(2026, 11, 23)  # Monday


@pytest.fixture
def db(monkeypatch):
    engine = sa.create_engine("sqlite+pysqlite:///:memory:")
    with engine.begin() as connection:
        for table in (
            Person.__table__,
            DistributionTerritory.__table__,
            DistributionRoute.__table__,
            DistributionRouteAssignment.__table__,
            DistributionRouteStop.__table__,
            DistributionCustomerProfile.__table__,
            DistributionDailyPlanLock.__table__,
            DistributionFieldVisit.__table__,
            DistributionBusinessSettings.__table__,
            DistributionVan.__table__,
            DistributionUserLiveLocation.__table__,
            DistributionReturnRequest.__table__,
        ):
            connection.execute(CreateTable(table, include_foreign_key_constraints=[]))
    monkeypatch.setattr(distribution, "_ensure_plugin", lambda *_args, **_kwargs: None)
    monkeypatch.setattr(distribution, "_ensure_route_allowed_for_strict", lambda *_args, **_kwargs: None)
    monkeypatch.setattr(distribution, "get_plan_lock", lambda *_args, **_kwargs: None)
    monkeypatch.setattr(
        distribution,
        "get_distribution_settings_row",
        lambda *_args, **_kwargs: SimpleNamespace(carry_over_missed_visits=False, carry_over_days=7),
    )
    with Session(engine) as session:
        session.execute(sa.insert(Person.__table__), [
            dict(id=707, business_id=10, alias_name="Tenant ten", person_types="[]",
                 mobile="09111111111", latitude=35.5, longitude=51.5),
            dict(id=808, business_id=11, alias_name="Tenant eleven SECRET", person_types="[]",
                 mobile="09222222222", latitude=36.5, longitude=52.5),
        ])
        session.add_all([
            DistributionRoute(id=99, business_id=10, code="R-99", name="My route", is_active=True),
            DistributionRoute(id=100, business_id=11, code="R-100", name="Foreign route", is_active=True),
        ])
        session.flush()
        session.add_all([
            DistributionRouteStop(id=1, route_id=99, person_id=707, weekday=0, sort_order=1),
            # Legacy corrupted row: foreign customer on a local route.
            DistributionRouteStop(id=2, route_id=99, person_id=808, weekday=0, sort_order=2),
            DistributionRouteStop(id=3, route_id=100, person_id=808, weekday=0, sort_order=1),
            DistributionRouteAssignment(
                business_id=10, route_id=99, user_id=20, valid_from=date(2026, 11, 1),
            ),
            # Legacy corrupted assignment: local visitor -> foreign route.
            DistributionRouteAssignment(
                business_id=10, route_id=100, user_id=20, valid_from=date(2026, 11, 1),
            ),
        ])
        session.commit()
        yield session
    engine.dispose()


def test_route_stop_list_never_discloses_other_business_customer_name(db):
    stops = distribution.list_route_stops(db, 10, 99, object())
    names = {stop["person_id"]: stop["person_name"] for stop in stops}
    assert names[707] == "Tenant ten"
    assert names[808] is None
    assert "Tenant eleven SECRET" not in repr(stops)


def test_individual_plan_item_masks_foreign_contact_and_location(db):
    route = db.get(DistributionRoute, 99)
    own = db.get(DistributionRouteStop, 1)
    foreign = db.get(DistributionRouteStop, 2)
    params = dict(plan_date=DAY, carried_over=False, customer_class=None, frequency="weekly")
    own_item = field_ops._stop_plan_item(db, route, own, **params)
    foreign_item = field_ops._stop_plan_item(db, route, foreign, **params)
    assert own_item["person_name"] == "Tenant ten"
    assert own_item["person_mobile"] == "09111111111"
    assert own_item["latitude"] is not None
    assert foreign_item["person_name"] == "808"
    assert foreign_item["person_mobile"] is None
    assert foreign_item["latitude"] is None
    assert foreign_item["longitude"] is None


def test_daily_plan_excludes_foreign_route_and_corrupt_customer_stop(db, monkeypatch):
    monkeypatch.setattr(db, 'commit', lambda: pytest.fail('daily-plan read must not commit'))
    plan = distribution.get_daily_plan(db, 10, 20, DAY)
    assert plan["plan_date"] == DAY.isoformat()
    assert plan["scheduled_count"] == 1
    assert {row["route_id"] for row in plan["items"]} == {99}
    assert {row["person_id"] for row in plan["items"]} == {707}
    local = plan["items"][0]
    assert local["person_name"] == "Tenant ten"
    assert local["person_mobile"] == "09111111111"
    assert "Tenant eleven SECRET" not in repr(plan)
    assert "09222222222" not in repr(plan)
    assert "808" not in repr(plan["items"])


def test_enrichment_ignores_other_business_route_even_when_assignment_is_corrupt(db):
    plan = field_ops.enrich_daily_plan(db, 10, 20, DAY, [])
    assert {row["route_id"] for row in plan["items"]} == {99}
    assert {row["person_id"] for row in plan["items"]} == {707}
    assert all(row["route_name"] == "My route" for row in plan["items"])


def test_carried_over_plan_does_not_include_foreign_customer(db, monkeypatch):
    # An invalid Tuesday stop would otherwise be carried into Monday's plan.
    db.get(DistributionRouteStop, 2).weekday = 1
    db.commit()
    monkeypatch.setattr(
        distribution,
        "get_distribution_settings_row",
        lambda *_a: SimpleNamespace(carry_over_missed_visits=True, carry_over_days=7),
    )
    monkeypatch.setattr(field_ops, "_completed_person_days", lambda *_args: set())
    result = field_ops.enrich_daily_plan(db, 10, 20, DAY, [])
    assert {row["person_id"] for row in result["items"]} == {707}
    assert result["scheduled_count"] == 1
    assert result["carried_over_count"] == 0


@pytest.mark.parametrize("invalid_items", [
    [{"person_id": 707}, {"person_id": 808}],
    [{"person_id": 808}],
    [{"person_id": "not-an-integer"}],
    [{"person_name": "Unscoped customer"}],
    [None],
])
def test_offline_pack_rejects_corrupt_customer_snapshot_before_disclosure(
    db, monkeypatch, invalid_items,
):
    monkeypatch.setattr(field_ops, "business_today", lambda *_args: DAY)
    monkeypatch.setattr(
        distribution,
        "get_daily_plan",
        lambda *_args: {"items": invalid_items, "plan_date": DAY.isoformat()},
    )
    monkeypatch.setattr(
        distribution,
        "get_distribution_settings_row",
        lambda *_args: None,
    )
    ctx = SimpleNamespace(get_user_id=lambda: 20)
    from app.core.responses import ApiError

    with pytest.raises(ApiError) as error:
        field_ops.build_offline_pack(db, 10, ctx)
    assert (error.value.code, error.value.status_code) == ("CONFLICT", 409)


def test_offline_pack_rejects_missing_items_in_old_snapshot(db, monkeypatch):
    monkeypatch.setattr(field_ops, "business_today", lambda *_args: DAY)
    monkeypatch.setattr(distribution, "get_daily_plan", lambda *_args: {"items": None})
    monkeypatch.setattr(distribution, "get_distribution_settings_row", lambda *_args: None)
    from app.core.responses import ApiError

    with pytest.raises(ApiError) as error:
        field_ops.build_offline_pack(db, 10, SimpleNamespace(get_user_id=lambda: 20))
    assert (error.value.code, error.value.status_code) == ("CONFLICT", 409)


