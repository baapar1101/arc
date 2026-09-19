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
    [string]$ProjectType = "professional",
    [string]$SignPfxPath = "",
    [string]$SignPfxPassword = "",
    [switch]$Sign,
    [switch]$SkipSign,
    [switch]$RequireSign,
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
  -ProjectType TYPE    Advanced Installer project type (default: professional)
  -Sign                Sign release binaries + MSI (default when cert env is set)
  -SkipSign            Do not sign (unsigned MSI; SmartScreen may block install)
  -RequireSign         Fail if no code-signing certificate is configured
  -SignPfxPath PATH    PFX file (or env WIN_CODESIGN_PFX)
  -SignPfxPassword PWD PFX password (or env WIN_CODESIGN_PASSWORD)
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

function Get-ShortcutIconPath {
    param(
        [string]$ReleaseDirectory,
        [string]$ExecutableName
    )
    $candidates = @(
        (Join-Path $ReleaseDirectory $ExecutableName),
        (Join-Path $ReleaseDirectory "data\flutter_assets\assets\app_icon.ico"),
        (Join-Path $ReleaseDirectory "app_icon.ico")
    )
    foreach ($path in $candidates) {
        if (Test-Path -LiteralPath $path) {
            return (Resolve-Path -LiteralPath $path).Path
        }
    }
    throw "No shortcut icon source found under $ReleaseDirectory"
}

function Repair-InstallerShortcutComponents {
    param(
        [string]$AipFile,
        [string]$ExecutableName = "hesabix_ui.exe"
    )
    if (-not (Test-Path -LiteralPath $AipFile)) { return }

    $lines = Get-Content -LiteralPath $AipFile -Encoding UTF8
    $changed = $false
    $fixed = foreach ($line in $lines) {
        if ($line -match '<ROW Shortcut=' -and $line -match ('Target="APPDIR\\' + [regex]::Escape($ExecutableName) + '"')) {
            $newLine = [regex]::Replace($line, 'Component_="[^"]*"', ('Component_="' + $ExecutableName + '"'))
            if ($newLine -ne $line) { $changed = $true }
            $newLine
        } else {
            $line
        }
    }
    if ($changed) {
        Set-Content -LiteralPath $AipFile -Value $fixed -Encoding UTF8
        Write-Host "[step] Repaired shortcut components -> $ExecutableName" -ForegroundColor Cyan
    } else {
        Write-Host "[warn] Could not repair shortcut components in $AipFile" -ForegroundColor Yellow
    }
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

function Resolve-FirstNonEmpty {
    param([string[]]$Values)
    foreach ($v in $Values) {
        if ($v -and $v.Trim()) { return $v.Trim() }
    }
    return ""
}

function Test-CodeSignConfigured {
    param(
        [string]$Pfx,
        [string]$Password
    )
    if ($Pfx -and (Test-Path -LiteralPath $Pfx)) { return $true }
    if (Resolve-FirstNonEmpty @($env:WIN_CODESIGN_THUMBPRINT)) { return $true }
    if (Resolve-FirstNonEmpty @($env:WIN_CODESIGN_SUBJECT)) { return $true }
    $defaultPfx = Join-Path $REPO_ROOT "installer\windows\codesign.pfx"
    if ((Test-Path -LiteralPath $defaultPfx) -and $Password) { return $true }
    return $false
}

function Invoke-WindowsCodeSign {
    param(
        [string[]]$Paths,
        [string]$Pfx,
        [string]$Password,
        [switch]$Verify
    )
    $signScript = Join-Path $REPO_ROOT "scripts\sign_windows_artifact.ps1"
    if (-not (Test-Path -LiteralPath $signScript)) {
        throw "Signing script not found: $signScript"
    }
    Write-Host "[step] Code signing: $($Paths -join ', ')" -ForegroundColor Cyan
    & $signScript -Path $Paths -PfxPath $Pfx -PfxPassword $Password $(if ($Verify) { '-Verify' }) $(if ($DryRun) { '-DryRun' })
    if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw "Code signing failed (exit $LASTEXITCODE)" }
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

$resolvedPfx = Resolve-FirstNonEmpty @(
    $SignPfxPath,
    $env:WIN_CODESIGN_PFX,
    $env:HESABIX_WIN_CODESIGN_PFX,
    (Join-Path $REPO_ROOT "installer\windows\codesign.pfx")
)
$resolvedPfxPassword = Resolve-FirstNonEmpty @(
    $SignPfxPassword,
    $env:WIN_CODESIGN_PASSWORD,
    $env:HESABIX_WIN_CODESIGN_PASSWORD
)
if ($resolvedPfx -and -not (Test-Path -LiteralPath $resolvedPfx)) {
    $resolvedPfx = ""
}
$signConfigured = Test-CodeSignConfigured -Pfx $resolvedPfx -Password $resolvedPfxPassword
$shouldSign = $false
if ($SkipSign) {
    $shouldSign = $false
} elseif ($Sign) {
    $shouldSign = $true
} elseif ($signConfigured) {
    $shouldSign = $true
}
if ($RequireSign -and -not $shouldSign) {
    throw "Code signing required (-RequireSign) but no certificate is configured. Set WIN_CODESIGN_PFX + WIN_CODESIGN_PASSWORD."
}
if ($shouldSign -and -not $signConfigured) {
    if ($RequireSign) {
        throw "Code signing required but no certificate found."
    }
    Write-Host "[warn] Signing requested but no certificate configured; continuing unsigned." -ForegroundColor Yellow
    $shouldSign = $false
}

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
        "-type", $ProjectType,
        "-lang", "en",
        "-overwrite"
    )
    if ($code -ne 0) { throw "Failed to create AIP (exit $code)" }
} else {
    Write-Host "[info] Reusing existing AIP: $AipPath" -ForegroundColor DarkGray
}

$msiPath = Join-Path $OutDir $ASSET_NAME
$shortcutIconPath = Get-ShortcutIconPath -ReleaseDirectory $ReleaseDir -ExecutableName $ExeName
$shortcutTarget = "APPDIR\$ExeName"

# Configure product metadata + package the Release folder.
$edits = @(
    @("/edit", $AipPath, "/SetVersion", $VERSION),
    @("/edit", $AipPath, "/SetProperty", "ProductName=$ProductName"),
    @("/edit", $AipPath, "/SetProperty", "Manufacturer=$Manufacturer"),
    @("/edit", $AipPath, "/SetAppdir", "-buildname", "DefaultBuild", "-path", "[ProgramFiles64Folder][Manufacturer]\[ProductName]"),
    @("/edit", $AipPath, "/SetShortcutdir", "-buildname", "DefaultBuild", "-path", "[ProgramMenuFolder][ProductName]"),
    # Sync Flutter Release output directly into APPDIR (no extra Release\ subfolder).
    # AddFolder would create APPDIR\Release\... and break shortcut targets.
    @("/edit", $AipPath, "/DelFolder", "APPDIR"),
    @("/edit", $AipPath, "/NewSync", "APPDIR", $ReleaseDir),
    # Start menu shortcut
    @("/edit", $AipPath, "/DelShortcut", "-name", $ProductName, "-dir", "SHORTCUTDIR"),
    @("/edit", $AipPath, "/NewShortcut", "-name", $ProductName, "-dir", "SHORTCUTDIR", "-target", $shortcutTarget, "-wkdir", "APPDIR", "-icon", $shortcutIconPath),
    # Desktop shortcut (Hesabix + app icon)
    @("/edit", $AipPath, "/DelShortcut", "-name", $ProductName, "-dir", "DesktopFolder"),
    @("/edit", $AipPath, "/NewShortcut", "-name", $ProductName, "-dir", "DesktopFolder", "-target", $shortcutTarget, "-wkdir", "APPDIR", "-icon", $shortcutIconPath),
    @("/edit", $AipPath, "/SetOutputLocation", "-buildname", "DefaultBuild", "-path", $OutDir),
    @("/edit", $AipPath, "/SetPackageName", $msiPath)
)

Write-Host "[step] Configuring AIP..." -ForegroundColor Cyan
foreach ($editArgs in $edits) {
    $code = Invoke-AdvInst -Exe $AdvInst -CliArgs $editArgs
    if ($code -ne 0) {
        Write-Host "[warn] Command returned ${code}: $($editArgs -join ' ')" -ForegroundColor Yellow
        # Some DelFolder/NewShortcut calls are best-effort on first create.
    }
}

Repair-InstallerShortcutComponents -AipFile $AipPath -ExecutableName $ExeName

if ($shouldSign) {
    Write-Host "[step] Signing Flutter release binaries before packaging..." -ForegroundColor Cyan
    Invoke-WindowsCodeSign -Paths @($ReleaseDir) -Pfx $resolvedPfx -Password $resolvedPfxPassword
}

Write-Host "[step] Building MSI..." -ForegroundColor Cyan
$code = Invoke-AdvInst -Exe $AdvInst -CliArgs @("/build", $AipPath)
if ($code -ne 0) { throw "Advanced Installer build failed (exit $code)" }

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
    if ($shouldSign) {
        Write-Host "[step] Signing MSI package..." -ForegroundColor Cyan
        Invoke-WindowsCodeSign -Paths @($msiPath) -Pfx $resolvedPfx -Password $resolvedPfxPassword -Verify
        $sig = Get-AuthenticodeSignature -LiteralPath $msiPath
        if ($sig.Status -eq "Valid") {
            Write-Host "[ok] MSI signature: Valid ($($sig.SignerCertificate.Subject))" -ForegroundColor Green
        } elseif ($sig.Status -eq "NotSigned") {
            Write-Host "[warn] MSI is still unsigned after signing step." -ForegroundColor Yellow
        } else {
            Write-Host "[warn] MSI signature status: $($sig.Status) - $($sig.StatusMessage)" -ForegroundColor Yellow
            Write-Host "       Use an OV/EV certificate from a public CA for SmartScreen trust." -ForegroundColor Yellow
        }
    } else {
        Write-Host ""
        Write-Host "[warn] MSI is UNSIGNED. Windows may block installation (SmartScreen / enterprise policy)." -ForegroundColor Yellow
        Write-Host "       Configure WIN_CODESIGN_PFX + WIN_CODESIGN_PASSWORD, then rebuild with signing enabled." -ForegroundColor Yellow
    }

    $sizeMb = [math]::Round(((Get-Item -LiteralPath $msiPath).Length / 1MB), 1)
    Write-Host ""
    Write-Host "MSI ready: $msiPath ($sizeMb MB)" -ForegroundColor Green
    Write-Host "Next: .\release_windows_forgejo.ps1" -ForegroundColor DarkGray
} else {
    Write-Host "[dry-run] Would build MSI to $msiPath" -ForegroundColor Yellow
}
