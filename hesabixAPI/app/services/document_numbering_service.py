from __future__ import annotations

from typing import Optional
from datetime import datetime, date
from sqlalchemy.orm import Session
from sqlalchemy import and_

from sqlalchemy.exc import IntegrityError

from adapters.db.models.document_numbering import (
    BusinessDocumentNumberingSetting,
    DocumentNumberCounter,
)
from app.core.calendar import CalendarConverter


def _get_default_setting_for_type(document_type: str) -> dict:
    """
    برگرداندن تنظیمات پیش‌فرض برای هر نوع سند به صورت dict
    """
    defaults = {
        "invoice_sales": {
            "prefix": "INV",
            "include_date": True,
            "calendar_type": "gregorian",
            "date_format": "YYYYMMDD",
            "separator": "-",
            "start_number": 1,
            "number_padding": 4,
            "reset_period": "never",
        },
        "invoice_sales_return": {
            "prefix": "INV-RET",
            "include_date": True,
            "calendar_type": "gregorian",
            "date_format": "YYYYMMDD",
            "separator": "-",
            "start_number": 1,
            "number_padding": 4,
            "reset_period": "never",
        },
        "receipt": {
            "prefix": "RC",
            "include_date": True,
            "calendar_type": "gregorian",
            "date_format": "YYYYMMDD",
            "separator": "-",
            "start_number": 1,
            "number_padding": 4,
            "reset_period": "never",
        },
        "payment": {
            "prefix": "PY",
            "include_date": True,
            "calendar_type": "gregorian",
            "date_format": "YYYYMMDD",
            "separator": "-",
            "start_number": 1,
            "number_padding": 4,
            "reset_period": "never",
        },
        "transfer": {
            "prefix": "TR",
            "include_date": True,
            "calendar_type": "gregorian",
            "date_format": "YYYYMMDD",
            "separator": "-",
            "start_number": 1,
            "number_padding": 4,
            "reset_period": "never",
        },
    }

    default = defaults.get(
        document_type,
        {
            "prefix": "DOC",
            "include_date": True,
            "calendar_type": "gregorian",
            "date_format": "YYYYMMDD",
            "separator": "-",
            "start_number": 1,
            "number_padding": 4,
            "reset_period": "never",
        },
    )

    return default


def _format_date(document_date: date, date_format: str, calendar_type: str) -> str:
    """
    فرمت‌بندی تاریخ بر اساس نوع تقویم (شمسی یا میلادی)
    """
    # تبدیل date به datetime
    dt = datetime.combine(document_date, datetime.min.time())

    # تبدیل به تقویم مورد نظر
    if calendar_type == "jalali":
        cal_data = CalendarConverter.to_jalali(dt)
        year = cal_data["year"]
        month = cal_data["month"]
        day = cal_data["day"]
    else:  # gregorian
        cal_data = CalendarConverter.to_gregorian(dt)
        year = cal_data["year"]
        month = cal_data["month"]
        day = cal_data["day"]

    # فرمت‌بندی بر اساس الگو
    formatted = date_format

    # جایگزینی سال
    formatted = formatted.replace("YYYY", f"{year:04d}")
    formatted = formatted.replace("YY", f"{year % 100:02d}")

    # جایگزینی ماه
    formatted = formatted.replace("MM", f"{month:02d}")
    formatted = formatted.replace("M", f"{month}")

    # جایگزینی روز
    formatted = formatted.replace("DD", f"{day:02d}")
    formatted = formatted.replace("D", f"{day}")

    return formatted


def _build_bucket_key(document_date: date, calendar_type: str, reset_period: Optional[str]) -> str:
    period = (reset_period or "never").lower()
    dt = datetime.combine(document_date, datetime.min.time())
    if calendar_type == "jalali":
        cal = CalendarConverter.to_jalali(dt)
    else:
        cal = CalendarConverter.to_gregorian(dt)
    year = cal["year"]
    month = cal["month"]
    day = cal["day"]

    if period == "daily":
        return f"{calendar_type}-D-{year:04d}{month:02d}{day:02d}"
    if period == "monthly":
        return f"{calendar_type}-M-{year:04d}{month:02d}"
    if period == "yearly":
        return f"{calendar_type}-Y-{year:04d}"
    return f"{calendar_type}-ALL"


def _get_next_number(
    db: Session,
    business_id: int,
    document_type: str,
    start_number: int,
    padding: int,
    reset_period: Optional[str],
    document_date: date,
    calendar_type: str = "gregorian",
) -> str:
    """
    دریافت شماره بعدی با استفاده از جدول شمارنده
    """
    bucket_key = _build_bucket_key(document_date, calendar_type, reset_period)

    counter_query = db.query(DocumentNumberCounter).filter(
        and_(
            DocumentNumberCounter.business_id == business_id,
            DocumentNumberCounter.document_type == document_type,
            DocumentNumberCounter.date_bucket == bucket_key,
        )
    )

    counter: DocumentNumberCounter | None = None
    max_attempts = 5
    for _ in range(max_attempts):
        counter = counter_query.with_for_update().first()
        if counter:
            break
        try:
            with db.begin_nested():
                counter = DocumentNumberCounter(
                    business_id=business_id,
                    document_type=document_type,
                    date_bucket=bucket_key,
                    last_number=start_number - 1,
                )
                db.add(counter)
                db.flush()
            break
        except IntegrityError:
            continue

    if not counter:
        raise RuntimeError("Failed to initialize document counter.")

    next_num = counter.last_number + 1
    if next_num < start_number:
        next_num = start_number

    counter.last_number = next_num
    counter.updated_at = datetime.utcnow()
    db.flush()

    return f"{next_num:0{padding}d}"


def generate_document_code(
    db: Session,
    business_id: int,
    document_type: str,
    document_date: date,
) -> str:
    """
    تولید شماره سند بر اساس تنظیمات کسب و کار یا پیش‌فرض
    """
    # دریافت تنظیمات از دیتابیس
    setting = (
        db.query(BusinessDocumentNumberingSetting)
        .filter(
            and_(
                BusinessDocumentNumberingSetting.business_id == business_id,
                BusinessDocumentNumberingSetting.document_type == document_type,
                BusinessDocumentNumberingSetting.is_active == True,
            )
        )
        .first()
    )

    # اگر تنظیمات وجود نداشت، از پیش‌فرض استفاده کن
    if not setting:
        default_dict = _get_default_setting_for_type(document_type)
        prefix = default_dict.get("prefix", "DOC")
        separator = default_dict.get("separator", "-")
        include_date = default_dict.get("include_date", True)
        date_format = default_dict.get("date_format", "YYYYMMDD")
        calendar_type = default_dict.get("calendar_type", "gregorian")
        start_number = default_dict.get("start_number", 1)
        number_padding = default_dict.get("number_padding", 4)
        reset_period = default_dict.get("reset_period", "never")
    else:
        prefix = setting.prefix or "DOC"
        separator = setting.separator or "-"
        include_date = setting.include_date
        date_format = setting.date_format or "YYYYMMDD"
        calendar_type = setting.calendar_type or "gregorian"
        start_number = setting.start_number or 1
        number_padding = setting.number_padding or 4
        reset_period = setting.reset_period

    # بخش تاریخ
    date_part = ""
    if include_date:
        date_part = _format_date(document_date, date_format, calendar_type)

    # بخش شماره
    number_part = _get_next_number(
        db,
        business_id,
        document_type,
        start_number,
        number_padding,
        reset_period,
        document_date,
        calendar_type,
    )

    # ترکیب نهایی
    if date_part:
        return f"{prefix}{separator}{date_part}{separator}{number_part}"
    else:
        return f"{prefix}{separator}{number_part}"

