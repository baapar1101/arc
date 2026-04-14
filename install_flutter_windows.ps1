# اسکریپت نصب Flutter برای ویندوز
# این اسکریپت Flutter SDK را دانلود و نصب می‌کند

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  نصب Flutter برای ویندوز" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# بررسی اینکه آیا Flutter قبلاً نصب شده است
$flutterPath = Get-Command flutter -ErrorAction SilentlyContinue
if ($flutterPath) {
    Write-Host "Flutter قبلاً نصب شده است در: $($flutterPath.Source)" -ForegroundColor Green
    flutter --version
    flutter doctor
    exit 0
}

# مسیر نصب پیشنهادی
$installPath = "$env:USERPROFILE\Development"
$flutterDir = "$installPath\flutter"

# ایجاد پوشه نصب در صورت عدم وجود
if (-not (Test-Path $installPath)) {
    New-Item -ItemType Directory -Path $installPath -Force | Out-Null
    Write-Host "پوشه $installPath ایجاد شد" -ForegroundColor Green
}

# بررسی اینکه آیا Flutter SDK قبلاً دانلود شده است
if (Test-Path $flutterDir) {
    Write-Host "Flutter SDK در مسیر $flutterDir یافت شد" -ForegroundColor Yellow
    Write-Host "برای استفاده از Flutter، لطفاً مسیر زیر را به PATH اضافه کنید:" -ForegroundColor Yellow
    Write-Host "$flutterDir\bin" -ForegroundColor White
    Write-Host ""
    Write-Host "یا دستور زیر را در PowerShell اجرا کنید:" -ForegroundColor Yellow
    Write-Host '$env:Path += ";$flutterDir\bin"' -ForegroundColor White
    exit 0
}

Write-Host "Flutter SDK یافت نشد." -ForegroundColor Yellow
Write-Host ""
Write-Host "لطفاً یکی از روش‌های زیر را انتخاب کنید:" -ForegroundColor Cyan
Write-Host ""
Write-Host "روش 1: دانلود دستی" -ForegroundColor Yellow
Write-Host "  1. به آدرس زیر بروید:" -ForegroundColor White
Write-Host "     https://docs.flutter.dev/get-started/install/windows" -ForegroundColor Green
Write-Host "  2. یا از لینک مستقیم دانلود کنید:" -ForegroundColor White
Write-Host "     https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_3.24.0-stable.zip" -ForegroundColor Green
Write-Host "  3. فایل zip را استخراج کنید به: $installPath" -ForegroundColor White
Write-Host "  4. مسیر $flutterDir\bin را به PATH اضافه کنید" -ForegroundColor White
Write-Host ""
Write-Host "روش 2: استفاده از Git (اگر Git نصب است)" -ForegroundColor Yellow
Write-Host "  git clone https://github.com/flutter/flutter.git -b stable $flutterDir" -ForegroundColor White
Write-Host ""

# بررسی اینکه آیا Git نصب است
$gitPath = Get-Command git -ErrorAction SilentlyContinue
if ($gitPath) {
    Write-Host "Git یافت شد. آیا می‌خواهید Flutter را با Git کلون کنید؟ (Y/N)" -ForegroundColor Cyan
    $response = Read-Host
    if ($response -eq "Y" -or $response -eq "y") {
        Write-Host "در حال کلون کردن Flutter..." -ForegroundColor Yellow
        try {
            git clone https://github.com/flutter/flutter.git -b stable $flutterDir
            Write-Host "Flutter با موفقیت کلون شد!" -ForegroundColor Green
        } catch {
            Write-Host "خطا در کلون کردن Flutter: $_" -ForegroundColor Red
            exit 1
        }
    } else {
        Write-Host "کلون کردن لغو شد." -ForegroundColor Yellow
        exit 0
    }
} else {
    Write-Host "Git نصب نیست. لطفاً Git را از https://git-scm.com/download/win نصب کنید" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "یا Flutter SDK را به صورت دستی دانلود و استخراج کنید." -ForegroundColor Yellow
    exit 0
}

# اضافه کردن Flutter به PATH برای جلسه فعلی
$flutterBinPath = "$flutterDir\bin"
if ($env:Path -notlike "*$flutterBinPath*") {
    $env:Path += ";$flutterBinPath"
    Write-Host "Flutter به PATH جلسه فعلی اضافه شد" -ForegroundColor Green
}

# بررسی نصب Flutter
Write-Host ""
Write-Host "بررسی نصب Flutter..." -ForegroundColor Cyan
flutter --version

Write-Host ""
Write-Host "اجرای flutter doctor..." -ForegroundColor Cyan
flutter doctor

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "برای اضافه کردن دائمی Flutter به PATH:" -ForegroundColor Yellow
Write-Host "1. Windows Settings > System > About > Advanced system settings" -ForegroundColor White
Write-Host "2. Environment Variables" -ForegroundColor White
Write-Host "3. در بخش User variables، Path را انتخاب کنید و Edit کنید" -ForegroundColor White
Write-Host "4. New را بزنید و این مسیر را اضافه کنید:" -ForegroundColor White
Write-Host "   $flutterBinPath" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan





