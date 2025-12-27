# مدیریت نسخه سراسری

این پروژه از یک سیستم مدیریت نسخه سراسری استفاده می‌کند که نسخه را در یک مکان مرکزی (`pubspec.yaml`) نگهداری می‌کند و Flutter به طور خودکار آن را به تمام پلتفرم‌ها منتقل می‌کند.

## نحوه کار

نسخه در فایل `hesabixUI/hesabix_ui/pubspec.yaml` به صورت زیر تعریف می‌شود:

```yaml
version: 1.0.23+23
```

فرمت: `MAJOR.MINOR.PATCH+BUILD`

- **MAJOR**: نسخه اصلی (تغییرات بزرگ و ناسازگار)
- **MINOR**: نسخه فرعی (ویژگی‌های جدید، سازگار با قبل)
- **PATCH**: نسخه اصلاحی (رفع باگ‌ها)
- **BUILD**: شماره بیلد (برای هر بیلد افزایش می‌یابد)

Flutter به طور خودکار این نسخه را به پلتفرم‌های زیر منتقل می‌کند:

- **Android**: `versionName` (MAJOR.MINOR.PATCH) و `versionCode` (BUILD)
- **iOS**: `CFBundleShortVersionString` (MAJOR.MINOR.PATCH) و `CFBundleVersion` (BUILD)
- **Windows**: `FLUTTER_VERSION_MAJOR`, `MINOR`, `PATCH`, `BUILD`
- **Linux**: از `pubspec.yaml` خوانده می‌شود
- **macOS**: `CFBundleShortVersionString` و `CFBundleVersion`
- **Web**: از `pubspec.yaml` خوانده می‌شود

## استفاده از اسکریپت‌های مدیریت نسخه

### Linux/macOS (Bash)

```bash
# نمایش نسخه فعلی
./update_version.sh --show

# تنظیم نسخه به 1.0.24 (شماره بیلد تغییر نمی‌کند)
./update_version.sh --set 1.0.24

# تنظیم شماره بیلد به 24
./update_version.sh --build 24

# تنظیم نسخه کامل
./update_version.sh --set-full 1.0.24+24

# افزایش نسخه patch (1.0.23 -> 1.0.24)
./update_version.sh --increment patch

# افزایش نسخه minor (1.0.23 -> 1.1.0)
./update_version.sh --increment minor

# افزایش نسخه major (1.0.23 -> 2.0.0)
./update_version.sh --increment major

# افزایش شماره بیلد (23 -> 24)
./update_version.sh --increment build
```

### Windows (PowerShell)

```powershell
# نمایش نسخه فعلی
.\update_version.ps1 -Show

# تنظیم نسخه به 1.0.24
.\update_version.ps1 -Set 1.0.24

# تنظیم شماره بیلد به 24
.\update_version.ps1 -Build 24

# تنظیم نسخه کامل
.\update_version.ps1 -SetFull 1.0.24+24

# افزایش نسخه patch
.\update_version.ps1 -Increment patch

# افزایش نسخه minor
.\update_version.ps1 -Increment minor

# افزایش نسخه major
.\update_version.ps1 -Increment major

# افزایش شماره بیلد
.\update_version.ps1 -Increment build
```

## مثال‌های عملی

### سناریو 1: انتشار نسخه جدید با رفع باگ

```bash
# افزایش patch و build
./update_version.sh --increment patch
./update_version.sh --increment build
```

یا به صورت یکجا:

```bash
# افزایش patch (build هم باید افزایش یابد)
./update_version.sh --increment patch
./update_version.sh --increment build
```

### سناریو 2: افزودن ویژگی جدید

```bash
# افزایش minor (patch و build به 0 برمی‌گردند)
./update_version.sh --increment minor
./update_version.sh --increment build
```

### سناریو 3: تغییرات بزرگ

```bash
# افزایش major (minor, patch و build به 0 برمی‌گردند)
./update_version.sh --increment major
./update_version.sh --increment build
```

### سناریو 4: تنظیم دستی نسخه

```bash
# تنظیم نسخه کامل
./update_version.sh --set-full 2.0.0+50
```

## نکات مهم

1. **همیشه قبل از بیلد، نسخه را بررسی کنید**: از `--show` استفاده کنید
2. **شماره بیلد باید همیشه افزایش یابد**: برای هر بیلد جدید، build number را افزایش دهید
3. **نسخه‌گذاری معنادار**: از semantic versioning پیروی کنید
4. **پس از تغییر نسخه، بیلد کنید**: تغییرات در `pubspec.yaml` فقط در بیلدهای بعدی اعمال می‌شوند

## بررسی نسخه در خروجی‌های بیلد

### Android
```bash
# بررسی APK
aapt dump badging app-release.apk | grep version
```

### iOS
نسخه در `Info.plist` و `project.pbxproj` تنظیم می‌شود.

### Windows
نسخه در `Runner.rc` و خواص فایل EXE قابل مشاهده است.

## عیب‌یابی

اگر نسخه در پلتفرم خاصی اعمال نشد:

1. مطمئن شوید که `pubspec.yaml` به درستی به‌روزرسانی شده است
2. پروژه را clean کنید: `flutter clean`
3. دوباره بیلد کنید: `flutter build <platform>`
4. بررسی کنید که فایل‌های native (مثل `build.gradle.kts` برای Android) از متغیرهای Flutter استفاده می‌کنند




