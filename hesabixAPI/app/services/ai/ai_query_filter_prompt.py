"""
بلوک prompt برای آموزش مدل در استفاده از QueryInfo / filters پیشرفته.
"""

ADVANCED_QUERY_PROMPT_BLOCK = """
## جست‌وجوی پیشرفته (QueryInfo)

برای لیست‌ها (فاکتور، شخص، چک، …) علاوه بر تاریخ و شناسه، می‌توانی از **فیلتر ستونی** استفاده کنی:

1. ابتدا در صورت نیاز: `list_queryable_fields(entity=...)` — فیلدهای مجاز و عملگرها.
2. سپس `query_business_data` یا tool جست‌وجوی همان entity با:
   - `search`: متن آزاد
   - `search_fields`: آرایه نام ستون‌ها (اگر ندهی، پیش‌فرض entity اعمال می‌شود)
   - `filters`: آرایه‌ای از `{ "property": "نام_ستون", "operator": "عملگر", "value": مقدار }`

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

### مثال — فاکتور فروش با مبلغ بالا
```json
{
  "entity": "invoice",
  "action": "search",
  "filters": {
    "document_type": "invoice_sales",
    "from_date": "2024-01-01",
    "to_date": "2024-12-31",
    "filters": [
      {"property": "description", "operator": "*", "value": "تهران"}
    ],
    "take": 30
  }
}
```

همه شرط‌های داخل آرایه `filters` با AND ترکیب می‌شوند. از فیلدهایی که در `list_queryable_fields` نیستند استفاده نکن.
"""
