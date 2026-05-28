# سناریوی غنی‌سازی AI — فاز ۶ و بعد (پوشش گزارشات، قالب اسناد، افزونه‌ها)

**تاریخ:** ۱۴۰۵/۰۳/۰۷ (به‌روز: فاز ۶–۸ پیاده‌سازی شد)  
**وضعیت فعلی ابزارها:** ~۱۱۲ function (فاز ۰–۸)  
**هدف این سند:** پاسخ صریح به «آیا AI به گزارشات / قالب اسناد / باشگاه مشتریان / باسلام / بازار افزونه دسترسی دارد؟»  
**اجرای فازها:** [`AI_EXECUTION_PHASES.md`](AI_EXECUTION_PHASES.md)

---

## ۱. جمع‌بندی سریع (برای مدیر محصول)

| حوزه UI | دسترسی AI امروز | سطح |
|---------|------------------|-----|
| **بخش گزارشات** | **گسترده** — `list_available_reports` + `get_report` با ~۳۵ نوع | 🟢 ~۷۵٪ |
| **قالب‌های گزارش / چاپ** | **MVP** — list/get/scope + set_default/publish با تأیید | 🟡 ~۵۰٪ |
| **باشگاه مشتریان** | read قبلی + **write** تنظیمات/امتیاز/RFM با تأیید | 🟡 ~۷۰٪ |
| **باسلام** | overview + dead-letter + لیست‌های قبلی | 🟡 ~۳۵٪ (بدون sync) |
| **ووکامرس** | **فقط لیست** سفارش و محصول | 🟡 ~۱۰٪ |
| **بازار افزونه‌ها** | list کاتالوگ + افزونه‌های کسب‌وکار | 🟡 ~۴۰٪ (بدون خرید) |
| **قالب اعلان** (`notification-templates`) | **خیر** | 🔴 ۰٪ |

**نتیجه:** AI برای عملیات روزمرهٔ حسابداری/فاکتور/اشخاص نسبتاً قوی است؛ برای **گزارشات پیشرفته، طراحی قالب، مدیریت افزونه و عملیات یکپارچه‌سازی** هنوز به UI نزدیک نیست. سناریوی قبلی (فاز ۰–۵) درست بوده اما **دامنهٔ «گزارشات و اکوسیستم افزونه»** را پوشش نداده است.

---

## ۲. وضعیت فعلی — آنچه AI دارد

### ۲.۱ گزارشات و تحلیل
**ابزارهای اختصاصی:**
- `get_debtors_report`, `get_creditors_report`, `get_sales_report`, `get_purchase_report`, `get_inventory_valuation`, `get_cash_flow`
- `get_financial_summary`, `get_business_dashboard`, `get_product_kardex`
- `get_report` با `report_type`: `sales_by_product`, `item_movements`, `debtors`, `creditors`, `cash_flow`, `inventory_valuation`, `sales`, `purchase`
- `export_business_data` — persons, invoices, products, expense_income, documents (Excel/PDF)
- CRM: `get_pipeline_report`, `get_lead_funnel_report`, `get_crm_summary`

**صفحات گزارش UI بدون پوشش مستقیم AI** (نمونه):
- حسابداری: `trial_balance`, `general_ledger`, `journal_ledger`, `pnl_period`, `pnl_cumulative`, `accounts_review`
- فروش/خرید: `daily_sales`, `daily_purchases`, `monthly_sales`, `top_customers`, `top_suppliers`, `materials_consumption`, `production`
- انبار: `inventory_kardex`, `inventory_stock`, `stock_count`, `warehouse_documents_summary`, `slow_moving_items`, `critical_stock`, `inter_warehouse_transfers`, `adjustment_documents`, `warehouse_performance`, `product_movement_history`, `inventory_turnover`, `pending_documents`
- مالی: `bank_accounts_turnover`, `cash_petty_turnover`, `people_transactions` (گزارش اختصاصی)
- توزیع: `distribution_dashboard`
- یکپارچه: گزارش‌های `basalam/dead-letter`, `woocommerce/overview`, `woocommerce/bridge-health`

سرویس‌های backend برای بسیاری از این گزارش‌ها **وجود دارد** (`trial_balance_service`, `pnl_service`, `warehouse_reports_service`, …) اما به AI وصل نشده‌اند.

### ۲.۲ قالب اسناد (Report Templates)
API کامل در `adapters/api/v1/report_templates.py`:
- scope catalog، list، get، create، update، delete، publish، preview، duplicate، …
- scopeها: فاکتور، دریافت/پرداخت، هزینه/درآمد، اسناد، انتقال، برچسب پستی انبار (`report_template_scope_registry.py`)

**AI:** هیچ tool — مدل نمی‌تواند قالب بسازد، منتشر کند، یا پیش‌نمایش PDF بگیرد.

### ۲.۳ باشگاه مشتریان
**AI (read):**
- `get_customer_club_settings`, `list_customer_club_tiers`, `list_customer_club_ledger`
- `get_customer_club_rfm_summary`, `search_customer_club_rfm_persons`
- entity در query: `customer_club_ledger`

**API ولی بدون AI:**
- `PUT settings`, `PUT tiers`, `POST adjustments` (تنظیم دستی امتیاز), `POST analytics/rfm/recalculate`, `GET persons/{id}/balance`

**بازار افزونه:** باشگاه مشتریان معمولاً به‌صورت **افزونهٔ marketplace** فعال می‌شود؛ AI وضعیت فعال بودن افزونه را نمی‌بیند (`list_business_plugins` وجود ندارد).

### ۲.۴ باسلام
**AI (read):**
- `list_basalam_synced_invoices`, `list_basalam_product_conflicts`

**API ولی بدون AI:**
- `reports/overview`, `reports/dead-letter`, `settings` GET/PUT
- sync: orders, products, publish, pull, push, conflict resolve/clear, payments, chats, webhook

### ۲.۵ ووکامرس
**AI:** `list_woocommerce_orders`, `list_woocommerce_products`  
**بدون AI:** overview، bridge health، تنظیمات، sync، opening inventory

### ۲.۶ بازار افزونه‌ها (Plugin Marketplace)
**API:** `list_plugins`, `purchase_plugin`, `list_business_plugins`, `start_trial`, orders, invoices  
**AI:** هیچ — کاربر نمی‌تواند از چت بپرسد «آیا باشگاه مشتریان فعال است؟» یا «افزونه X را trial کن».

---

## ۳. محدودیت‌های معماری (چرا «دسترسی» ≠ «مثل UI»)

1. **Intent + سقف ۴۸ tool** در هر درخواست — ابزارهای حوزه‌های کم‌استفاده ممکن است اصلاً به مدل نرسند.
2. **Permission map** — بدون alias درست، کاربر «دسترسی ندارم» می‌بیند در حالی که در UI دسترسی دارد (`report_templates`, `marketplace`, `customer_club.edit`).
3. **فقط read برای اکوسیستم افزونه** — حتی با permission، writeهای marketplace/باسلام نیاز به تأیید و audit دارند.
4. **قالب اسناد** — خروجی visual/PDF builder؛ برای AI بهتر است ابزارهای «ساختاریافته» (JSON blocks) + preview جدا باشد، نه drag-and-drop خام.

---

## ۴. سناریوی پیشنهادی — فاز ۶ تا ۸

### فاز ۶ — یکپارچه‌سازی گزارشات (اولویت بالا)
**هدف:** پوشش ~۸۰٪ سوالات «گزارش بده» بدون افزودن ۳۰ tool جدا.

| کار | ابزار پیشنهادی | توضیح |
|-----|----------------|--------|
| ۶.۱ | گسترش `get_report` | اضافه کردن `report_type`: `trial_balance`, `general_ledger`, `journal_ledger`, `pnl_period`, `pnl_cumulative`, `accounts_review`, `daily_sales`, `monthly_sales`, `top_customers`, `top_suppliers`, `people_transactions`, `inventory_stock`, `warehouse_documents_summary`, `slow_moving`, `critical_stock`, `distribution_dashboard`, … |
| ۶.۲ | `list_available_reports` | برگرداندن کاتالوگ گزارش‌های مجاز برای کاربر (با permission) — کمک به مدل برای انتخاب درست |
| ۶.۳ | alias permission | `reports.read` → تمام sectionهای گزارش UI |
| ۶.۴ | intent | کلیدواژه «تراز آزمایشی»، «دفتر کل»، «گردش بانک»، … → category `reports` |

**تخمین:** +۲ tool، ~۲۰ handler داخلی در `get_report`.

### فاز ۷ — قالب اسناد و چاپ
**هدف:** پاسخ به «قالب فاکتور بساز / پیش‌فرض کن / پیش‌نمایش بده».

| کار | ابزار | write؟ |
|-----|-------|--------|
| ۷.۱ | `list_report_templates` | خیر |
| ۷.۲ | `get_report_template` | خیر |
| ۷.۳ | `get_report_template_scope_catalog` | خیر |
| ۷.۴ | `create_report_template` / `update_report_template` | بله + تأیید |
| ۷.۵ | `publish_report_template` / `set_default_report_template` | بله + تأیید |
| ۷.۶ | `preview_report_template` | خیر — برگرداندن PDF base64 یا link |

**Permission:** `report_templates.view` / `report_templates.write` در `ai_permission_map`.

### فاز ۸ — افزونه‌ها، باشگاه، باسلام/ووکامرس
**هدف:** هم‌تراز با «افزونه‌های باشگاه / باسلام / …».

| کار | ابزار | یادداشت |
|-----|-------|---------|
| ۸.۱ | `list_marketplace_plugins`, `list_business_plugins`, `get_business_plugin_status` | read |
| ۸.۲ | `purchase_marketplace_plugin`, `start_plugin_trial` | write + تأیید + کیف‌پول |
| ۸.۳ باشگاه | `update_customer_club_settings`, `adjust_customer_club_points`, `update_customer_club_tiers`, `recalculate_customer_club_rfm` | write + تأیید |
| ۸.۴ باسلام | `get_basalam_overview`, `list_basalam_dead_letter`, `get_basalam_settings`, `trigger_basalam_sync` (با enum operation), `resolve_basalam_product_conflict` | sync = write |
| ۸.۵ ووکامرس | `get_woocommerce_overview`, `get_woocommerce_bridge_health` | read |
| ۸.۶ | `list_notification_templates` (اختیاری) | read |

---

## ۵. معیار پذیرش (Acceptance)

- کاربر با permission گزارشات بتواند از چت حداقل **۱۵ نوع گزارش** متداول را بگیرد (خروجی جدول/chart طبق فاز visualization).
- کاربر با `report_templates.write` بتواند **لیست قالب‌ها** را ببیند و با تأیید **قالب پیش‌فرض فاکتور** را عوض کند (حداقل MVP).
- کاربر بتواند بپرسد «آیا افزونه باشگاه مشتریان فعال است؟» و پاسخ بر اساس `list_business_plugins` باشد.
- کاربر با `basalam.view` بتواند **خلاصه وضعیت همگام‌سازی** ببیند؛ عملیات sync فقط با تأیید صریح.
- هیچ tool جدید بدون entry در `ai_permission_map`, `ai_tool_intent`, `ai_tool_keys`, `ai_chat_l10n` merge نشود.

---

## ۶. اولویت‌بندی پیشنهادی

```
فاز ۶ (گزارشات)     ████████████  اول — بیشترین سوال کاربر
فاز ۷ (قالب اسناد)  ████████░░░░  دوم — تمایز محصول / چاپ
فاز ۸ (افزونه/…)    ██████░░░░░░  سوم — وابسته به marketplace + write حساس
```

---

## ۷. آنچه عمداً خارج از scope فاز ۶–۸

- ویرایش visual کامل builder قالب (بلوک‌به‌بلوک) از داخل چت — فقط MVP JSON + preview
- جایگزینی کامل ۳۵ صفحه گزارش UI با tool جداگانه
- webhook و مدیریت infra باسلام
- خرید افزونه بدون کنترل موجودی کیف‌پول در UI تأیید

---

## ۸. ارجاع فایل‌ها

| موضوع | مسیر |
|--------|------|
| ثبت tools | `hesabixAPI/app/services/ai/function_registry.py`, `ai_function_extensions_phase*.py` |
| گزارش یکپارچه | `ai_function_extensions_phase4.py` → `get_report` |
| باشگاه | `ai_function_extensions_phase3.py`, `adapters/api/v1/customer_club.py` |
| باسلام | `adapters/api/v1/basalam_integration.py` |
| قالب گزارش | `adapters/api/v1/report_templates.py`, `report_template_service.py` |
| marketplace | `adapters/api/v1/marketplace.py` |
| مسیرهای UI | `hesabixUI/.../business_named_route_locations.dart` |
| فازهای قبلی | `docs/AI_FUNCTION_ENRICHMENT_PHASES.md` |
