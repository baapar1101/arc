# List Holoo sanads in manual partition that are unbalanced / thin (would be Failed with SkipReason).
param(
    [string]$HolooDb = "Holoo1",
    [string]$SqlServer = "localhost",
    [string]$SqlUser = "sa",
    [string]$SqlPass = $(if ($env:HOLOO_SQL_PASS) { $env:HOLOO_SQL_PASS } else { "" })
)
$ErrorActionPreference = "Stop"
$conn = New-Object System.Data.SqlClient.SqlConnection "Server=$SqlServer;Database=$HolooDb;User Id=$SqlUser;Password=$SqlPass;TrustServerCertificate=True"
$conn.Open()
$sql = @"
SELECT s.Sanad_Code,
  (SELECT COUNT(*) FROM SND_LIST l WHERE l.Sanad_Code=s.Sanad_Code AND (ISNULL(l.Bed,0)>0 OR ISNULL(l.Bes,0)>0)) Lines,
  (SELECT SUM(ISNULL(Bed,0)) FROM SND_LIST WHERE Sanad_Code=s.Sanad_Code) Bed,
  (SELECT SUM(ISNULL(Bes,0)) FROM SND_LIST WHERE Sanad_Code=s.Sanad_Code) Bes
FROM SANAD s
WHERE ISNULL(s.[Delete],0)=0 AND ISNULL(s.SaveFromFacture,0)=0
AND ISNULL(s.Sanad_Type,0) NOT IN (5,20)
AND NOT EXISTS (SELECT 1 FROM FACTURE f WHERE f.Sanad_Code=s.Sanad_Code AND ISNULL(f.[Delete],0)=0)
AND NOT EXISTS (SELECT 1 FROM [Check] c WHERE c.Sanad_Code=s.Sanad_Code OR c.Sanad_Code2=s.Sanad_Code)
AND NOT EXISTS (SELECT 1 FROM SND_LIST x WHERE x.Sanad_Code=s.Sanad_Code AND x.Col_Code IN ('601','702'))
ORDER BY s.Sanad_Code
"@
$cmd=$conn.CreateCommand(); $cmd.CommandTimeout=120; $cmd.CommandText=$sql
$da=New-Object System.Data.SqlClient.SqlDataAdapter $cmd; $t=New-Object System.Data.DataTable; [void]$da.Fill($t)
$conn.Close()
$bad=0; $ok=0
foreach($r in $t.Rows){
  $lines = if ($r["Lines"] -is [DBNull] -or $null -eq $r["Lines"]) { 0 } else { [int]$r["Lines"] }
  $bed = if ($r["Bed"] -is [DBNull] -or $null -eq $r["Bed"]) { 0.0 } else { [double]$r["Bed"] }
  $bes = if ($r["Bes"] -is [DBNull] -or $null -eq $r["Bes"]) { 0.0 } else { [double]$r["Bes"] }
  $diff=[math]::Abs($bed-$bes)
  if($lines -lt 2 -or $diff -gt 1){
    Write-Host ("SKIP Sanad={0} lines={1} bed={2:N0} bes={3:N0} diff={4:N2}" -f $r["Sanad_Code"],$lines,$bed,$bes,$diff)
    $bad++
  } else { $ok++ }
}
Write-Host "`nManual partition: transferable=$ok must-fail-explicit=$bad total=$($t.Rows.Count)"
if($bad -eq 0){ Write-Host "No silent-skip candidates in base manual partition." -ForegroundColor Green }
exit 0
