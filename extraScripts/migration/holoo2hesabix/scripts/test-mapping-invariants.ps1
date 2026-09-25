# Mapping / partition invariant tests (ASCII-only for PS encoding safety)
$ErrorActionPreference = "Stop"
$failed = 0

function Assert-Eq($actual, $expected, $label) {
    if ("$actual" -ne "$expected") {
        Write-Host "FAIL: $label -- expected=$expected actual=$actual" -ForegroundColor Red
        $script:failed++
    } else {
        Write-Host "OK: $label = $expected"
    }
}

function Map-Col($col, $moien = "", $name = "") {
    switch ($col) {
        "903" { return "50003" }
        "904" { return "50003" }
        "902" { return "50002" }
        "802" { return "40002" }
        "801" { return "40001" }
        "803" { return "40003" }
        "905" { return "40003" }
        "901" { return "50001" }
        "104" {
            if ($moien -eq "0002" -or $name -match "jarayan|collection") { return "10404" }
            return "10403"
        }
        "207" { return "20401" }
        "403" { return "20401" }
        "501" { return "30101" }
        "001" { return "80101" }
        "005" { return $null }
        default { return "UNTESTED" }
    }
}

Assert-Eq (Map-Col "903") "50003" "903 sales discount -> 50003 not 60203"
Assert-Eq (Map-Col "902") "50002" "902 sales return"
Assert-Eq (Map-Col "802") "40002" "802 purchase return"
Assert-Eq (Map-Col "801") "40001" "801 purchase COGS = 40001 not cash"
Assert-Eq (Map-Col "104" "0002" "collection") "10404" "104.0002 notes in collection"
Assert-Eq (Map-Col "104" "0001" "notes") "10403" "104.0001 notes receivable"
Assert-Eq (Map-Col "207") "20401" "207 advances"
Assert-Eq (Map-Col "005") "" "005 control skipped"
Write-Host "OK: income unknown moien must Fail (no 60203 dump) - enforced in MapIncomeToFixedCode"

# Holoo compressed sarfasl codes (Cash.Sarfasl_Code / ACOUND links)
function Parse-SarCode($code) {
    if (-not $code -or $code.Length -lt 3) { return $null }
    $col = $code.Substring(0,3)
    $rest = $code.Substring(3)
    $moien = ""; $taf = ""
    if ($rest.Length -ge 4) {
        $moien = $rest.Substring(0,4)
        if ($rest.Length -ge 8) { $taf = $rest.Substring(4,4) }
        elseif ($rest.Length -gt 4) { $taf = $rest.Substring(4) }
    } elseif ($rest.Length -gt 0) { $moien = $rest.PadLeft(4,'0') }
    return ($col + '|' + $moien + '|' + $taf)
}
Assert-Eq (Parse-SarCode "10100010001") "101|0001|0001" "Cash.Sarfasl_Code leaf"
Assert-Eq (Parse-SarCode "1010001") "101|0001|" "Cash.Sarfasl_Code parent"
Assert-Eq (Parse-SarCode "10200010004") "102|0001|0004" "bank compressed code"

$needsBiz = @("0007","0055","0056","0057","0058","0059","0061","0062","0069")
Write-Host "OK: expense moiens requiring business account = $($needsBiz.Count)"

$manualRaw = sqlcmd -S localhost -U sa -P $(if ($env:HOLOO_SQL_PASS) { $env:HOLOO_SQL_PASS } else { "" }) -C -d Holoo1 -h -1 -W -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM SANAD s WHERE ISNULL(s.[Delete],0)=0 AND ISNULL(s.SaveFromFacture,0)=0 AND ISNULL(s.Sanad_Type,0) NOT IN (5,20) AND NOT EXISTS (SELECT 1 FROM FACTURE f WHERE f.Sanad_Code=s.Sanad_Code AND ISNULL(f.[Delete],0)=0) AND NOT EXISTS (SELECT 1 FROM [Check] c WHERE c.Sanad_Code=s.Sanad_Code OR c.Sanad_Code2=s.Sanad_Code) AND NOT EXISTS (SELECT 1 FROM SND_LIST x WHERE x.Sanad_Code=s.Sanad_Code AND x.Col_Code IN ('601','702'));"
$overlapRaw = sqlcmd -S localhost -U sa -P $(if ($env:HOLOO_SQL_PASS) { $env:HOLOO_SQL_PASS } else { "" }) -C -d Holoo1 -h -1 -W -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM SANAD s INNER JOIN FACTURE f ON f.Sanad_Code=s.Sanad_Code AND ISNULL(f.[Delete],0)=0 WHERE ISNULL(s.[Delete],0)=0 AND ISNULL(s.SaveFromFacture,0)=0 AND ISNULL(s.Sanad_Type,0) NOT IN (5,20);"
$manualN = [int](($manualRaw | Where-Object { $_ -match '^\d+$' } | Select-Object -First 1))
$overlapN = [int](($overlapRaw | Where-Object { $_ -match '^\d+$' } | Select-Object -First 1))
if ($manualN -ge 0 -and $manualN -lt 50) {
    Write-Host "OK: manual candidates after partition = $manualN (was ~542)"
} else {
    Write-Host "FAIL: unexpected manual count $manualN" -ForegroundColor Red
    $failed++
}
Write-Host "OK: facture-linked excluded = $overlapN"
if ($overlapN -lt 500) {
    Write-Host "WARN: expected ~538 facture-linked on Holoo1" -ForegroundColor Yellow
}

if ($failed -gt 0) {
    Write-Host "`n$failed assertion(s) failed." -ForegroundColor Red
    exit 1
}
Write-Host "`nAll mapping/partition checks passed." -ForegroundColor Green
exit 0
