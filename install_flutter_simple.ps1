# اسکریپت ساده نصب Flutter برای ویندوز
# این اسکریپت Flutter را با Git کلون می‌کند

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  نصب Flutter برای ویندوز" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# بررسی اینکه آیا Flutter قبلاً نصب شده است
try {
    $flutterVersion = flutter --version 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Flutter قبلاً نصب شده است!" -ForegroundColor Green
        flutter --version
        Write-Host ""
        Write-Host "اجرای flutter doctor..." -ForegroundColor Cyan
        flutter doctor
        exit 0
    }
} catch {
    Write-Host "Flutter نصب نیست، ادامه نصب..." -ForegroundColor Yellow
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
try {
    $gitVersion = git --version 2>&1
    Write-Host "Git یافت شد: $gitVersion" -ForegroundColor Green
} catch {
    Write-Host "خطا: Git نصب نیست!" -ForegroundColor Red
    Write-Host "لطفاً Git را از https://git-scm.com/download/win نصب کنید" -ForegroundColor Yellow
    exit 1
}

# بررسی اینکه آیا Flutter قبلاً کلون شده است
if (Test-Path $flutterDir) {
    Write-Host "Flutter SDK در $flutterDir یافت شد" -ForegroundColor Yellow
    Write-Host "به‌روزرسانی Flutter..." -ForegroundColor Yellow
    Set-Location $flutterDir
    git pull
    git checkout stable
} else {
    Write-Host "در حال کلون کردن Flutter از GitHub..." -ForegroundColor Yellow
    git clone https://github.com/flutter/flutter.git -b stable $flutterDir
    if ($LASTEXITCODE -ne 0) {
        Write-Host "خطا در کلون کردن Flutter!" -ForegroundColor Red
        exit 1
    }
    Write-Host "Flutter با موفقیت کلون شد!" -ForegroundColor Green
}

# اضافه کردن Flutter به PATH برای جلسه فعلی
$flutterBinPath = "$flutterDir\bin"
$currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($currentPath -notlike "*$flutterBinPath*") {
    Write-Host "اضافه کردن Flutter به PATH..." -ForegroundColor Yellow
    [Environment]::SetEnvironmentVariable("Path", "$currentPath;$flutterBinPath", "User")
    $env:Path += ";$flutterBinPath"
    Write-Host "Flutter به PATH اضافه شد" -ForegroundColor Green
} else {
    Write-Host "Flutter قبلاً در PATH است" -ForegroundColor Green
    $env:Path += ";$flutterBinPath"
}

# بررسی نصب Flutter
Write-Host ""
Write-Host "بررسی نصب Flutter..." -ForegroundColor Cyan
Set-Location $flutterDir
.\bin\flutter.bat --version

Write-Host ""
Write-Host "اجرای flutter doctor (ممکن است چند دقیقه طول بکشد)..." -ForegroundColor Cyan
.\bin\flutter.bat doctor

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "نصب با موفقیت انجام شد!" -ForegroundColor Green
Write-Host ""
Write-Host "برای استفاده از Flutter، یک PowerShell جدید باز کنید" -ForegroundColor Yellow
Write-Host "یا دستورات زیر را اجرا کنید:" -ForegroundColor Yellow
Write-Host "  cd hesabixUI\hesabix_ui" -ForegroundColor White
Write-Host "  flutter pub get" -ForegroundColor White
Write-Host "  flutter build windows" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Cyan





