#Requires -Version 5.0
<#
.SYNOPSIS
  Builds Holoo2Hesabix (Release) and creates the Advanced Installer setup package
  with a Desktop shortcut and Start Menu shortcut.
#>
[CmdletBinding()]
param(
    [switch]$SkipAppBuild,
    [switch]$SkipProjectCreate
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$InstallerDir = $PSScriptRoot
$AipPath = Join-Path $InstallerDir "Holoo2Hesabix.aip"
$OutputDir = Join-Path $InstallerDir "output"
$ReleaseDir = Join-Path $Root "bin\Release"
$IconPath = Join-Path $Root "icon.ico"
$ShortcutDesc = "Holoo to Hesabix data migration"

$AiCandidates = @(
    "${env:ProgramFiles(x86)}\Caphyon\Advanced Installer 23.1\bin\x86\AdvancedInstaller.com",
    "${env:ProgramFiles(x86)}\Caphyon\Advanced Installer 23.1\bin\x64\AdvancedInstaller.com"
) + @(
    Get-ChildItem "${env:ProgramFiles(x86)}\Caphyon" -Filter "AdvancedInstaller.com" -Recurse -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty FullName
)

$Ai = $AiCandidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $Ai) {
    throw "Advanced Installer not found. Install Advanced Installer and retry."
}

Write-Host "Using Advanced Installer: $Ai"

function Invoke-AiEdit {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)
    & $Ai /edit $AipPath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw ("AdvancedInstaller /edit failed ({0}): {1}" -f $LASTEXITCODE, ($Arguments -join ' '))
    }
}

if (-not $SkipAppBuild) {
    $MsBuild = @(
        "${env:ProgramFiles(x86)}\MSBuild\14.0\Bin\MSBuild.exe",
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2019\BuildTools\MSBuild\Current\Bin\MSBuild.exe",
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2019\Community\MSBuild\Current\Bin\MSBuild.exe",
        "${env:ProgramFiles}\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe",
        "${env:ProgramFiles}\Microsoft Visual Studio\2022\Professional\MSBuild\Current\Bin\MSBuild.exe",
        "${env:ProgramFiles}\Microsoft Visual Studio\2022\Enterprise\MSBuild\Current\Bin\MSBuild.exe"
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1

    if (-not $MsBuild) {
        throw "MSBuild not found."
    }

    Write-Host "Building Release with: $MsBuild"
    & $MsBuild (Join-Path $Root "Holoo2Hesabix.vbproj") /p:Configuration=Release /p:Platform=AnyCPU /v:minimal
    if ($LASTEXITCODE -ne 0) { throw "MSBuild failed with exit code $LASTEXITCODE" }
}

$RequiredFiles = @(
    "Holoo2Hesabix.exe",
    "Holoo2Hesabix.exe.config",
    "Newtonsoft.Json.dll",
    "icon.ico"
)
foreach ($f in $RequiredFiles) {
    $p = Join-Path $ReleaseDir $f
    if (-not (Test-Path $p)) { throw "Missing release file: $p" }
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

if (-not $SkipProjectCreate -or -not (Test-Path $AipPath)) {
    Write-Host "Creating Advanced Installer project..."
    & $Ai /newproject $AipPath -overwrite
    if ($LASTEXITCODE -ne 0) { throw "Failed to create AIP project (exit $LASTEXITCODE)" }

    Write-Host "Configuring product..."
    Invoke-AiEdit /SetProperty, "ProductName=Holoo2Hesabix"
    Invoke-AiEdit /SetProperty, "Manufacturer=Hesabix"
    Invoke-AiEdit /SetVersion, "1.1.0"
    Invoke-AiEdit /SetIcon, "-icon", $IconPath
    Invoke-AiEdit /SetAppdir, "-buildname", "DefaultBuild", "-path", "[ProgramFilesFolder][Manufacturer]\[ProductName]"
    Invoke-AiEdit /SetShortcutdir, "-buildname", "DefaultBuild", "-path", "[ProgramMenuFolder][ProductName]"
    Invoke-AiEdit /SetOutputLocation, "-buildname", "DefaultBuild", "-path", $OutputDir
    Invoke-AiEdit /SetPackageName, "Holoo2Hesabix-Setup.msi", "-buildname", "DefaultBuild"
    Invoke-AiEdit /SetDotNetFrameworkLc, "-buildname", "DefaultBuild", "-version", "4.6.1"

    Write-Host "Adding application files..."
    Invoke-AiEdit /AddFile, "APPDIR", (Join-Path $ReleaseDir "Holoo2Hesabix.exe")
    Invoke-AiEdit /AddFile, "APPDIR", (Join-Path $ReleaseDir "Holoo2Hesabix.exe.config")
    Invoke-AiEdit /AddFile, "APPDIR", (Join-Path $ReleaseDir "Newtonsoft.Json.dll")
    Invoke-AiEdit /AddFile, "APPDIR", (Join-Path $ReleaseDir "icon.ico")

    Write-Host "Creating Desktop and Start Menu shortcuts..."
    Invoke-AiEdit /NewShortcut, "-name", "Holoo2Hesabix", "-dir", "DesktopFolder", `
        "-target", "APPDIR\Holoo2Hesabix.exe", "-wkdir", "APPDIR", `
        "-desc", $ShortcutDesc, "-icon", $IconPath
    Invoke-AiEdit /NewShortcut, "-name", "Holoo2Hesabix", "-dir", "SHORTCUTDIR", `
        "-target", "APPDIR\Holoo2Hesabix.exe", "-wkdir", "APPDIR", `
        "-desc", $ShortcutDesc, "-icon", $IconPath
}
else {
    Write-Host "Refreshing file sources from Release build..."
    Invoke-AiEdit /SetVersion, "1.1.0"
    Invoke-AiEdit /UpdateFile, "APPDIR\Holoo2Hesabix.exe", (Join-Path $ReleaseDir "Holoo2Hesabix.exe")
    Invoke-AiEdit /UpdateFile, "APPDIR\Holoo2Hesabix.exe.config", (Join-Path $ReleaseDir "Holoo2Hesabix.exe.config")
    Invoke-AiEdit /UpdateFile, "APPDIR\Newtonsoft.Json.dll", (Join-Path $ReleaseDir "Newtonsoft.Json.dll")
    Invoke-AiEdit /UpdateFile, "APPDIR\icon.ico", (Join-Path $ReleaseDir "icon.ico")
}

Write-Host "Building installer package..."
& $Ai /rebuild $AipPath
if ($LASTEXITCODE -ne 0) { throw "Installer build failed (exit $LASTEXITCODE)" }

$Built = @(Get-ChildItem -Path $OutputDir -Recurse -Include *.msi,*.exe -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending)
if ($Built.Count -eq 0) {
    $Built = @(Get-ChildItem -Path $InstallerDir -Recurse -Include *.msi,*.exe -ErrorAction SilentlyContinue |
        Where-Object { $_.DirectoryName -notmatch '[\\/]bin[\\/]' } |
        Sort-Object LastWriteTime -Descending)
}

Write-Host ""
Write-Host "Done. Installer output:"
foreach ($item in $Built) {
    Write-Host ("  {0}  ({1:N0} bytes)" -f $item.FullName, $item.Length)
}
