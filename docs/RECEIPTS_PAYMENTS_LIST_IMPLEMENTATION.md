# پیاده‌سازی صفحه لیست دریافت و پرداخت با ویجت جدول

## 📋 خلاصه
این سند توضیح می‌دهد که چگونه بخش لیست دریافت و پرداخت از یک ListView ساده به یک ویجت جدول پیشرفته تبدیل شده است.

## 🎯 اهداف
- جایگزینی ListView ساده با DataTableWidget پیشرفته
- افزودن قابلیت‌های جستجو، فیلتر و صفحه‌بندی
- بهبود تجربه کاربری و عملکرد
- استفاده مجدد از ویجت جدول در بخش‌های دیگر

## 📁 فایل‌های ایجاد شده

### 1. مدل داده
**مسیر:** `lib/models/receipt_payment_document.dart`

#### کلاس‌های اصلی:
- `ReceiptPaymentDocument`: مدل اصلی سند دریافت/پرداخت
- `PersonLine`: مدل خط شخص در سند
- `AccountLine`: مدل خط حساب در سند

#### ویژگی‌های کلیدی:
- پشتیبانی از JSON serialization
- محاسبه خودکار مجموع مبالغ
- تشخیص نوع سند (دریافت/پرداخت)
- فرمت‌بندی مناسب برای نمایش

### 2. سرویس
**مسیر:** `lib/services/receipt_payment_list_service.dart`

#### کلاس اصلی:
- `ReceiptPaymentListService`: مدیریت API calls

#### متدهای اصلی:
- `getList()`: دریافت لیست اسناد با فیلتر
- `getById()`: دریافت جزئیات یک سند
- `delete()`: حذف یک سند
- `deleteMultiple()`: حذف چندین سند
- `getStats()`: دریافت آمار کلی

### 3. صفحه جدید
**مسیر:** `lib/pages/business/receipts_payments_list_page.dart`

#### ویژگی‌های صفحه:
- استفاده از DataTableWidget
- فیلتر نوع سند (دریافت/پرداخت/همه)
- فیلتر بازه زمانی
- جستجوی پیشرفته
- عملیات CRUD کامل

## 🔧 تنظیمات جدول

### ستون‌های تعریف شده:
1. **کد سند** (TextColumn): نمایش کد سند
2. **نوع سند** (TextColumn): دریافت/پرداخت
3. **تاریخ سند** (DateColumn): تاریخ با فرمت جلالی
4. **مبلغ کل** (NumberColumn): مجموع مبالغ
5. **تعداد اشخاص** (NumberColumn): تعداد خطوط اشخاص
6. **تعداد حساب‌ها** (NumberColumn): تعداد خطوط حساب‌ها
7. **ایجادکننده** (TextColumn): نام کاربر
8. **تاریخ ثبت** (DateColumn): زمان ثبت
9. **عملیات** (ActionColumn): دکمه‌های عملیات

### قابلیت‌های فعال:
- ✅ جستجوی کلی
- ✅ فیلتر ستونی
- ✅ فیلتر بازه زمانی
- ✅ مرتب‌سازی
- ✅ صفحه‌بندی
- ✅ انتخاب چندتایی
- ✅ دکمه refresh
- ✅ دکمه clear filters

## 🚀 نحوه استفاده

### 1. Navigation
```dart
// در routing موجود
GoRoute(
  path: 'receipts-payments',
  name: 'business_receipts_payments',
  builder: (context, state) {
    final businessId = int.parse(state.pathParameters['business_id']!);
    return BusinessShell(
      businessId: businessId,
      authStore: _authStore!,
      localeController: controller,
      calendarController: _calendarController!,
      themeController: themeController,
      child: ReceiptsPaymentsListPage(
        businessId: businessId,
        calendarController: _calendarController!,
        authStore: _authStore!,
        apiClient: ApiClient(),
      ),
    );
  },
),
```

### 2. استفاده مستقیم
```dart
ReceiptsPaymentsListPage(
  businessId: 123,
  calendarController: calendarController,
  authStore: authStore,
  apiClient: apiClient,
)
```

## 🔄 تغییرات در Routing

### قبل:
```dart
child: ReceiptsPaymentsPage(
  businessId: businessId,
  calendarController: _calendarController!,
  authStore: _authStore!,
  apiClient: ApiClient(),
),
```

### بعد:
```dart
child: ReceiptsPaymentsListPage(
  businessId: businessId,
  calendarController: _calendarController!,
  authStore: _authStore!,
  apiClient: ApiClient(),
),
```

## 📊 API Integration

### Endpoint استفاده شده:
```
POST /businesses/{business_id}/receipts-payments
```

### پارامترهای پشتیبانی شده:
- `search`: جستجوی کلی
- `document_type`: نوع سند (receipt/payment)
- `from_date`: تاریخ شروع
- `to_date`: تاریخ پایان
- `sort_by`: فیلد مرتب‌سازی
- `sort_desc`: جهت مرتب‌سازی
- `take`: تعداد رکورد در صفحه
- `skip`: تعداد رکورد رد شده

## 🎨 UI/UX بهبودها

### قبل:
- ListView ساده
- فقط نمایش draft های محلی
- عدم وجود جستجو و فیلتر
- UI محدود

### بعد:
- DataTableWidget پیشرفته
- اتصال مستقیم به API
- جستجو و فیلتر کامل
- UI مدرن و responsive
- عملیات CRUD کامل

## 🔧 تنظیمات پیشرفته

### فیلترهای اضافی:
```dart
additionalParams: {
  if (_selectedDocumentType != null) 'document_type': _selectedDocumentType,
  if (_fromDate != null) 'from_date': _fromDate!.toIso8601String(),
  if (_toDate != null) 'to_date': _toDate!.toIso8601String(),
},
```

### تنظیمات جدول:
```dart
DataTableConfig<ReceiptPaymentDocument>(
  endpoint: '/businesses/${widget.businessId}/receipts-payments',
  searchFields: ['code', 'created_by_name'],
  filterFields: ['document_type'],
  dateRangeField: 'document_date',
  enableRowSelection: true,
  enableMultiRowSelection: true,
  defaultPageSize: 20,
  pageSizeOptions: [10, 20, 50, 100],
)
```

## 🚧 TODO های آینده

1. **صفحه افزودن سند جدید**
   - استفاده از dialog موجود
   - یکپارچه‌سازی با API

2. **صفحه جزئیات سند**
   - نمایش کامل خطوط اشخاص و حساب‌ها
   - امکان ویرایش

3. **عملیات گروهی**
   - حذف چندتایی
   - خروجی اکسل
   - چاپ اسناد

4. **بهبودهای UX**
   - انیمیشن‌های بهتر
   - حالت‌های loading پیشرفته
   - پیام‌های خطای بهتر

## 📝 نکات مهم

1. **سازگاری**: صفحه قدیمی `ReceiptsPaymentsPage` همچنان موجود است
2. **API**: از همان API موجود استفاده می‌کند
3. **مدل‌ها**: مدل‌های جدید با ساختار API سازگار هستند
4. **Performance**: صفحه‌بندی و lazy loading برای عملکرد بهتر

## 🔍 تست

### بررسی syntax:
```bash
flutter analyze lib/pages/business/receipts_payments_list_page.dart
flutter analyze lib/models/receipt_payment_document.dart
flutter analyze lib/services/receipt_payment_list_service.dart
```

### تست runtime:
1. اجرای اپلیکیشن
2. رفتن به بخش دریافت و پرداخت
3. تست فیلترها و جستجو
4. تست عملیات CRUD

## 📚 منابع

- [DataTableWidget Documentation](../hesabixUI/hesabix_ui/lib/widgets/data_table/README.md)
- [API Documentation](../hesabixAPI/adapters/api/v1/receipts_payments.py)
- [Service Implementation](../hesabixAPI/app/services/receipt_payment_service.py)
