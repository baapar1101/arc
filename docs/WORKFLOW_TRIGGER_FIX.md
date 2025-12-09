# 🔧 حل مشکل عدم اجرای ورک‌فلو هنگام ایجاد فاکتور

## 🎯 مشکل شناسایی شده

### خلاصه:
زمانی که فاکتور فروش جدیدی ایجاد می‌شود، **ورک‌فلو اجرا نمی‌شود** حتی اگر ورک‌فلو فعال باشد و تریگر `invoice.created` داشته باشد.

### جزئیات:
- **ورک‌فلو**: فعال ✅
- **تریگر**: `invoice.created` با فیلتر `invoice_sales` ✅
- **فاکتورهای ایجاد شده**: ۵ فاکتور در ۲۴ ساعت اخیر ✅
- **اجرای ورک‌فلو**: ❌ هیچ‌کدام ورک‌فلو را تریگر نکرده‌اند

### علت ریشه‌ای:
در تابع `create_invoice` در فایل `invoice_service.py`، **هیچ فراخوانی به `trigger_workflows` وجود نداشت**.

در مقایسه، تابع `create_manual_document` این فراخوانی را دارد:
```python
# فراخوانی workflow triggers
try:
    from app.services.workflow.workflow_trigger_service import trigger_document_created
    trigger_document_created(...)
except Exception as e:
    logger.warning(f"Failed to trigger workflows...")
```

---

## ✅ راه‌حل اعمال شده

### تغییرات کد:

در فایل `/var/www/ark/hesabixAPI/app/services/invoice_service.py` (خط ~1888)، **قبل از return**، کد زیر اضافه شد:

```python
# فراخوانی workflow triggers برای فاکتور ایجاد شده
try:
    from app.services.workflow.workflow_trigger_service import trigger_invoice_created
    trigger_invoice_created(
        db=db,
        business_id=business_id,
        invoice_id=document.id,
        invoice_type=invoice_type,
        total_amount=float(total_with_tax),
        user_id=user_id
    )
except Exception as e:
    # عدم موفقیت در trigger نباید مانع بازگشت فاکتور شود
    logger.warning(f"Failed to trigger workflows for invoice {document.id}: {e}")
```

### چه اتفاقی می‌افتد:

1. فاکتور ایجاد می‌شود و در دیتابیس commit می‌شود
2. تابع `trigger_invoice_created` فراخوانی می‌شود
3. این تابع:
   - نوع تریگر را تشخیص می‌دهد (`invoice.sales.created` برای فروش، `invoice.purchase.created` برای خرید، یا `invoice.created` به صورت عمومی)
   - تمام ورک‌فلوهای فعال با تریگر مطابق را پیدا می‌کند
   - هر ورک‌فلو را اجرا می‌کند
4. اگر خطایی رخ دهد، فقط لاگ می‌شود و فاکتور به درستی برگشت داده می‌شود

---

## 🧪 تست

### قبل از تغییر:
```
📄 فاکتورهای ایجاد شده: 5
📊 اجراهای ورک‌فلو: 0 ❌
```

### بعد از تغییر (انتظار می‌رود):
```
📄 یک فاکتور جدید ایجاد کنید
📊 ورک‌فلو به صورت خودکار اجرا می‌شود ✅
📨 پیام تلگرام ارسال می‌شود ✅
```

---

## 🚀 مراحل بعدی

### 1. ری‌استارت سرور API:
```bash
# اگر از systemd استفاده می‌کنید:
sudo systemctl restart hesabix-api

# یا اگر از Docker استفاده می‌کنید:
docker-compose restart api
```

### 2. تست ورک‌فلو:
1. وارد سیستم شوید (Business ID: 51)
2. یک فاکتور فروش جدید ایجاد کنید
3. بررسی کنید که:
   - ورک‌فلو اجرا شده (از بخش اتوماسیون‌ها > لاگ‌ها)
   - پیام تلگرام ارسال شده

### 3. بررسی لاگ‌ها:
```bash
# بررسی لاگ‌های API
tail -f /var/log/hesabix/api.log | grep -i workflow

# یا اگر از Docker استفاده می‌کنید:
docker-compose logs -f api | grep -i workflow
```

---

## 📊 انواع تریگرهای فاکتور

تابع `trigger_invoice_created` از منطق زیر برای تشخیص نوع تریگر استفاده می‌کند:

```python
if invoice_type in ["invoice_sales", "sales"]:
    trigger_type = "invoice.sales.created"
elif invoice_type in ["invoice_purchase", "purchase"]:
    trigger_type = "invoice.purchase.created"
else:
    trigger_type = "invoice.created"
```

### تریگرهای موجود:
- `invoice.created` - تمام فاکتورها
- `invoice.sales.created` - فقط فاکتورهای فروش
- `invoice.purchase.created` - فقط فاکتورهای خرید

### فیلترهای اضافی (در config تریگر):
- `invoice_type` - فیلتر بر اساس نوع دقیق فاکتور
- `min_amount` - حداقل مبلغ
- `max_amount` - حداکثر مبلغ
- `person_type` - نوع طرف حساب (حقیقی/حقوقی)
- `include_tax_details` - شامل جزئیات مالیاتی
- `include_payment_status` - شامل وضعیت پرداخت

---

## ✅ خلاصه

| مورد | قبل | بعد |
|------|-----|-----|
| فراخوانی trigger | ❌ | ✅ |
| اجرای خودکار ورک‌فلو | ❌ | ✅ |
| ارسال پیام تلگرام | ❌ | ✅ |
| سایر اکشن‌ها | ❌ | ✅ |

---

## 🔍 نکات مهم

1. **این تغییر فقط برای فاکتورهای جدید است**
   - فاکتورهای قبلی (که قبل از این تغییر ایجاد شده‌اند) ورک‌فلو را تریگر نمی‌کنند

2. **عدم موفقیت در trigger نباید مانع ایجاد فاکتور شود**
   - اگر خطایی در ورک‌فلو رخ دهد، فقط لاگ می‌شود
   - فاکتور به درستی ایجاد و برگشت داده می‌شود

3. **Performance**
   - فراخوانی trigger در یک try-except است
   - به صورت async اجرا نمی‌شود (در همان request)
   - اگر ورک‌فلوهای زیادی دارید، ممکن است response time کمی افزایش یابد

4. **Logging**
   - همه اجراهای ورک‌فلو در جدول `workflow_executions` ثبت می‌شوند
   - لاگ‌های جزئی در جدول `workflow_logs` ثبت می‌شوند
   - خطاها در لاگ API نیز ثبت می‌شوند

---

**تاریخ**: 2025-12-04
**نسخه**: 1.0
**وضعیت**: ✅ تکمیل شده - نیاز به ری‌استارت API


