"""CHAT-12: نگاشت ردیف SQL زیر-ایجنت به آیتم UI."""
from datetime import datetime

from adapters.db.models.ai_subagent_run import AISubagentRun
from app.services.ai.ai_subagent_run_store import row_to_ui_item


def test_row_to_ui_item_includes_status_and_goal():
    row = AISubagentRun(
        subagent_id="abcd1234abcd1234",
        session_id=9,
        goal="گزارش فروش",
        status="completed",
        error=None,
        created_at=datetime.utcnow(),
        updated_at=datetime.utcnow(),
    )
    item = row_to_ui_item(row)
    assert item["subagent_id"] == "abcd1234abcd1234"
    assert item["goal"] == "گزارش فروش"
    assert item["status"] == "completed"
    assert item["error"] is None
