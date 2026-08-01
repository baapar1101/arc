# Build a Windows MSI for Hesabix using Advanced Installer CLI.
# Packages the Flutter Windows Release folder into hesabix-windows.<version>.msi
#
# Prerequisites:
#   1) .\build_windows.ps1 -Mode release
#   2) Advanced Installer installed (AdvancedInstaller.com on PATH or default location)
#
# See installer\windows\README.md and docs\WINDOWS_AUTO_UPDATE.md

param(
    [string]$ProjectRoot = "",
    [string]$ReleaseDir = "",
    [string]$PubspecPath = "",
    [string]$AdvInstPath = "",
    [string]$AipPath = "",
    [string]$OutDir = "",
    [string]$ProductName = "Hesabix",
    [string]$Manufacturer = "Hesabix",
    [string]$ExeName = "hesabix_ui.exe",
    [switch]$SkipNewProject,
    [switch]$DryRun,
    [switch]$Help
)

$ErrorActionPreference = "Stop"

$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$REPO_ROOT = $SCRIPT_DIR

function Write-Usage {
    Write-Host @"
Usage: .\build_windows_installer.ps1 [options]

Options:
  -ReleaseDir PATH     Flutter Windows Release folder
  -PubspecPath PATH    pubspec.yaml (for Product Version)
  -AdvInstPath PATH    Path to AdvancedInstaller.com
  -AipPath PATH        Advanced Installer project (.aip)
  -OutDir PATH         Output directory for MSI
  -SkipNewProject      Do not recreate AIP; only edit version/files and build
  -DryRun              Print actions only
  -Help                Show help
"@
}

if ($Help) {
    Write-Usage
    exit 0
}

function Find-AdvancedInstallerCom {
    param([string]$Explicit)
    if ($Explicit) {
        if (-not (Test-Path -LiteralPath $Explicit)) {
            throw "AdvancedInstaller.com not found: $Explicit"
        }
        return (Resolve-Path -LiteralPath $Explicit).Path
    }
    $cmd = Get-Command AdvancedInstaller.com -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $roots = @(
        "${env:ProgramFiles(x86)}\Caphyon",
        "${env:ProgramFiles}\Caphyon"
    )
    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        $found = Get-ChildItem -Path $root -Recurse -Filter "AdvancedInstaller.com" -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($found) { return $found.FullName }
    }
    throw "Advanced Installer not found. Install it or pass -AdvInstPath."
}

function Get-PubspecVersionName {
    param([string]$Path)
    $line = Get-Content -LiteralPath $Path -ErrorAction Stop |
        Where-Object { $_ -match '^\s*version:\s*' } |
        Select-Object -First 1
    if (-not $line) { throw "No version: line in $Path" }
    if ($line -match '^\s*version:\s*([^\s#]+)') {
        $full = $Matches[1].Trim().Trim(([char[]]@(34, 39)))
        $name = ($full -split '\+', 2)[0].Trim()
        $parts = $name -split '\.'
        if ($parts.Count -ne 3 -or ($parts | Where-Object { $_ -notmatch '^\d+$' })) {
            throw "versionName must be MAJOR.MINOR.PATCH, got: $name"
        }
        return $name
    }
    throw "Could not parse version from $Path"
}

function Invoke-AdvInst {
    param(
        [string]$Exe,
        [string[]]$CliArgs
    )
    Write-Host "[advinst] $Exe $($CliArgs -join ' ')" -ForegroundColor DarkGray
    if ($DryRun) { return 0 }
    $p = Start-Process -FilePath $Exe -ArgumentList @($CliArgs) -Wait -PassThru -NoNewWindow
    return $p.ExitCode
}

if (-not $ProjectRoot) {
    $ProjectRoot = Join-Path $REPO_ROOT "hesabixUI\hesabix_ui"
}
if (-not $PubspecPath) {
    $PubspecPath = Join-Path $ProjectRoot "pubspec.yaml"
}
if (-not $ReleaseDir) {
    $ReleaseDir = Join-Path $ProjectRoot "build\windows\x64\runner\Release"
}
if (-not $AipPath) {
    $AipPath = Join-Path $REPO_ROOT "installer\windows\hesabix.aip"
}
if (-not $OutDir) {
    $OutDir = Join-Path $REPO_ROOT "installer\windows\dist"
}

$AdvInst = Find-AdvancedInstallerCom -Explicit $AdvInstPath
$VERSION = Get-PubspecVersionName -Path $PubspecPath
$ASSET_NAME = "hesabix-windows.$VERSION.msi"
$EXE_PATH = Join-Path $ReleaseDir $ExeName

Write-Host ""
Write-Host "Advanced Installer: $AdvInst"
Write-Host "Version:            $VERSION"
Write-Host "Release dir:        $ReleaseDir"
Write-Host "AIP:                $AipPath"
Write-Host "Output MSI name:    $ASSET_NAME"
Write-Host ""

if (-not (Test-Path -LiteralPath $ReleaseDir)) {
    throw "Release folder not found: $ReleaseDir (run .\build_windows.ps1 -Mode release first)"
}
if (-not (Test-Path -LiteralPath $EXE_PATH)) {
    throw "Executable not found: $EXE_PATH"
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$aipDir = Split-Path -Parent $AipPath
New-Item -ItemType Directory -Force -Path $aipDir | Out-Null

$needNew = -not $SkipNewProject
if ($needNew -or -not (Test-Path -LiteralPath $AipPath)) {
    Write-Host "[step] Creating Advanced Installer project..." -ForegroundColor Cyan
    $code = Invoke-AdvInst -Exe $AdvInst -CliArgs @(
        "/newproject", $AipPath,
        "-type", "simple",
        "-lang", "en",
        "-overwrite"
    )
    if ($code -ne 0) { throw "Failed to create AIP (exit $code)" }
} else {
    Write-Host "[info] Reusing existing AIP: $AipPath" -ForegroundColor DarkGray
}

# Configure product metadata + package the Release folder.
$edits = @(
    @("/edit", $AipPath, "/SetVersion", $VERSION),
    @("/edit", $AipPath, "/SetProperty", "ProductName=$ProductName"),
    @("/edit", $AipPath, "/SetProperty", "Manufacturer=$Manufacturer"),
    @("/edit", $AipPath, "/SetPackageType", "x64"),
    @("/edit", $AipPath, "/SetAppdir", "-buildname", "DefaultBuild", "-path", "[ProgramFiles64Folder][Manufacturer]\[ProductName]"),
    @("/edit", $AipPath, "/SetShortcutdir", "-buildname", "DefaultBuild", "-path", "[ProgramMenuFolder][ProductName]"),
    # Sync Application Folder with Flutter Release output
    @("/edit", $AipPath, "/DelFolder", "APPDIR"),
    @("/edit", $AipPath, "/AddFolder", "APPDIR", $ReleaseDir),
    @("/edit", $AipPath, "/NewShortcut", "-name", $ProductName, "-dir", "SHORTCUTDIR", "-target", "APPDIR\$ExeName", "-wkdir", "APPDIR"),
    @("/edit", $AipPath, "/SetOutput", "-buildname", "DefaultBuild", "-path", $OutDir),
    @("/edit", $AipPath, "/SetPackageName", ($ASSET_NAME -replace '\.msi$', ''))
)

Write-Host "[step] Configuring AIP..." -ForegroundColor Cyan
foreach ($editArgs in $edits) {
    $code = Invoke-AdvInst -Exe $AdvInst -CliArgs $editArgs
    if ($code -ne 0) {
        Write-Host "[warn] Command returned ${code}: $($editArgs -join ' ')" -ForegroundColor Yellow
        # Some DelFolder/NewShortcut calls are best-effort on first create.
    }
}

Write-Host "[step] Building MSI..." -ForegroundColor Cyan
$code = Invoke-AdvInst -Exe $AdvInst -CliArgs @("/build", $AipPath)
if ($code -ne 0) { throw "Advanced Installer build failed (exit $code)" }

$msiPath = Join-Path $OutDir $ASSET_NAME
if (-not $DryRun) {
    if (-not (Test-Path -LiteralPath $msiPath)) {
        # AI may emit a slightly different name; pick newest MSI in OutDir.
        $fallback = Get-ChildItem -LiteralPath $OutDir -Filter "*.msi" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if ($fallback) {
            $dest = Join-Path $OutDir $ASSET_NAME
            if ($fallback.FullName -ne $dest) {
                Move-Item -LiteralPath $fallback.FullName -Destination $dest -Force
            }
            $msiPath = $dest
        }
    }
    if (-not (Test-Path -LiteralPath $msiPath)) {
        throw "MSI not found after build under $OutDir"
    }
    $sizeMb = [math]::Round(((Get-Item -LiteralPath $msiPath).Length / 1MB), 1)
    Write-Host ""
    Write-Host "MSI ready: $msiPath ($sizeMb MB)" -ForegroundColor Green
    Write-Host "Next: .\release_windows_forgejo.ps1" -ForegroundColor DarkGray
} else {
    Write-Host "[dry-run] Would build MSI to $msiPath" -ForegroundColor Yellow
}
