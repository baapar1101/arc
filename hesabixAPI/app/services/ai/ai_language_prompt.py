"""
بلوک prompt زبان برای چت AI — هماهنگ‌سازی پاسخ و متن تحلیل/تفکر با زبان کاربر.
"""
from __future__ import annotations

from typing import Optional


def normalize_language_code(language: Optional[str]) -> str:
    if not language:
        return "fa"
    low = str(language).lower().strip().replace("_", "-")
    if low.startswith("en"):
        return "en"
    return "fa"


def resolve_effective_chat_language(
    *,
    ctx_language: Optional[str] = None,
    preferred_language: Optional[str] = None,
) -> str:
    """زبان مؤثر چت: ترجیح حافظه > locale درخواست > پیش‌فرض فارسی."""
    pref = normalize_language_code(preferred_language) if preferred_language in ("fa", "en") else None
    if pref:
        return pref
    return normalize_language_code(ctx_language)


def build_language_context_prompt_block(language: str = "fa") -> str:
    """بلوک پویا per-request برای تأکید زبان مکالمه."""
    lang = normalize_language_code(language)
    if lang == "en":
        return """
## User language and reasoning display (mandatory)

- Current conversation language: **English**
- All user-visible text must be in English: final answer, pre-tool narration, reasoning, step summaries, findings, and any analysis-panel content.
- **Reasoning text is shown directly to the user in the UI** — every reasoning token, live thinking stream, and narration must be in English for this session.
- Even if raw tool data or API field names are non-English, explain and analyze in English.
- Do not write analytical paragraphs in Persian or mixed languages.
- Match the language of the user's latest message; default to English for this session.
""".strip()

    return """
## زبان کاربر و نمایش تفکر (الزامی)

- زبان مکالمهٔ فعلی: **فارسی**
- تمام متن‌های قابل‌مشاهده برای کاربر باید فارسی باشد: پاسخ نهایی، narration قبل از فراخوانی ابزار، استدلال، خلاصهٔ مراحل، یافته‌ها و هر متن داخل پنل تحلیل.
- **متن استدلال (reasoning) مستقیماً در UI به کاربر نمایش داده می‌شود** — هر توکن استدلال، جریان تفکر زنده و narration باید فارسی باشد؛ استدلال انگلیسی ممنوع است.
- حتی اگر دادهٔ خام ابزار یا نام فیلد API انگلیسی است، توضیح و تحلیل را فارسی بنویس.
- از نوشتن جملات یا پاراگراف‌های تحلیلی به انگلیسی خودداری کن.
- با زبان آخرین پیام کاربر هماهنگ بمان؛ برای این نشست پیش‌فرض فارسی است.
""".strip()
