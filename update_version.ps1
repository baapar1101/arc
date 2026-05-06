# Global version management script for the Flutter project (PowerShell)
# Updates version in pubspec.yaml; Flutter propagates it to all platforms
# (Android, iOS, Windows, Linux, macOS, Web)

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
    Write-Host "Usage: .\update_version.ps1 [options]"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -Project PATH      Path to Flutter project (default: $DEFAULT_PROJECT)"
    Write-Host "  -Set VERSION       Set semantic version manually (e.g. 1.0.23)"
    Write-Host "  -Build NUMBER      Set build number (e.g. 23)"
    Write-Host "  -SetFull VERSION   Set full version (e.g. 1.0.23+23)"
    Write-Host "  -Increment TYPE    Bump version (major|minor|patch|build)"
    Write-Host "  -Show              Show current version"
    Write-Host "  -Help              Show this help"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  # Show current version"
    Write-Host "  .\update_version.ps1 -Show"
    Write-Host ""
    Write-Host "  # Set version to 1.0.24"
    Write-Host "  .\update_version.ps1 -Set 1.0.24"
    Write-Host ""
    Write-Host "  # Set build number to 24"
    Write-Host "  .\update_version.ps1 -Build 24"
    Write-Host ""
    Write-Host "  # Set full version"
    Write-Host "  .\update_version.ps1 -SetFull 1.0.24+24"
    Write-Host ""
    Write-Host "  # Bump patch (1.0.23 -> 1.0.24)"
    Write-Host "  .\update_version.ps1 -Increment patch"
    Write-Host ""
    Write-Host "  # Bump minor (1.0.23 -> 1.1.0)"
    Write-Host "  .\update_version.ps1 -Increment minor"
    Write-Host ""
    Write-Host "  # Bump major (1.0.23 -> 2.0.0)"
    Write-Host "  .\update_version.ps1 -Increment major"
    Write-Host ""
    Write-Host "  # Bump build number (23 -> 24)"
    Write-Host "  .\update_version.ps1 -Increment build"
    Write-Host ""
    Write-Host "Note: Flutter propagates this version to all platforms:"
    Write-Host "  - Android: versionName and versionCode"
    Write-Host "  - iOS: CFBundleShortVersionString and CFBundleVersion"
    Write-Host "  - Windows: FLUTTER_VERSION_MAJOR, MINOR, PATCH, BUILD"
    Write-Host "  - Linux: from pubspec.yaml"
    Write-Host "  - macOS: CFBundleShortVersionString and CFBundleVersion"
    Write-Host "  - Web: from pubspec.yaml"
}

if ($Help) {
    Print-Usage
    exit 0
}

function Get-CurrentVersion {
    param([string]$PubspecFile)
    
    $versionLine = Get-Content $PubspecFile | Select-String -Pattern "^version:" | Select-Object -First 1
    if (-not $versionLine) {
        Write-Host "[ERROR] No version: line found in pubspec.yaml" -ForegroundColor Red
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
        Write-Host "[ERROR] Invalid version format: $VersionStr (expected MAJOR.MINOR.PATCH+BUILD)" -ForegroundColor Red
        exit 1
    }
}

function Update-VersionInPubspec {
    param(
        [string]$PubspecFile,
        [string]$NewVersion
    )
    
    # Backup
    $backupFile = "$PubspecFile.bak"
    Copy-Item $PubspecFile $backupFile
    
    try {
        # Replace version line
        $content = Get-Content $PubspecFile
        $content = $content -replace "^version:.*", "version: $NewVersion"
        $content | Set-Content $PubspecFile -Encoding UTF8
        
        # Verify
        $updated = Get-CurrentVersion $PubspecFile
        if ($updated -ne $NewVersion) {
            Copy-Item $backupFile $PubspecFile
            Write-Host "[ERROR] Failed to update version" -ForegroundColor Red
            exit 1
        }
        
        Remove-Item $backupFile -ErrorAction SilentlyContinue
        Write-Host "[INFO] Version updated: $NewVersion" -ForegroundColor Green
    } catch {
        Copy-Item $backupFile $PubspecFile
        Write-Host "[ERROR] Failed to update version: $_" -ForegroundColor Red
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
            Write-Host "[ERROR] Invalid increment type: $IncrementType (use: major, minor, patch, build)" -ForegroundColor Red
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
    Write-Host "Current application version:" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "  Full:  $versionStr"
    Write-Host "  Major: $($version.Major)"
    Write-Host "  Minor: $($version.Minor)"
    Write-Host "  Patch: $($version.Patch)"
    Write-Host "  Build: $($version.Build)"
    Write-Host ""
    Write-Host "This version is used on all platforms:" -ForegroundColor Yellow
    Write-Host "  OK Android: versionName=$($version.Major).$($version.Minor).$($version.Patch), versionCode=$($version.Build)"
    Write-Host "  OK iOS:     CFBundleShortVersionString=$($version.Major).$($version.Minor).$($version.Patch), CFBundleVersion=$($version.Build)"
    Write-Host "  OK Windows: FLUTTER_VERSION=$($version.Major).$($version.Minor).$($version.Patch), BUILD=$($version.Build)"
    Write-Host "  OK Linux:   from pubspec.yaml"
    Write-Host "  OK macOS:   CFBundleShortVersionString=$($version.Major).$($version.Minor).$($version.Patch), CFBundleVersion=$($version.Build)"
    Write-Host "  OK Web:     from pubspec.yaml"
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""
}

# Auto-detect project path
$APP_DIR = $null

if ($Project) {
    $pubspecPath = Join-Path $Project "pubspec.yaml"
    if (Test-Path $pubspecPath) {
        $APP_DIR = Resolve-Path $Project
    } else {
        Write-Host "[ERROR] Project path missing or pubspec.yaml not found: $Project" -ForegroundColor Red
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
        Write-Host "[ERROR] Flutter project not found. Specify path with -Project." -ForegroundColor Red
        exit 1
    }
}

$PUBSPEC_FILE = Join-Path $APP_DIR "pubspec.yaml"

if (-not (Test-Path $PUBSPEC_FILE)) {
    Write-Host "[ERROR] pubspec.yaml not found: $PUBSPEC_FILE" -ForegroundColor Red
    exit 1
}

$CURRENT_VERSION = Get-CurrentVersion $PUBSPEC_FILE
$CURRENT_VERSION_OBJ = Parse-Version $CURRENT_VERSION

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
            Write-Host "[ERROR] Invalid version format: $Set (expected MAJOR.MINOR.PATCH, e.g. 1.0.24)" -ForegroundColor Red
            exit 1
        }
        $NEW_VERSION = "$Set+$($CURRENT_VERSION_OBJ.Build)"
        Update-VersionInPubspec $PUBSPEC_FILE $NEW_VERSION
        Show-Version $APP_DIR
    }
    "build" {
        if ($Build -notmatch "^\d+$") {
            Write-Host "[ERROR] Build number must be numeric: $Build" -ForegroundColor Red
            exit 1
        }
        $NEW_VERSION = "$($CURRENT_VERSION_OBJ.Major).$($CURRENT_VERSION_OBJ.Minor).$($CURRENT_VERSION_OBJ.Patch)+$Build"
        Update-VersionInPubspec $PUBSPEC_FILE $NEW_VERSION
        Show-Version $APP_DIR
    }
    "set-full" {
        if ($SetFull -notmatch "^\d+\.\d+\.\d+\+\d+$") {
            Write-Host "[ERROR] Invalid version format: $SetFull (expected MAJOR.MINOR.PATCH+BUILD, e.g. 1.0.24+24)" -ForegroundColor Red
            exit 1
        }
        Update-VersionInPubspec $PUBSPEC_FILE $SetFull
        Show-Version $APP_DIR
    }
    "increment" {
        $NEW_VERSION = Increment-Version $CURRENT_VERSION $Increment
        Update-VersionInPubspec $PUBSPEC_FILE $NEW_VERSION
        Write-Host "[INFO] Version bumped from $CURRENT_VERSION to $NEW_VERSION" -ForegroundColor Green
        Show-Version $APP_DIR
    }
}

Write-Host ""
Write-Host "[INFO] Done successfully." -ForegroundColor Green
Write-Host "[INFO] Run build commands to propagate changes into binaries:" -ForegroundColor Yellow
Write-Host "  .\build_android.sh"
Write-Host "  .\build_windows.ps1"
Write-Host "  flutter build ios"
Write-Host "  flutter build linux"
Write-Host "  flutter build macos"
Write-Host "  flutter build web"
Write-Host ""


