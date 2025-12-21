# Flutter SDK Download Script
# This script downloads Flutter SDK using Git

$ErrorActionPreference = "Continue"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Downloading Flutter SDK" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check if Flutter is already installed
try {
    $null = Get-Command flutter -ErrorAction Stop
    Write-Host "Flutter is already installed!" -ForegroundColor Green
    flutter --version
    Write-Host ""
    Write-Host "Running flutter doctor..." -ForegroundColor Cyan
    flutter doctor
    exit 0
} catch {
    Write-Host "Flutter not found, starting download..." -ForegroundColor Yellow
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
$gitInstalled = $false
try {
    $null = Get-Command git -ErrorAction Stop
    $gitInstalled = $true
    Write-Host "Git found" -ForegroundColor Green
} catch {
    Write-Host "Error: Git is not installed!" -ForegroundColor Red
    Write-Host "Please install Git from https://git-scm.com/download/win" -ForegroundColor Yellow
    Write-Host "After installing Git, run this script again." -ForegroundColor Yellow
    exit 1
}

# Check if Flutter is already cloned
if (Test-Path $flutterDir) {
    Write-Host "Flutter SDK found at $flutterDir" -ForegroundColor Yellow
    Write-Host "Updating Flutter..." -ForegroundColor Yellow
    Push-Location $flutterDir
    git pull
    git checkout stable
    Pop-Location
} else {
    Write-Host "Cloning Flutter from GitHub (this may take several minutes)..." -ForegroundColor Yellow
    try {
        git clone https://github.com/flutter/flutter.git -b stable $flutterDir
        if ($LASTEXITCODE -ne 0) {
            throw "git clone failed with exit code $LASTEXITCODE"
        }
        Write-Host "Flutter cloned successfully!" -ForegroundColor Green
    } catch {
        Write-Host "Error cloning Flutter: $_" -ForegroundColor Red
        Write-Host "Please check your internet connection and try again." -ForegroundColor Yellow
        exit 1
    }
}

# Add Flutter to PATH
$flutterBinPath = "$flutterDir\bin"

# Add to system PATH (User Environment Variable)
$currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($currentPath -notlike "*$flutterBinPath*") {
    Write-Host "Adding Flutter to PATH..." -ForegroundColor Yellow
    try {
        [Environment]::SetEnvironmentVariable("Path", "$currentPath;$flutterBinPath", "User")
        Write-Host "Flutter added to PATH (restart terminal required)" -ForegroundColor Green
    } catch {
        Write-Host "Error adding to PATH: $_" -ForegroundColor Yellow
        Write-Host "You can add manually later: $flutterBinPath" -ForegroundColor Yellow
    }
} else {
    Write-Host "Flutter is already in PATH" -ForegroundColor Green
}

# Add to current session PATH
if ($env:Path -notlike "*$flutterBinPath*") {
    $env:Path += ";$flutterBinPath"
}

# Verify Flutter installation
Write-Host ""
Write-Host "Verifying Flutter installation..." -ForegroundColor Cyan
try {
    & "$flutterBinPath\flutter.bat" --version
} catch {
    Write-Host "Error running flutter: $_" -ForegroundColor Red
}

Write-Host ""
Write-Host "Running flutter doctor (this may take several minutes)..." -ForegroundColor Cyan
try {
    & "$flutterBinPath\flutter.bat" doctor
} catch {
    Write-Host "Error running flutter doctor: $_" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Download completed successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "Important: Open a new Terminal to use Flutter" -ForegroundColor Yellow
Write-Host "or run the following commands in this terminal:" -ForegroundColor Yellow
Write-Host ""
Write-Host "  `$env:Path += ';$flutterBinPath'" -ForegroundColor White
Write-Host "  cd hesabixUI\hesabix_ui" -ForegroundColor White
Write-Host "  flutter pub get" -ForegroundColor White
Write-Host "  flutter build windows" -ForegroundColor White
Write-Host ""
Write-Host "Flutter path: $flutterDir" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan





