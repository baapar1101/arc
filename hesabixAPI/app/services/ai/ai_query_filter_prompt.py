"""
بلوک prompt برای آموزش مدل در استفاده از QueryInfo / filters پیشرفته.
"""

from __future__ import annotations

from app.core.calendar import CalendarType


def build_advanced_query_prompt_block(calendar_type: CalendarType = "jalali") -> str:
    if calendar_type == "jalali":
        example_from, example_to = "1404/01/01", "1404/12/29"
        date_note = "تاریخ‌ها را می‌توانی شمسی `YYYY/MM/DD` یا میلادی `YYYY-MM-DD` بفرستی؛ سیستم تبدیل می‌کند."
    else:
        example_from, example_to = "2025-01-01", "2025-12-31"
        date_note = "تاریخ‌ها را میلادی `YYYY-MM-DD` بفرست."

    return f"""
## جست‌وجوی پیشرفته (QueryInfo)

برای لیست‌ها (فاکتور، شخص، چک، …) علاوه بر تاریخ و شناسه، می‌توانی از **فیلتر ستونی** استفاده کنی:

1. برای بازهٔ تاریخ مبهم: `resolve_date_range` (مثلاً relative=last_month).
2. در صورت نیاز: `list_queryable_fields(entity=...)` — فیلدهای مجاز و عملگرها.
3. سپس `query_business_data` یا tool جست‌وجوی همان entity با:
   - `from_date` / `to_date`: بازهٔ تاریخ ({date_note})
   - `search`: متن آزاد
   - `search_fields`: آرایه نام ستون‌ها
   - `filters`: آرایه‌ای از `{{"property", "operator", "value"}}`

### عملگرها
| عملگر | معنی |
|--------|------|
| = | برابر |
| != | نابرابر |
| >, >=, <, <= | مقایسه (عدد/تاریخ) |
| * | شامل متن (مثل %علی%) |
| *? | شروع با |
| ?* | پایان با |
| in | مقدار در لیست (value آرایه) |

### مثال — فاکتور فروش در بازه
```json
{{
  "entity": "invoice",
  "action": "search",
  "filters": {{
    "document_type": "invoice_sales",
    "from_date": "{example_from}",
    "to_date": "{example_to}",
    "filters": [
      {{"property": "description", "operator": "*", "value": "تهران"}}
    ],
    "take": 30
  }}
}}
```

همه شرط‌های داخل آرایه `filters` با AND ترکیب می‌شوند. از فیلدهایی که در `list_queryable_fields` نیستند استفاده نکن.
""".strip()


# سازگاری با seed و importهای قدیمی (پیش‌فرض شمسی)
ADVANCED_QUERY_PROMPT_BLOCK = build_advanced_query_prompt_block("jalali")
