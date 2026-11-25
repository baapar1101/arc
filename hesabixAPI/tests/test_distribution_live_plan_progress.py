"""Live visit status must not mutate an immutable published day plan."""

from __future__ import annotations

from datetime import date, datetime
from types import SimpleNamespace

from sqlalchemy import create_engine
from sqlalchemy.orm import Session

from adapters.db.models.distribution import DistributionFieldVisit
from app.services import distribution_service as svc


def _visit(person: int, status: str, visit_id: int):
    return SimpleNamespace(person_id=person, status=status, id=visit_id)


def test_progress_uses_newest_valid_visit_for_only_scheduled_people():
    plan_items = [
        {"person_id": 707, "stop_id": 11},
        {"person_id": 808, "stop_id": 12},
        {"stop_id": 13},  # legacy/incomplete item must not crash the overlay
        {"person_id": "not-an-id"},
    ]
    newest_first = [
        _visit(999, "completed", 10),
        _visit(707, "in_progress", 9),
        _visit(707, "completed", 8),
        _visit(808, "cancelled", 7),
        _visit(808, "completed", 6),
    ]
    progress = svc._summarize_visit_progress(newest_first, plan_items)
    assert progress == {
        "707": {"kind": "current", "visit_id": 9},
        "808": {"kind": "done", "visit_id": 6},
    }
    assert "999" not in progress


def test_live_progress_scopes_business_visitor_and_business_day(monkeypatch):
    # Pure integration test: no external API and no production database.
    engine = create_engine("sqlite+pysqlite:///:memory:")
    DistributionFieldVisit.__table__.create(engine)
    day = date(2026, 11, 21)
    monkeypatch.setattr(
        svc,
        "business_day_utc_bounds",
        lambda business_id, plan_date: (
            datetime(2026, 11, 21, 0, 0),
            datetime(2026, 11, 21, 23, 59, 59),
        ),
    )

    with Session(engine) as session:
        session.add_all([
            DistributionFieldVisit(
                id=1, business_id=10, user_id=20, person_id=707,
                status="completed", started_at=datetime(2026, 11, 21, 8),
            ),
            DistributionFieldVisit(
                id=2, business_id=10, user_id=21, person_id=808,
                status="completed", started_at=datetime(2026, 11, 21, 9),
            ),
            DistributionFieldVisit(
                id=3, business_id=11, user_id=20, person_id=808,
                status="completed", started_at=datetime(2026, 11, 21, 10),
            ),
            DistributionFieldVisit(
                id=4, business_id=10, user_id=20, person_id=808,
                status="completed", started_at=datetime(2026, 11, 20, 18),
            ),
            DistributionFieldVisit(
                id=5, business_id=10, user_id=20, person_id=707,
                status="in_progress", started_at=datetime(2026, 11, 21, 11),
            ),
        ])
        session.commit()

        items = [{"person_id": 707}, {"person_id": 808}]
        progress = svc._get_plan_visit_progress(session, 10, 20, day, items)
        assert progress == {"707": {"kind": "current", "visit_id": 5}}
        assert svc._get_plan_visit_progress(session, 10, 21, day, items) == {
            "808": {"kind": "done", "visit_id": 2},
        }
        assert svc._get_plan_visit_progress(session, 10, 20, day, []) == {}
    engine.dispose()


def test_progress_overlay_does_not_modify_published_snapshot(db=None):
    # A saved publication's route data should not gain visit status fields.
    snapshot = {
        "plan_date": "2026-11-21",
        "user_id": 20,
        "items": [{"person_id": 707, "route_id": 99, "stop_id": 11}],
    }
    before = repr(snapshot)
    overlay = svc._summarize_visit_progress(
        [_visit(707, "completed", 123)],
        snapshot["items"],
    )
    assert overlay["707"]["kind"] == "done"
    assert repr(snapshot) == before
    assert "kind" not in snapshot["items"][0]
