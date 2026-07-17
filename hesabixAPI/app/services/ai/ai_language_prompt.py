"""
بلوک prompt زبان برای چت AI — هماهنگ‌سازی پاسخ و متن تحلیل/تفکر با زبان کاربر.
"""
from __future__ import annotations

import re
from typing import Optional

_PERSIAN_SCRIPT = re.compile(r"[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF]")
_LATIN_WORD = re.compile(r"[a-zA-Z]{2,}")


def normalize_language_code(language: Optional[str]) -> str:
    if not language:
        return "fa"
    low = str(language).lower().strip().replace("_", "-")
    if low.startswith("en"):
        return "en"
    return "fa"


def detect_message_language(text: Optional[str]) -> Optional[str]:
    """تشخیص سادهٔ fa/en از متن پیام کاربر. اگر نامشخص باشد None."""
    stripped = (text or "").strip()
    if not stripped:
        return None
    persian_chars = len(_PERSIAN_SCRIPT.findall(stripped))
    latin_words = len(_LATIN_WORD.findall(stripped))
    if persian_chars >= 2:
        return "fa"
    if latin_words >= 1 and persian_chars == 0:
        return "en"
    if latin_words >= 2 and persian_chars < 2:
        return "en"
    return None


def resolve_effective_chat_language(
    *,
    ctx_language: Optional[str] = None,
    preferred_language: Optional[str] = None,
    user_message: Optional[str] = None,
) -> str:
    """زبان مؤثر چت: متن آخرین پیام کاربر > ترجیح حافظه > locale درخواست."""
    from_message = detect_message_language(user_message)
    if from_message in ("fa", "en"):
        return from_message
    pref = (
        normalize_language_code(preferred_language)
        if preferred_language in ("fa", "en")
        else None
    )
    if pref:
        return pref
    return normalize_language_code(ctx_language)


def build_language_context_prompt_block(language: str = "fa") -> str:
    """بلوک پویا per-request برای تأکید زبان مکالمه."""
    lang = normalize_language_code(language)
    if lang == "en":
        return """
## User language and reasoning display (mandatory — highest priority)

- **Current conversation language: English** (derived from the user's latest message when possible).
- All user-visible text must be in English: final answer, pre-tool narration, **reasoning/thinking**, step summaries, findings, and analysis-panel content.
- **Reasoning text is streamed live to the user** — write every reasoning token in English. Do not think in Persian or mix languages in the reasoning channel.
- Tool/API field names may stay English; explain results in English.
- If the user switches to Persian in a later message, switch all output including reasoning to Persian.
""".strip()

    return """
## زبان کاربر و نمایش تفکر (الزامی — بالاترین اولویت)

- **زبان مکالمهٔ فعلی: فارسی** (در صورت امکان از آخرین پیام کاربر استخراج شده).
- تمام متن‌های قابل‌مشاهده باید فارسی باشد: پاسخ نهایی، narration، **استدلال/تفکر (reasoning)**، خلاصهٔ مراحل، یافته‌ها و پنل تحلیل.
- **متن reasoning به‌صورت زنده در UI نمایش داده می‌شود** — هر توکن تفکر را فارسی بنویس؛ تفکر یا استدلال انگلیسی ممنوع است.
- نام فیلد API می‌تواند انگلیسی بماند؛ توضیح و تحلیل فارسی باشد.
- اگر کاربر در پیام بعدی انگلیسی نوشت، همهٔ خروجی‌ها از جمله reasoning را انگلیسی کن.
""".strip()


def build_force_synthesis_user_content(
    language: str,
    explored_context: str,
) -> str:
    """پیام user برای نوبت اجباری سنتز پس از جمع شواهد."""
    lang = normalize_language_code(language)
    if lang == "en":
        return (
            "[force_synthesis]\n"
            "Based on the tool data below, write a direct, readable **English** "
            "final answer for the user. Do not call tools again:\n\n"
            + explored_context
        )
    return (
        "[force_synthesis]\n"
        "بر اساس داده‌های زیر که از ابزارها جمع‌آوری شده، یک "
        "پاسخ نهایی مستقیم، خوانا و **فارسی** برای کاربر بنویس. "
        "دیگر از فراخوانی ابزار استفاده نکن:\n\n"
        + explored_context
    )


def build_agent_synthesize_continue_message(language: str) -> str:
    """پیام continue وقتی متن planning است ولی شواهد جمع شده."""
    lang = normalize_language_code(language)
    if lang == "en":
        return (
            "[agent_synthesize]\n"
            "Based on the data already collected from tools, write a direct, "
            "readable final answer for the user. Do not plan or announce tool "
            "calls — deliver the answer now."
        )
    return (
        "[agent_synthesize]\n"
        "بر اساس داده‌هایی که از ابزارها جمع شد، "
        "یک پاسخ نهایی مستقیم و خوانا برای کاربر "
        "بنویس. دیگر برنامه‌ریزی یا توضیح قصد "
        "فراخوانی ابزار نده."
    )


def build_history_summary_system_prompt(language: str = "fa") -> str:
    """system prompt خلاصهٔ تاریخچه — هم‌زبان مکالمه."""
    lang = normalize_language_code(language)
    if lang == "en":
        return (
            "Summarize the prior conversation between the user and the Hesabix "
            "accounting assistant in **English**. Keep only facts, numbers, "
            "preferences, sales/financial goals, and important decisions. "
            "At most 15 short bullets. Do not guess."
        )
    return (
        "توضیحات مکالمهٔ قبلی بین کاربر و دستیار حسابداری را به **فارسی** خلاصه کن. "
        "فقط حقایق، اعداد، ترجیحات، اهداف فروش/مالی و تصمیم‌های مهم را نگه دار. "
        "حداکثر ۱۵ بولت کوتاه. از حدس زدن خودداری کن."
    )


def reasoning_language_mismatch(
    reasoning_text: str,
    expected_language: str,
) -> bool:
    """آیا reasoning با زبان مورد انتظار ناهماهنگ است؟ (برای log/monitor)"""
    detected = detect_message_language(reasoning_text)
    if not detected or len((reasoning_text or "").strip()) < 24:
        return False
    return detected != normalize_language_code(expected_language)
