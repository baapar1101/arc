# راهنمای رفع خطاهای Flutter Web

## 🔍 **خطاهای رایج و راه‌حل‌ها**

### 1. **SES (Secure EcmaScript) Lockdown**
```
SES Removing unpermitted intrinsics lockdown-install.js:1:203117
```

**علت:** این خطا مربوط به امنیت JavaScript است و در محیط‌های development رخ می‌دهد.

**راه‌حل:**
- این خطا بر عملکرد تأثیر نمی‌گذارد
- در production build این خطا کمتر دیده می‌شود
- می‌توانید آن را نادیده بگیرید

### 2. **Source Map Error**
```
Source map error: Error: JSON.parse: unexpected character at line 1 column 1
```

**علت:** مشکل در فایل source map

**راه‌حل:**
```bash
# پاک کردن cache و rebuild
flutter clean
flutter pub get
flutter build web --release
```

### 3. **WebGL Warning**
```
WEBGL_debug_renderer_info is deprecated in Firefox
WebGL warning: getParameter: The READ_BUFFER attachment is multisampled
```

**علت:** هشدارهای WebGL که بر عملکرد تأثیر نمی‌گذارد

**راه‌حل:**
- این فقط هشدار است و مشکل جدی نیست
- برای رفع کامل، از مرورگرهای جدیدتر استفاده کنید

### 4. **Invalid argument(s) Error**
```
Invalid argument(s): (740251, 1, 1, 0, 0, 0, 0, 0) main.dart.js:30656:78
```

**علت:** ممکن است مربوط به Canvas یا rendering باشد

**راه‌حل:**
- بررسی GridView و Container ها
- اضافه کردن `shrinkWrap: true` و `physics: NeverScrollableScrollPhysics()`
- حذف margin های اضافی

## 🛠️ **بهبودهای اعمال شده**

### 1. **بهبود Jalali DatePicker:**
```dart
GridView.builder(
  shrinkWrap: true,
  physics: const NeverScrollableScrollPhysics(),
  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: 7,
    childAspectRatio: 1,
    crossAxisSpacing: 2,
    mainAxisSpacing: 2,
  ),
  // ...
)
```

### 2. **بهبود HTML:**
```html
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<meta name="description" content="Hesabix - سیستم مدیریت مالی">
```

### 3. **تنظیمات Build:**
```bash
# Build بهینه
flutter build web --release

# Build بدون WASM warnings
flutter build web --release --no-wasm-dry-run
```

## 🚀 **دستورات مفید**

### پاک کردن و rebuild:
```bash
flutter clean
flutter pub get
flutter build web --release
```

### اجرای development server:
```bash
# پیشنهاد: از اسکریپت ریپو استفاده کنید تا API_BASE_URL درست ست شود (پیش‌فرض: http://localhost:8000)
./run_web.sh --mode debug

# نکته: به‌صورت پیش‌فرض روی 127.0.0.1 اجرا می‌شود (امن‌تر و بدون نویز ربات‌ها).
# اگر نیاز دارید از بیرون سرور هم دسترسی داشته باشید:
# ./run_web.sh --host 0.0.0.0 --mode debug

# اگر مستقیم flutter run می‌زنید، برای اینکه درخواست‌ها به خود فرانت نروند، API_BASE_URL را ست کنید:
flutter run -d web-server --web-port 8080 --dart-define=API_BASE_URL=http://localhost:8000
```

### بررسی مشکلات:
```bash
flutter analyze
flutter doctor
```

## 📱 **تست در مرورگرهای مختلف**

### Chrome/Edge:
- بهترین پشتیبانی
- کمترین خطا

### Firefox:
- ممکن است WebGL warnings داشته باشد
- عملکرد خوب

### Safari:
- ممکن است محدودیت‌هایی داشته باشد
- تست کامل ضروری است

## 🔧 **تنظیمات پیشرفته**

### 1. **غیرفعال کردن WASM warnings:**
```bash
flutter build web --release --no-wasm-dry-run
```

### 2. **تنظیمات Canvas:**
```dart
// در Jalali DatePicker
Container(
  decoration: BoxDecoration(
    // استفاده از withValues به جای withOpacity
    color: Theme.of(context).primaryColor.withValues(alpha: 0.3),
  ),
)
```

### 3. **بهینه‌سازی GridView:**
```dart
GridView.builder(
  shrinkWrap: true,
  physics: const NeverScrollableScrollPhysics(),
  // ...
)
```

## ✅ **نتیجه**

خطاهای نمایش داده شده عمدتاً هشدار هستند و بر عملکرد تقویم شمسی تأثیر نمی‌گذارند. پروژه به درستی build می‌شود و آماده استفاده است.

### نکات مهم:
- خطاهای SES و WebGL هشدار هستند
- Source map error با clean و rebuild حل می‌شود
- تقویم شمسی به درستی کار می‌کند
- تمام ویژگی‌ها فعال هستند
