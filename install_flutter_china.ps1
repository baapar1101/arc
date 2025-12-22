# Flutter Installation Script with Chinese Mirrors
# For use in China (due to Google sanctions)

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Installing Flutter with Chinese Mirrors" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Set Chinese Mirrors
$env:PUB_HOSTED_URL = "https://pub.flutter-io.cn"
$env:FLUTTER_STORAGE_BASE_URL = "https://storage.flutter-io.cn"

Write-Host "Setting Chinese Mirrors:" -ForegroundColor Yellow
Write-Host "  PUB_HOSTED_URL: $env:PUB_HOSTED_URL" -ForegroundColor White
Write-Host "  FLUTTER_STORAGE_BASE_URL: $env:FLUTTER_STORAGE_BASE_URL" -ForegroundColor White
Write-Host ""

# Check if Flutter is already installed
try {
    $flutterVersion = flutter --version 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Flutter is already installed!" -ForegroundColor Green
        flutter --version
        Write-Host ""
        Write-Host "Running flutter doctor..." -ForegroundColor Cyan
        flutter doctor
        Write-Host ""
        Write-Host "Chinese mirrors are set for this session." -ForegroundColor Green
        exit 0
    }
} catch {
    Write-Host "Flutter is not installed, continuing installation..." -ForegroundColor Yellow
}

# Installation path
$installPath = "$env:USERPROFILE\Development"
$flutterDir = "$installPath\flutter"

# Create installation directory
if (-not (Test-Path $installPath)) {
    Write-Host "Creating installation directory: $installPath" -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $installPath -Force | Out-Null
}

# Check Git
try {
    $gitVersion = git --version 2>&1
    Write-Host "Git found: $gitVersion" -ForegroundColor Green
} catch {
    Write-Host "Error: Git is not installed!" -ForegroundColor Red
    Write-Host "Please install Git from https://git-scm.com/download/win" -ForegroundColor Yellow
    exit 1
}

# Check if Flutter is already cloned
if (Test-Path $flutterDir) {
    Write-Host "Flutter SDK found at $flutterDir" -ForegroundColor Yellow
    Write-Host "Updating Flutter..." -ForegroundColor Yellow
    Set-Location $flutterDir
    git pull
    git checkout stable
} else {
    Write-Host "Cloning Flutter from GitHub (using Chinese mirror)..." -ForegroundColor Yellow
    Write-Host "This may take several minutes..." -ForegroundColor Yellow
    git clone https://github.com/flutter/flutter.git -b stable $flutterDir
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Error cloning Flutter!" -ForegroundColor Red
        exit 1
    }
    Write-Host "Flutter cloned successfully!" -ForegroundColor Green
}

# Add Flutter to PATH
$flutterBinPath = "$flutterDir\bin"
$currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($currentPath -notlike "*$flutterBinPath*") {
    Write-Host "Adding Flutter to PATH..." -ForegroundColor Yellow
    [Environment]::SetEnvironmentVariable("Path", "$currentPath;$flutterBinPath", "User")
    $env:Path += ";$flutterBinPath"
    Write-Host "Flutter added to PATH" -ForegroundColor Green
} else {
    Write-Host "Flutter is already in PATH" -ForegroundColor Green
    $env:Path += ";$flutterBinPath"
}

# Set Chinese Mirrors permanently in User Environment Variables
$currentPubHosted = [Environment]::GetEnvironmentVariable("PUB_HOSTED_URL", "User")
$currentFlutterStorage = [Environment]::GetEnvironmentVariable("FLUTTER_STORAGE_BASE_URL", "User")

if (-not $currentPubHosted) {
    [Environment]::SetEnvironmentVariable("PUB_HOSTED_URL", $env:PUB_HOSTED_URL, "User")
    Write-Host "PUB_HOSTED_URL added to environment variables" -ForegroundColor Green
}

if (-not $currentFlutterStorage) {
    [Environment]::SetEnvironmentVariable("FLUTTER_STORAGE_BASE_URL", $env:FLUTTER_STORAGE_BASE_URL, "User")
    Write-Host "FLUTTER_STORAGE_BASE_URL added to environment variables" -ForegroundColor Green
}

# Verify Flutter installation
Write-Host ""
Write-Host "Verifying Flutter installation..." -ForegroundColor Cyan
Set-Location $flutterDir
.\bin\flutter.bat --version

Write-Host ""
Write-Host "Running flutter doctor (this may take several minutes)..." -ForegroundColor Cyan
Write-Host "Please wait..." -ForegroundColor Yellow
.\bin\flutter.bat doctor

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "[SUCCESS] Installation completed successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "Chinese Mirror Settings:" -ForegroundColor Yellow
Write-Host "  PUB_HOSTED_URL: $env:PUB_HOSTED_URL" -ForegroundColor White
Write-Host "  FLUTTER_STORAGE_BASE_URL: $env:FLUTTER_STORAGE_BASE_URL" -ForegroundColor White
Write-Host ""
Write-Host "To use Flutter, open a new PowerShell window" -ForegroundColor Yellow
Write-Host "Or run the following commands:" -ForegroundColor Yellow
Write-Host "  cd hesabixUI\hesabix_ui" -ForegroundColor White
Write-Host "  flutter pub get" -ForegroundColor White
Write-Host "  flutter build windows" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Cyan
