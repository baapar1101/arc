# راهنمای نصب Flutter برای ویندوز

این راهنمای کامل برای نصب Flutter و آماده‌سازی محیط برای ساخت خروجی ویندوز است.

## پیش‌نیازها

### 1. Git
Git برای مدیریت نسخه‌های Flutter لازم است.

**دانلود و نصب:**
- آدرس: https://git-scm.com/download/win
- در حین نصب، گزینه "Add Git to PATH" را انتخاب کنید

### 2. Visual Studio 2022 (برای ساخت خروجی ویندوز)
برای ساخت برنامه‌های Flutter برای ویندوز، نیاز به Visual Studio دارید.

**دانلود و نصب:**
- آدرس: https://visualstudio.microsoft.com/downloads/
- نسخه Community رایگان است
- در حین نصب، حتماً این Workloads را انتخاب کنید:
  - **Desktop development with C++**
  - (اختیاری) **Windows 10/11 SDK** (اختیاری اما توصیه می‌شود)

## نصب Flutter

### روش 1: استفاده از اسکریپت خودکار

اسکریپت `install_flutter_windows.ps1` را اجرا کنید:

```powershell
.\install_flutter_windows.ps1
```

### روش 2: نصب دستی

1. **دانلود Flutter SDK:**
   - آدرس: https://docs.flutter.dev/get-started/install/windows
   - یا لینک مستقیم: https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_3.24.0-stable.zip
   - (نسخه ممکن است تغییر کند، به سایت رسمی مراجعه کنید)

2. **استخراج فایل:**
   - فایل zip را استخراج کنید
   - پیشنهاد می‌شود در مسیر `C:\Users\<YourUsername>\Development\flutter` استخراج کنید
   - **نکته مهم:** از استخراج در مسیرهایی با دسترسی محدود (مثل `C:\Program Files\`) خودداری کنید

3. **اضافه کردن به PATH:**
   - کلید Windows + R را بزنید
   - `sysdm.cpl` را تایپ کنید و Enter بزنید
   - تب **Advanced** > دکمه **Environment Variables**
   - در بخش **User variables**، متغیر **Path** را پیدا کنید
   - روی **Edit** کلیک کنید
   - **New** را بزنید و مسیر `flutter\bin` را اضافه کنید
   - مثال: `C:\Users\<YourUsername>\Development\flutter\bin`
   - **OK** را بزنید

4. **بررسی نصب:**
   - یک PowerShell یا Command Prompt جدید باز کنید
   - دستور زیر را اجرا کنید:

```powershell
flutter --version
```

## پیکربندی Flutter

### بررسی وضعیت نصب

پس از نصب Flutter، دستور زیر را اجرا کنید:

```powershell
flutter doctor
```

این دستور وضعیت نصب و پیش‌نیازها را بررسی می‌کند.

### فعال‌سازی پشتیبانی از ویندوز

برای اطمینان از فعال بودن پشتیبانی ویندوز:

```powershell
flutter config --enable-windows-desktop
```

### نصب Dependencies پروژه

برای نصب dependencies پروژه Flutter:

```powershell
cd hesabixUI\hesabix_ui
flutter pub get
```

## ساخت خروجی برای ویندوز

### ساخت نسخه Debug

```powershell
cd hesabixUI\hesabix_ui
flutter build windows
```

فایل اجرایی در مسیر زیر قرار می‌گیرد:
```
hesabixUI\hesabix_ui\build\windows\x64\runner\Debug\hesabix_ui.exe
```

### ساخت نسخه Release

```powershell
cd hesabixUI\hesabix_ui
flutter build windows --release
```

فایل اجرایی در مسیر زیر قرار می‌گیرد:
```
hesabixUI\hesabix_ui\build\windows\x64\runner\Release\hesabix_ui.exe
```

### اجرای مستقیم در حالت توسعه

```powershell
cd hesabixUI\hesabix_ui
flutter run -d windows
```

## رفع مشکلات رایج

### مشکل: "flutter is not recognized"
**راه حل:** 
- مطمئن شوید که Flutter به PATH اضافه شده است
- یک ترمینال جدید باز کنید
- یا در همان ترمینال، دستور زیر را اجرا کنید (موقت):
```powershell
$env:Path += ";C:\Users\<YourUsername>\Development\flutter\bin"
```

### مشکل: "Visual Studio not found" در flutter doctor
**راه حل:**
- Visual Studio 2022 را نصب کنید
- مطمئن شوید که Workload "Desktop development with C++" نصب شده است
- بعد از نصب، `flutter doctor` را دوباره اجرا کنید

### مشکل: "Unable to find git in your PATH"
**راه حل:**
- Git را نصب کنید
- مطمئن شوید که Git به PATH اضافه شده است
- یک ترمینال جدید باز کنید

### مشکل: خطا در دانلود packages
**راه حل:**
اگر در ایران هستید و دسترسی به سرورهای Flutter مشکل دارد:
- اسکریپت `setup_flutter_mirror.sh` را برای تنظیم mirror استفاده کنید
- یا به صورت دستی، متغیرهای محیطی زیر را تنظیم کنید:

```powershell
$env:PUB_HOSTED_URL="https://pub.flutter-io.cn"
$env:FLUTTER_STORAGE_BASE_URL="https://storage.flutter-io.cn"
```

## منابع مفید

- مستندات رسمی Flutter: https://docs.flutter.dev/get-started/install/windows
- Flutter Community: https://flutter.dev/community
- Flutter GitHub: https://github.com/flutter/flutter

## پشتیبانی

در صورت بروز مشکل، می‌توانید:
1. خروجی `flutter doctor -v` را بررسی کنید
2. مستندات رسمی Flutter را مطالعه کنید
3. در انجمن‌های Flutter سوال بپرسید





