# Applies a minimal Windows native fix for flutter_sound 9.29+ (CMake target + C API header).
# Safe to run repeatedly. Invoked from repo build_windows.ps1 before flutter build windows.

param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot
)

$ErrorActionPreference = "Stop"

function Get-PackageRootFromConfig {
    param(
        [string]$ConfigPath,
        [string]$PackageName
    )
    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        return $null
    }
    $config = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $package = $config.packages | Where-Object { $_.name -eq $PackageName } | Select-Object -First 1
    if (-not $package -or -not $package.rootUri) {
        return $null
    }

    $rootUri = [string]$package.rootUri
    if ([System.Uri]::IsWellFormedUriString($rootUri, [System.UriKind]::Absolute)) {
        $uri = [System.Uri]$rootUri
        $path = [System.Uri]::UnescapeDataString($uri.LocalPath)
        if ($path -match '^/[A-Za-z]:/') {
            $path = $path.Substring(1)
        }
        return $path
    }

    return [System.IO.Path]::GetFullPath(
        (Join-Path (Split-Path -Parent $ConfigPath) $rootUri)
    )
}

function Apply-FlutterSoundWindowsPatch {
    param([string]$PackageRoot)

    $patchRoot = Join-Path $PSScriptRoot "..\third_party\flutter_sound_windows_patch\windows"
    $patchRoot = (Resolve-Path -LiteralPath $patchRoot).Path

    $cmakePatch = Join-Path $patchRoot "CMakeLists.txt"
    $headerPatch = Join-Path $patchRoot "include\flutter_sound\flutter_sound_plugin_c_api.h"

    foreach ($patchFile in @($cmakePatch, $headerPatch)) {
        if (-not (Test-Path -LiteralPath $patchFile -PathType Leaf)) {
            throw "Required flutter_sound patch file is missing: $patchFile"
        }
    }

    $destWindows = Join-Path $PackageRoot "windows"
    if (-not (Test-Path -LiteralPath $destWindows)) {
        throw "flutter_sound has no windows/ folder at: $destWindows"
    }

    $destCmake = Join-Path $destWindows "CMakeLists.txt"
    if (-not (Test-Path -LiteralPath $destCmake -PathType Leaf)) {
        throw "flutter_sound CMakeLists.txt is missing: $destCmake"
    }

    $patchHash = (Get-FileHash -LiteralPath $cmakePatch -Algorithm SHA256).Hash
    $destinationHash = (Get-FileHash -LiteralPath $destCmake -Algorithm SHA256).Hash
    if ($patchHash -ne $destinationHash) {
        $destinationText = Get-Content -LiteralPath $destCmake -Raw -Encoding UTF8
        $knownUpstreamLayout =
            $destinationText -match 'set\(PLUGIN_NAME\s+"taudio_plugin"\)' -and
            $destinationText -match 'set\(taudio_bundled_libraries'
        if (-not $knownUpstreamLayout) {
            throw "Unsupported flutter_sound Windows CMake layout; refusing to overwrite $destCmake"
        }
        Copy-Item -LiteralPath $cmakePatch -Destination $destCmake -Force
    }

    $destHeaderDir = Join-Path $destWindows "include\flutter_sound"
    New-Item -ItemType Directory -Path $destHeaderDir -Force | Out-Null
    Copy-Item -LiteralPath $headerPatch -Destination (Join-Path $destHeaderDir "flutter_sound_plugin_c_api.h") -Force

    # Ephemeral plugin symlink (if already created by a prior build).
    $symlinkWindows = Join-Path $ProjectRoot "windows\flutter\ephemeral\.plugin_symlinks\flutter_sound\windows"
    if (Test-Path -LiteralPath $symlinkWindows) {
        Copy-Item -LiteralPath $cmakePatch -Destination (Join-Path $symlinkWindows "CMakeLists.txt") -Force
        $symlinkHeaderDir = Join-Path $symlinkWindows "include\flutter_sound"
        New-Item -ItemType Directory -Path $symlinkHeaderDir -Force | Out-Null
        Copy-Item -LiteralPath $headerPatch -Destination (Join-Path $symlinkHeaderDir "flutter_sound_plugin_c_api.h") -Force
    }
}

$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$configPath = Join-Path $ProjectRoot ".dart_tool\package_config.json"
$packageRoot = Get-PackageRootFromConfig -ConfigPath $configPath -PackageName "flutter_sound"

if (-not $packageRoot -or -not (Test-Path -LiteralPath $packageRoot)) {
    Write-Host "[warn] flutter_sound not found in package_config; skipping Windows patch." -ForegroundColor Yellow
    exit 0
}

$lockPath = Join-Path $ProjectRoot "pubspec.lock"
$lockText = if (Test-Path -LiteralPath $lockPath) { Get-Content -LiteralPath $lockPath -Raw } else { "" }
if ($lockText -notmatch '(?s)flutter_sound:.*?version:\s*"([^"]+)"') {
    throw "Could not read flutter_sound version from pubspec.lock; refusing an unverified patch."
} else {
    $ver = $Matches[1]
    if ([version]$ver -lt [version]"9.29.0") {
        Write-Host "[info] flutter_sound $ver (< 9.29): Windows desktop plugin patch not required." -ForegroundColor DarkGray
        exit 0
    }
    if ([version]$ver -ge [version]"10.0.0") {
        throw "flutter_sound $ver is outside the verified patch range (>=9.29.0,<10.0.0)."
    }
}

Apply-FlutterSoundWindowsPatch -PackageRoot $packageRoot
Write-Host "[step] Applied flutter_sound Windows patch (9.29+ CMake/header fix) -> $packageRoot" -ForegroundColor Green
