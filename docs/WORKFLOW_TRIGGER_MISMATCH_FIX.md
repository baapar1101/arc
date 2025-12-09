# 🔧 حل مشکل عدم تطابق نوع تریگر (Trigger Type Mismatch)

## 🎯 مشکل شناسایی شده

### خلاصه:
ورک‌فلو با **trigger_type = `invoice.created`** و **فیلتر invoice_type = `invoice_sales`** هنگام ایجاد فاکتور فروش اجرا نمی‌شد.

### علت ریشه‌ای:
**عدم تطابق نوع تریگر (Trigger Type Mismatch)**

#### ورک‌فلو شما:
```json
{
  "trigger_type": "invoice.created",
  "invoice_type": "invoice_sales"
}
```

#### کد backend (قبل از تغییر):
```python
if invoice_type in ["invoice_sales", "sales"]:
    trigger_type = "invoice.sales.created"  # فقط این ارسال می‌شد
elif invoice_type in ["invoice_purchase", "purchase"]:
    trigger_type = "invoice.purchase.created"
else:
    trigger_type = "invoice.created"
```

**نتیجه:**
- ورک‌فلو منتظر تریگر: `invoice.created` ✅
- Backend ارسال می‌کرد: `invoice.sales.created` ❌
- **عدم تطابق** = ورک‌فلو اجرا نمی‌شد ❌

---

## ✅ راه‌حل اعمال شده

### تغییر در منطق trigger

فایل: `/var/www/ark/hesabixAPI/app/services/workflow/workflow_trigger_service.py`

**قبل:**
```python
# فقط یک تریگر ارسال می‌شد
if invoice_type in ["invoice_sales", "sales"]:
    trigger_type = "invoice.sales.created"
    return trigger_workflows(db, business_id, trigger_type, trigger_data, user_id)
```

**بعد:**
```python
# حالا هر دو تریگر ارسال می‌شوند
# 1. تریگر عمومی برای همه فاکتورها
executed_general = trigger_workflows(db, business_id, "invoice.created", trigger_data, user_id)

# 2. تریگر خاص برای نوع فاکتور (sales/purchase)
if specific_trigger_type:
    executed_specific = trigger_workflows(db, business_id, specific_trigger_type, trigger_data, user_id)

return executed_general + executed_specific
```

### مزایا:
1. ✅ ورک‌فلوهایی با `invoice.created` اجرا می‌شوند (عمومی)
2. ✅ ورک‌فلوهایی با `invoice.sales.created` اجرا می‌شوند (خاص)
3. ✅ ورک‌فلوهایی با `invoice.purchase.created` اجرا می‌شوند (خاص)
4. ✅ سازگار با هر دو روش کانفیگ

---

## 📊 انواع تریگرهای پشتیبانی شده

### تریگرهای قبلی (همچنان کار می‌کنند):
- `invoice.sales.created` - فقط فاکتورهای فروش
- `invoice.purchase.created` - فقط فاکتورهای خرید

### تریگر جدید (اکنون پشتیبانی می‌شود):
- `invoice.created` - **همه فاکتورها** (با قابلیت فیلتر invoice_type)

### مثال‌های کاربرد:

#### 1. همه فاکتورها (فروش + خرید):
```json
{
  "trigger_type": "invoice.created"
}
```

#### 2. فقط فاکتورهای فروش (روش 1):
```json
{
  "trigger_type": "invoice.created",
  "invoice_type": "invoice_sales"
}
```

#### 3. فقط فاکتورهای فروش (روش 2):
```json
{
  "trigger_type": "invoice.sales.created"
}
```

#### 4. فقط فاکتورهای خرید (روش 1):
```json
{
  "trigger_type": "invoice.created",
  "invoice_type": "invoice_purchase"
}
```

#### 5. فقط فاکتورهای خرید (روش 2):
```json
{
  "trigger_type": "invoice.purchase.created"
}
```

---

## 🚀 مراحل اجرا

### ⚠️ مهم: **API را ری‌استارت کنید**

```bash
# اگر از systemd استفاده می‌کنید:
sudo systemctl restart hesabix-api

# یا اگر از Docker استفاده می‌کنید:
docker-compose restart api

# یا اگر از Gunicorn استفاده می‌کنید:
sudo pkill -HUP gunicorn
```

### تست:
1. یک فاکتور فروش جدید ایجاد کنید
2. بررسی کنید که:
   - ورک‌فلو اجرا شده ✅
   - پیام تلگرام ارسال شده ✅
   - در بخش اتوماسیون‌ها > لاگ‌ها، اجرا ثبت شده ✅

---

## 🔍 بررسی مشکل از دیتابیس

### فاکتورهای اخیر که باید تریگر می‌شدند اما نشدند:

```
📄 Document ID: 299 (INV-20251205-0009) - invoice_sales
   ✅ باید تریگر شود
   ❌ اجرا نشده - مشکل احتمالی!

📄 Document ID: 298 (INV-20251205-0008) - invoice_sales
   ✅ باید تریگر شود
   ❌ اجرا نشده - مشکل احتمالی!

📄 Document ID: 297 (INV-20251204-0007) - invoice_sales
   ✅ باید تریگر شود
   ❌ اجرا نشده - مشکل احتمالی!
```

**این فاکتورها قبل از تغییرات ایجاد شده‌اند و ورک‌فلو را تریگر نکردند.**

### بعد از ری‌استارت:
فاکتورهای **جدید** (که بعد از ری‌استارت ایجاد می‌شوند) ورک‌فلو را تریگر خواهند کرد ✅

---

## 📝 نکات مهم

### 1. دو تریگر برای هر فاکتور
حالا هر فاکتور فروش **دو تریگر** ایجاد می‌کند:
- `invoice.created` - برای ورک‌فلوهای عمومی
- `invoice.sales.created` - برای ورک‌فلوهای خاص فروش

**این یعنی:**
- اگر دو ورک‌فلو با هر دو تریگر داشته باشید، **هر دو اجرا می‌شوند**
- این رفتار مورد انتظار است و مشکلی نیست
- می‌توانید ورک‌فلوهای کلی (برای همه فاکتورها) و خاص (فقط فروش/خرید) داشته باشید

### 2. فیلتر invoice_type
- اگر `trigger_type = "invoice.created"` و `invoice_type = "invoice_sales"`:
  - فقط فاکتورهای فروش را تریگر می‌کند ✅
- اگر `trigger_type = "invoice.sales.created"`:
  - فیلتر invoice_type را حذف کنید (دیگر نیازی نیست)
  - خود trigger_type فیلتر کافی است

### 3. Performance
- فراخوانی دو trigger_workflows برای هر فاکتور
- اگر هیچ ورک‌فلویی با `invoice.created` نداشته باشید، overhead بسیار کم است
- اگر ده‌ها ورک‌فلو دارید، ممکن است response time کمی افزایش یابد

### 4. سازگاری با گذشته
- ✅ ورک‌فلوهای قدیمی که `invoice.sales.created` دارند همچنان کار می‌کنند
- ✅ ورک‌فلوهای جدید که `invoice.created` دارند حالا کار می‌کنند
- ✅ هیچ breaking change وجود ندارد

---

## 🧪 تست کامل

### Checklist:

- [ ] API را ری‌استارت کنید
- [ ] یک فاکتور فروش جدید ایجاد کنید
- [ ] بررسی کنید ورک‌فلو اجرا شده (از بخش اتوماسیون‌ها)
- [ ] بررسی کنید پیام تلگرام ارسال شده
- [ ] لاگ‌های API را بررسی کنید
- [ ] یک فاکتور خرید ایجاد کنید (اگر ورک‌فلویی دارید)
- [ ] بررسی کنید ورک‌فلوهای مربوط به خرید اجرا شده‌اند

---

## 📊 آمار قبل و بعد

### قبل از تغییر:
| Trigger Type | Invoice Type | نتیجه |
|-------------|-------------|--------|
| `invoice.created` | `invoice_sales` | ❌ اجرا نمی‌شد |
| `invoice.sales.created` | - | ✅ اجرا می‌شد |

### بعد از تغییر:
| Trigger Type | Invoice Type | نتیجه |
|-------------|-------------|--------|
| `invoice.created` | `invoice_sales` | ✅ اجرا می‌شود |
| `invoice.created` | - | ✅ اجرا می‌شود (همه فاکتورها) |
| `invoice.sales.created` | - | ✅ اجرا می‌شود |

---

**تاریخ**: 2025-12-04
**نسخه**: 2.0
**وضعیت**: ✅ تکمیل شده - **نیاز به ری‌استارت API دارد**


