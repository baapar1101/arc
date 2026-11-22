"""Regression for locked daily plans and their route/assignment mutation guards."""

from __future__ import annotations

from datetime import date, datetime

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import Session

from adapters.db.models.distribution import (
    DistributionDailyPlanLock,
    DistributionTerritory,
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
        DistributionTerritory.__table__,
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


def test_visit_attribution_matches_one_daily_plan_entry():
    from app.services.distribution_service import assert_visit_matches_daily_plan

    plan = {
        "items": [
            {"person_id": 707, "route_id": 99, "stop_id": 10},
            {"person_id": 707, "route_id": 100, "stop_id": 11},
            {"person_id": 808, "route_id": 99, "stop_id": 12},
        ]
    }
    assert_visit_matches_daily_plan(plan, 707)
    assert_visit_matches_daily_plan(plan, 707, route_id=99)
    assert_visit_matches_daily_plan(plan, 707, route_stop_id=11)
    assert_visit_matches_daily_plan(plan, 707, route_id=99, route_stop_id=10)

    with pytest.raises(ApiError):
        assert_visit_matches_daily_plan(plan, 999)
    with pytest.raises(ApiError):
        assert_visit_matches_daily_plan(plan, 707, route_id=101)
    with pytest.raises(ApiError):
        assert_visit_matches_daily_plan(plan, 707, route_stop_id=12)
    with pytest.raises(ApiError):
        assert_visit_matches_daily_plan(plan, 707, route_id=99, route_stop_id=11)


def test_visit_attribution_handles_invalid_or_corrupt_day_plan():
    from app.services.distribution_service import assert_visit_matches_daily_plan

    with pytest.raises(ApiError):
        assert_visit_matches_daily_plan({"items": None}, 707)
    with pytest.raises(ApiError):
        assert_visit_matches_daily_plan({}, 707)
    with pytest.raises(ApiError):
        assert_visit_matches_daily_plan(
            {"items": [{"person_id": "invalid"}, None, "bad"]}, 707
        )


@pytest.mark.parametrize(
    ("required", "locked"),
    [(True, False), (False, True)],
)
def test_start_visit_rejects_mismatched_day_plan_route_before_writing(
    monkeypatch, required, locked,
):
    from types import SimpleNamespace

    class _FakeQuery:
        def filter(self, *_args):
            return self

        def first(self):
            return SimpleNamespace(id=707, business_id=10)

    class _FakeDb:
        def query(self, _model):
            return _FakeQuery()

    monkeypatch.setattr(svc, "_ensure_plugin", lambda *_args: None)
    monkeypatch.setattr(svc, "_active_visit", lambda *_args: None)
    monkeypatch.setattr(svc, "business_today", lambda *_args: DAY)
    monkeypatch.setattr(
        svc, "get_or_create_distribution_settings",
        lambda *_args: SimpleNamespace(require_visit_in_daily_plan=required),
    )
    monkeypatch.setattr(
        svc, "get_plan_lock",
        lambda *_args: SimpleNamespace(is_locked=True) if locked else None,
    )
    monkeypatch.setattr(
        svc, "get_daily_plan",
        lambda *_args: {
            "items": [{"person_id": 707, "route_id": 99, "stop_id": 10}],
        },
    )

    with pytest.raises(ApiError):
        svc.start_visit(
            _FakeDb(), 10, 20,
            {"person_id": 707, "route_id": 99, "route_stop_id": 12},
        )


def test_supervisor_assignment_requires_manager_access():
    from app.services.distribution_service import validate_visit_supervisor_assignment

    class FakeContext:
        db = None

        def __init__(self, permissions=(), superadmin=False):
            self.permissions = set(permissions)
            self.superadmin = superadmin

        def is_superadmin(self):
            return self.superadmin

        def has_business_permission(self, section, action):
            return (section, action) in self.permissions

    visitor = FakeContext({("distribution", "operate"), ("distribution", "reports_team")})
    manager = FakeContext({("distribution", "manage")})
    admin = FakeContext(superadmin=True)

    assert validate_visit_supervisor_assignment(None, visitor, 10) is None
    with pytest.raises(ApiError):
        validate_visit_supervisor_assignment(99, visitor, 10)
    with pytest.raises(ApiError):
        validate_visit_supervisor_assignment(99, None, 10)
    assert validate_visit_supervisor_assignment(99, manager, 10) == 99
    assert validate_visit_supervisor_assignment(99, admin, 10) == 99


def test_start_visit_accepts_matching_locked_plan_attribution(monkeypatch):
    from types import SimpleNamespace

    class FakeQuery:
        def __init__(self, model):
            self.model = model

        def filter(self, *_args):
            return self

        def first(self):
            if self.model.__name__ == "DistributionRoute":
                return SimpleNamespace(id=99, business_id=10)
            if self.model.__name__ == "DistributionRouteStop":
                return SimpleNamespace(id=10, route_id=99, person_id=707)
            return SimpleNamespace(id=707, business_id=10, alias_name="Client")

    class FakeDb:
        def __init__(self):
            self.added = []
            self.commits = 0

        def query(self, _model):
            return FakeQuery(_model)

        def add(self, instance):
            self.added.append(instance)

        def commit(self):
            self.commits += 1

        def refresh(self, _instance):
            pass

    monkeypatch.setattr(svc, "_ensure_plugin", lambda *_args: None)
    monkeypatch.setattr(svc, "_active_visit", lambda *_args: None)
    monkeypatch.setattr(svc, "business_today", lambda *_args: DAY)
    monkeypatch.setattr(
        svc, "get_or_create_distribution_settings",
        lambda *_args: SimpleNamespace(require_visit_in_daily_plan=False),
    )
    monkeypatch.setattr(
        svc, "get_plan_lock",
        lambda *_args: SimpleNamespace(is_locked=True),
    )
    monkeypatch.setattr(
        svc, "get_daily_plan",
        lambda *_args: {
            "items": [{"person_id": 707, "route_id": 99, "stop_id": 10}],
        },
    )
    monkeypatch.setattr(
        phase3, "validate_geofence_on_start",
        lambda *_args, **_kwargs: {"geofence_warning": None, "distance_meters": None},
    )
    monkeypatch.setattr(
        svc, "visit_to_dict",
        lambda v, _name: {
            "person_id": v.person_id,
            "route_id": v.route_id,
            "route_stop_id": v.route_stop_id,
        },
    )

    db = FakeDb()
    result = svc.start_visit(
        db, 10, 20,
        {"person_id": 707, "route_id": 99, "route_stop_id": 10},
    )
    assert result == {"person_id": 707, "route_id": 99, "route_stop_id": 10}
    assert db.commits == 1
    assert len(db.added) == 1


def test_offline_sync_cannot_bypass_day_plan_stop_validation(monkeypatch):
    from types import SimpleNamespace
    from app.services.distribution_phase3_service import process_offline_sync

    class FakeQuery:
        def __init__(self, model):
            self.model = model

        def filter(self, *_args):
            return self

        def first(self):
            if self.model.__name__ == "Person":
                return SimpleNamespace(id=707, business_id=10)
            return None

    class FakeDb:
        def __init__(self):
            self.added = []
            self.commits = 0

        def query(self, model):
            return FakeQuery(model)

        def add(self, row):
            self.added.append(row)

        def commit(self):
            self.commits += 1

    class FakeContext:
        def has_business_permission(self, section, action):
            return section == "distribution" and action == "operate"

    monkeypatch.setattr(svc, "_ensure_plugin", lambda *_args: None)
    monkeypatch.setattr(svc, "_active_visit", lambda *_args: None)
    monkeypatch.setattr(svc, "business_today", lambda *_args: DAY)
    monkeypatch.setattr(
        svc,
        "get_or_create_distribution_settings",
        lambda *_args: SimpleNamespace(require_visit_in_daily_plan=True),
    )
    monkeypatch.setattr(svc, "get_plan_lock", lambda *_args: None)
    monkeypatch.setattr(
        svc,
        "get_daily_plan",
        lambda *_args: {
            "items": [{"person_id": 707, "route_id": 99, "stop_id": 10}],
        },
    )

    db = FakeDb()
    outcome = process_offline_sync(
        db,
        business_id=10,
        user_id=20,
        client_batch_id="invalid-visit-attribution",
        actions=[{
            "op": "start_visit",
            "client_ref": "visit-1",
            "payload": {"person_id": 707, "route_id": 99, "route_stop_id": 12},
        }],
        ctx=FakeContext(),
    )

    assert outcome["results"][0]["ok"] is False
    assert "visit_id" not in outcome["results"][0]
    assert db.commits == 1  # Sync result recorded; no visit is created.
    assert len(db.added) == 1
    assert db.added[0].__class__.__name__ == "DistributionOfflineSyncBatch"


def test_free_form_visit_route_attribution_is_business_scoped(db):
    # Without a required day plan, route and stop FK attribution must still be
    # coherent; free visits with neither field stay supported.
    from app.services.distribution_service import validate_visit_route_attribution

    setup_route(db, business_id=10, route_id=99, user_id=20, locked=False)
    setup_route(db, business_id=11, route_id=100, user_id=30, locked=False)
    db.add_all([
        DistributionRouteStop(route_id=99, person_id=707, sort_order=1),
        DistributionRouteStop(route_id=100, person_id=808, sort_order=1),
    ])
    db.commit()
    stop_local = db.query(DistributionRouteStop).filter_by(route_id=99).one()
    stop_other = db.query(DistributionRouteStop).filter_by(route_id=100).one()

    assert validate_visit_route_attribution(db, 10, 707, None, None) == (None, None)
    assert validate_visit_route_attribution(db, 10, 707, 99, None) == (99, None)
    assert validate_visit_route_attribution(db, 10, 707, None, stop_local.id) == (99, stop_local.id)
    assert validate_visit_route_attribution(db, 10, 707, 99, stop_local.id) == (99, stop_local.id)

    with pytest.raises(ApiError):  # foreign business
        validate_visit_route_attribution(db, 10, 808, 100, stop_other.id)
    with pytest.raises(ApiError):  # foreign business even without a stop
        validate_visit_route_attribution(db, 10, 707, 100, None)
    with pytest.raises(ApiError):  # correct stop, wrong customer
        validate_visit_route_attribution(db, 10, 808, 99, stop_local.id)
    with pytest.raises(ApiError):  # stop and route IDs disagree
        validate_visit_route_attribution(db, 10, 707, 100, stop_local.id)
    with pytest.raises(ApiError):  # unknown stop
        validate_visit_route_attribution(db, 10, 707, 99, 999999)


def test_locked_plan_blocks_territory_edit_and_delete_until_unpublished(db, monkeypatch):
    """A territory edit must not bypass protection on its linked route."""
    from app.services import sepidar_plugin_service

    monkeypatch.setattr(sepidar_plugin_service, "assert_plugin_entity_editable", lambda *_: None)
    route = setup_route(db)
    db.add(DistributionTerritory(id=17, business_id=10, code="T-17", name="Original"))
    db.add(DistributionTerritory(id=18, business_id=11, code="T-18", name="Other business"))
    db.commit()
    route.territory_id = 17
    db.commit()

    with pytest.raises(ApiError):
        svc.update_territory(db, 10, 17, {"name": "Must not change"})
    with pytest.raises(ApiError):
        svc.delete_territory(db, 10, 17)
    assert db.get(DistributionTerritory, 17).name == "Original"
    assert db.get(DistributionRoute, 99).territory_id == 17

    # Neither another business nor an unlocked publication is blocked.
    other = svc.update_territory(db, 11, 18, {"name": "Allowed elsewhere"})
    assert other["name"] == "Allowed elsewhere"
    svc.unpublish_daily_plan(db, 10, 20, DAY)
    renamed = svc.update_territory(db, 10, 17, {"name": "Allowed after unpublish"})
    assert renamed["name"] == "Allowed after unpublish"


def test_locked_plan_blocks_customer_location_edit_without_mutation(db):
    """Coordinates are part of the saved route-plan snapshot."""
    from types import SimpleNamespace
    from adapters.db.models.person import Person

    setup_route(db)
    db.add(DistributionRouteStop(route_id=99, person_id=707, sort_order=1))
    db.commit()
    person = SimpleNamespace(
        id=707, business_id=10, latitude=35.0, longitude=51.0, updated_at=None,
    )

    class PersonQuery:
        def filter(self, *_args):
            return self

        def first(self):
            return person

    class PersonSession:
        def query(self, model):
            return PersonQuery() if model is Person else db.query(model)

        def get_bind(self):
            return db.get_bind()

        def commit(self):
            db.commit()

    session = PersonSession()
    with pytest.raises(ApiError):
        phase3.update_person_location(session, 10, 707, 36.0, 52.0)
    assert (person.latitude, person.longitude) == (35.0, 51.0)

    # A different customer is unaffected by this guard.
    svc.assert_customer_schedule_unlocked(db, 10, 708)
    svc.assert_customer_schedule_unlocked(db, 11, 707)

    svc.unpublish_daily_plan(db, 10, 20, DAY)
    result = phase3.update_person_location(session, 10, 707, 36.0, 52.0)
    assert result == {"person_id": 707, "latitude": 36.0, "longitude": 52.0}
    assert (person.latitude, person.longitude) == (36.0, 52.0)
