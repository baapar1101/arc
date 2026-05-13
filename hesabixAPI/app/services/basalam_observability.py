"""Counters برای مشاهده‌پذیری یکپارچه‌سازی باسلام (Redis؛ بدون Redis بی‌اثر)."""

from __future__ import annotations

from typing import Any, Dict, List

import structlog

from app.core.cache import get_cache

logger = structlog.get_logger(__name__)

METRIC_TTL_SECONDS = 604800  # 7 days

# نام متریک‌های ثابت برای GET خلاصه بدون Redis KEYS
KNOWN_METRICS: List[str] = [
    "webhook_received",
    "webhook_duplicate",
    "webhook_processed_ok",
    "webhook_signature_invalid",
    "webhook_disabled",
    "sync_orders_batches",
    "sync_orders_processed",
    "sync_orders_invoices_created",
    "payment_sync_batches",
    "payment_sync_receipt_created",
    "payment_sync_dlq_appended",
    "payment_reconcile_blocked",
    "payment_reconcile_remaining_calc_failed",
]


def _metric_key(name: str) -> str:
    return f"metrics:basalam:v1:{name}"


def record_basalam_metric(name: str, amount: int = 1) -> None:
    if amount == 0:
        return
    cache = get_cache()
    if not cache.enabled:
        return
    try:
        key = _metric_key(name)
        cache.client.incrby(key, amount)
        cache.client.expire(key, METRIC_TTL_SECONDS)
    except Exception as exc:
        logger.warning("basalam_metric_incr_failed", metric=name, error=str(exc))


def get_basalam_metrics_summary() -> Dict[str, Any]:
    cache = get_cache()
    out: Dict[str, int] = {n: 0 for n in KNOWN_METRICS}
    if not cache.enabled:
        return {"redis_enabled": False, "counters": out}
    try:
        for name in KNOWN_METRICS:
            raw = cache.client.get(_metric_key(name))
            if raw is None:
                continue
            try:
                out[name] = int(raw)
            except (TypeError, ValueError):
                out[name] = int(str(raw))
        return {"redis_enabled": True, "counters": out}
    except Exception as exc:
        logger.warning("basalam_metrics_read_failed", error=str(exc))
        return {"redis_enabled": True, "counters": out, "error": str(exc)}
