"""کلید پایدار و kind یکپارچهٔ حافظهٔ دستیار."""
from __future__ import annotations

import hashlib
import re
from datetime import datetime
from typing import Optional

_SLUG_RE = re.compile(r"[^a-z0-9_\u0600-\u06ff]+", re.IGNORECASE)
_STABLE_KEY_RE = re.compile(r"^[a-z][a-z0-9_]*(?:\.[a-z0-9_]+){1,4}$")
_KIND_PREFIX = {
    "identity": "identity",
    "preference": "preference",
    "context": "context",
    "goal": "goal",
    "constraint": "constraint",
    "instruction": "instruction",
}

KIND_ALIASES = {
    "instruction": "instruction",
    "identity": "identity",
    "preference": "preference",
    "context": "context",
    "goal": "goal",
    "constraint": "constraint",
    "fact": "context",
    "term": "context",
    "hint": "constraint",
}

KIND_LABELS_FA = {
    "instruction": "سیاست همیشگی",
    "identity": "هویت",
    "preference": "ترجیح",
    "context": "زمینه",
    "goal": "هدف",
    "constraint": "محدودیت",
}

KIND_PROMPT_TITLES = {
    "instruction": "سیاست‌های الزام‌آور کاربر",
    "identity": "هویت و خطاب",
    "preference": "ترجیحات پایدار",
    "constraint": "محدودیت‌ها و اجتناب",
    "context": "زمینهٔ کاری پایدار",
    "goal": "اهداف پایدار",
}

KEY_PROMPT_LABELS = {
    "identity.preferred_name": "نام خطاب کاربر",
    "identity.role_in_business": "نقش کاربر در این کسب‌وکار",
    "preference.report_style": "سبک گزارش",
    "preference.amount_unit": "واحد مبلغ",
    "preference.language": "زبان پاسخ",
}


def canonical_kind(raw: Optional[str], *, default: str = "context") -> str:
    key = (raw or "").strip().lower()
    return KIND_ALIASES.get(key, default if default in KIND_ALIASES else "context")


def is_stable_key(raw: str) -> bool:
    return bool(_STABLE_KEY_RE.match((raw or "").strip().lower()))


def slugify_legacy_key(raw: str) -> str:
    text = (raw or "").strip().lower()[:80]
    text = _SLUG_RE.sub("_", text).strip("_")
    return text or f"item_{int(datetime.utcnow().timestamp())}"


def normalize_memory_key(
    raw: Optional[str],
    *,
    kind: str = "context",
    content: str = "",
) -> str:
    """کلید پایدار با namespace؛ متن آزاد قدیمی slug می‌شود."""
    kind = canonical_kind(kind)
    text = (raw or "").strip().lower().replace(" ", "_")
    if text == "instruction" or kind == "instruction":
        return "instruction"
    if is_stable_key(text):
        prefix = _KIND_PREFIX.get(kind)
        if prefix and not text.startswith(prefix + ".") and text != prefix:
            # کلید معتبر اما بدون namespace درست — اگر با kind نخواند، prefix بگذار
            first = text.split(".", 1)[0]
            if first not in _KIND_PREFIX:
                text = f"{prefix}.{text}"
        return text[:128]
    base = slugify_legacy_key(text or content[:40])
    prefix = _KIND_PREFIX.get(kind, "context")
    if base.startswith(prefix + "_") or base.startswith(prefix + "."):
        candidate = base.replace("_", ".", 1) if "." not in base else base
        if is_stable_key(candidate):
            return candidate[:128]
    digest = hashlib.sha1((content or base).encode("utf-8")).hexdigest()[:8]
    return f"{prefix}.{base[:40] or digest}"[:128]


def pinned_context_key(content: str) -> str:
    digest = hashlib.sha1((content or "").strip().encode("utf-8")).hexdigest()[:10]
    return f"context.pinned.{digest}"
