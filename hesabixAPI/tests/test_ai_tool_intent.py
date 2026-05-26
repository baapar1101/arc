"""تست intent filter ابزارهای AI."""
from app.services.ai.ai_tool_intent import detect_categories, select_tool_names


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
