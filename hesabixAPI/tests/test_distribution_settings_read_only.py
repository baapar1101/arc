"""Regression: read-only distribution lookups never initialize settings/commit.

Prevent transaction loss in visit validation, offline pack creation, van
capacity snapshots and automatic promotion selection. Use isolated fakes;
no production database or migrations are touched.
"""
from __future__ import annotations

from datetime import date, timedelta
from types import SimpleNamespace

import pytest

from app.services import distribution_service as distribution
from app.services import distribution_field_ops_service as field_ops


DAY = date(2026, 11, 24)


class QueryRows:
    def __init__(self, rows):
        self.rows = rows

    def filter(self, *_args):
        return self

    def all(self):
        return self.rows


class ReadOnlySession:
    def __init__(self, lots):
        self.lots = lots

    def query(self, _model):
        return QueryRows(self.lots)

    def add(self, *_args):
        pytest.fail("A read-only operation must not add database rows")

    def commit(self):
        pytest.fail("A read-only operation must not commit")


@pytest.fixture()
def forbid_settings_creation(monkeypatch):
    monkeypatch.setattr(
        distribution,
        "get_or_create_distribution_settings",
        lambda *_args: pytest.fail("Implicit settings creation/commit"),
    )
    monkeypatch.setattr(
        distribution, "get_distribution_settings_row", lambda *_args: None,
    )
    monkeypatch.setattr(field_ops, "business_today", lambda *_args: DAY)


def test_van_capacity_uses_read_only_default_settings(forbid_settings_creation):
    lot = SimpleNamespace(
        id=1, product_id=5, lot_code="L1",
        expiry_date=DAY + timedelta(days=10),
        quantity=2, unit_weight_kg=1.5, unit_volume_m3=0.25,
    )
    van = SimpleNamespace(id=12, max_weight_kg=9, max_volume_m3=3)
    result = field_ops.van_capacity_snapshot(ReadOnlySession([lot]), 10, van)
    assert result["weight_kg"] == 3
    assert result["volume_m3"] == 0.5
    assert result["near_expiry_lots"] == 1
    assert result["lots"][0]["near_expiry"] is True


def test_van_capacity_respects_saved_horizon_without_committing(
    forbid_settings_creation, monkeypatch,
):
    monkeypatch.setattr(
        distribution, "get_distribution_settings_row",
        lambda *_args: SimpleNamespace(near_expiry_days=3),
    )
    lot = SimpleNamespace(
        id=1, product_id=5, lot_code="L1",
        expiry_date=DAY + timedelta(days=10),
        quantity=1, unit_weight_kg=0, unit_volume_m3=0,
    )
    van = SimpleNamespace(id=12, max_weight_kg=None, max_volume_m3=None)
    result = field_ops.van_capacity_snapshot(ReadOnlySession([lot]), 10, van)
    assert result["near_expiry_lots"] == 0
    assert result["lots"][0]["near_expiry"] is False


def test_no_settings_auto_promotion_is_nonmutating(forbid_settings_creation):
    session = ReadOnlySession([])
    assert field_ops.apply_auto_promotions_if_needed(session, 10, None) is None
    assert field_ops.apply_auto_promotions_if_needed(session, 10, [9]) == [9]


def test_disabled_promotion_does_not_query_catalogue(
    forbid_settings_creation, monkeypatch,
):
    monkeypatch.setattr(
        distribution, "get_distribution_settings_row",
        lambda *_args: SimpleNamespace(auto_apply_promotions=False, enable_promotions=True),
    )
    assert field_ops.apply_auto_promotions_if_needed(ReadOnlySession([]), 10, None) is None
