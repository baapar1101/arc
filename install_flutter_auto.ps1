# اسکریپت خودکار نصب Flutter برای ویندوز
# این اسکریپت بدون نیاز به تعامل کاربر، Flutter را نصب می‌کند

$ErrorActionPreference = "Continue"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  نصب خودکار Flutter برای ویندوز" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# بررسی اینکه آیا Flutter قبلاً نصب شده است
try {
    $null = Get-Command flutter -ErrorAction Stop
    Write-Host "Flutter قبلاً نصب شده است!" -ForegroundColor Green
    flutter --version
    Write-Host ""
    Write-Host "اجرای flutter doctor..." -ForegroundColor Cyan
    flutter doctor
    exit 0
} catch {
    Write-Host "Flutter نصب نیست، شروع نصب..." -ForegroundColor Yellow
}

# مسیر نصب
$installPath = "$env:USERPROFILE\Development"
$flutterDir = "$installPath\flutter"

# ایجاد پوشه نصب
if (-not (Test-Path $installPath)) {
    Write-Host "ایجاد پوشه نصب: $installPath" -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $installPath -Force | Out-Null
}

# بررسی Git
$gitInstalled = $false
try {
    $null = Get-Command git -ErrorAction Stop
    $gitInstalled = $true
    Write-Host "Git یافت شد" -ForegroundColor Green
} catch {
    Write-Host "خطا: Git نصب نیست!" -ForegroundColor Red
    Write-Host "لطفاً Git را از https://git-scm.com/download/win نصب کنید" -ForegroundColor Yellow
    Write-Host "بعد از نصب Git، این اسکریپت را دوباره اجرا کنید." -ForegroundColor Yellow
    exit 1
}

# بررسی اینکه آیا Flutter قبلاً کلون شده است
if (Test-Path $flutterDir) {
    Write-Host "Flutter SDK در $flutterDir یافت شد" -ForegroundColor Yellow
    Write-Host "به‌روزرسانی Flutter..." -ForegroundColor Yellow
    Push-Location $flutterDir
    git pull
    git checkout stable
    Pop-Location
} else {
    Write-Host "در حال کلون کردن Flutter از GitHub (این کار ممکن است چند دقیقه طول بکشد)..." -ForegroundColor Yellow
    try {
        git clone https://github.com/flutter/flutter.git -b stable $flutterDir
        if ($LASTEXITCODE -ne 0) {
            throw "git clone failed with exit code $LASTEXITCODE"
        }
        Write-Host "Flutter با موفقیت کلون شد!" -ForegroundColor Green
    } catch {
        Write-Host "خطا در کلون کردن Flutter: $_" -ForegroundColor Red
        Write-Host "لطفاً اتصال اینترنت خود را بررسی کنید و دوباره تلاش کنید." -ForegroundColor Yellow
        exit 1
    }
}

# اضافه کردن Flutter به PATH
$flutterBinPath = "$flutterDir\bin"

# اضافه کردن به PATH سیستم (User Environment Variable)
$currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($currentPath -notlike "*$flutterBinPath*") {
    Write-Host "اضافه کردن Flutter به PATH..." -ForegroundColor Yellow
    try {
        [Environment]::SetEnvironmentVariable("Path", "$currentPath;$flutterBinPath", "User")
        Write-Host "Flutter به PATH اضافه شد (نیاز به restart terminal)" -ForegroundColor Green
    } catch {
        Write-Host "خطا در اضافه کردن به PATH: $_" -ForegroundColor Yellow
        Write-Host "می‌توانید بعداً به صورت دستی اضافه کنید: $flutterBinPath" -ForegroundColor Yellow
    }
} else {
    Write-Host "Flutter قبلاً در PATH است" -ForegroundColor Green
}

# اضافه کردن به PATH جلسه فعلی
if ($env:Path -notlike "*$flutterBinPath*") {
    $env:Path += ";$flutterBinPath"
}

# بررسی نصب Flutter
Write-Host ""
Write-Host "بررسی نصب Flutter..." -ForegroundColor Cyan
try {
    & "$flutterBinPath\flutter.bat" --version
} catch {
    Write-Host "خطا در اجرای flutter: $_" -ForegroundColor Red
}

Write-Host ""
Write-Host "اجرای flutter doctor (این کار ممکن است چند دقیقه طول بکشد)..." -ForegroundColor Cyan
try {
    & "$flutterBinPath\flutter.bat" doctor
} catch {
    Write-Host "خطا در اجرای flutter doctor: $_" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "نصب با موفقیت انجام شد!" -ForegroundColor Green
Write-Host ""
Write-Host "مهم: برای استفاده از Flutter، یک Terminal جدید باز کنید" -ForegroundColor Yellow
Write-Host "یا در همین terminal دستورات زیر را اجرا کنید:" -ForegroundColor Yellow
Write-Host ""
Write-Host "  `$env:Path += ';$flutterBinPath'" -ForegroundColor White
Write-Host "  cd hesabixUI\hesabix_ui" -ForegroundColor White
Write-Host "  flutter pub get" -ForegroundColor White
Write-Host "  flutter build windows" -ForegroundColor White
Write-Host ""
Write-Host "مسیر Flutter: $flutterDir" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan





