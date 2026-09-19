"""Tests for scheduled AI task metering / gating."""
from __future__ import annotations

from unittest.mock import AsyncMock, MagicMock

import pytest

from app.services.ai.ai_scheduled_task_service import run_scheduled_task


@pytest.mark.asyncio
async def test_scheduled_task_skips_llm_without_availability():
    ai = MagicMock()
    ai.check_availability.return_value = {
        "can_use": False,
        "reason": "NO_ACTIVE_SUBSCRIPTION",
        "details": {"message": "no sub"},
    }
    ai.chat_completion = AsyncMock()

    result = await run_scheduled_task(
        db=MagicMock(),
        task={"id": "weekly_sales_report", "prompt": "گزارش بده"},
        business_id=1,
        ai_service=ai,
    )
    assert result["success"] is False
    assert result["reason"] == "NO_ACTIVE_SUBSCRIPTION"
    ai.chat_completion.assert_not_called()


@pytest.mark.asyncio
async def test_scheduled_task_charges_after_success():
    ai = MagicMock()
    ai.check_availability.return_value = {"can_use": True, "reason": None, "details": {}}
    ai.chat_completion = AsyncMock(
        return_value={
            "message": {"content": "ok"},
            "usage": {"input_tokens": 10, "output_tokens": 5, "total_tokens": 15},
        }
    )
    ai._charge_and_log_usage.return_value = {
        "payment_method": "subscription",
        "cost": 0,
    }

    result = await run_scheduled_task(
        db=MagicMock(),
        task={"id": "weekly_sales_report", "prompt": "گزارش بده"},
        business_id=1,
        ai_service=ai,
    )
    assert result["success"] is True
    ai._charge_and_log_usage.assert_called_once()
    assert result["usage"]["input_tokens"] == 10
