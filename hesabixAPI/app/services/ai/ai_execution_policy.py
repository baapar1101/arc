"""
سیاست اجرای دستیار AI — حالت تحلیلگر، نظارت انسانی، خودکار.

جدا از exploration_mode (عمق تحلیل agent).
"""
from __future__ import annotations

from typing import Optional

from app.services.ai.ai_exploration_service import (
    EXPLORATION_MODE_AUTO,
    EXPLORATION_MODE_EXPLORE,
)
from app.services.ai.ai_write_guard import get_risk_level, is_write_function

EXECUTION_MODE_ANALYZER = "analyzer"
EXECUTION_MODE_SUPERVISED = "supervised"
EXECUTION_MODE_AUTONOMOUS = "autonomous"

VALID_EXECUTION_MODES = frozenset({
    EXECUTION_MODE_ANALYZER,
    EXECUTION_MODE_SUPERVISED,
    EXECUTION_MODE_AUTONOMOUS,
})

DEFAULT_EXECUTION_MODE = EXECUTION_MODE_ANALYZER

# عملیات پرریسک — حتی در حالت خودکار نیاز به تأیید صریح دارند.
HIGH_RISK_ALWAYS_APPROVE = frozenset({
    "delete_person",
    "delete_invoice",
    "delete_workflow",
    "execute_workflow",
    "create_workflow",
    "update_workflow",
    "export_business_data",
    "set_default_report_template",
    "publish_report_template",
    "adjust_customer_club_points",
    "recalculate_customer_club_rfm",
    "update_customer_club_settings",
})

EXECUTION_MODE_LABELS_FA = {
    EXECUTION_MODE_ANALYZER: "تحلیلگر",
    EXECUTION_MODE_SUPERVISED: "با تأیید من",
    EXECUTION_MODE_AUTONOMOUS: "خودکار",
}

EXECUTION_MODE_DESCRIPTIONS_FA = {
    EXECUTION_MODE_ANALYZER: "فقط خواندن و تحلیل داده‌ها — بدون تغییر در سیستم",
    EXECUTION_MODE_SUPERVISED: "هر تغییر قبل از اجرا نیاز به تأیید شما دارد",
    EXECUTION_MODE_AUTONOMOUS: "اجرای مستقیم تغییرات؛ عملیات پرریسک همچنان تأیید می‌خواهند",
}


def resolve_execution_mode(value: Optional[str]) -> str:
    mode = (value or DEFAULT_EXECUTION_MODE).strip().lower()
    if mode not in VALID_EXECUTION_MODES:
        return DEFAULT_EXECUTION_MODE
    return mode


def exposes_write_tools(execution_mode: str) -> bool:
    return resolve_execution_mode(execution_mode) != EXECUTION_MODE_ANALYZER


def exploration_mode_for_execution(execution_mode: str) -> str:
    """پیش‌فرض exploration بر اساس سیاست اجرا."""
    if resolve_execution_mode(execution_mode) == EXECUTION_MODE_ANALYZER:
        return EXPLORATION_MODE_EXPLORE
    return EXPLORATION_MODE_AUTO


def execution_mode_prompt_block(execution_mode: str) -> str:
    mode = resolve_execution_mode(execution_mode)
    if mode == EXECUTION_MODE_ANALYZER:
        return (
            "\n\n[حالت اجرا: تحلیلگر]\n"
            "شما در حالت مشاوره‌ای و فقط-خواندنی هستید.\n"
            "- فقط از ابزارهای خواندنی برای تحلیل داده‌های کسب‌وکار استفاده کنید.\n"
            "- هیچ ابزار نوشتنی (ایجاد، ویرایش، حذف) فراخوانی نکنید.\n"
            "- اگر کاربر درخواست تغییر داده کرد، توضیح دهید که در این حالت امکان ثبت تغییر نیست "
            "و پیشنهاد کنید حالت «با تأیید من» یا «خودکار» را انتخاب کند."
        )
    if mode == EXECUTION_MODE_SUPERVISED:
        return (
            "\n\n[حالت اجرا: با تأیید من]\n"
            "قبل از هر عملیات نوشتنی (ایجاد، ویرایش، حذف)، سیستم از کاربر تأیید می‌گیرد.\n"
            "خلاصهٔ عملیات پیشنهادی را شفاف بیان کنید و منتظر تأیید کاربر بمانید."
        )
    return (
        "\n\n[حالت اجرا: خودکار]\n"
        "می‌توانید عملیات نوشتنی معمولی را مستقیم اجرا کنید.\n"
        "عملیات پرریسک (حذف، workflow، export و …) همچنان نیاز به تأیید کاربر دارند.\n"
        "پس از هر تغییر، خلاصهٔ اقدام انجام‌شده را گزارش دهید."
    )


def is_high_risk_write(function_name: str, registry=None) -> bool:
    if function_name in HIGH_RISK_ALWAYS_APPROVE:
        return True
    return get_risk_level(function_name, registry) == "high"


def should_block_write_in_analyzer(execution_mode: str, function_name: str, registry=None) -> bool:
    if resolve_execution_mode(execution_mode) != EXECUTION_MODE_ANALYZER:
        return False
    return is_write_function(function_name, registry)


def should_require_write_approval(
    execution_mode: str,
    function_name: str,
    *,
    approve_writes: bool,
    registry=None,
) -> bool:
    """آیا قبل از اجرا باید APPROVAL_REQUIRED برگردد؟"""
    if not is_write_function(function_name, registry):
        return False
    mode = resolve_execution_mode(execution_mode)
    if mode == EXECUTION_MODE_ANALYZER:
        return False
    if mode == EXECUTION_MODE_SUPERVISED:
        return not approve_writes
    # autonomous — فقط پرریسک
    if is_high_risk_write(function_name, registry):
        return not approve_writes
    return False
