# Holoo-side trial balance by Col for one fiscal year (proof baseline)
param(
    [string]$Server = "localhost",
    [string]$Database = "Holoo1",
    [string]$User = "sa",
    [string]$Password = $(if ($env:HOLOO_SQL_PASS) { $env:HOLOO_SQL_PASS } else { "" }),
    [string]$StartDate = "2023-03-21",
    [string]$EndDate = "2024-03-20"
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$conn = New-Object System.Data.SqlClient.SqlConnection "Server=$Server;Database=$Database;User Id=$User;Password=$Password;TrustServerCertificate=True"
$conn.Open()
$cmd = $conn.CreateCommand()
$cmd.CommandTimeout = 300
$cmd.CommandText = @"
SELECT LTRIM(RTRIM(l.Col_Code)) AS ColCode,
  SUM(ISNULL(l.Bed,0)) AS Debit,
  SUM(ISNULL(l.Bes,0)) AS Credit
FROM SND_LIST l
INNER JOIN SANAD s ON s.Sanad_Code=l.Sanad_Code AND ISNULL(s.[Delete],0)=0
WHERE s.Sanad_Date >= @s AND s.Sanad_Date < DATEADD(day,1,@e)
  AND LTRIM(RTRIM(l.Col_Code)) NOT IN ('005','006')
GROUP BY LTRIM(RTRIM(l.Col_Code))
ORDER BY 1
"@
$cmd.Parameters.AddWithValue("@s", [datetime]::Parse($StartDate)) | Out-Null
$cmd.Parameters.AddWithValue("@e", [datetime]::Parse($EndDate)) | Out-Null
$rd = $cmd.ExecuteReader()
$sumD = 0.0; $sumC = 0.0
Write-Output "Col`tDebit`tCredit`tNet"
while ($rd.Read()) {
    $col = $rd.GetValue(0).ToString().Trim()
    $d = [double]$rd.GetValue(1)
    $c = [double]$rd.GetValue(2)
    $sumD += $d; $sumC += $c
    Write-Output ("{0}`t{1:N0}`t{2:N0}`t{3:N0}" -f $col, $d, $c, ($d-$c))
}
$rd.Close()
Write-Output ("TOTAL`t{0:N0}`t{1:N0}`t{2:N0}" -f $sumD, $sumC, ($sumD-$sumC))
Write-Output "Note: exclude 005/006. Invoice GL and checks are included; Hesabix proof must use same buckets."
$conn.Close()
