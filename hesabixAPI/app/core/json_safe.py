"""
سریال‌سازی امن JSON برای API و استریم AI.
"""
from __future__ import annotations

import json
from datetime import date, datetime
from decimal import Decimal
from enum import Enum
from typing import Any
from uuid import UUID


def json_safe_value(obj: Any) -> Any:
    """تبدیل datetime، Decimal و انواع دیگر به فرمت قابل json.dumps."""
    if obj is None or isinstance(obj, (str, int, float, bool)):
        return obj
    if isinstance(obj, dict):
        return {key: json_safe_value(value) for key, value in obj.items()}
    if isinstance(obj, (list, tuple, set)):
        return [json_safe_value(item) for item in obj]
    if isinstance(obj, datetime):
        return obj.isoformat()
    if isinstance(obj, date):
        return obj.isoformat()
    if isinstance(obj, Decimal):
        return float(obj)
    if isinstance(obj, UUID):
        return str(obj)
    if isinstance(obj, Enum):
        return obj.value
    if hasattr(obj, "isoformat"):
        try:
            return obj.isoformat()
        except Exception:
            pass
    if hasattr(obj, "__dict__") and not isinstance(obj, type):
        try:
            return json_safe_value(vars(obj))
        except Exception:
            return str(obj)
    return str(obj)


def json_dumps_safe(obj: Any, **kwargs: Any) -> str:
    return json.dumps(json_safe_value(obj), ensure_ascii=False, **kwargs)
