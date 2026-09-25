# Watchdog: keep full E2E running until invoices reach Holoo count (or max hours).
param(
    [int]$BusinessId = 6823,
    [int]$TargetInvoices = 22789,
    [int]$MaxHours = 36,
    [string]$RunScript = "d:\hesabixArc\extraScripts\migration\holoo2hesabix\scripts\run-full-e2e.ps1"
)
$ErrorActionPreference = "Continue"
$log = "d:\hesabixArc\.eyeban\e2e-watchdog.txt"
$pidFile = "d:\hesabixArc\.eyeban\e2e-full-pid.txt"
$deadline = (Get-Date).AddHours($MaxHours)
function Log([string]$m) {
  $line = "$(Get-Date -Format 's') $m"
  Add-Content $log $line -Encoding UTF8
  Write-Output $line
}
function DoneCount() {
  try {
    $j = Get-Content "$env:LOCALAPPDATA\Holoo2Hesabix\checkpoints\biz${BusinessId}_Holoo1.json" -Raw -Encoding UTF8 | ConvertFrom-Json
    return @($j.Modules.Invoices.Done.PSObject.Properties).Count
  } catch { return -1 }
}
function IsAlive() {
  if (-not (Test-Path $pidFile)) { return $false }
  $p = 0
  try { $p = [int](Get-Content $pidFile -Raw).Trim() } catch { return $false }
  if ($p -le 0) { return $false }
  return [bool](Get-Process -Id $p -ErrorAction SilentlyContinue)
}
function StartTransfer() {
  & powershell -NoProfile -ExecutionPolicy Bypass -File $RunScript -BusinessId $BusinessId
  Start-Sleep -Seconds 4
}
Log "watchdog start target=$TargetInvoices maxHours=$MaxHours"
if (-not (IsAlive)) {
  Log "starting initial transfer"
  StartTransfer
}
while ((Get-Date) -lt $deadline) {
  $d = DoneCount
  $alive = IsAlive
  Log "alive=$alive inv=$d/$TargetInvoices"
  if ($d -ge $TargetInvoices) {
    Log "TARGET REACHED inv=$d"
    if ($alive) {
      for ($i = 0; $i -lt 90; $i++) {
        if (-not (IsAlive)) { break }
        Start-Sleep -Seconds 30
      }
    }
    Log "watchdog done"
    exit 0
  }
  if (-not $alive) {
    Log "process dead - restart from checkpoint"
    StartTransfer
    if (-not (IsAlive)) {
      Log "restart FAILED"
      Start-Sleep -Seconds 60
    }
  }
  Start-Sleep -Seconds 120
}
Log "watchdog deadline reached inv=$(DoneCount)"
exit 2
