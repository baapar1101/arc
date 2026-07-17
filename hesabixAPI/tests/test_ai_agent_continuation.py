"""تست ارزیابی evidence-based agent (Plan C)."""
from __future__ import annotations

from app.services.ai.ai_agent_continuation import (
    EvidenceContinuation,
    assess_text_round_evidence,
    resolve_needs_tools,
)
from app.services.ai.ai_exploration_service import ObservationStore, ThoughtRecord


def test_needs_tools_for_data_query():
    assert resolve_needs_tools("فاکتورهای فروش را بررسی کن") is True


def test_needs_tools_for_short_follow_up_with_history():
    history = [{"role": "user", "content": "بررسی مالی از ۳ ماه گذشته انجام بده"}]
    assert resolve_needs_tools("انجامش بده", history) is True


def test_no_needs_tools_for_greeting():
    assert resolve_needs_tools("سلام") is False


def test_continue_when_no_evidence_and_needs_tools():
    result = assess_text_round_evidence(
        round_text="در حال جستجوی فاکتورهای فروش.",
        user_query="فاکتورهای فروش را بررسی کن",
        observation_store=ObservationStore(),
        needs_tools=True,
    )
    assert isinstance(result, EvidenceContinuation)
    assert result.should_continue is True
    assert result.goal_reached is False


def test_stop_for_simple_greeting():
    result = assess_text_round_evidence(
        round_text="سلام! چطور می‌توانم کمک کنم؟",
        user_query="سلام",
        observation_store=ObservationStore(),
        needs_tools=False,
    )
    assert result.should_continue is False
    assert result.goal_reached is True


def test_stop_when_high_confidence_thought():
    store = ObservationStore()
    store.add_thought(
        ThoughtRecord(
            thought_id="t1",
            bundle_id="b1",
            iteration=1,
            body_markdown="### یافته‌ها",
            confidence="high",
            open_questions=[],
        )
    )
    result = assess_text_round_evidence(
        round_text="",
        user_query="لیست بدهکاران",
        observation_store=store,
        needs_tools=True,
    )
    assert result.goal_reached is False
    assert result.should_continue is True


def test_continue_when_evidence_but_planning_narrative_session_756():
    """session 756: planning + JSON با evidence نباید goal_reached شود."""
    store = ObservationStore()
    store.add_thought(
        ThoughtRecord(
            thought_id="t1",
            bundle_id="b1",
            iteration=1,
            body_markdown="### یافته‌ها",
            confidence="medium",
            open_questions=[],
        )
    )
    planning = (
        "برای تهیهٔ گزارش مالی سه ماه گذشته ابتدا بازهٔ تاریخی را تبدیل می‌کنم. "
        "سپس داده‌های فروش و خرید را دریافت می‌کنم.\n\n"
        '```json\n{"relative": "last_3_months"}\n```'
    )
    result = assess_text_round_evidence(
        round_text=planning,
        user_query="یه گزارش مالی از سه ماه گذشته بهم بده",
        observation_store=store,
        needs_tools=True,
    )
    assert result.should_continue is True
    assert result.goal_reached is False


def test_narrative_text_does_not_auto_stop_without_evidence():
    """متن planning بدون evidence → continue (بدون regex)."""
    result = assess_text_round_evidence(
        round_text="We will call resolve_date_range then get_financial_summary.",
        user_query="بررسی مالی انجام بده",
        observation_store=ObservationStore(),
        needs_tools=True,
    )
    assert result.should_continue is True
    assert result.goal_reached is False


def test_stop_when_evidence_and_composed_answer_text():
    """session 750: بعد از tool، خلاصهٔ واقعی مدل باید نهایی شود نه continue."""
    store = ObservationStore()
    store.add_thought(
        ThoughtRecord(
            thought_id="t1",
            bundle_id="b1",
            iteration=1,
            body_markdown="### یافته‌ها\n1. گزارش فروش: **11** مورد",
            confidence="medium",
            open_questions=[],
        )
    )
    result = assess_text_round_evidence(
        round_text=(
            "**خلاصهٔ فروش ۳ ماه اخیر**\n\n"
            "- تعداد فاکتور: ۱۱\n"
            "- مجموع مبلغ: ۴۱۴ میلیون ریال"
        ),
        user_query="یه گزارش از فروش سه ماه گذشته بهم بگو",
        observation_store=store,
        needs_tools=True,
    )
    assert result.should_continue is False
    assert result.goal_reached is True


def test_continue_when_evidence_but_status_narrative():
    """با evidence اگر هنوز «در حال…» می‌گوید → continue."""
    store = ObservationStore()
    store.add_thought(
        ThoughtRecord(
            thought_id="t1",
            bundle_id="b1",
            iteration=1,
            body_markdown="### یافته‌ها",
            confidence="medium",
            open_questions=["نیاز به جزئیات بیشتر"],
        )
    )
    result = assess_text_round_evidence(
        round_text="در حال دریافت جزئیات فاکتورها هستم.",
        user_query="فاکتورهای فروش را بررسی کن",
        observation_store=store,
        needs_tools=True,
    )
    assert result.should_continue is True
    assert result.goal_reached is False
