# اسکریپت مدیریت نسخه سراسری برای پروژه Flutter (PowerShell)
# این اسکریپت نسخه را در pubspec.yaml تغییر می‌دهد و Flutter به طور خودکار
# این نسخه را به تمام پلتفرم‌ها (Android, iOS, Windows, Linux, macOS, Web) منتقل می‌کند

param(
    [string]$Project = "",
    [string]$Set = "",
    [string]$Build = "",
    [string]$SetFull = "",
    [ValidateSet("major", "minor", "patch", "build")]
    [string]$Increment = "",
    [switch]$Show,
    [switch]$Help
)

$ErrorActionPreference = "Stop"

$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$REPO_ROOT = $SCRIPT_DIR
$DEFAULT_PROJECT = "hesabixUI\hesabix_ui"

function Print-Usage {
    Write-Host "استفاده: .\update_version.ps1 [گزینه‌ها]"
    Write-Host ""
    Write-Host "گزینه‌ها:"
    Write-Host "  -Project PATH      مسیر پروژه Flutter (پیش‌فرض: $DEFAULT_PROJECT)"
    Write-Host "  -Set VERSION       تنظیم نسخه به صورت دستی (مثال: 1.0.23)"
    Write-Host "  -Build NUMBER      تنظیم شماره بیلد (مثال: 23)"
    Write-Host "  -SetFull VERSION   تنظیم نسخه کامل (مثال: 1.0.23+23)"
    Write-Host "  -Increment TYPE    افزایش نسخه (major|minor|patch|build)"
    Write-Host "  -Show              نمایش نسخه فعلی"
    Write-Host "  -Help              نمایش راهنما"
    Write-Host ""
    Write-Host "مثال‌ها:"
    Write-Host "  # نمایش نسخه فعلی"
    Write-Host "  .\update_version.ps1 -Show"
    Write-Host ""
    Write-Host "  # تنظیم نسخه به 1.0.24"
    Write-Host "  .\update_version.ps1 -Set 1.0.24"
    Write-Host ""
    Write-Host "  # تنظیم شماره بیلد به 24"
    Write-Host "  .\update_version.ps1 -Build 24"
    Write-Host ""
    Write-Host "  # تنظیم نسخه کامل"
    Write-Host "  .\update_version.ps1 -SetFull 1.0.24+24"
    Write-Host ""
    Write-Host "  # افزایش نسخه patch (1.0.23 -> 1.0.24)"
    Write-Host "  .\update_version.ps1 -Increment patch"
    Write-Host ""
    Write-Host "  # افزایش نسخه minor (1.0.23 -> 1.1.0)"
    Write-Host "  .\update_version.ps1 -Increment minor"
    Write-Host ""
    Write-Host "  # افزایش نسخه major (1.0.23 -> 2.0.0)"
    Write-Host "  .\update_version.ps1 -Increment major"
    Write-Host ""
    Write-Host "  # افزایش شماره بیلد (23 -> 24)"
    Write-Host "  .\update_version.ps1 -Increment build"
    Write-Host ""
    Write-Host "نکته: Flutter به طور خودکار نسخه را به تمام پلتفرم‌ها منتقل می‌کند:"
    Write-Host "  - Android: versionName و versionCode"
    Write-Host "  - iOS: CFBundleShortVersionString و CFBundleVersion"
    Write-Host "  - Windows: FLUTTER_VERSION_MAJOR, MINOR, PATCH, BUILD"
    Write-Host "  - Linux: از pubspec.yaml"
    Write-Host "  - macOS: CFBundleShortVersionString و CFBundleVersion"
    Write-Host "  - Web: از pubspec.yaml"
}

if ($Help) {
    Print-Usage
    exit 0
}

function Get-CurrentVersion {
    param([string]$PubspecFile)
    
    $versionLine = Get-Content $PubspecFile | Select-String -Pattern "^version:" | Select-Object -First 1
    if (-not $versionLine) {
        Write-Host "[خطا] خط version در pubspec.yaml یافت نشد" -ForegroundColor Red
        exit 1
    }
    
    $versionStr = $versionLine -replace "^version:\s*", "" -replace "\s", ""
    return $versionStr
}

function Parse-Version {
    param([string]$VersionStr)
    
    if ($VersionStr -match "^(\d+)\.(\d+)\.(\d+)\+(\d+)$") {
        return @{
            Major = [int]$Matches[1]
            Minor = [int]$Matches[2]
            Patch = [int]$Matches[3]
            Build = [int]$Matches[4]
        }
    } else {
        Write-Host "[خطا] فرمت نسخه نامعتبر: $VersionStr (باید به صورت MAJOR.MINOR.PATCH+BUILD باشد)" -ForegroundColor Red
        exit 1
    }
}

function Update-VersionInPubspec {
    param(
        [string]$PubspecFile,
        [string]$NewVersion
    )
    
    # پشتیبان‌گیری
    $backupFile = "$PubspecFile.bak"
    Copy-Item $PubspecFile $backupFile
    
    try {
        # جایگزینی نسخه
        $content = Get-Content $PubspecFile
        $content = $content -replace "^version:.*", "version: $NewVersion"
        $content | Set-Content $PubspecFile -Encoding UTF8
        
        # بررسی موفقیت
        $updated = Get-CurrentVersion $PubspecFile
        if ($updated -ne $NewVersion) {
            Copy-Item $backupFile $PubspecFile
            Write-Host "[خطا] خطا در به‌روزرسانی نسخه" -ForegroundColor Red
            exit 1
        }
        
        # حذف فایل پشتیبان
        Remove-Item $backupFile -ErrorAction SilentlyContinue
        Write-Host "[اطلاعات] نسخه به‌روزرسانی شد: $NewVersion" -ForegroundColor Green
    } catch {
        Copy-Item $backupFile $PubspecFile
        Write-Host "[خطا] خطا در به‌روزرسانی نسخه: $_" -ForegroundColor Red
        exit 1
    }
}

function Increment-Version {
    param(
        [string]$VersionStr,
        [string]$IncrementType
    )
    
    $version = Parse-Version $VersionStr
    $major = $version.Major
    $minor = $version.Minor
    $patch = $version.Patch
    $build = $version.Build
    
    switch ($IncrementType) {
        "major" {
            $major++
            $minor = 0
            $patch = 0
        }
        "minor" {
            $minor++
            $patch = 0
        }
        "patch" {
            $patch++
        }
        "build" {
            $build++
        }
        default {
            Write-Host "[خطا] نوع افزایش نامعتبر: $IncrementType (باید یکی از: major, minor, patch, build باشد)" -ForegroundColor Red
            exit 1
        }
    }
    
    return "$major.$minor.$patch+$build"
}

function Show-Version {
    param([string]$AppDir)
    
    $pubspecFile = Join-Path $AppDir "pubspec.yaml"
    $versionStr = Get-CurrentVersion $pubspecFile
    $version = Parse-Version $versionStr
    
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "نسخه فعلی برنامه:" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "  نسخه کامل: $versionStr"
    Write-Host "  Major:     $($version.Major)"
    Write-Host "  Minor:     $($version.Minor)"
    Write-Host "  Patch:     $($version.Patch)"
    Write-Host "  Build:     $($version.Build)"
    Write-Host ""
    Write-Host "این نسخه در تمام پلتفرم‌ها استفاده می‌شود:" -ForegroundColor Yellow
    Write-Host "  ✓ Android: versionName=$($version.Major).$($version.Minor).$($version.Patch), versionCode=$($version.Build)"
    Write-Host "  ✓ iOS:     CFBundleShortVersionString=$($version.Major).$($version.Minor).$($version.Patch), CFBundleVersion=$($version.Build)"
    Write-Host "  ✓ Windows: FLUTTER_VERSION=$($version.Major).$($version.Minor).$($version.Patch), BUILD=$($version.Build)"
    Write-Host "  ✓ Linux:   از pubspec.yaml"
    Write-Host "  ✓ macOS:   CFBundleShortVersionString=$($version.Major).$($version.Minor).$($version.Patch), CFBundleVersion=$($version.Build)"
    Write-Host "  ✓ Web:     از pubspec.yaml"
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""
}

# تشخیص خودکار مسیر پروژه
$APP_DIR = $null

if ($Project) {
    $pubspecPath = Join-Path $Project "pubspec.yaml"
    if (Test-Path $pubspecPath) {
        $APP_DIR = Resolve-Path $Project
    } else {
        Write-Host "[خطا] مسیر پروژه وجود ندارد یا pubspec.yaml یافت نشد: $Project" -ForegroundColor Red
        exit 1
    }
} else {
    if ($env:FLUTTER_APP_DIR) {
        $pubspecPath = Join-Path $env:FLUTTER_APP_DIR "pubspec.yaml"
        if (Test-Path $pubspecPath) {
            $APP_DIR = Resolve-Path $env:FLUTTER_APP_DIR
        }
    }
    
    if (-not $APP_DIR) {
        $commonPath = Join-Path $REPO_ROOT $DEFAULT_PROJECT
        $pubspecPath = Join-Path $commonPath "pubspec.yaml"
        if (Test-Path $pubspecPath) {
            $APP_DIR = $commonPath
        }
    }
    
    if (-not $APP_DIR) {
        Write-Host "[خطا] پروژه Flutter یافت نشد. لطفاً مسیر را با -Project مشخص کنید." -ForegroundColor Red
        exit 1
    }
}

$PUBSPEC_FILE = Join-Path $APP_DIR "pubspec.yaml"

if (-not (Test-Path $PUBSPEC_FILE)) {
    Write-Host "[خطا] فایل pubspec.yaml یافت نشد: $PUBSPEC_FILE" -ForegroundColor Red
    exit 1
}

$CURRENT_VERSION = Get-CurrentVersion $PUBSPEC_FILE
$CURRENT_VERSION_OBJ = Parse-Version $CURRENT_VERSION

# تعیین عملیات
$action = $null
if ($Show) { $action = "show" }
elseif ($Set) { $action = "set" }
elseif ($Build) { $action = "build" }
elseif ($SetFull) { $action = "set-full" }
elseif ($Increment) { $action = "increment" }

if (-not $action) {
    Print-Usage
    exit 0
}

switch ($action) {
    "show" {
        Show-Version $APP_DIR
    }
    "set" {
        if ($Set -notmatch "^\d+\.\d+\.\d+$") {
            Write-Host "[خطا] فرمت نسخه نامعتبر: $Set (باید به صورت MAJOR.MINOR.PATCH باشد، مثال: 1.0.24)" -ForegroundColor Red
            exit 1
        }
        $NEW_VERSION = "$Set+$($CURRENT_VERSION_OBJ.Build)"
        Update-VersionInPubspec $PUBSPEC_FILE $NEW_VERSION
        Show-Version $APP_DIR
    }
    "build" {
        if ($Build -notmatch "^\d+$") {
            Write-Host "[خطا] شماره بیلد باید یک عدد باشد: $Build" -ForegroundColor Red
            exit 1
        }
        $NEW_VERSION = "$($CURRENT_VERSION_OBJ.Major).$($CURRENT_VERSION_OBJ.Minor).$($CURRENT_VERSION_OBJ.Patch)+$Build"
        Update-VersionInPubspec $PUBSPEC_FILE $NEW_VERSION
        Show-Version $APP_DIR
    }
    "set-full" {
        if ($SetFull -notmatch "^\d+\.\d+\.\d+\+\d+$") {
            Write-Host "[خطا] فرمت نسخه نامعتبر: $SetFull (باید به صورت MAJOR.MINOR.PATCH+BUILD باشد، مثال: 1.0.24+24)" -ForegroundColor Red
            exit 1
        }
        Update-VersionInPubspec $PUBSPEC_FILE $SetFull
        Show-Version $APP_DIR
    }
    "increment" {
        $NEW_VERSION = Increment-Version $CURRENT_VERSION $Increment
        Update-VersionInPubspec $PUBSPEC_FILE $NEW_VERSION
        Write-Host "[اطلاعات] نسخه از $CURRENT_VERSION به $NEW_VERSION افزایش یافت" -ForegroundColor Green
        Show-Version $APP_DIR
    }
}

Write-Host ""
Write-Host "[اطلاعات] ✓ عملیات با موفقیت انجام شد!" -ForegroundColor Green
Write-Host "[اطلاعات] برای اعمال تغییرات در بیلدها، دستورات build را اجرا کنید:" -ForegroundColor Yellow
Write-Host "  .\build_android.sh"
Write-Host "  .\build_windows.ps1"
Write-Host "  flutter build ios"
Write-Host "  flutter build linux"
Write-Host "  flutter build macos"
Write-Host "  flutter build web"
Write-Host ""

