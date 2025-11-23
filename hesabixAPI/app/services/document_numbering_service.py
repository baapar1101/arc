from __future__ import annotations

from typing import Optional
from datetime import datetime, date, timedelta
from sqlalchemy.orm import Session
from sqlalchemy import and_

from adapters.db.models.document_numbering import BusinessDocumentNumberingSetting
from adapters.db.models.document import Document
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


def _get_next_number(
    db: Session,
    business_id: int,
    document_type: str,
    start_number: int,
    padding: int,
    reset_period: Optional[str],
    document_date: date,
    calendar_type: str = "gregorian",
    separator: str = "-",
) -> str:
    """
    دریافت شماره بعدی بر اساس دوره ریست
    """
    # تعیین محدوده جستجو بر اساس reset_period
    if reset_period == "daily":
        date_from = document_date
        date_to = document_date
    elif reset_period == "monthly":
        date_from = document_date.replace(day=1)
        date_to = (date_from + timedelta(days=32)).replace(day=1) - timedelta(days=1)
    elif reset_period == "yearly":
        date_from = document_date.replace(month=1, day=1)
        date_to = document_date.replace(month=12, day=31)
    else:  # never
        date_from = None
        date_to = None

    # جستجوی آخرین سند
    query = db.query(Document).filter(
        and_(
            Document.business_id == business_id,
            Document.document_type == document_type,
        )
    )

    if date_from and date_to:
        if calendar_type == "jalali" and reset_period in ["daily", "monthly", "yearly"]:
            # برای تقویم شمسی، باید اسناد را بر اساس تاریخ شمسی فیلتر کنیم
            query = query.filter(
                and_(
                    Document.document_date >= date_from,
                    Document.document_date <= date_to,
                )
            )
            # سپس در Python، اسناد را بر اساس تاریخ شمسی فیلتر می‌کنیم
            docs = query.all()
            dt = datetime.combine(document_date, datetime.min.time())
            target_jalali = CalendarConverter.to_jalali(dt)

            filtered_docs = []
            for doc in docs:
                doc_dt = datetime.combine(doc.document_date, datetime.min.time())
                doc_jalali = CalendarConverter.to_jalali(doc_dt)

                if reset_period == "daily":
                    if (
                        doc_jalali["year"] == target_jalali["year"]
                        and doc_jalali["month"] == target_jalali["month"]
                        and doc_jalali["day"] == target_jalali["day"]
                    ):
                        filtered_docs.append(doc)
                elif reset_period == "monthly":
                    if (
                        doc_jalali["year"] == target_jalali["year"]
                        and doc_jalali["month"] == target_jalali["month"]
                    ):
                        filtered_docs.append(doc)
                elif reset_period == "yearly":
                    if doc_jalali["year"] == target_jalali["year"]:
                        filtered_docs.append(doc)

            last_doc = max(filtered_docs, key=lambda d: d.code) if filtered_docs else None
        else:
            # برای میلادی یا never، از فیلتر ساده استفاده می‌کنیم
            query = query.filter(
                and_(
                    Document.document_date >= date_from,
                    Document.document_date <= date_to,
                )
            )
            last_doc = query.order_by(Document.code.desc()).first()
    else:
        last_doc = query.order_by(Document.code.desc()).first()

    if last_doc:
        try:
            # استخراج شماره از کد آخرین سند
            parts = last_doc.code.split(separator)
            last_num = int(parts[-1])
            next_num = last_num + 1
        except Exception:
            next_num = start_number
    else:
        next_num = start_number

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
        separator,
    )

    # ترکیب نهایی
    if date_part:
        return f"{prefix}{separator}{date_part}{separator}{number_part}"
    else:
        return f"{prefix}{separator}{number_part}"

