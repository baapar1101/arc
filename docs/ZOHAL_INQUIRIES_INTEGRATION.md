# یکپارچه‌سازی دیالوگ استعلام هویتی با صفحه استعلامات
# Identity Inquiry Dialog Integration with Inquiries Page

## 📋 خلاصه تغییرات / Summary

دیالوگ شخصی‌سازی شده استعلام اطلاعات هویتی به صفحه استعلامات (`ZohalInquiriesPage`) یکپارچه شد.

The custom Identity Inquiry Dialog has been integrated into the Inquiries Page.

---

## 🔄 تغییرات انجام شده / Changes Made

### 1️⃣ فایل تغییر یافته / Modified File

```
📍 hesabixUI/hesabix_ui/lib/pages/business/zohal_inquiries_page.dart
```

### 2️⃣ تغییرات کد / Code Changes

#### ✅ افزودن Import:
```dart
import '../../widgets/zohal/identity_inquiry_dialog.dart';
```

#### ✅ تغییر متد `_selectService`:
قبل از انتخاب سرویس، بررسی می‌شود که آیا سرویس "استعلام اطلاعات هویتی" است یا خیر:

```dart
void _selectService(Map<String, dynamic> service) async {
  final serviceCode = service['service_code']?.toString() ?? '';
  
  // برای استعلام اطلاعات هویتی، دیالوگ شخصی‌سازی شده را نمایش می‌دهیم
  if (_isIdentityInquiry(serviceCode)) {
    await _showIdentityInquiryDialog();
    return;
  }
  
  // ... بقیه کد
}
```

#### ✅ افزودن متد `_isIdentityInquiry`:
برای شناسایی سرویس استعلام هویتی:

```dart
bool _isIdentityInquiry(String serviceCode) {
  final normalized = serviceCode.toLowerCase().replaceAll('/', '_').replaceAll('-', '_');
  return normalized.contains('identity') || 
         normalized.contains('national_identity') ||
         normalized.contains('national_code') ||
         serviceCode.contains('national_identity_inquiry');
}
```

#### ✅ افزودن متد `_showIdentityInquiryDialog`:
برای نمایش دیالوگ و مدیریت نتیجه:

```dart
Future<void> _showIdentityInquiryDialog() async {
  final result = await IdentityInquiryDialog.show(
    context,
    businessId: widget.businessId,
  );

  if (result != null) {
    // به‌روزرسانی موجودی کیف پول
    await _load();
    
    // نمایش نتیجه در صفحه (اختیاری)
    setState(() {
      _lastResult = result;
    });
  }
}
```

---

## 🎯 نحوه کارکرد / How It Works

### مراحل اجرا / Execution Flow:

```
1. کاربر وارد صفحه استعلامات می‌شود
   ↓
2. لیست سرویس‌های موجود نمایش داده می‌شود
   ↓
3. کاربر روی "استعلام اطلاعات هویتی" کلیک می‌کند
   ↓
4. سیستم تشخیص می‌دهد این سرویس identity inquiry است
   ↓
5. به جای فرم عمومی، دیالوگ زیبای شخصی‌سازی شده نمایش داده می‌شود
   ↓
6. کاربر اطلاعات را وارد می‌کند و استعلام را انجام می‌دهد
   ↓
7. نتیجه در دیالوگ نمایش داده می‌شود
   ↓
8. پس از بستن دیالوگ، موجودی کیف پول به‌روزرسانی می‌شود
```

### تصویر مقایسه / Comparison:

#### ❌ قبل (فرم عمومی):
```
┌─────────────────────────────┐
│ فرم استعلام                 │
├─────────────────────────────┤
│ national_code: [_________]  │
│ birth_date:    [_________]  │
│                             │
│        [ارسال درخواست]      │
└─────────────────────────────┘
```

#### ✅ بعد (دیالوگ شخصی‌سازی شده):
```
┌──────────────────────────────────┐
│  🔍 استعلام اطلاعات هویتی       │
│     Identity Inquiry             │
├──────────────────────────────────┤
│  ℹ️ لطفاً کد ملی و تاریخ تولد را │
│     وارد کنید                    │
│                                  │
│  🪪 کد ملی / National ID        │
│  [_________________]             │
│  ✓ اعتبارسنجی کامل کد ملی      │
│                                  │
│  📅 تاریخ تولد / Birth Date      │
│  [_________________] 📆          │
│  ✓ اعتبارسنجی فرمت تاریخ       │
│                                  │
│           [🔍 استعلام / Inquire] │
└──────────────────────────────────┘
```

---

## ✨ مزایای تغییرات / Benefits

### 1. **تجربه کاربری بهتر** / Better UX
- ✅ رابط کاربری زیبا و حرفه‌ای
- ✅ راهنمایی‌های واضح برای کاربر
- ✅ نمایش نتایج با طراحی مدرن

### 2. **اعتبارسنجی قوی‌تر** / Stronger Validation
- ✅ الگوریتم استاندارد کد ملی
- ✅ بررسی فرمت تاریخ شمسی
- ✅ پیام‌های خطای واضح

### 3. **چند زبانگی کامل** / Full Multilingual
- ✅ تمام متن‌ها به دو زبان فارسی و انگلیسی
- ✅ سازگار با سیستم i18n موجود

### 4. **نمایش نتایج بهتر** / Better Results Display
- ✅ کارت‌های اطلاعاتی زیبا
- ✅ نمایش وضعیت حیات
- ✅ قابلیت کپی اطلاعات

### 5. **سازگاری با سایر سرویس‌ها** / Compatibility
- ✅ سایر سرویس‌ها همچنان با فرم عمومی کار می‌کنند
- ✅ عدم تداخل با عملکرد فعلی

---

## 🔍 شناسایی سرویس / Service Detection

دیالوگ برای سرویس‌هایی نمایش داده می‌شود که `service_code` آنها شامل یکی از موارد زیر باشد:

- `identity`
- `national_identity`
- `national_code`
- `national_identity_inquiry`

### مثال‌های Service Code:

✅ نمایش دیالوگ:
- `/services/inquiry/national_identity_inquiry`
- `/services/identity`
- `/services/national-code-inquiry`
- `identity_verification`

❌ نمایش فرم عمومی:
- `/services/inquiry/card_inquiry`
- `/services/company_inquiry`
- `/services/vehicle_inquiry`

---

## 🧪 تست / Testing

### تست دستی / Manual Testing:

1. وارد صفحه استعلامات شوید:
   ```
   /business/{id}/zohal/inquiries
   ```

2. فیلتر را روی "احراز هویت" قرار دهید

3. روی سرویس "استعلام اطلاعات هویتی" کلیک کنید

4. بررسی کنید که دیالوگ شخصی‌سازی شده نمایش داده می‌شود

5. یک استعلام نمونه انجام دهید:
   - کد ملی: یک کد ملی معتبر
   - تاریخ تولد: مثلاً `1370-01-01`

6. نتیجه را بررسی کنید

7. موجودی کیف پول را بررسی کنید (باید به‌روز شده باشد)

### تست خودکار / Automated Testing:

```dart
testWidgets('Identity inquiry uses custom dialog', (WidgetTester tester) async {
  // Build ZohalInquiriesPage
  await tester.pumpWidget(
    MaterialApp(
      home: ZohalInquiriesPage(
        businessId: 1,
        authStore: mockAuthStore,
      ),
    ),
  );
  
  // Wait for services to load
  await tester.pumpAndSettle();
  
  // Tap on identity inquiry service
  await tester.tap(find.text('استعلام اطلاعات هویتی'));
  await tester.pumpAndSettle();
  
  // Verify custom dialog is shown
  expect(find.text('Identity Inquiry'), findsOneWidget);
  expect(find.text('کد ملی / National ID'), findsOneWidget);
});
```

---

## 📝 یادداشت‌های توسعه / Development Notes

### 1. افزودن سرویس‌های جدید / Adding New Services

اگر می‌خواهید برای سرویس دیگری هم دیالوگ شخصی‌سازی شده داشته باشید:

```dart
void _selectService(Map<String, dynamic> service) async {
  final serviceCode = service['service_code']?.toString() ?? '';
  
  // استعلام اطلاعات هویتی
  if (_isIdentityInquiry(serviceCode)) {
    await _showIdentityInquiryDialog();
    return;
  }
  
  // استعلام کارت بانکی (مثال)
  if (_isCardInquiry(serviceCode)) {
    await _showCardInquiryDialog();
    return;
  }
  
  // ... فرم عمومی برای بقیه
}
```

### 2. مدیریت خطاها / Error Handling

خطاها در داخل دیالوگ مدیریت می‌شوند و نیازی به مدیریت خارجی نیست:

```dart
// دیالوگ خودش خطاها را مدیریت می‌کند
final result = await IdentityInquiryDialog.show(context, businessId: id);

// اگر result null بود یعنی کاربر کنسل کرده
if (result == null) {
  // کاربر دیالوگ را بست
  return;
}

// اگر result مقداری داشت، موفق بوده
```

### 3. به‌روزرسانی موجودی / Balance Update

پس از هر استعلام موفق، موجودی به‌روز می‌شود:

```dart
if (result != null) {
  await _load(); // بارگذاری مجدد اطلاعات صفحه
}
```

---

## 🔧 عیب‌یابی / Troubleshooting

### مشکل: دیالوگ نمایش داده نمی‌شود

**علت**: احتمالاً `service_code` به درستی تشخیص داده نمی‌شود.

**راه حل**:
1. `service_code` را در API بررسی کنید
2. لاگ اضافه کنید:
   ```dart
   if (_isIdentityInquiry(serviceCode)) {
     debugPrint('Showing identity dialog for: $serviceCode');
     await _showIdentityInquiryDialog();
     return;
   }
   ```

### مشکل: موجودی به‌روز نمی‌شود

**علت**: متد `_load()` بعد از دیالوگ صدا زده نمی‌شود.

**راه حل**: مطمئن شوید که بعد از `result != null` متد `_load()` فراخوانی می‌شود.

### مشکل: خطای Import

**علت**: فایل دیالوگ پیدا نمی‌شود.

**راه حل**: مطمئن شوید فایل در مسیر صحیح است:
```
lib/widgets/zohal/identity_inquiry_dialog.dart
```

---

## 📊 آمار / Statistics

- **خطوط کد اضافه شده**: ~50 خط
- **خطوط کد حذف شده**: 0 خط
- **فایل‌های تغییر یافته**: 1 فایل
- **Linter errors**: 0 ❌
- **Breaking changes**: 0 ❌
- **Backward compatible**: ✅

---

## ✅ چک‌لیست / Checklist

- [x] دیالوگ ایجاد شد
- [x] Import به صفحه اضافه شد
- [x] متد `_selectService` تغییر کرد
- [x] متد `_isIdentityInquiry` اضافه شد
- [x] متد `_showIdentityInquiryDialog` اضافه شد
- [x] خطاها رفع شدند
- [x] تست دستی انجام شد
- [x] مستندات نوشته شد

---

## 📞 پشتیبانی / Support

در صورت بروز مشکل:
1. مستندات دیالوگ: `/docs/IDENTITY_INQUIRY_DIALOG.md`
2. این مستندات: `/docs/ZOHAL_INQUIRIES_INTEGRATION.md`
3. تیکت پشتیبانی در سیستم

---

**تاریخ یکپارچه‌سازی**: 2024-12-04
**نسخه**: 1.0.0
**وضعیت**: ✅ فعال و آماده استفاده


