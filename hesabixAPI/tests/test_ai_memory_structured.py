"""تست‌های باقی‌ماندهٔ ماژول structured — فقط برای سازگاری import در صورت نیاز."""
from __future__ import annotations

import pytest


def test_structured_module_still_importable_but_unused():
    """فیلدهای ساخت‌یافته از جریان اصلی حافظه حذف شدند."""
    from app.services.ai import ai_memory_structured as mod

    assert hasattr(mod, "parse_structured")
    s = mod.parse_structured(None)
    assert isinstance(s, dict)


@pytest.mark.parametrize(
    "text,expect_key",
    [
        ("هدف فروش ماهانه ۵۰۰ میلیون تومان", "sales_goal_monthly"),
    ],
)
def test_legacy_extract_still_works(text, expect_key):
    from app.services.ai.ai_memory_structured import extract_structured_from_text

    patch = extract_structured_from_text(text)
    assert expect_key in patch
