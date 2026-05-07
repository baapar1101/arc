"""
ترجمه متای تریگرهای چت وب CRM (fa/en) برای API متادیتا ورک‌فلو.
"""
from __future__ import annotations

_CRM_CHAT_CONFIG_COMMON_FA: dict[str, str] = {
    "field_enabled": "فعال‌بودن تریگر",
    "field_enabled_desc": "اگر خاموش باشد این ورک‌فلو با این تریگر اجرا نمی‌شود",
    "field_widget_id_filter": "محدود به ویجت",
    "field_widget_id_filter_desc": "فقط اگر شناسه ویجت چت با این مقدار یکسان باشد؛ خالی یعنی همه ویجت‌ها",
    "field_cooldown_seconds": "حداقل فاصله بین اجرا (ثانیه)",
    "field_cooldown_seconds_desc": "پس از یک اجرا، تا این مدت تریگر دوباره برای همان ورک‌فلو اجرا نمی‌شود",
}

_CRM_CHAT_CONFIG_COMMON_EN: dict[str, str] = {
    "field_enabled": "Trigger enabled",
    "field_enabled_desc": "When off, this workflow will not run for this trigger",
    "field_widget_id_filter": "Restrict to widget",
    "field_widget_id_filter_desc": "Only when the web chat widget id equals this value; empty means all widgets",
    "field_cooldown_seconds": "Minimum cooldown (seconds)",
    "field_cooldown_seconds_desc": "After a run, suppress retriggers for this workflow until this interval passes",
}

CRM_CHAT_CONVERSATION_STARTED_TRANSLATIONS: dict[str, dict[str, str]] = {
    "fa": {
        "trigger_name": "شروع مکالمه چت وب",
        "trigger_description": "اولین ثبت مکالمه پس از تکمیل فرم بازدیدکننده (نام، نام خانوادگی، ایمیل، تلفن)",
        **_CRM_CHAT_CONFIG_COMMON_FA,
    },
    "en": {
        "trigger_name": "CRM web chat conversation started",
        "trigger_description": "When a visitor submits the identity form and a conversation record is created",
        **_CRM_CHAT_CONFIG_COMMON_EN,
    },
}

CRM_CHAT_MESSAGE_RECEIVED_TRANSLATIONS: dict[str, dict[str, str]] = {
    "fa": {
        "trigger_name": "پیام جدید از بازدیدکننده (چت وب)",
        "trigger_description": "وقتی بازدیدکننده پیام متنی یا با فایل در ویجت چت می‌فرستد",
        **_CRM_CHAT_CONFIG_COMMON_FA,
    },
    "en": {
        "trigger_name": "CRM web chat visitor message received",
        "trigger_description": "When a visitor sends a text message or a file in the web chat widget",
        **_CRM_CHAT_CONFIG_COMMON_EN,
    },
}

CRM_CHAT_MESSAGE_SENT_TRANSLATIONS: dict[str, dict[str, str]] = {
    "fa": {
        "trigger_name": "پاسخ عامل در چت وب",
        "trigger_description": "وقتی کاربر CRM یا سیستم از طرف عامل پیام ارسال کند",
        **_CRM_CHAT_CONFIG_COMMON_FA,
        "field_ignore_workflow_automation": "نادیده گرفتن پیام اتوماسیون ورک‌فلو",
        "field_ignore_workflow_automation_desc": "اگر روشن باشد، پیام‌هایی که با اتوماسیون ارسال شده‌اند تریگر نمی‌شوند",
        "field_ignore_operator_relay": "نادیده گرفتن پل تلگرام/بله",
        "field_ignore_operator_relay_desc": "اگر روشن باشد، پیام‌های ارسالی از کانال اپراتور تلگرام/بله تریگر نمی‌شوند",
    },
    "en": {
        "trigger_name": "CRM web chat agent message sent",
        "trigger_description": "When a CRM user or automation posts an agent message in web chat",
        **_CRM_CHAT_CONFIG_COMMON_EN,
        "field_ignore_workflow_automation": "Ignore workflow automation messages",
        "field_ignore_workflow_automation_desc": "When on, messages sent by workflow automation will not fire this trigger",
        "field_ignore_operator_relay": "Ignore Telegram/Bale operator relay",
        "field_ignore_operator_relay_desc": "When on, messages relayed from operator channels will not fire this trigger",
    },
}

CRM_CHAT_CONVERSATION_ASSIGNED_TRANSLATIONS: dict[str, dict[str, str]] = {
    "fa": {
        "trigger_name": "تخصیص مکالمه چت وب",
        "trigger_description": "وقتی مسئول مکالمه (کاربر عامل) تغییر کند",
        **_CRM_CHAT_CONFIG_COMMON_FA,
        "field_new_assigned_to_user_id_filter": "فقط مسئول جدید",
        "field_new_assigned_to_user_id_filter_desc": "فقط وقتی شناسه کاربر مسئول جدید با این مقدار برابر است؛ خالی یعنی همه",
    },
    "en": {
        "trigger_name": "CRM web chat conversation assigned",
        "trigger_description": "When the assignee (agent user) of a conversation changes",
        **_CRM_CHAT_CONFIG_COMMON_EN,
        "field_new_assigned_to_user_id_filter": "Filter by new assignee",
        "field_new_assigned_to_user_id_filter_desc": "Only when the new assignee user id equals this; empty means any",
    },
}

CRM_CHAT_CONVERSATION_RESOLVED_TRANSLATIONS: dict[str, dict[str, str]] = {
    "fa": {
        "trigger_name": "حل‌شدن مکالمه چت وب",
        "trigger_description": "وقتی وضعیت مکالمه به resolved تنظیم شود",
        **_CRM_CHAT_CONFIG_COMMON_FA,
    },
    "en": {
        "trigger_name": "CRM web chat conversation resolved",
        "trigger_description": "When the conversation status is set to resolved",
        **_CRM_CHAT_CONFIG_COMMON_EN,
    },
}

CRM_CHAT_CONVERSATION_REOPENED_TRANSLATIONS: dict[str, dict[str, str]] = {
    "fa": {
        "trigger_name": "بازگشایی مکالمه چت وب",
        "trigger_description": "وقتی مکالمه از حالت resolved خارج شود یا وضعیت تغییر کند",
        **_CRM_CHAT_CONFIG_COMMON_FA,
    },
    "en": {
        "trigger_name": "CRM web chat conversation reopened",
        "trigger_description": "When a resolved conversation is reopened or status changes from resolved",
        **_CRM_CHAT_CONFIG_COMMON_EN,
    },
}
