"""تست کاتالوگ ابزار و intent کشف ابزار."""
from __future__ import annotations

from app.services.ai.ai_tool_catalog import (
    build_tool_catalog_markdown,
    is_tool_discovery_query,
)


def test_is_tool_discovery_query_fa():
    assert is_tool_discovery_query("برای اتصال به مودیان چه ابزارهایی داری؟")
    assert is_tool_discovery_query("What tools do you have for tax?")


def test_is_tool_discovery_query_negative():
    assert not is_tool_discovery_query("لیست فاکتورهای امروز")
    assert not is_tool_discovery_query("")


def test_build_tool_catalog_uses_real_names():
    definitions = [
        {
            "function": {
                "name": "get_tax_settings",
                "description": "تنظیمات مالیاتی کسب‌وکار",
            }
        },
        {
            "function": {
                "name": "search_tax_workspace",
                "description": "جستجو در کارپوشه مودیان",
            }
        },
    ]
    md = build_tool_catalog_markdown(definitions)
    assert "`get_tax_settings`" in md
    assert "`search_tax_workspace`" in md
    assert "list_tax_returns" not in md
    assert "مالیات و مودیان" in md
