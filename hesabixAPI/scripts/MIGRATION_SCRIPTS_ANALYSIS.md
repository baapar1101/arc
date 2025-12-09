# گزارش بررسی کامل اسکریپت‌های Migration

## خلاصه

✅ **بله، می‌توانیم یک migration کامل انجام دهیم!**

اسکریپت‌های migration موجود قابلیت انتقال کامل کسب‌وکارها و تمام موارد مرتبط را دارند.

---

## اسکریپت‌های موجود

### 1. ✅ **migrate_users_from_old_db.py**
- **نوع**: کاربران
- **وظیفه**: انتقال کاربران از hesabixOld به hesabixpy
- **وضعیت**: موجود

### 2. ✅ **migrate_businesses_complete.py**
- **نوع**: کسب‌وکارها
- **وظیفه**: 
  - انتقال کسب‌وکارها
  - انتقال سال‌های مالی
  - انتقال واحدهای ارزی
- **وضعیت**: موجود و کامل

### 3. ✅ **migrate_persons_complete.py**
- **نوع**: اشخاص
- **وظیفه**: 
  - انتقال اشخاص
  - تبدیل person_types به JSON
  - تقسیم name به first_name و last_name
- **وضعیت**: موجود و کامل

### 4. ✅ **migrate_products_complete.py**
- **نوع**: کالاها و خدمات
- **وظیفه**: 
  - انتقال دسته‌بندی‌ها
  - انتقال کالا/خدمات
  - نگاشت واحدها
- **وضعیت**: موجود و کامل

### 5. ✅ **migrate_bank_cash_petty_complete.py**
- **نوع**: حساب‌های بانکی، صندوق‌ها، تنخواه‌ها
- **وظیفه**: 
  - انتقال حساب‌های بانکی
  - انتقال صندوق‌ها (cash registers)
  - انتقال تنخواه گردان‌ها (petty cash)
- **وضعیت**: موجود و کامل

### 6. ✅ **migrate_checks_complete.py**
- **نوع**: چک‌ها
- **وظیفه**: 
  - انتقال چک‌ها
  - نگاشت انواع چک
  - نگاشت وضعیت چک‌ها
- **وضعیت**: موجود و کامل

### 7. ✅ **migrate_warehouses_complete.py**
- **نوع**: انبارها و اسناد انبار
- **وظیفه**: 
  - انتقال انبارها (warehouses)
  - انتقال اسناد انبار (warehouse documents)
  - انتقال خطوط سند انبار (warehouse document lines)
- **وضعیت**: موجود و کامل

### 8. ✅ **migrate_business_users_complete.py**
- **نوع**: کاربران عضو کسب‌وکار
- **وظیفه**: 
  - انتقال کاربران عضو کسب‌وکار
  - تبدیل permissions به JSON
- **وضعیت**: موجود و کامل

### 9. ✅ **migrate_invoices_complete.py**
- **نوع**: فاکتورها
- **وظیفه**: 
  - انتقال فاکتورهای فروش/خرید
  - انتقال برگشت از فروش/خرید
  - استفاده از invoice_service برای ایجاد فاکتورها
- **وضعیت**: موجود و کامل (با بهینه‌سازی)

### 10. ⭐ **migrate_remaining_businesses_complete.py**
- **نوع**: جامع - تمام موارد مرتبط
- **وظیفه**: 
  - انتقال کسب‌وکارهای منتقل نشده
  - **برای هر کسب‌وکار به طور خودکار انتقال می‌دهد:**
    1. ✅ سال‌های مالی
    2. ✅ اشخاص
    3. ✅ حساب‌های بانکی
    4. ✅ صندوق‌ها
    5. ✅ تنخواه‌ها
    6. ✅ کالاها/خدمات
    7. ✅ چک‌ها
    8. ✅ کاربران عضو
  - **نکته**: این اسکریپت **انبارها را منتقل نمی‌کند**
- **وضعیت**: موجود و کامل

---

## موارد قابل انتقال

### ✅ موارد موجود در اسکریپت‌ها:

1. ✅ **کاربران** (`users`)
   - اسکریپت: `migrate_users_from_old_db.py`

2. ✅ **کسب‌وکارها** (`businesses`)
   - اسکریپت: `migrate_businesses_complete.py` یا `migrate_remaining_businesses_complete.py`

3. ✅ **سال‌های مالی** (`fiscal_years`)
   - در: `migrate_businesses_complete.py` یا `migrate_remaining_businesses_complete.py`

4. ✅ **واحدهای ارزی** (`business_currencies`)
   - در: `migrate_businesses_complete.py` یا `migrate_remaining_businesses_complete.py`

5. ✅ **اشخاص** (`persons`)
   - اسکریپت: `migrate_persons_complete.py` یا در `migrate_remaining_businesses_complete.py`

6. ✅ **کالاها/خدمات** (`products`)
   - اسکریپت: `migrate_products_complete.py` یا در `migrate_remaining_businesses_complete.py`

7. ✅ **حساب‌های بانکی** (`bank_accounts`)
   - اسکریپت: `migrate_bank_cash_petty_complete.py` یا در `migrate_remaining_businesses_complete.py`

8. ✅ **صندوق‌ها** (`cash_registers`)
   - اسکریپت: `migrate_bank_cash_petty_complete.py` یا در `migrate_remaining_businesses_complete.py`

9. ✅ **تنخواه گردان‌ها** (`petty_cash`)
   - اسکریپت: `migrate_bank_cash_petty_complete.py` یا در `migrate_remaining_businesses_complete.py`

10. ✅ **چک‌ها** (`checks`)
    - اسکریپت: `migrate_checks_complete.py` یا در `migrate_remaining_businesses_complete.py`

11. ✅ **انبارها** (`warehouses`)
    - اسکریپت: `migrate_warehouses_complete.py`
    - **نکته**: در `migrate_remaining_businesses_complete.py` موجود نیست

12. ✅ **اسناد انبار** (`warehouse_documents`)
    - اسکریپت: `migrate_warehouses_complete.py`
    - **نکته**: در `migrate_remaining_businesses_complete.py` موجود نیست

13. ✅ **خطوط سند انبار** (`warehouse_document_lines`)
    - اسکریپت: `migrate_warehouses_complete.py`
    - **نکته**: در `migrate_remaining_businesses_complete.py` موجود نیست

14. ✅ **کاربران عضو کسب‌وکار** (`business_permissions`)
    - اسکریپت: `migrate_business_users_complete.py` یا در `migrate_remaining_businesses_complete.py`

15. ✅ **فاکتورها** (`documents` - invoice types)
    - اسکریپت: `migrate_invoices_complete.py`

---

## ترتیب پیشنهادی Migration

### مرحله 1: زیرساخت پایه
```
1. migrate_users_from_old_db.py          → کاربران
2. migrate_businesses_complete.py        → کسب‌وکارها + سال‌های مالی + واحدهای ارزی
```

### مرحله 2: داده‌های اصلی کسب‌وکار
```
3. migrate_persons_complete.py           → اشخاص
4. migrate_products_complete.py          → کالاها/خدمات
5. migrate_bank_cash_petty_complete.py   → بانک + صندوق + تنخواه
6. migrate_checks_complete.py            → چک‌ها
7. migrate_warehouses_complete.py        → انبارها + اسناد انبار
8. migrate_business_users_complete.py    → کاربران عضو
```

### مرحله 3: اسناد حسابداری
```
9. migrate_invoices_complete.py          → فاکتورها (sell, buy, rfsell, rfbuy)
```

**یا استفاده از اسکریپت جامع:**

### روش جامع (برای کسب‌وکارهای باقی‌مانده):
```
1. migrate_users_from_old_db.py          → کاربران (اگر لازم باشد)
2. migrate_remaining_businesses_complete.py  → کسب‌وکار + تمام موارد مرتبط (بدون انبار)
3. migrate_warehouses_complete.py        → انبارها + اسناد انبار (جداگانه)
4. migrate_invoices_complete.py          → فاکتورها
```

---

## تحلیل migrate_remaining_businesses_complete.py

### ✅ مواردی که انتقال می‌دهد:
1. ✅ کسب‌وکار
2. ✅ سال‌های مالی
3. ✅ اشخاص
4. ✅ حساب‌های بانکی
5. ✅ صندوق‌ها
6. ✅ تنخواه‌ها
7. ✅ کالاها/خدمات
8. ✅ چک‌ها
9. ✅ کاربران عضو

### ❌ مواردی که انتقال نمی‌دهد:
1. ❌ انبارها
2. ❌ اسناد انبار
3. ❌ فاکتورها

---

## پیشنهاد برای انتقال کامل

### سناریو 1: انتقال کسب‌وکارهای باقی‌مانده (250 کسب‌وکار)

**گام 1: انتقال کسب‌وکارها و موارد مرتبط**
```bash
python scripts/migrate_remaining_businesses_complete.py
```
این اسکریپت برای هر کسب‌وکار منتقل نشده:
- کسب‌وکار را ایجاد می‌کند
- سال‌های مالی را منتقل می‌کند
- اشخاص را منتقل می‌کند
- حساب‌های بانکی را منتقل می‌کند
- صندوق‌ها را منتقل می‌کند
- تنخواه‌ها را منتقل می‌کند
- کالاها را منتقل می‌کند
- چک‌ها را منتقل می‌کند
- کاربران عضو را منتقل می‌کند

**گام 2: انتقال انبارها (اختیاری)**
```bash
python scripts/migrate_warehouses_complete.py
```

**گام 3: انتقال فاکتورها**
```bash
python scripts/migrate_invoices_complete.py
```

---

## مزایای استفاده از migrate_remaining_businesses_complete.py

1. ✅ **جامع**: تمام موارد مرتبط را یکجا منتقل می‌کند
2. ✅ **خودکار**: نیاز به اجرای چند اسکریپت جداگانه نیست
3. ✅ **بهینه**: فقط کسب‌وکارهای منتقل نشده را پردازش می‌کند
4. ✅ **مستقل**: برای هر کسب‌وکار به صورت کامل عمل می‌کند
5. ✅ **Mapping هوشمند**: از case-insensitive mapping برای کاربران استفاده می‌کند

---

## نکات مهم

### 1. وابستگی‌ها
- قبل از انتقال فاکتورها، باید:
  - ✅ کسب‌وکارها منتقل شده باشند
  - ✅ اشخاص منتقل شده باشند
  - ✅ کالاها منتقل شده باشند
  - ✅ حساب‌های بانکی/صندوق/تنخواه منتقل شده باشند
  - ✅ سال‌های مالی منتقل شده باشند

### 2. Mapping
- Mapping بر اساس:
  - **کاربران**: email یا mobile (case-insensitive)
  - **کسب‌وکارها**: نام کسب‌وکار + owner_id
  - **اشخاص**: code + business_id
  - **کالاها**: code + business_id
  - **بانک/صندوق/تنخواه**: code + business_id
  - **چک‌ها**: number + business_id

### 3. انبارها
- **نکته مهم**: `migrate_remaining_businesses_complete.py` انبارها را منتقل نمی‌کند
- باید جداگانه با `migrate_warehouses_complete.py` اجرا شود

### 4. فاکتورها
- فاکتورها باید **بعد از** انتقال تمام موارد دیگر منتقل شوند
- از `migrate_invoices_complete.py` استفاده می‌شود که از `invoice_service` استفاده می‌کند

---

## نتیجه‌گیری

✅ **بله، امکان انتقال کامل وجود دارد!**

### راه‌حل پیشنهادی:

1. **برای کسب‌وکارهای باقی‌مانده (250 کسب‌وکار):**
   ```
   migrate_remaining_businesses_complete.py  → کسب‌وکار + موارد مرتبط (بدون انبار)
   migrate_warehouses_complete.py           → انبارها (اختیاری)
   migrate_invoices_complete.py             → فاکتورها
   ```

2. **این روش:**
   - ✅ تمام کسب‌وکارها را منتقل می‌کند
   - ✅ تمام داده‌های مرتبط را منتقل می‌کند
   - ✅ فاکتورهای باقی‌مانده را قابل انتقال می‌کند
   - ✅ نیاز به mapping دستی ندارد

3. **بعد از اجرا:**
   - تمام 3,651 فاکتور باقی‌مانده قابل انتقال خواهند بود
   - فقط 114 فاکتور بدون row/product/person قابل انتقال نیستند

---

## اقدامات پیشنهادی

1. ✅ اجرای `migrate_remaining_businesses_complete.py` برای انتقال کسب‌وکارها
2. ✅ (اختیاری) اجرای `migrate_warehouses_complete.py` برای انبارها
3. ✅ اجرای مجدد `migrate_invoices_complete.py` برای انتقال فاکتورهای باقی‌مانده

---

**وضعیت کلی: ✅ آماده برای انتقال کامل**

