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
        ):
            connection.execute(CreateTable(table, include_foreign_key_constraints=[]))
    monkeypatch.setattr(distribution, "_ensure_plugin", lambda *_args, **_kwargs: None)
    monkeypatch.setattr(distribution, "_ensure_route_allowed_for_strict", lambda *_args, **_kwargs: None)
    monkeypatch.setattr(distribution, "get_plan_lock", lambda *_args, **_kwargs: None)
    monkeypatch.setattr(distribution, "_get_plan_visit_progress", lambda *_args, **_kwargs: {})
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


def test_daily_plan_excludes_foreign_route_and_corrupt_customer_stop(db):
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


def _add_locked_snapshot(db, monkeypatch, items):
    """Exercise the real locked get_daily_plan branch, not a fake getter."""
    lock = DistributionDailyPlanLock(
        business_id=10,
        user_id=20,
        plan_date=DAY,
        is_locked=True,
        published_by_user_id=1,
        published_at=datetime.utcnow(),
        plan_snapshot={
            "user_id": 20,
            "plan_date": DAY.isoformat(),
            "items": items,
            "scheduled_count": len(items),
            "carried_over_count": 0,
        },
    )
    db.add(lock)
    db.commit()
    monkeypatch.setattr(
        distribution,
        "get_plan_lock",
        lambda session, business_id, user_id, plan_date: session.query(
            DistributionDailyPlanLock
        ).filter(
            DistributionDailyPlanLock.business_id == business_id,
            DistributionDailyPlanLock.user_id == user_id,
            DistributionDailyPlanLock.plan_date == plan_date,
        ).first(),
    )
    return lock


def _published_stop(*, person_id=707, route_id=99, stop_id=1, **additional):
    return {
        "person_id": person_id,
        "route_id": route_id,
        "stop_id": stop_id,
        "person_name": "Original frozen customer name",
        "person_mobile": "09111111111",
        **additional,
    }


def test_valid_locked_snapshot_preserves_original_person_fields(db, monkeypatch):
    original = _published_stop()
    lock = _add_locked_snapshot(db, monkeypatch, [original])
    first = distribution.get_daily_plan(db, 10, 20, DAY)
    assert first["locked"] is True
    assert first["items"] == [original]

    # A legitimate CRM edit does not rewrite an immutable publication;
    # ownership IDs are checked but display data remains the saved copy.
    db.get(Person, 707).alias_name = "Edited after publication"
    db.commit()
    second = distribution.get_daily_plan(db, 10, 20, DAY)
    assert second["items"] == [original]
    second["items"][0]["person_name"] = "Caller-mutated copy"
    assert lock.plan_snapshot["items"][0]["person_name"] == "Original frozen customer name"


@pytest.mark.parametrize("item", [
    _published_stop(person_id=808, stop_id=2),       # foreign person linked to own route
    _published_stop(person_id=808, route_id=100, stop_id=3),  # foreign route
    _published_stop(person_id=707, stop_id=2),       # forged customer for an existing stop
    _published_stop(person_id=707, route_id=100),    # forged route for a real stop
    _published_stop(person_id=707, stop_id=3),       # foreign route stop
    _published_stop(person_id=707, stop_id=99999),   # deleted/unknown stop
    _published_stop(person_id=707, stop_id="1"),     # malformed JSON identifier
    _published_stop(person_id=707, stop_id=True),    # booleans are not integer IDs
    _published_stop(person_id="707"),                # ID coercion is not permitted
    _published_stop(route_id=None),                  # incomplete snapshot
    {"person_name": "Unscoped legacy value"},       # old forged data
])
def test_locked_snapshot_rejects_foreign_missing_or_forged_links(db, monkeypatch, item):
    # Each corrupt item must fail independently, not only because a good
    # item in the same fixture happens to duplicate its stop ID.
    _add_locked_snapshot(db, monkeypatch, [item])
    from app.core.responses import ApiError

    with pytest.raises(ApiError) as error:
        distribution.get_daily_plan(db, 10, 20, DAY)
    assert (error.value.code, error.value.status_code) == ("CONFLICT", 409)


def test_locked_snapshot_rejects_duplicate_stops(db, monkeypatch):
    _add_locked_snapshot(db, monkeypatch, [_published_stop(), _published_stop()])
    from app.core.responses import ApiError

    with pytest.raises(ApiError) as error:
        distribution.get_daily_plan(db, 10, 20, DAY)
    assert (error.value.code, error.value.status_code) == ("CONFLICT", 409)


def test_locked_snapshot_rejects_route_not_assigned_to_visitor(db, monkeypatch):
    # An in-business route can still be forbidden if this visitor was never
    # assigned to it on the published day.
    db.add(DistributionRoute(id=101, business_id=10, code="R-101", name="Other local route", is_active=True))
    db.flush()
    db.add(DistributionRouteStop(id=4, route_id=101, person_id=707, weekday=0))
    db.commit()
    _add_locked_snapshot(db, monkeypatch, [_published_stop(route_id=101, stop_id=4)])
    from app.core.responses import ApiError

    with pytest.raises(ApiError) as error:
        distribution.get_daily_plan(db, 10, 20, DAY)
    assert (error.value.code, error.value.status_code) == ("CONFLICT", 409)


def test_empty_locked_snapshot_does_not_require_route_assignments(db, monkeypatch):
    _add_locked_snapshot(db, monkeypatch, [])
    db.query(DistributionRouteAssignment).delete()
    db.commit()
    plan = distribution.get_daily_plan(db, 10, 20, DAY)
    assert plan["items"] == []
    assert plan["locked"] is True


def test_mixed_locked_snapshot_fails_entire_response_without_disclosing_foreign_pii(
    db, monkeypatch,
):
    _add_locked_snapshot(
        db, monkeypatch,
        [_published_stop(), _published_stop(person_id=808, stop_id=2, person_mobile="FOREIGN-SECRET")],
    )
    from app.core.responses import ApiError
    with pytest.raises(ApiError) as error:
        distribution.get_daily_plan(db, 10, 20, DAY)
    assert (error.value.code, error.value.status_code) == ("CONFLICT", 409)
    assert "FOREIGN-SECRET" not in str(error.value)


def _assert_no_implicit_settings_creation(db, monkeypatch):
    """Exercise the real read-only selector and forbid premature commits."""
    monkeypatch.setattr(
        distribution,
        "get_distribution_settings_row",
        lambda session, business_id: session.query(DistributionBusinessSettings).filter(
            DistributionBusinessSettings.business_id == business_id,
        ).first(),
    )
    monkeypatch.setattr(
        distribution,
        "get_or_create_distribution_settings",
        lambda *_args: pytest.fail("Read-only operation must never initialize settings"),
    )
    monkeypatch.setattr(
        db,
        "commit",
        lambda: pytest.fail("Rejected operation must not commit partial settings"),
    )


def test_rejected_visit_does_not_create_or_commit_missing_settings(db, monkeypatch):
    from app.core.responses import ApiError

    _assert_no_implicit_settings_creation(db, monkeypatch)
    monkeypatch.setattr(distribution, "business_today", lambda *_args: DAY)
    assert db.get(DistributionBusinessSettings, 10) is None
    with pytest.raises(ApiError) as error:
        distribution.start_visit(
            db, 10, 20,
            {"person_id": 707, "route_id": 100},  # route belongs to business 11
        )
    assert (error.value.code, error.value.status_code) == ("VALIDATION_ERROR", 400)
    assert db.get(DistributionBusinessSettings, 10) is None
    assert db.query(DistributionFieldVisit).count() == 0


def test_rejected_offline_pack_does_not_create_or_commit_settings(db, monkeypatch):
    from app.core.responses import ApiError

    _assert_no_implicit_settings_creation(db, monkeypatch)
    monkeypatch.setattr(field_ops, "business_today", lambda *_args: DAY)
    monkeypatch.setattr(
        distribution, "get_daily_plan",
        lambda *_args: {"plan_date": DAY.isoformat(), "items": [{"person_id": 808}]},
    )
    assert db.get(DistributionBusinessSettings, 10) is None
    with pytest.raises(ApiError) as error:
        field_ops.build_offline_pack(
            db, 10, SimpleNamespace(get_user_id=lambda: 20),
        )
    assert (error.value.code, error.value.status_code) == ("CONFLICT", 409)
    assert db.get(DistributionBusinessSettings, 10) is None


def test_read_only_default_settings_do_not_create_row(db, monkeypatch):
    _assert_no_implicit_settings_creation(db, monkeypatch)
    result = distribution.settings_for_read(db, 10)
    assert result["require_visit_in_daily_plan"] is False
    assert result["carry_over_days"] == 7
    assert db.get(DistributionBusinessSettings, 10) is None


def _add_second_local_optimization_stop(db):
    db.execute(sa.insert(Person.__table__), [
        dict(id=709, business_id=10, alias_name="Another local customer",
             person_types="[]", mobile="09133333333",
             latitude=35.8, longitude=51.8),
    ])
    db.add(DistributionRouteStop(
        id=4, route_id=99, person_id=709, weekday=0, sort_order=3,
    ))
    db.commit()


def test_route_optimizer_excludes_foreign_tenant_name_coordinates_and_stop(db):
    _add_second_local_optimization_stop(db)

    result = phase3.optimize_route_plan(db, 10, 99, DAY)
    assert result["optimized"] is True
    assert {row["person_id"] for row in result["items"]} == {707, 709}
    assert {row["stop_id"] for row in result["items"]} == {1, 4}
    assert "Tenant ten" in repr(result)
    assert "Another local customer" in repr(result)
    assert "Tenant eleven SECRET" not in repr(result)
    assert "36.5" not in repr(result)
    assert "52.5" not in repr(result)
    assert "808" not in repr(result)


def test_saved_route_optimization_only_persists_business_owned_stop_ids(db):
    _add_second_local_optimization_stop(db)

    result = phase3.apply_route_optimize(db, 10, 99, DAY)
    assert result["persisted"] is True
    assert {row["stop_id"] for row in result["items"]} == {1, 4}
    override = db.get(DistributionRoute, 99).plan_sort_overrides[DAY.isoformat()]
    assert set(override) == {"1", "4"}
    assert "2" not in override  # Corrupt foreign-customer stop is never saved.


def test_route_optimization_locks_before_reading_stops(db, monkeypatch):
    order = []
    monkeypatch.setattr(
        distribution, "assert_route_has_no_locked_plans",
        lambda *_args, **_kwargs: order.append("lock"),
    )

    def staged_optimizer(*_args, **_kwargs):
        order.append("read")
        return {"items": [], "optimized": False}

    monkeypatch.setattr(phase3, "optimize_route_plan", staged_optimizer)
    result = phase3.apply_route_optimize(db, 10, 99, DAY)
    assert result["persisted"] is False
    assert order == ["lock", "read"]


def test_locked_route_optimizer_rejects_before_calculating_any_stops(db, monkeypatch):
    from app.core.responses import ApiError

    db.add(DistributionDailyPlanLock(
        business_id=10, user_id=20, plan_date=DAY,
        is_locked=True, published_at=datetime.utcnow(),
    ))
    db.commit()
    monkeypatch.setattr(
        phase3, "optimize_route_plan",
        lambda *_args, **_kwargs: pytest.fail(
            "Locked route must be rejected before calculating stops"
        ),
    )
    with pytest.raises(ApiError) as error:
        phase3.apply_route_optimize(db, 10, 99, DAY)
    assert (error.value.code, error.value.status_code) == ("CONFLICT", 409)
    assert db.get(DistributionRoute, 99).plan_sort_overrides is None


def test_optimizer_rejects_foreign_business_route_without_customer_info(db):
    from app.core.responses import ApiError

    with pytest.raises(ApiError) as error:
        phase3.optimize_route_plan(db, 10, 100, DAY)
    assert (error.value.code, error.value.status_code) == ("NOT_FOUND", 404)
    assert "Tenant eleven SECRET" not in str(error.value)


def test_territory_delete_rejects_invalid_foreign_route_reference_before_write(db, monkeypatch):
    """ORM territory relationship deletes must never detach another tenant's route."""
    from app.services import sepidar_plugin_service
    from app.core.responses import ApiError

    monkeypatch.setattr(
        sepidar_plugin_service, "assert_plugin_entity_editable",
        lambda *_args: None,
    )
    territory = DistributionTerritory(
        id=17, business_id=10, code="T-17", name="Local territory",
    )
    db.add(territory)
    db.commit()
    db.get(DistributionRoute, 99).territory_id = 17
    # Corrupt legacy route FK: a foreign route points to our territory.
    db.get(DistributionRoute, 100).territory_id = 17
    db.commit()

    with pytest.raises(ApiError) as error:
        distribution.delete_territory(db, 10, 17)
    assert (error.value.code, error.value.status_code) == ("CONFLICT", 409)
    assert db.get(DistributionTerritory, 17) is not None
    assert db.get(DistributionRoute, 99).territory_id == 17
    assert db.get(DistributionRoute, 100).territory_id == 17


def test_territory_delete_detaches_only_local_routes_without_foreign_links(db, monkeypatch):
    from app.services import sepidar_plugin_service

    monkeypatch.setattr(
        sepidar_plugin_service, "assert_plugin_entity_editable",
        lambda *_args: None,
    )
    db.add(DistributionTerritory(
        id=17, business_id=10, code="T-17", name="Local territory",
    ))
    db.commit()
    db.get(DistributionRoute, 99).territory_id = 17
    db.commit()

    distribution.delete_territory(db, 10, 17)
    assert db.get(DistributionTerritory, 17) is None
    assert db.get(DistributionRoute, 99).territory_id is None
    assert db.get(DistributionRoute, 100).business_id == 11
    assert db.get(DistributionRoute, 100).territory_id is None
