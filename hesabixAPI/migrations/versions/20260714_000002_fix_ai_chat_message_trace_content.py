"""اصلاح پیام‌های AI — بستن traceهای active و حذف توکن‌های Harmony.

Revision ID: 20260714_000002_fix_ai_chat_message_trace_content
Revises: 20260714_000001_ai_prompts_language_policy
"""

from __future__ import annotations

import json

import sqlalchemy as sa
from alembic import op

revision = "20260714_000002_fix_ai_chat_message_trace_content"
down_revision = "20260714_000001_ai_prompts_language_policy"
branch_labels = None
depends_on = None


def _sanitize_trace_steps(trace_steps: list) -> list:
    from app.services.ai.ai_content_sanitize import sanitize_assistant_content

    out = []
    for step in trace_steps:
        if not isinstance(step, dict):
            continue
        record = dict(step)
        if record.get("state") == "active":
            record["state"] = "done"
        body = record.get("body_markdown")
        if isinstance(body, str) and body:
            record["body_markdown"] = sanitize_assistant_content(body)
        out.append(record)
    return out


def _repair_function_results(raw: str | None) -> str | None:
    if not raw:
        return raw
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return raw
    if not isinstance(data, dict):
        return raw

    from app.services.ai.ai_trace import TRACE_AGENT_KEY, TRACE_REASONING_KEY, split_trace_layers

    trace = data.get(TRACE_AGENT_KEY)
    if isinstance(trace, list) and trace:
        finalized = _sanitize_trace_steps(trace)
        data[TRACE_AGENT_KEY] = finalized
        _, reasoning = split_trace_layers(finalized)
        if reasoning:
            data[TRACE_REASONING_KEY] = reasoning
        elif TRACE_REASONING_KEY in data:
            data[TRACE_REASONING_KEY] = reasoning

    return json.dumps(data, ensure_ascii=False)


def upgrade() -> None:
    from app.services.ai.ai_content_sanitize import (
        extract_leaked_function_calls,
        sanitize_assistant_content,
    )

    conn = op.get_bind()
    rows = conn.execute(
        sa.text(
            """
            SELECT id, content, function_calls, function_results
            FROM ai_chat_messages
            WHERE role = 'assistant'
              AND (
                content LIKE '%<|start|>%'
                OR content LIKE '%<|channel|>%'
                OR function_results LIKE '%"state": "active"%'
              )
            """
        )
    ).fetchall()

    for row in rows:
        msg_id = row.id
        raw_content = row.content or ""
        cleaned_content = sanitize_assistant_content(raw_content)

        function_calls = row.function_calls
        if not function_calls:
            leaked = extract_leaked_function_calls(f"{raw_content}\n{cleaned_content}")
            if leaked:
                function_calls = json.dumps(leaked, ensure_ascii=False)

        repaired_results = _repair_function_results(row.function_results)

        conn.execute(
            sa.text(
                """
                UPDATE ai_chat_messages
                SET content = :content,
                    function_calls = COALESCE(:function_calls, function_calls),
                    function_results = COALESCE(:function_results, function_results)
                WHERE id = :id
                """
            ),
            {
                "id": msg_id,
                "content": cleaned_content,
                "function_calls": function_calls,
                "function_results": repaired_results,
            },
        )


def downgrade() -> None:
    # دادهٔ اصلاح‌شده را به حالت قبلی برنمی‌گردانیم.
    pass
