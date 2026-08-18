"""تست حافظهٔ واحد: compiler، curator validator، intent."""
from __future__ import annotations

from app.services.ai.ai_memory_compiler import compile_memory_prompt
from app.services.ai.ai_memory_curator import (
    extract_json_object,
    parse_curator_ops,
    validate_curator_op,
)
from app.services.ai.ai_memory_keys import normalize_memory_key
from app.services.ai.ai_memory_service import extract_facts_from_messages, extract_learned_candidates
from app.services.ai.ai_tool_intent import detect_categories, select_tool_names


def test_compile_includes_identity_without_history():
    text = compile_memory_prompt(
        instructions="مبالغ را تومان بگو",
        items=[
            {
                "kind": "identity",
                "item_key": "identity.preferred_name",
                "content": "کاربر ترجیح می‌دهد علی خطاب شود.",
            }
        ],
        user_query="سلام",
    )
    assert "علی" in text
    assert "تومان" in text
    assert "حافظهٔ پایدار" in text


def test_compile_skips_unrelated_context_when_budget_tight_keeps_identity():
    items = [
        {
            "kind": "identity",
            "item_key": "identity.preferred_name",
            "content": "نام خطاب: سارا",
        },
        {
            "kind": "context",
            "item_key": "context.current_project",
            "content": "پروژه جاری نسیم‌کالاست",
            "updated_at": "2026-01-01",
        },
    ]
    text = compile_memory_prompt(items=items, user_query="سلام")
    assert "سارا" in text


def test_compile_recalls_project_when_query_mentions_it():
    items = [
        {
            "kind": "context",
            "item_key": "context.current_project",
            "content": "پروژه جاری نسیم‌کالاست",
            "updated_at": "2026-01-01",
        }
    ]
    text = compile_memory_prompt(items=items, user_query="وضعیت پروژه نسیم‌کالا چیست؟")
    assert "نسیم" in text


def test_validate_rejects_instruction_without_explicit_flag():
    op, reason = validate_curator_op(
        {
            "action": "upsert",
            "key": "instruction",
            "kind": "instruction",
            "content": "همیشه جدول بده",
            "user_explicit": False,
        }
    )
    assert op is None
    assert reason == "instruction_not_explicit"


def test_validate_accepts_preferred_name():
    op, reason = validate_curator_op(
        {
            "action": "upsert",
            "key": "identity.preferred_name",
            "kind": "identity",
            "content": "کاربر ترجیح می‌دهد علی خطاب شود.",
            "confidence": 0.9,
        }
    )
    assert reason == ""
    assert op is not None
    assert op["key"] == "identity.preferred_name"


def test_validate_rejects_secret_and_invoice_id():
    secret, s_reason = validate_curator_op(
        {
            "action": "upsert",
            "key": "context.note",
            "kind": "context",
            "content": "api_key=sk-live-secret",
            "confidence": 0.9,
        }
    )
    assert secret is None
    assert s_reason == "secret"
    inv, i_reason = validate_curator_op(
        {
            "action": "upsert",
            "key": "context.doc",
            "kind": "context",
            "content": "فاکتور #1234",
            "confidence": 0.9,
        }
    )
    assert inv is None
    assert i_reason == "ephemeral"


def test_extract_json_from_fenced_block():
    raw = """here\n```json\n{"ops":[{"action":"noop"}]}\n```\n"""
    data = extract_json_object(raw)
    assert data is not None
    assert parse_curator_ops(data)[0]["action"] == "noop"


def test_normalize_stable_key_keeps_namespace():
    key = normalize_memory_key("identity.preferred_name", kind="identity")
    assert key == "identity.preferred_name"


def test_memory_tools_not_selected_for_sales_report():
    names = {
        "query_business_data",
        "search_invoices",
        "read_memory",
        "upsert_memory_entry",
        "delete_memory_entry",
    }
    selected = select_tool_names(names, "گزارش فروش ماه گذشته")
    assert "search_invoices" in selected
    assert "read_memory" not in selected
    assert "upsert_memory_entry" not in selected


def test_memory_tools_selected_when_asking_what_you_know():
    names = {
        "query_business_data",
        "search_invoices",
        "read_memory",
        "upsert_memory_entry",
        "delete_memory_entry",
    }
    selected = select_tool_names(names, "چی درباره من می‌دانی؟")
    assert "read_memory" in selected
    cats = detect_categories("چی درباره من می‌دانی؟")
    assert "memory" in cats


def test_legacy_extract_helpers_still_importable():
    facts = extract_facts_from_messages(
        [{"role": "user", "content": "ترجیح می‌دم گزارش‌ها را به تومان بدهی"}]
    )
    assert isinstance(facts, list)
    cands = extract_learned_candidates(
        [{"role": "user", "content": "یادت باشه اسم پروژه ما نسیم‌کالا است"}]
    )
    assert isinstance(cands, list)
