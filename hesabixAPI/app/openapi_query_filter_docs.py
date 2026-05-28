"""
بخش مستندات OpenAPI — جستجو و فیلتر پیشرفته (QueryInfo).
در ابتدای description سند OpenAPI قرار می‌گیرد.
"""

OPENAPI_QUERY_FILTER_SECTION = """
---

## جستجو و فیلتر پیشرفته (QueryInfo)

بسیاری از endpointهای **لیست** (اشخاص، فاکتور، کالا، چک، دریافت/پرداخت، …) بدنهٔ JSON با ساختار **`QueryInfo`** می‌پذیرند. این همان مدلی است که UI حسابیکس در جداول داده استفاده می‌کند.

### ساختار کلی

```json
{
  "take": 20,
  "skip": 0,
  "sort_by": "created_at",
  "sort_desc": true,
  "search": "علی",
  "search_fields": ["alias_name", "mobile", "code"],
  "filters": [
    {"property": "is_active", "operator": "=", "value": true},
    {"property": "document_date", "operator": ">=", "value": "2024-01-01"},
    {"property": "description", "operator": "*", "value": "خرید"}
  ]
}
```

| فیلد | نوع | توضیح |
|------|-----|--------|
| `take` | integer | تعداد در صفحه (۱–۱۰۰۰، پیش‌فرض اغلب ۱۰–۲۰) |
| `skip` | integer | تعداد رکورد ردشده از ابتدا (صفحه‌بندی) |
| `sort_by` | string | نام ستون مرتب‌سازی |
| `sort_desc` | boolean | `true` = نزولی |
| `sort` | array | مرتب‌سازی چندسطحی: `[{"by":"document_date","desc":true}]` |
| `search` | string | جستجوی آزاد در `search_fields` |
| `search_fields` | string[] | ستون‌های جستجو؛ اگر خالی باشد پیش‌فرض endpoint اعمال می‌شود |
| `filters` | FilterItem[] | فیلترهای ستونی (همه با **AND**) |

### FilterItem — عملگرها

هر عنصر: `{ "property": "نام_ستون", "operator": "عملگر", "value": مقدار }`

| عملگر | معنی | مثال `value` |
|--------|------|----------------|
| `=` | برابر | `true`, `123`, `"invoice_sales"` |
| `!=` | نابرابر | |
| `>`, `>=`, `<`, `<=` | مقایسه عدد/تاریخ | `1000000`, `"2024-06-01"` |
| `*` | شامل متن (LIKE `%…%`) | `"تهران"` |
| `*?` | شروع با | `"INV"` |
| `?*` | پایان با | `"1403"` |
| `in` | عضو لیست | `["a","b"]` |
| `not_in` | خارج از لیست | (در برخی سرویس‌ها) |
| `is_null` | مقدار خالی | `null` |
| `is_not_null` | مقدار غیرخالی | `null` |

### نمونه — فاکتور فروش با شرح شامل «تهران»

```bash
curl -s -X POST "<BASE_URL>/api/v1/businesses/{business_id}/invoices/list" \\
  -H "Authorization: ApiKey ak_live_xxxx" \\
  -H "Content-Type: application/json" \\
  -d '{
    "take": 30,
    "skip": 0,
    "document_type": "invoice_sales",
    "from_date": "2024-01-01",
    "to_date": "2024-12-31",
    "filters": [
      {"property": "description", "operator": "*", "value": "تهران"}
    ]
  }'
```

> مسیر دقیق هر ماژول را در operation مربوطه ببینید؛ بعضی endpointها فیلدهای تخت (`from_date`, `person_id`) را علاوه بر `filters` می‌پذیرند.

### نمونه — اشخاص فعال با نام شامل «احمد»

```json
{
  "take": 50,
  "search": "احمد",
  "search_fields": ["alias_name", "first_name", "last_name", "mobile"],
  "filters": [
    {"property": "is_active", "operator": "=", "value": true}
  ]
}
```

### نمونه — کالا با نوع product

```json
{
  "take": 20,
  "filters": [
    {"property": "item_type", "operator": "=", "value": "product"}
  ]
}
```

### نکات برای توسعه‌دهندگان

1. **ستون‌های مجاز** به entity بستگی دارد؛ فیلتر روی ستونی که سرویس نمی‌شناسد نادیده یا خطا می‌دهد.
2. **فیلدهای مجازی UI** (مثل `project_name` روی سند) ممکن است در DB به `project_id` نگاشت شوند — توضیح operation را بخوانید.
3. **پاسخ** معمولاً `{ "items": [...], "pagination": { "total", "take", "skip" } }` یا معادل در `data` است.
4. **AI / اتوماسیون:** در API داخلی AI از `list_queryable_fields` و `query_business_data` با همان ساختار `filters` استفاده کنید.

### اسکیمای Pydantic

مدل‌های `FilterItem` و `QueryInfo` در OpenAPI Components (پایین همین سند) و در کد: `adapters/api/v1/schemas.py`.

"""
