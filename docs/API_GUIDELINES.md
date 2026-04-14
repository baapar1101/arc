# 📚 راهنمای جامع استفاده از Hesabix API

## فهرست مطالب
1. [شروع سریع](#شروع-سریع)
2. [احراز هویت](#احراز-هویت)
3. [صفحه‌بندی](#صفحه‌بندی)
4. [فیلتر و جستجو](#فیلتر-و-جستجو)
5. [مرتب‌سازی](#مرتب‌سازی)
6. [مدیریت خطاها](#مدیریت-خطاها)
7. [Rate Limiting](#rate-limiting)
8. [چندزبانه](#چندزبانه)
9. [تقویم](#تقویم)
10. [Versioning](#versioning)
11. [Best Practices](#best-practices)

---

## 🚀 شروع سریع

### دسترسی به مستندات
- **Swagger UI**: https://agent.hesabix.ir/docs
- **ReDoc**: https://agent.hesabix.ir/redoc
- **OpenAPI Schema**: https://agent.hesabix.ir/openapi.json

### اولین درخواست
```bash
# 1. بررسی وضعیت API
curl https://agent.hesabix.ir/api/v1/health

# 2. دریافت کپچا
curl -X POST https://agent.hesabix.ir/api/v1/auth/captcha

# 3. ثبت‌نام
curl -X POST https://agent.hesabix.ir/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -H "Accept-Language: fa" \
  -d '{
    "first_name": "احمد",
    "last_name": "احمدی",
    "email": "ahmad@example.com",
    "password": "SecurePassword123!",
    "captcha_id": "...",
    "captcha_code": "12345"
  }'
```

---

## 🔐 احراز هویت

### نوع احراز هویت
Hesabix API از **API Key Authentication** استفاده می‌کند.

### فرمت Header
```http
Authorization: Bearer sk_your_api_key_here
```

### انواع کلید API

#### 1. Session Keys (موقت)
- با ورود/ثبت‌نام ایجاد می‌شوند
- مدت اعتبار: 30 روز
- فرمت: `sk_session_...`
- استفاده: برای web apps و موبایل apps

#### 2. Personal Keys (دائمی)
- توسط کاربر ایجاد می‌شوند
- بدون تاریخ انقضا
- فرمت: `sk_personal_...`
- استفاده: برای یکپارچه‌سازی‌ها و automation

### نحوه دریافت کلید

**روش 1: ثبت‌نام**
```bash
POST /api/v1/auth/register
```

**روش 2: ورود**
```bash
POST /api/v1/auth/login
```

**روش 3: ایجاد کلید شخصی**
```bash
POST /api/v1/auth/api-keys
Authorization: Bearer sk_session_...

{
  "name": "Integration Key",
  "scopes": "read,write",
  "expires_at": null
}
```

### مثال کامل
```bash
# ورود و دریافت کلید
curl -X POST https://agent.hesabix.ir/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "identifier": "ahmad@example.com",
    "password": "SecurePassword123!",
    "captcha_id": "...",
    "captcha_code": "12345"
  }'

# استفاده از کلید
curl https://agent.hesabix.ir/api/v1/auth/me \
  -H "Authorization: Bearer sk_session_abc123..."
```

---

## 📄 صفحه‌بندی

### روش استاندارد: Skip & Take

تمام endpoint های لیست از `skip` و `take` استفاده می‌کنند:

```json
{
  "skip": 0,
  "take": 20
}
```

**پارامترها:**
- `skip`: تعداد رکوردی که از ابتدا رد می‌شود (پیش‌فرض: 0)
- `take`: تعداد رکورد در هر صفحه (پیش‌فرض: 10، حداکثر: 1000)

### مثال
```bash
# صفحه اول (رکورد 1-20)
curl -X POST https://agent.hesabix.ir/api/v1/businesses/1/transfers \
  -H "Authorization: Bearer sk_..." \
  -H "Content-Type: application/json" \
  -d '{
    "skip": 0,
    "take": 20
  }'

# صفحه دوم (رکورد 21-40)
curl -X POST https://agent.hesabix.ir/api/v1/businesses/1/transfers \
  -H "Authorization: Bearer sk_..." \
  -H "Content-Type: application/json" \
  -d '{
    "skip": 20,
    "take": 20
  }'
```

### پاسخ
```json
{
  "success": true,
  "data": {
    "items": [...],
    "total_count": 156,
    "has_more": true
  }
}
```

---

## 🔍 فیلتر و جستجو

### جستجوی ساده
```json
{
  "search": "احمد",
  "search_fields": ["name", "email", "mobile"]
}
```

### فیلترهای پیشرفته

استفاده از آرایه `filters`:

```json
{
  "filters": [
    {
      "property": "total_amount",
      "operator": ">=",
      "value": 1000000
    },
    {
      "property": "status",
      "operator": "in",
      "value": ["active", "pending"]
    },
    {
      "property": "name",
      "operator": "*",
      "value": "احمد"
    }
  ]
}
```

### عملگرهای موجود

| عملگر | نام | توضیح | مثال |
|-------|-----|-------|------|
| `=` | برابر | برابری دقیق | `{"property": "status", "operator": "=", "value": "active"}` |
| `!=` | نابرابر | عدم برابری | `{"property": "is_deleted", "operator": "!=", "value": true}` |
| `>` | بزرگتر | بزرگتر از | `{"property": "age", "operator": ">", "value": 18}` |
| `>=` | بزرگتر مساوی | بزرگتر یا مساوی | `{"property": "amount", "operator": ">=", "value": 1000}` |
| `<` | کوچکتر | کوچکتر از | `{"property": "quantity", "operator": "<", "value": 10}` |
| `<=` | کوچکتر مساوی | کوچکتر یا مساوی | `{"property": "price", "operator": "<=", "value": 5000}` |
| `*` | شامل | شامل (در هر جای متن) | `{"property": "description", "operator": "*", "value": "خرید"}` |
| `*?` | شروع با | شروع می‌شود با | `{"property": "code", "operator": "*?", "value": "P"}` |
| `?*` | پایان با | پایان می‌یابد با | `{"property": "email", "operator": "?*", "value": "@gmail.com"}` |
| `in` | موجود در | موجود در لیست | `{"property": "type", "operator": "in", "value": ["sale", "purchase"]}` |
| `not_in` | موجود نیست | موجود نیست در لیست | `{"property": "status", "operator": "not_in", "value": ["deleted", "cancelled"]}` |
| `is_null` | خالی است | مقدار null دارد | `{"property": "deleted_at", "operator": "is_null", "value": null}` |
| `is_not_null` | خالی نیست | مقدار null ندارد | `{"property": "confirmed_at", "operator": "is_not_null", "value": null}` |

### مثال کامل
```bash
curl -X POST https://agent.hesabix.ir/api/v1/businesses/1/transfers \
  -H "Authorization: Bearer sk_..." \
  -H "Content-Type: application/json" \
  -d '{
    "take": 50,
    "skip": 0,
    "search": "بانک",
    "filters": [
      {
        "property": "total_amount",
        "operator": ">=",
        "value": 1000000
      },
      {
        "property": "document_date",
        "operator": ">=",
        "value": "2024-01-01"
      }
    ]
  }'
```

---

## 📊 مرتب‌سازی

### پارامترها
```json
{
  "sort_by": "created_at",
  "sort_desc": true
}
```

**پارامترها:**
- `sort_by`: نام فیلد مورد نظر
- `sort_desc`: `true` = نزولی (Z-A, 9-1), `false` = صعودی (A-Z, 1-9)

### فیلدهای معمول برای مرتب‌سازی
- `created_at` - تاریخ ایجاد
- `updated_at` - تاریخ ویرایش
- `name` - نام
- `code` - کد
- `total_amount` - مبلغ
- `document_date` - تاریخ سند

### مثال
```json
{
  "sort_by": "total_amount",
  "sort_desc": true,
  "take": 20,
  "skip": 0
}
```

---

## ⚠️ مدیریت خطاها

### فرمت پاسخ خطا
```json
{
  "success": false,
  "error_code": "VALIDATION_ERROR",
  "message": "داده‌های ورودی نامعتبر است",
  "details": [
    {
      "field": "email",
      "message": "فرمت ایمیل نامعتبر است",
      "code": "INVALID_EMAIL_FORMAT"
    }
  ],
  "timestamp": "2024-01-15T10:30:00Z",
  "path": "/api/v1/users"
}
```

### کدهای خطای رایج

| کد HTTP | کد خطا | توضیح |
|---------|--------|-------|
| 400 | `VALIDATION_ERROR` | خطا در اعتبارسنجی داده‌ها |
| 400 | `INVALID_INPUT` | ورودی نامعتبر |
| 401 | `UNAUTHORIZED` | احراز هویت نشده |
| 401 | `INVALID_API_KEY` | کلید API نامعتبر |
| 403 | `FORBIDDEN` | عدم دسترسی |
| 403 | `INSUFFICIENT_PERMISSIONS` | مجوزهای کافی نیست |
| 404 | `NOT_FOUND` | منبع یافت نشد |
| 409 | `DUPLICATE_ENTRY` | رکورد تکراری |
| 429 | `RATE_LIMIT_EXCEEDED` | تعداد درخواست بیش از حد |
| 500 | `INTERNAL_SERVER_ERROR` | خطای سرور |
| 503 | `SERVICE_UNAVAILABLE` | سرویس در دسترس نیست |

### مثال مدیریت خطا (JavaScript)
```javascript
try {
  const response = await fetch('https://agent.hesabix.ir/api/v1/transfers/123', {
    headers: {
      'Authorization': 'Bearer sk_...',
    }
  });
  
  const data = await response.json();
  
  if (!data.success) {
    switch(data.error_code) {
      case 'UNAUTHORIZED':
        // هدایت به صفحه ورود
        window.location.href = '/login';
        break;
      case 'NOT_FOUND':
        // نمایش پیام منبع یافت نشد
        showError('سند مورد نظر یافت نشد');
        break;
      case 'VALIDATION_ERROR':
        // نمایش خطاهای فیلدها
        data.details.forEach(err => {
          showFieldError(err.field, err.message);
        });
        break;
      default:
        // خطای عمومی
        showError(data.message);
    }
  }
} catch (error) {
  // خطای شبکه
  showError('خطا در برقراری ارتباط با سرور');
}
```

---

## 🚦 Rate Limiting

### محدودیت‌های فعلی

| Endpoint Type | محدودیت | بازه زمانی |
|---------------|---------|-----------|
| عمومی | 100 درخواست | 1 دقیقه |
| احراز هویت | 5 درخواست | 1 ساعت |
| ثبت‌نام | 5 درخواست | 1 ساعت |
| کپچا | 20 درخواست | 1 دقیقه |

### Headers پاسخ
```http
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 95
X-RateLimit-Reset: 1705315800
```

### پاسخ محدودیت
```json
{
  "success": false,
  "error_code": "RATE_LIMIT_EXCEEDED",
  "message": "تعداد درخواست‌های شما بیش از حد مجاز است",
  "retry_after": 60
}
```

### بهترین روش‌ها
1. ✅ ذخیره‌سازی پاسخ‌ها (Caching)
2. ✅ استفاده از Batch Operations
3. ✅ بررسی headers قبل از درخواست بعدی
4. ✅ Exponential Backoff برای retry

---

## 🌍 چندزبانه (i18n)

### Header زبان
```http
Accept-Language: fa
```

### زبان‌های پشتیبانی شده
- `fa` - فارسی (پیش‌فرض)
- `en` - انگلیسی
- `fa-IR` - فارسی ایران
- `en-US` - انگلیسی آمریکا

### مثال
```bash
# فارسی
curl https://agent.hesabix.ir/api/v1/auth/me \
  -H "Authorization: Bearer sk_..." \
  -H "Accept-Language: fa"

# انگلیسی
curl https://agent.hesabix.ir/api/v1/auth/me \
  -H "Authorization: Bearer sk_..." \
  -H "Accept-Language: en"
```

---

## 📅 تقویم

### Header تقویم
```http
X-Calendar-Type: jalali
```

### انواع تقویم
- `jalali` - تقویم شمسی (پیش‌فرض)
- `gregorian` - تقویم میلادی

### نکته
- تاریخ‌ها در پاسخ بر اساس تقویم انتخابی فرمت می‌شوند
- تاریخ‌ها در request می‌توانند ISO (YYYY-MM-DD) یا جلالی (YYYY/MM/DD) باشند

### مثال
```bash
curl https://agent.hesabix.ir/api/v1/businesses/1/transfers \
  -H "Authorization: Bearer sk_..." \
  -H "X-Calendar-Type: jalali"
```

پاسخ:
```json
{
  "document_date": "1403/10/15",
  "created_at": "1403/10/15 14:30:00"
}
```

---

## 🔄 Versioning

### نسخه فعلی: v1
```
https://agent.hesabix.ir/api/v1/
```

### استراتژی Versioning
- نسخه در URL قرار دارد
- نسخه‌های قدیمی حداقل 12 ماه پشتیبانی می‌شوند
- تغییرات Breaking در نسخه جدید اعمال می‌شوند
- تغییرات Non-breaking در همان نسخه اضافه می‌شوند

### تغییرات Non-breaking
- افزودن endpoint جدید
- افزودن فیلد اختیاری
- افزودن enum value جدید

### تغییرات Breaking
- حذف endpoint
- حذف فیلد
- تغییر نوع فیلد
- تغییر رفتار موجود

---

## ✨ Best Practices

### 1. امنیت

```javascript
// ❌ بد
const API_KEY = 'sk_...'; // hardcoded

// ✅ خوب
const API_KEY = process.env.HESABIX_API_KEY;
```

### 2. Error Handling

```javascript
// ❌ بد
const data = await api.get('/users');
console.log(data.items);

// ✅ خوب
try {
  const response = await api.get('/users');
  if (response.success) {
    console.log(response.data.items);
  } else {
    handleError(response.error_code, response.message);
  }
} catch (error) {
  handleNetworkError(error);
}
```

### 3. Pagination

```javascript
// ❌ بد - دریافت همه رکوردها یکجا
const all = await api.get('/transfers?take=10000');

// ✅ خوب - pagination
let skip = 0;
const take = 100;
while (true) {
  const response = await api.post('/transfers', { skip, take });
  processItems(response.data.items);
  if (!response.data.has_more) break;
  skip += take;
}
```

### 4. Rate Limiting

```javascript
// ✅ خوب - بررسی rate limit
async function apiCall(url, options) {
  const response = await fetch(url, options);
  
  if (response.status === 429) {
    const retryAfter = response.headers.get('Retry-After');
    await sleep(retryAfter * 1000);
    return apiCall(url, options); // retry
  }
  
  return response.json();
}
```

### 5. Caching

```javascript
// ✅ خوب - کش کردن داده‌های ثابت
const cache = new Map();

async function getCategories() {
  if (cache.has('categories')) {
    return cache.get('categories');
  }
  
  const data = await api.get('/categories');
  cache.set('categories', data, { ttl: 3600 }); // 1 hour
  return data;
}
```

### 6. Batch Operations

```javascript
// ❌ بد - تک تک
for (const id of productIds) {
  await api.delete(`/products/${id}`);
}

// ✅ خوب - گروهی
await api.post('/products/bulk-delete', {
  ids: productIds
});
```

---

## 📞 پشتیبانی

- **ایمیل**: support@hesabix.ir
- **مستندات**: https://docs.hesabix.ir
- **وضعیت سرویس**: https://status.hesabix.ir
- **تلگرام**: @hesabix_support

---

## 📝 تغییرات و به‌روزرسانی‌ها

برای مطلع شدن از آخرین تغییرات:
- CHANGELOG: https://docs.hesabix.ir/changelog
- خبرنامه توسعه‌دهندگان: https://hesabix.ir/newsletter
- کانال تلگرام: @hesabix_developers

---

**نسخه مستندات:** 1.0.0  
**آخرین به‌روزرسانی:** 2024-12-04


