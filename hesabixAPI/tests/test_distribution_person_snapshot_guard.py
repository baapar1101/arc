"""Regression for general Person mutations that affect locked daily plans.

Route/assignment/lock tables are real SQLite tables. Person lookup is isolated
because this suite only tests the pre-write business-scoped distribution guard.
"""
from types import SimpleNamespace

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import Session

from adapters.api.v1.schema_models.person import PersonUpdateRequest
from adapters.db.models.person import Person
from adapters.db.models.distribution import (
    DistributionDailyPlanLock, DistributionRoute, DistributionRouteAssignment,
    DistributionRouteStop,
)
from app.core.responses import ApiError
from app.services import person_service
from app.services import distribution_service
from tests.test_distribution_plan_lock_guards import DAY, setup_route


class _PersonQuery:
    def __init__(self, person):
        self.person = person

    def filter(self, *_args):
        return self

    def options(self, *_args):
        return self

    def first(self):
        return self.person


class _PersonSession:
    def __init__(self, route_db, person):
        self.route_db = route_db
        self.person = person
        self.commits = 0
        self.deletes = 0

    def query(self, model):
        if model is Person:
            return _PersonQuery(self.person)
        return self.route_db.query(model)

    def get_bind(self):
        return self.route_db.get_bind()

    def commit(self):
        self.commits += 1
        self.route_db.commit()

    def refresh(self, _row):
        pass

    def delete(self, _row):
        self.deletes += 1

    def rollback(self):
        self.route_db.rollback()


@pytest.fixture
def db(monkeypatch):
    # This suite exercises guards on isolated route/assignment tables without
    # loading marketplace entitlement tables.
    monkeypatch.setattr(distribution_service, "_ensure_plugin", lambda *_args: None)
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


def _person(pid=707, business=10):
    return SimpleNamespace(
        id=pid, business_id=business, alias_name="Original",
        mobile="09120000000", mobile_2=None, mobile_3=None,
        phone=None, latitude=35.0, longitude=51.0,
        person_types="[]", share_count=None,
    )


def _locked_customer(db):
    setup_route(db, business_id=10, route_id=99, user_id=20, locked=True)
    db.add(DistributionRouteStop(route_id=99, person_id=707, sort_order=1))
    db.commit()


@pytest.mark.parametrize("field,new_value", [
    ("alias_name", "Renamed"),
    ("mobile", "09121111111"),
    ("mobile_2", "09122222222"),
    ("phone", "02112345678"),
])
def test_general_person_edit_rejected_before_mutation(db, field, new_value):
    _locked_customer(db)
    person = _person()
    session = _PersonSession(db, person)
    with pytest.raises(ApiError, match="locked daily plan"):
        person_service.update_person(
            session, 707, 10, PersonUpdateRequest(**{field: new_value})
        )
    assert getattr(person, field) != new_value
    assert session.commits == 0


def test_general_person_delete_rejected_before_document_checks_or_write(db, monkeypatch):
    _locked_customer(db)
    session = _PersonSession(db, _person())
    monkeypatch.setattr(
        person_service, "check_person_has_accounting_documents",
        lambda *_args: (_ for _ in ()).throw(
            AssertionError("Document check must not run before locked-plan rejection")
        ),
    )
    with pytest.raises(ApiError, match="locked daily plan"):
        person_service.delete_person(session, 707, 10)
    assert session.deletes == session.commits == 0


def test_unrelated_person_edits_and_noop_name_not_restricted(db):
    _locked_customer(db)
    person = _person()
    session = _PersonSession(db, person)
    person_service._assert_distribution_snapshot_person_editable(
        session, person, {"credit_limit": 100, "alias_name": "Original"}
    )
    assert session.commits == 0


def test_unchanged_business_and_unpublish_restore_edits_and_delete(db, monkeypatch):
    _locked_customer(db)
    person = _person()
    session = _PersonSession(db, person)

    other = _person(pid=708, business=10)
    person_service._assert_distribution_snapshot_person_editable(
        _PersonSession(db, other), other, {"alias_name": "Other name"}
    )
    person_service._assert_distribution_snapshot_person_editable(
        _PersonSession(db, _person(pid=707, business=11)),
        _person(pid=707, business=11),
        {"mobile": "09129999999"},
    )

    distribution_service.unpublish_daily_plan(db, 10, 20, DAY)
    monkeypatch.setattr(person_service, "invalidate_persons_cache", lambda *_args, **_kw: None)
    monkeypatch.setattr(person_service, "_person_to_dict", lambda row: {"alias_name": row.alias_name})
    from app.services.workflow import workflow_trigger_service
    monkeypatch.setattr(workflow_trigger_service, "trigger_person_updated", lambda **_kw: None)

    person_service.update_person(session, 707, 10, PersonUpdateRequest(alias_name="Allowed"))
    assert person.alias_name == "Allowed" and session.commits == 1

    monkeypatch.setattr(person_service, "check_person_has_accounting_documents", lambda *_: (False, []))
    assert person_service.delete_person(session, 707, 10) == (True, None)
    assert session.deletes == 1
