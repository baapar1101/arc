# افزونه حقوق و دستمزد (Payroll) — سند اجرایی تولید

این سند برای پیاده‌سازی **سطح تجاری و تولید (Production)** افزونه حقوق و دستمزد در Hesabix تهیه شده است. معماری با الگوی افزونه‌های موجود (`customer_club`, `repair_shop_management`) و بازار افزونه هم‌خوان است.

---

## ۱. هدف و محدوده

### ۱.۱ هدف

- مدیریت **انعطاف‌پذیر** حقوق و دستمزد به ازای هر کسب‌وکار
- تعریف آیتم‌های حقوق (مزایا، کسورات، هزینه کارفرما) با **نگاشت حساب** از دفتر کل
- ثبت پرسنل، دوره‌های حقوق، اجرای حقوق و در فازهای بعد صدور اسناد حسابداری

### ۱.۲ وضعیت پیاده‌سازی (فاز ۰ — زیرساخت)

| قابلیت | وضعیت |
|--------|--------|
| ثبت افزونه در بازار با کد `payroll` | ✓ |
| مدل داده جامع (۱۱ جدول) | ✓ |
| گیت لایسنس (`payroll_plugin_dependency`) | ✓ |
| API تنظیمات، آیتم‌ها، دسته‌ها، پرسنل، دوره، لیست اجرا | ✓ |
| Seed آیتم‌های پیش‌فرض سیستمی | ✓ |
| مجوزهای `view`, `manage`, `operate`, `post`, `approve` | ✓ |
| منو، تنظیمات، داشبورد Flutter | ✓ |
| ثبت/ویرایش سند حقوق (اجرای حقوق) | ✓ |
| انتخاب حساب از درخت حساب‌ها در UI تنظیمات | ✓ |
| CRUD پرسنل و بخش در UI | ✓ (پرسنل؛ بخش از API) |
| محاسبه خودکار جمع‌ها | ✓ |
| فیش حقوق PDF | ✓ (فاز ۲) |
| import گروهی Excel پرسنل و مقادیر سند | ✓ (فاز ۲) |
| بستن دوره حقوق | ✓ (فاز ۲) |
| کپی سند از دوره/سند قبل | ✓ (فاز ۲) |
| مدیریت بخش در UI | ✓ (فاز ۲) |
| گزارش تفکیکی بخش | ✓ (فاز ۲) |
| صدور سند تعهدی و پرداخت حسابداری | ✓ (فاز ۳) |
| قوانین بیمه/مالیات (`payroll_statutory.py`) | ✓ (فاز ۴) |
| رد تأیید و بازگشت به پیش‌نویس (`reject_run`) | ✓ (فاز ۴) |
| گزارش‌های پیشرفته (آیتم، پرسنل، بیمه/مالیات، نمای دوره) | ✓ (فاز ۴) |
| UI قوانین بیمه/مالیات و گزارش‌ها | ✓ (فاز ۴) |

---

## ۲. معماری فنی

### ۲.۱ کد افزونه

- **کد بازار:** `payroll`
- **دسته:** `hr_payroll`
- فعال‌سازی: `business_plugins` + `marketplace_plugins`
- اسکریپت: `scripts/add_payroll_plugin.py`

### ۲.۲ مجوزهای کسب‌وکار

| اکشن | کاربرد |
|------|--------|
| `view` | مشاهده داشبورد، آیتم‌ها، پرسنل، لیست اسناد |
| `manage` | تنظیمات، آیتم‌ها، دسته‌ها، پرسنل، بخش‌ها |
| `operate` | ایجاد دوره و اجرای حقوق |
| `approve` | تأیید اجرای حقوق (در صورت `require_approval`) |
| `post` | صدور سند حسابداری |

### ۲.۳ مدل داده

| جدول | نقش |
|------|-----|
| `payroll_settings` | تنظیمات کسب‌وکار، حساب‌های پیش‌فرض |
| `payroll_item_categories` | دسته‌بندی آیتم‌ها |
| `payroll_item_definitions` | آیتم‌های حقوق + `account_id` |
| `payroll_departments` | بخش سازمانی |
| `payroll_employees` | پروفایل پرسنلی (`person_id`) |
| `payroll_periods` | دوره ماهانه |
| `payroll_runs` | اجرای حقوق / سند تجمیعی |
| `payroll_run_lines` | ردیف per پرسنل |
| `payroll_run_line_items` | مقدار آیتم per ردیف |
| `payroll_document_links` | پیوند با `documents` |
| `payroll_audit_logs` | حسابرسی تغییرات |

### ۲.۴ انواع آیتم (`item_kind`)

- `earning` — مزایا / درآمد
- `deduction` — کسورات
- `employer_cost` — هزینه سمت کارفرما
- `informational` — بدون اثر حسابداری

### ۲.۵ انواع محاسبه (`calculation_type`)

- `manual` — مقدار دستی در سند
- `fixed` — مقدار پیش‌فرض ثابت
- `percent_of_base` — درصد از حقوق پایه
- `percent_of_gross` — درصد از ناخالص
- `formula` — فرمول (فاز بعد)

---

## ۳. API

پیشوند: `/api/v1/payroll/business/{business_id}/...`

| متد | مسیر | مجوز |
|-----|------|------|
| GET | `/settings` | view |
| PUT | `/settings` | manage |
| GET | `/dashboard` | view |
| GET/POST/PUT/DELETE | `/item-categories` | view / manage |
| GET/POST/PUT/DELETE | `/items` | view / manage |
| GET/POST | `/departments` | view / manage |
| GET/POST | `/employees` | view / manage |
| GET/POST | `/periods` | view / operate |
| POST | `/periods/{period_id}/close` | operate |
| GET | `/runs` | view |
| GET | `/runs/{run_id}` | view |
| POST | `/runs` | operate |
| PUT | `/runs/{run_id}` | operate |
| DELETE | `/runs/{run_id}` | operate |
| POST | `/runs/{run_id}/finalize` | operate |
| POST | `/runs/{run_id}/cancel` | operate |
| POST | `/runs/{run_id}/copy` | operate |
| GET | `/runs/{run_id}/payslip/pdf` | view |
| GET | `/runs/{run_id}/import/template` | operate |
| POST | `/runs/{run_id}/import/excel` | operate |
| GET | `/employees/import/template` | manage |
| GET | `/employees/export/excel` | view |
| POST | `/employees/import/excel` | manage |
| GET | `/reports/department-summary` | view |
| POST | `/runs/{run_id}/approve` | approve |
| POST | `/runs/{run_id}/post` | post |
| POST | `/runs/{run_id}/post-payment` | post |
| PUT | `/employees/{employee_id}` | manage |
| PUT | `/departments/{department_id}` | manage |

---

## ۴. فرانت‌اند

| مسیر | صفحه |
|------|------|
| `/business/:id/payroll` | `PayrollMainPage` |
| `/business/:id/payroll/reports` | `PayrollReportsPage` |
| `/business/:id/settings/payroll` | `PayrollSettingsPage` |

گیت لایسنس: `PayrollPluginGate`

---

## ۵. استقرار

```bash
# مهاجرت
alembic upgrade head

# ثبت افزونه در بازار
python scripts/add_payroll_plugin.py
```

---

## ۶. فازهای بعدی

1. **فاز ۱:** CRUD کامل `payroll_runs` + فرم ثبت سند حقوق — ✓
2. **فاز ۲:** فیش حقوق PDF، import Excel، بستن دوره، کپی سند، بخش‌ها، گزارش تفکیکی — ✓
3. **فاز ۳:** `payroll_accounting.py` — سند تعهدی و پرداخت — ✓
4. **فاز ۴:** قوانین بیمه/مالیات، workflow تأیید، گزارش‌های پیشرفته — ✓
5. **فاز ۵ (آینده):** فرمول سفارشی آیتم‌ها، ادغام حضور و غیاب، گزارش‌های قانونی خروجی
