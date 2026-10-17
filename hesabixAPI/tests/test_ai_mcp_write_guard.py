"""MCP نباید write را از query یا آرگومان پنهان تأیید کند."""
from __future__ import annotations

from app.services.ai.ai_mcp_service import (
    mcp_explicit_write_approval,
    prepare_mcp_tool_arguments,
)
from app.services.ai.ai_write_guard import is_write_function


def test_mcp_write_functions_are_gated():
    assert is_write_function("create_invoice") is True
    assert is_write_function("search_invoices") is False


def test_mcp_argument_backdoor_is_stripped():
    cleaned = prepare_mcp_tool_arguments(
        {"customer": "علی", "_approve_writes": True}, business_id=7
    )
    assert "_approve_writes" not in cleaned
    assert cleaned["customer"] == "علی"


def test_mcp_rpc_cannot_authorize_a_write():
    assert mcp_explicit_write_approval({}) is False
    assert mcp_explicit_write_approval({"approve_writes": False}) is False
    assert mcp_explicit_write_approval({"approve_writes": "true"}) is False
    assert mcp_explicit_write_approval({"approve_writes": True}) is False


def test_mcp_arguments_cannot_override_bound_business():
    cleaned = prepare_mcp_tool_arguments(
        {"business_id": 99, "approve_writes": True}, business_id=7
    )
    assert cleaned["business_id"] == 7
    assert "approve_writes" not in cleaned
