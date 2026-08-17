"""تست intent filter ابزارهای AI."""
from app.services.ai.ai_tool_intent import (
    detect_categories,
    estimate_query_complexity,
    merge_tool_allowlists,
    query_expects_tool_use,
    query_needs_knowledge,
    query_targets_tool_domain,
    select_tool_names,
)


def test_detect_financial_keywords():
    cats = detect_categories("گزارش فاکتور فروش ماه گذشته")
    assert "financial" in cats


def test_select_tools_includes_core():
    all_names = {
        "query_business_data",
        "search_invoices",
        "search_warehouse_documents",
        "get_customer_club_settings",
    }
    selected = select_tool_names(all_names, "فاکتور فروش")
    assert "query_business_data" in selected
    assert "search_invoices" in selected


def test_query_needs_knowledge_skips_greeting():
    assert query_needs_knowledge("سلام") is False


def test_query_needs_knowledge_detects_policy():
    assert query_needs_knowledge("سیاست مرجوعی فاکتور فروش چیست؟") is True


def test_query_needs_knowledge_long_question():
    assert query_needs_knowledge(
        "لطفاً وضعیت موجودی انبار مرکزی و کالاهای کم‌موجود را با جزئیات بررسی کن"
    ) is True


def test_select_tools_includes_write_on_add_keyword():
    all_names = {
        "query_business_data",
        "create_person",
        "update_person",
        "search_invoices",
    }
    selected = select_tool_names(all_names, "یک مشتری به نام علی اضافه کن")
    assert "create_person" in selected


def test_detect_people_category():
    cats = detect_categories("لیست مشتریان و گروه اشخاص")
    assert "people" in cats


def test_estimate_query_complexity_multi_domain():
    assert estimate_query_complexity(
        "گزارش فروش، موجودی انبار و وضعیت مشتریان VIP"
    ) == "complex"


def test_estimate_query_complexity_write_operation():
    assert estimate_query_complexity("یک مشتری جدید به نام علی اضافه کن") == "medium"


def test_estimate_query_complexity_greeting():
    assert estimate_query_complexity("سلام") == "simple"


# ---- Phase 0: routing باید حتی سوال‌های «ساده» اما داده‌محور را tools بدهد ----

def test_query_expects_tool_use_simple_complexity_but_data_domain():
    query = "موجودی کالای الف چقدر است؟"
    # سوال داده‌محور کوتاه بدون کلیدواژهٔ گزارش هنوز می‌تواند simple باشد
    # اما باید tools بگیرد.
    assert query_expects_tool_use(query) is True


def test_estimate_query_complexity_short_report_is_not_simple():
    assert estimate_query_complexity("تراز آزمایشی فروردین") == "medium"
    assert estimate_query_complexity("یه گزارش از هزینه ها بهم بگو") == "medium"
    assert estimate_query_complexity("سلام") == "simple"


def test_query_targets_tool_domain_strips_leading_greeting():
    assert query_targets_tool_domain("سلام یه گزارش از هزینه ها بهم بگو") is True


def test_query_expects_tool_use_greeting_prefixed_data_query():
    assert query_expects_tool_use("سلام یه گزارش از هزینه ها بهم بگو") is True


def test_query_expects_tool_use_pure_greeting_stays_false():
    assert query_expects_tool_use("سلام") is False


def test_query_expects_tool_use_short_followup_with_history():
    history = [
        {"role": "user", "content": "بررسی مالی از ۳ ماه گذشته انجام بده"},
    ]
    assert query_expects_tool_use("انجامش بده", history) is True


def test_plan_tools_union_survives_intent_without_plan_keywords():
    from app.services.ai.ai_session_todo_service import SESSION_TODO_TOOL_NAMES

    all_names = {
        "query_business_data",
        "search_invoices",
        "get_sales_report",
        "create_session_plan",
        "list_session_todos",
        "update_session_todo",
    }
    selected = select_tool_names(all_names, "فروش این ماه چقدر بوده؟")
    assert "create_session_plan" not in selected
    allowed = merge_tool_allowlists(
        selected,
        forced_names=SESSION_TODO_TOOL_NAMES & all_names,
    )
    assert "create_session_plan" in allowed
    assert "update_session_todo" in allowed
