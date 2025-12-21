@echo off
setlocal enabledelayedexpansion

REM Build script for Flutter Windows Desktop in this repo.
REM Creates a standalone executable for Windows.

set SCRIPT_DIR=%~dp0
set REPO_ROOT=%SCRIPT_DIR%

set DEFAULT_MODE=release
set DEFAULT_API_BASE_URL=https://hsxn.hesabix.ir
set DEFAULT_PUB_HOSTED_URL=https://mirrors.tuna.tsinghua.edu.cn/dart-pub
set DEFAULT_FLUTTER_STORAGE_BASE_URL=https://mirrors.tuna.tsinghua.edu.cn/flutter

set USER_PROJECT=
set MODE=%DEFAULT_MODE%
set API_BASE_URL=%DEFAULT_API_BASE_URL%
set CLEAN_BUILD=false
set INSTALL_DEPS=false

:parse_args
if "%~1"=="" goto end_parse
if /i "%~1"=="--project" (
    set USER_PROJECT=%~2
    shift
    shift
    goto parse_args
)
if /i "%~1"=="--mode" (
    set MODE=%~2
    shift
    shift
    goto parse_args
)
if /i "%~1"=="--api-base-url" (
    set API_BASE_URL=%~2
    shift
    shift
    goto parse_args
)
if /i "%~1"=="--pub-hosted-url" (
    set PUB_HOSTED_URL=%~2
    shift
    shift
    goto parse_args
)
if /i "%~1"=="--flutter-storage-base-url" (
    set FLUTTER_STORAGE_BASE_URL=%~2
    shift
    shift
    goto parse_args
)
if /i "%~1"=="--clean" (
    set CLEAN_BUILD=true
    shift
    goto parse_args
)
if /i "%~1"=="--install-deps" (
    set INSTALL_DEPS=true
    shift
    goto parse_args
)
if /i "%~1"=="--help" (
    echo Usage: build_windows.bat [--project ^<path^>] [--mode ^<debug^|profile^|release^>] [--api-base-url ^<url^>] [--pub-hosted-url ^<url^>] [--flutter-storage-base-url ^<url^>] [--clean] [--install-deps] [--help]
    echo.
    echo Options:
    echo   --project PATH     Flutter project path (contains pubspec.yaml). If not specified, will be auto-detected.
    echo   --mode MODE        Build type: debug, profile, or release (default: %DEFAULT_MODE%).
    echo   --api-base-url URL API base URL (default: %DEFAULT_API_BASE_URL%).
    echo   --pub-hosted-url URL Dart/Flutter pub mirror ^(default: %DEFAULT_PUB_HOSTED_URL% if env not set^).
    echo   --flutter-storage-base-url URL Flutter storage mirror ^(default: %DEFAULT_FLUTTER_STORAGE_BASE_URL% if env not set^).
    echo   --clean            Clean build directory before building.
    echo   --install-deps     Install dependencies before building.
    echo   --help             Show help.
    echo.
    echo Usage examples:
    echo   build_windows.bat
    echo   build_windows.bat --mode release --clean
    echo   build_windows.bat --project hesabixUI\hesabix_ui
    echo   build_windows.bat --api-base-url https://hsxn.hesabix.ir
    exit /b 0
)
echo [warn] Unknown argument: %~1
shift
goto parse_args
:end_parse

REM Validate mode
if /i not "%MODE%"=="debug" if /i not "%MODE%"=="profile" if /i not "%MODE%"=="release" (
    echo [error] Invalid mode: %MODE% (allowed: debug, profile, release)
    exit /b 1
)

REM Check Flutter
where flutter >nul 2>&1
if errorlevel 1 (
    echo [error] Flutter not found. Please install it or configure PATH.
    exit /b 1
)

REM Check Visual Studio toolchain for Windows desktop builds
where cl >nul 2>&1
if errorlevel 1 (
  set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
  if exist "%VSWHERE%" (
    "%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath >nul 2>&1
    if errorlevel 1 (
      echo [error] Visual Studio C++ toolchain not found.
      echo Install Visual Studio 2022 and select workload: Desktop development with C++.
      echo Make sure Windows 10/11 SDK and MSVC v143 are included.
      echo Download: https://visualstudio.microsoft.com/downloads/
      exit /b 1
    )
  ) else (
    echo [error] Visual Studio not installed (or vswhere not found). Windows build requires Visual Studio C++ toolchain.
    echo Install Visual Studio 2022 and select workload: Desktop development with C++.
    echo Download: https://visualstudio.microsoft.com/downloads/
    exit /b 1
  )
)

REM Auto-detect project directory
set APP_DIR=
if not "%USER_PROJECT%"=="" (
    if exist "%USER_PROJECT%\pubspec.yaml" (
        set APP_DIR=%USER_PROJECT%
    ) else (
        echo [error] Project path does not exist or does not contain pubspec.yaml: %USER_PROJECT%
        exit /b 1
    )
) else (
    set COMMON_PATH=%REPO_ROOT%hesabixUI\hesabix_ui
    if exist "%COMMON_PATH%\pubspec.yaml" (
        set APP_DIR=%COMMON_PATH%
    ) else (
        echo [error] Flutter project not found. Please specify path with --project.
        exit /b 1
    )
)

echo Repo root: %REPO_ROOT%
echo Project path: %APP_DIR%
echo Mode: %MODE%
echo API Base URL: %API_BASE_URL%
echo.

cd /d "%APP_DIR%"

REM Configure mirrors (env vars win over defaults; CLI args can override env vars above)
if not defined PUB_HOSTED_URL set "PUB_HOSTED_URL=%DEFAULT_PUB_HOSTED_URL%"
if not defined FLUTTER_STORAGE_BASE_URL set "FLUTTER_STORAGE_BASE_URL=%DEFAULT_FLUTTER_STORAGE_BASE_URL%"

echo PUB_HOSTED_URL: %PUB_HOSTED_URL%
echo FLUTTER_STORAGE_BASE_URL: %FLUTTER_STORAGE_BASE_URL%
echo.

REM Symlink check (Windows build with plugins requires symlink support)
set "_SYMLINK_TMP=%TEMP%\flutter_symlink_test_%RANDOM%%RANDOM%"
mkdir "%_SYMLINK_TMP%" >nul 2>&1
echo ok> "%_SYMLINK_TMP%\target.txt"
mklink "%_SYMLINK_TMP%\link.txt" "%_SYMLINK_TMP%\target.txt" >nul 2>&1
if errorlevel 1 (
    echo [error] Symlink support is not enabled. Flutter Windows build with plugins requires symlink support.
    echo Enable Windows Developer Mode: Settings ^> System ^> For developers ^> Developer Mode
    echo Or run the terminal as Administrator.
    echo Opening Developer Mode settings...
    start ms-settings:developers
    rmdir /s /q "%_SYMLINK_TMP%" >nul 2>&1
    exit /b 1
)
del /f /q "%_SYMLINK_TMP%\link.txt" >nul 2>&1
del /f /q "%_SYMLINK_TMP%\target.txt" >nul 2>&1
rmdir /s /q "%_SYMLINK_TMP%" >nul 2>&1

REM Install dependencies if requested
if "%INSTALL_DEPS%"=="true" (
    echo Installing dependencies...
    flutter pub get
    if errorlevel 1 (
        echo [error] Error downloading dependencies. Please check internet connection.
        exit /b 1
    )
) else (
    if not exist ".dart_tool" if not exist "pubspec.lock" (
        echo Dependencies not installed. Installing...
        flutter pub get
        if errorlevel 1 (
            echo [warn] Error downloading dependencies. Trying to continue...
        )
    )
)

REM Clean build directory if requested
if "%CLEAN_BUILD%"=="true" (
    echo Cleaning build directory...
    flutter clean
)

REM Build flags
set BUILD_FLAGS=--%MODE%
set BUILD_FLAGS=%BUILD_FLAGS% --dart-define=API_BASE_URL=%API_BASE_URL%

echo.
echo Build Configuration:
echo   Mode: %MODE%
echo   API Base URL: %API_BASE_URL%
echo.

echo ==========================================
echo Building Flutter for Windows...
echo ==========================================
echo Command: flutter build windows %BUILD_FLAGS%
echo.

flutter build windows %BUILD_FLAGS%

if errorlevel 1 (
    echo [error] Build failed!
    exit /b 1
)

REM Check output
set RUNNER_DIR=%APP_DIR%\build\windows\x64\runner
set EXECUTABLE=
for /r "%RUNNER_DIR%" %%F in (hesabix_ui.exe) do (
  set "EXECUTABLE=%%F"
  goto :found_exe
)
:found_exe

if defined EXECUTABLE if exist "%EXECUTABLE%" (
    echo.
    echo ==========================================
    echo ^✓ Build completed successfully!
    echo ==========================================
    echo.
    echo Build Configuration:
    echo   Mode: %MODE%
    echo   API Base URL: %API_BASE_URL%
    echo.
    echo Executable file:
    echo   %EXECUTABLE%
    echo.
    echo Build outputs are located at:
    for %%D in ("%EXECUTABLE%") do echo   %%~dpD
    echo.
) else (
    echo [warn] Executable file not found under: %RUNNER_DIR%
    echo Build may have completed but executable was not found.
)

endlocal


