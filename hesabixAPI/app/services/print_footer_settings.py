"""پاورقی PDF مشترک از تنظیمات عمومی چاپ (business_print_settings.document_type=all)."""

from __future__ import annotations

import datetime
from typing import Optional, Tuple

from sqlalchemy.orm import Session

from adapters.db.models.business_print_settings import BusinessPrintSettings
from app.core.calendar import CalendarConverter


def get_default_print_footer_flags(db: Session, business_id: int) -> Tuple[bool, bool]:
    row = (
        db.query(BusinessPrintSettings)
        .filter(
            BusinessPrintSettings.business_id == business_id,
            BusinessPrintSettings.document_type == "all",
        )
        .first()
    )
    if row is None:
        return (True, True)
    return (
        bool(getattr(row, "show_footer_print_time", True)),
        bool(getattr(row, "show_footer_preparer", True)),
    )


def build_print_meta_footer_line(
    db: Session,
    business_id: int,
    *,
    now: datetime.datetime,
    preparer_name: Optional[str],
    is_fa: bool,
    calendar_type: str,
) -> str:
    """همان الگوی فاکتور تک‌صفحه: زمان چاپ | تهیه‌کننده."""
    show_t, show_p = get_default_print_footer_flags(db, business_id)
    parts: list[str] = []
    printed_at_str = ""
    if show_t:
        try:
            cal = "jalali" if calendar_type == "jalali" else "gregorian"
            fd = CalendarConverter.format_datetime(now, cal)
            printed_at_str = (fd.get("formatted") or fd.get("date_only") or "") or ""
        except Exception:
            printed_at_str = now.strftime("%Y/%m/%d %H:%M")
        if printed_at_str:
            footer_label = "زمان چاپ" if is_fa else "Printed at"
            parts.append(f"{footer_label}: {printed_at_str}")
    name = (preparer_name or "").strip()
    if show_p and name:
        preparer_label = "تهیه‌کننده" if is_fa else "Prepared by"
        parts.append(f"{preparer_label}: {name}")
    return " | ".join(parts)


def build_generated_at_pdf_footer(
    db: Session,
    business_id: int,
    *,
    formatted_generated_at: str,
    preparer_name: Optional[str],
    is_fa: bool,
) -> str:
    """برای لیست‌ها و گزارش‌ها: «تولید شده در …» و اختیاری تهیه‌کننده."""
    show_t, show_p = get_default_print_footer_flags(db, business_id)
    parts: list[str] = []
    ts = (formatted_generated_at or "").strip()
    if show_t and ts:
        parts.append(f"تولید شده در {ts}" if is_fa else f"Generated at {ts}")
    name = (preparer_name or "").strip()
    if show_p and name:
        pl = "تهیه‌کننده" if is_fa else "Prepared by"
        parts.append(f"{pl}: {name}")
    return " | ".join(parts)


def build_report_title_and_time_footer(
    db: Session,
    business_id: int,
    *,
    title: str,
    time_part: str,
    preparer_name: Optional[str],
    is_fa: bool,
) -> str:
    """مثل «عنوان گزارش • زمان» به‌همراه تهیه‌کننده."""
    show_t, show_p = get_default_print_footer_flags(db, business_id)
    t = (title or "").strip()
    tp = (time_part or "").strip()
    core_parts: list[str] = []
    if t:
        core_parts.append(t)
    if show_t and tp:
        core_parts.append(tp)
    head = " • ".join(core_parts) if core_parts else ""
    name = (preparer_name or "").strip()
    if show_p and name:
        pl = "تهیه‌کننده" if is_fa else "Prepared by"
        return f"{head} | {pl}: {name}" if head else f"{pl}: {name}"
    return head


def merge_document_code_footer_with_meta(
    *,
    base_footer: str,
    meta_line: str,
) -> str:
    b = (base_footer or "").strip()
    m = (meta_line or "").strip()
    if b and m:
        return f"{b} | {m}"
    return b or m
