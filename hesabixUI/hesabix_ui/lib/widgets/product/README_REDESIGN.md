# طراحی مجدد دیالوگ افزودن و ویرایش کالا

## خلاصه تغییرات

دیالوگ افزودن و ویرایش کالا به طور کامل بازطراحی شده تا ساختار بهتری داشته باشد و قابل نگهداری و توسعه باشد.

## مشکلات قبلی

### ساختار قبلی:
- **فایل تک‌تکه**: تمام منطق در یک فایل 550+ خطی
- **مدیریت وضعیت ضعیف**: بیش از 20 متغیر وضعیت جداگانه
- **عدم جداسازی مسئولیت‌ها**: UI، اعتبارسنجی، API و تبدیل داده همه در یک جا
- **عدم قابلیت استفاده مجدد**: بخش‌های فرم قابل استفاده مجدد نبودند
- **مدیریت خطای ضعیف**: try-catch ساده بدون پیام‌های خطای خاص
- **عدم ذخیره خودکار**: داده‌ها در صورت بسته شدن دیالوگ از دست می‌رفتند

## راه‌حل جدید

### 1. مدل داده (`ProductFormData`)
```dart
// فایل: lib/models/product_form_data.dart
class ProductFormData {
  // تمام فیلدهای فرم در یک کلاس منظم
  // متدهای copyWith، toPayload، fromProduct
  // اعتبارسنجی داخلی
}
```

### 2. کنترلر فرم (`ProductFormController`)
```dart
// فایل: lib/controllers/product_form_controller.dart
class ProductFormController extends ChangeNotifier {
  // مدیریت وضعیت متمرکز
  // بارگذاری داده‌های مرجع
  // اعتبارسنجی فرم
  // ارسال داده‌ها
}
```

### 3. بخش‌های جداگانه فرم

#### اطلاعات کلی (`ProductBasicInfoSection`)
- نوع کالا/خدمت
- کد و نام
- توضیحات
- دسته‌بندی
- ویژگی‌ها

#### قیمت و موجودی (`ProductPricingInventorySection`)
- واحدها (اصلی، فرعی، ضریب تبدیل)
- کنترل موجودی
- قیمت‌گذاری
- تنظیمات سفارش

#### مالیات (`ProductTaxSection`)
- مالیات فروش
- مالیات خرید
- کد مالیاتی

### 4. اعتبارسنجی پیشرفته (`ProductFormValidator`)
```dart
// فایل: lib/utils/product_form_validator.dart
class ProductFormValidator {
  static String? validateName(String? value)
  static String? validatePrice(String? value)
  static String? validateTaxRate(String? value)
  // و سایر متدهای اعتبارسنجی
}
```

### 5. دیالوگ اصلی (`ProductFormDialog`)
```dart
// فایل: lib/widgets/product/product_form_dialog_v2.dart
class ProductFormDialog extends StatefulWidget {
  // استفاده از TabBar برای سازماندهی بهتر
  // مدیریت خطاهای بهتر
  // UI بهبود یافته
}
```

## مزایای ساختار جدید

### 1. **قابلیت نگهداری**
- هر بخش در فایل جداگانه
- کد تمیز و قابل فهم
- جداسازی مسئولیت‌ها

### 2. **قابلیت استفاده مجدد**
- بخش‌های فرم قابل استفاده در جاهای دیگر
- کنترلر قابل استفاده برای فرم‌های مشابه

### 3. **مدیریت وضعیت بهتر**
- تمام وضعیت در یک مکان
- تغییرات خودکار UI
- اعتبارسنجی متمرکز

### 4. **تجربه کاربری بهتر**
- اعتبارسنجی لحظه‌ای
- پیام‌های خطای واضح
- UI سازمان‌یافته با تب‌ها

### 5. **قابلیت توسعه**
- افزودن بخش‌های جدید آسان
- تغییرات مستقل در هر بخش
- تست‌پذیری بهتر

## نحوه استفاده

### افزودن کالای جدید:
```dart
showDialog(
  context: context,
  builder: (context) => ProductFormDialog(
    businessId: businessId,
    authStore: authStore,
    onSuccess: () {
      // کالا با موفقیت اضافه شد
    },
  ),
);
```

### ویرایش کالای موجود:
```dart
showDialog(
  context: context,
  builder: (context) => ProductFormDialog(
    businessId: businessId,
    authStore: authStore,
    product: existingProductData,
    onSuccess: () {
      // کالا با موفقیت به‌روزرسانی شد
    },
  ),
);
```

## فایل‌های جدید

1. `lib/models/product_form_data.dart` - مدل داده فرم
2. `lib/controllers/product_form_controller.dart` - کنترلر فرم
3. `lib/widgets/product/sections/product_basic_info_section.dart` - بخش اطلاعات کلی
4. `lib/widgets/product/sections/product_pricing_inventory_section.dart` - بخش قیمت و موجودی
5. `lib/widgets/product/sections/product_tax_section.dart` - بخش مالیات
6. `lib/widgets/product/product_form_dialog.dart` - دیالوگ اصلی جدید
7. `lib/utils/product_form_validator.dart` - اعتبارسنجی فرم
8. `lib/examples/product_management_example.dart` - مثال استفاده

## مهاجرت از نسخه قدیمی

برای استفاده از نسخه جدید، کافی است:

1. فایل `product_form_dialog.dart` قدیمی با نسخه جدید جایگزین شده است
2. import ها به‌روزرسانی شده‌اند
3. از کنترلر جدید استفاده می‌شود

## ویژگی‌های آینده

- [ ] ذخیره خودکار فرم
- [ ] اعتبارسنجی سرور
- [ ] پشتیبانی از تصاویر کالا
- [ ] تاریخچه تغییرات
- [ ] قالب‌های پیش‌فرض
