# Compare Holoo opening nets (ex 005/006) vs Hesabix posted OB by account group.
# Usage: .\compare-opening-balance.ps1 -BusinessId 6823 -FiscalYearId 6894 -ApiKey <key>
param(
    [int]$BusinessId = 6823,
    [int]$FiscalYearId = 6894,
    [string]$ApiKey = "",
    [string]$ApiBase = "https://hsxn.hesabix.ir",
    [string]$SqlServer = "localhost",
    [string]$SqlUser = "sa",
    [string]$SqlPass = $(if ($env:HOLOO_SQL_PASS) { $env:HOLOO_SQL_PASS } else { "" }),
    [string]$SqlDb = "Holoo1"
)
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

if (-not $ApiKey) {
    $p = if ($env:HESABIX_API_KEY_FILE) { $env:HESABIX_API_KEY_FILE } else { Join-Path $env:USERPROFILE ".hesabix\api_key.txt" }
    if (Test-Path $p) { $ApiKey = (Get-Content $p -Raw).Trim() }
}
if (-not $ApiKey) { throw "ApiKey required" }

$conn = New-Object System.Data.SqlClient.SqlConnection "Server=$SqlServer;Database=$SqlDb;User Id=$SqlUser;Password=$SqlPass;TrustServerCertificate=True"
$conn.Open()
$cmd = $conn.CreateCommand()
$cmd.CommandText = "SELECT TOP 1 Sanad_Code FROM SANAD WHERE ISNULL([Delete],0)=0 AND (Comment LIKE N'%افتتاح%' OR Sanad_Code=1) ORDER BY Sanad_Code"
$sanad = [int]$cmd.ExecuteScalar()
$cmd.CommandText = @"
SELECT l.Col_Code,
  SUM(ISNULL(l.Bed,0)) - SUM(ISNULL(l.Bes,0)) AS net
FROM SND_LIST l
WHERE l.Sanad_Code=$sanad AND l.Col_Code NOT IN ('005','006')
GROUP BY l.Col_Code
"@
$holoo = @{}
$r = $cmd.ExecuteReader()
while ($r.Read()) { $holoo[[string]$r.GetValue(0)] = [decimal]$r.GetValue(1) }
$r.Close(); $conn.Close()

$headers = @{ Authorization = "ApiKey $ApiKey" }
$ob = Invoke-RestMethod -Method Get -Uri "$ApiBase/api/v1/businesses/$BusinessId/opening-balance?fiscal_year_id=$FiscalYearId" -Headers $headers
$hx = @{}
foreach ($ln in $ob.data.lines) {
    $code = [string]$ln.account_code
    if (-not $hx.ContainsKey($code)) { $hx[$code] = 0.0 }
    $hx[$code] += [double]$ln.debit - [double]$ln.credit
}

# Expected Holoo Col -> Hesabix code groups (nets additive)
$groups = @(
    @{ Name = "cash_petty"; HolooCols = @("101"); HxCodes = @("10202","10201") },
    @{ Name = "banks"; HolooCols = @("102"); HxCodes = @("10203") },
    @{ Name = "inventory"; HolooCols = @("106"); HxCodes = @("10102") },
    @{ Name = "notes_pay"; HolooCols = @("402"); HxCodes = @("20202") },
    @{ Name = "fixed_assets"; HolooCols = @("205"); HxCodes = @("10704","10701","10702","10703") },
    @{ Name = "equity_capital"; HolooCols = @("404"); HxCodes = @("30105") },
    @{ Name = "equity_open"; HolooCols = @("502"); HxCodes = @("30106") }
)

$failed = 0
foreach ($g in $groups) {
    $hNet = 0.0
    foreach ($c in $g.HolooCols) { if ($holoo.ContainsKey($c)) { $hNet += [double]$holoo[$c] } }
    $xNet = 0.0
    foreach ($c in $g.HxCodes) { if ($hx.ContainsKey($c)) { $xNet += [double]$hx[$c] } }
    $diff = [Math]::Abs($hNet - $xNet)
    if ($diff -gt 1.0) {
        Write-Host ("FAIL: {0} holoo={1:N2} hx={2:N2} diff={3:N2}" -f $g.Name, $hNet, $xNet, $diff) -ForegroundColor Red
        $failed++
    } else {
        Write-Host ("OK: {0} net={1:N2}" -f $g.Name, $hNet)
    }
}

# persons+loans combined
$hPers = 0.0
foreach ($c in @("103","401")) { if ($holoo.ContainsKey($c)) { $hPers += [double]$holoo[$c] } }
$xPers = 0.0
foreach ($kv in $hx.GetEnumerator()) {
    if ($kv.Key -eq "10401" -or $kv.Key -eq "20201" -or $kv.Key -like "20519401*") {
        $xPers += $kv.Value
    }
}
$diffP = [Math]::Abs($hPers - $xPers)
if ($diffP -gt 1.0) {
    Write-Host ("FAIL: persons_loans holoo={0:N2} hx={1:N2} diff={2:N2}" -f $hPers, $xPers, $diffP) -ForegroundColor Red
    $failed++
} else {
    Write-Host ("OK: persons_loans net={0:N2}" -f $hPers)
}

$bal = [Math]::Abs([double]$ob.data.total_debit - [double]$ob.data.total_credit)
if ($bal -gt 0.01) {
    Write-Host "FAIL: Hesabix OB unbalanced debit-credit=$bal" -ForegroundColor Red
    $failed++
} else {
    Write-Host ("OK: Hesabix OB balanced total={0:N2} lines={1}" -f [double]$ob.data.total_debit, $ob.data.lines_count)
}

if ($failed -gt 0) { Write-Host "`n$failed group(s) failed." -ForegroundColor Red; exit 1 }
Write-Host "`nOpening balance acceptance passed." -ForegroundColor Green
exit 0
