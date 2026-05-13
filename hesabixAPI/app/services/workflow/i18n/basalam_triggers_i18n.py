"""ترجمهٔ متای تریگرهای باسلام برای API ورک‌فلو."""

from __future__ import annotations

_BASALAM_TRIGGER_FIELDS_FA: dict[str, str] = {
    "field_enabled": "فعال بودن تریگر",
    "field_enabled_desc": "اگر خاموش باشد این ورک‌فلو با این منبع اجرا نمی‌شود",
    "field_event_type": "نوع رویداد باسلام",
    "field_event_type_desc": "اختیاری؛ فقط اگر نوع رویداد وب‌هوک با این رشته یکسان باشد (حروف کوچک)",
    "field_cooldown_seconds": "حداقل فاصله بین اجرا (ثانیه)",
    "field_cooldown_seconds_desc": "پس از یک اجرا، تا این مدت برای همین ورک‌فلو سرکوب می‌شود",
}

_BASALAM_TRIGGER_FIELDS_EN: dict[str, str] = {
    "field_enabled": "Trigger enabled",
    "field_enabled_desc": "When off, this workflow will not run for this trigger",
    "field_event_type": "Basalam event type",
    "field_event_type_desc": "Optional; only when webhook event_type equals this string (case-insensitive)",
    "field_cooldown_seconds": "Minimum cooldown (seconds)",
    "field_cooldown_seconds_desc": "After a run, suppress retriggers for this workflow until this interval passes",
}

BASALAM_WEBHOOK_RECEIVED_TRANSLATIONS: dict[str, dict[str, str]] = {
    "fa": {
        "trigger_name": "وب‌هوک باسلام (عمومی)",
        "trigger_description": "هر رویداد وب‌هوک باسلام که به کلید اختصاصی نگاشت نشده باشد",
        **_BASALAM_TRIGGER_FIELDS_FA,
    },
    "en": {
        "trigger_name": "Basalam webhook (generic)",
        "trigger_description": "Any Basalam webhook event that does not match a specific mapped trigger key",
        **_BASALAM_TRIGGER_FIELDS_EN,
    },
}

BASALAM_ORDER_CREATED_TRANSLATIONS: dict[str, dict[str, str]] = {
    "fa": {
        "trigger_name": "سفارش جدید باسلام",
        "trigger_description": "وقتی رویداد ایجاد سفارش از باسلام دریافت می‌شود",
        **_BASALAM_TRIGGER_FIELDS_FA,
    },
    "en": {
        "trigger_name": "Basalam order created",
        "trigger_description": "When an order.created event is received from Basalam",
        **_BASALAM_TRIGGER_FIELDS_EN,
    },
}

BASALAM_ORDER_UPDATED_TRANSLATIONS: dict[str, dict[str, str]] = {
    "fa": {
        "trigger_name": "به‌روزرسانی سفارش باسلام",
        "trigger_description": "وقتی رویداد به‌روزرسانی سفارش از باسلام دریافت می‌شود",
        **_BASALAM_TRIGGER_FIELDS_FA,
    },
    "en": {
        "trigger_name": "Basalam order updated",
        "trigger_description": "When an order.updated event is received from Basalam",
        **_BASALAM_TRIGGER_FIELDS_EN,
    },
}

BASALAM_ORDER_PAID_TRANSLATIONS: dict[str, dict[str, str]] = {
    "fa": {
        "trigger_name": "پرداخت سفارش باسلام",
        "trigger_description": "وقتی رویداد پرداخت‌شدن سفارش از باسلام دریافت می‌شود",
        **_BASALAM_TRIGGER_FIELDS_FA,
    },
    "en": {
        "trigger_name": "Basalam order paid",
        "trigger_description": "When an order.paid event is received from Basalam",
        **_BASALAM_TRIGGER_FIELDS_EN,
    },
}

BASALAM_CHAT_MESSAGE_RECEIVED_TRANSLATIONS: dict[str, dict[str, str]] = {
    "fa": {
        "trigger_name": "پیام چت باسلام",
        "trigger_description": "وقتی پیام جدید از چت باسلام به سیستم می‌رسد",
        **_BASALAM_TRIGGER_FIELDS_FA,
    },
    "en": {
        "trigger_name": "Basalam chat message",
        "trigger_description": "When a new chat message is received from Basalam",
        **_BASALAM_TRIGGER_FIELDS_EN,
    },
}
