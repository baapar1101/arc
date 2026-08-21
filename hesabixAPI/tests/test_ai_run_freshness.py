from datetime import datetime, timezone

from app.services.ai.ai_run_hub import is_running_row_fresh
from app.services.ai.ai_constants import LIVE_RUN_STALE_SEC


def test_running_row_fresh_within_window():
    now = datetime.now(timezone.utc)
    assert is_running_row_fresh(now) is True


def test_running_row_stale_after_threshold():
    now = datetime.now(timezone.utc).timestamp()
    stale = datetime.fromtimestamp(now - LIVE_RUN_STALE_SEC - 5, tz=timezone.utc)
    assert is_running_row_fresh(stale, now=now) is False
