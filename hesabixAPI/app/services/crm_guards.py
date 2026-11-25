# noqa: D100
"""بررسی‌های مالکیت و تأیید صریح برای عملیات حساس CRM."""
from __future__ import annotations

from typing import Any, Optional
from urllib.parse import urlparse

from sqlalchemy.orm import Session

from adapters.db.models.currency import BusinessCurrency
from adapters.db.models.document import Document
from app.core.responses import ApiError


def normalize_allowed_origins(raw: Any) -> list[str]:
    """میزبان‌های مجاز را به حروف کوچک و بدون طرح (scheme) برمی‌گرداند."""
    if not raw or not isinstance(raw, list):
        return []
    hosts: list[str] = []
    seen: set[str] = set()
    for item in raw:
        text = str(item or "").strip().lower()
        if not text:
            continue
        if "://" in text:
            try:
                text = (urlparse(text).hostname or "").lower()
            except Exception:
                text = ""
        text = text.split("/")[0].split(":")[0].strip().lstrip(".")
        if not text or text in seen:
            continue
        seen.add(text)
        hosts.append(text)
    return hosts


def origins_unrestricted(raw: Any) -> bool:
    return len(normalize_allowed_origins(raw)) == 0


def require_allowed_origins(raw: Any) -> list[str]:
    """ویجت تازه یا ویرایش مبدأ بدون میزبان مجاز ساخته نمی‌شود.

    ویجت‌های قدیمی که از قبل لیست خالی دارند تا زمان ویرایش، رفتار قبلی را حفظ می‌کنند.
    """
    hosts = normalize_allowed_origins(raw)
    if not hosts:
        raise ApiError(
            "CRM_CHAT_ORIGINS_REQUIRED",
            "حداقل یک مبدأ مجاز برای ویجت چت لازم است.",
            http_status=400,
        )
    return hosts


def assert_bulk_delete_confirmed(*, status: Optional[str], confirm_all: bool) -> None:
    """حذف همه مکالمات فقط با پرچم صریح ممکن است. حذف یک وضعیت مشخص پرچم نمی‌خواهد."""
    if status:
        return
    if confirm_all:
        return
    raise ApiError(
        "CRM_CHAT_BULK_DELETE_CONFIRMATION_REQUIRED",
        "حذف همه مکالمات فقط با تأیید صریح ممکن است.",
        http_status=400,
    )


def assert_document_in_business(db: Session, business_id: int, document_id: Optional[int]) -> None:
    if document_id is None:
        return
    row = (
        db.query(Document.id)
        .filter(Document.id == int(document_id), Document.business_id == business_id)
        .first()
    )
    if row is None:
        raise ApiError(
            "CRM_DOCUMENT_NOT_IN_BUSINESS",
            "سند انتخاب‌شده متعلق به این کسب‌وکار نیست.",
            http_status=400,
        )


def assert_currency_enabled_for_business(db: Session, business_id: int, currency_id: Optional[int]) -> None:
    if currency_id is None:
        return
    row = (
        db.query(BusinessCurrency.id)
        .filter(
            BusinessCurrency.business_id == business_id,
            BusinessCurrency.currency_id == int(currency_id),
        )
        .first()
    )
    if row is None:
        raise ApiError(
            "CRM_CURRENCY_NOT_IN_BUSINESS",
            "ارز انتخاب‌شده برای این کسب‌وکار فعال نیست.",
            http_status=400,
        )
