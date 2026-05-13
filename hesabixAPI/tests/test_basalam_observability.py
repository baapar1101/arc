"""متریک‌های یRedis باسلام (بدون Redis نیز باید امن باشد)."""

from __future__ import annotations

import pytest

from app.services import basalam_observability as obs


class _CacheOff:
    enabled = False


def test_record_metric_when_cache_disabled_no_crash(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(obs, "get_cache", lambda: _CacheOff())
    obs.record_basalam_metric("webhook_received", 3)


def test_summary_when_cache_disabled(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(obs, "get_cache", lambda: _CacheOff())
    s = obs.get_basalam_metrics_summary()
    assert s.get("redis_enabled") is False
    assert s["counters"]["webhook_received"] == 0
