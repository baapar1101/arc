"""Atomic distribution setup wizard regression on a real SQLAlchemy Session.

The setup wizard creates settings, territory, route, route stops, customer
profiles and assignments. All must be committed exactly once, or all must be
rolled back if a later stage fails. Repeated calls must not duplicate stops.
"""

from __future__ import annotations

from datetime import date, datetime

import pytest
from sqlalchemy import create_engine, insert
from sqlalchemy.orm import Session
from sqlalchemy.schema import CreateTable

from adapters.db.models.person import Person
from adapters.db.models.distribution import (
    DistributionBusinessSettings,
    DistributionCustomerProfile,
    DistributionDailyPlanLock,
    DistributionRoute,
    DistributionRouteAssignment,
    DistributionRouteStop,
    DistributionTerritory,
)
from app.core.responses import ApiError
from app.services import distribution_service as dist_svc
from app.services import distribution_field_ops_service as fieldops


DAY = date(2026, 11, 25)


@pytest.fixture()
def db(monkeypatch):
    engine = create_engine("sqlite+pysqlite:///:memory:")
    with engine.begin() as conn:
        for table in (
            Person.__table__,
            DistributionBusinessSettings.__table__,
            DistributionTerritory.__table__,
            DistributionRoute.__table__,
            DistributionRouteStop.__table__,
            DistributionRouteAssignment.__table__,
            DistributionCustomerProfile.__table__,
            DistributionDailyPlanLock.__table__,
        ):
            conn.execute(CreateTable(table, include_foreign_key_constraints=[]))
    monkeypatch.setattr(dist_svc, "_ensure_plugin", lambda *_a: None)
    monkeypatch.setattr(fieldops, "business_today", lambda *_a: DAY)
    with Session(engine) as session:
        session.execute(insert(Person.__table__), [
            dict(id=707, business_id=10, alias_name="Local Alpha", person_types="[]"),
            dict(id=708, business_id=10, alias_name="Local Beta", person_types="[]"),
            dict(id=808, business_id=11, alias_name="Other tenant", person_types="[]"),
        ])
        session.commit()
        yield session
    engine.dispose()


def payload(**updates):
    data = {
        "territory_code": "T-TEST",
        "territory_name": "Test Territory",
        "route_code": "R-TEST",
        "route_name": "Test Route",
        "person_ids": [707, 708],
        "customer_class": "A",
        "weekday": 2,
        "frequency": "weekly",
        "visitor_user_id": 20,
        "valid_from": DAY.isoformat(),
    }
    data.update(updates)
    return data


def test_wizard_persists_all_entities_in_exactly_one_commit(db, monkeypatch):
    original_commit = db.commit
    commits = []

    def count_commit():
        commits.append(True)
        return original_commit()

    monkeypatch.setattr(db, "commit", count_commit)
    result = fieldops.run_setup_wizard(db, 10, 1, payload())
    assert commits == [True]
    assert result["ok"] is True
    assert result["settings"]["setup_completed"] is True
    assert result["stops_created"] == 2
    assert result["route"]["id"] > 0
    assert result["assignment"]["user_id"] == 20
    assert db.query(DistributionBusinessSettings).filter_by(business_id=10).count() == 1
    assert db.query(DistributionTerritory).filter_by(business_id=10).count() == 1
    assert db.query(DistributionRoute).filter_by(business_id=10).count() == 1
    assert db.query(DistributionRouteStop).count() == 2
    assert db.query(DistributionCustomerProfile).filter_by(business_id=10).count() == 2
    assert db.query(DistributionRouteAssignment).filter_by(business_id=10).count() == 1


@pytest.mark.parametrize("bad_person_ids", [
    [707, 99999],  # second stop fails AFTER settings, territory, route, first stop/profile
    [707, 808],    # second stop belongs to a different business
])
def test_wizard_rolls_back_all_changes_if_later_stop_fails(
    db, monkeypatch, bad_person_ids,
):
    original_commit = db.commit
    commits = []

    def count_commit():
        commits.append(True)
        return original_commit()

    monkeypatch.setattr(db, "commit", count_commit)
    with pytest.raises(ApiError):
        fieldops.run_setup_wizard(db, 10, 1, payload(person_ids=bad_person_ids))
    assert commits == []
    for model in (
        DistributionBusinessSettings,
        DistributionTerritory,
        DistributionRoute,
        DistributionRouteStop,
        DistributionCustomerProfile,
        DistributionRouteAssignment,
    ):
        assert db.query(model).count() == 0, model.__tablename__
    assert db.query(Person).count() == 3  # preexisting reference data intact


def test_wizard_rolls_back_existing_settings_update_on_failure(db):
    settings = DistributionBusinessSettings(
        business_id=10, enable_van_sales=False, setup_completed=False,
        carry_over_missed_visits=False,
    )
    db.add(settings)
    db.commit()

    with pytest.raises(ApiError):
        fieldops.run_setup_wizard(db, 10, 1, payload(person_ids=[707, 99999]))
    db.expire_all()
    existing = db.get(DistributionBusinessSettings, 10)
    assert existing.setup_completed is False
    assert existing.enable_van_sales is False
    assert existing.carry_over_missed_visits is False
    assert db.query(DistributionRoute).count() == 0


def test_wizard_retry_reuses_existing_stop_and_assignment(db):
    first = fieldops.run_setup_wizard(db, 10, 1, payload())
    second = fieldops.run_setup_wizard(db, 10, 1, payload())
    assert first["stops_created"] == 2
    assert second["stops_created"] == 0
    assert second["route"]["id"] == first["route"]["id"]
    assert second["assignment"]["id"] == first["assignment"]["id"]
    assert db.query(DistributionRouteStop).count() == 2
    assert db.query(DistributionRouteAssignment).count() == 1
    assert db.query(DistributionCustomerProfile).count() == 2


def test_wizard_locked_existing_route_fails_before_settings_update(db):
    route = DistributionRoute(
        id=99, business_id=10, code="R-LOCK", name="Locked route",
        is_active=True,
    )
    db.add(route)
    db.add(DistributionRouteAssignment(
        business_id=10, route_id=99, user_id=20,
        valid_from=date(2026, 11, 1),
    ))
    db.add(DistributionDailyPlanLock(
        business_id=10, user_id=20, plan_date=DAY,
        is_locked=True, published_at=datetime.utcnow(),
    ))
    db.commit()
    with pytest.raises(ApiError):
        fieldops.run_setup_wizard(db, 10, 1, {
            "route_id": 99, "person_ids": [707],
        })
    assert db.query(DistributionBusinessSettings).count() == 0
    assert db.query(DistributionRouteStop).count() == 0
    assert db.query(DistributionDailyPlanLock).count() == 1


def test_wizard_existing_route_does_not_write_other_tenants(db):
    foreign = DistributionRoute(
        id=100, business_id=11, code="R-FOREIGN", name="Foreign route",
        is_active=True,
    )
    db.add(foreign)
    db.commit()
    with pytest.raises(ApiError):
        fieldops.run_setup_wizard(db, 10, 1, {"route_id": 100, "person_ids": [707]})
    assert db.query(DistributionBusinessSettings).count() == 0
    assert db.get(DistributionRoute, 100).name == "Foreign route"
