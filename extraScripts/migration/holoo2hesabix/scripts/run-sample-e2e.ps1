# Run sample E2E: 2 docs per module (receipts/checks/expense/manual/invoices-by-type).
param(
    [int]$BusinessId = 6823,
    [int]$Sample = 2,
    [string]$ApiKeyFile = "",    [string]$Exe = "d:\hesabixArc\extraScripts\migration\holoo2hesabix\bin\DebugBuild\Holoo2Hesabix.exe"
)
$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ApiKeyFile)) { $ApiKeyFile = if ($env:HESABIX_API_KEY_FILE) { $env:HESABIX_API_KEY_FILE } else { Join-Path $env:USERPROFILE '.hesabix\api_key.txt' } }
if (-not (Test-Path $Exe)) { throw "exe missing: $Exe - build first" }
$apiKey = (Get-Content $ApiKeyFile -Raw).Trim()
$stdout = "d:\hesabixArc\.eyeban\e2e-sample-stdout.txt"
$stderr = "d:\hesabixArc\.eyeban\e2e-sample-stderr.txt"
$argList = @(
  "--e2e-opening","--docs-only","--with-all-docs",
  "--sample", "$Sample",
  "--business-id", "$BusinessId",
  "--sql-server","localhost","--sql-user","sa","--sql-pass",($(if ($env:HOLOO_SQL_PASS) { $env:HOLOO_SQL_PASS } else { "" })),"--sql-db","Holoo1",
  "--api-key",$apiKey,"--api-base","https://hsxn.hesabix.ir",
  "--out","d:\hesabixArc\.eyeban"
)
Write-Host "Sample E2E business=$BusinessId sample=$Sample"
$p = Start-Process -FilePath $Exe -ArgumentList $argList -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru -NoNewWindow -Wait
Write-Host "exit=$($p.ExitCode) stdout=$stdout"
Get-Content $stdout -Tail 40 -Encoding UTF8 -ErrorAction SilentlyContinue
$resultFile = "d:\hesabixArc\.eyeban\e2e-opening-result.json"
if (Test-Path $resultFile) {
  Write-Host ""
  Write-Host "=== result ==="
  Get-Content $resultFile -Raw -Encoding UTF8
}
exit $p.ExitCode

