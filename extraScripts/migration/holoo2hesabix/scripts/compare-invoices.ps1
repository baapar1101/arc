# Compare Holoo FACTURE counts vs Hesabix invoice checkpoint for a business.
# ASCII-only for PS encoding safety.
param(
    [int]$BusinessId = 6823,
    [string]$HolooDb = "Holoo1",
    [string]$SqlServer = "localhost",
    [string]$SqlUser = "sa",
    [string]$SqlPass = $(if ($env:HOLOO_SQL_PASS) { $env:HOLOO_SQL_PASS } else { "" })
)
$ErrorActionPreference = "Stop"

function Sql-Scalar([string]$q) {
    $raw = sqlcmd -S $SqlServer -U $SqlUser -P $SqlPass -C -d $HolooDb -h -1 -W -Q "SET NOCOUNT ON; $q"
    return [int](($raw | Where-Object { $_ -match '^\d+$' } | Select-Object -First 1))
}

$cpPath = Join-Path $env:LOCALAPPDATA "Holoo2Hesabix\checkpoints\biz${BusinessId}_${HolooDb}.json"
if (-not (Test-Path $cpPath)) { throw "checkpoint missing: $cpPath" }
$cp = Get-Content $cpPath -Raw -Encoding UTF8 | ConvertFrom-Json
$m = $cp.Modules.Invoices; if (-not $m) { $m = $cp.modules.Invoices }
$doneObj = $m.Done; if (-not $doneObj) { $doneObj = $m.done }
$failObj = $m.Failed; if (-not $failObj) { $failObj = $m.failed }
$done = if ($doneObj) { @($doneObj.PSObject.Properties).Count } else { 0 }
$fail = if ($failObj) { @($failObj.PSObject.Properties).Count } else { 0 }

$holoo = Sql-Scalar "SELECT COUNT(*) FROM FACTURE WHERE ISNULL([Delete],0)=0"
$byType = sqlcmd -S $SqlServer -U $SqlUser -P $SqlPass -C -d $HolooDb -h -1 -W -Q "SET NOCOUNT ON; SELECT Fac_Type, COUNT(*) c FROM FACTURE WHERE ISNULL([Delete],0)=0 GROUP BY Fac_Type ORDER BY Fac_Type;"

Write-Host "=== Invoice compare biz$BusinessId ==="
Write-Host "Holoo FACTURE rows=$holoo"
Write-Host "Checkpoint done=$done fail=$fail"
Write-Host "By Fac_Type:"
$byType | ForEach-Object { Write-Host "  $_" }
$pct = if ($holoo -gt 0) { [math]::Round(100.0 * $done / $holoo, 2) } else { 0 }
Write-Host ("Coverage={0}% ({1}/{2})" -f $pct, $done, $holoo)

$exit = 0
if ($fail -gt 0) { Write-Host "WARN: failures=$fail" -ForegroundColor Yellow; $exit = 2 }
if ($done -lt $holoo) { Write-Host "INCOMPLETE: still short of Holoo count" -ForegroundColor Yellow; $exit = 2 }
elseif ($fail -eq 0) { Write-Host "Invoice coverage complete." -ForegroundColor Green }
exit $exit
