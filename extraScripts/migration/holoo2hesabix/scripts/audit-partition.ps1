# فاز ۰ — سنجش baseline پارتیشن اسناد و نگاشت سرفصل روی دیتابیس هلو
# Usage: .\scripts\audit-partition.ps1 [-Server localhost] [-Database Holoo1] [-User sa] [-Password ...]

param(
    [string]$Server = "localhost",
    [string]$Database = "Holoo1",
    [string]$User = "sa",
    [string]$Password = $(if ($env:HOLOO_SQL_PASS) { $env:HOLOO_SQL_PASS } else { "" })
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$connStr = "Server=$Server;Database=$Database;User Id=$User;Password=$Password;TrustServerCertificate=True"
$conn = New-Object System.Data.SqlClient.SqlConnection $connStr
$conn.Open()
$cmd = $conn.CreateCommand()
$cmd.CommandTimeout = 180

function Invoke-Scalar([string]$sql) {
    $cmd.CommandText = $sql
    return $cmd.ExecuteScalar()
}

function Invoke-Table([string]$sql) {
    $cmd.CommandText = $sql
    $rd = $cmd.ExecuteReader()
    $t = New-Object System.Data.DataTable
    $t.Load($rd)
    $rd.Close()
    return $t
}

Write-Output "=== Holoo partition audit: $Database @ $Server ==="
Write-Output ("Total SANAD active: " + (Invoke-Scalar "SELECT COUNT(*) FROM SANAD WHERE ISNULL([Delete],0)=0"))
Write-Output ("FACTURE F/K/Y/X/Z: " + (Invoke-Scalar "SELECT COUNT(*) FROM FACTURE WHERE ISNULL([Delete],0)=0 AND Fac_Type IN ('F','K','Y','X','Z')"))

$buckets = Invoke-Table @"
SELECT bucket, COUNT(*) cnt FROM (
  SELECT CASE
    WHEN s.Sanad_Code = 1 THEN 'OPENING'
    WHEN NOT EXISTS (SELECT 1 FROM SND_LIST l WHERE l.Sanad_Code=s.Sanad_Code AND (ISNULL(l.Bed,0)>0 OR ISNULL(l.Bes,0)>0))
      OR EXISTS(SELECT 1 FROM SND_LIST x WHERE x.Sanad_Code=s.Sanad_Code AND x.Col_Code IN ('005','006')
           AND NOT EXISTS (SELECT 1 FROM SND_LIST y WHERE y.Sanad_Code=s.Sanad_Code AND y.Col_Code NOT IN ('005','006') AND (ISNULL(y.Bed,0)>0 OR ISNULL(y.Bes,0)>0)))
      THEN 'SKIP_CONTROL'
    WHEN ISNULL(s.Sanad_Type,0) = 5
      OR EXISTS(SELECT 1 FROM [Check] c WHERE c.Sanad_Code=s.Sanad_Code OR c.Sanad_Code2=s.Sanad_Code)
      THEN 'CHECK_GL_SKIP'
    WHEN EXISTS(SELECT 1 FROM FACTURE f WHERE f.Sanad_Code=s.Sanad_Code AND ISNULL(f.[Delete],0)=0)
      OR (ISNULL(s.SaveFromFacture,0)=1 AND ISNULL(s.Sanad_Type,0) IN (0,13,14))
      THEN 'INVOICE_GL_SKIP'
    WHEN EXISTS(SELECT 1 FROM SND_LIST x WHERE x.Sanad_Code=s.Sanad_Code AND x.Col_Code IN ('601','702'))
      THEN 'EXPENSE_INCOME'
    WHEN ISNULL(s.Sanad_Type,0)=20 THEN 'RECEIPT_PAYMENT'
    WHEN ISNULL(s.SaveFromFacture,0)=0
      AND ISNULL(s.Sanad_Type,0) NOT IN (5,20)
      AND NOT EXISTS(SELECT 1 FROM FACTURE f WHERE f.Sanad_Code=s.Sanad_Code AND ISNULL(f.[Delete],0)=0)
      AND NOT EXISTS(SELECT 1 FROM [Check] c WHERE c.Sanad_Code=s.Sanad_Code OR c.Sanad_Code2=s.Sanad_Code)
      AND NOT EXISTS(SELECT 1 FROM SND_LIST x WHERE x.Sanad_Code=s.Sanad_Code AND x.Col_Code IN ('601','702'))
      THEN 'MANUAL'
    ELSE 'UNCLASSIFIED'
  END AS bucket
  FROM SANAD s WHERE ISNULL(s.[Delete],0)=0
) t GROUP BY bucket ORDER BY cnt DESC
"@
Write-Output "`n=== Buckets ==="
$buckets | Format-Table -AutoSize | Out-String -Width 80

$manual = Invoke-Scalar @"
SELECT COUNT(*) FROM SANAD s WHERE ISNULL(s.[Delete],0)=0 AND ISNULL(s.SaveFromFacture,0)=0
AND ISNULL(s.Sanad_Type,0) NOT IN (5,20)
AND NOT EXISTS (SELECT 1 FROM FACTURE f WHERE f.Sanad_Code=s.Sanad_Code AND ISNULL(f.[Delete],0)=0)
AND NOT EXISTS (SELECT 1 FROM [Check] c WHERE c.Sanad_Code=s.Sanad_Code OR c.Sanad_Code2=s.Sanad_Code)
AND NOT EXISTS (SELECT 1 FROM SND_LIST x WHERE x.Sanad_Code=s.Sanad_Code AND x.Col_Code IN ('601','702'))
"@
$overlap = Invoke-Scalar @"
SELECT COUNT(*) FROM SANAD s WHERE ISNULL(s.[Delete],0)=0 AND ISNULL(s.SaveFromFacture,0)=0
AND ISNULL(s.Sanad_Type,0) NOT IN (5,20)
AND EXISTS (SELECT 1 FROM FACTURE f WHERE f.Sanad_Code=s.Sanad_Code AND ISNULL(f.[Delete],0)=0)
AND NOT EXISTS (SELECT 1 FROM SND_LIST x WHERE x.Sanad_Code=s.Sanad_Code AND x.Col_Code IN ('601','702'))
"@
Write-Output "Manual candidates (post-partition): $manual"
Write-Output "Facture-linked excluded from manual: $overlap"
Write-Output ("Gate: overlap must be reported; manual must NOT include facture-linked. OK if overlap>0 and manual excludes them.")

Write-Output "`n=== MapCol coverage (Col with amount) ==="
$mapCols = @('001','002','101','102','103','104','106','107','205','207','401','402','403','404','501','502','503','506','601','702','801','802','803','901','902','903','904','905')
$usage = Invoke-Table @"
SELECT LTRIM(RTRIM(l.Col_Code)) Col, COUNT(*) Lines
FROM SND_LIST l
INNER JOIN SANAD s ON s.Sanad_Code=l.Sanad_Code AND ISNULL(s.[Delete],0)=0
WHERE ISNULL(l.Bed,0)>0 OR ISNULL(l.Bes,0)>0
GROUP BY LTRIM(RTRIM(l.Col_Code))
ORDER BY 1
"@
foreach ($row in $usage.Rows) {
    $c = [string]$row["Col"]
    $lines = $row["Lines"]
    $status = if ($mapCols -contains $c -or $c -eq '005' -or $c -eq '006') { 'MAPPED/SKIP' } else { 'UNMAPPED' }
    Write-Output ("  Col $c lines=$lines $status")
}

$conn.Close()
Write-Output "`nDone."
