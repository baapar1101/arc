# راهنمای نصب و اجرای برنامه Flutter Windows

این راهنما برای اجرای برنامه `hesabix_ui.exe` روی کامپیوترهای دیگر (بدون نیاز به نصب Flutter) است.

## پیش‌نیازهای سیستم

### 1. سیستم عامل
- **Windows 10** (نسخه 1809 یا بالاتر) - **حداقل نیاز**
- **Windows 11** - **توصیه می‌شود**
- **Windows Server 2019** یا بالاتر (برای سرورها)

### 2. Visual C++ Redistributable (ضروری)
برنامه Flutter Windows به Visual C++ Runtime نیاز دارد.

**دانلود و نصب:**
- **Visual C++ Redistributable 2015-2022 (x64)**
- لینک دانلود: https://aka.ms/vs/17/release/vc_redist.x64.exe
- یا از سایت Microsoft: https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist

**نکته:** این فایل را باید روی کامپیوتر مقصد نصب کنید.

### 3. .NET Framework (اختیاری - بسته به پلاگین‌ها)
برخی از پلاگین‌های Flutter ممکن است به .NET Framework نیاز داشته باشند:
- **.NET Framework 4.7.2** یا بالاتر
- معمولاً در Windows 10/11 از قبل نصب است

## روش نصب و اجرا

### روش 1: کپی کامل پوشه Release (توصیه می‌شود)

1. **کپی کل پوشه Release:**
   ```
   C:\Users\babak\Desktop\arc\hesabixUI\hesabix_ui\build\windows\x64\runner\Release
   ```
   
   این پوشه شامل:
   - `hesabix_ui.exe` - فایل اجرایی اصلی
   - `flutter_windows.dll` - کتابخانه Flutter
   - `file_saver_plugin.dll` - پلاگین ذخیره فایل
   - `file_selector_windows_plugin.dll` - پلاگین انتخاب فایل
   - `flutter_secure_storage_windows_plugin.dll` - پلاگین ذخیره امن
   - `url_launcher_windows_plugin.dll` - پلاگین باز کردن URL
   - `data/` - پوشه شامل assets، فونت‌ها و داده‌های برنامه

2. **کپی به کامپیوتر مقصد:**
   - کل پوشه `Release` را کپی کنید
   - می‌توانید در هر مسیری قرار دهید (مثلاً `C:\Program Files\HesabixUI\`)

3. **نصب Visual C++ Redistributable:**
   - فایل `vc_redist.x64.exe` را دانلود و نصب کنید

4. **اجرای برنامه:**
   - روی `hesabix_ui.exe` دوبار کلیک کنید

### روش 2: ایجاد Installer (پیشرفته)

برای توزیع حرفه‌ای‌تر، می‌توانید از ابزارهای زیر استفاده کنید:
- **Inno Setup** (رایگان): https://jrsoftware.org/isinfo.php
- **NSIS** (رایگان): https://nsis.sourceforge.io/
- **WiX Toolset** (رایگان): https://wixtoolset.org/

## بررسی پیش‌نیازها

### بررسی Visual C++ Redistributable

در PowerShell یا Command Prompt:
```powershell
Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64" -ErrorAction SilentlyContinue
```

یا بررسی کنید که فایل زیر وجود دارد:
```
C:\Windows\System32\vcruntime140.dll
```

### بررسی نسخه Windows

```powershell
[System.Environment]::OSVersion.Version
```

یا:
```cmd
winver
```

## مشکلات رایج و راه‌حل

### خطا: "The code execution cannot proceed because VCRUNTIME140.dll was not found"

**راه‌حل:** Visual C++ Redistributable را نصب کنید:
- دانلود: https://aka.ms/vs/17/release/vc_redist.x64.exe

### خطا: "The application was unable to start correctly (0xc000007b)"

**راه‌حل:** 
1. Visual C++ Redistributable را نصب/بازنصب کنید
2. مطمئن شوید نسخه x64 را نصب کرده‌اید (نه x86)

### خطا: "Missing DLL files"

**راه‌حل:** 
- مطمئن شوید کل پوشه `Release` را کپی کرده‌اید
- همه فایل‌های `.dll` باید در همان پوشه `hesabix_ui.exe` باشند

### برنامه اجرا نمی‌شود

**بررسی‌ها:**
1. آیا Windows 10 (1809+) یا Windows 11 دارید؟
2. آیا Visual C++ Redistributable نصب است؟
3. آیا آنتی‌ویروس برنامه را مسدود نکرده است؟
4. آیا فایل‌ها کامل کپی شده‌اند؟

## ساختار فایل‌های مورد نیاز

```
Release/
├── hesabix_ui.exe                    (91 KB - فایل اصلی)
├── flutter_windows.dll               (17.6 MB - کتابخانه Flutter)
├── file_saver_plugin.dll             (85 KB)
├── file_selector_windows_plugin.dll  (110 KB)
├── flutter_secure_storage_windows_plugin.dll (158 KB)
├── url_launcher_windows_plugin.dll   (98 KB)
└── data/
    ├── app.so                        (کد کامپایل شده)
    ├── icudtl.dat                    (داده‌های ICU)
    └── flutter_assets/               (assets، فونت‌ها، تصاویر)
        ├── assets/
        ├── fonts/
        └── packages/
```

**حجم کل:** حدود 20-25 MB (بدون فشرده‌سازی)

## توزیع برنامه

### برای توزیع:
1. کل پوشه `Release` را فشرده کنید (ZIP)
2. فایل `vc_redist.x64.exe` را هم اضافه کنید
3. یک فایل README با دستورالعمل نصب اضافه کنید

### مثال ساختار ZIP:
```
hesabix_ui_release.zip
├── Release/              (کل پوشه Release)
├── vc_redist.x64.exe     (Visual C++ Redistributable)
└── README.txt           (دستورالعمل نصب)
```

## خلاصه پیش‌نیازها

| پیش‌نیاز | ضروری | توضیحات |
|---------|-------|---------|
| Windows 10 (1809+) یا Windows 11 | ✅ بله | حداقل نیاز سیستم عامل |
| Visual C++ Redistributable 2015-2022 | ✅ بله | برای اجرای DLL های C++ |
| .NET Framework 4.7.2+ | ⚠️ ممکن است | بسته به پلاگین‌ها |
| Flutter SDK | ❌ خیر | فقط برای ساخت نیاز است |
| Visual Studio | ❌ خیر | فقط برای ساخت نیاز است |

## لینک‌های مفید

- Visual C++ Redistributable: https://aka.ms/vs/17/release/vc_redist.x64.exe
- Microsoft Visual C++ Runtime: https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist
- Flutter Windows Deployment: https://docs.flutter.dev/deployment/windows

