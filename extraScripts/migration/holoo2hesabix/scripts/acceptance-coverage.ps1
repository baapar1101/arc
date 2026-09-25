# Holoo1 acceptance: partition coverage counts vs migration checkpoint.
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

$totalSanad = Sql-Scalar "SELECT COUNT(*) FROM SANAD WHERE ISNULL([Delete],0)=0"
$factureSanad = Sql-Scalar "SELECT COUNT(DISTINCT Sanad_Code) FROM FACTURE WHERE ISNULL([Delete],0)=0 AND ISNULL(Sanad_Code,0)>0"
$factureRows = Sql-Scalar "SELECT COUNT(*) FROM FACTURE WHERE ISNULL([Delete],0)=0"
$checkSanad = Sql-Scalar "SELECT COUNT(DISTINCT Sanad_Code) FROM (SELECT Sanad_Code FROM [Check] WHERE ISNULL(Sanad_Code,0)>0 UNION SELECT Sanad_Code2 FROM [Check] WHERE ISNULL(Sanad_Code2,0)>0) x"
$checkRows = Sql-Scalar "SELECT COUNT(*) FROM [Check]"
$manualN = Sql-Scalar @"
SELECT COUNT(*) FROM SANAD s WHERE ISNULL(s.[Delete],0)=0 AND ISNULL(s.SaveFromFacture,0)=0
AND ISNULL(s.Sanad_Type,0) NOT IN (5,20)
AND NOT EXISTS (SELECT 1 FROM FACTURE f WHERE f.Sanad_Code=s.Sanad_Code AND ISNULL(f.[Delete],0)=0)
AND NOT EXISTS (SELECT 1 FROM [Check] c WHERE c.Sanad_Code=s.Sanad_Code OR c.Sanad_Code2=s.Sanad_Code)
AND NOT EXISTS (SELECT 1 FROM SND_LIST x WHERE x.Sanad_Code=s.Sanad_Code AND x.Col_Code IN ('601','702'))
"@
# Pure Type20 receipts: exclude those with 601/702 (those are EXPENSE_INCOME / EI-fallback)
$type20Receipt = Sql-Scalar @"
SELECT COUNT(*) FROM SANAD s WHERE ISNULL(s.[Delete],0)=0 AND ISNULL(s.Sanad_Type,0)=20
AND NOT EXISTS (SELECT 1 FROM SND_LIST x WHERE x.Sanad_Code=s.Sanad_Code AND x.Col_Code IN ('601','702'))
"@
$type20All = Sql-Scalar "SELECT COUNT(*) FROM SANAD WHERE ISNULL([Delete],0)=0 AND ISNULL(Sanad_Type,0)=20"
# Expense/income candidates: any non-check, non-facture sanad with 601/702 (includes Type20)
$expenseLike = Sql-Scalar @"
SELECT COUNT(DISTINCT s.Sanad_Code) FROM SANAD s
WHERE ISNULL(s.[Delete],0)=0 AND ISNULL(s.SaveFromFacture,0)=0 AND ISNULL(s.Sanad_Type,0)<>5
AND EXISTS (SELECT 1 FROM SND_LIST x WHERE x.Sanad_Code=s.Sanad_Code AND x.Col_Code IN ('601','702'))
AND NOT EXISTS (SELECT 1 FROM FACTURE f WHERE f.Sanad_Code=s.Sanad_Code AND ISNULL(f.[Delete],0)=0)
AND NOT EXISTS (SELECT 1 FROM [Check] c WHERE c.Sanad_Code=s.Sanad_Code OR c.Sanad_Code2=s.Sanad_Code)
"@

function Mod-Count($name) {
    $m = $cp.Modules.$name
    if (-not $m) { $m = $cp.modules.$name }
    if (-not $m) { return @{ done = 0; fail = 0 } }
    $doneObj = $m.Done; if (-not $doneObj) { $doneObj = $m.done }
    $failObj = $m.Failed; if (-not $failObj) { $failObj = $m.failed }
    return @{
        done = if ($doneObj) { @($doneObj.PSObject.Properties).Count } else { 0 }
        fail = if ($failObj) { @($failObj.PSObject.Properties).Count } else { 0 }
    }
}

$inv = Mod-Count "Invoices"
$man = Mod-Count "ManualJournals"
$rcp = Mod-Count "ReceiptsPayments"
$chk = Mod-Count "Checks"
$exp = Mod-Count "ExpenseIncome"
$ob = Mod-Count "FiscalYearsAndOpening"

Write-Host "=== Holoo source ==="
Write-Host "SANAD total=$totalSanad"
Write-Host "FACTURE rows=$factureRows distinct-sanad=$factureSanad"
Write-Host "Check rows=$checkRows linked-sanad=$checkSanad"
Write-Host "Type20 all=$type20All receipt-only(no 601/702)=$type20Receipt"
Write-Host "Expense/Income candidates (incl Type20+601/702)=$expenseLike"
Write-Host "Manual partition (excl EI)=$manualN"

Write-Host "`n=== Checkpoint biz$BusinessId ==="
Write-Host ("Opening done={0} fail={1}" -f $ob.done, $ob.fail)
Write-Host ("Invoices done={0} fail={1} (holoo facture rows={2})" -f $inv.done, $inv.fail, $factureRows)
Write-Host ("Manual done={0} fail={1} (holoo base partition={2}; EI-fallback counted in Manual)" -f $man.done, $man.fail, $manualN)
Write-Host ("Receipts done={0} fail={1} (holoo receipt-only={2})" -f $rcp.done, $rcp.fail, $type20Receipt)
Write-Host ("Checks done={0} fail={1} (holoo rows={2})" -f $chk.done, $chk.fail, $checkRows)
Write-Host ("Expense done={0} fail={1} (holoo EI candidates={2})" -f $exp.done, $exp.fail, $expenseLike)

$failed = 0
if ($ob.fail -gt 0) { Write-Host "FAIL: opening has failures" -ForegroundColor Red; $failed++ }
if ($ob.done -lt 1) { Write-Host "FAIL: opening not done" -ForegroundColor Red; $failed++ }
if ($man.fail -gt 0) { Write-Host "FAIL: manual has failures" -ForegroundColor Red; $failed++ }
if ($man.done -lt 1) { Write-Host "FAIL: no manual journals migrated" -ForegroundColor Red; $failed++ }
if ($inv.fail -gt 0) { Write-Host "WARN: invoice failures=$($inv.fail)" -ForegroundColor Yellow }
$invPct = if ($factureRows -gt 0) { [math]::Round(100.0 * $inv.done / $factureRows, 1) } else { 0 }
Write-Host ("Invoice coverage={0}% ({1}/{2})" -f $invPct, $inv.done, $factureRows)
if ($invPct -lt 99.0 -and $inv.done -lt $factureRows) {
    Write-Host "INCOMPLETE: invoice migration still in progress or short" -ForegroundColor Yellow
    $failed++
}
if ($rcp.done -eq 0 -and $type20Receipt -gt 0) {
    Write-Host "INCOMPLETE: receipts not started (holoo receipt-only=$type20Receipt)" -ForegroundColor Yellow
    $failed++
}
if ($chk.done -eq 0 -and $checkRows -gt 0) {
    Write-Host "INCOMPLETE: checks not started (holoo=$checkRows)" -ForegroundColor Yellow
    $failed++
}
if ($exp.done -eq 0 -and $expenseLike -gt 0) {
    Write-Host "INCOMPLETE: expense/income not started (holoo=$expenseLike)" -ForegroundColor Yellow
    $failed++
}

if ($failed -gt 0) { Write-Host "`nAcceptance incomplete ($failed)." -ForegroundColor Yellow; exit 2 }
Write-Host "`nAcceptance gates for completed modules passed." -ForegroundColor Green
exit 0
