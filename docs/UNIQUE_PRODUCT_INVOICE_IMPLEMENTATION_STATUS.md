# وضعیت پیاده‌سازی: انتخاب کالاهای یونیک در فاکتور

## تاریخ: 2024

---

## ✅ کارهای انجام شده

### Backend (کامل)

1. **اعتبارسنجی selected_instance_ids** (`invoice_service.py`)
   - تابع `_validate_selected_instances` ایجاد شد
   - بررسی اینکه کالا یونیک است
   - بررسی اینکه تعداد instance ها دقیقاً برابر quantity باشد
   - بررسی تکرار در لیست
   - بررسی دسترس بودن همه instance ها
   - فقط برای فاکتور فروش و برگشت از خرید

2. **اعمال اعتبارسنجی در create_invoice**
   - اعتبارسنجی در زمان ذخیره فاکتور

3. **اعمال اعتبارسنجی در update_invoice**
   - اعتبارسنجی در زمان به‌روزرسانی فاکتور

4. **انتقال selected_instance_ids به حواله** (`warehouse_service.py`)
   - در تابع `create_from_invoice`
   - خواندن `selected_instance_ids` از `extra_info` خط فاکتور
   - انتقال به `instance_ids_from_line` در حواله

### Frontend (در حال انجام)

1. **مدل InvoiceLineItem**
   - فیلد `selectedInstanceIds` اضافه شد
   - در constructor و copyWith اضافه شد

2. **تابع فرمت ویژگی‌ها** (`attribute_formatter.dart`)
   - تابع `formatAttributeValue` برای فرمت بر اساس data_type
   - پشتیبانی از text, number, date, select, boolean
   - تابع `formatAttributesForDisplay` برای نمایش چند ویژگی

3. **دیالوگ انتخاب instance ها** (`unique_product_instance_selector_dialog.dart`)
   - دیالوگ کامل برای انتخاب instance ها
   - بارگذاری ویژگی‌های کالا با data_type
   - فرمت ویژگی‌ها برای نمایش
   - جستجو و فیلتر
   - اعتبارسنجی تعداد انتخاب شده

4. **به‌روزرسانی InvoiceLineItemsTable**
   - CalendarController اضافه شد به پارامترها
   - Import دیالوگ اضافه شد

5. **به‌روزرسانی new_invoice_page**
   - CalendarController به InvoiceLineItemsTable ارسال شد
   - در `_serializeLineItem`، `selected_instance_ids` به extra_info اضافه شد

6. **به‌روزرسانی edit_invoice_page**
   - CalendarController به InvoiceLineItemsTable ارسال شد
   - در `_serializeLineItem`، `selected_instance_ids` به extra_info اضافه شد

---

## ⏳ کارهای باقی‌مانده

### Frontend

1. **بارگذاری selected_instance_ids در edit_invoice_page**
   - در تابع `_loadInvoice`، خواندن `selected_instance_ids` از `extra_info`
   - افزودن به InvoiceLineItem در زمان بارگذاری

2. **UI برای انتخاب instance ها در line_items_table**
   - افزودن دکمه "انتخاب کالای یونیک" در ردیف‌ها
   - فقط برای کالاهای یونیک (`inventory_mode == "unique"`)
   - فقط برای فاکتور فروش و برگشت از خرید
   - باز کردن دیالوگ انتخاب
   - به‌روزرسانی InvoiceLineItem با selectedInstanceIds

3. **نمایش instance های انتخاب شده در فاکتور**
   - نمایش خلاصه instance های انتخاب شده در ردیف
   - نمایش سریال نامبرها یا تعداد

4. **نمایش در حواله ایجاد شده از فاکتور**
   - در `warehouse_document_form_dialog.dart`
   - خواندن `selected_instance_ids` از فاکتور
   - نمایش instance های انتخاب شده با فرمت ویژگی‌ها

---

## 📝 نکات مهم

1. **فقط برای فاکتور فروش و برگشت از خرید**
   - این قابلیت فقط برای فاکتورهایی که حواله خارج ایجاد می‌کنند معنا دارد

2. **اختیاری بودن انتخاب**
   - اگر instance انتخاب نشود، می‌توان در زمان ایجاد حواله انتخاب کرد

3. **اعتبارسنجی**
   - تعداد instance های انتخاب شده باید دقیقاً برابر quantity باشد
   - همه instance ها باید در دسترس باشند (status == "available")

4. **فرمت ویژگی‌ها**
   - تاریخ بر اساس تقویم انتخاب شده کاربر (شمسی یا میلادی)
   - عدد با جداکننده هزارگان
   - select: نمایش label به جای value

---

## 🔄 مراحل بعدی

1. کامل کردن UI در line_items_table
2. بارگذاری selected_instance_ids در edit_invoice_page
3. نمایش در حواله
4. تست کامل سناریو

