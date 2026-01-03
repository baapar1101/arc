# Migration های دارای داده‌های پایه (Seed Data)

این فایل لیست migration هایی را که داده‌های پایه نرم‌افزار را به جداول اضافه می‌کنند، نشان می‌دهد.

## 1. `20250101_000000_init_schema.py` ⭐ (اصلی)

این migration شامل بیشترین داده‌های پایه است:

### داده‌های پشتیبانی:
- **support_categories**: دسته‌بندی‌های تیکت (5 مورد)
  - مشکل فنی
  - درخواست ویژگی
  - سوال
  - شکایت
  - سایر

- **support_priorities**: اولویت‌های تیکت (4 مورد)
  - کم
  - متوسط
  - بالا
  - فوری

- **support_statuses**: وضعیت‌های تیکت (5 مورد)
  - باز
  - در حال پیگیری
  - در انتظار کاربر
  - بسته
  - حل شده

### ارزها (Currencies):
- لیست کامل 80+ ارز جهان شامل:
  - ریال ایران (IRR)
  - دلار آمریکا (USD)
  - یورو (EUR)
  - پوند انگلیس (GBP)
  - و سایر ارزهای مهم جهان

### انواع مالیات (Tax Types):
- 12 نوع مالیات استاندارد سازمان امور مالیاتی ایران:
  1. دارو
  2. دخانیات
  3. موبایل
  4. لوازم خانگی برقی
  5. قطعات مصرفی و یدکی وسایل نقلیه
  6. فراورده‌ها و مشتقات نفتی و گازی و پتروشیمیایی
  7. طلا اعم از شمش، مسکوکات و مصنوعات زینتی
  8. منسوجات و پوشاک
  9. اسباب بازی
  10. دام زنده، گوشت سفید و قرمز
  11. محصولات اساسی کشاورزی
  12. سایر کالاها

### تنظیمات سیستم (System Settings):
- `wallet_base_currency_code`: ارز پایه کیف پول (IRR)

### چارت حساب‌ها (Accounts Chart):
- چارت کامل حساب‌های حسابداری استاندارد ایران شامل:
  - دارایی‌ها (کد 1)
  - بدهی‌ها (کد 2)
  - حقوق صاحبان سهام (کد 3)
  - بهای تمام شده کالای فروخته شده (کد 4)
  - فروش (کد 5)
  - درآمد (کد 6)
  - هزینه‌ها (کد 7)
  - سایر حساب‌ها (کد 8)

---

## 2. `20250205_000002_seed_repair_shop_plugin.py`

### افزونه‌های Marketplace:
- **marketplace_plugins**: افزونه "مدیریت تعمیرگاه"
  - کد: `repair_shop_management`
  - دسته: `operations`
  - توضیحات کامل قابلیت‌ها

- **marketplace_plugin_plans**: پلن‌های افزونه
  - پلن ماهانه: 500,000 تومان
  - پلن سالانه: 5,000,000 تومان

---

## 3. `20250118_000001_add_product_warranty_plugin.py`

### افزونه‌های Marketplace:
- **marketplace_plugins**: افزونه "گارانتی کالا"
  - کد: `product_warranty`
  - دسته: `product_management`

- **marketplace_plugin_plans**: پلن‌های افزونه
  - پلن ماهانه: 100,000 تومان
  - پلن سالانه: 1,000,000 تومان

---

## 4. `20250121_000001_add_ai_expense_account.py`

### حساب‌های حسابداری:
- **accounts**: حساب هزینه هوش مصنوعی
  - کد: `70508`
  - نام: "هزینه هوش مصنوعی"
  - نوع: `accounting_document`
  - والد: حساب `705` (هزینه‌های عمومی)

---

## 5. `20250115_000001_fix_zohal_account_code.py`

### حساب‌های حسابداری:
- **accounts**: حساب هزینه سرویس‌های استعلامات
  - کد: `70509`
  - نام: "هزینه سرویس‌های استعلامات"
  - نوع: `accounting_document`
  - والد: حساب `705` (هزینه‌های عمومی)

- **accounts**: اصلاح حساب جرائم دیرکرد بانکی
  - کد: `70903`
  - نام: "جرائم دیرکرد بانکی"

---

## 6. `20251202_000002_create_document_monetization_expense_account.py`

### حساب‌های حسابداری:
- **accounts**: حساب هزینه اشتراک و خدمات سیستم
  - کد: `70507`
  - نام: "هزینه اشتراک و خدمات سیستم"
  - نوع: `accounting_document`
  - والد: حساب `705` (هزینه‌های عمومی)

---

## 7. `20251202_000003_backfill_document_monetization_accounting_documents.py`

### Backfill داده‌ها (نه seed خالص):
این migration داده‌های قدیمی را backfill می‌کند:
- **documents**: ایجاد اسناد حسابداری برای تراکنش‌های قدیمی Document Monetization
- **document_lines**: ایجاد ردیف‌های حسابداری (با amount=0)
- **document_usage_charges**: به‌روزرسانی document_id
- **wallet_transactions**: به‌روزرسانی document_id

⚠️ **نکته**: این migration برای داده‌های موجود است، نه seed خالص.

---

## خلاصه

| Migration | نوع داده | جداول |
|-----------|----------|--------|
| `20250101_000000_init_schema.py` | Seed اصلی | support_categories, support_priorities, support_statuses, currencies, tax_types, system_settings, accounts |
| `20250205_000002_seed_repair_shop_plugin.py` | Seed افزونه | marketplace_plugins, marketplace_plugin_plans |
| `20250118_000001_add_product_warranty_plugin.py` | Seed افزونه | marketplace_plugins, marketplace_plugin_plans |
| `20250121_000001_add_ai_expense_account.py` | Seed حساب | accounts |
| `20250115_000001_fix_zohal_account_code.py` | Seed/اصلاح حساب | accounts |
| `20251202_000002_create_document_monetization_expense_account.py` | Seed حساب | accounts |
| `20251202_000003_backfill_document_monetization_accounting_documents.py` | Backfill | documents, document_lines, document_usage_charges, wallet_transactions |

---

## توصیه

برای مدیریت بهتر، می‌توانید:
1. داده‌های seed را از migration ها جدا کنید
2. یک migration جداگانه برای seed data ایجاد کنید
3. یا از یک script جداگانه برای seed استفاده کنید

