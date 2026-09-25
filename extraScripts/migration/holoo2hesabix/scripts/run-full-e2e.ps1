# Resume FULL document transfer (no --sample) from existing checkpoint.
param(
    [int]$BusinessId = 6823,
    [string]$ApiKeyFile = "",    [string]$Exe = "d:\hesabixArc\extraScripts\migration\holoo2hesabix\bin\DebugBuild\Holoo2Hesabix.exe"
)
$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ApiKeyFile)) { $ApiKeyFile = if ($env:HESABIX_API_KEY_FILE) { $env:HESABIX_API_KEY_FILE } else { Join-Path $env:USERPROFILE '.hesabix\api_key.txt' } }
if (-not (Test-Path $Exe)) { throw "exe missing: $Exe - build first" }

# Clear Completed flags left by sample runs so remaining docs are processed
$cpPath = Join-Path $env:LOCALAPPDATA "Holoo2Hesabix\checkpoints\biz${BusinessId}_Holoo1.json"
if (Test-Path $cpPath) {
  $cp = Get-Content $cpPath -Raw -Encoding UTF8 | ConvertFrom-Json
  foreach ($name in @("Invoices","ReceiptsPayments","Checks","ExpenseIncome","ManualJournals","WarehouseDocs")) {
    $m = $cp.Modules.$name
    if ($m) { $m.Completed = $false }
  }
  [IO.File]::WriteAllText($cpPath, ($cp | ConvertTo-Json -Depth 30), [Text.UTF8Encoding]::new($false))
  Write-Host "cleared Completed flags on doc modules"
}

$apiKey = (Get-Content $ApiKeyFile -Raw).Trim()
$stdout = "d:\hesabixArc\.eyeban\e2e-full-stdout.txt"
$stderr = "d:\hesabixArc\.eyeban\e2e-full-stderr.txt"
$argList = @(
  "--e2e-opening","--docs-only","--with-all-docs",
  "--business-id", "$BusinessId",
  "--sql-server","localhost","--sql-user","sa","--sql-pass",($(if ($env:HOLOO_SQL_PASS) { $env:HOLOO_SQL_PASS } else { "" })),"--sql-db","Holoo1",
  "--api-key",$apiKey,"--api-base","https://hsxn.hesabix.ir",
  "--out","d:\hesabixArc\.eyeban"
)
Write-Host "FULL E2E business=$BusinessId (no sample limit)"
$p = Start-Process -FilePath $Exe -ArgumentList $argList -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru -WindowStyle Hidden
Set-Content "d:\hesabixArc\.eyeban\e2e-full-pid.txt" $p.Id
Write-Host "pid=$($p.Id) stdout=$stdout"

