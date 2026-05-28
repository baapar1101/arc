# سناریوی جست‌وجوی پیشرفته (QueryInfo) برای AI

## مشکل

در API حسابیکس، لیست‌های اصلی (اشخاص، فاکتور، کالا، چک، …) از **`QueryInfo`** پشتیبانی می‌کنند:

| قابلیت | OpenAPI (`schemas.py`) | Backend (`query_service.py` / سرویس‌ها) | AI امروز |
|--------|------------------------|----------------------------------------|----------|
| `search` + `search_fields` | ✅ | ✅ (در بسیاری سرویس‌ها) | 🟡 فقط `search` ساده؛ `search_fields` گاهی پیش‌فرض داخلی |
| `filters[]` با `property`, `operator`, `value` | ✅ | ✅ (ناهمگون بین entityها) | 🔴 تقریباً **استفاده نمی‌شود** |
| عملگرهای `=`, `>`, `<`, `*`, `in`, … | ✅ مستند | ✅ در `QueryBuilder` و سرویس‌های اختصاصی | 🔴 مدل از وجودشان بی‌خبر است |
| `sort` / `sort_by` | ✅ | ✅ | 🟡 محدود |

**علت:** توضیحات toolهای AI (`search_invoices`, `query_business_data`, …) فقط فیلدهای تخت (`from_date`, `person_id`) دارند و **`filters` به‌عنوان آرایهٔ `FilterItem` در schema/tool prompt نیامده**. علاوه بر این، `_build_list_query` در `ai_query_service.py` کلید `filters` را به query سرویس **forward نمی‌کرد** (رفع شد در فاز ۱۰).

---

## مدل دادهٔ استاندارد (مرجع OpenAPI)

```json
{
  "take": 20,
  "skip": 0,
  "search": "علی",
  "search_fields": ["alias_name", "mobile", "code"],
  "sort_by": "created_at",
  "sort_desc": true,
  "filters": [
    {"property": "total_amount", "operator": ">=", "value": 1000000},
    {"property": "document_date", "operator": ">=", "value": "2024-01-01"},
    {"property": "description", "operator": "*", "value": "خرید"}
  ]
}
```

### عملگرها (همان `FilterOperator` / `QueryBuilder`)

| عملگر | معنی |
|--------|------|
| `=` | برابر |
| `!=` | نابرابر |
| `>`, `>=`, `<`, `<=` | مقایسه عددی/تاریخ |
| `*` | شامل (LIKE %value%) |
| `*?` | شروع با |
| `?*` | پایان با |
| `in` | عضو مجموعه (value آرایه) |
| `is_null` / `is_not_null` | خالی / غیرخالی (در برخی سرویس‌ها) |

همهٔ `filters` با **AND** ترکیب می‌شوند.

---

## فازهای اجرایی پیشنهادی

### فاز ۱۰ — زیرساخت AI + query_business_data (اولویت بالا) ✅ شروع شده

| # | تحویل | توضیح |
|---|--------|--------|
| ۱۰.۱ | `ai_query_filter_catalog.py` | برای هر `entity`: ستون‌های قابل فیلتر + عملگرهای مجاز + فیلدهای جستجو |
| ۱۰.۲ | `list_queryable_fields` | tool: «برای invoice چه فیلترهایی دارم؟» |
| ۱۰.۳ | `ai_query_filter_service.normalize_query_filters` | اعتبارسنجی و نرمال‌سازی `filters` قبل از سرویس |
| ۱۰.۴ | اصلاح `_build_list_query` | پاس‌دادن `filters`, `search_fields`, `sort` |
| ۱۰.۵ | `ADVANCED_QUERY_PROMPT_BLOCK` در prompt سیستم | آموزش مدل برای ساخت `filters` |
| ۱۰.۶ | گسترش schemaی `query_business_data.filters` | توضیح ساختار `FilterItem` + مثال |

### فاز ۱۱ — toolهای اختصاصی ✅ (پیاده‌سازی شده)

| entity | tool | کار |
|--------|------|-----|
| invoice/document | `search_invoices` | پارامتر `filters` + `search_fields` |
| person | `search_persons` | مهاجرت به `get_persons_by_business` + QueryInfo کامل |
| product | `search_products` | `filters` برای `item_type`, قیمت، … |
| check, transfer, expense_income | همان الگو | |

**الگوی واحد:** هر tool لیست، پارامترهای مشترک:

```json
{
  "search": "string?",
  "search_fields": ["string"]?,
  "filters": [{"property","operator","value"}]?,
  "take", "skip", "sort_by", "sort_desc"
}
```

### فاز ۱۲ — OpenAPI و UI (هم‌راستاسازی) ✅

| # | کار | وضعیت |
|---|-----|--------|
| ۱۲.۱ | کامپوننت مشترک `QueryInfo` / `DocumentListQuery` در POST list | ✅ |
| ۱۲.۲ | مثال‌های فارسی در Swagger (`json_schema_extra` + Components) | ✅ |
| ۱۲.۳ | `GET /api/v1/query-schema/{entity}` برای کلاینت و AI | ✅ |

### فاز ۱۳ — کاتالوگ پویا (بلندمدت)

- استخراج خودکار فیلدهای مجاز از metadata مدل/SQLAlchemy یا registry UI
- تست قراردادی: «هر فیلد UI در گرید → در catalog AI»

---

## جریان پیشنهادی برای مدل (بعد از فاز ۱۰)

```
کاربر: «فاکتورهای فروش بالای ۵ میلیون از تهران»
    ↓
۱. list_queryable_fields(entity=invoice)  [اختیاری اگر مطمئن نیست]
    ↓
۲. query_business_data(
     entity=invoice,
     filters=[
       {"property":"document_type","operator":"=","value":"invoice_sales"},
       {"property":"total_amount","operator":">=","value":5000000}
     ],
     search="تهران",
     search_fields=["description","extra_info"]
   )
```

یا برای اشخاص:

```
filters=[
  {"property":"person_types","operator":"*","value":"customer"},
  {"property":"balance","operator":">","value":0}
]
```

---

## محدودیت‌ها و نکات

1. **ناهمگونی سرویس‌ها:** همه entityها از `QueryBuilder` یکسان استفاده نمی‌کنند؛ `person_service` منطق اختصاصی دارد؛ `document_repository` فقط برخی `property`ها را در `filters` می‌شناسد. کاتالوگ AI باید **فقط فیلدهای تأییدشده** را نشان دهد.
2. **فیلدهای مجازی:** مثل `project_name` روی سند — در DB `project_id` است؛ catalog باید alias را مستند کند.
3. **امنیت:** اعتبارسنجی `property` در برابر whitelist (جلوگیری از فیلتر روی ستون‌های حساس).
4. **حجم:** سقف تعداد `filters` (مثلاً ۱۰) و `take` (۲۰۰ در AI).

---

## معیار پذیرش

- مدل بتواند با `query_business_data` فاکتوری با `total_amount >= X` پیدا کند (در entityهای پشتیبانی‌شده).
- `list_queryable_fields` برای حداقل ۶ entity پرکاربرد فیلد برگرداند.
- Prompt سیستم به صراحت به `filters` و عملگرها اشاره کند.
- مستندات اجرایی در `AI_EXECUTION_PHASES.md` به‌روز شود.

---

## فایل‌های مرتبط

| موضوع | مسیر |
|--------|------|
| Schema | `adapters/api/v1/schemas.py` → `FilterItem`, `QueryInfo` |
| Query builder | `app/services/query_service.py` |
| AI query | `app/services/ai/ai_query_service.py` |
| کاتالوگ فاز ۱۰ | `app/services/ai/ai_query_filter_catalog.py` |
| نرمال‌ساز | `app/services/ai/ai_query_filter_service.py` |
