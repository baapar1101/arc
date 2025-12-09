# دیالوگ استعلام اطلاعات هویتی
# Identity Inquiry Dialog

## 📋 توضیحات / Description

یک دیالوگ مستقل، زیبا و چند زبانه برای استعلام اطلاعات هویتی (کد ملی و تاریخ تولد) در سیستم حسابیکس.

A standalone, beautiful, and multilingual dialog for identity inquiry (national ID and birth date) in Hesabix system.

## ✨ ویژگی‌ها / Features

### 🎨 طراحی زیبا و مدرن / Beautiful & Modern Design
- رابط کاربری جذاب با گرادینت‌های رنگی
- انیمیشن‌ها و افکت‌های بصری
- طراحی ریسپانسیو برای اندازه‌های مختلف صفحه
- استفاده از Material Design 3

### 🌍 چند زبانه / Multilingual
- پشتیبانی کامل از فارسی و انگلیسی
- تمام متن‌ها به صورت دوزبانه نمایش داده می‌شوند
- استفاده از سیستم i18n موجود در پروژه

### ✅ اعتبارسنجی قوی / Strong Validation
- اعتبارسنجی کامل کد ملی ایرانی با الگوریتم استاندارد
- بررسی فرمت و محدوده تاریخ شمسی
- نمایش پیام‌های خطای واضح و مفید

### 📊 نمایش نتایج / Results Display
- نمایش اطلاعات شخصی با طراحی کارت‌گونه
- نمایش وضعیت حیات با آیکون و رنگ مناسب
- قابلیت کپی کردن اطلاعات با یک کلیک
- مدیریت حالت‌های مختلف: موفقیت، خطا، عدم تطابق

### 🔐 امنیت / Security
- ارسال امن درخواست به API
- مدیریت صحیح خطاها
- اطلاعات محرمانه کاربر محافظت می‌شود

## 📦 نصب و استفاده / Installation & Usage

### 1. فایل قرار گرفته در:
```
lib/widgets/zohal/identity_inquiry_dialog.dart
```

### 2. Import کردن:
```dart
import 'package:hesabix_ui/widgets/zohal/identity_inquiry_dialog.dart';
```

### 3. نمایش دیالوگ:

#### روش ساده:
```dart
await IdentityInquiryDialog.show(
  context,
  businessId: currentBusinessId,
);
```

#### دریافت نتیجه:
```dart
final result = await IdentityInquiryDialog.show(
  context,
  businessId: currentBusinessId,
);

if (result != null) {
  final data = result['result']?['response_body']?['data'];
  print('نام: ${data['first_name']} ${data['last_name']}');
}
```

## 🎯 موارد استفاده / Use Cases

### 1. در منوی استعلامات:
```dart
ListTile(
  leading: const Icon(Icons.person_search),
  title: const Text('استعلام اطلاعات هویتی'),
  subtitle: const Text('Identity Inquiry'),
  onTap: () => IdentityInquiryDialog.show(
    context,
    businessId: widget.businessId,
  ),
)
```

### 2. در Floating Action Button:
```dart
floatingActionButton: FloatingActionButton.extended(
  onPressed: () => IdentityInquiryDialog.show(
    context,
    businessId: businessId,
  ),
  icon: const Icon(Icons.person_search),
  label: const Text('استعلام هویتی'),
)
```

### 3. در AppBar:
```dart
actions: [
  IconButton(
    icon: const Icon(Icons.person_search),
    tooltip: 'استعلام اطلاعات هویتی',
    onPressed: () => IdentityInquiryDialog.show(
      context,
      businessId: businessId,
    ),
  ),
]
```

### 4. در فرم ثبت مشتری:
```dart
ElevatedButton.icon(
  onPressed: () async {
    final result = await IdentityInquiryDialog.show(
      context,
      businessId: businessId,
    );
    
    if (result != null) {
      final data = result['result']?['response_body']?['data'];
      if (data?['matched'] == true) {
        // پر کردن خودکار فرم
        firstNameController.text = data['first_name'] ?? '';
        lastNameController.text = data['last_name'] ?? '';
        nationalIdController.text = data['national_code'] ?? '';
      }
    }
  },
  icon: const Icon(Icons.auto_fix_high),
  label: const Text('تکمیل خودکار از طریق استعلام'),
)
```

## 📸 اسکرین‌شات‌ها / Screenshots

### فرم ورودی / Input Form
```
┌─────────────────────────────────────┐
│  🔍 استعلام اطلاعات هویتی          │
│     Identity Inquiry                │
├─────────────────────────────────────┤
│  ℹ️ لطفاً کد ملی و تاریخ تولد را    │
│     وارد کنید                       │
│                                     │
│  🪪 کد ملی / National ID           │
│  [1234567890]                       │
│  کد ملی 10 رقمی                    │
│                                     │
│  📅 تاریخ تولد / Birth Date         │
│  [1370-01-01]           📆          │
│  تاریخ شمسی                         │
│                                     │
│              [🔍 استعلام / Inquire] │
└─────────────────────────────────────┘
```

### نمایش نتیجه موفق / Success Result
```
┌─────────────────────────────────────┐
│  👤                                 │
│  محمد محمدی                         │
│  🪪 1234567890                      │
│  [✅ زنده / Alive]                  │
├─────────────────────────────────────┤
│  👤 اطلاعات شخصی                    │
│  ─────────────────────────────────  │
│  🪪 نام / First Name                │
│     محمد                      📋    │
│                                     │
│  🪪 نام خانوادگی / Last Name       │
│     محمدی                     📋    │
│                                     │
│  👨‍👩‍👦 نام پدر / Father Name          │
│     علی                       📋    │
│                                     │
│  [🔄 استعلام جدید]    [✅ بستن]    │
└─────────────────────────────────────┘
```

### نمایش خطا / Error Display
```
┌─────────────────────────────────────┐
│          ⚠️                         │
│     عدم تطابق                       │
│     No Match                        │
│                                     │
│  کد ملی و تاریخ تولد با یکدیگر     │
│  مطابقت ندارند                      │
│                                     │
│  [🔄 استعلام جدید]    [✅ بستن]    │
└─────────────────────────────────────┘
```

## 🔧 پارامترها / Parameters

| پارامتر | نوع | الزامی | توضیحات |
|---------|-----|--------|---------|
| `businessId` | `int?` | خیر | شناسه کسب‌وکار برای ارسال به API |

## 📤 خروجی / Output

در صورت موفقیت، یک `Map<String, dynamic>` برمی‌گرداند که شامل:

```dart
{
  "result": {
    "response_body": {
      "data": {
        "matched": true,
        "first_name": "محمد",
        "last_name": "محمدی",
        "father_name": "علی",
        "national_code": "1234567890",
        "alive": true,
        "is_dead": false
      },
      "message": "عملیات موفق",
      "error_code": null
    }
  }
}
```

در صورت انصراف کاربر، `null` برمی‌گرداند.

## 🎨 سفارشی‌سازی / Customization

### تغییر رنگ‌ها:
دیالوگ به صورت خودکار از `Theme` اپلیکیشن استفاده می‌کند. برای تغییر رنگ‌ها، تم اپلیکیشن را تغییر دهید:

```dart
MaterialApp(
  theme: ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.blue,
    ),
  ),
)
```

### تغییر متن‌ها:
متن‌ها از سیستم i18n استفاده می‌کنند. برای افزودن یا تغییر متن‌ها:

1. فایل `lib/l10n/app_fa.arb` را ویرایش کنید
2. فایل `lib/l10n/app_en.arb` را ویرایش کنید
3. دستور `flutter gen-l10n` را اجرا کنید

## 🧪 تست / Testing

برای تست دیالوگ:

```dart
testWidgets('Identity inquiry dialog test', (WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => IdentityInquiryDialog.show(
              context,
              businessId: 1,
            ),
            child: const Text('Test'),
          ),
        ),
      ),
    ),
  );
  
  await tester.tap(find.text('Test'));
  await tester.pumpAndSettle();
  
  expect(find.text('استعلام اطلاعات هویتی'), findsOneWidget);
});
```

## 📝 نکات مهم / Important Notes

1. **اتصال به API**: اطمینان حاصل کنید که `ApiClient` به درستی پیکربندی شده است.

2. **مدیریت خطا**: در صورت بروز خطا، دیالوگ پیام مناسب نمایش می‌دهد و نیازی به مدیریت خارجی نیست.

3. **وابستگی‌ها**: این دیالوگ به موارد زیر وابسته است:
   - `AppLocalizations` (i18n)
   - `ApiClient`
   - `NumberNormalizer`
   - `SnackBarHelper`

4. **تطابق با Material Design 3**: این دیالوگ با MD3 سازگار است و از کامپوننت‌های جدید استفاده می‌کند.

5. **Responsive Design**: دیالوگ در اندازه‌های مختلف صفحه (موبایل، تبلت، دسکتاپ) به خوبی کار می‌کند.

## 🐛 رفع مشکلات / Troubleshooting

### خطای "ApiClient not found"
```dart
// اطمینان حاصل کنید که ApiClient به درستی import شده است:
import 'package:hesabix_ui/core/api_client.dart';
```

### خطای "AppLocalizations not found"
```dart
// اطمینان حاصل کنید که i18n تنظیم شده است:
MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
)
```

### دیالوگ نمایش داده نمی‌شود
```dart
// اطمینان حاصل کنید که context معتبر است:
Builder(
  builder: (context) => ElevatedButton(
    onPressed: () => IdentityInquiryDialog.show(context),
  ),
)
```

## 🔄 به‌روزرسانی‌ها / Updates

### نسخه 1.0.0 (2024-12-04)
- ✅ ایجاد اولیه دیالوگ
- ✅ پشتیبانی کامل از دو زبان
- ✅ اعتبارسنجی کامل ورودی‌ها
- ✅ نمایش نتایج با طراحی زیبا
- ✅ مدیریت خطاها
- ✅ قابلیت کپی اطلاعات

## 📞 پشتیبانی / Support

در صورت بروز مشکل یا نیاز به راهنمایی:
- مستندات: `/docs/IDENTITY_INQUIRY_DIALOG.md`
- مثال استفاده: `lib/widgets/zohal/identity_inquiry_dialog_example.dart`
- تیکت پشتیبانی: از بخش Support در اپلیکیشن

## 📄 مجوز / License

این کامپوننت بخشی از پروژه Hesabix است و تحت مجوز پروژه منتشر شده است.

---

**نکته**: این دیالوگ می‌تواند به راحتی برای سایر انواع استعلامات نیز تعمیم داده شود.


