#!/usr/bin/env pwsh
# نصب NDK نسخهٔ 26.1.10909125 (r26b) مطابق android/gradle.properties — بدون sdkmanager
#
# لینک رسمی Google (ویندوز، ~631 مگابایت):
#   https://dl.google.com/android/repository/android-ndk-r26b-windows.zip
# صفحهٔ NDK: https://developer.android.com/ndk/downloads
#
# استفاده:
#   .\scripts\install_android_ndk_26_windows.ps1
#   .\scripts\install_android_ndk_26_windows.ps1 -SdkRoot "D:\Android\Sdk"
# اگر دسترسی مستقیم به Google ندارید، با مرورگر/VPN دانلود کنید و مسیر زیپ را بدهید:
#   .\scripts\install_android_ndk_26_windows.ps1 -ZipPath "$env:USERPROFILE\Downloads\android-ndk-r26b-windows.zip"
#
# محتوای زیپ یک پوشهٔ android-ndk-r26b است؛ به Sdk\ndk\26.1.10909125 منتقل می‌شود.

param(
    [string]$SdkRoot = "",
    [string]$ZipPath = "",
    [switch]$Force
)

$ErrorActionPreference = "Stop"

$NdkVersion = "26.1.10909125"
$ZipName = "android-ndk-r26b-windows.zip"
$ZipUrl = "https://dl.google.com/android/repository/$ZipName"
$InnerFolderName = "android-ndk-r26b"

if (-not $SdkRoot) {
    if ($env:ANDROID_SDK_ROOT) { $SdkRoot = $env:ANDROID_SDK_ROOT }
    elseif ($env:ANDROID_HOME) { $SdkRoot = $env:ANDROID_HOME }
    else { $SdkRoot = Join-Path $env:LOCALAPPDATA "Android\Sdk" }
}

$destDir = Join-Path $SdkRoot "ndk\$NdkVersion"
$props = Join-Path $destDir "source.properties"

if ((Test-Path -LiteralPath $props) -and -not $Force) {
    Write-Host "NDK already present: $destDir (source.properties exists). Use -Force to reinstall." -ForegroundColor Green
    exit 0
}

$tempRoot = Join-Path $env:TEMP "hesabix_ndk_install_$(Get-Random)"
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

try {
    if ($ZipPath) {
        if (-not (Test-Path -LiteralPath $ZipPath)) {
            throw "ZipPath not found: $ZipPath"
        }
        $zipPath = (Resolve-Path -LiteralPath $ZipPath).Path
        Write-Host "Using local zip: $zipPath" -ForegroundColor Cyan
    } else {
        $zipPath = Join-Path $tempRoot $ZipName
        Write-Host "Downloading (official Google, ~631 MB): $ZipUrl" -ForegroundColor Cyan
        Write-Host "  Tip: if this hangs, use VPN or download in a browser then: -ZipPath <path>" -ForegroundColor DarkGray
        $ProgressPreference = "SilentlyContinue"
        $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
        if ($curl) {
            & curl.exe -fL --retry 5 --retry-delay 5 --connect-timeout 30 -o $zipPath $ZipUrl
            if ($LASTEXITCODE -ne 0) {
                throw "curl download failed with exit code $LASTEXITCODE"
            }
        } else {
            Invoke-WebRequest -Uri $ZipUrl -OutFile $zipPath -UseBasicParsing
        }
    }

    Write-Host "Extracting..." -ForegroundColor Cyan
    Expand-Archive -LiteralPath $zipPath -DestinationPath $tempRoot -Force

    $inner = Join-Path $tempRoot $InnerFolderName
    if (-not (Test-Path -LiteralPath $inner)) {
        $found = Get-ChildItem -LiteralPath $tempRoot -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "android-ndk-*" } | Select-Object -First 1
        if ($found) { $inner = $found.FullName }
    }
    if (-not (Test-Path -LiteralPath $inner)) {
        throw "Extracted folder not found (expected $InnerFolderName under $tempRoot)."
    }

    $sourceProps = Join-Path $inner "source.properties"
    if (-not (Test-Path -LiteralPath $sourceProps)) {
        throw "Invalid NDK package: missing source.properties under $inner"
    }

    New-Item -ItemType Directory -Path (Split-Path $destDir -Parent) -Force | Out-Null
    if (Test-Path -LiteralPath $destDir) {
        Write-Host "Removing previous $destDir" -ForegroundColor Yellow
        Remove-Item -LiteralPath $destDir -Recurse -Force
    }

    Write-Host "Installing to: $destDir" -ForegroundColor Cyan
    Move-Item -LiteralPath $inner -Destination $destDir

    if (-not (Test-Path -LiteralPath (Join-Path $destDir "source.properties"))) {
        throw "Install verification failed (source.properties missing)."
    }

    Write-Host "OK: NDK $NdkVersion installed at $destDir" -ForegroundColor Green
} finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
