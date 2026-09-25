"""پارس پاسخ‌های کوتاه CRM AI — بدون عدد ساختگی."""
from __future__ import annotations

import re

_PERSIAN_DIGITS = str.maketrans("۰۱۲۳۴۵۶۷۸۹٠١٢٣٤٥٦٧٨٩", "01234567890123456789")
_NUMBER_RE = re.compile(r"(?<![.\d])(\d{1,3})(?![.\d])")


def parse_probability_percent(raw: str | None) -> int | None:
    """اولین عدد ۰–۱۰۰ را برمی‌گرداند؛ اگر قابل استخراج نبود None.

    عمداً به ۵۰ fallback نمی‌کند — عدد ساختگی برای فرصت فروش خطرناک است.
    """
    if raw is None:
        return None
    text = str(raw).translate(_PERSIAN_DIGITS).replace(",", " ").strip()
    if not text:
        return None
    for match in _NUMBER_RE.finditer(text):
        value = int(match.group(1))
        if 0 <= value <= 100:
            return value
    return None
