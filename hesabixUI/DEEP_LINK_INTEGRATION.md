# راهنمای یکپارچه‌سازی Deep Link

این فایل راهنمای کامل برای یکپارچه‌سازی Deep Link در اپلیکیشن حسابیکس است.

## 📱 تنظیمات انجام شده

### Android
✅ فایل `AndroidManifest.xml` اصلاح شد
✅ Deep Link Scheme: `hesabix://`
✅ Hosts پشتیبانی شده:
- `hesabix://payment/callback` - بازگشت از درگاه پرداخت
- `hesabix://dashboard` - داشبورد
- `hesabix://wallet` - کیف پول
- `hesabix://support` - پشتیبانی

### iOS
✅ فایل `Info.plist` اصلاح شد
✅ URL Scheme: `hesabix` اضافه شد

## 🔧 نحوه استفاده در کد Flutter

### 1. نصب پکیج (اختیاری - برای مدیریت بهتر)

```yaml
dependencies:
  uni_links: ^0.5.1  # یا app_links: ^3.4.0 برای روش جدیدتر
```

### 2. استفاده از کد آماده

```dart
import 'package:hesabix_ui/services/deep_link_handler.dart';

// در main.dart یا صفحه اصلی
void initState() {
  super.initState();
  
  // راه‌اندازی Deep Link Handler
  DeepLinkHandler.init((Uri uri) {
    _handleDeepLink(uri);
  });
}

void _handleDeepLink(Uri uri) {
  // پردازش payment callback
  final paymentData = DeepLinkHandler.parsePaymentCallback(uri);
  if (paymentData != null) {
    // هدایت به صفحه نتیجه پرداخت
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentResultPage(
          txId: paymentData['tx_id'],
          status: paymentData['status'],
          amount: paymentData['amount'],
          ref: paymentData['ref'],
        ),
      ),
    );
    return;
  }
  
  // سایر روت‌ها
  final route = DeepLinkHandler.getRouteFromDeepLink(uri);
  if (route != null) {
    Navigator.pushNamed(context, route);
  }
}
```

### 3. ارسال source به API

وقتی کاربر در اپ درخواست افزایش اعتبار می‌کند:

```dart
// در wallet_service.dart
Future<Map<String, dynamic>> topUp({
  required int businessId,
  required double amount,
  String? description,
  int? gatewayId,
}) async {
  final res = await _api.post<Map<String, dynamic>>(
    '/businesses/$businessId/wallet/top-up',
    data: {
      'amount': amount,
      'source': 'app',  // ⬅️ مهم: منبع را مشخص کنید
      if (description != null && description.isNotEmpty) 'description': description,
      if (gatewayId != null) 'gateway_id': gatewayId,
    },
  );
  final body = res.data as Map<String, dynamic>;
  return Map<String, dynamic>.from(body['data'] as Map);
}
```

## 🧪 تست Deep Links

### Android (ADB)
```bash
# تست payment callback موفق
adb shell am start -W -a android.intent.action.VIEW -d "hesabix://payment/callback?tx_id=28&status=success&amount=100000&ref=123456"

# تست payment callback ناموفق
adb shell am start -W -a android.intent.action.VIEW -d "hesabix://payment/callback?tx_id=29&status=failed&ref=123457"

# تست داشبورد
adb shell am start -W -a android.intent.action.VIEW -d "hesabix://dashboard"
```

### iOS (Simulator)
```bash
# تست payment callback موفق
xcrun simctl openurl booted "hesabix://payment/callback?tx_id=28&status=success&amount=100000&ref=123456"

# تست payment callback ناموفق
xcrun simctl openurl booted "hesabix://payment/callback?tx_id=29&status=failed&ref=123457"
```

## 📋 جریان کامل

### جریان پرداخت موفق:

1. کاربر در اپ روی "افزایش اعتبار" کلیک می‌کند
2. اپ درخواست به API می‌فرستد با `source: 'app'`
3. API لینک پرداخت BitPay را برمی‌گرداند
4. کاربر به مرورگر هدایت می‌شود و پرداخت می‌کند
5. بانک به callback API می‌زند با پارامتر `source=app`
6. API صفحه HTML نشان می‌دهد که:
   - پیام موفقیت نمایش می‌دهد
   - پس از 2 ثانیه تلاش می‌کند اپ را با Deep Link باز کند:
     ```
     hesabix://payment/callback?tx_id=28&status=success&amount=100000&ref=123456
     ```
7. اپ باز می‌شود و صفحه `PaymentResultPage` نمایش داده می‌شود
8. کاربر جزئیات تراکنش و موجودی جدید را می‌بیند

### جریان پرداخت ناموفق:

مشابه بالا، فقط با `status=failed` و پیام خطا

## 🎨 سفارشی‌سازی

### تغییر URL های داشبورد و پشتیبانی

در فایل `payment_callbacks.py`:

```python
dashboard_url="https://hsxn.hesabix.ir/dashboard",  # ⬅️ تغییر دهید
support_url="https://hsxn.hesabix.ir/support",      # ⬅️ تغییر دهید
```

### تغییر Deep Link Scheme

اگر می‌خواهید به جای `hesabix://` از scheme دیگری استفاده کنید:

1. در `AndroidManifest.xml`: `android:scheme="your_scheme"`
2. در `Info.plist`: `<string>your_scheme</string>`
3. در HTML templates: `your_scheme://payment/callback?...`

## ⚠️ نکات مهم

1. **تست روی دستگاه واقعی**: Deep Links ممکن است در simulator/emulator کاملاً کار نکنند
2. **App Links (Android 6+)**: برای تجربه بهتر می‌توانید App Links را فعال کنید
3. **Universal Links (iOS 9+)**: برای iOS بهتر است Universal Links استفاده شود
4. **Fallback**: همیشه یک صفحه HTML backup داشته باشید (همین الان موجود است)

## 🚀 مرحله بعد: App Links / Universal Links

برای تجربه کاربری بهتر (بدون نمایش دیالوگ انتخاب اپ):

### Android App Links
1. فایل `.well-known/assetlinks.json` در domain
2. `android:autoVerify="true"` (✅ قبلاً اضافه شده)

### iOS Universal Links
1. فایل `.well-known/apple-app-site-association` در domain
2. Associated Domains در Xcode

## 📞 پشتیبانی

در صورت بروز مشکل:
1. لاگ‌های اپ را بررسی کنید
2. تست Deep Link را با ADB/Simulator انجام دهید
3. بررسی کنید که `source: 'app'` به API ارسال می‌شود

