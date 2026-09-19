"""تست Prompt Caching در سطح Provider."""
from __future__ import annotations

from app.services.ai.ai_constants import PROMPT_CACHE_MIN_STATIC_TOKENS
from app.services.ai.ai_prompt_cache import (
    PromptCachePolicy,
    build_anthropic_system_blocks,
    build_prompt_cache_policy,
    merge_provider_extra,
    normalize_openai_usage,
    openai_supports_prompt_cache,
    split_system_messages_for_provider,
    usage_context_fields,
    LLMUsageDetails,
)
from app.services.ai.ai_system_prompt import (
    StructuredSystemPrompt,
    compose_structured_system_prompt,
    coerce_structured_system_prompt,
)


class _FakeProvider:
    def estimate_tokens(self, text: str) -> int:
        return max(1, len(text) // 4)


def test_structured_prompt_full_text_preserves_layers():
    structured = compose_structured_system_prompt(
        static_core="BASE " * 200,
        business_anchor="\n\nکسب‌وکار فعلی: شناسه 1",
        execution_block="\n\n[mode]",
        semi_static_sections=("\n\n[memory]",),
        runtime_sections=("\n\n[datetime]",),
        role="user",
        business_id=1,
    )
    text = structured.full_text()
    assert "BASE" in text
    assert "کسب‌وکار فعلی" in text
    assert "[memory]" in text
    assert "[datetime]" in text
    assert "[memory]" in structured.semi_static_text()
    assert "[datetime]" in structured.dynamic_system_text()
    assert "[datetime]" not in structured.semi_static_text()


def test_cache_key_changes_when_insights_change():
    kwargs = dict(
        static_core="X" * 5000,
        business_anchor="\n\nbiz",
        role="user",
        business_id=7,
    )
    a = compose_structured_system_prompt(
        **kwargs, semi_static_sections=("insights-a",), insights_section="insights-a"
    )
    b = compose_structured_system_prompt(
        **kwargs, semi_static_sections=("insights-b",), insights_section="insights-b"
    )
    c = compose_structured_system_prompt(
        **kwargs,
        semi_static_sections=("insights-a",),
        insights_section="insights-a",
        execution_block="\n\nchanged-mode",
    )
    assert a.cache_key() != b.cache_key()
    assert a.cache_key() == c.cache_key()


def test_cache_key_stable_for_same_static_prefix():
    a = compose_structured_system_prompt(
        static_core="X" * 5000,
        business_anchor="\n\nbiz",
        role="user",
        business_id=7,
    )
    b = compose_structured_system_prompt(
        static_core="X" * 5000,
        business_anchor="\n\nbiz",
        execution_block="\n\nchanged",
        role="user",
        business_id=7,
    )
    assert a.cache_key() == b.cache_key()


def test_prompt_cache_policy_disabled_when_static_too_small():
    structured = compose_structured_system_prompt(
        static_core="tiny",
        business_anchor="",
        role="user",
        business_id=1,
    )
    policy = build_prompt_cache_policy(structured, "anthropic", _FakeProvider())
    assert policy.enabled is False


def test_openai_prompt_cache_disabled_for_custom_base_url():
    assert openai_supports_prompt_cache("https://api.openai.com/v1") is True
    assert openai_supports_prompt_cache(None) is True
    assert openai_supports_prompt_cache("https://ai.arvancloud.ir/v1") is False

    structured = compose_structured_system_prompt(
        static_core="A" * (PROMPT_CACHE_MIN_STATIC_TOKENS * 4 + 100),
        business_anchor="\n\nbiz",
        role="user",
        business_id=2,
    )
    policy = build_prompt_cache_policy(
        structured,
        "openai",
        _FakeProvider(),
        api_base_url="https://ai.arvancloud.ir/v1",
    )
    assert policy.enabled is False


def test_prompt_cache_policy_enabled_for_large_static():
    structured = compose_structured_system_prompt(
        static_core="A" * (PROMPT_CACHE_MIN_STATIC_TOKENS * 4 + 100),
        business_anchor="\n\nbiz",
        role="user",
        business_id=2,
    )
    policy = build_prompt_cache_policy(structured, "openai", _FakeProvider())
    assert policy.enabled is True
    assert policy.cache_key.startswith("hx:v1:")


def test_split_system_messages_adds_static_and_dynamic():
    policy = PromptCachePolicy(
        enabled=True,
        cache_key="hx:test",
        static_system="STATIC",
        dynamic_system="DYNAMIC",
    )
    messages = [
        {"role": "system", "content": "STATICDYNAMIC"},
        {"role": "user", "content": "hi"},
    ]
    out = split_system_messages_for_provider(messages, policy)
    assert out[0]["content"] == "STATIC"
    assert out[1]["content"] == "DYNAMIC"
    assert out[2]["content"] == "hi"


def test_anthropic_system_blocks_cache_control_on_static():
    policy = PromptCachePolicy(
        enabled=True,
        cache_key="hx:test",
        static_system="STATIC",
        dynamic_system="DYNAMIC",
    )
    blocks = build_anthropic_system_blocks(policy)
    assert blocks is not None
    assert blocks[0]["cache_control"]["type"] == "ephemeral"
    assert "cache_control" not in blocks[1]


def test_anthropic_system_blocks_cache_control_on_semi_static():
    policy = PromptCachePolicy(
        enabled=True,
        cache_key="hx:test",
        static_system="STATIC",
        semi_static_system="SEMI",
        dynamic_system="DYNAMIC",
    )
    blocks = build_anthropic_system_blocks(policy)
    assert blocks is not None
    assert len(blocks) == 3
    assert blocks[0]["cache_control"]["type"] == "ephemeral"
    assert blocks[1]["cache_control"]["type"] == "ephemeral"
    assert "cache_control" not in blocks[2]


def test_split_system_messages_inserts_semi_static():
    policy = PromptCachePolicy(
        enabled=True,
        cache_key="hx:test",
        static_system="STATIC",
        semi_static_system="SEMI",
        dynamic_system="DYNAMIC",
    )
    out = split_system_messages_for_provider(
        [{"role": "system", "content": "ALL"}, {"role": "user", "content": "hi"}],
        policy,
    )
    assert [m["content"] for m in out] == ["STATIC", "SEMI", "DYNAMIC", "hi"]


def test_merge_provider_extra_includes_prompt_cache():
    merged = merge_provider_extra(
        {"anthropic_skills": ["sk-1"]},
        PromptCachePolicy(
            enabled=True,
            cache_key="hx:1",
            static_system="S",
            dynamic_system="D",
        ),
    )
    assert merged["anthropic_skills"] == ["sk-1"]
    assert merged["prompt_cache"]["enabled"] is True


def test_normalize_openai_usage_cached_tokens():
    class _Details:
        cached_tokens = 512

    class _Usage:
        prompt_tokens = 2000
        completion_tokens = 100
        total_tokens = 2100
        prompt_tokens_details = _Details()

    details = normalize_openai_usage(_Usage())
    assert details.cache_read_tokens == 512
    ctx = usage_context_fields(details)
    assert ctx["prompt_cache_read_tokens"] == 512


def test_coerce_structured_from_legacy_string():
    structured = coerce_structured_system_prompt("hello", role="operator", business_id=3)
    assert structured.static_core == "hello"
    assert structured.role == "operator"
    assert structured.business_id == 3
