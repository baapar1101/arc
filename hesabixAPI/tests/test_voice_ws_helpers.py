"""تست‌های کمکی WebSocket صوتی AI."""

from __future__ import annotations

import pytest

from adapters.api.v1.ai.voice_ws import (
	_availability_error_message,
	_forward_agent_chunk,
	_voice_deps_ready,
)


def test_availability_subscription_message() -> None:
	msg = _availability_error_message("NO_ACTIVE_SUBSCRIPTION", {})
	assert "اشتراک" in msg


def test_availability_quota_message() -> None:
	msg = _availability_error_message(
		"QUOTA_EXCEEDED",
		{"subscription": {"tokens_used": 100, "tokens_limit": 200}},
	)
	assert "100" in msg
	assert "200" in msg


@pytest.mark.asyncio
async def test_forward_agent_status_chunk() -> None:
	sent: list[dict] = []

	async def send_event(payload: dict) -> None:
		sent.append(payload)

	consumed = await _forward_agent_chunk(
		{"event": "status", "phase": "planning_tools"},
		send_event,
	)
	assert consumed is True
	assert sent[-1]["type"] == "voice_status"
	assert sent[-1]["phase"] == "planning_tools"


@pytest.mark.asyncio
async def test_forward_agent_tool_start() -> None:
	sent: list[dict] = []

	async def send_event(payload: dict) -> None:
		sent.append(payload)

	consumed = await _forward_agent_chunk(
		{
			"event": "tool_start",
			"tool": "search_invoices",
			"tool_key": "aiToolSearchInvoices",
			"label": "جستجوی فاکتور",
		},
		send_event,
	)
	assert consumed is True
	assert sent[-1]["phase"] == "tool_running"


def test_voice_deps_ready_returns_none_or_code() -> None:
	# بسته به نصب webrtcvad در محیط تست
	result = _voice_deps_ready()
	assert result is None or result == "VOICE_DEPS_MISSING"
