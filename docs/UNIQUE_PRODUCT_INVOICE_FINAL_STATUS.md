# وضعیت نهایی پیاده‌سازی: انتخاب کالاهای یونیک در فاکتور

## تاریخ: 2024

---

## ✅ کارهای انجام شده

### Backend (کامل ✅)

1. **اعتبارسنجی selected_instance_ids** (`invoice_service.py`)
   - تابع `_validate_selected_instances` ایجاد شد
   - بررسی اینکه کالا یونیک است
   - بررسی اینکه تعداد instance ها دقیقاً برابر quantity باشد
   - بررسی تکرار در لیست
   - بررسی دسترس بودن همه instance ها
   - فقط برای فاکتور فروش و برگشت از خرید

2. **انتقال selected_instance_ids به حواله** (`warehouse_service.py`)
   - در تابع `create_from_invoice`
   - خواندن `selected_instance_ids` از `extra_info` خط فاکتور
   - انتقال به `instance_ids` در حواله
   - به‌روزرسانی وضعیت instance ها (status = "sold")

### Frontend (کامل ✅)

1. **مدل InvoiceLineItem**
   - فیلد `selectedInstanceIds` اضافه شد
   - در constructor و copyWith اضافه شد

2. **تابع فرمت ویژگی‌ها** (`attribute_formatter.dart`)
   - تابع `formatAttributeValue` برای فرمت بر اساس data_type
   - پشتیبانی از text, number, date, select, boolean
   - تابع `formatAttributesForDisplay` برای نمایش چند ویژگی
   - پشتیبانی از تقویم شمسی و میلادی

3. **دیالوگ انتخاب instance ها** (`unique_product_instance_selector_dialog.dart`)
   - دیالوگ کامل برای انتخاب instance ها
   - بارگذاری ویژگی‌های کالا با data_type
   - فرمت ویژگی‌ها برای نمایش
   - جستجو و فیلتر
   - اعتبارسنجی تعداد انتخاب شده

4. **UI در line_items_table**
   - CalendarController اضافه شد به پارامترها
   - Import دیالوگ و ProductService اضافه شد
   - Cache برای اطلاعات کالاها (`_productCache`)
   - تابع `_shouldShowInstanceSelector` برای بررسی نمایش دکمه
   - تابع `_loadProductInfo` برای بارگذاری اطلاعات کالا
   - تابع `_selectUniqueProductInstances` برای باز کردن دیالوگ
   - دکمه "انتخاب کالای یونیک" در سطر سوم هر ردیف
   - نمایش خلاصه instance های انتخاب شده
   - بارگذاری اطلاعات کالاها در initState

5. **new_invoice_page**
   - CalendarController به InvoiceLineItemsTable ارسال شد
   - در `_serializeLineItem`، `selected_instance_ids` به extra_info اضافه شد

6. **edit_invoice_page**
   - CalendarController به InvoiceLineItemsTable ارسال شد
   - در `_serializeLineItem`، `selected_instance_ids` به extra_info اضافه شد
   - در `_loadInvoice`، `selected_instance_ids` از extra_info بارگذاری شد

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

5. **نمایش در حواله**
   - instance های انتخاب شده در فاکتور به صورت خودکار به حواله منتقل می‌شوند
   - در حواله، instance_ids در extra_info ذخیره می‌شود
   - در Frontend حواله، دکمه انتخاب instance برای ویرایش موجود است

---

## 🎉 خلاصه

همه بخش‌های اصلی پیاده‌سازی شده است:
- ✅ Backend: اعتبارسنجی و انتقال
- ✅ Frontend: UI انتخاب در فاکتور
- ✅ Frontend: بارگذاری و ذخیره
- ✅ Frontend: نمایش در حواله

سیستم آماده استفاده است! 🚀

