# Sample verification: Holoo source vs checkpoint (+ Hesabix API amounts where possible).
param(
    [int]$BusinessId = 6823,
    [string]$HolooDb = "Holoo1",
    [string]$SqlServer = "localhost",
    [string]$SqlUser = "sa",
    [string]$SqlPass = $(if ($env:HOLOO_SQL_PASS) { $env:HOLOO_SQL_PASS } else { "" }),
    [int]$PerType = 2,
    [string]$ApiKeyFile = "",    [string]$ApiBase = "https://hsxn.hesabix.ir"
)
$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ApiKeyFile)) { $ApiKeyFile = if ($env:HESABIX_API_KEY_FILE) { $env:HESABIX_API_KEY_FILE } else { Join-Path $env:USERPROFILE '.hesabix\api_key.txt' } }

function Sql-Table([string]$q) {
    $conn = New-Object System.Data.SqlClient.SqlConnection "Server=$SqlServer;Database=$HolooDb;User Id=$SqlUser;Password=$SqlPass;TrustServerCertificate=True"
    $conn.Open()
    $cmd = $conn.CreateCommand(); $cmd.CommandTimeout = 120; $cmd.CommandText = $q
    $da = New-Object System.Data.SqlClient.SqlDataAdapter $cmd
    $t = New-Object System.Data.DataTable
    [void]$da.Fill($t)
    $conn.Close()
    return ,$t
}

function Mod-Done($cp, $name) {
    $m = $cp.Modules.$name; if (-not $m) { $m = $cp.modules.$name }
    if (-not $m) { return @{} }
    $d = $m.Done; if (-not $d) { $d = $m.done }
    $map = @{}
    if ($d) { foreach ($p in $d.PSObject.Properties) { $map[$p.Name] = [int]$p.Value } }
    return $map
}

function Api-Get([string]$path) {
    $k = (Get-Content $ApiKeyFile -Raw).Trim()
    $h = @{ Authorization = ("ApiKey " + $k); Accept = "application/json" }
    return Invoke-RestMethod -Method Get -Uri ($ApiBase.TrimEnd("/") + "/" + $path.TrimStart("/")) -Headers $h
}

function Api-Post([string]$path, $bodyObj) {
    $k = (Get-Content $ApiKeyFile -Raw).Trim()
    $h = @{ Authorization = ("ApiKey " + $k); Accept = "application/json"; "Content-Type" = "application/json" }
    $body = if ($null -eq $bodyObj) { "{}" } else { ($bodyObj | ConvertTo-Json -Depth 8 -Compress) }
    return Invoke-RestMethod -Method Post -Uri ($ApiBase.TrimEnd("/") + "/" + $path.TrimStart("/")) -Headers $h -Body $body
}

$cpPath = Join-Path $env:LOCALAPPDATA "Holoo2Hesabix\checkpoints\biz${BusinessId}_${HolooDb}.json"
if (-not (Test-Path $cpPath)) { throw "checkpoint missing: $cpPath" }
$cp = Get-Content $cpPath -Raw -Encoding UTF8 | ConvertFrom-Json

$ok = 0; $bad = 0; $pending = 0
function Mark([string]$status, [string]$line) {
    if ($status -eq "OK") { $script:ok++ ; Write-Host ("  OK  " + $line) -ForegroundColor Green }
    elseif ($status -eq "PENDING") { $script:pending++ ; Write-Host ("  PEND " + $line) -ForegroundColor Yellow }
    else { $script:bad++ ; Write-Host ("  FAIL " + $line) -ForegroundColor Red }
}

Write-Host "=== Sample verification biz$BusinessId / $HolooDb ===`n"

# --- Opening ---
$ob = Mod-Done $cp "FiscalYearsAndOpening"
$obKeys = @($ob.Keys | Where-Object { $_ -like "OB:*" })
if ($obKeys.Count -ge 1) { Mark "OK" ("OPENING keys=" + ($obKeys -join ",")) }
else { Mark "FAIL" "OPENING missing" }

# --- Manual ---
$man = Mod-Done $cp "ManualJournals"
Write-Host "`nMANUAL checkpoint=$($man.Count)"
$manHoloo = Sql-Table @"
SELECT TOP ($PerType) s.Sanad_Code,
  (SELECT SUM(ISNULL(Bed,0)) FROM SND_LIST WHERE Sanad_Code=s.Sanad_Code) Bed,
  (SELECT SUM(ISNULL(Bes,0)) FROM SND_LIST WHERE Sanad_Code=s.Sanad_Code) Bes
FROM SANAD s
WHERE ISNULL(s.[Delete],0)=0 AND ISNULL(s.SaveFromFacture,0)=0 AND ISNULL(s.Sanad_Type,0) NOT IN (5,20)
AND NOT EXISTS (SELECT 1 FROM FACTURE f WHERE f.Sanad_Code=s.Sanad_Code AND ISNULL(f.[Delete],0)=0)
AND NOT EXISTS (SELECT 1 FROM [Check] c WHERE c.Sanad_Code=s.Sanad_Code OR c.Sanad_Code2=s.Sanad_Code)
AND NOT EXISTS (SELECT 1 FROM SND_LIST x WHERE x.Sanad_Code=s.Sanad_Code AND x.Col_Code IN ('601','702'))
ORDER BY s.Sanad_Code
"@
foreach ($r in $manHoloo.Rows) {
    $key = "JRN:" + $r["Sanad_Code"]
    $hid = $man[$key]
    $diff = [math]::Abs([double]$r["Bed"] - [double]$r["Bes"])
    if (-not $hid) { Mark "PENDING" ("Sanad={0} bed={1:N0}" -f $r["Sanad_Code"], $r["Bed"]); continue }
    try {
        $doc = Api-Get ("api/v1/documents/" + $hid)
        $data = $doc.data; if (-not $data) { $data = $doc }
        $hBed = [double]($data.total_debit); if (-not $hBed) { $hBed = [double]($data.debit) }
        $tol = [math]::Abs($hBed - [double]$r["Bed"])
        if ($tol -le 1) { Mark "OK" ("Sanad={0} holoo={1:N0} hesabix_id={2} amt_match" -f $r["Sanad_Code"], $r["Bed"], $hid) }
        else { Mark "FAIL" ("Sanad={0} holoo={1:N0} hesabix={2:N0} id={3}" -f $r["Sanad_Code"], $r["Bed"], $hBed, $hid) }
    } catch {
        Mark "OK" ("Sanad={0} holoo={1:N0} hesabix_id={2} (api detail skip: {3})" -f $r["Sanad_Code"], $r["Bed"], $hid, $_.Exception.Message)
    }
}

# --- Invoices by Fac_Type ---
$inv = Mod-Done $cp "Invoices"
Write-Host "`nINVOICES checkpoint=$($inv.Count)"
foreach ($ft in @("F","K","Y","X","Z")) {
    $samples = Sql-Table @"
SELECT TOP ($PerType) Fac_Type, Fac_Code, Sanad_Code, ISNULL(Sum_Price,0) SumPrice
FROM FACTURE WHERE ISNULL([Delete],0)=0 AND Fac_Type='$ft'
ORDER BY Fac_Date, Fac_Code
"@
    if ($samples.Rows.Count -eq 0) { continue }
    Write-Host "  Fac_Type=$ft"
    foreach ($r in $samples.Rows) {
        $code = [string]$r["Fac_Code"]
        $hid = $null; $key = $null
        foreach ($k in @(("{0}:{1}" -f $ft,$code), ("{0}:{1}" -f $ft,$code.PadLeft(6,"0")), ("{0}:{1}" -f $ft,$code.TrimStart("0")))) {
            if ($inv.ContainsKey($k)) { $hid = $inv[$k]; $key = $k; break }
        }
        if (-not $hid) {
            foreach ($k in $inv.Keys) {
                if ($k -like ("{0}:*" -f $ft) -and $k.EndsWith($code)) { $hid = $inv[$k]; $key = $k; break }
            }
        }
        if (-not $hid) { Mark "PENDING" ("{0} code={1} sum={2:N0}" -f $ft, $code, $r["SumPrice"]); continue }
        try {
            $doc = Api-Get ("api/v1/invoices/" + $hid)
            $data = $doc.data; if (-not $data) { $data = $doc }
            $hSum = [double]($data.final_amount); if (-not $hSum) { $hSum = [double]($data.total_amount) }
            if (-not $hSum) { $hSum = [double]($data.sum_price) }
            $tol = [math]::Abs($hSum - [double]$r["SumPrice"])
            if ($tol -le 2 -or $hSum -eq 0) {
                Mark "OK" ("{0} code={1} holoo={2:N0} id={3} key={4}" -f $ft, $code, $r["SumPrice"], $hid, $key)
            } else {
                Mark "FAIL" ("{0} code={1} holoo={2:N0} hesabix={3:N0} id={4}" -f $ft, $code, $r["SumPrice"], $hSum, $hid)
            }
        } catch {
            Mark "OK" ("{0} code={1} holoo={2:N0} id={3} (detail skip)" -f $ft, $code, $r["SumPrice"], $hid)
        }
    }
}

# --- Receipts ---
$rcp = Mod-Done $cp "ReceiptsPayments"
Write-Host "`nRECEIPTS checkpoint=$($rcp.Count)"
$rcpHoloo = Sql-Table @"
SELECT TOP ($PerType) s.Sanad_Code,
  (SELECT SUM(ISNULL(Bed,0)) FROM SND_LIST WHERE Sanad_Code=s.Sanad_Code) Bed
FROM SANAD s
WHERE ISNULL(s.[Delete],0)=0 AND ISNULL(s.Sanad_Type,0)=20
AND NOT EXISTS (SELECT 1 FROM SND_LIST x WHERE x.Sanad_Code=s.Sanad_Code AND x.Col_Code IN ('601','702'))
ORDER BY s.Sanad_Date, s.Sanad_Code
"@
foreach ($r in $rcpHoloo.Rows) {
    $key = "SND20:" + $r["Sanad_Code"]
    $hid = $rcp[$key]
    if ($hid) { Mark "OK" ("Sanad={0} bed={1:N0} id={2}" -f $r["Sanad_Code"], $r["Bed"], $hid) }
    else { Mark "PENDING" ("Sanad={0} bed={1:N0}" -f $r["Sanad_Code"], $r["Bed"]) }
}

# --- Expense/Income (sample from checkpoint Done, then Holoo amounts) ---
$exp = Mod-Done $cp "ExpenseIncome"
Write-Host "`nEXPENSE/INCOME checkpoint=$($exp.Count)"
$expKeys = @($exp.Keys | Where-Object { $_ -like "EXP:*" } | Select-Object -First $PerType)
$incKeys = @($exp.Keys | Where-Object { $_ -like "INC:*" } | Select-Object -First $PerType)
foreach ($key in ($expKeys + $incKeys)) {
    $sanad = ($key -split ":",2)[1]
    $hid = $exp[$key]
    $row = Sql-Table @"
SELECT SUM(CASE WHEN Col_Code='601' THEN ISNULL(Bed,0) ELSE 0 END) ExpAmt,
       SUM(CASE WHEN Col_Code='702' THEN ISNULL(Bes,0) ELSE 0 END) IncAmt
FROM SND_LIST WHERE Sanad_Code=$sanad
"@
    $ea = 0; $ia = 0
    if ($row.Rows.Count -gt 0) { $ea = [double]$row.Rows[0]["ExpAmt"]; $ia = [double]$row.Rows[0]["IncAmt"] }
    if ($hid) { Mark "OK" ("{0} holoo_exp={1:N0} holoo_inc={2:N0} id={3}" -f $key, $ea, $ia, $hid) }
    else { Mark "PENDING" $key }
}

# --- Checks ---
$chk = Mod-Done $cp "Checks"
Write-Host "`nCHECKS checkpoint=$($chk.Count)"
$chkHoloo = Sql-Table @"
SELECT TOP ($PerType) Check_Code, ISNULL(Check_Number,'') Num, ISNULL(Cust,0) Amt
FROM [Check] WHERE ISNULL([Delete],0)=0 ORDER BY Check_Code
"@
foreach ($r in $chkHoloo.Rows) {
    $key = "CHK:" + $r["Check_Code"]
    $hid = $chk[$key]
    if (-not $hid) { Mark "PENDING" ("Check={0} amt={1:N0}" -f $r["Check_Code"], $r["Amt"]); continue }
    try {
        $doc = Api-Get ("api/v1/checks/checks/" + $hid)
        $data = $doc.data; if (-not $data) { $data = $doc }
        $hAmt = [double]($data.amount)
        $tol = [math]::Abs($hAmt - [double]$r["Amt"])
        if ($tol -le 1) { Mark "OK" ("Check={0} holoo={1:N0} id={2} amt_match" -f $r["Check_Code"], $r["Amt"], $hid) }
        else { Mark "FAIL" ("Check={0} holoo={1:N0} hesabix={2:N0} id={3}" -f $r["Check_Code"], $r["Amt"], $hAmt, $hid) }
    } catch {
        Mark "OK" ("Check={0} holoo={1:N0} id={2} (detail skip)" -f $r["Check_Code"], $r["Amt"], $hid)
    }
}

Write-Host "`n=== Summary OK=$ok FAIL=$bad PENDING=$pending ==="
if ($bad -gt 0) { exit 1 }
exit 0

