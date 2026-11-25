"""Onboard a distribution outlet atomically, with post-commit notifications.

Uses a real isolated SQLAlchemy session and person/business/profile/route
tables. It deliberately fails after the person ID has been allocated to prove
the new customer cannot survive a failed follow-on step.
"""
from __future__ import annotations

from datetime import date, datetime
from types import SimpleNamespace

import pytest
import sqlalchemy as sa
from sqlalchemy.orm import Session
from sqlalchemy.schema import CreateTable

from adapters.db.models.business import Business, BusinessType, BusinessField
from adapters.db.models.person import Person, PersonBankAccount, PersonSocialContact
from adapters.db.models.distribution import (
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
from app.services import person_service


DAY = date(2026, 11, 25)


@pytest.fixture()
def db(monkeypatch):
    engine = sa.create_engine("sqlite+pysqlite:///:memory:")
    tables = (
        Business.__table__,
        Person.__table__,
        PersonBankAccount.__table__,
        PersonSocialContact.__table__,
        DistributionTerritory.__table__,
        DistributionRoute.__table__,
        DistributionRouteStop.__table__,
        DistributionRouteAssignment.__table__,
        DistributionCustomerProfile.__table__,
        DistributionDailyPlanLock.__table__,
    )
    with engine.begin() as conn:
        for table in tables:
            conn.execute(CreateTable(table, include_foreign_key_constraints=[]))

    monkeypatch.setattr(dist_svc, "_ensure_plugin", lambda *_args: None)
    monkeypatch.setattr(fieldops, "business_today", lambda *_args: DAY)
    # External side effects must never run while an uncommitted person exists.
    notices = []
    monkeypatch.setattr(
        person_service, "notify_person_created",
        lambda _db, business_id, person_id, person_types, **_kwargs: notices.append(
            (business_id, person_id, tuple(person_types))
        ),
    )
    with Session(engine) as session:
        session.add_all([
            Business(
                id=10, name="Own business", owner_id=1,
                business_type=BusinessType.SHOP, business_field=BusinessField.TRADING,
            ),
            Business(
                id=11, name="Other business", owner_id=2,
                business_type=BusinessType.SHOP, business_field=BusinessField.TRADING,
            ),
            DistributionRoute(
                id=99, business_id=10, code="R-LOCAL",
                name="Local Route", is_active=True,
            ),
            DistributionRoute(
                id=100, business_id=11, code="R-FOREIGN",
                name="Other Route", is_active=True,
            ),
        ])
        session.commit()
        yield session, notices
    engine.dispose()


def test_outlet_onboarding_commits_once_and_returns_nested_person_id(db, monkeypatch):
    session, notices = db
    actual_commit = session.commit
    calls = []

    def tracked_commit():
        calls.append("commit")
        return actual_commit()

    monkeypatch.setattr(session, "commit", tracked_commit)
    result = fieldops.onboard_new_outlet(session, 10, 1, {
        "name": "New grocery",
        "mobile": "09123456789",
        "latitude": 35.7,
        "longitude": 51.4,
        "customer_class": "A",
        "frequency": "weekly",
        "outlet_type": "grocery",
        "route_id": 99,
        "weekday": 2,
        "sort_order": 5,
    })

    assert calls == ["commit"]
    person_id = result["person_id"]
    assert result["person"]["data"]["id"] == person_id
    assert result["person"]["data"]["business_id"] == 10
    assert result["person"]["data"]["alias_name"] == "New grocery"
    assert result["stop"]["person_id"] == person_id
    assert result["profile"]["onboarded_at"]
    person = session.get(Person, person_id)
    assert person is not None
    assert float(person.latitude) == pytest.approx(35.7)
    assert float(person.longitude) == pytest.approx(51.4)
    assert person.business_id == 10
    assert session.query(DistributionRouteStop).filter_by(route_id=99).count() == 1
    assert session.query(DistributionCustomerProfile).filter_by(person_id=person_id).count() == 1
    assert notices == [(10, person_id, tuple(result["person"]["data"]["person_types"]))]


@pytest.mark.parametrize("bad_payload,expected_code", [
    ({"outlet_type": "invalid-type"}, "VALIDATION_ERROR"),
    ({"route_id": 100}, "NOT_FOUND"),
])
def test_outlet_failure_leaves_no_person_profile_or_notification(
    db, bad_payload, expected_code,
):
    session, notices = db
    payload = {
        "name": "Should not survive",
        "mobile": "09120000000",
        "route_id": 99,
    }
    payload.update(bad_payload)
    with pytest.raises(ApiError) as error:
        fieldops.onboard_new_outlet(session, 10, 1, payload)
    assert error.value.code == expected_code
    assert session.query(Person).count() == 0
    assert session.query(DistributionRouteStop).count() == 0
    assert session.query(DistributionCustomerProfile).count() == 0
    assert notices == []


def test_outlet_rolls_back_after_profile_if_stop_stage_fails(db, monkeypatch):
    session, notices = db
    def reject_stop(*_args, **_kwargs):
        raise ApiError("CONFLICT", "Simulated stop failure", http_status=409)

    monkeypatch.setattr(dist_svc, "upsert_route_stop", reject_stop)
    with pytest.raises(ApiError, match="Simulated stop failure"):
        fieldops.onboard_new_outlet(session, 10, 1, {
            "name": "Failed after customer and profile",
            "route_id": 99, "customer_class": "B",
            "latitude": 35.1, "longitude": 51.2,
        })
    assert session.query(Person).count() == 0
    assert session.query(DistributionCustomerProfile).count() == 0
    assert session.query(DistributionRouteStop).count() == 0
    assert notices == []


def test_onboarding_rejects_locked_route_without_creating_customer(db):
    session, notices = db
    session.add(DistributionRouteAssignment(
        business_id=10, user_id=20, route_id=99,
        valid_from=date(2026, 11, 1),
    ))
    session.add(DistributionDailyPlanLock(
        business_id=10, user_id=20, plan_date=DAY,
        is_locked=True, published_at=datetime.utcnow(),
    ))
    session.commit()
    with pytest.raises(ApiError) as error:
        fieldops.onboard_new_outlet(
            session, 10, 1, {"name": "Forbidden", "route_id": 99},
        )
    assert error.value.status_code == 409
    assert session.query(Person).count() == 0
    assert session.query(DistributionRouteStop).count() == 0
    assert notices == []


def test_onboarding_without_route_still_persists_customer_profile(db):
    session, notices = db
    result = fieldops.onboard_new_outlet(session, 10, 1, {
        "name": "Unrouted shop", "outlet_type": "kiosk",
    })
    assert result["stop"] is None
    assert result["person_id"] > 0
    assert result["profile"]["outlet_type"] == "kiosk"
    assert session.query(DistributionRouteStop).count() == 0
    assert session.query(Person).count() == 1
    assert len(notices) == 1


def test_standalone_person_create_preserves_default_commit_and_notification(
    db, monkeypatch,
):
    """Public non-distribution APIs still commit the person and notify once."""
    from adapters.api.v1.schema_models.person import PersonCreateRequest, PersonType

    session, notices = db
    original_commit = session.commit
    commits = []

    def tracked_commit():
        commits.append(True)
        return original_commit()

    monkeypatch.setattr(session, "commit", tracked_commit)
    result = person_service.create_person(
        session, 10,
        PersonCreateRequest(alias_name="Standalone person", person_types=[PersonType.CUSTOMER]),
    )
    assert result["success"] is True
    person_id = result["data"]["id"]
    assert person_id > 0
    assert commits == [True]
    assert session.query(Person).filter_by(business_id=10).count() == 1
    assert notices == [(10, person_id, tuple(result["data"]["person_types"]))]


def test_onboarding_commit_failure_rolls_back_without_notification(db, monkeypatch):
    session, notices = db

    def failed_commit():
        raise RuntimeError("Simulated database commit failure")

    monkeypatch.setattr(session, "commit", failed_commit)
    with pytest.raises(RuntimeError, match="Simulated database commit failure"):
        fieldops.onboard_new_outlet(
            session, 10, 1,
            {"name": "Person must be rolled back", "route_id": 99},
        )
    assert session.query(Person).count() == 0
    assert session.query(DistributionCustomerProfile).count() == 0
    assert session.query(DistributionRouteStop).count() == 0
    assert notices == []


def test_postcommit_notification_failure_does_not_lie_about_saved_customer(db, monkeypatch):
    session, notices = db

    def broken_notification(*_args, **_kwargs):
        raise RuntimeError("Workflow backend unavailable")

    monkeypatch.setattr(person_service, "notify_person_created", broken_notification)
    result = fieldops.onboard_new_outlet(
        session, 10, 1, {"name": "Customer safely committed", "route_id": 99},
    )
    assert result["person_id"] > 0
    assert session.query(Person).filter_by(id=result["person_id"]).count() == 1
    assert session.query(DistributionCustomerProfile).count() == 1
    assert session.query(DistributionRouteStop).count() == 1
    assert notices == []
