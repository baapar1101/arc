"""تست قالب‌های پیش‌فرض رویدادهای نوتیفیکیشن کسب‌وکار."""

from __future__ import annotations

from unittest.mock import MagicMock

import pytest

from adapters.db.seed_data.notification_event_types_seed import (
    NOTIFICATION_EVENT_TYPES_ROWS,
    event_type_row_by_code,
)
from app.services.business_notification_service import (
    BusinessNotificationService,
    ResolvedNotificationTemplate,
)


def test_all_event_types_have_sms_default() -> None:
    missing = [
        row["code"]
        for row in NOTIFICATION_EVENT_TYPES_ROWS
        if not (row.get("default_sms_template") or "").strip()
    ]
    assert missing == [], f"رویدادهای بدون default_sms_template: {missing}"


def test_all_event_types_have_email_default() -> None:
    missing = [
        row["code"]
        for row in NOTIFICATION_EVENT_TYPES_ROWS
        if not (row.get("default_email_template") or "").strip()
    ]
    assert missing == [], f"رویدادهای بدون default_email_template: {missing}"


def test_all_event_types_have_email_subject() -> None:
    missing = [
        row["code"]
        for row in NOTIFICATION_EVENT_TYPES_ROWS
        if not (row.get("default_email_subject") or "").strip()
    ]
    assert missing == [], f"رویدادهای بدون default_email_subject: {missing}"


def test_event_type_row_by_code() -> None:
    row = event_type_row_by_code("invoice_share_link")
    assert row is not None
    assert "share_link" in row["default_sms_template"]


def test_resolve_template_uses_business_template_first() -> None:
    db = MagicMock()
    svc = BusinessNotificationService(db)

    business_tpl = MagicMock()
    business_tpl.body = "سلام {{ customer_name }}"
    business_tpl.subject = "موضوع"
    business_tpl.id = 99
    business_tpl.name = "قالب کسب‌وکار"

    svc.template_repo.find_active_template = MagicMock(return_value=business_tpl)

    resolved = svc._resolve_template(1, "invoice_share_link", "sms")
    assert resolved is not None
    assert resolved.source == "business"
    assert resolved.template_id == 99
    assert resolved.body == "سلام {{ customer_name }}"


def test_resolve_template_falls_back_to_system_default() -> None:
    db = MagicMock()
    svc = BusinessNotificationService(db)

    svc.template_repo.find_active_template = MagicMock(return_value=None)

    event_row = MagicMock()
    event_row.is_active = True
    event_row.name = "لینک فاکتور"
    event_row.default_sms_template = "لینک: {{ share_link }}"
    event_row.default_email_template = None
    event_row.default_email_subject = None

    svc.event_type_repo.get_by_code = MagicMock(return_value=event_row)

    resolved = svc._resolve_template(1, "invoice_share_link", "sms")
    assert isinstance(resolved, ResolvedNotificationTemplate)
    assert resolved.source == "system_default"
    assert resolved.template_id is None
    assert "share_link" in resolved.body


def test_resolve_template_returns_none_when_no_defaults() -> None:
    db = MagicMock()
    svc = BusinessNotificationService(db)

    svc.template_repo.find_active_template = MagicMock(return_value=None)

    event_row = MagicMock()
    event_row.is_active = True
    event_row.default_sms_template = ""
    svc.event_type_repo.get_by_code = MagicMock(return_value=event_row)

    assert svc._resolve_template(1, "unknown.event", "sms") is None
