@echo off
chcp 65001 >nul
echo ========================================
echo   Downloading Flutter SDK
echo ========================================
echo.

REM Check if Flutter is already installed
where flutter >nul 2>&1
if %ERRORLEVEL% == 0 (
    echo Flutter is already installed!
    flutter --version
    echo.
    echo Running flutter doctor...
    flutter doctor
    exit /b 0
)

REM Installation path
set "INSTALL_PATH=%USERPROFILE%\Development"
set "FLUTTER_DIR=%INSTALL_PATH%\flutter"

REM Create installation directory
if not exist "%INSTALL_PATH%" (
    echo Creating installation directory: %INSTALL_PATH%
    mkdir "%INSTALL_PATH%"
)

REM Check Git
where git >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo Error: Git is not installed!
    echo Please install Git from https://git-scm.com/download/win
    echo After installing Git, run this script again.
    exit /b 1
)
echo Git found

REM Check if Flutter is already cloned
if exist "%FLUTTER_DIR%" (
    echo Flutter SDK found at %FLUTTER_DIR%
    echo Updating Flutter...
    cd /d "%FLUTTER_DIR%"
    git pull
    git checkout stable
) else (
    echo Cloning Flutter from GitHub (this may take several minutes)...
    git clone https://github.com/flutter/flutter.git -b stable "%FLUTTER_DIR%"
    if %ERRORLEVEL% NEQ 0 (
        echo Error cloning Flutter!
        echo Please check your internet connection and try again.
        exit /b 1
    )
    echo Flutter cloned successfully!
)

REM Add Flutter to PATH
set "FLUTTER_BIN=%FLUTTER_DIR%\bin"

REM Add to current session PATH
set "PATH=%PATH%;%FLUTTER_BIN%"

REM Verify Flutter installation
echo.
echo Verifying Flutter installation...
"%FLUTTER_BIN%\flutter.bat" --version

echo.
echo Running flutter doctor (this may take several minutes)...
"%FLUTTER_BIN%\flutter.bat" doctor

echo.
echo ========================================
echo Download completed successfully!
echo.
echo Important: Open a new Terminal to use Flutter
echo or run the following commands:
echo.
echo   set PATH=%%PATH%%;%FLUTTER_BIN%
echo   cd hesabixUI\hesabix_ui
echo   flutter pub get
echo   flutter build windows
echo.
echo Flutter path: %FLUTTER_DIR%
echo ========================================

pause





