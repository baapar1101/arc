# به‌روزرسانی خودکار ویندوز (Forgejo Releases + Advanced Installer)

## هدف

کاربران دسکتاپ ویندوز، هنگام انتشار نسخهٔ جدید در
[ریلیزهای مخزن](https://source.hesabix.ir/hesabix/arc/releases) اعلان بگیرند،
بستهٔ نصب (MSI/Setup) را دانلود کنند و نصب‌کننده را اجرا کنند.

**وب و اندروید تحت تأثیر قرار نمی‌گیرند.** ماژول فقط وقتی
`supportsWindowsDesktopUpdate` برقرار باشد اجرا می‌شود
(`!kIsWeb && TargetPlatform.windows`). سرویس از conditional import
(stub برای وب / IO برای دسکتاپ) استفاده می‌کند.

## معیار نسخه

همان قرارداد اندروید (`docs/ANDROID_AUTO_UPDATE.md` و `docs/VERSION_MANAGEMENT.md`):

| مورد | مقدار |
|------|--------|
| منبع حقیقت | تگ ریلیز Forgejo (`tag_name`) = `MAJOR.MINOR.PATCH` |
| نسخه نصب‌شده | `PackageInfo.version` از Flutter / `pubspec.yaml` |
| asset ویندوز | ترجیح: `hesabix-windows.<version>.msi` سپس هر `.msi`، سپس setup-like `.exe` |
| ریلیز فقط اندروید | اگر تگ جدیدتر باشد ولی asset ویندوز نباشد → برای ویندوز «به‌روز» (بدون اعلان) |

## سناریوی کاربر

1. اپ ویندوز پس از آماده شدن شل (با تأخیر کوتاه) `releases/latest` را می‌خواند.
2. اگر نسخه ریموت بزرگ‌تر باشد و asset ویندوز موجود باشد و کاربر «بعداً» نزده باشد:
   - دیالوگ changelog + حجم فایل
   - دانلود با progress و امکان لغو
3. پس از دانلود، تأیید برای اجرای نصب‌کننده؛ سپس `msiexec /i` یا اجرای Setup EXE و بستن اپ.
4. در **تنظیمات حساب → به‌روزرسانی برنامه (ویندوز)**: بررسی دستی، دانلود، تنظیمات auto-check / auto-download.

## API

- `GET https://source.hesabix.ir/api/v1/repos/hesabix/arc/releases/latest`
- دانلود از `assets[].browser_download_url` (فقط assetهای ویندوز)

## پایپ‌لاین بیلد و انتشار

```powershell
# 1) نسخه
.\update_version.ps1 -Set 70.11.381   # یا Set-Full / Increment

# 2) بیلد Flutter Windows
.\build_windows.ps1 -Mode release -Clean

# 3) ساخت MSI با Advanced Installer
.\build_windows_installer.ps1

# 4) آپلود به Forgejo (همان تگ؛ در صورت وجود ریلیز اندروید فقط asset ویندوز اضافه می‌شود)
$env:FORGEJO_TOKEN='...'
.\release_windows_forgejo.ps1
```

جزئیات Advanced Installer: `installer/windows/README.md`

## ایزوله‌سازی پلتفرم (الزامی)

| لایه | رفتار |
|------|--------|
| `WindowsUpdateGate` | فقط روی ویندوز زمان‌بندی چک |
| روت `/user/profile/windows-update-settings` | روی غیر ویندوز redirect به account-settings |
| کارت تنظیمات حساب | فقط اگر `showWindowsUpdateSettingsEntry()` |
| prefs | کلیدهای جدا (`windows_update_*`) از اندروید |
| سرویس | stub روی وب؛ بدون `dart:io` در UI |

## نکات امنیتی / عملیاتی

- MSI را در صورت امکان **Code Sign** کنید تا SmartScreen کمتر مزاحم شود.
- برای جایگزینی فایل‌های در حال اجرا، اپ پس از شروع نصب‌کننده بسته می‌شود (UAC ممکن است ظاهر شود).
- ریلیز مشترک با اندروید: یک تگ، چند asset (`app-release.*.apk` + `hesabix-windows.*.msi`).
