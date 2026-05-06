# Helps diagnose/fix Windows cases where Gradle fails with "Permission denied"
# (Flutter surfaces this as "Gradle does not have execution permission").
#
# Usage (from repo root):
#   powershell -ExecutionPolicy Bypass -File .\scripts\fix_windows_android_gradle_permission_denied.ps1 [-Project hesabixUI\hesabix_ui] [-ResetLocalGradleCaches]

param(
    [string]$Project = "hesabixUI\hesabix_ui",
    [switch]$ResetLocalGradleCaches
)

$ErrorActionPreference = "Stop"

$ROOT = Split-Path -Parent $PSScriptRoot
$projPath = $Project
if (-not [System.IO.Path]::IsPathRooted($projPath)) {
    $projPath = Join-Path $ROOT $projPath
}
$projPath = (Resolve-Path -LiteralPath $projPath).Path
$androidDir = Join-Path $projPath "android"

Write-Host "Project: $projPath"
Write-Host "Android: $androidDir"

if (-not (Test-Path -LiteralPath $androidDir)) {
    Write-Host "[error] android folder not found." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "[step] Unblock-File on android\ (clears MOTW blocks from downloads/ZIP copies)..."
Get-ChildItem -LiteralPath $androidDir -Recurse -File -Force -ErrorAction SilentlyContinue |
    ForEach-Object { Unblock-File -LiteralPath $_.FullName -ErrorAction SilentlyContinue }

$gradleHome = $env:GRADLE_USER_HOME
if (-not $gradleHome) {
    $gradleHome = Join-Path $env:USERPROFILE ".gradle"
}

Write-Host ""
Write-Host "[step] Gradle user home (writable probe): $gradleHome"
try {
    if (-not (Test-Path -LiteralPath $gradleHome)) {
        New-Item -ItemType Directory -Path $gradleHome -Force | Out-Null
    }
    $p = Join-Path $gradleHome ".write_probe_hesabix"
    Set-Content -LiteralPath $p -Value "ok" -Encoding ascii -ErrorAction Stop
    Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
    Write-Host "        OK — directory is writable." -ForegroundColor Green
} catch {
    Write-Host "[error] Cannot write under Gradle home: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "        Fix ACLs on $gradleHome (Properties → Security) or pick another folder via GRADLE_USER_HOME." -ForegroundColor Yellow
    exit 1
}

if ($ResetLocalGradleCaches) {
    Write-Host ""
    Write-Host "[step] Removing project-local Gradle caches..."
    foreach ($rel in @("android\.gradle", "android\build", "android\app\build")) {
        $full = Join-Path $projPath $rel
        if (Test-Path -LiteralPath $full) {
            Remove-Item -LiteralPath $full -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "        Removed $rel"
        }
    }
}

Write-Host ""
Write-Host "[step] Stop Gradle daemons (needs gradlew.bat)..."
$gw = Join-Path $androidDir "gradlew.bat"
if (Test-Path -LiteralPath $gw) {
    Push-Location $androidDir
    try {
        cmd.exe /c "`"$gw`" --stop" | Out-Host
    } finally {
        Pop-Location
    }
} else {
    Write-Host "[warn] gradlew.bat missing — recreate Android wrapper with:" -ForegroundColor Yellow
    Write-Host ('        cd "{0}"' -f $projPath)
    Write-Host '        flutter create . --platforms=android'
}

Write-Host ""
Write-Host "Done. Retry build from project folder:"
Write-Host ('  cd "{0}"' -f $projPath)
Write-Host "  flutter clean"
Write-Host "  flutter build appbundle --release"
Write-Host ""
Write-Host "If it still fails, run with verbose logs to see the exact Permission denied path:"
Write-Host "  flutter build appbundle --release -v"
Write-Host ""
