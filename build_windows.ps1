# Build script for Flutter Windows Desktop in this repo.
# Creates a standalone executable for Windows.
#
# Pub + engine artifact mirrors match deploy.sh set_flutter_mirror_env (Hesabix f.mirror).

param(
    [string]$Project = "",
    [ValidateSet("debug", "profile", "release")]
    [string]$Mode = "release",
    [string]$ApiBaseUrl = "https://hsxn.hesabix.ir",
    [string]$PubHostedUrl = "",
    [string]$FlutterStorageBaseUrl = "",
    [switch]$PreferEnvFlutterMirror,
    [switch]$Clean,
    [switch]$InstallDeps,
    [switch]$Help
)

$ErrorActionPreference = "Stop"

$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$REPO_ROOT = $SCRIPT_DIR

# Same URLs as deploy.sh set_flutter_mirror_env()
$HESABIX_PUB_HOSTED_URL = "https://f.mirror.hesabix.ir/pub"
$HESABIX_FLUTTER_STORAGE_BASE_URL = "https://f.mirror.hesabix.ir/gcs"

function Print-Usage {
    Write-Host "Usage: .\build_windows.ps1 [-Project <path>] [-Mode <debug|profile|release>] [-ApiBaseUrl <url>] [-PubHostedUrl <url>] [-FlutterStorageBaseUrl <url>] [-PreferEnvFlutterMirror] [-Clean] [-InstallDeps] [-Help]"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -Project PATH     Flutter project path (contains pubspec.yaml). If not specified, will be auto-detected."
    Write-Host "  -Mode MODE        Build type: debug, profile, or release (default: release)."
    Write-Host "  -ApiBaseUrl URL   API base URL (default: https://hsxn.hesabix.ir)."
    Write-Host "  -PubHostedUrl URL Override Pub mirror (default: deploy.sh Hesabix mirror)."
    Write-Host "  -FlutterStorageBaseUrl URL Override Flutter storage mirror (default: deploy.sh)."
    Write-Host "  -PreferEnvFlutterMirror   Keep existing env mirror vars when args do not override."
    Write-Host "  -Clean            Clean build directory before building."
    Write-Host "  -InstallDeps      Always run flutter pub get before building."
    Write-Host "  -Help             Show help."
    Write-Host ""
    Write-Host "Usage examples:"
    Write-Host "  .\build_windows.ps1"
    Write-Host "  .\build_windows.ps1 -Mode release -Clean"
    Write-Host "  .\build_windows.ps1 -Project hesabixUI\hesabix_ui"
    Write-Host "  .\build_windows.ps1 -ApiBaseUrl https://hsxn.hesabix.ir"
}

function Write-BuildGuide {
    Write-Host ""
    Write-Host "=== Flutter Windows build - quick guide ===" -ForegroundColor Cyan
    Write-Host "This script will:"
    Write-Host "  1) Verify Flutter is on PATH and Visual Studio C++ (MSVC) is available for desktop builds."
    Write-Host "  2) Allow Windows to create symlinks (Developer Mode or an elevated terminal)."
    Write-Host "  3) Run flutter pub get when dependencies look stale (use -InstallDeps to always refresh)."
    Write-Host "  4) Generate app icons (flutter_launcher_icons, including Windows .ico)."
    Write-Host "  5) Patch flutter_sound 9.29+ Windows CMake (upstream taudio target name bug)."
    Write-Host "  6) Run flutter build windows with your selected -Mode and -ApiBaseUrl."
    Write-Host "  7) Ensure DLLs and data/ are copied next to the .exe (CMake install + fallback staging)."
    Write-Host ""
    Write-Host "If something fails: run .\build_windows.ps1 -Help for all options; check IDE setup with: flutter doctor -v"
    Write-Host "===========================================" -ForegroundColor Cyan
    Write-Host ""
}

function Get-PubspecPackageName {
    param([string]$ProjectRoot)
    $pubspecPath = Join-Path $ProjectRoot "pubspec.yaml"
    $nameLine = Get-Content -LiteralPath $pubspecPath -ErrorAction Stop |
        Where-Object { $_ -match '^\s*name:\s*' } |
        Select-Object -First 1
    if (-not $nameLine) { return $null }
    if ($nameLine -match '^\s*name:\s*([^\s#]+)') {
        return $Matches[1].Trim().Trim(([char[]]@(34, 39)))
    }
    return $null
}

function Test-NeedsPubGet {
    param(
        [string]$ProjectRoot,
        [bool]$Force
    )
    if ($Force) { return $true }
    $pkgConfig = Join-Path $ProjectRoot ".dart_tool\package_config.json"
    if (-not (Test-Path -LiteralPath $pkgConfig)) { return $true }
    try {
        $pkgTime = (Get-Item -LiteralPath $pkgConfig).LastWriteTimeUtc
        $pubspecYaml = Join-Path $ProjectRoot "pubspec.yaml"
        if ((Get-Item -LiteralPath $pubspecYaml).LastWriteTimeUtc -gt $pkgTime) { return $true }
        $pubspecLock = Join-Path $ProjectRoot "pubspec.lock"
        if ((Test-Path -LiteralPath $pubspecLock) -and ((Get-Item -LiteralPath $pubspecLock).LastWriteTimeUtc -gt $pkgTime)) {
            return $true
        }
    } catch {
        return $true
    }
    return $false
}

# Flutter/Dart write mirror notices to stderr; PowerShell 7+ can treat that as a
# terminating error when $ErrorActionPreference is Stop. Only exit codes matter.
function Invoke-NativeCli {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Exe,
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$CliArgs
    )

    $restoreNative = $null
    if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue) {
        $restoreNative = $PSNativeCommandUseErrorActionPreference
        $PSNativeCommandUseErrorActionPreference = $false
    }

    $restoreEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        & $Exe @CliArgs 2>&1 | ForEach-Object {
            if ($_ -is [System.Management.Automation.ErrorRecord]) {
                Write-Host $_.ToString()
            } else {
                Write-Host $_
            }
        }
        return $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $restoreEap
        if ($null -ne $restoreNative) {
            $PSNativeCommandUseErrorActionPreference = $restoreNative
        }
    }
}

function Invoke-FlutterPubGet {
    Write-Host ""
    Write-Host "[step] Fetching Dart/Flutter dependencies (flutter pub get)..." -ForegroundColor Cyan
    Write-Host "       Hint: Uses PUB_HOSTED_URL / mirror env if set above." -ForegroundColor DarkGray
    $exitCode = Invoke-NativeCli -Exe "flutter" -CliArgs @("pub", "get")
    if ($exitCode -ne 0) {
        Write-Host "[error] flutter pub get failed. Check network, mirror URLs, and pubspec.yaml." -ForegroundColor Red
        exit 1
    }
}

function Invoke-FlutterLauncherIcons {
    Write-Host ""
    Write-Host "[step] Generating app icons (flutter_launcher_icons)..." -ForegroundColor Cyan
    $exitCode = Invoke-NativeCli -Exe "dart" -CliArgs @("run", "flutter_launcher_icons")
    if ($exitCode -ne 0) {
        Write-Host "[warn] flutter_launcher_icons failed; Windows may keep the default Flutter icon." -ForegroundColor Yellow
    }
}

function Get-WindowsBuildConfigName {
    param([string]$Mode)
    switch ($Mode) {
        "debug" { return "Debug" }
        "profile" { return "Profile" }
        default { return "Release" }
    }
}

if ($Help) {
    Print-Usage
    exit 0
}

Write-BuildGuide

# Check Flutter
$flutterCmd = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $flutterCmd) {
    Write-Host "[error] Flutter not found. Install Flutter and add it to PATH, then run 'flutter doctor'." -ForegroundColor Red
    exit 1
}

Write-Host "[step] Prerequisites: Flutter found at $($flutterCmd.Source)" -ForegroundColor Green
Write-Host "       Run 'flutter doctor -v' if desktop toolchains look wrong." -ForegroundColor DarkGray

# Check Visual Studio toolchain for Windows desktop builds
function Test-VisualStudioCppToolchain {
    $cl = Get-Command cl.exe -ErrorAction SilentlyContinue
    if ($cl) { return $true }

    $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path -LiteralPath $vswhere) {
        try {
            $installPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
            if ($installPath) { return $true }
        } catch {
        }
    }

    return $false
}

if (-not (Test-VisualStudioCppToolchain)) {
    Write-Host "[error] Unable to find a suitable Visual Studio C++ toolchain for Windows builds." -ForegroundColor Red
    Write-Host "Install Visual Studio 2022 (Community is fine) and select workload:" -ForegroundColor Yellow
    Write-Host "  - Desktop development with C++" -ForegroundColor Yellow
    Write-Host "Make sure Windows 10/11 SDK and MSVC v143 are included." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Download: https://visualstudio.microsoft.com/downloads/" -ForegroundColor Yellow
    Write-Host "After install, open a new terminal or run MSVC setup so cl.exe becomes available." -ForegroundColor Yellow
    exit 1
}

Write-Host "[step] Visual Studio C++ toolchain detected (PATH or vswhere)." -ForegroundColor Green

# Auto-detect project directory
$APP_DIR = $null

if ($Project) {
    $projPath = $Project
    if (-not [System.IO.Path]::IsPathRooted($projPath)) {
        $projPath = Join-Path $REPO_ROOT $projPath
    }
    $pubspecTest = Join-Path $projPath "pubspec.yaml"
    if (Test-Path -LiteralPath $pubspecTest) {
        $APP_DIR = $projPath
    } else {
        Write-Host "[error] Project path does not exist or does not contain pubspec.yaml: $Project" -ForegroundColor Red
        exit 1
    }
} else {
    $COMMON_PATH = Join-Path $REPO_ROOT "hesabixUI\hesabix_ui"
    if (Test-Path -LiteralPath (Join-Path $COMMON_PATH "pubspec.yaml")) {
        $APP_DIR = $COMMON_PATH
    } else {
        Write-Host "[error] Flutter project not found. Specify -Project pointing to the app folder." -ForegroundColor Red
        exit 1
    }
}

$APP_DIR = (Resolve-Path -LiteralPath $APP_DIR).Path

Write-Host ""
Write-Host "Repo root:       $REPO_ROOT"
Write-Host "Project path:    $APP_DIR"
Write-Host "Mode:            $Mode"
Write-Host "API Base URL:    $ApiBaseUrl"
Write-Host ""

Set-Location -LiteralPath $APP_DIR

# Mirror policy: matches deploy.sh (always Hesabix) unless overridden or -PreferEnvFlutterMirror.
if ($PubHostedUrl) {
    $env:PUB_HOSTED_URL = $PubHostedUrl
} elseif (-not $PreferEnvFlutterMirror) {
    $env:PUB_HOSTED_URL = $HESABIX_PUB_HOSTED_URL
} elseif (-not $env:PUB_HOSTED_URL) {
    $env:PUB_HOSTED_URL = $HESABIX_PUB_HOSTED_URL
}

if ($FlutterStorageBaseUrl) {
    $env:FLUTTER_STORAGE_BASE_URL = $FlutterStorageBaseUrl
} elseif (-not $PreferEnvFlutterMirror) {
    $env:FLUTTER_STORAGE_BASE_URL = $HESABIX_FLUTTER_STORAGE_BASE_URL
} elseif (-not $env:FLUTTER_STORAGE_BASE_URL) {
    $env:FLUTTER_STORAGE_BASE_URL = $HESABIX_FLUTTER_STORAGE_BASE_URL
}

Write-Host "[step] Flutter pub/storage mirrors (deploy.sh defaults unless overridden):" -ForegroundColor Cyan
Write-Host "       PUB_HOSTED_URL=$($env:PUB_HOSTED_URL)"
Write-Host "       FLUTTER_STORAGE_BASE_URL=$($env:FLUTTER_STORAGE_BASE_URL)"
Write-Host "       Override with env vars or -PubHostedUrl / -FlutterStorageBaseUrl if needed." -ForegroundColor DarkGray
Write-Host ""

# Symlink check (Windows build with plugins requires symlink support)
function Test-SymlinkSupport {
    try {
        $tmpDir = Join-Path $env:TEMP ("flutter_symlink_test_" + [guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $tmpDir | Out-Null
        $target = Join-Path $tmpDir "target.txt"
        $link = Join-Path $tmpDir "link.txt"
        Set-Content -Path $target -Value "ok" -Encoding ascii
        New-Item -ItemType SymbolicLink -Path $link -Target $target | Out-Null
        $ok = Test-Path -LiteralPath $link
        Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue
        return $ok
    } catch {
        return $false
    }
}

Write-Host "[step] Checking symlink support (required for many Flutter plugins)..." -ForegroundColor Cyan
if (-not (Test-SymlinkSupport)) {
    Write-Host "[error] Symlink support is not enabled. Flutter Windows builds often need symlink creation." -ForegroundColor Red
    Write-Host "Enable Windows Developer Mode: Settings -> System -> For developers -> Developer Mode" -ForegroundColor Yellow
    Write-Host "Or run this terminal as Administrator, then try again." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Opening Developer Mode settings..." -ForegroundColor Yellow
    try { Start-Process "ms-settings:developers" | Out-Null } catch { }
    exit 1
}
Write-Host "       Symlink check passed." -ForegroundColor Green

if (Test-NeedsPubGet -ProjectRoot $APP_DIR -Force:$InstallDeps) {
    Invoke-FlutterPubGet
} else {
    Write-Host "[info] Skipping flutter pub get (package_config.json is newer than pubspec.yaml / pubspec.lock)." -ForegroundColor DarkGray
    Write-Host "       Use -InstallDeps to always run flutter pub get before build." -ForegroundColor DarkGray
}

Invoke-FlutterLauncherIcons

$patchScript = Join-Path $APP_DIR "scripts\patch_flutter_sound_windows.ps1"
if (Test-Path -LiteralPath $patchScript) {
    & $patchScript -ProjectRoot $APP_DIR
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[error] flutter_sound Windows patch script failed." -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "[warn] Missing $patchScript - flutter_sound 9.29+ Windows builds may fail at CMake." -ForegroundColor Yellow
}

# Clean build directory if requested
if ($Clean) {
    Write-Host ""
    Write-Host "[step] Cleaning previous build (flutter clean)..." -ForegroundColor Cyan
    $cleanExit = Invoke-NativeCli -Exe "flutter" -CliArgs @("clean")
    if ($cleanExit -ne 0) {
        Write-Host "[error] flutter clean failed." -ForegroundColor Red
        exit 1
    }
    if (Test-Path -LiteralPath $patchScript) {
        & $patchScript -ProjectRoot $APP_DIR
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[error] flutter_sound Windows patch script failed after clean." -ForegroundColor Red
            exit 1
        }
    }
}

$packageName = Get-PubspecPackageName -ProjectRoot $APP_DIR
if (-not $packageName) {
    Write-Host "[warn] Could not read package name from pubspec.yaml; executable detection may fall back to any .exe under runner." -ForegroundColor Yellow
}

# Build flags
$buildFlags = @(
    "--$Mode",
    "--dart-define=API_BASE_URL=$ApiBaseUrl"
)

Write-Host ""
Write-Host "Build configuration:"
Write-Host "  Mode:           $Mode"
Write-Host "  API base URL:   $ApiBaseUrl"
Write-Host "  Expected EXE:   $(if ($packageName) { "$packageName.exe" } else { "(from pubspec name)" })"
Write-Host ""

Write-Host "=========================================="
Write-Host "Building Flutter for Windows..."
Write-Host "=========================================="
Write-Host "Command: flutter build windows $($buildFlags -join ' ')"
Write-Host ""

$buildExit = Invoke-NativeCli -Exe "flutter" -CliArgs (@("build", "windows") + $buildFlags)

if ($buildExit -ne 0) {
    Write-Host ""
    Write-Host "[error] Build failed." -ForegroundColor Red
    Write-Host "        Run: flutter doctor -v  ... and confirm Windows (desktop) is supported; fix MSVC or SDK warnings shown there." -ForegroundColor Yellow
    exit 1
}

$cmakeConfig = Get-WindowsBuildConfigName -Mode $Mode
$stageScript = Join-Path $APP_DIR "scripts\stage_windows_release.ps1"
if (Test-Path -LiteralPath $stageScript) {
    & $stageScript -ProjectRoot $APP_DIR -Config $cmakeConfig
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[error] Windows release staging failed." -ForegroundColor Red
        exit 1
    }
}

# Check output
$RUNNER_DIR = Join-Path $APP_DIR "build\windows\x64\runner"
$EXECUTABLE = $null

if (Test-Path -LiteralPath $RUNNER_DIR) {
    if ($packageName) {
        $match = Get-ChildItem -Path $RUNNER_DIR -Recurse -File -Filter "$packageName.exe" -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($match) { $EXECUTABLE = $match.FullName }
    }
    if (-not $EXECUTABLE) {
        $match = Get-ChildItem -Path $RUNNER_DIR -Recurse -File -Filter "*.exe" -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($match) { $EXECUTABLE = $match.FullName }
    }
}

if ($EXECUTABLE -and (Test-Path -LiteralPath $EXECUTABLE)) {
    Write-Host ""
    Write-Host "=========================================="
    Write-Host "Build completed successfully." -ForegroundColor Green
    Write-Host "=========================================="
    Write-Host ""
    Write-Host "Output:"
    Write-Host "  Executable:     $EXECUTABLE"
    Write-Host "  Output folder:  $(Split-Path -Parent $EXECUTABLE)"
    Write-Host ""
    $bundleDir = Split-Path -Parent $EXECUTABLE
    $bundleDllCount = @(Get-ChildItem -LiteralPath $bundleDir -Filter "*.dll" -ErrorAction SilentlyContinue).Count
    $hasData = Test-Path -LiteralPath (Join-Path $bundleDir "data\flutter_assets")
    Write-Host "  Bundle DLLs:    $bundleDllCount in output folder"
    Write-Host "  data/assets:    $(if ($hasData) { 'present' } else { 'MISSING - run with -Clean and rebuild' })"
    Write-Host ""
    Write-Host "Tip: Run hesabix_ui.exe from the folder above. Distribute the whole folder (exe + all DLLs + data/), not the .exe alone." -ForegroundColor DarkGray
    Write-Host ""
} else {
    Write-Host ""
    Write-Host "[warn] Could not locate the built executable under:" -ForegroundColor Yellow
    Write-Host "       $RUNNER_DIR" -ForegroundColor Yellow
    Write-Host '       The build finished without error; check build\windows\x64 for the actual output layout.' -ForegroundColor Yellow
    Write-Host ""
}
