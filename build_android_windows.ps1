# Build script for Flutter Android on Windows in this repo.
# Creates Android App Bundle (AAB) and APK files.
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
    [switch]$BuildAab,
    [switch]$NoAab,
    [switch]$BuildApk,
    [switch]$NoApk,
    [switch]$UniversalApk,
    [switch]$SplitApk,
    [switch]$NoSplitApk,
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

$buildAabEnabled = $true
$buildApkEnabled = $true
$buildUniversalApkEnabled = $false
$buildSplitApkEnabled = $true

if ($BuildAab) { $buildAabEnabled = $true }
if ($NoAab) { $buildAabEnabled = $false }
if ($BuildApk) { $buildApkEnabled = $true }
if ($NoApk) { $buildApkEnabled = $false }
if ($UniversalApk) { $buildUniversalApkEnabled = $true }
if ($SplitApk) { $buildSplitApkEnabled = $true }
if ($NoSplitApk) { $buildSplitApkEnabled = $false }

function Print-Usage {
    Write-Host "Usage: .\build_android_windows.ps1 [-Project <path>] [-Mode <debug|profile|release>] [-ApiBaseUrl <url>] [-PreferEnvFlutterMirror] [-BuildAab] [-NoAab] [-BuildApk] [-NoApk] [-UniversalApk] [-SplitApk] [-NoSplitApk] [-Clean] [-InstallDeps] [-Help]"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -Project PATH             Flutter project path (contains pubspec.yaml). If not specified, will be auto-detected."
    Write-Host "  -Mode MODE                Build type: debug, profile, or release (default: release)."
    Write-Host "  -ApiBaseUrl URL           API base URL (default: https://hsxn.hesabix.ir)."
    Write-Host "  -BuildAab / -NoAab        Enable/disable Android App Bundle build (default: enabled)."
    Write-Host "  -BuildApk / -NoApk        Enable/disable APK build (default: enabled)."
    Write-Host "  -UniversalApk             Build universal APK (all ABIs, default: disabled)."
    Write-Host "  -SplitApk / -NoSplitApk   Enable/disable split APKs per ABI (default: enabled)."
    Write-Host "  -PubHostedUrl URL         Override Pub mirror (default: deploy.sh Hesabix mirror)."
    Write-Host "  -FlutterStorageBaseUrl URL Override Flutter storage mirror (default: deploy.sh)."
    Write-Host "  -PreferEnvFlutterMirror   If set, keep existing PUB_HOSTED_URL / FLUTTER_STORAGE_BASE_URL when not overridden by args."
    Write-Host "  -Clean                    Clean build directory before building."
    Write-Host "  -InstallDeps              Always run flutter pub get before building."
    Write-Host "  -Help                     Show help."
    Write-Host ""
    Write-Host "Usage examples:"
    Write-Host "  .\build_android_windows.ps1"
    Write-Host "  .\build_android_windows.ps1 -Mode release -Clean"
    Write-Host "  .\build_android_windows.ps1 -Project hesabixUI\hesabix_ui -NoAab -UniversalApk"
    Write-Host "  .\build_android_windows.ps1 -ApiBaseUrl https://hsxn.hesabix.ir"
}

function Write-BuildGuide {
    Write-Host ""
    Write-Host "=== Flutter Android build on Windows - quick guide ===" -ForegroundColor Cyan
    Write-Host "This script will:"
    Write-Host "  1) Verify Flutter is on PATH."
    Write-Host "  2) Verify Android SDK and Java are available."
    Write-Host "  3) Set pub + Flutter storage mirrors like deploy.sh (unless -PreferEnvFlutterMirror or explicit mirror args)."
    Write-Host "  4) Run flutter pub get when dependencies look stale (use -InstallDeps to always refresh)."
    Write-Host "  5) Build AAB/APK based on selected flags."
    Write-Host ""
    Write-Host "If something fails: run .\build_android_windows.ps1 -Help; check setup with: flutter doctor -v"
    Write-Host "=======================================================" -ForegroundColor Cyan
    Write-Host ""
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

function Invoke-FlutterPubGet {
    Write-Host ""
    Write-Host "[step] Fetching Dart/Flutter dependencies (flutter pub get)..." -ForegroundColor Cyan
    flutter pub get
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[error] flutter pub get failed. Check network, mirror URLs, and pubspec.yaml." -ForegroundColor Red
        exit 1
    }
}

function Get-ResolvedAndroidSdkPath {
    $candidatePaths = @()
    if ($env:ANDROID_SDK_ROOT) { $candidatePaths += $env:ANDROID_SDK_ROOT }
    if ($env:ANDROID_HOME) { $candidatePaths += $env:ANDROID_HOME }
    if ($env:LOCALAPPDATA) { $candidatePaths += (Join-Path $env:LOCALAPPDATA "Android\Sdk") }

    foreach ($candidate in $candidatePaths) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    return $null
}

function Test-JavaAvailability {
    if ($env:JAVA_HOME) {
        $javaExe = Join-Path $env:JAVA_HOME "bin\java.exe"
        if (Test-Path -LiteralPath $javaExe) { return $true }
    }
    $javaCmd = Get-Command java -ErrorAction SilentlyContinue
    return ($null -ne $javaCmd)
}

function Invoke-UnblockAndroidTree {
    param([string]$ProjectRoot)
    $androidRoot = Join-Path $ProjectRoot "android"
    if (-not (Test-Path -LiteralPath $androidRoot)) { return }
    try {
        Get-ChildItem -LiteralPath $androidRoot -Recurse -Force -ErrorAction SilentlyContinue |
            ForEach-Object { Unblock-File -LiteralPath $_.FullName -ErrorAction SilentlyContinue }
    } catch {
        # Ignore unblock failures (restricted dirs etc.).
    }
}

function Get-HesabixGradleMirrorFromGradleProperties {
    param([string]$AndroidDir)
    $gp = Join-Path $AndroidDir "gradle.properties"
    if (-not (Test-Path -LiteralPath $gp)) { return $null }
    foreach ($line in Get-Content -LiteralPath $gp -ErrorAction SilentlyContinue) {
        $t = $line.Trim()
        if ($t.Length -eq 0 -or $t.StartsWith("#")) { continue }
        if ($t -match '^\s*hesabix\.gradle\.mirror\s*=\s*(.+)\s*$') {
            return $Matches[1].Trim().Trim('"')
        }
    }
    return $null
}

function Get-AndroidNdkVersionFromGradleProps {
    param([string]$AndroidDir)
    $gp = Join-Path $AndroidDir "gradle.properties"
    if (-not (Test-Path -LiteralPath $gp)) { return "26.1.10909125" }
    foreach ($line in Get-Content -LiteralPath $gp -ErrorAction SilentlyContinue) {
        $t = $line.Trim()
        if ($t.Length -eq 0 -or $t.StartsWith("#")) { continue }
        if ($t -match '^\s*android\.ndkVersion\s*=\s*(.+)\s*$') {
            return $Matches[1].Trim().Trim('"')
        }
    }
    return "26.1.10909125"
}

function Write-AndroidNdkPreflight {
    param(
        [string]$SdkRoot,
        [string]$AndroidDir
    )
    $ndkVer = Get-AndroidNdkVersionFromGradleProps -AndroidDir $AndroidDir
    $expected = Join-Path $SdkRoot "ndk\$ndkVer"
    $props = Join-Path $expected "source.properties"
    if (-not (Test-Path -LiteralPath $props)) {
        Write-Host "[warn] Pinned NDK (android.ndkVersion=$ndkVer) is missing or incomplete at:" -ForegroundColor Yellow
        Write-Host "       $expected" -ForegroundColor Yellow
        Write-Host "       Example: sdkmanager `"ndk;$ndkVer`"   (from cmdline-tools\\latest\\bin)" -ForegroundColor DarkGray
    }
    $ndkRoot = Join-Path $SdkRoot "ndk"
    if (-not (Test-Path -LiteralPath $ndkRoot)) { return }
    Get-ChildItem -LiteralPath $ndkRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $sp = Join-Path $_.FullName "source.properties"
        if (-not (Test-Path -LiteralPath $sp)) {
            Write-Host "[warn] NDK folder without source.properties (often breaks AGP with CXX1101). Remove and reinstall if you do not need it:" -ForegroundColor Yellow
            Write-Host "       $($_.FullName)" -ForegroundColor Yellow
        }
    }
}

function Resolve-AppDir {
    param(
        [string]$ProjectArg
    )

    if ($ProjectArg) {
        $projPath = $ProjectArg
        if (-not [System.IO.Path]::IsPathRooted($projPath)) {
            $projPath = Join-Path $REPO_ROOT $projPath
        }
        if (Test-Path -LiteralPath (Join-Path $projPath "pubspec.yaml")) {
            return (Resolve-Path -LiteralPath $projPath).Path
        }
        Write-Host "[error] Project path does not exist or does not contain pubspec.yaml: $ProjectArg" -ForegroundColor Red
        exit 1
    }

    $commonPath = Join-Path $REPO_ROOT "hesabixUI\hesabix_ui"
    if (Test-Path -LiteralPath (Join-Path $commonPath "pubspec.yaml")) {
        return (Resolve-Path -LiteralPath $commonPath).Path
    }

    Write-Host "[error] Flutter project not found. Specify -Project pointing to the app folder." -ForegroundColor Red
    exit 1
}

if ($Help) {
    Print-Usage
    exit 0
}

Write-BuildGuide

$flutterCmd = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $flutterCmd) {
    Write-Host "[error] Flutter not found. Install Flutter and add it to PATH, then run 'flutter doctor'." -ForegroundColor Red
    exit 1
}
Write-Host "[step] Flutter found at $($flutterCmd.Source)" -ForegroundColor Green

$androidSdkPath = Get-ResolvedAndroidSdkPath
if (-not $androidSdkPath) {
    Write-Host "[error] Android SDK not found." -ForegroundColor Red
    Write-Host "Set ANDROID_SDK_ROOT (or ANDROID_HOME), or install Android SDK to default path: %LOCALAPPDATA%\Android\Sdk" -ForegroundColor Yellow
    exit 1
}

$env:ANDROID_SDK_ROOT = $androidSdkPath
$env:ANDROID_HOME = $androidSdkPath

$platformTools = Join-Path $androidSdkPath "platform-tools"
$cmdlineTools = Join-Path $androidSdkPath "cmdline-tools\latest\bin"
$buildToolsRoot = Join-Path $androidSdkPath "build-tools"
$env:Path = "$platformTools;$cmdlineTools;$env:Path"

if (-not (Test-Path -LiteralPath $platformTools)) {
    Write-Host "[warn] Android platform-tools not found at $platformTools" -ForegroundColor Yellow
}
if (-not (Test-Path -LiteralPath $buildToolsRoot)) {
    Write-Host "[warn] Android build-tools folder not found at $buildToolsRoot" -ForegroundColor Yellow
}

if (-not (Test-JavaAvailability)) {
    Write-Host "[error] Java not found. Install Java 17+ and set JAVA_HOME (or add java to PATH)." -ForegroundColor Red
    exit 1
}

Write-Host "[step] Android SDK: $androidSdkPath" -ForegroundColor Green
Write-Host "[step] Java detected." -ForegroundColor Green

$APP_DIR = Resolve-AppDir -ProjectArg $Project
Set-Location -LiteralPath $APP_DIR

# Mirror policy: matches deploy.sh (always Hesabix) unless explicitly overridden or -PreferEnvFlutterMirror.
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

Write-Host "[step] Flutter pub/storage mirrors (deploy.sh Hesabix defaults unless overridden):" -ForegroundColor Cyan

Write-Host ""
Write-Host "Repo root:             $REPO_ROOT"
Write-Host "Project path:          $APP_DIR"
Write-Host "Mode:                  $Mode"
Write-Host "API Base URL:          $ApiBaseUrl"
Write-Host "Build AAB:             $buildAabEnabled"
Write-Host "Build APK:             $buildApkEnabled"
Write-Host "Universal APK:         $buildUniversalApkEnabled"
Write-Host "Split APK:             $buildSplitApkEnabled"
Write-Host "PUB_HOSTED_URL:        $($env:PUB_HOSTED_URL)"
Write-Host "FLUTTER_STORAGE_BASE_URL: $($env:FLUTTER_STORAGE_BASE_URL)"
Write-Host ""

if (Test-NeedsPubGet -ProjectRoot $APP_DIR -Force:$InstallDeps) {
    Invoke-FlutterPubGet
} else {
    Write-Host "[info] Skipping flutter pub get (dependencies look up-to-date)." -ForegroundColor DarkGray
}

if ($Clean) {
    Write-Host ""
    Write-Host "[step] Cleaning previous build (flutter clean)..." -ForegroundColor Cyan
    flutter clean
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[error] flutter clean failed." -ForegroundColor Red
        exit 1
    }
}

if (($Mode -eq "release") -and (-not (Test-Path -LiteralPath (Join-Path $APP_DIR "android\keystore.properties")))) {
    Write-Host "[warn] keystore.properties not found. Release build may use debug signing." -ForegroundColor Yellow
}

$androidGradleRoot = Join-Path $APP_DIR "android"
if (-not (Test-Path -LiteralPath (Join-Path $androidGradleRoot "gradlew.bat"))) {
    Write-Host "[error] android\gradlew.bat missing under project root." -ForegroundColor Red
    Write-Host "        Flutter Gradle expects wrapper scripts here (often restored via):" -ForegroundColor Yellow
    Write-Host '          flutter pub get  …then Android Gradle regenerate:' -ForegroundColor Yellow
    Write-Host ('          cd "{0}"' -f $APP_DIR) -ForegroundColor Yellow
    Write-Host '          flutter create . --platforms=android' -ForegroundColor Yellow
    exit 1
}

Write-Host "[step] Unblocking Zone.Identifier on android\ (reduces some Permission denied cases on Windows)..." -ForegroundColor DarkGray
Invoke-UnblockAndroidTree -ProjectRoot $APP_DIR

$gradleMirrorFromProps = Get-HesabixGradleMirrorFromGradleProperties -AndroidDir $androidGradleRoot
if ($gradleMirrorFromProps) {
    $env:HESABIX_GRADLE_MIRROR = $gradleMirrorFromProps
    Write-Host "[step] HESABIX_GRADLE_MIRROR from android\gradle.properties: $gradleMirrorFromProps" -ForegroundColor DarkGray
} elseif ($env:HESABIX_GRADLE_MIRROR) {
    Write-Host "[step] HESABIX_GRADLE_MIRROR (already set in env): $($env:HESABIX_GRADLE_MIRROR)" -ForegroundColor DarkGray
}

Write-AndroidNdkPreflight -SdkRoot $androidSdkPath -AndroidDir $androidGradleRoot

try {
    $gradleUserHome = $env:GRADLE_USER_HOME
    if (-not $gradleUserHome) { $gradleUserHome = Join-Path $env:USERPROFILE ".gradle" }
    if (-not (Test-Path -LiteralPath $gradleUserHome)) {
        New-Item -ItemType Directory -Path $gradleUserHome -Force | Out-Null
    }
    $probe = Join-Path $gradleUserHome ".hesabix_gradle_write_probe"
    Set-Content -LiteralPath $probe -Value "" -Encoding ascii -ErrorAction Stop
    Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
} catch {
    Write-Host "[warn] Cannot write to GRADLE_USER_HOME ($($env:USERPROFILE)\.gradle). Gradle may fail with 'Permission denied'. Fix folder ACLs or disk space." -ForegroundColor Yellow
}

$commonBuildFlags = @(
    "--$Mode",
    "--android-skip-build-dependency-validation",
    "--dart-define=API_BASE_URL=$ApiBaseUrl"
)

if ($buildAabEnabled) {
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "Building Android App Bundle (AAB)..."
    Write-Host "==========================================" -ForegroundColor Cyan
    flutter build appbundle @commonBuildFlags
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[warn] Failed to build AAB." -ForegroundColor Yellow
        Write-Host "       If you saw 'Gradle does not have execution permission': Flutter shows that when Gradle output contains 'Permission denied' (not only gradlew). Run: flutter build appbundle $($commonBuildFlags -join ' ') -v" -ForegroundColor DarkGray
    } else {
        Write-Host "[ok] AAB build completed." -ForegroundColor Green
    }
}

if ($buildApkEnabled) {
    if ($buildUniversalApkEnabled) {
        Write-Host ""
        Write-Host "==========================================" -ForegroundColor Cyan
        Write-Host "Building Universal APK..."
        Write-Host "==========================================" -ForegroundColor Cyan
        flutter build apk @commonBuildFlags
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[warn] Failed to build universal APK." -ForegroundColor Yellow
        } else {
            Write-Host "[ok] Universal APK build completed." -ForegroundColor Green
        }
    }

    if ($buildSplitApkEnabled) {
        Write-Host ""
        Write-Host "==========================================" -ForegroundColor Cyan
        Write-Host "Building Split APKs (per ABI)..."
        Write-Host "==========================================" -ForegroundColor Cyan
        $splitFlags = $commonBuildFlags + @("--split-per-abi")
        flutter build apk @splitFlags
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[warn] Failed to build split APKs." -ForegroundColor Yellow
        } else {
            Write-Host "[ok] Split APK build completed." -ForegroundColor Green
        }
    }
}

$aabPath = Join-Path $APP_DIR "build\app\outputs\bundle\$Mode\app-$Mode.aab"
$apkDir = Join-Path $APP_DIR "build\app\outputs\flutter-apk"
$apkUniversalPath = Join-Path $apkDir "app-$Mode.apk"

Write-Host ""
Write-Host "==========================================" -ForegroundColor Green
Write-Host "Build summary"
Write-Host "==========================================" -ForegroundColor Green

if ($buildAabEnabled) {
    if (Test-Path -LiteralPath $aabPath) {
        Write-Host "[out] AAB: $aabPath"
    } else {
        Write-Host "[out] AAB: not found"
    }
}

if ($buildApkEnabled) {
    if ($buildUniversalApkEnabled) {
        if (Test-Path -LiteralPath $apkUniversalPath) {
            Write-Host "[out] Universal APK: $apkUniversalPath"
        } else {
            Write-Host "[out] Universal APK: not found"
        }
    }

    if ($buildSplitApkEnabled) {
        $splitApks = @()
        if (Test-Path -LiteralPath $apkDir) {
            $splitApks = Get-ChildItem -Path $apkDir -File -Filter "*-$Mode.apk" -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -ne "app-$Mode.apk" } |
                Select-Object -ExpandProperty FullName
        }
        if ($splitApks.Count -gt 0) {
            Write-Host "[out] Split APKs:"
            foreach ($apk in $splitApks) {
                Write-Host "      $apk"
            }
        } else {
            Write-Host "[out] Split APKs: not found"
        }
    }
}

Write-Host ""
Write-Host "Outputs directory: $(Join-Path $APP_DIR 'build\app\outputs')"
Write-Host ""
