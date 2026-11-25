"""Prevent mutation of scheduling inputs while immutable daily plans exist.

The publication lock check must run before any insert/commit, remain scoped to
the current business, and not block unrelated display/telemetry preferences.
SQLite exercises the guard; PostgreSQL/MSSQL transaction lock primitives are
validated by dedicated CI suites.
"""

from __future__ import annotations

from datetime import date, datetime

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import Session

from adapters.db.models.distribution import (
    DistributionBusinessSettings,
    DistributionDailyPlanLock,
)
from app.core.responses import ApiError
from app.services import distribution_service as svc


@pytest.fixture()
def db(monkeypatch):
    monkeypatch.setattr(svc, "_ensure_plugin", lambda *_a, **_k: None)
    engine = create_engine("sqlite+pysqlite:///:memory:")
    DistributionBusinessSettings.__table__.create(engine)
    DistributionDailyPlanLock.__table__.create(engine)
    with Session(engine) as session:
        yield session
    engine.dispose()


def published(db, business_id: int, *, user_id: int = 20, locked: bool = True):
    row = DistributionDailyPlanLock(
        business_id=business_id,
        user_id=user_id,
        plan_date=date(2026, 11, 23),
        is_locked=locked,
        published_by_user_id=1,
        published_at=datetime.utcnow(),
    )
    db.add(row)
    db.commit()
    return row


@pytest.mark.parametrize("change", [
    {"carry_over_missed_visits": False},
    {"carry_over_days": 14},
    {"carry_over_days": 14, "share_live_location": False},
])
def test_locked_business_rejects_plan_input_change_without_creating_settings(db, change):
    published(db, 10)
    with pytest.raises(ApiError) as raised:
        svc.update_distribution_settings(db, 10, change)
    assert (raised.value.code, raised.value.status_code) == ("CONFLICT", 409)
    assert db.get(DistributionBusinessSettings, 10) is None
    assert db.query(DistributionDailyPlanLock).count() == 1


def test_locked_business_allows_unrelated_telemetry_setting(db):
    published(db, 10)
    result = svc.update_distribution_settings(db, 10, {"share_live_location": False})
    assert result["share_live_location"] is False
    assert db.get(DistributionBusinessSettings, 10).share_live_location is False
    assert db.query(DistributionDailyPlanLock).count() == 1


def test_other_business_lock_does_not_block_this_business(db):
    published(db, 11)
    result = svc.update_distribution_settings(
        db, 10, {"carry_over_missed_visits": False, "carry_over_days": 10}
    )
    assert result["carry_over_missed_visits"] is False
    assert result["carry_over_days"] == 10
    assert db.get(DistributionBusinessSettings, 11) is None


def test_unlocked_publication_does_not_reject_schedule_edits(db):
    published(db, 10, locked=False)
    result = svc.update_distribution_settings(db, 10, {"carry_over_days": 21})
    assert result["carry_over_days"] == 21


def test_unpublish_allows_scheduling_policy_change(db):
    lock = published(db, 10)
    with pytest.raises(ApiError):
        svc.update_distribution_settings(db, 10, {"carry_over_days": 9})
    db.delete(lock)
    db.commit()
    result = svc.update_distribution_settings(db, 10, {"carry_over_days": 9})
    assert result["carry_over_days"] == 9


def test_failed_new_settings_input_does_not_commit_partial_row(db):
    with pytest.raises((TypeError, ValueError)):
        svc.update_distribution_settings(db, 10, {"carry_over_days": "invalid"})
    db.rollback()
    assert db.get(DistributionBusinessSettings, 10) is None


def test_unrelated_edit_does_not_request_schedule_lock(db, monkeypatch):
    def cannot_lock(*_args, **_kwargs):
        raise AssertionError("Unrelated settings must not lock plan catalogue")

    monkeypatch.setattr(svc, "_serialize_distribution_plan_mutation", cannot_lock)
    result = svc.update_distribution_settings(db, 10, {"share_live_location": False})
    assert result["share_live_location"] is False
