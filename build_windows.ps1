# Build script for Flutter Windows Desktop in this repo.
# Creates a standalone executable for Windows.

param(
    [string]$Project = "",
    [ValidateSet("debug", "profile", "release")]
    [string]$Mode = "release",
    [string]$ApiBaseUrl = "https://hsxn.hesabix.ir",
    [string]$PubHostedUrl = "",
    [string]$FlutterStorageBaseUrl = "",
    [switch]$Clean,
    [switch]$InstallDeps,
    [switch]$Help
)

$ErrorActionPreference = "Stop"

$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$REPO_ROOT = $SCRIPT_DIR

function Print-Usage {
    Write-Host "Usage: .\build_windows.ps1 [-Project <path>] [-Mode <debug|profile|release>] [-ApiBaseUrl <url>] [-PubHostedUrl <url>] [-FlutterStorageBaseUrl <url>] [-Clean] [-InstallDeps] [-Help]"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -Project PATH     Flutter project path (contains pubspec.yaml). If not specified, will be auto-detected."
    Write-Host "  -Mode MODE        Build type: debug, profile, or release (default: release)."
    Write-Host "  -ApiBaseUrl URL   API base URL (default: https://hsxn.hesabix.ir)."
    Write-Host "  -PubHostedUrl URL Dart/Flutter pub mirror. If not set, will auto-default to Tsinghua mirror when env var not set."
    Write-Host "  -FlutterStorageBaseUrl URL Flutter storage mirror. If not set, will auto-default to Tsinghua mirror when env var not set."
    Write-Host "  -Clean            Clean build directory before building."
    Write-Host "  -InstallDeps      Install dependencies before building."
    Write-Host "  -Help             Show help."
    Write-Host ""
    Write-Host "Usage examples:"
    Write-Host "  .\build_windows.ps1"
    Write-Host "  .\build_windows.ps1 -Mode release -Clean"
    Write-Host "  .\build_windows.ps1 -Project hesabixUI\hesabix_ui"
    Write-Host "  .\build_windows.ps1 -ApiBaseUrl https://hsxn.hesabix.ir"
}

if ($Help) {
    Print-Usage
    exit 0
}

# Check Flutter
$flutterCmd = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $flutterCmd) {
    Write-Host "[error] Flutter not found. Please install it or configure PATH." -ForegroundColor Red
    exit 1
}

# Check Visual Studio toolchain for Windows desktop builds
function Test-VisualStudioCppToolchain {
    # Fast check: if cl.exe is available in PATH, we're good.
    $cl = Get-Command cl.exe -ErrorAction SilentlyContinue
    if ($cl) { return $true }

    # Try vswhere (available after installing Visual Studio Installer / VS)
    $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path $vswhere) {
        try {
            $installPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
            if ($installPath) { return $true }
        } catch { }
    }

    return $false
}

if (-not (Test-VisualStudioCppToolchain)) {
    Write-Host "[error] Unable to find suitable Visual Studio C++ toolchain for Windows builds." -ForegroundColor Red
    Write-Host "Install Visual Studio 2022 (Community is fine) and select workload:" -ForegroundColor Yellow
    Write-Host "  - Desktop development with C++" -ForegroundColor Yellow
    Write-Host "Make sure Windows 10/11 SDK and MSVC v143 are included." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Download: https://visualstudio.microsoft.com/downloads/" -ForegroundColor Yellow
    exit 1
}

# Auto-detect project directory
$APP_DIR = $null

if ($Project) {
    if (Test-Path (Join-Path $Project "pubspec.yaml")) {
        $APP_DIR = Resolve-Path $Project
    } else {
        Write-Host "[error] Project path does not exist or does not contain pubspec.yaml: $Project" -ForegroundColor Red
        exit 1
    }
} else {
    $COMMON_PATH = Join-Path $REPO_ROOT "hesabixUI\hesabix_ui"
    if (Test-Path (Join-Path $COMMON_PATH "pubspec.yaml")) {
        $APP_DIR = $COMMON_PATH
    } else {
        Write-Host "[error] Flutter project not found. Please specify path with -Project." -ForegroundColor Red
        exit 1
    }
}

Write-Host "Repo root: $REPO_ROOT"
Write-Host "Project path: $APP_DIR"
Write-Host "Mode: $Mode"
Write-Host "API Base URL: $ApiBaseUrl"
Write-Host ""

Set-Location $APP_DIR

# Configure mirrors (use provided args, else env vars, else sensible default for restricted networks)
if ($PubHostedUrl) { $env:PUB_HOSTED_URL = $PubHostedUrl }
if ($FlutterStorageBaseUrl) { $env:FLUTTER_STORAGE_BASE_URL = $FlutterStorageBaseUrl }

if (-not $env:PUB_HOSTED_URL) {
    $env:PUB_HOSTED_URL = "https://mirrors.tuna.tsinghua.edu.cn/dart-pub"
}
if (-not $env:FLUTTER_STORAGE_BASE_URL) {
    $env:FLUTTER_STORAGE_BASE_URL = "https://mirrors.tuna.tsinghua.edu.cn/flutter"
}

Write-Host "PUB_HOSTED_URL: $($env:PUB_HOSTED_URL)"
Write-Host "FLUTTER_STORAGE_BASE_URL: $($env:FLUTTER_STORAGE_BASE_URL)"
Write-Host ""

# Symlink check (Windows build with plugins requires symlink support)
function Test-SymlinkSupport {
    try {
        $tmpDir = Join-Path $env:TEMP ("flutter_symlink_test_" + [guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $tmpDir | Out-Null
        $target = Join-Path $tmpDir "target.txt"
        $link = Join-Path $tmpDir "link.txt"
        Set-Content -Path $target -Value "ok" -Encoding Ascii
        New-Item -ItemType SymbolicLink -Path $link -Target $target | Out-Null
        $ok = (Test-Path $link)
        Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue
        return $ok
    } catch {
        return $false
    }
}

if (-not (Test-SymlinkSupport)) {
    Write-Host "[error] Symlink support is not enabled. Flutter Windows build with plugins requires symlink support." -ForegroundColor Red
    Write-Host "Enable Windows Developer Mode: Settings -> System -> For developers -> Developer Mode" -ForegroundColor Yellow
    Write-Host "Or run the terminal as Administrator." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Opening Developer Mode settings..." -ForegroundColor Yellow
    try { Start-Process "ms-settings:developers" | Out-Null } catch {}
    exit 1
}

# Install dependencies if requested
if ($InstallDeps) {
    Write-Host "Installing dependencies..."
    flutter pub get
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[error] Error downloading dependencies. Please check internet connection." -ForegroundColor Red
        exit 1
    }
} else {
    $dartToolExists = Test-Path ".dart_tool"
    $pubspecLockExists = Test-Path "pubspec.lock"
    if (-not $dartToolExists -and -not $pubspecLockExists) {
        Write-Host "Dependencies not installed. Installing..."
        flutter pub get
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[warn] Error downloading dependencies. Trying to continue..." -ForegroundColor Yellow
        }
    }
}

# Clean build directory if requested
if ($Clean) {
    Write-Host "Cleaning build directory..."
    flutter clean
}

# Build flags
$buildFlags = @(
    "--$Mode",
    "--dart-define=API_BASE_URL=$ApiBaseUrl"
)

Write-Host ""
Write-Host "Build Configuration:"
Write-Host "  Mode: $Mode"
Write-Host "  API Base URL: $ApiBaseUrl"
Write-Host ""

Write-Host "=========================================="
Write-Host "Building Flutter for Windows..."
Write-Host "=========================================="
Write-Host "Command: flutter build windows $($buildFlags -join ' ')"
Write-Host ""

flutter build windows $buildFlags

if ($LASTEXITCODE -ne 0) {
    Write-Host "[error] Build failed!" -ForegroundColor Red
    exit 1
}

# Check output
$RUNNER_DIR = Join-Path $APP_DIR "build\windows\x64\runner"
$EXECUTABLE = $null

if (Test-Path $RUNNER_DIR) {
    $EXECUTABLE = (Get-ChildItem -Path $RUNNER_DIR -Recurse -File -Filter "hesabix_ui.exe" -ErrorAction SilentlyContinue | Select-Object -First 1)?.FullName
}

if ($EXECUTABLE -and (Test-Path $EXECUTABLE)) {
    Write-Host ""
    Write-Host "=========================================="
    Write-Host "✓ Build completed successfully!" -ForegroundColor Green
    Write-Host "=========================================="
    Write-Host ""
    Write-Host "Build Configuration:"
    Write-Host "  Mode: $Mode"
    Write-Host "  API Base URL: $ApiBaseUrl"
    Write-Host ""
    Write-Host "Executable file:"
    Write-Host "  $EXECUTABLE"
    Write-Host ""
    Write-Host "Build outputs are located at:"
    Write-Host "  $(Split-Path -Parent $EXECUTABLE)"
    Write-Host ""
} else {
    Write-Host "[warn] Executable file not found under: $RUNNER_DIR" -ForegroundColor Yellow
    Write-Host "Build may have completed but executable was not found."
}


