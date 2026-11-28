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
    DistributionUserPreference,
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
            DistributionUserPreference.__table__,
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

def test_route_list_masks_foreign_territory_name_and_identifier(db, monkeypatch):
    # A route in business 10 may have a stale invalid territory FK to
    # business 11. Do not materialize the ORM relationship and leak its name.
    monkeypatch.setattr(
        distribution, "_use_strict_catalog_for_field_user",
        lambda *_args: False,
    )
    db.add_all([
        DistributionTerritory(id=17, business_id=10, code="T-10", name="Own territory"),
        DistributionTerritory(id=18, business_id=11, code="T-11", name="FOREIGN-TERRITORY-SECRET"),
        DistributionRoute(id=102, business_id=10, code="R-102",
                          name="Corrupted local route", territory_id=18),
    ])
    db.flush()
    db.get(DistributionRoute, 99).territory_id = 17
    db.commit()

    routes = distribution.list_routes(db, 10, SimpleNamespace(has_business_permission=lambda *_a: False))
    result = {route["id"]: route for route in routes}
    assert set(result) == {99, 102}
    assert result[99]["territory_id"] == 17
    assert result[99]["territory_name"] == "Own territory"
    assert result[102]["territory_id"] is None
    assert result[102]["territory_name"] is None
    assert "FOREIGN-TERRITORY-SECRET" not in repr(routes)
    assert "18" not in repr(result[102]["territory_id"])


def test_team_map_masks_cross_tenant_legacy_visit_person_without_writes(db, monkeypatch):
    from app.services import distribution_documents as docs

    monkeypatch.setattr(
        distribution, "_can_see_team_distribution", lambda *_args: True,
    )
    monkeypatch.setattr(docs, "user_label", lambda _db, uid: f"Visitor {uid}")
    monkeypatch.setattr(distribution, "scoped_user_ids_for_ctx", lambda *_a: None)
    monkeypatch.setattr(
        phase3, "business_day_utc_bounds",
        lambda *_args: (datetime(2026, 11, 23), datetime(2026, 11, 24)),
    )
    db.add_all([
        DistributionFieldVisit(
            id=21, business_id=10, person_id=808, user_id=20,
            route_id=99, status="in_progress",
            started_at=datetime(2026, 11, 23, 9),
            start_latitude=35.1, start_longitude=51.1,
        ),
        DistributionFieldVisit(
            id=22, business_id=10, person_id=707, user_id=21,
            route_id=99, status="completed",
            started_at=datetime(2026, 11, 23, 10),
            ended_at=datetime(2026, 11, 23, 11),
            start_latitude=35.2, start_longitude=51.2,
            end_latitude=35.2, end_longitude=51.2,
        ),
    ])
    db.commit()
    # Read-only map must neither create settings nor commit the transaction.
    monkeypatch.setattr(
        distribution, "get_or_create_distribution_settings",
        lambda *_args: pytest.fail("Team map must never initialize settings"),
    )
    monkeypatch.setattr(
        db, "commit", lambda: pytest.fail("Team map must not commit"),
    )
    result = phase3.get_team_map(db, 10, object(), DAY)
    by_user = {item["user_id"]: item for item in result["visitors"]}
    assert by_user[20]["visit_id"] == 21
    assert by_user[20]["person_id"] is None
    assert by_user[20]["person_name"] is None
    assert by_user[20]["customer_latitude"] is None
    assert by_user[20]["customer_longitude"] is None
    assert by_user[21]["person_id"] == 707
    assert by_user[21]["person_name"] == "Tenant ten"
    assert {x["person_id"] for x in result["customers"]} == {707}
    assert {x["person_id"] for x in result["markers"]} == {707}
    assert result["share_live_location"] is False
    assert by_user[20]["latitude"] is None
    assert by_user[20]["live_allowed"] is False
    monkeypatch.setattr(distribution, "scoped_user_ids_for_ctx", lambda *_a: {20})
    scoped = phase3.get_team_map(db, 10, object(), DAY)
    assert {x["user_id"] for x in scoped["visitors"]} == {20}
    assert scoped["customers"] == []
    assert "Tenant eleven SECRET" not in repr(result)
    assert "36.5" not in repr(result)
    assert "52.5" not in repr(result)
    assert "808" not in repr(result)


def test_route_update_does_not_expose_foreign_territory_or_prevent_repair(db, monkeypatch):
    from app.services import sepidar_plugin_service

    monkeypatch.setattr(
        sepidar_plugin_service, "assert_plugin_entity_editable",
        lambda *_args: None,
    )
    db.add(DistributionTerritory(
        id=18, business_id=11, code="T-FOREIGN",
        name="FOREIGN-TERRITORY-SECRET",
    ))
    db.commit()
    db.get(DistributionRoute, 99).territory_id = 18
    db.commit()

    result = distribution.update_route(db, 10, 99, {"name": "Valid local rename"})
    assert result["name"] == "Valid local rename"
    assert result["territory_id"] is None
    assert result["territory_name"] is None
    assert "FOREIGN-TERRITORY-SECRET" not in repr(result)

    repaired = distribution.update_route(db, 10, 99, {"territory_id": None})
    assert repaired["territory_id"] is None
    assert db.get(DistributionRoute, 99).territory_id is None
    assert db.get(DistributionTerritory, 18).name == "FOREIGN-TERRITORY-SECRET"


def _seed_legacy_visit_links(db):
    db.add_all([
        DistributionFieldVisit(
            id=31, business_id=10, person_id=808, user_id=20,
            route_id=99, status="in_progress",
            started_at=datetime(2026, 11, 23, 9),
        ),
        DistributionFieldVisit(
            id=32, business_id=10, person_id=707, user_id=21,
            route_id=99, status="in_progress",
            started_at=datetime(2026, 11, 23, 10),
        ),
        DistributionFieldVisit(
            id=33, business_id=11, person_id=707, user_id=30,
            route_id=100, status="in_progress",
            started_at=datetime(2026, 11, 23, 11),
        ),
    ])
    db.commit()


def test_visit_list_masks_foreign_customer_identity_on_corrupt_legacy_link(db, monkeypatch):
    _seed_legacy_visit_links(db)
    monkeypatch.setattr(
        distribution, "scoped_user_ids_for_ctx", lambda *_args: None,
    )
    rows, total = distribution.list_visits(
        db, 10, SimpleNamespace(get_user_id=lambda: 20), None, None, 100, 0,
    )
    by_id = {row["id"]: row for row in rows}
    assert total == 2
    assert by_id[31]["person_id"] is None
    assert by_id[31]["person_name"] is None
    assert by_id[32]["person_id"] == 707
    assert by_id[32]["person_name"] == "Tenant ten"
    assert "Tenant eleven SECRET" not in repr(rows)
    assert "808" not in repr(rows)


def test_cancel_visit_masks_foreign_customer_identity_on_corrupt_legacy_link(db):
    _seed_legacy_visit_links(db)
    result = distribution.cancel_visit(db, 10, 20, 31, "no access")
    assert result["status"] == "cancelled"
    assert result["person_id"] is None
    assert result["person_name"] is None
    assert "Tenant eleven SECRET" not in repr(result)
    assert db.get(DistributionFieldVisit, 33).status == "in_progress"


def test_return_request_list_masks_corrupt_foreign_customer_name_and_id(db, monkeypatch):
    from app.services import distribution_documents

    monkeypatch.setattr(
        distribution, "scoped_user_ids_for_ctx", lambda *_args: None,
    )
    monkeypatch.setattr(
        distribution_documents, "user_label", lambda _db, uid: f"Visitor {uid}",
    )
    db.add_all([
        DistributionReturnRequest(
            id=41, business_id=10, person_id=808, created_by_user_id=20,
            lines=[{"product_id": 7, "quantity": 1}], status="pending",
        ),
        DistributionReturnRequest(
            id=42, business_id=10, person_id=707, created_by_user_id=20,
            lines=[{"product_id": 7, "quantity": 1}], status="pending",
        ),
    ])
    db.commit()
    rows = distribution.list_return_requests(db, 10, object(), None)
    by_id = {row["id"]: row for row in rows}
    assert by_id[41]["person_id"] is None
    assert by_id[41]["person_name"] is None
    assert by_id[42]["person_id"] == 707
    assert by_id[42]["person_name"] == "Tenant ten"
    assert "Tenant eleven SECRET" not in repr(rows)
    assert "808" not in repr(rows)


@pytest.mark.parametrize("bad_visit_id,expected_code,expected_http", [
    (31, "NOT_FOUND", 404),  # local visit, but references foreign customer
    (33, "NOT_FOUND", 404),  # different business's visit, same person_id
    ("not-an-integer", "VALIDATION_ERROR", 400),
    (-1, "VALIDATION_ERROR", 400),
])
def test_return_request_does_not_link_mismatched_or_foreign_visit(
    db, monkeypatch, bad_visit_id, expected_code, expected_http,
):
    from app.core.responses import ApiError

    _seed_legacy_visit_links(db)
    monkeypatch.setattr(
        distribution, "_validate_return_lines", lambda _db, _bid, lines: lines,
    )
    monkeypatch.setattr(db, "commit", lambda: pytest.fail("Invalid return must not commit"))
    with pytest.raises(ApiError) as error:
        distribution.create_return_request(
            db, 10, 20,
            {"person_id": 707, "visit_id": bad_visit_id,
             "lines": [{"product_id": 7, "quantity": 1}]},
        )
    assert (error.value.code, error.value.status_code) == (expected_code, expected_http)
    assert db.query(DistributionReturnRequest).count() == 0
    assert db.get(DistributionBusinessSettings, 10) is None


def test_return_request_accepts_valid_same_tenant_visit(db, monkeypatch):
    _seed_legacy_visit_links(db)
    monkeypatch.setattr(
        distribution, "_validate_return_lines", lambda _db, _bid, lines: lines,
    )
    created = distribution.create_return_request(
        db, 10, 20,
        {"person_id": 707, "visit_id": 32,
         "lines": [{"product_id": 7, "quantity": 1}]},
    )
    assert created["visit_id"] == 32
    assert created["person_id"] == 707
    assert db.query(DistributionReturnRequest).count() == 1


@pytest.mark.parametrize("payload", [
    {"customer_class": "A"}, {"visit_frequency": "monthly"},
    {"cycle_offset": 2}, {"owner_user_id": 21},
])
def test_locked_customer_profile_fields_are_rejected_before_write(db, payload):
    from app.core.responses import ApiError
    db.add(DistributionDailyPlanLock(
        business_id=10, user_id=20, plan_date=DAY, is_locked=True,
        published_by_user_id=1, published_at=datetime.utcnow(),
    ))
    db.commit()
    with pytest.raises(ApiError) as error:
        field_ops.upsert_customer_profile(db, 10, 707, payload)
    assert error.value.status_code == 409
    assert db.query(DistributionCustomerProfile).count() == 0
