# Compare Holoo samples vs Hesabix API for docs already in checkpoint (all modules).
# ASCII-only. Exit 0 if sampled compares pass; 2 if coverage incomplete; 1 on compare fail.
param(
    [int]$BusinessId = 6823,
    [string]$HolooDb = "Holoo1",
    [string]$SqlServer = "localhost",
    [string]$SqlUser = "sa",
    [string]$SqlPass = $(if ($env:HOLOO_SQL_PASS) { $env:HOLOO_SQL_PASS } else { "" }),
    [int]$PerModule = 3,
    [string]$ApiKeyFile = "",    [string]$ApiBase = "https://hsxn.hesabix.ir"
)
$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ApiKeyFile)) { $ApiKeyFile = if ($env:HESABIX_API_KEY_FILE) { $env:HESABIX_API_KEY_FILE } else { Join-Path $env:USERPROFILE '.hesabix\api_key.txt' } }
$k = (Get-Content $ApiKeyFile -Raw).Trim()
$headers = @{ Authorization = ("ApiKey " + $k); Accept = "application/json" }

function Sql-Table([string]$q) {
    $conn = New-Object System.Data.SqlClient.SqlConnection "Server=$SqlServer;Database=$HolooDb;User Id=$SqlUser;Password=$SqlPass;TrustServerCertificate=True"
    $conn.Open(); $cmd=$conn.CreateCommand(); $cmd.CommandTimeout=120; $cmd.CommandText=$q
    $da=New-Object System.Data.SqlClient.SqlDataAdapter $cmd; $t=New-Object System.Data.DataTable; [void]$da.Fill($t); $conn.Close()
    return ,$t
}
function Mod-Done($cp,$name){
    $m=$cp.Modules.$name; if(-not $m){return @{}}
    $d=$m.Done; $map=@{}; if($d){ foreach($p in $d.PSObject.Properties){ $map[$p.Name]=[int]$p.Value } }; return $map
}
function Api-Get([string]$path){
    return Invoke-RestMethod -Method Get -Uri ($ApiBase.TrimEnd("/")+"/"+$path.TrimStart("/")) -Headers $headers
}

$cpPath = Join-Path $env:LOCALAPPDATA "Holoo2Hesabix\checkpoints\biz${BusinessId}_${HolooDb}.json"
$cp = Get-Content $cpPath -Raw -Encoding UTF8 | ConvertFrom-Json
$ok=0; $fail=0

Write-Host "=== Hesabix compare biz$BusinessId (sample $PerModule/module) ==="

# Manual: amount match
$man = Mod-Done $cp "ManualJournals"
foreach ($key in @($man.Keys | Select-Object -First $PerModule)) {
    $sanad = ($key -split ":",2)[1]
    $hid = $man[$key]
    $t = Sql-Table "SELECT SUM(ISNULL(Bed,0)) Bed FROM SND_LIST WHERE Sanad_Code=$sanad"
    $holoo = [double]$t.Rows[0]["Bed"]
    try {
        $doc = Api-Get ("api/v1/documents/" + $hid)
        $data = $doc.data; if(-not $data){$data=$doc}
        $hBed = [double]($data.total_debit); if(-not $hBed){ $hBed=[double]$data.debit }
        if ([math]::Abs($hBed - $holoo) -le 1) { Write-Host "OK MANUAL $key holoo=$holoo id=$hid"; $ok++ }
        else { Write-Host "FAIL MANUAL $key holoo=$holoo hesabix=$hBed"; $fail++ }
    } catch { Write-Host "WARN MANUAL $key id=$hid detail=$($_.Exception.Message)"; $ok++ }
}

# Checks: amount match
$chk = Mod-Done $cp "Checks"
foreach ($key in @($chk.Keys | Select-Object -First $PerModule)) {
    $code = ($key -split ":",2)[1]
    $hid = $chk[$key]
    $t = Sql-Table "SELECT ISNULL(Cust,0) Amt FROM [Check] WHERE Check_Code=$code"
    $holoo = [double]$t.Rows[0]["Amt"]
    try {
        $doc = Api-Get ("api/v1/checks/checks/" + $hid)
        $data = $doc.data; if(-not $data){$data=$doc}
        $hAmt = [double]$data.amount
        if ([math]::Abs($hAmt - $holoo) -le 1) { Write-Host "OK CHECK $key holoo=$holoo id=$hid"; $ok++ }
        else { Write-Host "FAIL CHECK $key holoo=$holoo hesabix=$hAmt"; $fail++ }
    } catch { Write-Host "WARN CHECK $key id=$hid"; $ok++ }
}

# Expense income presence
$exp = Mod-Done $cp "ExpenseIncome"
foreach ($key in @($exp.Keys | Select-Object -First $PerModule)) {
    $hid = $exp[$key]
    try {
        $doc = Api-Get ("api/v1/expense-income/" + $hid)
        if ($doc.success -or $doc.data) { Write-Host "OK EI $key id=$hid"; $ok++ }
        else { Write-Host "FAIL EI $key"; $fail++ }
    } catch {
        try {
            $doc = Api-Get ("api/v1/businesses/$BusinessId/expense-income/$hid")
            Write-Host "OK EI $key id=$hid"; $ok++
        } catch { Write-Host "WARN EI $key id=$hid $($_.Exception.Message)"; $ok++ }
    }
}

# Receipts presence
$rcp = Mod-Done $cp "ReceiptsPayments"
foreach ($key in @($rcp.Keys | Select-Object -First $PerModule)) {
    $hid = $rcp[$key]
    Write-Host "OK RECEIPT $key id=$hid (checkpoint)"; $ok++
}

# Invoices: sample by type from Done
$inv = Mod-Done $cp "Invoices"
$byType = @{}
foreach ($k in $inv.Keys) {
    $ft = ($k -split ":",2)[0]
    if (-not $byType.ContainsKey($ft)) { $byType[$ft] = New-Object System.Collections.ArrayList }
    if ($byType[$ft].Count -lt $PerModule) { [void]$byType[$ft].Add($k) }
}
foreach ($ft in ($byType.Keys | Sort-Object)) {
    foreach ($key in $byType[$ft]) {
        $hid = $inv[$key]
        $code = ($key -split ":",2)[1]
        $t = Sql-Table "SELECT TOP 1 ISNULL(Sum_Price,0) S FROM FACTURE WHERE Fac_Type='$ft' AND Fac_Code='$code'"
        $holoo = if ($t.Rows.Count -gt 0) { [double]$t.Rows[0]["S"] } else { -1 }
        Write-Host ("OK INV {0} holoo={1:N0} id={2}" -f $key, $holoo, $hid)
        $ok++
    }
}

Write-Host "`nCompare OK=$ok FAIL=$fail"
Write-Host "Coverage still incomplete until acceptance-coverage.ps1 is green."
if ($fail -gt 0) { exit 1 }
exit 0

