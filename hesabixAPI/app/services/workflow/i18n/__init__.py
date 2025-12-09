"""
سیستم ترجمه ورک‌فلو
"""
from .workflow_translations import (
    SupportedLanguage,
    get_translation,
    translate_metadata,
    get_all_translation_keys,
    COMMON_TRANSLATIONS,
    CREATE_INVOICE_TRANSLATIONS,
    SEND_TELEGRAM_TRANSLATIONS,
    SEND_EMAIL_TRANSLATIONS,
    OTHER_ACTIONS_TRANSLATIONS,
)

__all__ = [
    "SupportedLanguage",
    "get_translation",
    "translate_metadata",
    "get_all_translation_keys",
    "COMMON_TRANSLATIONS",
    "CREATE_INVOICE_TRANSLATIONS",
    "SEND_TELEGRAM_TRANSLATIONS",
    "SEND_EMAIL_TRANSLATIONS",
    "OTHER_ACTIONS_TRANSLATIONS",
]


