# سناریوی کامل رفع مشکلات محاسبه سود فاکتور (فرانت + بک‌اند)

## هدف
- رفع خطای محاسبه سود برای روش‌های `FIFO` و `LIFO`
- جلوگیری از اعمال تنظیمات نامعتبر در API تنظیمات کسب‌وکار
- هم‌راستا کردن رفتار واقعی سیستم با گزینه‌های UI در تنظیمات سود
- ایجاد تست‌های رگرسیون برای جلوگیری از بازگشت خطا

---

## 1) تحلیل ریشه مشکل (Root Cause)

### 1.1 مشکل اصلی FIFO/LIFO در بک‌اند
- در `hesabixAPI/app/services/invoice_service.py`، توابع `_calculate_fifo_cost` و `_calculate_lifo_cost` فقط لایه‌های `in` را می‌دیدند و `out`‌های تاریخی را از لایه‌ها کم نمی‌کردند.
- نتیجه: هزینه‌ی خروج فعلی بر اساس «ورودی‌های تاریخی اولیه» محاسبه می‌شد، نه «موجودی باقی‌مانده واقعی».

### 1.2 نشت فیلتر انبار
- در `_iter_product_movements`، وقتی فیلتر انبار فعال بود اما حرکت `warehouse_id` نداشت، خط وارد محاسبه می‌شد.
- نتیجه: در بعضی سناریوها، هزینه‌ی یک انبار با داده‌های بدون انبار/انبار دیگر آلوده می‌شد.

### 1.3 اعتبارسنجی ناکافی تنظیمات سود
- فیلدهای `invoice_profit_calculation_method/basis/type/overhead_type` در `BusinessUpdateRequest` اعتبارسنجی دقیقی نداشتند.
- امکان ذخیره داده‌های نامعتبر/ناهمگون (از نظر حروف بزرگ-کوچک، مقدار اشتباه و...) وجود داشت.

---

## 2) طرح اصلاح (Solution Design)

### 2.1 اصلاح الگوریتم هزینه‌گذاری FIFO/LIFO
- ایجاد دو helper جدید:
  - `_build_cost_layers_from_movements`
  - `_consume_cost_layers_for_quantity`
- این دو helper:
  - حرکات تاریخی را با ترتیب صحیح زمان/سند پردازش می‌کنند
  - `out`‌های تاریخی را از لایه‌ها مصرف می‌کنند
  - در کمبود لایه، fallback معقول به آخرین هزینه مصرف‌شده دارند

### 2.2 یکپارچه‌سازی normalize برای تنظیمات سود
- افزودن نرمال‌سازهای داخلی در `invoice_service.py`:
  - `_normalize_invoice_profit_method`
  - `_normalize_invoice_profit_basis`
  - `_normalize_invoice_profit_type`
  - `_normalize_invoice_profit_overhead_type`
- استفاده از نرمال‌سازها قبل از محاسبه سود تا رفتار محاسباتی پایدار شود.

### 2.3 سفت‌کردن ورودی API تنظیمات کسب‌وکار
- افزودن validator در `BusinessUpdateRequest` برای چهار فیلد تنظیمات سود:
  - `invoice_profit_calculation_method`
  - `invoice_profit_calculation_basis`
  - `invoice_profit_overhead_type`
  - `invoice_profit_calculation_type`
- خروجی validator‌ها lowercase canonical است.

### 2.4 تست رگرسیون
- افزودن تست جدید:
  - `hesabixAPI/tests/test_invoice_profit_costing.py`
- پوشش تست:
  - مصرف درست لایه‌ها در FIFO
  - مصرف درست لایه‌ها در LIFO
  - fallback هزینه در کمبود لایه
  - نرمال‌سازی مقادیر تنظیمات سود

---

## 3) تغییرات اعمال‌شده

### 3.1 فایل‌های تغییر یافته
- `hesabixAPI/app/services/invoice_service.py`
- `hesabixAPI/adapters/api/v1/schemas.py`
- `hesabixAPI/tests/test_invoice_profit_costing.py` (جدید)

### 3.2 جزئیات فنی تغییرات
- جایگزینی منطق قدیمی `_calculate_fifo_cost` / `_calculate_lifo_cost` با لایه‌سازی واقعی مبتنی بر in/out.
- اصلاح فیلتر انبار در `_iter_product_movements` برای جلوگیری از نشت داده.
- استفاده از normalize داخلی در `_calculate_invoice_profit`.
- اضافه‌کردن validators سطح schema برای جلوگیری از ورود مقادیر نامعتبر.

---

## 4) اثر روی فرانت‌اند

- ساختار فرانت (`business_info_settings_page.dart`) برای ارسال مقادیر `fifo/lifo/...` صحیح است.
- تغییر بک‌اند باعث می‌شود همان payload فعلی فرانت، خروجی محاسباتی صحیح‌تری بدهد.
- نیازی به تغییر اجباری UI برای این فاز نبود.

---

## 5) ریسک‌ها و کنترل ریسک

- **ریسک:** تغییر منطق هزینه‌گذاری ممکن است در داده‌های قبلی اختلاف عددی با قبل ایجاد کند (اختلاف مثبت از جنس «اصلاح خطا»).
  - **کنترل:** تست رگرسیون + اجرای recalculation سود از endpoint موجود.

- **ریسک:** رد شدن درخواست‌هایی که قبلا مقدار نامعتبر می‌پذیرفتند.
  - **کنترل:** پیام خطای validator شفاف است و مقادیر مجاز مشخص هستند.

---

## 6) برنامه اعتبارسنجی بعد از استقرار

1. روی یک کسب‌وکار تست:
   - مبنا = `fifo`
   - محاسبه سود چند فاکتور فروش با تاریخ‌های مختلف
2. اجرای endpoint:
   - `POST /api/v1/invoices/business/{business_id}/recalculate-all-profits`
3. مقایسه:
   - سود فاکتورهای نمونه قبل/بعد
4. کنترل چندانباره:
   - تکرار سناریو با `warehouse_id` متفاوت

---

## 7) خروجی مورد انتظار

- FIFO/LIFO از حالت تقریبی/اشتباه به محاسبه مبتنی بر لایه‌های واقعی موجودی تبدیل می‌شود.
- تنظیمات سود نامعتبر دیگر وارد سیستم نمی‌شود.
- رفتار محاسبه سود در API پایدارتر و قابل پیش‌بینی‌تر می‌شود.

