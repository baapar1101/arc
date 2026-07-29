"""
تبدیل و بازهٔ تاریخ برای ابزارهای AI — ورودی کاربر/مدل به ISO میلادی و نمایش بر اساس تقویم.
"""
from __future__ import annotations

from calendar import monthrange
from dataclasses import dataclass
from datetime import date, datetime, timedelta
from typing import Any, Dict, List, Optional, Tuple

import jdatetime
from sqlalchemy.orm import Session

from app.core.business_calendar import business_today
from app.core.calendar import CalendarType
from app.core.date_input import (
    DateParseError,
    format_user_date,
    gregorian_month_range,
    jalali_month_range,
    normalize_date_range,
    parse_user_date,
)
from app.services.ai.ai_query_filter_catalog import get_entity_query_spec

_DATE_FLAT_KEYS = frozenset({"from_date", "to_date", "date_from", "date_to", "as_of_date"})
_DATE_FILTER_PROPERTIES = frozenset(
    {"document_date", "due_date", "issue_date", "registered_at", "created_at"}
)

_RELATIVE_PRESETS = frozenset({
    "today",
    "yesterday",
    "this_week",
    "last_week",
    "last_7_days",
    "last_30_days",
    "this_month",
    "last_month",
    "this_year",
    "last_year",
})


@dataclass(frozen=True)
class ResolvedDateRange:
    from_date: date
    to_date: date
    calendar_type: CalendarType
    description_fa: str

    def to_dict(self) -> Dict[str, Any]:
        return {
            "from_date": self.from_date.isoformat(),
            "to_date": self.to_date.isoformat(),
            "from_date_display": format_user_date(self.from_date, calendar_type=self.calendar_type),
            "to_date_display": format_user_date(self.to_date, calendar_type=self.calendar_type),
            "calendar_type": self.calendar_type,
            "description_fa": self.description_fa,
        }


def calendar_type_from_context(context: Optional[Dict[str, Any]]) -> CalendarType:
    if not context:
        return "jalali"
    raw = context.get("calendar_type")
    if raw in ("jalali", "gregorian"):
        return raw
    uc = context.get("user_context")
    if uc is not None and hasattr(uc, "get_calendar_type"):
        return uc.get_calendar_type()
    return "jalali"


def _week_bounds(anchor: date) -> Tuple[date, date]:
    """شنبه تا جمعه (تقویم کاری ایران)."""
    weekday = anchor.weekday()  # Mon=0
    days_since_saturday = (weekday + 2) % 7
    start = anchor - timedelta(days=days_since_saturday)
    end = start + timedelta(days=6)
    return start, end


def resolve_relative_date_range(
    relative: str,
    *,
    calendar_type: CalendarType = "jalali",
    business_id: Optional[int] = None,
    jalali_year: Optional[int] = None,
    jalali_month: Optional[int] = None,
    gregorian_year: Optional[int] = None,
    gregorian_month: Optional[int] = None,
) -> ResolvedDateRange:
    today = business_today(business_id)
    rel = (relative or "").strip().lower()

    if jalali_year is not None and jalali_month is not None:
        start, end = jalali_month_range(int(jalali_year), int(jalali_month))
        return ResolvedDateRange(
            from_date=start,
            to_date=end,
            calendar_type=calendar_type,
            description_fa=f"ماه {jalali_month} سال {jalali_year} شمسی",
        )

    if gregorian_year is not None and gregorian_month is not None:
        start, end = gregorian_month_range(int(gregorian_year), int(gregorian_month))
        return ResolvedDateRange(
            from_date=start,
            to_date=end,
            calendar_type=calendar_type,
            description_fa=f"ماه {gregorian_month} سال {gregorian_year} میلادی",
        )

    if rel == "today":
        return ResolvedDateRange(today, today, calendar_type, "امروز")
    if rel == "yesterday":
        y = today - timedelta(days=1)
        return ResolvedDateRange(y, y, calendar_type, "دیروز")
    if rel == "this_week":
        start, end = _week_bounds(today)
        return ResolvedDateRange(start, end, calendar_type, "هفته جاری")
    if rel == "last_week":
        start, _ = _week_bounds(today)
        end = start - timedelta(days=1)
        start = end - timedelta(days=6)
        return ResolvedDateRange(start, end, calendar_type, "هفته قبل")
    if rel == "last_7_days":
        return ResolvedDateRange(today - timedelta(days=6), today, calendar_type, "۷ روز اخیر")
    if rel == "last_30_days":
        return ResolvedDateRange(today - timedelta(days=29), today, calendar_type, "۳۰ روز اخیر")

    if rel == "this_month":
        if calendar_type == "jalali":
            jn = jdatetime.date.fromgregorian(date=today)
            start, end = jalali_month_range(jn.year, jn.month)
            return ResolvedDateRange(start, end, calendar_type, "ماه جاری (شمسی)")
        start = today.replace(day=1)
        end = today.replace(day=monthrange(today.year, today.month)[1])
        return ResolvedDateRange(start, end, calendar_type, "ماه جاری (میلادی)")

    if rel == "last_month":
        if calendar_type == "jalali":
            jn = jdatetime.date.fromgregorian(date=today)
            m, y = jn.month - 1, jn.year
            if m < 1:
                m, y = 12, y - 1
            start, end = jalali_month_range(y, m)
            return ResolvedDateRange(start, end, calendar_type, "ماه قبل (شمسی)")
        first_this = today.replace(day=1)
        end = first_this - timedelta(days=1)
        start = end.replace(day=1)
        return ResolvedDateRange(start, end, calendar_type, "ماه قبل (میلادی)")

    if rel == "this_year":
        if calendar_type == "jalali":
            jy = jdatetime.date.fromgregorian(date=today).year
            start, _ = jalali_month_range(jy, 1)
            _, end = jalali_month_range(jy, 12)
            return ResolvedDateRange(start, end, calendar_type, f"سال {jy} شمسی")
        start = date(today.year, 1, 1)
        end = date(today.year, 12, 31)
        return ResolvedDateRange(start, end, calendar_type, f"سال {today.year} میلادی")

    if rel == "last_year":
        if calendar_type == "jalali":
            jy = jdatetime.date.fromgregorian(date=today).year - 1
            start, _ = jalali_month_range(jy, 1)
            _, end = jalali_month_range(jy, 12)
            return ResolvedDateRange(start, end, calendar_type, f"سال {jy} شمسی")
        y = today.year - 1
        return ResolvedDateRange(date(y, 1, 1), date(y, 12, 31), calendar_type, f"سال {y} میلادی")

    if rel not in _RELATIVE_PRESETS and rel:
        raise ValueError(
            f"relative نامعتبر: {relative}. "
            f"مجاز: {', '.join(sorted(_RELATIVE_PRESETS))}"
        )
    raise ValueError("یکی از relative، jalali_year/month یا gregorian_year/month را مشخص کنید.")


def resolve_fiscal_year_range(
    db: Session,
    business_id: int,
    fiscal_year_id: int,
    *,
    calendar_type: CalendarType = "jalali",
) -> ResolvedDateRange:
    from adapters.db.repositories.fiscal_year_repo import FiscalYearRepository

    fy = FiscalYearRepository(db).get_by_id(int(fiscal_year_id))
    if not fy or fy.business_id != business_id:
        raise ValueError(f"سال مالی {fiscal_year_id} یافت نشد")
    if not fy.start_date:
        raise ValueError("تاریخ شروع سال مالی تعریف نشده")
    start = fy.start_date
    end = fy.end_date or business_today(business_id)
    return ResolvedDateRange(
        from_date=start,
        to_date=end,
        calendar_type=calendar_type,
        description_fa=fy.title or f"سال مالی {fiscal_year_id}",
    )


def resolve_date_range_for_ai(
    db: Optional[Session],
    business_id: Optional[int],
    args: Dict[str, Any],
    *,
    calendar_type: CalendarType = "jalali",
) -> Dict[str, Any]:
    """ورودی ابزار resolve_date_range."""
    relative = args.get("relative")
    if relative:
        resolved = resolve_relative_date_range(
            str(relative),
            calendar_type=calendar_type,
            business_id=business_id,
            jalali_year=args.get("jalali_year"),
            jalali_month=args.get("jalali_month"),
            gregorian_year=args.get("gregorian_year"),
            gregorian_month=args.get("gregorian_month"),
        )
        return resolved.to_dict()

    fiscal_year_id = args.get("fiscal_year_id")
    if fiscal_year_id is not None:
        if db is None or business_id is None:
            raise ValueError("fiscal_year_id نیاز به context کسب‌وکار دارد")
        return resolve_fiscal_year_range(
            db, int(business_id), int(fiscal_year_id), calendar_type=calendar_type
        ).to_dict()

    from_raw = args.get("from_date") or args.get("date_from")
    to_raw = args.get("to_date") or args.get("date_to")
    if from_raw or to_raw:
        from_parsed, to_parsed = normalize_date_range(
            from_raw, to_raw, calendar_type=calendar_type
        )
        if from_parsed is None or to_parsed is None:
            raise ValueError("هر دو from_date و to_date برای بازهٔ صریح الزامی است")
        desc = (
            f"از {format_user_date(from_parsed, calendar_type=calendar_type)} "
            f"تا {format_user_date(to_parsed, calendar_type=calendar_type)}"
        )
        return ResolvedDateRange(from_parsed, to_parsed, calendar_type, desc).to_dict()

    raise ValueError(
        "یکی از relative، fiscal_year_id، jalali_year+jalali_month، "
        "یا from_date+to_date را بدهید."
    )


def _normalize_filter_date_values(
    filters: List[Dict[str, Any]],
    *,
    entity: Optional[str],
    calendar_type: CalendarType,
) -> List[Dict[str, Any]]:
    spec = get_entity_query_spec(entity) if entity else None
    date_props = set(_DATE_FILTER_PROPERTIES)
    if spec:
        date_props |= {f.property for f in spec.filterable_fields if f.type == "date"}

    out: List[Dict[str, Any]] = []
    for item in filters:
        row = dict(item)
        prop = str(row.get("property") or "")
        val = row.get("value")
        if prop in date_props and val is not None and val != "":
            if isinstance(val, list):
                row["value"] = [
                    parse_user_date(v, calendar_type=calendar_type).isoformat()
                    if v is not None and v != ""
                    else v
                    for v in val
                ]
            else:
                row["value"] = parse_user_date(val, calendar_type=calendar_type).isoformat()
        out.append(row)
    return out


def normalize_query_dates(
    query: Dict[str, Any],
    *,
    calendar_type: CalendarType = "jalali",
    entity: Optional[str] = None,
) -> Dict[str, Any]:
    """نرمال‌سازی کلیدهای تاریخ در dict فیلتر AI قبل از ارسال به سرویس."""
    q = dict(query or {})

    alias_map = {"date_from": "from_date", "date_to": "to_date"}
    for src, dst in alias_map.items():
        if q.get(src) is not None and q.get(dst) is None:
            q[dst] = q.pop(src)
        elif src in q:
            q.pop(src, None)

    from_raw = q.get("from_date")
    to_raw = q.get("to_date")
    if from_raw is not None or to_raw is not None:
        from_parsed, to_parsed = normalize_date_range(
            from_raw, to_raw, calendar_type=calendar_type
        )
        if from_parsed is not None:
            q["from_date"] = from_parsed.isoformat()
        if to_parsed is not None:
            q["to_date"] = to_parsed.isoformat()

    if q.get("as_of_date"):
        q["as_of_date"] = parse_user_date(
            q["as_of_date"], calendar_type=calendar_type
        ).isoformat()

    if q.get("filters"):
        q["filters"] = _normalize_filter_date_values(
            q["filters"], entity=entity, calendar_type=calendar_type
        )

    return q


def filters_applied_display(
    applied: Dict[str, Any],
    *,
    calendar_type: CalendarType = "jalali",
) -> Dict[str, Any]:
    """نسخهٔ نمایشی filters_applied برای مدل/کاربر."""
    out = dict(applied or {})
    for key in ("from_date", "to_date", "date_from", "date_to", "as_of_date"):
        raw = out.get(key)
        if raw:
            try:
                d = parse_user_date(raw, calendar_type="gregorian")
                out[f"{key}_display"] = format_user_date(d, calendar_type=calendar_type)
            except DateParseError:
                pass
    return out


def enrich_tool_result_dates(
    result: Any,
    *,
    calendar_type: CalendarType = "jalali",
) -> Any:
    """افزودن فیلدهای *_display برای تاریخ‌های ISO در نتیجه tool."""
    if not isinstance(result, dict):
        return result

    out = dict(result)
    if "filters_applied" in out and isinstance(out["filters_applied"], dict):
        out["filters_applied_display"] = filters_applied_display(
            out["filters_applied"], calendar_type=calendar_type
        )

    date_field_names = (
        "document_date",
        "due_date",
        "issue_date",
        "registered_at",
        "created_at",
        "start_date",
        "end_date",
    )
    for key in ("items", "data", "results", "invoices", "products", "persons"):
        items = out.get(key)
        if not isinstance(items, list):
            continue
        enriched: List[Dict[str, Any]] = []
        for row in items[:50]:
            if not isinstance(row, dict):
                enriched.append(row)
                continue
            row_copy = dict(row)
            for fname in date_field_names:
                if fname in row_copy and row_copy[fname]:
                    try:
                        d = parse_user_date(row_copy[fname], calendar_type="gregorian")
                        row_copy[f"{fname}_display"] = format_user_date(
                            d, calendar_type=calendar_type
                        )
                    except DateParseError:
                        pass
            enriched.append(row_copy)
        out[key] = enriched
        break
    return out
