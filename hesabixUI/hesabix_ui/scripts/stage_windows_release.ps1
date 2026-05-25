# Fallback: copy Flutter engine, plugins, and assets next to hesabix_ui.exe when
# CMake INSTALL did not populate runner/Release (e.g. old CMAKE_INSTALL_PREFIX).

param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot,
    [ValidateSet("Debug", "Profile", "Release")]
    [string]$Config = "Release"
)

$ErrorActionPreference = "Stop"

$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$BuildRoot = Join-Path $ProjectRoot "build\windows\x64"
$ReleaseDir = Join-Path $BuildRoot "runner\$Config"
$Ephemeral = Join-Path $ProjectRoot "windows\flutter\ephemeral"

if (-not (Test-Path -LiteralPath $ReleaseDir)) {
    throw "Release directory not found: $ReleaseDir"
}

$existingDlls = @(Get-ChildItem -LiteralPath $ReleaseDir -Filter "*.dll" -ErrorAction SilentlyContinue)
if ($existingDlls.Count -ge 2) {
    Write-Host "[info] Windows bundle already contains $($existingDlls.Count) DLL(s); skip staging." -ForegroundColor DarkGray
    exit 0
}

Write-Host "[step] Staging Windows runtime bundle into $ReleaseDir ..." -ForegroundColor Cyan

function Copy-RequiredFile {
    param([string]$Source, [string]$Destination)
    if (-not (Test-Path -LiteralPath $Source)) {
        throw "Required file missing: $Source"
    }
    $destDir = Split-Path -Parent $Destination
    if ($destDir -and -not (Test-Path -LiteralPath $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
}

Copy-RequiredFile (Join-Path $Ephemeral "flutter_windows.dll") (Join-Path $ReleaseDir "flutter_windows.dll")

$DataDir = Join-Path $ReleaseDir "data"
New-Item -ItemType Directory -Path $DataDir -Force | Out-Null
Copy-RequiredFile (Join-Path $Ephemeral "icudtl.dat") (Join-Path $DataDir "icudtl.dat")
Copy-RequiredFile (Join-Path $ProjectRoot "build\windows\app.so") (Join-Path $DataDir "app.so")

$AssetsSrc = Join-Path $ProjectRoot "build\flutter_assets"
$AssetsDst = Join-Path $DataDir "flutter_assets"
if (-not (Test-Path -LiteralPath $AssetsSrc)) {
    throw "flutter_assets not found: $AssetsSrc (run flutter build windows first)"
}
if (Test-Path -LiteralPath $AssetsDst) {
    Remove-Item -LiteralPath $AssetsDst -Recurse -Force
}
Copy-Item -LiteralPath $AssetsSrc -Destination $AssetsDst -Recurse -Force

$PluginsRoot = Join-Path $BuildRoot "plugins"
if (Test-Path -LiteralPath $PluginsRoot) {
    Get-ChildItem -Path $PluginsRoot -Recurse -Filter "*.dll" -File -ErrorAction SilentlyContinue |
        Where-Object { $_.DirectoryName -match "\\$([regex]::Escape($Config))\\?$" } |
        ForEach-Object {
            Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $ReleaseDir $_.Name) -Force
        }
}

$pdfium = Join-Path $BuildRoot "pdfium-src\bin\pdfium.dll"
if (Test-Path -LiteralPath $pdfium) {
    Copy-Item -LiteralPath $pdfium -Destination (Join-Path $ReleaseDir "pdfium.dll") -Force
}

$nativeAssets = Join-Path $BuildRoot "native_assets\windows"
if (Test-Path -LiteralPath $nativeAssets) {
    Copy-Item -LiteralPath "$nativeAssets\*" -Destination $ReleaseDir -Recurse -Force
}

$dllCount = @(Get-ChildItem -LiteralPath $ReleaseDir -Filter "*.dll").Count
Write-Host "[step] Windows bundle staged ($dllCount DLL(s), data/, flutter_assets)." -ForegroundColor Green
