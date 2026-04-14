@echo off
chcp 65001 >nul
echo ========================================
echo   نصب Flutter برای ویندوز
echo ========================================
echo.

REM بررسی اینکه آیا Flutter قبلاً نصب شده است
flutter --version >nul 2>&1
if %errorlevel% equ 0 (
    echo Flutter قبلاً نصب شده است!
    flutter --version
    echo.
    echo اجرای flutter doctor...
    flutter doctor
    goto :end
)

REM مسیر نصب
set INSTALL_PATH=%USERPROFILE%\Development
set FLUTTER_DIR=%INSTALL_PATH%\flutter

REM ایجاد پوشه نصب
if not exist "%INSTALL_PATH%" (
    echo ایجاد پوشه نصب: %INSTALL_PATH%
    mkdir "%INSTALL_PATH%"
)

REM بررسی Git
git --version >nul 2>&1
if %errorlevel% neq 0 (
    echo خطا: Git نصب نیست!
    echo لطفاً Git را از https://git-scm.com/download/win نصب کنید
    pause
    exit /b 1
)

echo Git یافت شد

REM بررسی اینکه آیا Flutter قبلاً کلون شده است
if exist "%FLUTTER_DIR%" (
    echo Flutter SDK در %FLUTTER_DIR% یافت شد
    echo به‌روزرسانی Flutter...
    cd /d "%FLUTTER_DIR%"
    git pull
    git checkout stable
) else (
    echo در حال کلون کردن Flutter از GitHub...
    git clone https://github.com/flutter/flutter.git -b stable "%FLUTTER_DIR%"
    if %errorlevel% neq 0 (
        echo خطا در کلون کردن Flutter!
        pause
        exit /b 1
    )
    echo Flutter با موفقیت کلون شد!
)

REM اضافه کردن Flutter به PATH
set FLUTTER_BIN=%FLUTTER_DIR%\bin
setx PATH "%PATH%;%FLUTTER_BIN%"
set PATH=%PATH%;%FLUTTER_BIN%

REM بررسی نصب Flutter
echo.
echo بررسی نصب Flutter...
cd /d "%FLUTTER_DIR%"
call bin\flutter.bat --version

echo.
echo اجرای flutter doctor (ممکن است چند دقیقه طول بکشد)...
call bin\flutter.bat doctor

echo.
echo ========================================
echo نصب با موفقیت انجام شد!
echo.
echo برای استفاده از Flutter، یک Command Prompt یا PowerShell جدید باز کنید
echo یا دستورات زیر را اجرا کنید:
echo   cd hesabixUI\hesabix_ui
echo   flutter pub get
echo   flutter build windows
echo ========================================

:end
pause





